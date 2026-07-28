#!/usr/bin/env bash
# Role-dispatch entrypoint for the d2-bnftp-poller Argo Workflow.
#
# Usage: entrypoint.sh <clone|fetch|collect>
#
# The CronWorkflow runs a clone -> fetch(x3) -> collect DAG; Argo's DAG
# dependencies handle ordering. All three roles share a RWX PVC mounted at /work:
#   clone   - fresh clone of the archive repo into /work/repo (needs GIT_TOKEN)
#   fetch   - the Zig poller fetches this shard's (file,source) pairs into
#             /work/stage/<source>/<filename> (SHARD_INDEX/SHARD_TOTAL). The three
#             fetch pods land on distinct nodes (podAntiAffinity) -> distinct IPs.
#   collect - compare + placement + commit + push (needs GIT_TOKEN).
#
# Discord: instead of streaming every line, roles post only meaningful events via
# discord() - a committed change (diff + commit link), new/resolved cross-realm
# divergences, a probe hit (a speculative filename Blizzard actually serves),
# errors/anomalies, and a heartbeat on no-change runs. Everything still goes to
# the pod log (stdout) for debugging.
set -uo pipefail

WORK=/work
REPO="$WORK/repo"
STAGE="$WORK/stage"
TOTAL="${SHARD_TOTAL:-3}"
REPO_URL="github.com/jaenster/d2-bnftp-archive.git"
GH_REPO="jaenster/d2-bnftp-archive"
FETCH_LIST_PATH="$REPO/fetch-list"
D2_SOURCES="useast uswest asia europe vegas"
FT_TMP="$WORK/.filetimes"

ROLE="${1:-}"

log() { echo "[$ROLE] $*"; }

