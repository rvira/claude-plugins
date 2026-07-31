# Claude Chime

**Which VS Code window did Claude Code finish in?** With several windows and
Claude sessions running, sounds alone don't tell you where to look. Claude
Chime raises the notification **inside the exact window** whose session
finished or is waiting for permission — labeled with the workspace name and
what it was about:

> Claude finished responding — my-app: "fix the login bug and add tests"

## Features

- Per-window toasts: only the window whose workspace matches the finished
  session notifies; the rest stay silent.
- Says what happened: shows the prompt Claude answered, or the tool/command
  it wants permission for.
- Offers optional native dependencies at first activation (macOS:
  `terminal-notifier` for clickable OS banners) — one click, or "Don't ask
  again".

## Requirements

Works together with the **claude-sounds** Claude Code plugin, which emits
the signal files this extension watches:

```bash
claude plugin marketplace add rvira/claude-plugins
claude plugin install claude-sounds@rishabh-plugins
```

Full setup, per-OS options, and troubleshooting:
[github.com/rvira/claude-plugins](https://github.com/rvira/claude-plugins).

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `claudeChime.enabled` | `true` | Show notifications in this window. |

## How it works

The claude-sounds hook writes a small JSON signal (event, project `cwd`, and
a short detail snippet) to `~/.claude-code-chime/` on every `Stop` /
`PermissionRequest` event. Each VS Code window runs its own instance of this
extension; an instance toasts only when the signal's `cwd` falls inside one
of its own workspace folders, then consumes the file. Signals are size-capped,
parsed defensively, sanitized before display, and auto-pruned.
