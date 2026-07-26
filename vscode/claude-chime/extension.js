// Claude Chime — answers "which VS Code window finished?".
//
// The claude-sounds Claude Code plugin writes a signal file to
// ~/.claude-code-chime/ on every Stop / PermissionRequest event, containing
// the session's cwd. Every VS Code window runs its own instance of this
// extension; each instance reacts only to signals whose cwd falls inside
// one of ITS workspace folders — so the toast appears in the exact window
// whose Claude session fired, no matter how many windows are open.
//
// Signal files are untrusted input: size-capped, JSON-parsed defensively,
// event names allow-listed, and cwd matched with a proper path-containment
// check (no string-prefix tricks).

const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");

const SIGNAL_DIR = path.join(os.homedir(), ".claude-code-chime");
const MAX_SIGNAL_BYTES = 4096;
const EVENT_TEXT = {
  stop: "finished responding",
  permission: "needs permission",
};

function activate(context) {
  try {
    fs.mkdirSync(SIGNAL_DIR, { recursive: true, mode: 0o700 });
  } catch {
    return;
  }

  let watcher;
  try {
    watcher = fs.watch(SIGNAL_DIR, (_eventType, filename) => {
      if (!filename || !filename.endsWith(".json")) return;
      // Small delay so the writer's atomic rename fully settles.
      setTimeout(() => handleSignal(path.join(SIGNAL_DIR, filename)), 50);
    });
  } catch {
    return;
  }
  context.subscriptions.push({ dispose: () => watcher.close() });
}

function handleSignal(file) {
  const config = vscode.workspace.getConfiguration("claudeChime");
  if (!config.get("enabled", true)) return;

  let raw;
  try {
    if (fs.statSync(file).size > MAX_SIGNAL_BYTES) return;
    raw = fs.readFileSync(file, "utf8");
  } catch {
    return; // already consumed by another window, or gone
  }

  let signal;
  try {
    signal = JSON.parse(raw);
  } catch {
    return;
  }
  if (
    !signal ||
    typeof signal.cwd !== "string" ||
    !Object.prototype.hasOwnProperty.call(EVENT_TEXT, signal.event)
  ) {
    return;
  }

  const folder = matchWorkspace(signal.cwd);
  if (!folder) return; // some other window's session

  try {
    fs.unlinkSync(file); // consume so it doesn't replay
  } catch {
    // A duplicate window on the same folder consumed it first; still notify.
  }

  vscode.window.showInformationMessage(
    `Claude ${EVENT_TEXT[signal.event]} — ${folder.name}`
  );
}

function matchWorkspace(cwd) {
  const folders = vscode.workspace.workspaceFolders || [];
  return folders.find((folder) => {
    const rel = path.relative(folder.uri.fsPath, cwd);
    return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
  });
}

function deactivate() {}

module.exports = { activate, deactivate };
