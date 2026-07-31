# Clickable macOS banners (optional)

By default macOS banners are informational only. With
[terminal-notifier](https://github.com/julienXX/terminal-notifier), clicking
a banner focuses the VS Code window (or iTerm2 tab) the event came from.

```bash
brew install terminal-notifier
```

**Critical second step** — allow it, or all banners go silent:

> System Settings → Notifications → **terminal-notifier** → Allow
> Notifications, style *Banners* or *Alerts*.

If banners ever stop appearing entirely, this permission is the first thing
to check — see the
[troubleshooting guide](https://github.com/rvira/claude-plugins/blob/main/TROUBLESHOOTING.md).

Not on macOS? Linux gets clickable banners with libnotify ≥ 0.7.10; Windows
toasts are clickable when `code` is on PATH. Nothing else to install.
