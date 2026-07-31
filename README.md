# claude-plugins

Rishabh's Claude Code plugin **marketplace** (`rishabh-plugins`), hosting the
**claude-sounds** plugin and its companion VS Code extension **Claude Chime**:
know **that** Claude finished, **where** it finished, and **what** it finished
— without watching the screen.

## Features

- 🔔 **Sound on every event** — one sound when Claude finishes a turn
  (`Stop`), another when it's waiting for your approval (`PermissionRequest`).
- 🏷️ **Banners that name the project** — the OS notification says which
  project fired: *"Claude finished responding — Project: my-app"*.
- 💬 **Banners that say what happened** — the prompt Claude just answered
  (read from the session transcript) or the exact tool/command it wants to
  run (*"Bash: npm install"*).
- 🎯 **The right VS Code window toasts** — with many windows open, Claude
  Chime raises the notification inside the exact window whose session fired;
  the others stay silent.
- 🖱️ **Clickable banners** — click to focus the VS Code window (or iTerm2)
  for that project (per-OS requirements below).
- 🧭 **iTerm2 tab identification + auto-focus** — CLI sessions get
  *"iTerm2 win 1 tab 3"* in the banner, and can auto-focus that exact tab
  when Claude needs permission.
- 🖥️ **Cross-platform** — macOS, Linux, and Windows (Git Bash), degrading
  gracefully when an optional dependency is missing.
- 🔒 **Hardened by default** — untrusted text (prompts, paths, tool args) is
  validated, sanitized, and passed only as data (argv/env), never as script
  source; signal files live in an owner-only directory and auto-prune.
- 🔕 **Privacy-aware** — prompt snippets (max 140 chars) appear in
  notifications; consider Do Not Disturb when screen-sharing.

## Marketplace vs plugin — two different things in this repo

| Concept | What it is | Where it lives |
|---|---|---|
| **Marketplace** | A catalog. It's just a list that tells Claude Code which plugins exist in this repo and where to find them. It contains no behavior of its own. | Repo root: `.claude-plugin/marketplace.json` |
| **Plugin** | An actual unit of functionality that gets installed (manifest + hooks + scripts). Each plugin is fully self-contained in its own folder. | `plugins/<plugin-name>/` |

You `add` the marketplace once, then `install` plugins from it.

## Repository layout

```
claude-plugins/
│
├── .claude-plugin/
│   └── marketplace.json     ← MARKETPLACE manifest: names the marketplace
│                              ("rishabh-plugins") and lists every plugin
│                              folder under plugins/. Catalog only — no logic.
│
├── README.md                ← this file
├── TROUBLESHOOTING.md       ← per-OS symptom → diagnosis → fix guide
│
├── plugins/                 ← one self-contained folder per PLUGIN
│   └── claude-sounds/
│       ├── .claude-plugin/
│       │   └── plugin.json  ← PLUGIN manifest: this plugin's name, version,
│       │                      description, author. What `claude plugin
│       │                      install` reads.
│       ├── hooks/
│       │   └── hooks.json   ← WHEN to act: binds Claude Code events
│       │                      (Stop, PermissionRequest) to a command.
│       └── scripts/
│           ├── play-sound.sh   ← WHAT to do: sound + OS banner (project +
│           │                     prompt/tool detail) + signal file.
│           └── focus-vscode.sh ← click-action helper: focuses the VS Code
│                                 window that has the project open.
│
└── vscode/                  ← NOT a Claude plugin: a real VS Code extension.
    └── claude-chime/          Watches the signal files from claude-sounds and
                               shows the toast in the exact window that finished.
```

The two `.claude-plugin/` folders are **not** duplicates: the root one holds
the *marketplace* manifest, the per-plugin one holds that *plugin's* manifest.
Claude Code requires exactly these names and locations.

---

# Installation

## 1. The claude-sounds plugin (required — everything starts here)

From GitHub:

```bash
# 1. Register the catalog (once)
claude plugin marketplace add rvira/claude-plugins

# 2. Install the plugin from it
claude plugin install claude-sounds@rishabh-plugins
```

Or from a local clone:

```bash
claude plugin marketplace add /path/to/claude-plugins
claude plugin install claude-sounds@rishabh-plugins
```

**Restart any open sessions** (CLI, VS Code windows, desktop app) — plugins
are resolved when a session starts. Later updates: `claude plugin update
claude-sounds@rishabh-plugins` (then restart again).

To try it without installing:

```bash
claude --plugin-dir /path/to/claude-plugins/plugins/claude-sounds
```

> **Avoid double sounds:** if you previously added `Stop`/`PermissionRequest`
> `afplay` hooks directly in `~/.claude/settings.json`, remove them once this
> plugin is installed — otherwise both fire and you hear each sound twice.

