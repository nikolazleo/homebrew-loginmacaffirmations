# 0) Variables — adjust these
USER_NAME="$(whoami)"               # user to install for
# Configure one or more API sources to alternate between. On each run the updater rotates
# to the next source and skips re-applying a message identical to the last one shown.
# API_AUTH_HEADERS must be the same length as API_URLS; use "" for sources that need no auth header.
API_URLS=(
  "https://www.affirmations.dev/"      # returns JSON like {"affirmation":"..."}
  # "https://your-second-api.example.com/message"   # add more sources here to rotate between them
)
API_AUTH_HEADERS=(
  ""
  # ""   # keep this array the same length as API_URLS, e.g. 'Authorization: Bearer xyz'
)
CRON_INTERVAL_SECONDS="${CRON_INTERVAL_SECONDS:-3600}"   # scheduled refresh interval, in addition to at-login refresh

# 1) Root helper that sets the lock message
sudo install -d /usr/local/sbin
cat <<'EOF' | sudo tee /usr/local/sbin/set-loginmessage >/dev/null
#!/bin/zsh
set -euo pipefail
# Join all args into one string (spaces preserved)
msg="$*"
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "$msg"
/usr/bin/killall cfprefsd 2>/dev/null || true
# Next lock will show it; no reboot needed.
EOF
sudo chmod 755 /usr/local/sbin/set-loginmessage
sudo chown root:wheel /usr/local/sbin/set-loginmessage

# 2) Sudoers rule (only allow running that exact helper without a password)
echo "${USER_NAME} ALL=(root) NOPASSWD: /usr/local/sbin/set-loginmessage *" | sudo tee /etc/sudoers.d/lockmessage >/dev/null
sudo chmod 440 /etc/sudoers.d/lockmessage

# 3) State directory for rotation/dedup (owned by the installing user so the LaunchAgent,
#    which runs as that user, can read/write it without sudo)
sudo install -d -o "$USER_NAME" -m 755 /usr/local/var/lockmessage

# Render the configured API sources into literal zsh array syntax for the generated script.
render_array_literal() {
  local -a items=("$@")
  local out="(" item esc
  for item in "${items[@]}"; do
    esc="${item//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    out+=$'\n  '"\"$esc\""
  done
  out+=$'\n)'
  print -r -- "$out"
}
API_URLS_LITERAL="$(render_array_literal "${API_URLS[@]}")"
API_AUTH_HEADERS_LITERAL="$(render_array_literal "${API_AUTH_HEADERS[@]}")"

# 4) User script that fetches, rotates through sources, dedups, and applies the message
cat <<EOF > "/usr/local/sbin/update_lock_message.sh"
#!/bin/zsh
set -uo pipefail

STATE_DIR="/usr/local/var/lockmessage"
mkdir -p "\$STATE_DIR" 2>/dev/null || true

API_URLS=${API_URLS_LITERAL}
API_AUTH_HEADERS=${API_AUTH_HEADERS_LITERAL}

count=\${#API_URLS[@]}
if (( count == 0 )); then
  echo "update_lock_message: no API_URLS configured" >&2
  exit 1
fi

last_index=0
if [[ -f "\$STATE_DIR/last_index" ]]; then
  last_index=\$(<"\$STATE_DIR/last_index")
  [[ "\$last_index" =~ ^[0-9]+\$ ]] || last_index=0
fi

last_message=""
[[ -f "\$STATE_DIR/last_message" ]] && last_message=\$(<"\$STATE_DIR/last_message")

# Fetch + parse one source. Prints the sanitized message and returns 0, or returns 1 on failure.
fetch_and_parse() {
  local url="\$1" auth="\$2" resp msg
  if [[ -n "\$auth" ]]; then
    resp=\$(/usr/bin/curl -fsSL --max-time 10 -H "\$auth" "\$url" 2>/dev/null) || return 1
  else
    resp=\$(/usr/bin/curl -fsSL --max-time 10 "\$url" 2>/dev/null) || return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    msg=\$(printf '%s' "\$resp" | jq -r '.message // .msg // .text // .value // .affirmation // empty' 2>/dev/null | head -n1)
  else
    msg=\$(printf '%s' "\$resp" | /usr/bin/python3 -c '
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
  [[ -z "\$msg" ]] && msg="\$resp"

  # Sanitize and trim (loginwindow renders best with single-line; keep it sane-length)
  msg="\${msg//\$'\n'/ }"
  msg="\${msg//\$'\r'/ }"
  msg="\${msg:0:500}"

  [[ -z "\$msg" ]] && return 1
  printf '%s' "\$msg"
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
  idx=\$(( (last_index + 1 + i) % count ))
  candidate=\$(fetch_and_parse "\${API_URLS[\$((idx+1))]}" "\${API_AUTH_HEADERS[\$((idx+1))]}") || candidate=""
  if [[ -n "\$candidate" ]]; then
    if [[ -z "\$fallback_msg" ]]; then
      fallback_msg="\$candidate"
      fallback_idx=\$idx
    fi
    if [[ "\$candidate" != "\$last_message" ]]; then
      chosen_msg="\$candidate"
      chosen_idx=\$idx
      break
    fi
  fi
  i=\$(( i + 1 ))
done

if [[ -z "\$chosen_msg" ]]; then
  chosen_msg="\$fallback_msg"
  chosen_idx=\$fallback_idx
fi

if [[ -z "\$chosen_msg" || "\$chosen_idx" -lt 0 ]]; then
  echo "update_lock_message: all API sources failed; leaving existing message in place" >&2
  exit 1
fi

# Set the system message via the root helper
/usr/bin/sudo /usr/local/sbin/set-loginmessage "\$chosen_msg"

printf '%s' "\$chosen_idx" > "\$STATE_DIR/last_index"
printf '%s' "\$chosen_msg" > "\$STATE_DIR/last_message"
EOF
chmod +x "/usr/local/sbin/update_lock_message.sh"

# 5) LaunchAgent to run at login and on a schedule
mkdir -p "/Library/LaunchAgents"
cat <<EOF > "/Library/LaunchAgents/com.custom.update-lockmessage.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.custom.update-lockmessage</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>/usr/local/sbin/update_lock_message.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>${CRON_INTERVAL_SECONDS}</integer>
  <key>StandardOutPath</key><string>/Library/Logs/update-lockmessage.out.log</string>
  <key>StandardErrorPath</key><string>/Library/Logs/update-lockmessage.err.log</string>
</dict></plist>
EOF

# 6) Ensure loginwindow text is enabled
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow DisableLoginwindowText -bool false

# 7) Load the LaunchAgent now (and it will run at every future login and every CRON_INTERVAL_SECONDS)
launchctl bootstrap "gui/$(id -u)" "/Library/LaunchAgents/com.custom.update-lockmessage.plist" 2>/dev/null || launchctl load -w "/Library/LaunchAgents/com.custom.update-lockmessage.plist"

# 8) Prime-run once so your next lock shows the new text
"/usr/local/sbin/update_lock_message.sh"

echo "Done. Lock the screen and you should see the updated message."
