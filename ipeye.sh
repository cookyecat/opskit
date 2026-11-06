#!/usr/bin/env bash
# Record the primary LAN IPv4 address; optionally email when it changes.
# No recipient, credentials, machine paths, or mail backend are hard-coded.
set -euo pipefail
umask 077

usage() {
  cat <<'HELP'
Usage: ipeye.sh [--state-file PATH] [--email ADDRESS] [--ip IPv4]
Track the machine's primary IPv4 address. The first run initializes state;
later changes print a message and optionally email via sendmail -t.

Examples:
  ./ipeye.sh
  ./ipeye.sh --email admin@example.com
  ./ipeye.sh --state-file /tmp/my-ip-state --ip 192.0.2.10

--ip is primarily useful for controlled tests.
Run from cron/launchd to check periodically; this script does not daemonize.
HELP
}

state_file="${XDG_STATE_HOME:-$HOME/.local/state}/utiscripts/lan-ip"
email=""
override_ip=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-file)
      [[ $# -ge 2 ]] || { echo "Missing --state-file value" >&2; exit 2; }
      state_file="$2"; shift 2 ;;
    --email)
      [[ $# -ge 2 ]] || { echo "Missing --email value" >&2; exit 2; }
      email="$2"; shift 2 ;;
    --ip)
      [[ $# -ge 2 ]] || { echo "Missing --ip value" >&2; exit 2; }
      override_ip="$2"; shift 2 ;;
    --help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$email" && ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid email address." >&2; exit 2
fi

primary_ip() {
  local iface
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null |
      awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  elif [[ "$(uname -s)" == Darwin ]]; then
    iface="$(route -n get default 2>/dev/null |
      awk '/interface:/{print $2; exit}')"
    [[ -n "$iface" ]] && ipconfig getifaddr "$iface"
  elif command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

current_ip="${override_ip:-$(primary_ip || true)}"
if [[ ! "$current_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Could not determine a valid IPv4 address." >&2
  exit 1
fi
IFS=. read -r a b c d <<< "$current_ip"
for octet in "$a" "$b" "$c" "$d"; do
  if (( 10#$octet > 255 )); then
    echo "Invalid IPv4 address." >&2; exit 2
  fi
done

old_ip=""
if [[ -f "$state_file" ]]; then
  IFS= read -r old_ip < "$state_file" || true
fi

if [[ "$old_ip" == "$current_ip" ]]; then
  echo "Unchanged: $current_ip"
  exit 0
fi

if [[ -n "$old_ip" && -n "$email" ]]; then
  mailer="$(command -v sendmail || true)"
  if [[ -z "$mailer" ]]; then
    echo "sendmail is required for --email (state was not updated)." >&2
    exit 1
  fi
  host="$(hostname)"
  if ! printf 'To: %s\nSubject: LAN IP changed (%s)\n\nOld: %s\nNew: %s\n' \
      "$email" "$host" "$old_ip" "$current_ip" | "$mailer" -t; then
    echo "Email delivery failed (state was not updated)." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$state_file")"
temp_file="$(mktemp "${state_file}.XXXXXX")"
trap 'rm -f "$temp_file"' EXIT
printf '%s\n' "$current_ip" > "$temp_file"
mv -f "$temp_file" "$state_file"
if [[ -n "$old_ip" ]]; then
  printf 'Changed: %s -> %s\n' "$old_ip" "$current_ip"
else
  printf 'Initialized: %s\n' "$current_ip"
fi
