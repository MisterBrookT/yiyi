#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/Applications"
[[ "$(uname)" == Darwin ]] || { echo "yiyi is macOS only." >&2; exit 1; }
command -v swift >/dev/null || { echo "swift is required." >&2; exit 1; }
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

"$ROOT/scripts/build-app.sh"
SOURCE_APP="$ROOT/dist/yiyi.app"
TARGET_APP="$DEST/yiyi.app"
STAGED_APP="$DEST/.yiyi.app.$$.staged"
BACKUP_APP="$DEST/.yiyi.app.$$.backup"
rm -rf "$STAGED_APP" "$BACKUP_APP"
trap 'rm -rf "$STAGED_APP" "$BACKUP_APP"' EXIT

ditto "$SOURCE_APP" "$STAGED_APP"
"$ROOT/scripts/check-signature.sh" "$STAGED_APP"

pkill -f "$TARGET_APP/Contents/MacOS/yiyi" 2>/dev/null || true
if [[ -d "$TARGET_APP" ]]; then
  ditto "$TARGET_APP" "$BACKUP_APP"
  if ! ditto "$STAGED_APP" "$TARGET_APP" ||
     ! "$ROOT/scripts/check-signature.sh" "$TARGET_APP"; then
    echo "ERROR: install failed; restoring the previous app bundle." >&2
    rm -rf "$TARGET_APP"
    mv "$BACKUP_APP" "$TARGET_APP"
    exit 1
  fi
  rm -rf "$BACKUP_APP"
else
  mv "$STAGED_APP" "$TARGET_APP"
fi
rm -rf "$STAGED_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
open "$TARGET_APP"
echo "Installed and launched $TARGET_APP"
"$ROOT/scripts/check-signature.sh" "$TARGET_APP"
trap - EXIT
