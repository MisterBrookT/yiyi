# yiyi website

Dependency-free static site deployed to <https://misterbrookt.github.io/yiyi/>.

## Local preview

```sh
python3 -m http.server 8000 --directory docs/site
python3 scripts/check-site.py
node scripts/check-site-browser.mjs
```

Open <http://localhost:8000>. The browser check needs Node 22+ and Chrome; use `CHROME_BIN` for a nonstandard Chrome executable. It checks desktop/mobile under both light and dark OS preferences, verifies that the site remains light-only and always selects light product images, and checks image loading, overflow, 44px targets, keyboard focus, and reduced motion. It prints the screenshot directory.

## Product images

All PNGs are rendered from the real app with deterministic fixtures, never from user configuration. The three carousel slides are the same size (1012×512 CSS px at 2×):

- `scene-shortcut.png` — `--preview light --scene <path>`: a fixture reading window, a highlighted sentence, the live result panel, and a laptop deck with the shortcut keys lit.
- `scene-hold.png` — `--preview light trackpad --scene <path>`: the same scene with a fingertip pressing the trackpad of the laptop deck.
- `scene-commands.png` — `--preview light --settings-scene <settings-capture> <path>`: wraps a `--ui-journey` settings capture in the same padded frame.

Keep HTML image dimensions in sync; the checker fails on missing assets or mismatched aspect ratios.

The original app icon comes from `Resources/AppIcon.icns`. The social preview is 1200×630. Do not put credentials or personal selected text in public captures.

`.github/workflows/pages.yml` deploys this directory. No build step, tracking scripts, external fonts, or third-party runtime libraries are required.
