import XCTest
@testable import YiyiCore

final class YiyiCoreTests: XCTestCase {

    func testAccessibilityAdviceMatrix() {
        XCTAssertEqual(accessibilityAdvice(trusted: true, hasPrompted: false, grantedSignature: nil, currentSignature: "current"), .ok)
        XCTAssertEqual(accessibilityAdvice(trusted: true, hasPrompted: true, grantedSignature: "old", currentSignature: "current"), .ok)
        XCTAssertEqual(accessibilityAdvice(trusted: false, hasPrompted: false, grantedSignature: nil, currentSignature: "current"), .promptOnce)
        XCTAssertEqual(accessibilityAdvice(trusted: false, hasPrompted: true, grantedSignature: "old", currentSignature: "current"), .staleGrant)
        XCTAssertEqual(accessibilityAdvice(trusted: false, hasPrompted: true, grantedSignature: "current", currentSignature: "current"), .awaitGrant)
        XCTAssertEqual(accessibilityAdvice(trusted: false, hasPrompted: true, grantedSignature: nil, currentSignature: "current"), .awaitGrant)
    }

    func testSelectionCaptureUsesAdvancedNonEmptySelection() {
        XCTAssertEqual(
            chooseCaptureInput(trusted: true, changeCountAdvanced: true, capturedText: "selected", clipboardText: "old"),
            CaptureDecision(text: "selected", source: .selection)
        )
    }

    func testSelectionCaptureFallsBackWhenCapturedTextIsWhitespace() {
        XCTAssertEqual(
            chooseCaptureInput(trusted: true, changeCountAdvanced: true, capturedText: " \n ", clipboardText: "clipboard"),
            CaptureDecision(text: "clipboard", source: .clipboard)
        )
    }

    func testSelectionCaptureFallsBackWhenChangeCountDoesNotAdvance() {
        XCTAssertEqual(
            chooseCaptureInput(trusted: true, changeCountAdvanced: false, capturedText: "ignored", clipboardText: "clipboard"),
            CaptureDecision(text: "clipboard", source: .clipboard)
        )
    }

    func testRegressionUntrustedProcessLabelsClipboardAndExplainsRelaunch() {
        let decision = chooseCaptureInput(
            trusted: false,
            changeCountAdvanced: false,
            capturedText: nil,
            clipboardText: "stale clipboard"
        )
        XCTAssertEqual(decision.source, .clipboard)
        XCTAssertEqual(decision.text, "stale clipboard")
        XCTAssertNotNil(decision.hint)
        XCTAssertTrue(decision.hint?.contains("relaunch") == true)
    }

    func testUntrustedProcessWithEmptyClipboardIsEmpty() {
        let decision = chooseCaptureInput(
            trusted: false,
            changeCountAdvanced: false,
            capturedText: nil,
            clipboardText: "  "
        )
        XCTAssertEqual(decision.source, .empty)
        XCTAssertNil(decision.text)
    }

    func testTrustIsReevaluatedForEverySynthesisDecision() {
        XCTAssertFalse(shouldSynthesizeSelection(trusted: false))
        XCTAssertTrue(shouldSynthesizeSelection(trusted: true))
    }
    func testPromptTemplateAliases() throws {
        XCTAssertEqual(try renderPrompt("A {selection} B {input}", input: "hello"), "A hello B hello")
        XCTAssertThrowsError(try renderPrompt("No variable", input: "hello")) {
            XCTAssertEqual($0 as? PromptTemplateError, .missingPlaceholder)
        }
    }

    func testHotkeyParsing() throws {
        XCTAssertEqual(try parseHotkey("cmd+-"), ParsedHotkey(keyCode: 27, modifiers: HotkeyModifier.cmd))
        XCTAssertEqual(
            try parseHotkey("cmd+shift+-"),
            ParsedHotkey(keyCode: 27, modifiers: HotkeyModifier.cmd | HotkeyModifier.shift)
        )
        XCTAssertEqual(
            try parseHotkey("ctrl+opt+t"),
            ParsedHotkey(keyCode: 17, modifiers: HotkeyModifier.control | HotkeyModifier.option)
        )
        XCTAssertThrowsError(try parseHotkey("cmd+banana"))
        XCTAssertThrowsError(try parseHotkey("cmd"))
        XCTAssertThrowsError(try parseHotkey("cmd+a+b"))
    }

