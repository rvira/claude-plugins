# claude-plugins

Rishabh's Claude Code plugin **marketplace** (`rishabh-plugins`), hosting one or
more **plugins** — currently just `claude-sounds`.

There are two different things in this repo, and they're easy to conflate:

| Concept | What it is | Where it lives |
|---|---|---|
| **Marketplace** | A catalog. It's just a list that tells Claude Code which plugins exist in this repo and where to find them. It contains no behavior of its own. | Repo root: `.claude-plugin/marketplace.json` |
| **Plugin** | An actual unit of functionality that gets installed (manifest + hooks + scripts). Each plugin is fully self-contained in its own folder. | `plugins/<plugin-name>/` |

You `add` the marketplace once, then `install` plugins from it.

## Repository layout — what each file is

```
claude-plugins/
│
├── .claude-plugin/
│   └── marketplace.json     ← MARKETPLACE manifest: names the marketplace
│                              ("rishabh-plugins") and lists every plugin
│                              folder under plugins/. Catalog only — no logic.
│
├── README.md                ← this file (documents the marketplace)
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
│       ├── scripts/
│       │   └── play-sound.sh ← WHAT to do: plays the sound, shows an OS
│       │                       notification naming the project, and writes
│       │                       a signal file for the VS Code extension.
│       └── README.md        ← docs for this plugin specifically
│
└── vscode/                  ← NOT a Claude plugin: a real VS Code extension,
    └── claude-chime/          published to the VS Code Marketplace. Watches
                               the signal files from claude-sounds and shows
                               the toast in the exact window that finished.
```

Note the two `.claude-plugin/` folders are **not** duplicates: the root one
holds the *marketplace* manifest, the per-plugin one holds that *plugin's*
manifest. Claude Code requires exactly these names and locations.

## Install

```bash
# 1. Register the catalog (once)
claude plugin marketplace add rvira/claude-plugins

# 2. Install a plugin from it
claude plugin install claude-sounds@rishabh-plugins
```

## Available plugins

| Plugin | What it does |
|---|---|
| [claude-sounds](plugins/claude-sounds/) | Sound + OS notification naming the project when Claude finishes a turn (`Stop`) or a permission prompt appears (`PermissionRequest`). macOS, Linux, Windows (Git Bash). See its [README](plugins/claude-sounds/README.md). |

## Companion VS Code extension

[vscode/claude-chime](vscode/claude-chime/) solves "**which** VS Code window
finished?" when several windows run Claude sessions: claude-sounds writes a
signal file carrying the session's `cwd`, and each window's claude-chime
instance shows the toast only when that `cwd` matches its own workspace.
Install the `.vsix` locally (`code --install-extension claude-chime-0.1.0.vsix`)
or from the VS Code Marketplace once published.

## Adding a new plugin

1. Create `plugins/<new-name>/` containing its own
   `.claude-plugin/plugin.json` (plus `hooks/`, `commands/`, `agents/`,
   `skills/` — whatever the plugin needs).
2. Add an entry for it to the `plugins` array in
   `.claude-plugin/marketplace.json`, with `"source": "./plugins/<new-name>"`.
3. Verify with `claude plugin validate .`
