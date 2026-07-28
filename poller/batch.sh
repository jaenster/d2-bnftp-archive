#!/usr/bin/env bash
# Batched Discord log sender. Reads lines on stdin, tees them to stdout (so the
# k8s pod log still has everything), and accumulates them into batches that are
# POSTed to $DISCORD_WEBHOOK_URL. A batch is flushed when it reaches ~1900 chars
# or ~1.5s has passed since the last line. Each POST is JSON:
#   {"username":"d2-bnftp-poller","content":"```\n<batch>\n```"}
# HTTP 429 retry_after is honored. If DISCORD_WEBHOOK_URL is unset this is never
# invoked (the entrypoint runs without the pipe); if it is somehow reached with
# no webhook it degrades to a plain tee.
set -uo pipefail

WEBHOOK="${DISCORD_WEBHOOK_URL:-}"
FLUSH_SECS=1.5
MAX_CHARS=1900

# Fractional read timeouts need bash >= 4 (the alpine runtime has bash 5). Fall
# back to an integer timeout on older bash so input is never dropped.
if ! ( read -t 1.5 -r _x </dev/null ) 2>/dev/null; then
  FLUSH_SECS=2
fi

buf=""

json_escape() {
  # Escape a string for embedding in a JSON string literal.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

post() {
  # POST the given content as a fenced code block, honoring 429 retry_after.
  local content="$1"
  [ -z "$content" ] && return 0
  [ -z "$WEBHOOK" ] && return 0
  local payload
  payload="$(printf '{"username":"d2-bnftp-poller","content":"```\\n%s\\n```"}' "$(json_escape "$content")")"
  local attempt=0
  while [ "$attempt" -lt 5 ]; do
    local resp code
    resp="$(curl -sS -w $'\n%{http_code}' \
      -H 'Content-Type: application/json' \
      -X POST -d "$payload" "$WEBHOOK" 2>/dev/null)"
    code="${resp##*$'\n'}"
    if [ "$code" = "429" ]; then
      local body="${resp%$'\n'*}"
      local retry
      retry="$(printf '%s' "$body" | grep -o '"retry_after"[: ]*[0-9.]*' | grep -o '[0-9.]*' | head -1)"
      [ -z "$retry" ] && retry=1
      sleep "$retry"
      attempt=$((attempt + 1))
      continue
    fi
    return 0
  done
  return 0
}

flush() {
  if [ -n "$buf" ]; then
    post "$buf"
    buf=""
  fi
}

# Read with a short timeout so a partial batch still flushes on idle. `read -t`
# returns >128 on timeout; we flush and keep going. EOF ends the loop.
while :; do
  if IFS= read -r -t "$FLUSH_SECS" line; then
    printf '%s\n' "$line"
    if [ -z "$buf" ]; then
      buf="$line"
    else
      buf="$buf"$'\n'"$line"
    fi
    if [ "${#buf}" -ge "$MAX_CHARS" ]; then
      flush
    fi
  else
    rc=$?
    if [ "$rc" -gt 128 ]; then
      # idle timeout -> flush what we have
      flush
    else
      # EOF
      break
    fi
  fi
done
flush