    func testBindingParsing() throws {
        XCTAssertEqual(try parseBinding("super+t"), .superKey(keyCode: 17))
        XCTAssertEqual(try parseBinding("hyper+t"), .superKey(keyCode: 17))
        XCTAssertEqual(
            try parseBinding("cmd+-"),
            .carbon(ParsedHotkey(keyCode: 27, modifiers: HotkeyModifier.cmd))
        )
        XCTAssertThrowsError(try parseBinding("super+banana"))
    }

    func testFormattedHotkeysRoundTrip() throws {
        let keys: [UInt32] = [0, 17, 24, 27, 36, 48, 49, 53]
        let modifiers: [UInt32] = [
            0,
            HotkeyModifier.cmd,
            HotkeyModifier.shift | HotkeyModifier.option,
            HotkeyModifier.cmd | HotkeyModifier.shift | HotkeyModifier.option | HotkeyModifier.control
        ]
        for key in keys {
            for modifier in modifiers {
                let formatted = formatHotkey(keyCode: key, modifiers: modifier)
                XCTAssertEqual(
                    try parseHotkey(formatted),
                    ParsedHotkey(keyCode: key, modifiers: modifier),
                    formatted
                )
            }
        }
        XCTAssertEqual(formatHotkey(keyCode: 27, modifiers: HotkeyModifier.cmd), "cmd+-")
        XCTAssertEqual(formatHotkey(keyCode: 24, modifiers: 0), "=")
        XCTAssertEqual(formatHotkey(keyCode: 49, modifiers: 0), "space")
        XCTAssertEqual(formatHotkey(keyCode: 53, modifiers: 0), "escape")
    }

    func testConfigDefaultsWhenFieldsMissing() throws {
        let config = try JSONDecoder().decode(YiyiConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config.defaultProvider, "deepseek")
        XCTAssertEqual(Set(config.providers.keys), ["deepseek", "qwen"])
        XCTAssertEqual(config.providers["qwen"]?.model, "qwen-plus")
        XCTAssertNil(config.providers["deepseek"]?.temperature)
        XCTAssertEqual(config.providers["deepseek"]?.reasoningEffort, ReasoningEffort.none)
        XCTAssertTrue(config.autoCopy)
        XCTAssertEqual(config.superKey, .none)
        XCTAssertEqual(config.commands.count, 2)
        XCTAssertNil(config.commands.first?.reasoningEffort)
    }

    func testConfigDecodesNewFieldsAndPreservesUnknownProviders() throws {
        let json = #"{"defaultProvider":"custom","providers":{"custom":{"baseURL":"https://example/v1","model":"custom-model","apiKeyEnv":"CUSTOM_KEY","temperature":0.7,"reasoningEffort":"high"}},"autoCopy":false,"superKey":"rightCommand","commands":[{"name":"Test","hotkey":"super+t","provider":"custom","model":"override","reasoningEffort":"low","prompt":"{input}"}]}"#
        let config = try JSONDecoder().decode(YiyiConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.defaultProvider, "custom")
        XCTAssertEqual(Set(config.providers.keys), ["custom"])
        XCTAssertEqual(config.providers["custom"]?.temperature, 0.7)
        XCTAssertEqual(config.providers["custom"]?.reasoningEffort, .high)
        XCTAssertEqual(config.superKey, .rightCommand)
        XCTAssertFalse(config.autoCopy)
        XCTAssertEqual(config.commands.first?.model, "override")
        XCTAssertEqual(config.commands.first?.reasoningEffort, .low)
    }

    func testProviderAndModelOverrides() throws {
        let config = YiyiConfig(defaultProvider: "deepseek")
        let inherited = try resolveProvider(
            config: config,
            command: CommandConfig(name: "A", hotkey: "cmd+-", prompt: "{input}")
        )
        XCTAssertEqual(inherited.name, "deepseek")
        XCTAssertEqual(inherited.model, "deepseek-v4-flash")
        let override = try resolveProvider(
            config: config,
            command: CommandConfig(
                name: "B",
                hotkey: "cmd+-",
                provider: "qwen",
                model: "qwen-mt-turbo",
                prompt: "{input}"
            )
        )
        XCTAssertEqual(override.name, "qwen")
        XCTAssertEqual(override.model, "qwen-mt-turbo")
    }

