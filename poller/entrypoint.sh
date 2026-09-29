#!/usr/bin/env bash
# Role-dispatch entrypoint for the d2-bnftp-poller Argo Workflow.
#
# Usage: entrypoint.sh <prepare|fetch|collect>
#
# The CronWorkflow runs a prepare -> fetch(x3) -> collect DAG; Argo's DAG
# dependencies handle ordering. The pods share no volume: each has its own /work,
# and the bytes the shards fetched travel through an S3 prefix, WORK_S3/RUN_ID/.
#   prepare - empties WORK_S3 (earlier runs' leftovers) and pins the revision of
#             the archive repo the run works from: its sha is the output every
#             later role gets as REPO_SHA, so all shards read one fetch-list.
#   fetch   - the Zig poller fetches this shard's (file,source) pairs into
#             /work/stage/<source>/<filename> (SHARD_INDEX/SHARD_TOTAL), then
#             uploads them to WORK_S3/RUN_ID/stage and checks the upload. The three
#             fetch pods land on distinct nodes (podAntiAffinity) -> distinct IPs.
#   collect - downloads every shard's stage, then compare + placement + commit +
#             push (needs GIT_TOKEN).
# S3 is reached with rclone, configured from RCLONE_CONFIG_* variables.
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
FETCH_LIST_PATH="$WORK/fetch-list"
RAW_URL="https://raw.githubusercontent.com/$GH_REPO"
RUN_S3="${WORK_S3:-}/${RUN_ID:-}"
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

role_prepare() {
  log "prepare: clearing $WORK_S3 and pinning the archive repo's revision"
  if [ -z "${WORK_S3:-}" ]; then
    discord "ERROR: prepare role has no WORK_S3"; return 2
  fi
  # Nothing to purge on a first run; a purge that fails for any other reason
  # shows up as the fetch upload failing next.
  rclone purge "$WORK_S3" >/dev/null 2>&1 || true
  local sha
  sha="$(git ls-remote "https://${REPO_URL}" refs/heads/main | cut -f1)"
  case "$sha" in
    ????????????????????????????????????????) ;;
    *) discord "ERROR: cannot read the head of $GH_REPO"; return 1 ;;
  esac
  printf '%s' "$sha" > /tmp/sha
  log "prepare: pinned $sha"
  return 0
}

fetch_list() {
  # The fetch-list of the pinned revision (the repo is public).
  mkdir -p "$WORK"
  if ! curl -fsS "$RAW_URL/$REPO_SHA/fetch-list" -o "$FETCH_LIST_PATH"; then
    discord "ERROR: cannot read fetch-list at ${REPO_SHA:-?} of $GH_REPO"; return 1
  fi
}

role_fetch() {
  local idx="${SHARD_INDEX:-0}"
  log "fetch: shard $idx/$TOTAL into stage"
  mkdir -p "$STAGE"
  fetch_list || return 1
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
  # The collect pod is elsewhere: hand it what this shard staged, and check the
  # copy is complete (every staged file is there with its size).
  if ! rclone copy "$STAGE" "$RUN_S3/stage" --transfers 8 --retries 5 --quiet \
     || ! rclone check "$STAGE" "$RUN_S3/stage" --one-way --size-only --quiet; then
    discord "ERROR: fetch shard $idx/$TOTAL could not upload its stage to $WORK_S3"
    return 1
  fi
  log "fetch: shard $idx uploaded $(find "$STAGE" -type f | wc -l | tr -d ' ') files"
  return "$rc"
}

role_collect() {
  log "collect: compare + place over stage"
  if [ -z "${GIT_TOKEN:-}" ]; then
    discord "ERROR: collect role has no GIT_TOKEN"; return 2
  fi
  rm -rf "$REPO" "$STAGE"
  if ! git clone -q "https://x-access-token:${GIT_TOKEN}@${REPO_URL}" "$REPO"; then
    discord "ERROR: clone of $GH_REPO failed"; return 1
  fi
  git -C "$REPO" config user.email "d2-bnftp-poller@users.noreply.github.com"
  git -C "$REPO" config user.name "d2-bnftp-poller"
  mkdir -p "$STAGE"
  if ! rclone copy "$RUN_S3/stage" "$STAGE" --transfers 8 --retries 5 --quiet \
     || ! rclone check "$RUN_S3/stage" "$STAGE" --one-way --size-only --quiet; then
    discord "ERROR: collect could not download the shards' stage from $WORK_S3"; return 1
  fi
  log "collect: stage has $(find "$STAGE" -type f | wc -l | tr -d ' ') files"
  # The fetch-list the shards worked from, not whatever the repo's head says now.
  fetch_list || return 1
  cd "$REPO"
  # Refresh to the freshest origin/main before doing anything, so the resulting
  # commit is always a plain fast-forward (the push can't race a mid-run edit).
  # Safe: the clone has no local commits, and the fetched bytes live in stage/,
  # outside the repo, so this only advances the working tree to the latest remote.
  git fetch -q origin main && git reset -q --hard origin/main
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
  # Plain fast-forward push - no rebase, no merge, no force. If the remote moved
  # during this run (only happens when the repo is edited mid-run), the push just
  # fails and we skip it; the next scheduled run redoes the work, since the commit
  # is a pure function of the fetched bytes. The remote is never rewritten.
  if ! git push -q; then
    discord "ERROR: git push to $GH_REPO skipped - remote moved during this run; the next run will redo it"$'\n'"$anomalies"
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
    prepare) role_prepare ;;
    fetch)   role_fetch ;;
    collect) role_collect ;;
    *)
      log "usage: entrypoint.sh <prepare|fetch|collect>"
      return 2
      ;;
  esac
}

dispatch
rc=$?
# A finished run's bytes are of no use to the next one (prepare empties the
# prefix regardless); drop them once collect has what it needs.
[ "$ROLE" = collect ] && [ "$rc" -eq 0 ] && rclone purge "$RUN_S3" >/dev/null 2>&1
exit "$rc"
