# Claude Chime

**Which VS Code window did Claude finish in?** With several windows and Claude
Code sessions running, sounds alone don't tell you where to look. Claude Chime
raises the notification **inside the exact window** whose session finished or
is waiting for permission, labeled with the workspace name.

## How it works

1. The [claude-sounds](https://github.com/rvira/claude-plugins) Claude Code
   plugin's hook receives the session's `cwd` on every `Stop` /
   `PermissionRequest` event and drops a signal file in `~/.claude-code-chime/`.
2. Every VS Code window runs its own instance of this extension. Each instance
   watches that directory and reacts **only** when the signal's `cwd` is inside
   one of its own workspace folders.
3. Result: the toast appears in the right window; other windows stay silent.
   The plugin's OS-level notification also names the project, covering
   sessions with no VS Code window at all (plain CLI, desktop app).

## Requirements

- The `claude-sounds` Claude Code plugin (writes the signal files):

  ```bash
  claude plugin marketplace add rvira/claude-plugins
  claude plugin install claude-sounds@rishabh-plugins
  ```

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `claudeChime.enabled` | `true` | Show notifications in this window. |

## Platform notes

Signal files are written by a bash hook script — macOS and Linux out of the
box, Windows via Git Bash (requires `python3` on PATH for signal writing).
