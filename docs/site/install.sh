#!/usr/bin/env bash
# One-line installer for yiyi:  curl -fsSL https://misterbrookt.github.io/yiyi/install.sh | bash
#
# Clones (or updates) the source into a cache directory, then runs the repository's own
# install.sh, which builds, signs locally, installs to /Applications, and launches the app.
# Nothing is downloaded pre-built; you compile what you run.
set -euo pipefail

REPO="${YIYI_REPO:-https://github.com/MisterBrookT/yiyi.git}"
REF="${YIYI_REF:-main}"
SRC="${YIYI_SRC:-$HOME/Library/Caches/yiyi/src}"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf 'yiyi: %s\n' "$*" >&2; exit 1; }

[[ "$(uname)" == Darwin ]] || fail "yiyi is macOS only."
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ]] || fail "yiyi needs macOS 14 or newer."
command -v git >/dev/null || fail "git is required. Install Xcode Command Line Tools: xcode-select --install"
command -v swift >/dev/null || fail "swift is required. Install Xcode Command Line Tools: xcode-select --install"

mkdir -p "$(dirname "$SRC")"
if [[ -d "$SRC/.git" ]]; then
  say "Updating source in $SRC"
  git -C "$SRC" fetch --quiet --depth 1 origin "$REF"
  git -C "$SRC" checkout --quiet --force FETCH_HEAD
else
  say "Fetching source into $SRC"
  rm -rf "$SRC"
  git clone --quiet --depth 1 --branch "$REF" "$REPO" "$SRC"
fi

say "Building and installing (first build takes a minute or two)"
exec "$SRC/install.sh"
