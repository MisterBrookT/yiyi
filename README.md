<div align="center">

# yiyi

**A quiet macOS menu-bar translator for the text you select.**

[Website](https://misterbrookt.github.io/yiyi/) · [Install](#install)

<img src="docs/site/assets/scene-shortcut.png" width="760" alt="Selected text in a reading window, the shortcut pressed on a laptop keyboard, and yiyi’s result panel beside it">

</div>

## About

yiyi translates selected text without switching apps. Bring an OpenAI-compatible or Anthropic endpoint, save your prompts as commands, and invoke them with a keyboard shortcut, Hyper Key, or an experimental mouse/trackpad gesture. It uses native macOS frameworks, with no runtime dependencies or Dock icon.

This is a source-build release, not a notarized download. Text is sent to your chosen endpoint; yiyi is not inherently offline.

## Install

Requires macOS 14+.

```sh
curl -fsSL https://misterbrookt.github.io/yiyi/install.sh | bash
```

yiyi is compiled on your Mac. If Apple's Command Line Tools are missing, the script installs them first (macOS asks you to confirm once), then fetches the source into `~/Library/Caches/yiyi/src`, builds, and launches. Run the same line again to update. Prefer to read first? Clone and run it yourself (needs a Swift 6 toolchain):

```sh
git clone https://github.com/MisterBrookT/yiyi.git
cd yiyi
./install.sh
```

The installer builds, signs, installs, and opens yiyi. It uses your Developer ID if available, otherwise a reusable local signing identity. Local signing is not Apple notarization.

## First use

1. Click the **译** icon in the menu bar to open Settings (right-click it to quit). In **Connection**, enter your **Base URL**, **API key**, and **model**, then **Save**.
2. Enable yiyi in **System Settings → Privacy & Security → Accessibility** for selected-text capture. Without it, yiyi uses clipboard text.
3. Select some text and press **⌘−** to translate into Chinese, or **⌘⇧−** for English. Change these in **Commands**.

The floating panel shows the result. **Esc** closes it; **⌘C** copies it. Automatic copying is optional in **General**.

## Commands and inputs

Each command has a name, shortcut, and prompt. Changes remain drafts until **Save** (or **⌘S**). Cancel, closing Settings, and quitting protect unsaved work with a confirmation. **Delete…** is beside the command picker.

- `{selection}` / `{input}` — selected text, falling back to the clipboard when selection is unavailable.
- `{clipboard}` / `{copy}` — clipboard text from before capture, without synthesizing Copy for clipboard-only prompts.
- Insert buttons add highlighted tokens at the cursor. Unknown tokens such as `{selecton}` show an error.

Each command card has a **Keyboard** shortcut and a **Trackpad** checkbox. The shortcut recorder takes an ordinary modifier combination; if you have chosen a **Hyper Key** in General (a right-side modifier reserved for yiyi, or an existing external **⌃⌥⇧⌘** remap), pressing it with a key records **◆ + key** instead. Selecting External Hyper does not remap Caps Lock or change system keyboard settings.

## Mouse and trackpad

On a command card, check **Press and hold runs this command**. Only one command owns the gesture; checking it elsewhere moves it. Select text, then press the trackpad or mouse button and hold still for about half a second; the command starts while you are still holding, and you can let go once the panel appears.

The experimental gesture uses the selection at press time when Accessibility can read it quickly; otherwise it uses the clipboard. Dragging or another button cancels it. It never consumes normal pointer events. Input Monitoring permission may also be required. It stays **off by default**.

## Configuration and privacy

Settings live in `~/.config/yiyi/config.json`. Saved files are owner-readable/writable only; inline API keys are stored as plaintext, not in Keychain. Keys can also come from environment variables or local key files. Existing named connections and command overrides remain supported and are preserved by Settings.

Changing a server’s origin requires re-entering the API key or explicitly confirming its reuse. Prompt and clipboard text are not written to diagnostic logs.

[Configuration details](docs/configuration.md) · [Development and checks](docs/development.md)
