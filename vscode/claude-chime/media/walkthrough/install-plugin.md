# Install the claude-sounds plugin

Claude Chime is the display side; the **claude-sounds** Claude Code plugin is
the sensor. It hooks Claude Code's `Stop` and `PermissionRequest` events and
writes the signal files this extension watches.

Run once in any terminal:

```bash
claude plugin marketplace add rvira/claude-plugins
claude plugin install claude-sounds@rishabh-plugins
```

Then **restart open Claude Code sessions** (plugins load at session start).

You also get, independently of VS Code: a sound per event and an OS banner
naming the project and what happened.
