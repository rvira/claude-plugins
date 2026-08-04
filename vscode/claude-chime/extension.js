// Claude Chime — raises the toast in the exact VS Code window whose Claude
// Code session fired, driven by signal files from the claude-sounds plugin.
// Signal files are untrusted input: size-capped, parsed defensively,
// allow-listed, and matched with a path-containment check.

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

let muted = false;

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

  // The Marketplace forbids install-time scripts, so optional native
  // dependencies are offered once, at activation.
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

// Exercises the same watcher -> matching -> toast pipeline live events use.
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

  // Untrusted text from the hook: control chars stripped, length capped.
  let detail = "";
  if (config.get("showPromptText", true) && typeof signal.detail === "string") {
    detail = signal.detail.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 140);
  }

  showToast(
    config,
    `Claude ${EVENT_TEXT[signal.event]} — ${folder.name}` +
      (detail ? `: “${detail}”` : "")
  );
}

// showInformationMessage toasts are sticky, so auto-dismiss is done via a
// progress notification that resolves after autoDismissSeconds (0 = sticky).
function showToast(config, message) {
  let dismiss = Number(config.get("autoDismissSeconds", 8));
  if (!Number.isFinite(dismiss) || dismiss < 0) dismiss = 8;
  dismiss = Math.min(Math.floor(dismiss), 300);

  if (dismiss === 0) {
    vscode.window.showInformationMessage(message);
    return;
  }
  vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: message },
    () => new Promise((resolve) => setTimeout(resolve, dismiss * 1000))
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
