#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/yiyi"
APP="$ROOT/dist/yiyi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/yiyi"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/yiyi"
xattr -cr "$APP"
codesign --force --sign "${YIYI_CODESIGN_IDENTITY:--}" --identifier cc.blackblue.yiyi "$APP"
echo "==> done: $APP"
