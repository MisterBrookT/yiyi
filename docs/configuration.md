# Configuration

Settings edits are staged in memory. Save validates them and atomically replaces `~/.config/yiyi/config.json`; runtime hotkeys and the connection change only after a successful write. If the file changes outside the window, Save refuses to overwrite it. Cancel and reopen, or use General → Advanced → Reload from file.

The generic connection form edits the current default connection. Existing provider dictionary keys, other connections, and per-command overrides are preserved. Advanced command settings can remove a connection override to inherit the main connection. To change the default among legacy named connections, edit `defaultProvider` in the config file.

API key lookup order:

1. `providers.<name>.apiKey` in config.
2. The process environment variable named by `apiKeyEnv`.
3. That variable in `~/.config/yiyi/.env`.
4. `~/.config/yiyi/apikey`, for the default connection only.

The key field shows the inline key from the config file, masked, with a reveal button. Clearing it and saving removes the inline key; other key sources still apply. Keys that come from the environment or key files are not shown in the field, but the line beneath it says which source is in use. The JSON file is mode `0600`; keys are not encrypted. Keep `.env` and `apikey` owner-readable only too.

Each connection has an `apiStyle`: `openai` (default, omitted from the file) or `anthropic`. OpenAI-style connections post to `<baseURL>/chat/completions` with a Bearer token; Anthropic connections post to `<baseURL>/messages` with `x-api-key` and `anthropic-version: 2023-06-01`. Switching the API in Settings swaps the base URL only when it still equals the other protocol's public default.

Base URLs must use HTTP(S), without embedded credentials, query strings, or fragments. Use the API root (usually `/v1`), not the endpoint path. The model must match a model exposed by the endpoint. Provider-specific reasoning support varies; Advanced exposes reasoning effort and temperature. Empty temperature omits it. On Anthropic, reasoning effort maps to an extended-thinking budget (minimal 1k, low 2k, medium 8k, high 16k tokens), `none` disables thinking, and temperature is omitted whenever thinking is on because the API rejects the combination.

Commands support optional `provider`, `model`, and `reasoningEffort` overrides. Prompts must contain a supported input token. Substitution is single-pass: token-looking text inside an input is preserved literally, not substituted again.

Shortcuts accept `cmd`, `shift`, `ctrl`, and `opt`, plus a key. `super+t` and `hyper+t` use the selected Hyper Key. Right-side leader keys require Accessibility. External Hyper registers the all-four-modifier chord and requires an existing system remap. Empty shortcuts remain unassigned.

The pointer setting is `"pointerTrigger": {"enabled": false, "commandIndex": 0}`. Old configs decode with the gesture disabled. It is edited from the owning command's card under Commands. Deleting commands through Settings updates this index; deleting its target disables the gesture.

## Permissions

Accessibility may need to be granted again after a signing-identity or application-path change. General → Advanced shows the signing and event-tap status. Permission repair targets yiyi’s entry only. A physical keyboard is required to exercise Carbon hotkeys; AppleScript-generated keystrokes do not exercise that path.
