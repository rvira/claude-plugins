#!/usr/bin/env bash
# Claude Code hook: sound + OS notification naming the project + signal file.
# Usage: play-sound.sh <stop|permission>   (hook JSON arrives on stdin)
#
# Identification layers:
#   1. OS banner names the project folder (macOS banner, Linux notify-send,
#      Windows tray toast) — works for CLI, VS Code, and desktop sessions.
#   2. Signal file in ~/.claude-code-chime/ lets the claude-chime VS Code
#      extension raise the toast inside the exact window that finished.
#   3. iTerm2 CLI sessions: the banner also names the window/tab, and can
#      optionally focus that exact tab (CLAUDE_SOUNDS_FOCUS=permission|all).
#
# Security: stdin is size-capped and parsed with a real JSON parser; untrusted
# text reaches osascript only as argv items and PowerShell only via
# environment variables (never interpolated into script source); the iTerm2
# session id is allow-list validated; signal files are written atomically
# under a 0700 directory; the event name is allow-list validated.
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

script_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Extract project name + drop a signal file for the VS Code extension ---
proj=""
cwd_b64=""
if command -v python3 >/dev/null 2>&1; then
  py_out="$(printf '%s' "$payload" | python3 -c '
import base64, json, os, sys, tempfile, time

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
print(base64.b64encode(cwd.encode()).decode() if cwd else "")
' "$event" 2>/dev/null || true)"
  proj="$(printf '%s\n' "$py_out" | sed -n '1p')"
  cwd_b64="$(printf '%s\n' "$py_out" | sed -n '2p')"
  [[ "$cwd_b64" =~ ^[A-Za-z0-9+/=]+$ ]] || cwd_b64=""
fi

if [ "$event" = "permission" ]; then
  title="Claude needs permission"
else
  title="Claude finished responding"
fi
body="Project: ${proj:-unknown}"

# --- iTerm2 session identity (present only when the session runs in iTerm2) ---
# ITERM_SESSION_ID looks like "w0t2p0:UUID": window 0, tab 2, pane 0.
iterm_uuid=""
if [ -n "${ITERM_SESSION_ID:-}" ]; then
  wtp="${ITERM_SESSION_ID%%:*}"
  uuid="${ITERM_SESSION_ID#*:}"
  if [[ "$wtp" =~ ^w([0-9]+)t([0-9]+)p([0-9]+)$ ]]; then
    body="$body • iTerm2 win $((10#${BASH_REMATCH[1]} + 1)) tab $((10#${BASH_REMATCH[2]} + 1))"
  fi
  if [[ "$uuid" =~ ^[A-Fa-f0-9-]{8,64}$ ]]; then
    iterm_uuid="$uuid"
  fi
fi

# Focus the exact iTerm2 tab? Opt-in: CLAUDE_SOUNDS_FOCUS=permission|all
should_focus=0
case "${CLAUDE_SOUNDS_FOCUS:-off}" in
  all) should_focus=1 ;;
  permission) [ "$event" = "permission" ] && should_focus=1 ;;
esac

