#!/usr/bin/env bash
# Runs the given command (normally ./bin/api) against a locally launched
# CDP browser, standing in for the wrapper/supervisord stack the container
# provides: it starts the browser with remote debugging, captures its output
# to a log file, waits for the "DevTools listening on ws://" line the
# server's upstream manager tails for, then runs the server pointed at that
# log. The browser is killed when the server exits.
set -euo pipefail

SERVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIR="$SERVER_DIR/.dev"
LOG_FILE="$DEV_DIR/chromium.log"
USER_DATA_DIR="$DEV_DIR/chrome-user-data"
# 9223: the server's own DevTools proxy listens on 9222.
DEBUG_PORT="${CHROME_DEBUG_PORT:-9223}"
READY_TIMEOUT="${READY_TIMEOUT:-30}"

# CHROME_BIN overrides (e.g. your installed Google Chrome); default is the
# Chrome for Testing installed by `make dev-browser`, falling back to a
# previously installed chrome-headless-shell.
BROWSER="${CHROME_BIN:-}"
if [[ -z "$BROWSER" ]]; then
  BROWSER="$(find "$DEV_DIR/browser" -type f -name 'Google Chrome for Testing' 2>/dev/null | head -1)"
fi
if [[ -z "$BROWSER" ]]; then
  BROWSER="$(find "$DEV_DIR/browser" -type f -name 'chrome-headless-shell' 2>/dev/null | head -1)"
fi
if [[ -z "$BROWSER" || ! -x "$BROWSER" ]]; then
  echo "dev-local: no browser found — run 'make dev-browser' (or set CHROME_BIN)" >&2
  exit 1
fi

mkdir -p "$DEV_DIR" "$USER_DATA_DIR"
# Truncate so the upstream manager can't scrape a stale ws:// URL from a
# previous run.
: > "$LOG_FILE"

# Headful by default so you can watch the browser. HEADLESS=1 opts out
# (chrome-headless-shell is headless by construction and needs no flag).
HEADLESS_FLAG=""
if [[ "$BROWSER" != *chrome-headless-shell* && -n "${HEADLESS:-}" ]]; then
  HEADLESS_FLAG="--headless=new"
fi

"$BROWSER" $HEADLESS_FLAG \
  --remote-debugging-port="$DEBUG_PORT" \
  --user-data-dir="$USER_DATA_DIR" \
  --no-first-run --no-default-browser-check \
  about:blank >"$LOG_FILE" 2>&1 &
BROWSER_PID=$!
trap 'kill "$BROWSER_PID" 2>/dev/null; wait "$BROWSER_PID" 2>/dev/null' EXIT

# Gate on the DevTools line so a slow browser cold start can't eat into the
# server's own 10s upstream deadline.
for _ in $(seq 1 $((READY_TIMEOUT * 5))); do
  grep -q 'DevTools listening on ws://' "$LOG_FILE" && break
  if ! kill -0 "$BROWSER_PID" 2>/dev/null; then
    echo "dev-local: browser exited during startup; its output:" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi
  sleep 0.2
done
if ! grep -q 'DevTools listening on ws://' "$LOG_FILE"; then
  echo "dev-local: browser produced no DevTools URL within ${READY_TIMEOUT}s; its output:" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi
echo "dev-local: browser ready ($(grep -o 'DevTools listening on ws://[^ ]*' "$LOG_FILE" | head -1))"

export CHROMIUM_LOG_PATH="$LOG_FILE"
# Not exec: the EXIT trap must survive to reap the browser on Ctrl-C.
"$@"