json_str() {
  # Emit a JSON string literal (quotes included) for arbitrary text.
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"; s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

discord_post() {
  # POST one <=2000-char message as plain markdown (so links stay clickable),
  # honoring HTTP 429 retry_after.
  local content="$1"
  [ -z "$content" ] && return 0
  local payload attempt=0 resp code retry body
  payload="$(printf '{"username":"d2-bnftp-poller","content":%s}' "$(json_str "$content")")"
  while [ "$attempt" -lt 5 ]; do
    resp="$(curl -sS -w $'\n%{http_code}' -H 'Content-Type: application/json' \
      -X POST -d "$payload" "$DISCORD_WEBHOOK_URL" 2>/dev/null)"
    code="${resp##*$'\n'}"
    if [ "$code" = "429" ]; then
      body="${resp%$'\n'*}"
      retry="$(printf '%s' "$body" | grep -o '"retry_after"[: ]*[0-9.]*' | grep -o '[0-9.]*' | head -1)"
      [ -z "$retry" ] && retry=1
      sleep "$retry"; attempt=$((attempt + 1)); continue
    fi
    return 0
  done
}

discord() {
  # Log a discrete event: always to the pod log, and to Discord (chunked to
  # ~1900 chars on line boundaries) when DISCORD_WEBHOOK_URL is set.
  local msg="$1"
  printf '%s\n' "$msg"
  [ -n "${DISCORD_WEBHOOK_URL:-}" ] || return 0
  local chunk="" line
  while IFS= read -r line; do
    if [ -n "$chunk" ] && [ $(( ${#chunk} + ${#line} + 1 )) -ge 1900 ]; then
      discord_post "$chunk"; chunk=""
    fi
    if [ -z "$chunk" ]; then chunk="$line"; else chunk="$chunk"$'\n'"$line"; fi
  done <<< "$msg"
  [ -n "$chunk" ] && discord_post "$chunk"
}

record_ft() {
  # Append "archive-path <TAB> ISO-date" for a placed file, reading Blizzard's
  # last-write time from the staged <path>.ft sidecar. $1 = staged file path,
  # $2 = archive path. Windows FILETIME is 100ns ticks since 1601-01-01.
  local ftfile="$1.ft" ft unix iso
  [ -s "$ftfile" ] || return 0
  ft="$(cat "$ftfile" 2>/dev/null)"
  case "$ft" in ''|0|*[!0-9]*) return 0 ;; esac
  unix=$(( ft / 10000000 - 11644473600 ))
  iso="$(date -u -d "@$unix" +%FT%TZ 2>/dev/null)" || iso="ft:$ft"
  printf '%s\t%s\n' "$2" "$iso" >> "$FT_TMP"
}

role_clone() {
  log "clone: fresh clone of the archive repo"
  if [ -z "${GIT_TOKEN:-}" ]; then
    discord "ERROR: clone role has no GIT_TOKEN"; return 2
  fi
  rm -rf "$REPO" "$STAGE"
  if ! git clone "https://x-access-token:${GIT_TOKEN}@${REPO_URL}" "$REPO"; then
    discord "ERROR: clone of $GH_REPO failed"; return 1
  fi
  git -C "$REPO" config user.email "d2-bnftp-poller@users.noreply.github.com"
  git -C "$REPO" config user.name "d2-bnftp-poller"
  mkdir -p "$STAGE"
  log "clone: done"
  return 0
}

role_fetch() {
  local idx="${SHARD_INDEX:-0}"
  log "fetch: shard $idx/$TOTAL into stage"
  mkdir -p "$STAGE"
  FETCH_LIST="$FETCH_LIST_PATH" \
  STAGE_DIR="$STAGE" \
  SHARD_INDEX="$idx" \
  SHARD_TOTAL="$TOTAL" \
    d2-bnftp-poller
  local rc=$?
  log "fetch: shard $idx exited rc=$rc"
  if [ "$rc" -ne 0 ]; then
    discord "ERROR: fetch shard $idx/$TOTAL staged nothing (IP blocked / DNS / gateway down?)"
  fi
  return "$rc"
}

role_collect() {
  log "collect: compare + place over stage"
  if [ -z "${GIT_TOKEN:-}" ]; then
    discord "ERROR: collect role has no GIT_TOKEN"; return 2
  fi
  cd "$REPO"
  mkdir -p files
  : > "$FT_TMP"

  # Pre-run divergence set: basenames currently under the 5 d2 per-source dirs.
  ( cd files && find $D2_SOURCES -type f 2>/dev/null | sed 's|.*/||' | LC_ALL=C sort -u ) > "$WORK/.old_div" 2>/dev/null || : > "$WORK/.old_div"

  local probe_hits=""

  # Placement over the staged bytes. Two-field read so a filename with spaces
  # ("Diablo II.pdb") lands whole in $filename.
  while read -r class filename; do
    case "$class" in
      ""|\#*) continue ;;
    esac
    [ -z "${filename:-}" ] && continue

    if [ "$class" = "forever" ]; then
      local src="$STAGE/forever/$filename"
      if [ -s "$src" ]; then
        mkdir -p "files/forever"
        cp "$src" "files/forever/$filename"
        record_ft "$src" "files/forever/$filename"
      else
        log "WARN forever/$filename missing from stage"
      fi
      continue
    fi

    case "$class" in
      d2|probe|star|bw|war2|war3|w3xp) ;;
      *) log "WARN unknown class $class for $filename"; continue ;;
    esac

    # d2 and probe share this path: gather the gateways that produced bytes and
    # decide identical vs divergent. (A probe hit on even one gateway is a find;
    # they only need to leak a file on a single realm.)
    local present="" first_sum="" identical=1 have=0
    for s in $D2_SOURCES; do
      local sp="$STAGE/$s/$filename"
      if [ -s "$sp" ]; then
        present="$present $s"
        have=$((have + 1))
        local sum
        sum="$(sha256sum "$sp" | awk '{print $1}')"
        if [ -z "$first_sum" ]; then
          first_sum="$sum"
        elif [ "$sum" != "$first_sum" ]; then
          identical=0
        fi
      fi
    done

    if [ "$have" -eq 0 ]; then
      # A probe miss is the expected case - stay silent; a d2 file served by nobody
      # is worth a warning.
      [ "$class" = "d2" ] && log "WARN d2/$filename: no source produced bytes"
      continue
    fi

    if [ "$identical" -eq 1 ] && [ "$have" -eq 5 ]; then
      # All five sources agree -> canonical. Drop any stale per-source copies.
      set -- $present
      cp "$STAGE/$1/$filename" "files/$filename"
      record_ft "$STAGE/$1/$filename" "files/$filename"
      for s in $D2_SOURCES; do
        rm -f "files/$s/$filename"
      done
    else
      # Divergence (or a source missing bytes) -> per-source copies for every
      # source that produced bytes; drop the canonical copy.
      log "DIVERGENCE $class/$filename (present:$present identical=$identical have=$have)"
      rm -f "files/$filename"
      for s in $D2_SOURCES; do
        local sp="$STAGE/$s/$filename"
        if [ -s "$sp" ]; then
          mkdir -p "files/$s"
          cp "$sp" "files/$s/$filename"
          record_ft "$sp" "files/$s/$filename"
        fi
      done
    fi

    if [ "$class" = "probe" ]; then
      probe_hits="$probe_hits $filename"
      log "PROBE HIT $filename (present:$present)"
    fi
  done < "$FETCH_LIST_PATH"

  # Drop now-empty per-source dirs so the tree stays clean.
  for s in $D2_SOURCES forever; do
    [ -d "files/$s" ] && rmdir "files/$s" 2>/dev/null
  done
  true

  log "regenerating SHA256SUMS (recursive over files/)"
  if [ -d files ] && [ -n "$(find files -type f -print -quit)" ]; then
    ( cd files && find . -type f | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do sha256sum "$f"; done ) > SHA256SUMS
  else
    : > SHA256SUMS
  fi

  # Blizzard's reported last-write time per archived file (git drops on-disk
  # mtimes, so it lives in a committed manifest). Changes only when a file does.
  if [ -s "$FT_TMP" ]; then LC_ALL=C sort "$FT_TMP" > FILETIMES.txt; else : > FILETIMES.txt; fi

  # Post-run divergence set + per-gateway liveness.
  ( cd files && find $D2_SOURCES -type f 2>/dev/null | sed 's|.*/||' | LC_ALL=C sort -u ) > "$WORK/.new_div" 2>/dev/null || : > "$WORK/.new_div"
  local down=""
  for s in $D2_SOURCES; do
    local cnt
    cnt=$(find "$STAGE/$s" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "${cnt:-0}" -eq 0 ] && down="$down $s"
  done

  local nfiles ndiv
  nfiles=$(find files -type f 2>/dev/null | wc -l | tr -d ' ')
  ndiv=$(wc -l < "$WORK/.new_div" | tr -d ' ')

  # Anomaly lines shared by the change/no-change/push-fail messages.
  local anomalies=""
  [ -n "$down" ] && anomalies="${anomalies}WARNING: gateway served nothing:$down"$'\n'
  [ -n "$probe_hits" ] && anomalies="${anomalies}NEW FILE SERVED (probe hit):$probe_hits"$'\n'

  git add -A
  local namestatus
  namestatus="$(git diff --cached --name-status)"

  if [ -z "$namestatus" ]; then
    local hb="poller ran: no changes ($nfiles files, $ndiv divergent across realms)"
    [ -n "$anomalies" ] && hb="$hb"$'\n'"$anomalies"
    discord "$hb"
    return 0
  fi

  git commit -q -m "refetch: update changed BNFTP files ($(date -u +%F))"
  if ! git push -q; then
    discord "ERROR: git push to $GH_REPO failed (commit $(git rev-parse --short HEAD) is local only)"$'\n'"$anomalies"
    return 1
  fi

  local hash a m d newdiv resdiv changed
  hash="$(git rev-parse --short HEAD)"
  a=$(printf '%s\n' "$namestatus" | grep -c '^A')
  m=$(printf '%s\n' "$namestatus" | grep -c '^M')
  d=$(printf '%s\n' "$namestatus" | grep -c '^D')
  newdiv="$(comm -13 "$WORK/.old_div" "$WORK/.new_div" | tr '\n' ' ')"
  resdiv="$(comm -23 "$WORK/.old_div" "$WORK/.new_div" | tr '\n' ' ')"
  changed="$(printf '%s\n' "$namestatus" | sed 's/\t/ /g' | head -25)"

  local msg="**$GH_REPO updated** ([\`$hash\`](https://github.com/$GH_REPO/commit/$hash))"
  msg="$msg"$'\n'"+$a new  ~$m changed  -$d removed"
  [ -n "${newdiv// }" ] && msg="$msg"$'\n'"new divergence across realms: $newdiv"
  [ -n "${resdiv// }" ] && msg="$msg"$'\n'"divergence resolved: $resdiv"
  [ -n "$anomalies" ] && msg="$msg"$'\n'"$anomalies"
  msg="$msg"$'\n'"files:"$'\n'"$changed"
  discord "$msg"
  return 0
}

dispatch() {
  case "$ROLE" in
    clone)   role_clone ;;
    fetch)   role_fetch ;;
    collect) role_collect ;;
    *)
      log "usage: entrypoint.sh <clone|fetch|collect>"
      return 2
      ;;
  esac
}

dispatch
exit $?
