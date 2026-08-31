<div align="center">

# yiyi

**A native macOS menu-bar translator, available from any app with one hotkey.**

</div>

<div align="center">
  <img src="docs/light-panel.png" width="420" alt="yiyi result panel in light appearance">
  <img src="docs/dark-panel.png" width="420" alt="yiyi result panel in dark appearance">
</div>

## About

yiyi captures selected text, sends it to an OpenAI-compatible provider, copies the translation, and shows it in a quiet floating panel. It is an LSUIElement app with no Dock icon, uses only macOS frameworks, and supports multiple named commands and providers.

## Install

Requires macOS 14+ and Swift 6.

```sh
./install.sh
```

The installer builds an ad-hoc-signed release app, installs it to `/Applications` (or `~/Applications` without write access), and launches it.

## First use

1. Trigger **Translate to Chinese** with <kbd>⌘</kbd><kbd>-</kbd>.
2. Click **Open Accessibility Settings** and enable yiyi under **Privacy & Security → Accessibility**. This allows yiyi to synthesize Copy in the frontmost app.
3. Trigger the hotkey again. The result appears and is copied automatically.

If no selection can be copied, yiyi translates the existing clipboard. Escape closes the panel; Command-C copies its selectable result.

## Configuration

On first launch yiyi creates `~/.config/yiyi/config.json` with these exact defaults:

```json
{
  "autoCopy" : true,
  "commands" : [
    {
      "hotkey" : "cmd+-",
      "name" : "Translate to Chinese",
      "prompt" : "Translate the following into Chinese. Output only the translation, no explanation.\n\n{selection}"
    },
    {
      "hotkey" : "cmd+shift+-",
      "name" : "Translate to English",
      "prompt" : "Translate the following into English. Output only the translation, no explanation.\n\n{selection}"
    }
  ],
  "defaultProvider" : "deepseek",
  "providers" : {
    "ark" : {
      "apiKeyEnv" : "ARK_API_KEY",
      "baseURL" : "https://ark.cn-beijing.volces.com/api/v3",
      "model" : "doubao-1-5-lite-32k-250115"
    },
    "deepseek" : {
      "apiKeyEnv" : "DEEPSEEK_API_KEY",
      "baseURL" : "https://api.deepseek.com/v1",
      "model" : "deepseek-v4-flash"
    },
    "openrouter" : {
      "apiKeyEnv" : "OPENROUTER_API_KEY",
      "baseURL" : "https://openrouter.ai/api/v1",
      "model" : "google/gemini-2.5-flash-lite"
    },
    "qwen" : {
      "apiKeyEnv" : "DASHSCOPE_API_KEY",
      "baseURL" : "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "model" : "qwen-plus"
    }
  }
}
```

A command's optional `provider` and `model` override the selected default. For example: `{"provider":"qwen","model":"qwen-mt-turbo"}` (optional; requires a Qwen key). Every prompt must contain `{selection}` or `{input}`. Hotkeys accept `cmd`, `shift`, `ctrl`, and `opt` plus a key, such as `ctrl+opt+t`.

Choose an available default from the menu's **Provider** submenu. Providers without a key are disabled and explain what is missing. **Edit config…** opens the file; **Reload config** applies changes and re-registers hotkeys without a restart.

Provider key lookup order is `providers.<name>.apiKey`, its `apiKeyEnv` process environment variable, the same variable in `~/.config/yiyi/.env`, then `~/.config/yiyi/apikey` for the default provider only. Keys are never logged.

## Providers

| Provider | Default model | Key setting | Available on this machine |
| --- | --- | --- | --- |
| OpenRouter | `google/gemini-2.5-flash-lite` | `OPENROUTER_API_KEY` | Yes |
| DeepSeek | `deepseek-v4-flash` | `DEEPSEEK_API_KEY` | Yes |
| Qwen / DashScope | `qwen-plus` | `DASHSCOPE_API_KEY` | No |
| Ark | `doubao-1-5-lite-32k-250115` | `ARK_API_KEY` | No |

To enable Qwen or DeepSeek for a Finder/login-launched app, add `DASHSCOPE_API_KEY=...` or `DEEPSEEK_API_KEY=...` to `~/.config/yiyi/.env`. Alternatively, put the key in `providers.qwen.apiKey` or `providers.deepseek.apiKey` in `~/.config/yiyi/config.json`, then choose **Reload config**. Shell-exported variables work when yiyi is launched from that shell.

## Build and smoke test

```sh
swift test
swift build -c release
.build/release/yiyi --translate "hello world"
```
