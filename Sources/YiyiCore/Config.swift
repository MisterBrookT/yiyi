import Foundation

public enum ReasoningEffort: String, Codable, Sendable, CaseIterable {
    case none, minimal, low, medium, high
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var apiKeyEnv: String
    public var apiKey: String?
    public var temperature: Double?
    public var reasoningEffort: ReasoningEffort

    public init(
        baseURL: String,
        model: String,
        apiKeyEnv: String,
        apiKey: String? = nil,
        temperature: Double? = nil,
        reasoningEffort: ReasoningEffort = .none
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKeyEnv = apiKeyEnv
        self.apiKey = apiKey
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, model, apiKeyEnv, apiKey, temperature, reasoningEffort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        apiKeyEnv = try c.decode(String.self, forKey: .apiKeyEnv)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .none
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

public struct YiyiConfig: Codable, Equatable, Sendable {
    public var defaultProvider: String
    public var providers: [String: ProviderConfig]
    public var autoCopy: Bool
    public var superKey: SuperKey
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
        commands: [CommandConfig] = defaultCommands
    ) {
        self.defaultProvider = defaultProvider
        self.providers = providers
        self.autoCopy = autoCopy
        self.superKey = superKey
        self.commands = commands
    }

    enum CodingKeys: String, CodingKey {
        case defaultProvider, providers, autoCopy, superKey, commands
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultProvider = try c.decodeIfPresent(String.self, forKey: .defaultProvider) ?? "deepseek"
        providers = try c.decodeIfPresent([String: ProviderConfig].self, forKey: .providers) ?? Self.defaultProviders
        autoCopy = try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? true
        superKey = try c.decodeIfPresent(SuperKey.self, forKey: .superKey) ?? .none
        commands = try c.decodeIfPresent([CommandConfig].self, forKey: .commands) ?? Self.defaultCommands
    }
}

public struct ResolvedProvider: Equatable, Sendable {
    public let name: String
    public let baseURL: String
    public let model: String
    public let apiKeyEnv: String
    public let temperature: Double?
    public let reasoningEffort: ReasoningEffort

    public init(
        name: String,
        baseURL: String,
        model: String,
        apiKeyEnv: String,
        temperature: Double? = nil,
        reasoningEffort: ReasoningEffort = .none
    ) {
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiKeyEnv = apiKeyEnv
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
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
        reasoningEffort: command.reasoningEffort ?? provider.reasoningEffort
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

public enum PromptTemplateError: Error, Equatable { case missingPlaceholder }
public func renderPrompt(_ template: String, input: String) throws -> String {
    guard template.contains("{selection}") || template.contains("{input}") else { throw PromptTemplateError.missingPlaceholder }
    return template.replacingOccurrences(of: "{selection}", with: input).replacingOccurrences(of: "{input}", with: input)
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
        case .missingPromptPlaceholder: "Prompt must contain {selection} or {input}."
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
    if let hotkey {
        do { _ = try parseBinding(hotkey) } catch { throw ConfigValidationError.invalidHotkey(hotkey) }
        if commands.enumerated().contains(where: { $0.offset != index && $0.element.hotkey.lowercased() == hotkey.lowercased() }) {
            throw ConfigValidationError.duplicateHotkey(hotkey)
        }
    }
    if let prompt {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigValidationError.emptyPrompt }
        guard prompt.contains("{selection}") || prompt.contains("{input}") else { throw ConfigValidationError.missingPromptPlaceholder }
    }
}
