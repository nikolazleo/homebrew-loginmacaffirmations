#!/bin/zsh
# Fetches, rotates, dedupes, and applies the macOS login-window text.
#
# Designed to run as root (e.g. under a Homebrew-managed LaunchDaemon started
# via `sudo brew services start`), so it writes the system preference and
# flushes the preference cache directly -- no separate sudo helper is needed.
set -uo pipefail

CONFIG_FILE="${LOGINMACAFFIRMATIONS_CONFIG:-/usr/local/etc/loginmacaffirmations/config}"
STATE_DIR="${LOGINMACAFFIRMATIONS_STATE_DIR:-/usr/local/var/loginmacaffirmations}"
mkdir -p "$STATE_DIR" 2>/dev/null || true

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

# Fall back to the affirmations.dev default if no config is present yet.
API_URLS=("${API_URLS[@]:-https://www.affirmations.dev/}")
API_AUTH_HEADERS=("${API_AUTH_HEADERS[@]:-}")

count=${#API_URLS[@]}
if (( count == 0 )); then
  echo "update-lock-message: no API_URLS configured in $CONFIG_FILE" >&2
  exit 1
fi

last_index=0
if [[ -f "$STATE_DIR/last_index" ]]; then
  last_index=$(<"$STATE_DIR/last_index")
  [[ "$last_index" =~ ^[0-9]+$ ]] || last_index=0
fi

last_message=""
[[ -f "$STATE_DIR/last_message" ]] && last_message=$(<"$STATE_DIR/last_message")

# Fetch + parse one source. Prints the sanitized message and returns 0, or returns 1 on failure.
fetch_and_parse() {
  local url="$1" auth="$2" resp msg
  if [[ -n "$auth" ]]; then
    resp=$(/usr/bin/curl -fsSL --max-time 10 -H "$auth" "$url" 2>/dev/null) || return 1
  else
    resp=$(/usr/bin/curl -fsSL --max-time 10 "$url" 2>/dev/null) || return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    msg=$(printf '%s' "$resp" | jq -r '.message // .msg // .text // .value // .affirmation // empty' 2>/dev/null | head -n1)
  else
    msg=$(printf '%s' "$resp" | /usr/bin/python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for k in ("message","msg","text","value","affirmation"):
        if isinstance(d,dict) and isinstance(d.get(k),str):
            print(d[k]); break
        elif isinstance(d,list) and d and isinstance(d[0],str):
            print(d[0]); break
except Exception:
    pass
' 2>/dev/null)
  fi
  [[ -z "$msg" ]] && msg="$resp"

  # Sanitize and trim (loginwindow renders best with single-line; keep it sane-length)
  msg="${msg//$'\n'/ }"
  msg="${msg//$'\r'/ }"
  msg="${msg:0:500}"

  [[ -z "$msg" ]] && return 1
  printf '%s' "$msg"
  return 0
}

# Rotate starting at the source after the last one used. Prefer the first candidate that
# differs from the last-applied message; fall back to the first successful fetch otherwise
# (e.g. on the very first run, or if every source currently matches the last message).
chosen_msg=""
chosen_idx=-1
fallback_msg=""
fallback_idx=-1

i=0
while (( i < count )); do
  idx=$(( (last_index + 1 + i) % count ))
  candidate=$(fetch_and_parse "${API_URLS[$((idx+1))]}" "${API_AUTH_HEADERS[$((idx+1))]:-}") || candidate=""
  if [[ -n "$candidate" ]]; then
    if [[ -z "$fallback_msg" ]]; then
      fallback_msg="$candidate"
      fallback_idx=$idx
    fi
    if [[ "$candidate" != "$last_message" ]]; then
      chosen_msg="$candidate"
      chosen_idx=$idx
      break
    fi
  fi
  i=$(( i + 1 ))
done

if [[ -z "$chosen_msg" ]]; then
  chosen_msg="$fallback_msg"
  chosen_idx=$fallback_idx
fi

if [[ -z "$chosen_msg" || "$chosen_idx" -lt 0 ]]; then
  echo "update-lock-message: all API sources failed; leaving existing message in place" >&2
  exit 1
fi

# Set the system message directly (this script must run as root). Also
# ensure loginwindow text is enabled, in case something (an MDM profile, a
# manual admin change) previously set DisableLoginwindowText -- otherwise the
# message we just set would be silently suppressed.
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow DisableLoginwindowText -bool false
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "$chosen_msg"
/usr/bin/killall cfprefsd 2>/dev/null || true

printf '%s' "$chosen_idx" > "$STATE_DIR/last_index"
printf '%s' "$chosen_msg" > "$STATE_DIR/last_message"