# --- OS notification + sound, per platform ---
case "$(uname -s)" in
  Darwin)
    # Prefer terminal-notifier: its banners support a real click action
    # (focus the right app/window). osascript banners can only activate
    # Script Editor on click — kept as fallback only.
    tn=""
    for cand in terminal-notifier /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier; do
      if command -v "$cand" >/dev/null 2>&1; then tn="$cand"; break; fi
    done

    if [ -n "$tn" ]; then
      tn_args=(-title "$title" -message "$body")
      if [ -n "${ITERM_SESSION_ID:-}" ]; then
        tn_args+=(-activate com.googlecode.iterm2)
      elif { [ "${TERM_PROGRAM:-}" = "vscode" ] || [ -n "${VSCODE_IPC_HOOK_CLI:-}${VSCODE_PID:-}${VSCODE_CWD:-}${VSCODE_GIT_ASKPASS_MAIN:-}" ]; } && [ -n "$cwd_b64" ]; then
        # cwd crosses into the click command base64-encoded and allow-list
        # validated; focus-vscode.sh re-validates before decoding.
        tn_args+=(-execute "'$script_dir/focus-vscode.sh' $cwd_b64")
      fi
      "$tn" "${tn_args[@]}" >/dev/null 2>&1 &
    else
      # argv-based AppleScript: values are data, never script source
      osascript \
        -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
        -e 'end run' \
        "$body" "$title" >/dev/null 2>&1 &
    fi

    if [ "$should_focus" = 1 ] && [ -n "$iterm_uuid" ]; then
      osascript -e 'on run argv
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if id of s is (item 1 of argv) then
                  set index of w to 1
                  select t
                  select s
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
      end run' "$iterm_uuid" >/dev/null 2>&1 &
    fi

    if [ "$event" = "permission" ]; then
      sound="/System/Library/Sounds/Purr.aiff"
    else
      sound="/System/Library/Sounds/Funk.aiff"
    fi
    [ -f "$sound" ] && exec afplay "$sound"
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      if [ -n "$cwd_b64" ] && notify-send --help 2>&1 | grep -q -- '--action'; then
        # --action (libnotify >= 0.7.10) makes notify-send wait and print the
        # chosen action, so it runs in a background subshell; clicking focuses
        # the project window via the "code" CLI (focus-vscode.sh handles Linux).
        (
          choice="$(notify-send --action=default=Focus "$title" "$body" 2>/dev/null)"
          if [ "$choice" = "default" ]; then
            "$script_dir/focus-vscode.sh" "$cwd_b64" >/dev/null 2>&1
          fi
        ) &
      else
        notify-send "$title" "$body" >/dev/null 2>&1 &
      fi
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
      wav='C:\Windows\Media\Windows Notify.wav'
    else
      wav='C:\Windows\Media\Windows Ding.wav'
    fi
    # Untrusted data (hook payload) crosses into PowerShell via environment
    # variables only — the -Command string below is a fixed literal. The
    # payload is parsed with ConvertFrom-Json inside PowerShell, so Windows
    # needs no python3. Clicking the toast focuses the project window via
    # the "code" CLI when available.
    CLAUDE_NOTIFY_TITLE="$title" CLAUDE_NOTIFY_PAYLOAD="$payload" CLAUDE_NOTIFY_WAV="$wav" \
    exec powershell.exe -NoProfile -NonInteractive -Command '
      $dir = "";
      try { $p = $env:CLAUDE_NOTIFY_PAYLOAD | ConvertFrom-Json; if ($p.cwd -is [string]) { $dir = $p.cwd } } catch {}
      $proj = "unknown";
      if ($dir) { $proj = Split-Path -Leaf $dir }
      Add-Type -AssemblyName System.Windows.Forms, System.Drawing;
      $n = New-Object System.Windows.Forms.NotifyIcon;
      $n.Icon = [System.Drawing.SystemIcons]::Information;
      $n.Visible = $true;
      $n.BalloonTipTitle = $env:CLAUDE_NOTIFY_TITLE;
      $n.BalloonTipText = "Project: " + $proj;
      if ($dir -and (Test-Path -LiteralPath $dir) -and (Get-Command code -ErrorAction SilentlyContinue)) {
        Register-ObjectEvent -InputObject $n -EventName BalloonTipClicked -MessageData $dir -Action {
          Start-Process -FilePath "code" -ArgumentList ([char]34 + $event.MessageData + [char]34)
        } | Out-Null
      }
      $n.ShowBalloonTip(5000);
      (New-Object System.Media.SoundPlayer $env:CLAUDE_NOTIFY_WAV).PlaySync();
      Start-Sleep -Seconds 6;
      $n.Dispose()
    '
    ;;
esac

# Fallback: terminal bell
printf '\a'
