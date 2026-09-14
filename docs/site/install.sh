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
# yiyi is compiled on this Mac, which needs Apple's Command Line Tools (git + swift). On a
# stock macOS they are missing; ask macOS to install them, then wait, so the one-liner still
# finishes on its own without a second run.
have_tools() { xcode-select -p >/dev/null 2>&1 && command -v swift >/dev/null && swift --version >/dev/null 2>&1; }
if ! have_tools; then
  say "Installing Apple's Command Line Tools (a system dialog will ask you to confirm)"
  # Trigger the softwareupdate path so it installs without opening Xcode.
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  label="$(softwareupdate -l 2>/dev/null | grep -o 'Command Line Tools for Xcode-[0-9.]*' | tail -1 || true)"
  if [[ -n "$label" ]]; then
    softwareupdate -i "$label" --verbose || true
  else
    xcode-select --install 2>/dev/null || true
    printf 'Waiting for the Command Line Tools to finish installing'
    until have_tools; do printf '.'; sleep 10; done
    echo
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  have_tools || fail "Command Line Tools did not install. Run: xcode-select --install, then rerun this command."
fi

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
