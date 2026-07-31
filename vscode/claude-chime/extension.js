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

let muted = false; // per-window mute, flipped by claudeChime.toggle

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("claudeChime.toggle", () => {
      muted = !muted;
      vscode.window.setStatusBarMessage(
        muted
          ? "Claude Chime: muted in this window"
          : "Claude Chime: notifications on",
        3000
      );
    }),
    vscode.commands.registerCommand("claudeChime.testNotification", () =>
      sendTestSignal()
    )
  );

  try {
    fs.mkdirSync(SIGNAL_DIR, { recursive: true, mode: 0o700 });
  } catch {
    return;
  }

  // VS Code extensions cannot run install scripts at download time (the
  // Marketplace forbids it), so optional native dependencies are offered
  // here, once, at activation. The install command is a fixed literal.
  checkDependencies(context);

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

// Writes a real signal file for this window's workspace folder, exercising
// the same watcher -> matching -> toast pipeline live events use. Content is
// a fixed literal; only the folder path (trusted workspace state) varies.
function sendTestSignal() {
  const folder = (vscode.workspace.workspaceFolders || [])[0];
  if (!folder) {
    vscode.window.showInformationMessage(
      "Claude Chime test: open a folder in this window first — matching is per workspace folder."
    );
    return;
  }
  const signal = {
    event: "stop",
    cwd: folder.uri.fsPath,
    detail: "Test notification — Claude Chime is working",
    ts: Date.now() / 1000,
  };
  try {
    fs.writeFileSync(
      path.join(SIGNAL_DIR, `signal-test-${Date.now()}.json`),
      JSON.stringify(signal)
    );
  } catch (err) {
    vscode.window.showWarningMessage(
      `Claude Chime: could not write the test signal (${
        err && err.message ? err.message : "unknown error"
      })`
    );
  }
}

function handleSignal(file) {
  const config = vscode.workspace.getConfiguration("claudeChime");
  if (!config.get("enabled", true) || muted) return;

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

  const notifyOn = config.get("notifyOn", "both");
  if (notifyOn !== "both" && notifyOn !== signal.event) return;

  const folder = matchWorkspace(signal.cwd);
  if (!folder) return; // some other window's session

  try {
    fs.unlinkSync(file); // consume so it doesn't replay
  } catch {
    // A duplicate window on the same folder consumed it first; still notify.
  }

  // detail = last user prompt / requested tool, written by the hook script.
  // Untrusted text: control chars stripped, length capped; rendered only as
  // plain notification text.
  let detail = "";
  if (config.get("showPromptText", true) && typeof signal.detail === "string") {
    detail = signal.detail.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 140);
  }

  vscode.window.showInformationMessage(
    `Claude ${EVENT_TEXT[signal.event]} — ${folder.name}` +
      (detail ? `: “${detail}”` : "")
  );
}

function matchWorkspace(cwd) {
  const folders = vscode.workspace.workspaceFolders || [];
  return folders.find((folder) => {
    const rel = path.relative(folder.uri.fsPath, cwd);
    return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
  });
}

async function checkDependencies(context) {
  if (process.platform !== "darwin") return;
  if (context.globalState.get("claudeChime.depPromptDismissed")) return;

  const candidates = [
    "/opt/homebrew/bin/terminal-notifier",
    "/usr/local/bin/terminal-notifier",
  ];
  const installed = candidates.some((p) => {
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  });
  if (installed) return;

  const choice = await vscode.window.showInformationMessage(
    "Claude Chime: install terminal-notifier so macOS banners become " +
      "clickable (a click focuses the window Claude finished in).",
    "Install with Homebrew",
    "Don't ask again"
  );
  if (choice === "Install with Homebrew") {
    const term = vscode.window.createTerminal("Claude Chime setup");
    term.show();
    term.sendText("brew install terminal-notifier", true);
  } else if (choice === "Don't ask again") {
    await context.globalState.update("claudeChime.depPromptDismissed", true);
  }
}

function deactivate() {}

module.exports = { activate, deactivate };
