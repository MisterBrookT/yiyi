import Foundation

public enum ReasoningEffort: String, Codable, Sendable, CaseIterable {
    case none, minimal, low, medium, high
}

/// Which wire protocol a connection speaks. Prompts and commands are the same either way.
public enum APIStyle: String, Codable, Sendable, CaseIterable {
    case openAI = "openai"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        }
    }
    public var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        }
    }
}

public enum ProviderGroup: String, CaseIterable, Sendable {
    case deepseek = "DeepSeek"
    case qwen = "Qwen"
    case openAICompatible = "OpenAI-compatible"
}

/// Built-in services retain their own groups; every user-defined endpoint uses the shared protocol group.
public func providerGroup(for name: String) -> ProviderGroup {
    switch name {
    case "deepseek": .deepseek
    case "qwen": .qwen
    default: .openAICompatible
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var apiKeyEnv: String
    public var apiKey: String?
    public var temperature: Double?
    public var reasoningEffort: ReasoningEffort
    public var apiStyle: APIStyle

    public init(
        baseURL: String,
        model: String,
        apiKeyEnv: String,
        apiKey: String? = nil,
        temperature: Double? = nil,
        reasoningEffort: ReasoningEffort = .none,
        apiStyle: APIStyle = .openAI
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKeyEnv = apiKeyEnv
        self.apiKey = apiKey
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.apiStyle = apiStyle
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, model, apiKeyEnv, apiKey, temperature, reasoningEffort, apiStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        apiKeyEnv = try c.decode(String.self, forKey: .apiKeyEnv)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .none
        // Older configs predate the field; they were all OpenAI-style.
        apiStyle = try c.decodeIfPresent(APIStyle.self, forKey: .apiStyle) ?? .openAI
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        try c.encode(apiKeyEnv, forKey: .apiKeyEnv)
        try c.encodeIfPresent(apiKey, forKey: .apiKey)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encode(reasoningEffort, forKey: .reasoningEffort)
        // Keep existing files byte-stable: only write the style when it is not the default.
        if apiStyle != .openAI { try c.encode(apiStyle, forKey: .apiStyle) }
    }
}

public struct CommandConfig: Codable, Equatable, Sendable {
    public var name: String
    public var hotkey: String
    public var provider: String?
    public var model: String?
    public var reasoningEffort: ReasoningEffort?
    public var prompt: String

    public init(
        name: String,
        hotkey: String,
        provider: String? = nil,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        prompt: String
    ) {
        self.name = name
        self.hotkey = hotkey
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.prompt = prompt
    }

    enum CodingKeys: String, CodingKey {
        case name, hotkey, provider, model, reasoningEffort, prompt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        hotkey = try c.decode(String.self, forKey: .hotkey)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        prompt = try c.decode(String.self, forKey: .prompt)
    }
}

public func makeNewCommand(existing: [CommandConfig]) -> CommandConfig {
    let names = Set(existing.map(\.name))
    var name = "New command"
    var suffix = 2
    while names.contains(name) { name = "New command \(suffix)"; suffix += 1 }
    return CommandConfig(name: name, hotkey: "", prompt: "Translate the following text:\n\n{selection}")
}

public struct YiyiConfig: Codable, Equatable, Sendable {
    public var defaultProvider: String
    public var providers: [String: ProviderConfig]
    public var autoCopy: Bool
    public var superKey: SuperKey
    public var pointerTrigger: PointerTriggerConfig
    public var commands: [CommandConfig]

    public static let defaultProviders: [String: ProviderConfig] = [
        "deepseek": ProviderConfig(baseURL: "https://api.deepseek.com/v1", model: "deepseek-v4-flash", apiKeyEnv: "DEEPSEEK_API_KEY"),
        "qwen": ProviderConfig(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", apiKeyEnv: "DASHSCOPE_API_KEY")
    ]
    public static let defaultCommands = [
        CommandConfig(name: "Translate to Chinese", hotkey: "cmd+-", prompt: "Translate the following into Chinese. Output only the translation, no explanation.\n\n{selection}"),
        CommandConfig(name: "Translate to English", hotkey: "cmd+shift+-", prompt: "Translate the following into English. Output only the translation, no explanation.\n\n{selection}")
    ]

    public init(
        defaultProvider: String = "deepseek",
        providers: [String: ProviderConfig] = defaultProviders,
        autoCopy: Bool = true,
        superKey: SuperKey = .none,
        pointerTrigger: PointerTriggerConfig = .init(),
        commands: [CommandConfig] = defaultCommands
    ) {
        self.defaultProvider = defaultProvider
        self.providers = providers
        self.autoCopy = autoCopy
        self.superKey = superKey
        self.pointerTrigger = pointerTrigger
        self.commands = commands
    }

    enum CodingKeys: String, CodingKey {
        case defaultProvider, providers, autoCopy, superKey, pointerTrigger, commands
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultProvider = try c.decodeIfPresent(String.self, forKey: .defaultProvider) ?? "deepseek"
        providers = try c.decodeIfPresent([String: ProviderConfig].self, forKey: .providers) ?? Self.defaultProviders
        autoCopy = try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? true
        superKey = try c.decodeIfPresent(SuperKey.self, forKey: .superKey) ?? .none
        pointerTrigger = try c.decodeIfPresent(PointerTriggerConfig.self, forKey: .pointerTrigger) ?? .init()
        commands = try c.decodeIfPresent([CommandConfig].self, forKey: .commands) ?? Self.defaultCommands
    }
}

/// Applies an update only after its candidate representation has been persisted successfully.
public func updatePersistedConfig(
    _ config: inout YiyiConfig,
    mutation: (inout YiyiConfig) -> Void,
    persist: (YiyiConfig) throws -> Void
) throws {
    var candidate = config
    mutation(&candidate)
    try persist(candidate)
    config = candidate
}

public struct ResolvedProvider: Equatable, Sendable {
    public let name: String
    public let baseURL: String
    public let model: String
    public let apiKeyEnv: String
    public let temperature: Double?
    public let reasoningEffort: ReasoningEffort
    public let apiStyle: APIStyle

    public init(
        name: String,
        baseURL: String,
        model: String,
        apiKeyEnv: String,
        temperature: Double? = nil,
        reasoningEffort: ReasoningEffort = .none,
        apiStyle: APIStyle = .openAI
    ) {
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiKeyEnv = apiKeyEnv
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.apiStyle = apiStyle
    }
}

public enum ProviderResolutionError: Error, LocalizedError, Equatable {
    case unknownProvider(String)
    case missingKey(provider: String, env: String)
    public var errorDescription: String? {
        switch self {
        case let .unknownProvider(name): "unknown provider '\(name)'"
        case let .missingKey(provider, env): "no API key for provider '\(provider)': set \(env) or providers.\(provider).apiKey in ~/.config/yiyi/config.json"
        }
    }
}

public func resolveProvider(config: YiyiConfig, command: CommandConfig) throws -> ResolvedProvider {
    let name = command.provider ?? config.defaultProvider
    guard let provider = config.providers[name] else { throw ProviderResolutionError.unknownProvider(name) }
    return ResolvedProvider(
        name: name,
        baseURL: provider.baseURL,
        model: command.model ?? provider.model,
        apiKeyEnv: provider.apiKeyEnv,
        temperature: provider.temperature,
        reasoningEffort: command.reasoningEffort ?? provider.reasoningEffort,
        apiStyle: provider.apiStyle
    )
}

public func resolveAPIKey(providerName: String, config: YiyiConfig, environment: [String: String], dotEnv: [String: String], defaultProviderKey: String?) throws -> String {
    guard let provider = config.providers[providerName] else { throw ProviderResolutionError.unknownProvider(providerName) }
    if let key = provider.apiKey, !key.isEmpty { return key }
    if let key = environment[provider.apiKeyEnv], !key.isEmpty { return key }
    if let key = dotEnv[provider.apiKeyEnv], !key.isEmpty { return key }
    if providerName == config.defaultProvider, let key = defaultProviderKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty { return key }
    throw ProviderResolutionError.missingKey(provider: providerName, env: provider.apiKeyEnv)
}

public struct PromptPlaceholder: Equatable, Sendable {
    public let range: NSRange
    public let name: String
    public let isSupported: Bool

    public init(range: NSRange, name: String, isSupported: Bool) {
        self.range = range
        self.name = name
        self.isSupported = isSupported
    }
}

private let supportedPromptPlaceholders: Set<String> = ["selection", "input", "clipboard", "copy"]
private let promptPlaceholderPattern = try! NSRegularExpression(pattern: #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#)

public func promptPlaceholders(in template: String) -> [PromptPlaceholder] {
    let fullRange = NSRange(template.startIndex..<template.endIndex, in: template)
    return promptPlaceholderPattern.matches(in: template, range: fullRange).compactMap { match in
        guard let nameRange = Range(match.range(at: 1), in: template) else { return nil }
        let name = String(template[nameRange])
        return PromptPlaceholder(range: match.range, name: name, isSupported: supportedPromptPlaceholders.contains(name))
    }
}

public func promptNeedsSelection(_ template: String) -> Bool {
    promptPlaceholders(in: template).contains { $0.name == "selection" || $0.name == "input" }
}

public func promptNeedsClipboard(_ template: String) -> Bool {
    promptPlaceholders(in: template).contains { $0.name == "clipboard" || $0.name == "copy" }
}

public enum PromptTemplateError: Error, LocalizedError, Equatable {
    case missingPlaceholder
    case unsupportedPlaceholder(String)
    case missingClipboard

    public var errorDescription: String? {
        switch self {
        case .missingPlaceholder: "Prompt must contain {selection}, {input}, {clipboard}, or {copy}."
        case let .unsupportedPlaceholder(name): "Unknown prompt placeholder {\(name)}. Use {selection}, {input}, {clipboard}, or {copy}."
        case .missingClipboard: "This prompt requires clipboard text, but the clipboard is empty."
        }
    }
}

public func renderPrompt(_ template: String, input: String, clipboard: String? = nil) throws -> String {
    let placeholders = promptPlaceholders(in: template)
    guard !placeholders.isEmpty else { throw PromptTemplateError.missingPlaceholder }
    if let unsupported = placeholders.first(where: { !$0.isSupported }) {
        throw PromptTemplateError.unsupportedPlaceholder(unsupported.name)
    }
    if promptNeedsClipboard(template), clipboard == nil { throw PromptTemplateError.missingClipboard }

    let source = template as NSString
    var result = ""
    var cursor = 0
    for placeholder in placeholders {
        result += source.substring(with: NSRange(location: cursor, length: placeholder.range.location - cursor))
        switch placeholder.name {
        case "selection", "input": result += input
        case "clipboard", "copy": result += clipboard!
        default: break // Unsupported placeholders were rejected above.
        }
        cursor = NSMaxRange(placeholder.range)
    }
    result += source.substring(from: cursor)
    return result
}

public enum ConfigValidationError: Error, LocalizedError, Equatable {
    case emptyProviderName
    case duplicateProvider(String)
    case defaultProviderCannotBeRemoved(String)
    case emptyCommandName
    case duplicateHotkey(String)
    case invalidHotkey(String)
    case emptyPrompt
    case missingPromptPlaceholder
    case unsupportedPromptPlaceholder(String)
    case invalidTemperature(String)

    public var errorDescription: String? {
        switch self {
        case .emptyProviderName: "Provider name cannot be empty."
        case let .duplicateProvider(name): "A provider named “\(name)” already exists."
        case let .defaultProviderCannotBeRemoved(name): "“\(name)” is the default provider. Choose another default before removing it."
        case .emptyCommandName: "Command name cannot be empty."
        case let .duplicateHotkey(value): "The shortcut “\(value)” is already used by another command."
        case let .invalidHotkey(value): "“\(value)” is not a valid shortcut."
        case .emptyPrompt: "Prompt cannot be empty."
        case .missingPromptPlaceholder: "Prompt must contain {selection}, {input}, {clipboard}, or {copy}."
        case let .unsupportedPromptPlaceholder(name): "Unknown prompt placeholder {\(name)}. Use {selection}, {input}, {clipboard}, or {copy}."
        case let .invalidTemperature(value): "“\(value)” is not a number."
        }
    }
}

public func validateProviderName(_ name: String, existing: Set<String>) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ConfigValidationError.emptyProviderName }
    guard !existing.contains(trimmed) else { throw ConfigValidationError.duplicateProvider(trimmed) }
    return trimmed
}

public func validateTemperature(_ value: String) throws -> Double? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let result = Double(trimmed) else { throw ConfigValidationError.invalidTemperature(value) }
    return result
}

public func validateCommand(name: String? = nil, hotkey: String? = nil, prompt: String? = nil, commands: [CommandConfig], excluding index: Int) throws {
    if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ConfigValidationError.emptyCommandName }
    if let hotkey, !hotkey.isEmpty {
        do { _ = try parseBinding(hotkey) } catch { throw ConfigValidationError.invalidHotkey(hotkey) }
        if commands.enumerated().contains(where: { $0.offset != index && $0.element.hotkey.lowercased() == hotkey.lowercased() }) {
            throw ConfigValidationError.duplicateHotkey(hotkey)
        }
    }
    if let prompt {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigValidationError.emptyPrompt }
        let placeholders = promptPlaceholders(in: prompt)
        if let unsupported = placeholders.first(where: { !$0.isSupported }) {
            throw ConfigValidationError.unsupportedPromptPlaceholder(unsupported.name)
        }
        guard placeholders.contains(where: \.isSupported) else { throw ConfigValidationError.missingPromptPlaceholder }
    }
}
