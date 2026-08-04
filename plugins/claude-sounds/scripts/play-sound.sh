#!/usr/bin/env bash
# Claude Code hook: sound + OS notification naming the project + what ran.
# Usage: play-sound.sh <stop|permission>   (hook JSON arrives on stdin)
#
# Security contract: all untrusted input (hook payload, transcript text,
# env vars) is size-capped, allow-list validated, and crosses into
# osascript/terminal-notifier/PowerShell only as data (argv or env vars) —
# never interpolated into script source.
set -u

case "${1:-}" in
  stop|permission) event="$1" ;;
  *) event="stop" ;;
esac

# Payload read is skipped on a TTY so the script can be run by hand.
payload=""
if [ ! -t 0 ]; then
  payload="$(head -c 16384 2>/dev/null || true)"
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"

proj=""
cwd_b64=""
snippet=""
if command -v python3 >/dev/null 2>&1; then
  py_out="$(printf '%s' "$payload" | python3 -c '
import base64, json, os, sys, tempfile, time

event = sys.argv[1]

def clean(text, limit=140):
    text = " ".join(str(text).split())
    text = "".join(ch if ch.isprintable() else " " for ch in text)
    text = text.lstrip("-[ ")                    # terminal-notifier option quirk
    return (text[: limit - 1] + "\u2026") if len(text) > limit else text

data = {}
try:
    loaded = json.load(sys.stdin)
    if isinstance(loaded, dict):
        data = loaded
except Exception:
    pass

cwd = data.get("cwd") if isinstance(data.get("cwd"), str) else ""

def last_user_prompt(path):
    try:
        if not (isinstance(path, str) and path.endswith(".jsonl") and os.path.isfile(path)):
            return ""
        with open(path, "rb") as f:
            f.seek(max(0, os.path.getsize(path) - 262144))
            lines = f.read().decode("utf-8", "ignore").splitlines()
        for line in reversed(lines):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if not isinstance(obj, dict) or obj.get("type") != "user" or obj.get("isMeta"):
                continue
            content = (obj.get("message") or {}).get("content")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
                    continue
                text = " ".join(
                    c.get("text", "") for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                )
            else:
                continue
            text = text.strip()
            if not text or text.startswith("<"):   # <command-name> wrappers etc.
                continue
            return text
    except Exception:
        pass
    return ""

snippet = ""
if event == "permission":
    tool = data.get("tool_name")
    tool_input = data.get("tool_input") if isinstance(data.get("tool_input"), dict) else {}
    brief = tool_input.get("command") or tool_input.get("file_path") or ""
    if isinstance(tool, str) and tool:
        snippet = clean(tool + (": " + str(brief) if brief else ""))
if not snippet:
    snippet = clean(last_user_prompt(data.get("transcript_path")))

sig_dir = os.path.join(os.path.expanduser("~"), ".claude-code-chime")
try:
    os.makedirs(sig_dir, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=sig_dir, suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump({"event": event, "cwd": cwd, "detail": snippet, "ts": time.time()}, f)
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
print(snippet)
' "$event" 2>/dev/null || true)"
  proj="$(printf '%s\n' "$py_out" | sed -n '1p')"
  cwd_b64="$(printf '%s\n' "$py_out" | sed -n '2p')"
  snippet="$(printf '%s\n' "$py_out" | sed -n '3p')"
  [[ "$cwd_b64" =~ ^[A-Za-z0-9+/=]+$ ]] || cwd_b64=""
fi

if [ "$event" = "permission" ]; then
  title="Claude needs permission"
else
  title="Claude finished responding"
fi
body="Project: ${proj:-unknown}"

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

should_focus=0
case "${CLAUDE_SOUNDS_FOCUS:-off}" in
  all) should_focus=1 ;;
  permission) [ "$event" = "permission" ] && should_focus=1 ;;
esac

# Banner auto-dismiss after N seconds; 0 = leave it up. Untrusted env var —
# validated to a short integer before reaching sleep/PowerShell.
dismiss_secs="${CLAUDE_SOUNDS_DISMISS_SECS:-8}"
[[ "$dismiss_secs" =~ ^[0-9]{1,3}$ ]] || dismiss_secs=8

