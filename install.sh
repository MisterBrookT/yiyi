#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/Applications"
[[ "$(uname)" == Darwin ]] || { echo "yiyi is macOS only." >&2; exit 1; }
command -v swift >/dev/null || { echo "swift is required." >&2; exit 1; }
if [[ ! -w "$DEST" ]]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
"$ROOT/scripts/build-app.sh"
pkill -f "$DEST/yiyi.app/Contents/MacOS/yiyi" 2>/dev/null || true
rm -rf "$DEST/yiyi.app"
cp -R "$ROOT/dist/yiyi.app" "$DEST/yiyi.app"
xattr -dr com.apple.quarantine "$DEST/yiyi.app" 2>/dev/null || true
open "$DEST/yiyi.app"
echo "Installed and launched $DEST/yiyi.app"
