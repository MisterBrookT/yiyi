# Development

```sh
swift test
swift build -c release
python3 scripts/check-site.py
./scripts/build-app.sh
```

Use a full Xcode installation for XCTest. If Command Line Tools lack its module, `python3 scripts/test-core-standalone.py` runs the same synchronous core test methods using a small assertion adapter. This fallback is not the XCTest runner. GitHub Actions runs the actual XCTest suite on macOS.

## Native UI acceptance

Never point UI tests at real configuration:

```sh
d=$(mktemp -d)
YIYI_CONFIG_DIR="$d/config" dist/yiyi.app/Contents/MacOS/yiyi --ui-journey "$d/results"
```

This exercises real AppKit controls and isolated file persistence: staged edits, Save/Cancel, write failure and retry, disk conflict, credential destination confirmation, prompt validation/highlighting/undo, deletion, ordinary/Hyper shortcuts, and pointer settings. It writes assertions and light/dark screenshots.

`--settings-preview light` or `--settings-preview dark` opens an interactive settings window and also requires an isolated `YIYI_CONFIG_DIR`.

```sh
dist/yiyi.app/Contents/MacOS/yiyi --selftest-pointer
```

This optional OS check requires the event-tap permissions. It opens a disposable window and posts ordinary clicks, short holds, dragging, and a valid hold-release to that window. It verifies real event-tap dispatch and press-time selection, then closes. Do not move the pointer or change focus while it runs. It never reads or writes clipboard contents.

`--selftest-superkey` tests leader matching after creating a real event tap. `--diagnose` reports permission and binding state without credentials.

## Website

The static site lives in `docs/site`. GitHub Pages deploys that directory through `.github/workflows/pages.yml`. See [local preview instructions](site/README.md).

## App icon

`./scripts/make-icon.sh` regenerates `Resources/AppIcon.icns`. `./scripts/build-app.sh` copies it before signing. Set `YIYI_CODESIGN_IDENTITY` to choose a signing identity explicitly; the installer otherwise reuses a stable local identity when no Developer ID is available.
