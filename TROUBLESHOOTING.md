# Troubleshooting

The notification pipeline, so you know where to look:

```
Claude Code event (Stop / PermissionRequest)
  → hooks.json runs scripts/play-sound.sh with the event JSON on stdin
      → plays the sound
      → shows the OS banner (project + prompt/tool detail)
      → writes a signal file to ~/.claude-code-chime/
          → Claude Chime (VS Code) toasts in the matching window
```

**Universal first step — fire a test event by hand** (any OS, from a terminal):

```bash
echo "{\"cwd\":\"$PWD\"}" | bash ~/.claude/plugins/marketplaces/rishabh-plugins/plugins/claude-sounds/scripts/play-sound.sh stop
```

Sound but no banner → notification permission/daemon problem (see your OS
below). Nothing at all → the plugin isn't installed/enabled, or the session
predates it (plugin changes only apply to **restarted** sessions).

---

## macOS

### Banners stopped completely after installing terminal-notifier

This one bit us. terminal-notifier posts notifications under **its own app
identity**, so it needs its own permission — and its first-use prompt is easy
to miss. Until granted, macOS drops every banner **silently**: the hook runs,
the sound plays, `terminal-notifier` exits 0, and nothing appears.

Diagnose — check whether it's registered but never approved:

```bash
plutil -p ~/Library/Preferences/com.apple.ncprefs.plist | grep -A6 -i terminal-notifier
```

An entry existing while no banners show means "registered, not allowed".

**Fix A — keep clickable banners:** System Settings → Notifications →
terminal-notifier → **Allow Notifications**, style Banners or Alerts.
Verify: `terminal-notifier -title test -message hello`.

**Fix B — the simple way out (what we did):**

```bash
brew uninstall terminal-notifier
```

The plugin auto-falls back to `osascript` banners (posted as "Script
Editor", which is usually already allowed). You lose click-to-focus on the
banner — the Claude Chime toast still identifies the VS Code window, and
iTerm2 focus-on-permission still works (it's AppleScript, independent of
terminal-notifier). Claude Chime will offer to reinstall terminal-notifier
once — click **Don't ask again**.

### Clicking a banner opens Script Editor

You're on the `osascript` fallback. macOS offers no click actions for
`display notification` — this is a platform limitation, not a bug. Install
+ permit terminal-notifier (Fix A above) if you want click-to-focus.

### No banners on a fresh install

- System Settings → Notifications → **Script Editor** (fallback) or
  **terminal-notifier** must be allowed.
- A **Focus / Do Not Disturb** mode suppresses banners from every app.

### iTerm2 tab doesn't get focused on permission prompts

- Opt-in required: `{ "env": { "CLAUDE_SOUNDS_FOCUS": "permission" } }` in
  `~/.claude/settings.json`.
- First use triggers a macOS Automation prompt ("…wants to control iTerm2")
  — it must be allowed (System Settings → Privacy & Security → Automation).

---

## Linux

### No banner

- `notify-send` missing → Debian/Ubuntu: `sudo apt install libnotify-bin`,
  Fedora: `sudo dnf install libnotify`.
- A notification daemon must be running. GNOME/KDE ship one; bare window
  managers need e.g. `dunst`.
- WSL: there is no Linux notification daemon talking to Windows — expect
  sound/bell only.

### Banner shows but isn't clickable

Click actions need `notify-send --action` (libnotify ≥ 0.7.10 — Ubuntu
22.04+ qualifies). Check: `notify-send -v` and
`notify-send --help | grep -- --action`. Older libnotify automatically gets
a plain, non-clickable banner.

### Click does nothing

The click focuses the project through the `code` CLI — it must be on PATH
(`which code`). In VS Code: Cmd/Ctrl+Shift+P → "Shell Command: Install
'code' command in PATH" (or install via your package manager).

### No sound

`sudo apt install pulseaudio-utils sound-theme-freedesktop` (provides
`paplay` and the freedesktop sounds). Missing pieces degrade to the
terminal bell.

---

## Windows (Git Bash)

### Nothing fires at all

Hooks run through bash — Git for Windows must be installed (it is, if
you're using Claude Code there).

### No toast

- Settings → System → Notifications: notifications must be on for the
  desktop; check **Focus Assist / Do Not Disturb** isn't suppressing them.
- The toast is a tray balloon (NotifyIcon); some strict "quiet hours"
  configurations hide balloons entirely.

### Toast shows the project but not the prompt text

Prompt snippets are extracted with `python3`, which Git Bash doesn't ship.
Install Python 3 for Windows with "Add python.exe to PATH" checked. The
project name works without it (parsed inside PowerShell).

### Click does nothing

Clicking focuses the project via the `code` CLI — the VS Code installer's
"Add to PATH" option must have been selected (verify with `where code`).

---

## All platforms

| Symptom | Cause / fix |
|---|---|
| Changes to the plugin don't apply | Sessions resolve the plugin at start — restart CLI sessions and VS Code windows. |
| Every sound plays twice | Leftover `Stop`/`PermissionRequest` hooks in `~/.claude/settings.json` from before the plugin — delete the `hooks` block. |
| No VS Code toast | Claude Chime installed? The session's folder must be (inside) a workspace folder of that window. |
| Signal files pile up in `~/.claude-code-chime/` | Signals written but no window matched them — normal for CLI-only sessions; pruned after an hour. |
| Which plugin version is a session using? | `grep installPath ~/.claude/plugins/installed_plugins.json` — update with `claude plugin update claude-sounds@rishabh-plugins`. |
