import XCTest
@testable import YiyiCore

final class YiyiCoreTests: XCTestCase {
    func testPromptTemplateAliases() throws {
        XCTAssertEqual(try renderPrompt("A {selection} B {input}", input: "hello"), "A hello B hello")
        XCTAssertThrowsError(try renderPrompt("No variable", input: "hello")) { XCTAssertEqual($0 as? PromptTemplateError, .missingPlaceholder) }
    }
    func testHotkeyParsing() throws {
        XCTAssertEqual(try parseHotkey("cmd+-"), ParsedHotkey(keyCode: 27, modifiers: HotkeyModifier.cmd))
        XCTAssertEqual(try parseHotkey("cmd+shift+-"), ParsedHotkey(keyCode: 27, modifiers: HotkeyModifier.cmd | HotkeyModifier.shift))
        XCTAssertEqual(try parseHotkey("ctrl+opt+t"), ParsedHotkey(keyCode: 17, modifiers: HotkeyModifier.control | HotkeyModifier.option))
        XCTAssertThrowsError(try parseHotkey("cmd+banana")); XCTAssertThrowsError(try parseHotkey("cmd")); XCTAssertThrowsError(try parseHotkey("cmd+a+b"))
    }
    func testConfigDefaultsWhenFieldsMissing() throws {
        let config = try JSONDecoder().decode(YiyiConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config.defaultProvider, "deepseek"); XCTAssertEqual(config.providers["qwen"]?.model, "qwen-plus")
        XCTAssertTrue(config.autoCopy); XCTAssertEqual(config.commands.count, 2)
    }
    func testConfigDecodesOverrides() throws {
        let json = #"{"defaultProvider":"deepseek","providers":{"deepseek":{"baseURL":"https://example/v1","model":"deepseek-chat","apiKeyEnv":"DEEPSEEK_API_KEY"}},"autoCopy":false,"commands":[{"name":"Test","hotkey":"ctrl+t","provider":"deepseek","model":"override","prompt":"{input}"}]}"#
        let config = try JSONDecoder().decode(YiyiConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.defaultProvider, "deepseek"); XCTAssertFalse(config.autoCopy); XCTAssertEqual(config.commands.first?.model, "override")
    }
    func testProviderAndModelOverrides() throws {
        let config = YiyiConfig(defaultProvider: "deepseek")
        let inherited = try resolveProvider(config: config, command: CommandConfig(name: "A", hotkey: "cmd+-", prompt: "{input}"))
        XCTAssertEqual(inherited.name, "deepseek"); XCTAssertEqual(inherited.model, "deepseek-v4-flash")
        let override = try resolveProvider(config: config, command: CommandConfig(name: "B", hotkey: "cmd+-", provider: "qwen", model: "qwen-mt-turbo", prompt: "{input}"))
        XCTAssertEqual(override.name, "qwen"); XCTAssertEqual(override.model, "qwen-mt-turbo")
    }
    func testAPIKeyResolutionOrderAndDefaultFallback() throws {
        var providers = YiyiConfig.defaultProviders; providers["qwen"]?.apiKey = "configured"
        let config = YiyiConfig(defaultProvider: "openrouter", providers: providers)
        XCTAssertEqual(try resolveAPIKey(providerName: "qwen", config: config, environment: ["DASHSCOPE_API_KEY":"env"], dotEnv: [:], defaultProviderKey: "file"), "configured")
        providers["qwen"]?.apiKey = nil; let withoutConfig = YiyiConfig(defaultProvider: "openrouter", providers: providers)
        XCTAssertEqual(try resolveAPIKey(providerName: "qwen", config: withoutConfig, environment: ["DASHSCOPE_API_KEY":"env"], dotEnv: ["DASHSCOPE_API_KEY":"dot"], defaultProviderKey: "file"), "env")
        XCTAssertEqual(try resolveAPIKey(providerName: "openrouter", config: withoutConfig, environment: [:], dotEnv: [:], defaultProviderKey: "file"), "file")
    }
    func testMissingProviderKeyMessage() {
        let config = YiyiConfig(defaultProvider: "openrouter")
        XCTAssertThrowsError(try resolveAPIKey(providerName: "qwen", config: config, environment: [:], dotEnv: [:], defaultProviderKey: "openrouter-only")) {
            XCTAssertEqual($0.localizedDescription, "no API key for provider 'qwen': set DASHSCOPE_API_KEY or providers.qwen.apiKey in ~/.config/yiyi/config.json")
        }
    }
    func testResponseAndErrorPayloadParsing() throws {
        XCTAssertEqual(try parseChatCompletion(Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)), "你好")
        XCTAssertThrowsError(try parseChatCompletion(Data(#"{"error":{"message":"bad key"}}"#.utf8))) { XCTAssertEqual($0 as? OpenAIError, .provider("bad key")) }
        XCTAssertThrowsError(try parseChatCompletion(Data(#"{"choices":[]}"#.utf8))) { XCTAssertEqual($0 as? OpenAIError, .emptyResponse) }
    }
}
