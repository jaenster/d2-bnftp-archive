#!/usr/bin/env bash
# Role-dispatch entrypoint for the d2-bnftp-poller Argo Workflow.
#
# Usage: entrypoint.sh <clone|fetch|collect>
#
# The weekly CronWorkflow runs a clone -> fetch(x3) -> collect DAG; Argo's DAG
# dependencies handle ordering, so there is no shared-PVC barrier. All three
# roles share a RWX PVC mounted at /work:
#   clone   - fresh clone of the archive repo into /work/repo (needs GIT_TOKEN)
#   fetch   - the Zig poller fetches this shard's (file,source) pairs into
#             /work/stage/<source>/<filename> (SHARD_INDEX/SHARD_TOTAL). The three
#             fetch pods land on distinct nodes (podAntiAffinity) -> distinct
#             egress IPs.
#   collect - compare + placement + SHA256SUMS + REALM-DIVERGENCE.md + commit +
#             push (needs GIT_TOKEN).
#
# Each role's stdout/stderr is piped through the batched Discord sender (batch.sh)
# when DISCORD_WEBHOOK_URL is set; otherwise it goes to stdout only.
set -uo pipefail

WORK=/work
REPO="$WORK/repo"
STAGE="$WORK/stage"
TOTAL="${SHARD_TOTAL:-3}"
REPO_URL="github.com/jaenster/d2-bnftp-archive.git"
FETCH_LIST_PATH="$REPO/fetch-list"
D2_SOURCES="useast uswest asia europe vegas"
HERE="$(cd "$(dirname "$0")" && pwd)"

ROLE="${1:-}"

log() { echo "[$ROLE] $*"; }

role_clone() {
  log "clone: fresh clone of the archive repo"
  if [ -z "${GIT_TOKEN:-}" ]; then
    log "GIT_TOKEN is not set"; return 2
  fi
  rm -rf "$REPO" "$STAGE"
  git clone "https://x-access-token:${GIT_TOKEN}@${REPO_URL}" "$REPO"
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
  return "$rc"
}

role_collect() {
  log "collect: compare + place over stage"
  if [ -z "${GIT_TOKEN:-}" ]; then
    log "GIT_TOKEN is not set"; return 2
  fi
  cd "$REPO"
  mkdir -p files
  local divergent=0

  # Placement over the staged bytes.
  while read -r class filename rest; do
    case "$class" in
      ""|\#*) continue ;;
    esac
    [ -z "${filename:-}" ] && continue

    if [ "$class" = "forever" ]; then
      local src="$STAGE/forever/$filename"
      if [ -s "$src" ]; then
        mkdir -p "files/forever"
        cp "$src" "files/forever/$filename"
      else
        log "WARN forever/$filename missing from stage"
      fi
      continue
    fi

    if [ "$class" != "d2" ]; then
      log "WARN unknown class $class for $filename"
      continue
    fi

    # Gather the d2 sources that produced bytes; decide identical vs divergent.
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
      log "WARN d2/$filename: no source produced bytes"
      continue
    fi

    if [ "$identical" -eq 1 ] && [ "$have" -eq 5 ]; then
      # All five sources agree -> canonical. Drop any stale per-source copies.
      set -- $present
      cp "$STAGE/$1/$filename" "files/$filename"
      for s in $D2_SOURCES; do
        rm -f "files/$s/$filename"
      done
    else
      # Divergence (or a source missing bytes) -> per-source copies for every
      # source that produced bytes; drop the canonical copy.
      divergent=$((divergent + 1))
      log "DIVERGENCE d2/$filename (present:$present identical=$identical have=$have)"
      rm -f "files/$filename"
      for s in $D2_SOURCES; do
        local sp="$STAGE/$s/$filename"
        if [ -s "$sp" ]; then
          mkdir -p "files/$s"
          cp "$sp" "files/$s/$filename"
        fi
      done
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

  write_divergence_report
  echo "$(date -u +%FT%TZ) fetched via 3-shard Argo Workflows multi-source poller" > LAST-FETCHED.txt

  if [ -n "$(git status --porcelain)" ]; then
    log "changes detected, committing ($divergent divergent d2 file(s))"
    git add -A
    git commit -m "refetch: update changed BNFTP files ($(date -u +%F))"
    git push
    log "pushed"
  else
    log "no changes; nothing to commit ($divergent divergent d2 file(s))"
  fi
  return 0
}

write_divergence_report() {
  # List every file NOT in canonical files/ (i.e. under a per-source subdir) with
  # its per-source sha256.
  local md="REALM-DIVERGENCE.md"
  {
    echo "# Realm divergence report"
    echo
    echo "Generated $(date -u +%FT%TZ) by the 3-shard Argo Workflows multi-source poller."
    echo
    echo "Files here were NOT byte-identical across all D2 sources, plus the"
    echo "forever-only legacy set. Byte-identical D2 files live at the canonical"
    echo "path files/<filename> and are omitted below."
    echo
    local subfiles
    subfiles="$( (cd files 2>/dev/null && find . -mindepth 2 -type f 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort) || true)"
    if [ -z "$subfiles" ]; then
      echo "No divergences. Every D2 file was identical across all sources."
    else
      local names
      names="$(echo "$subfiles" | awk -F/ '{print $NF}' | LC_ALL=C sort -u)"
      echo "$names" | while read -r name; do
        [ -z "$name" ] && continue
        echo "## $name"
        echo
        echo "| source | sha256 |"
        echo "|-|-|"
        for s in $D2_SOURCES forever; do
          local fp="files/$s/$name"
          if [ -s "$fp" ]; then
            printf '| %s | %s |\n' "$s" "$(sha256sum "$fp" | awk '{print $1}')"
          fi
        done
        echo
      done
    fi
  } > "$md"
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

# --- Discord-batched output wrapper ---------------------------------------------
if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
  dispatch 2>&1 | "$HERE/batch.sh"
  exit "${PIPESTATUS[0]}"
else
  dispatch
  exit $?
fi
