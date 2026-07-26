#!/usr/bin/env bash
# terminal-notifier click action: focus the VS Code window showing this folder.
# Argument: base64-encoded absolute path of the project.
# Charset is allow-list validated before decoding, and the decoded value is
# only ever passed as a quoted argument — never interpreted as shell source.
set -u

b64="${1:-}"
[[ "$b64" =~ ^[A-Za-z0-9+/=]+$ ]] || exit 1

dir="$(python3 -c 'import base64,sys; sys.stdout.write(base64.b64decode(sys.argv[1]).decode("utf-8","strict"))' "$b64" 2>/dev/null)" || exit 1
[ -n "$dir" ] && [ -d "$dir" ] || exit 1

# VS Code reuses the window that already has this folder open, so this
# focuses the exact window rather than opening a new one.
case "$(uname -s)" in
  Darwin) exec open -a "Visual Studio Code" "$dir" ;;
  *) command -v code >/dev/null 2>&1 && exec code "$dir" ;;
esac
exit 1
