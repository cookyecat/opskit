#!/usr/bin/env bash
# Wait for an existing process to finish, then run a command safely.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: watchit.sh [--interval SECONDS] PID COMMAND [ARG ...]
Wait for the given process (or its zombie state), then run COMMAND.

Examples:
  ./watchit.sh 12345 python3 train.py
  ./watchit.sh --interval 5 12345 bash -lc 'echo finished && date'

Commands are passed as arguments, not evaluated as a shell string.
HELP
}

interval="${WATCHIT_INTERVAL:-3}"
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --interval)
      [[ $# -ge 2 ]] || { echo "Missing --interval value" >&2; exit 2; }
      interval="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $# -lt 2 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  usage >&2
  exit 2
fi
pid="$1"
shift

if [[ ! "$interval" =~ ^[1-9][0-9]*$ ]]; then
  echo "Interval must be a positive integer number of seconds." >&2
  exit 2
fi

process_state() {
  ps -p "$pid" -o stat= 2>/dev/null | tr -d '[:space:]' || true
}

initial_state="$(process_state)"
if [[ -z "$initial_state" || "$initial_state" == Z* ]]; then
  echo "PID $pid is not a running process." >&2
  exit 1
fi

# Guard against PID reuse (different process later receiving the same PID).
started_at="$(ps -p "$pid" -o lstart= 2>/dev/null || true)"
printf 'Waiting for PID %s (every %ss) ...\n' "$pid" "$interval"

while true; do
  state="$(process_state)"
  [[ -z "$state" || "$state" == Z* ]] && break
  current_start="$(ps -p "$pid" -o lstart= 2>/dev/null || true)"
  [[ -n "$started_at" && "$current_start" != "$started_at" ]] && break
  sleep "$interval"
done

printf 'PID %s finished; running: %s\n' "$pid" "$1"
exec "$@"
