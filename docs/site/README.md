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

All PNGs use sanitized, deterministic fixtures from the real app—not user configuration. The settings capture comes from `--ui-journey`; the result capture uses `--preview light --png <path>`. The public website intentionally uses only light captures, regardless of the visitor’s OS appearance. The mobile settings image crops the prompt region so text stays readable. Keep HTML image dimensions in sync; the checker fails on missing assets or mismatched aspect ratios.

The original app icon comes from `Resources/AppIcon.icns`. The social preview is 1200×630. Do not put credentials or personal selected text in public captures.

`.github/workflows/pages.yml` deploys this directory. No build step, tracking scripts, external fonts, or third-party runtime libraries are required.