case "$(uname -s)" in
  Darwin)
    # terminal-notifier preferred: it supports a real click action and can be
    # removed programmatically; osascript is fallback only.
    tn=""
    for cand in terminal-notifier /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier; do
      if command -v "$cand" >/dev/null 2>&1; then tn="$cand"; break; fi
    done

    if [ -n "$tn" ]; then
      # Unique group id so the timed removal only pulls down this banner.
      tn_group="claude-sounds-$$-${RANDOM}"
      if [ -n "$snippet" ]; then
        tn_args=(-group "$tn_group" -title "$title" -subtitle "$body" -message "$snippet")
      else
        tn_args=(-group "$tn_group" -title "$title" -message "$body")
      fi
      if [ -n "${ITERM_SESSION_ID:-}" ]; then
        tn_args+=(-activate com.googlecode.iterm2)
      elif { [ "${TERM_PROGRAM:-}" = "vscode" ] || [ -n "${VSCODE_IPC_HOOK_CLI:-}${VSCODE_PID:-}${VSCODE_CWD:-}${VSCODE_GIT_ASKPASS_MAIN:-}" ]; } && [ -n "$cwd_b64" ]; then
        # cwd crosses into the click command base64-encoded and allow-list
        # validated; focus-vscode.sh re-validates before decoding.
        tn_args+=(-execute "'$script_dir/focus-vscode.sh' $cwd_b64")
      fi
      "$tn" "${tn_args[@]}" >/dev/null 2>&1 &
      if [ "$dismiss_secs" -gt 0 ]; then
        # "Alerts"-style notifications stay on screen until removed.
        ( sleep "$dismiss_secs" && "$tn" -remove "$tn_group" ) >/dev/null 2>&1 &
      fi
    else
      # No programmatic removal here: osascript banners follow the user's
      # Script Editor notification style. Values are argv data, never source.
      osascript \
        -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title (item 2 of argv) subtitle (item 3 of argv)' \
        -e 'end run' \
        "${snippet:-$body}" "$title" "$body" >/dev/null 2>&1 &
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
      nbody="$body"
      [ -n "$snippet" ] && nbody="$body"$'\n'"$snippet"
      if [ -n "$cwd_b64" ] && notify-send --help 2>&1 | grep -q -- '--action'; then
        # --action makes notify-send block until clicked/expired, so it runs
        # in a background subshell.
        (
          choice="$(notify-send --action=default=Focus "$title" "$nbody" 2>/dev/null)"
          if [ "$choice" = "default" ]; then
            "$script_dir/focus-vscode.sh" "$cwd_b64" >/dev/null 2>&1
          fi
        ) &
      else
        notify-send "$title" "$nbody" >/dev/null 2>&1 &
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
    # Untrusted data crosses into PowerShell via env vars only — the -Command
    # string is a fixed literal. Payload is parsed in PowerShell (no python3
    # needed on Windows).
    CLAUDE_NOTIFY_TITLE="$title" CLAUDE_NOTIFY_PAYLOAD="$payload" CLAUDE_NOTIFY_SNIPPET="$snippet" CLAUDE_NOTIFY_WAV="$wav" CLAUDE_NOTIFY_DISMISS="$dismiss_secs" \
    exec powershell.exe -NoProfile -NonInteractive -Command '
      $dismiss = 8;
      try { $v = [int]$env:CLAUDE_NOTIFY_DISMISS; if ($v -ge 1 -and $v -le 300) { $dismiss = $v } } catch {}
      $dir = "";
      try { $p = $env:CLAUDE_NOTIFY_PAYLOAD | ConvertFrom-Json; if ($p.cwd -is [string]) { $dir = $p.cwd } } catch {}
      $proj = "unknown";
      if ($dir) { $proj = Split-Path -Leaf $dir }
      $text = "Project: " + $proj;
      if ($env:CLAUDE_NOTIFY_SNIPPET) { $text = $text + " - " + $env:CLAUDE_NOTIFY_SNIPPET }
      if ($text.Length -gt 250) { $text = $text.Substring(0, 250) }
      Add-Type -AssemblyName System.Windows.Forms, System.Drawing;
      $n = New-Object System.Windows.Forms.NotifyIcon;
      $n.Icon = [System.Drawing.SystemIcons]::Information;
      $n.Visible = $true;
      $n.BalloonTipTitle = $env:CLAUDE_NOTIFY_TITLE;
      $n.BalloonTipText = $text;
      if ($dir -and (Test-Path -LiteralPath $dir) -and (Get-Command code -ErrorAction SilentlyContinue)) {
        Register-ObjectEvent -InputObject $n -EventName BalloonTipClicked -MessageData $dir -Action {
          Start-Process -FilePath "code" -ArgumentList ([char]34 + $event.MessageData + [char]34)
        } | Out-Null
      }
      $n.ShowBalloonTip($dismiss * 1000);
      (New-Object System.Media.SoundPlayer $env:CLAUDE_NOTIFY_WAV).PlaySync();
      Start-Sleep -Seconds $dismiss;
      # Dispose clears the toast from the screen and the Action Center.
      $n.Dispose()
    '
    ;;
esac

printf '\a'