## 2. Claude Chime VS Code extension (recommended if you use VS Code)

Gives you the per-window toast. Install the packaged `.vsix`:

```bash
code --install-extension vscode/claude-chime/claude-chime-0.4.0.vsix
```

(If `code` isn't found: in VS Code, Cmd/Ctrl+Shift+P → **"Shell Command:
Install 'code' command in PATH"**.) Reload VS Code windows after installing.
One install covers every window — each window runs its own instance.

## 3. Optional dependencies — install only what you want

| Feature | OS | What to install | Notes |
|---|---|---|---|
| Clickable banners | macOS | `brew install terminal-notifier` | **Then allow it**: System Settings → Notifications → terminal-notifier → Allow. Skipping this silently kills ALL banners — see [TROUBLESHOOTING.md](TROUBLESHOOTING.md). Claude Chime also offers this install on first activation. |
| Banner + sound | Linux (Debian/Ubuntu) | `sudo apt install libnotify-bin pulseaudio-utils sound-theme-freedesktop` | Fedora: `sudo dnf install libnotify pulseaudio-utils sound-theme-freedesktop`. Clickable banners additionally need libnotify ≥ 0.7.10 (Ubuntu 22.04+). |
| Click-to-focus | Linux / Windows | `code` on PATH | Linux: the VS Code "Install 'code' command" step above. Windows: the installer's "Add to PATH" checkbox (verify with `where code`). |
| Prompt snippets in the Windows toast | Windows | [Python 3](https://www.python.org/downloads/windows/) with "Add python.exe to PATH" checked | Without it the toast still shows the project name (parsed in PowerShell) — just not the prompt text. |
| iTerm2 auto-focus | macOS | Nothing to install — add to `~/.claude/settings.json`: `{ "env": { "CLAUDE_SOUNDS_FOCUS": "permission" } }` | `permission` (recommended) focuses the tab only when Claude is blocked; `all` also on completion. First use: allow the macOS Automation prompt ("…wants to control iTerm2"). |

No optional dependency is required — missing pieces degrade gracefully
(plain banner instead of clickable, project name instead of prompt text,
terminal bell as the last resort).

## 4. Verify it works

Fire a fake event by hand from any terminal:

```bash
echo "{\"cwd\":\"$PWD\"}" | bash ~/.claude/plugins/marketplaces/rishabh-plugins/plugins/claude-sounds/scripts/play-sound.sh stop
```

You should hear the sound and see a banner naming the current folder — and if
that folder is open in VS Code with Claude Chime installed, a toast in that
window. Anything missing → [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

# claude-sounds

Sound **and** project-named OS notification for Claude Code:

| Event | When it fires | Sound (macOS) | Notification |
|---|---|---|---|
| `Stop` | Claude finishes a turn | Funk | "Claude finished responding — Project: \<folder\>" + the **prompt it answered** (read from the session transcript) |
| `PermissionRequest` | Claude is waiting for your approval | Purr | "Claude needs permission — Project: \<folder\>" + the **tool/command requested** (e.g. `Bash: npm install`) |

The same detail is written into the signal file, so the Claude Chime VS Code
toast also says what completed. Privacy note: prompt snippets (max 140 chars)
appear in OS notifications and in `~/.claude-code-chime/` signal files
(owner-only permissions, auto-pruned after an hour).

Because Claude Code's CLI, VS Code extension, and desktop app all run the same
local engine and load the same plugins, installing this once enables it in
all three.

## Identifying the window/session

The hook's stdin JSON carries the session's `cwd`, so:

1. The OS notification **names the project folder** that fired.
2. The script drops a signal file in `~/.claude-code-chime/`; the companion
   [Claude Chime](vscode/claude-chime/) VS Code extension watches it and
   raises the toast **inside the exact VS Code window** whose workspace
   matches — other windows stay silent.

## How it's put together

| File | Role |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest — name, version, description. What `claude plugin install` reads. |
| `hooks/hooks.json` | The **when** — binds the `Stop` and `PermissionRequest` events to the script below. |
| `scripts/play-sound.sh` | The **what** — plays the right sound, shows the OS notification (project + prompt/tool detail), writes the signal file. |
| `scripts/focus-vscode.sh` | Click-action helper — validates its input, then focuses the VS Code window that has the project open. |

## iTerm2 tab identification

CLI sessions running in iTerm2 inherit `ITERM_SESSION_ID`, so:

- The banner also names the spot: `Project: foo • iTerm2 win 1 tab 3`.
- **Auto-focus** — jump straight to that tab. Opt in via env var in
  `~/.claude/settings.json`:

  ```json
  { "env": { "CLAUDE_SOUNDS_FOCUS": "permission" } }
  ```

  `permission` focuses the tab only when Claude is blocked waiting for your
  approval (recommended); `all` also focuses on completion; unset/`off`
  disables. First use triggers a one-time macOS Automation prompt
  ("...wants to control iTerm2") — click Allow.

Terminal.app and VS Code terminals don't set `ITERM_SESSION_ID`; they get the
project-named banner without the tab label (VS Code windows are covered by
the Claude Chime extension instead).

## Platform support

- **macOS** — `afplay` system sounds + Notification Center banner
  (terminal-notifier when installed, `osascript` otherwise).
- **Linux** — `paplay` freedesktop sounds + `notify-send` banner; falls back to the terminal bell.
- **Windows** — via Git Bash: PowerShell system-WAV sound + tray balloon toast in the notification center.
- **Other platforms** — terminal bell (`\a`).

Signal files / project names / prompt snippets need `python3` on PATH
(present by default on macOS and most Linux distros); without it the plugin
degrades to sound-only (on Windows the project name still works — it's
parsed inside PowerShell).

## Clickable banners — per OS

| OS | Click behavior | Requirement |
|---|---|---|
| macOS | Focuses the VS Code window with that project (or brings iTerm2 forward for CLI sessions) | `brew install terminal-notifier` **+ allow it in System Settings → Notifications** — the Claude Chime extension offers this install on first activation |
| Linux | Focuses the project window via the `code` CLI | libnotify ≥ 0.7.10 (`notify-send --action`; GNOME/KDE on Ubuntu 22.04+ qualify) — older libnotify falls back to a non-clickable banner |
| Windows | Toast click focuses the project window via the `code` CLI | `code` on PATH (VS Code installer default) |

Without terminal-notifier, macOS falls back to `osascript`, whose banners
post as "Script Editor" — macOS offers no click action there, so clicking
just opens Script Editor. That's a platform limitation of `display
notification`, not a bug.

> **Banners not showing, not clickable, or silent after installing
> terminal-notifier?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — a
> symptom → diagnosis → fix guide for macOS, Linux, and Windows, including
> the exact debugging path for the "terminal-notifier silently swallows all
> banners" permission trap.

## Customizing sounds

Edit `scripts/play-sound.sh` — each OS branch maps the `stop` / `permission`
event to a sound file. Browse `/System/Library/Sounds/` on macOS for options.

---

# Claude Chime (VS Code extension)

**Which VS Code window did Claude finish in?** With several windows and Claude
Code sessions running, sounds alone don't tell you where to look. Claude Chime
raises the notification **inside the exact window** whose session finished or
is waiting for permission, labeled with the workspace name and what it was
about: *Claude finished responding — my-app: "fix the login bug"*.

Install: see [Installation → step 2](#2-claude-chime-vs-code-extension-recommended-if-you-use-vs-code).

On first activation (macOS) it checks for `terminal-notifier` and offers a
one-click Homebrew install — VS Code extensions can't run install scripts at
download time (the Marketplace forbids arbitrary code on install), so an
activation-time prompt is the sanctioned way to set up native dependencies.

## How it works

1. The claude-sounds plugin's hook receives the session's `cwd` on every
   `Stop` / `PermissionRequest` event and drops a signal file in
   `~/.claude-code-chime/`.
2. Every VS Code window runs its own instance of this extension. Each instance
   watches that directory and reacts **only** when the signal's `cwd` is inside
   one of its own workspace folders.
3. Result: the toast appears in the right window; other windows stay silent.
   The plugin's OS-level notification also names the project, covering
   sessions with no VS Code window at all (plain CLI, desktop app).

## Requirements

The `claude-sounds` plugin must be installed (it writes the signal files) —
see [Installation](#installation) above.

## Commands & settings

Command Palette: **Claude Chime: Test Notification** (fires a real signal
through the full pipeline) and **Claude Chime: Toggle Notifications (This
Window)** (per-window mute). A **Get Started walkthrough** (Help → Get
Started) covers the plugin install, macOS clickable banners, and a live test.

| Setting | Default | Meaning |
|---|---|---|
| `claudeChime.enabled` | `true` | Show notifications in this window. |
| `claudeChime.notifyOn` | `both` | Which events notify: `both`, `stop`, or `permission`. |
| `claudeChime.showPromptText` | `true` | Include the answered prompt / requested command; off = project name only (privacy). |

Signal files are written by a bash hook script — macOS and Linux out of the
box, Windows via Git Bash (requires `python3` on PATH for signal writing).

---

# Adding a new plugin

1. Create `plugins/<new-name>/` containing its own
   `.claude-plugin/plugin.json` (plus `hooks/`, `commands/`, `agents/`,
   `skills/` — whatever the plugin needs).
2. Add an entry for it to the `plugins` array in
   `.claude-plugin/marketplace.json`, with `"source": "./plugins/<new-name>"`.
3. Verify with `claude plugin validate .`
