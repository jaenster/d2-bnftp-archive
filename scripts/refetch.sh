#!/usr/bin/env bash
#
# refetch.sh -- re-fetch every file in fetch-list from Blizzard's classic
# Battle.net BNFTP servers using the d2-clientless BNFTP client, then
# regenerate SHA256SUMS and LAST-FETCHED.txt.
#
# BNFTP is unauthenticated (protocol selector 0x02), so every fetch uses
# --bnftp-only. Files land in files/. A file that comes back empty is retried
# a few times before giving up (the servers occasionally RST a connection,
# yielding a false 0-byte reply). A file that is empty on every attempt is
# left as-is so a transient server hiccup never wipes an archived file.
#
# Usage:
#   scripts/refetch.sh [PATH_TO_D2_CLIENTLESS_CHECKOUT]
#
# If no path is given, d2-clientless is cloned into a temp dir. Requires
# Zig 0.16.0 on PATH.
#
# Idempotent and safe to run locally: it only writes files/, SHA256SUMS and
# LAST-FETCHED.txt.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FETCH_LIST="$REPO_ROOT/fetch-list"
FILES_DIR="$REPO_ROOT/files"
CLIENTLESS_REPO="https://github.com/jaenster/d2-clientless.git"
MAX_TRIES=4

if [ ! -f "$FETCH_LIST" ]; then
  echo "error: fetch-list not found at $FETCH_LIST" >&2
  exit 1
fi

# Resolve the d2-clientless checkout: use the argument if given, else clone.
CLEANUP_CLIENTLESS=0
if [ "${1:-}" != "" ]; then
  CLIENTLESS_DIR="$(cd "$1" && pwd)"
else
  CLIENTLESS_DIR="$(mktemp -d)/d2-clientless"
  CLEANUP_CLIENTLESS=1
  echo "cloning d2-clientless into $CLIENTLESS_DIR ..."
  git clone --depth 1 "$CLIENTLESS_REPO" "$CLIENTLESS_DIR"
fi

cleanup() {
  if [ "$CLEANUP_CLIENTLESS" = "1" ]; then
    rm -rf "$(dirname "$CLIENTLESS_DIR")"
  fi
}
trap cleanup EXIT

if [ ! -f "$CLIENTLESS_DIR/build.zig" ]; then
  echo "error: $CLIENTLESS_DIR does not look like a d2-clientless checkout" >&2
  exit 1
fi

echo "building d2-clientless bnftp tool ..."
( cd "$CLIENTLESS_DIR" && zig build )
BNFTP_BIN="$CLIENTLESS_DIR/zig-out/bin/clientless"
if [ ! -x "$BNFTP_BIN" ]; then
  echo "error: built clientless binary not found at $BNFTP_BIN" >&2
  exit 1
fi

mkdir -p "$FILES_DIR"

# Fetch one file into files/. Returns 0 if a non-empty file is present after
# the attempt, 1 otherwise. Retries up to MAX_TRIES on an empty reply.
fetch_one() {
  local host="$1" product="$2" fname="$3"
  local dest="$FILES_DIR/$fname"
  local try
  for try in $(seq 1 "$MAX_TRIES"); do
    "$BNFTP_BIN" bnftp --bnftp-only --out-dir "$FILES_DIR" "$host" "$product" "$fname" >/dev/null 2>&1 || true
    if [ -s "$dest" ]; then
      return 0
    fi
    echo "  empty reply for $fname (attempt $try/$MAX_TRIES), retrying ..."
    sleep 2
  done
  return 1
}

TOTAL=0
OK=0
FAILED=()
HOSTS=""

while read -r host product fname; do
  case "$host" in
    ""|\#*) continue ;;
  esac
  TOTAL=$((TOTAL + 1))
  case "$HOSTS" in
    *"$host"*) : ;;
    *) HOSTS="$HOSTS $host" ;;
  esac
  echo "fetch: $host $product $fname"
  if fetch_one "$host" "$product" "$fname"; then
    OK=$((OK + 1))
  else
    echo "  WARN: $fname still empty after $MAX_TRIES attempts; leaving existing file untouched" >&2
    FAILED+=("$fname")
  fi
done < "$FETCH_LIST"

echo "fetched $OK/$TOTAL files non-empty"
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "empty (not served right now): ${FAILED[*]}"
fi

# Regenerate SHA256SUMS over files/* (paths relative to files/, sorted).
echo "regenerating SHA256SUMS ..."
if command -v sha256sum >/dev/null 2>&1; then
  SHACMD="sha256sum"
else
  SHACMD="shasum -a 256"
fi
(
  cd "$FILES_DIR"
  # shellcheck disable=SC2035
  LC_ALL=C ls | sort | while read -r f; do
    [ -f "$f" ] || continue
    $SHACMD "$f"
  done
) > "$REPO_ROOT/SHA256SUMS"

# Record when this ran and where the files came from.
{
  echo "last-fetched (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "sources:$HOSTS"
} > "$REPO_ROOT/LAST-FETCHED.txt"

echo "done."
