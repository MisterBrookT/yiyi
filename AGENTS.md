# AGENTS.md

yiyi is a small macOS menu-bar translator. Keep the app quiet, native, and dependency-free.

- Support macOS 14 and newer.
- Keep provider, prompt, config, and hotkey parsing in `YiyiCore`; AppKit and Carbon belong in the executable target.
- Never log or commit API keys.
- Preserve valid user config fields when extending the schema; new fields need decoding defaults and tests.
- Local app bundles are ad-hoc signed unless `YIYI_CODESIGN_IDENTITY` is explicitly supplied.
- Verify changes with `swift test`, a release build, and the relevant real app or CLI path.
