# claude-sounds

Sound **and** project-named OS notification for Claude Code:

| Event | When it fires | Sound (macOS) | Notification |
|---|---|---|---|
| `Stop` | Claude finishes a turn | Funk | "Claude finished responding — Project: \<folder\>" |
| `PermissionRequest` | Claude is waiting for your approval | Purr | "Claude needs permission — Project: \<folder\>" |

Because Claude Code's CLI, VS Code extension, and desktop app all run the same
local engine and load the same plugins, installing this once enables it in
all three.

## Which window/session was it?

The hook's stdin JSON carries the session's `cwd`, so:

1. The OS notification **names the project folder** that fired.
2. The script drops a signal file in `~/.claude-code-chime/`; the companion
   [claude-chime](../../vscode/claude-chime/) VS Code extension watches it and
   raises the toast **inside the exact VS Code window** whose workspace
   matches — other windows stay silent.

## How it's put together

| File | Role |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest — name, version, description. What `claude plugin install` reads. |
| `hooks/hooks.json` | The **when** — binds the `Stop` and `PermissionRequest` events to the script below. |
| `scripts/play-sound.sh` | The **what** — plays the right sound, shows the OS notification, writes the signal file. |

## Install

From GitHub:

```bash
claude plugin marketplace add rvira/claude-plugins
claude plugin install claude-sounds@rishabh-plugins
```

Or from a local clone:

```bash
claude plugin marketplace add /path/to/claude-plugins
claude plugin install claude-sounds@rishabh-plugins
```

Restart any open VS Code / desktop sessions so they pick up the plugin.

To try it without installing:

```bash
claude --plugin-dir /path/to/claude-plugins/plugins/claude-sounds
```

> **Avoid double sounds:** if you previously added `Stop`/`PermissionRequest`
> `afplay` hooks directly in `~/.claude/settings.json`, remove them once this
> plugin is installed — otherwise both fire and you hear each sound twice.

## Platform support

- **macOS** — `afplay` system sounds + `osascript` notification.
- **Linux** — `paplay` freedesktop sounds + `notify-send`; falls back to the terminal bell.
- **Windows** — via Git Bash: PowerShell `Media.SoundPlayer` with system WAVs (sound only).
- **Anything else** — terminal bell (`\a`).

Signal files / project names need `python3` on PATH (present by default on
macOS and most Linux distros); without it the plugin degrades to sound-only.

## Web (claude.ai/code)?

Cloud web sessions execute on a remote sandbox, so a hook there cannot play
audio on your machine — this is a platform limitation, not a plugin gap. Two
practical substitutes:

- Web sessions connected to your **local machine via Remote Control** run the
  local engine, so these hooks fire and sounds play normally.
- For pure cloud sessions, enable mobile/desktop push notifications
  (`inputNeededNotifEnabled` in settings) to get pinged when input is needed.

## Customizing sounds

Edit `scripts/play-sound.sh` — each OS branch maps the `stop` / `permission`
event to a sound file. Browse `/System/Library/Sounds/` on macOS for options.
