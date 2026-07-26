#!/usr/bin/env bash
# Claude Code hook: sound + OS notification naming the project + signal file.
# Usage: play-sound.sh <stop|permission>   (hook JSON arrives on stdin)
#
# The hook's stdin JSON carries `cwd` — the project Claude was working in.
# That gives "which window/tab finished?" three answers at once:
#   1. The OS notification names the project folder.
#   2. A signal file in ~/.claude-code-chime/ lets the claude-chime VS Code
#      extension raise the toast inside the exact window that finished.
#   3. The sound still plays as before.
#
# Security: stdin is size-capped and parsed with a real JSON parser; the
# project name reaches osascript only as an argv item (never interpolated
# into AppleScript source); signal files are written atomically under a
# 0700 directory; the event name is allow-list validated.
set -u

case "${1:-}" in
  stop|permission) event="$1" ;;
  *) event="stop" ;;
esac

# --- Read hook payload (size-capped; skipped when run manually from a TTY) ---
payload=""
if [ ! -t 0 ]; then
  payload="$(head -c 4096 2>/dev/null || true)"
fi

# --- Extract project name + drop a signal file for the VS Code extension ---
proj=""
if command -v python3 >/dev/null 2>&1; then
  proj="$(printf '%s' "$payload" | python3 -c '
import json, os, sys, tempfile, time

event = sys.argv[1]
cwd = ""
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict) and isinstance(data.get("cwd"), str):
        cwd = data["cwd"]
except Exception:
    pass

sig_dir = os.path.join(os.path.expanduser("~"), ".claude-code-chime")
try:
    os.makedirs(sig_dir, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=sig_dir, suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump({"event": event, "cwd": cwd, "ts": time.time()}, f)
    os.rename(tmp, os.path.join(sig_dir, "signal-%d.json" % int(time.time() * 1000)))
    now = time.time()
    for name in os.listdir(sig_dir):
        p = os.path.join(sig_dir, name)
        try:
            if now - os.path.getmtime(p) > 3600:
                os.remove(p)
        except OSError:
            pass
except Exception:
    pass

print(os.path.basename(cwd))
' "$event" 2>/dev/null || true)"
fi

if [ "$event" = "permission" ]; then
  title="Claude needs permission"
else
  title="Claude finished responding"
fi
body="Project: ${proj:-unknown}"

# --- OS notification + sound, per platform ---
case "$(uname -s)" in
  Darwin)
    # argv-based AppleScript: values are data, never script source
    osascript \
      -e 'on run argv' \
      -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
      -e 'end run' \
      "$body" "$title" >/dev/null 2>&1 &
    if [ "$event" = "permission" ]; then
      sound="/System/Library/Sounds/Purr.aiff"
    else
      sound="/System/Library/Sounds/Funk.aiff"
    fi
    [ -f "$sound" ] && exec afplay "$sound"
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$title" "$body" >/dev/null 2>&1 &
    fi
    if [ "$event" = "permission" ]; then
      sound="/usr/share/sounds/freedesktop/stereo/dialog-information.oga"
    else
      sound="/usr/share/sounds/freedesktop/stereo/complete.oga"
    fi
    if command -v paplay >/dev/null 2>&1 && [ -f "$sound" ]; then
      exec paplay "$sound"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    if [ "$event" = "permission" ]; then
      ps_cmd='(New-Object Media.SoundPlayer "C:\Windows\Media\Windows Notify.wav").PlaySync()'
    else
      ps_cmd='(New-Object Media.SoundPlayer "C:\Windows\Media\Windows Ding.wav").PlaySync()'
    fi
    exec powershell.exe -NoProfile -NonInteractive -Command "$ps_cmd"
    ;;
esac

# Fallback: terminal bell
printf '\a'
