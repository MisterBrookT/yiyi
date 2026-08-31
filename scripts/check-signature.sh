#!/usr/bin/env bash
set -euo pipefail

APP="${1:-/Applications/yiyi.app}"
[[ -d "$APP" ]] || { echo "ERROR: app bundle not found: $APP" >&2; exit 1; }

echo "==> signature summary: $APP"
codesign -dv --verbose=4 "$APP" 2>&1

echo "==> designated requirement: $APP"
requirements="$(codesign -d --requirements - "$APP" 2>&1)"
printf '%s\n' "$requirements"

if [[ "$requirements" == *'cdhash H"'* ]]; then
  cat >&2 <<'EOF'
ERROR: yiyi's designated requirement is pinned to its current binary cdhash.
Accessibility permission will be lost on the next reinstall; a stable signing identity is required.
EOF
  exit 1
fi

codesign --verify --deep --strict "$APP"
echo "==> signature is stable and passes strict verification"