    func testReasoningEffortResolutionPrecedence() throws {
        let provider = ProviderConfig(
            baseURL: "https://example/v1",
            model: "model",
            apiKeyEnv: "KEY",
            temperature: 0.4,
            reasoningEffort: .medium
        )
        let config = YiyiConfig(defaultProvider: "test", providers: ["test": provider])
        let inherited = try resolveProvider(
            config: config,
            command: CommandConfig(name: "A", hotkey: "cmd+-", prompt: "{input}")
        )
        XCTAssertEqual(inherited.reasoningEffort, .medium)
        XCTAssertEqual(inherited.temperature, 0.4)
        let overridden = try resolveProvider(
            config: config,
            command: CommandConfig(name: "B", hotkey: "cmd+-", reasoningEffort: .minimal, prompt: "{input}")
        )
        XCTAssertEqual(overridden.reasoningEffort, .minimal)
    }

    func testAPIKeyResolutionOrderAndDefaultFallback() throws {
        let custom = ProviderConfig(
            baseURL: "https://custom.example/v1",
            model: "custom",
            apiKeyEnv: "CUSTOM_API_KEY"
        )
        var providers = YiyiConfig.defaultProviders
        providers["custom"] = custom
        providers["qwen"]?.apiKey = "configured"
        let config = YiyiConfig(defaultProvider: "custom", providers: providers)
        XCTAssertEqual(
            try resolveAPIKey(
                providerName: "qwen",
                config: config,
                environment: ["DASHSCOPE_API_KEY": "env"],
                dotEnv: [:],
                defaultProviderKey: "file"
            ),
            "configured"
        )
        providers["qwen"]?.apiKey = nil
        let withoutConfig = YiyiConfig(defaultProvider: "custom", providers: providers)
        XCTAssertEqual(
            try resolveAPIKey(
                providerName: "qwen",
                config: withoutConfig,
                environment: ["DASHSCOPE_API_KEY": "env"],
                dotEnv: ["DASHSCOPE_API_KEY": "dot"],
                defaultProviderKey: "file"
            ),
            "env"
        )
        XCTAssertEqual(
            try resolveAPIKey(
                providerName: "custom",
                config: withoutConfig,
                environment: [:],
                dotEnv: [:],
                defaultProviderKey: "file"
            ),
            "file"
        )
    }

    func testMissingProviderKeyMessage() {
        let config = YiyiConfig()
        XCTAssertThrowsError(
            try resolveAPIKey(
                providerName: "qwen",
                config: config,
                environment: [:],
                dotEnv: [:],
                defaultProviderKey: "deepseek-only"
            )
        ) {
            XCTAssertEqual(
                $0.localizedDescription,
                "no API key for provider 'qwen': set DASHSCOPE_API_KEY or providers.qwen.apiKey in ~/.config/yiyi/config.json"
            )
        }
    }

    func testChatCompletionBodyIncludesTunableParameters() throws {
        let provider = ResolvedProvider(
            name: "test",
            baseURL: "https://example/v1",
            model: "model",
            apiKeyEnv: "KEY",
            temperature: 0.35,
            reasoningEffort: .high
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: buildChatCompletionBody(prompt: "hello", provider: provider))
                as? [String: Any]
        )
        XCTAssertEqual(body["temperature"] as? Double, 0.35)
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
    }

    func testChatCompletionBodyOmitsUnsetTunableParameters() throws {
        let provider = ResolvedProvider(
            name: "test",
            baseURL: "https://example/v1",
            model: "model",
            apiKeyEnv: "KEY"
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: buildChatCompletionBody(prompt: "hello", provider: provider))
                as? [String: Any]
        )
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["reasoning_effort"])
    }

    func testResponseAndErrorPayloadParsing() throws {
        XCTAssertEqual(
            try parseChatCompletion(Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)),
            "你好"
        )
        XCTAssertThrowsError(try parseChatCompletion(Data(#"{"error":{"message":"bad key"}}"#.utf8))) {
            XCTAssertEqual($0 as? OpenAIError, .provider("bad key"))
        }
        XCTAssertThrowsError(try parseChatCompletion(Data(#"{"choices":[]}"#.utf8))) {
            XCTAssertEqual($0 as? OpenAIError, .emptyResponse)
        }
    }
}
