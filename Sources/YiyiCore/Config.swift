import Foundation

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var apiKeyEnv: String
    public var apiKey: String?
    public init(baseURL: String, model: String, apiKeyEnv: String, apiKey: String? = nil) {
        self.baseURL = baseURL; self.model = model; self.apiKeyEnv = apiKeyEnv; self.apiKey = apiKey
    }
}

public struct CommandConfig: Codable, Equatable, Sendable {
    public var name: String
    public var hotkey: String
    public var provider: String?
    public var model: String?
    public var prompt: String
    public init(name: String, hotkey: String, provider: String? = nil, model: String? = nil, prompt: String) {
        self.name = name; self.hotkey = hotkey; self.provider = provider; self.model = model; self.prompt = prompt
    }
}

public struct YiyiConfig: Codable, Equatable, Sendable {
    public var defaultProvider: String
    public var providers: [String: ProviderConfig]
    public var autoCopy: Bool
    public var commands: [CommandConfig]

    public static let defaultProviders: [String: ProviderConfig] = [
        "openrouter": ProviderConfig(baseURL: "https://openrouter.ai/api/v1", model: "google/gemini-2.5-flash-lite", apiKeyEnv: "OPENROUTER_API_KEY"),
        "deepseek": ProviderConfig(baseURL: "https://api.deepseek.com/v1", model: "deepseek-v4-flash", apiKeyEnv: "DEEPSEEK_API_KEY"),
        "qwen": ProviderConfig(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", apiKeyEnv: "DASHSCOPE_API_KEY"),
        "ark": ProviderConfig(baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: "doubao-1-5-lite-32k-250115", apiKeyEnv: "ARK_API_KEY")
    ]
    public static let defaultCommands = [
        CommandConfig(name: "Translate to Chinese", hotkey: "cmd+-", prompt: "Translate the following into Chinese. Output only the translation, no explanation.\n\n{selection}"),
        CommandConfig(name: "Translate to English", hotkey: "cmd+shift+-", prompt: "Translate the following into English. Output only the translation, no explanation.\n\n{selection}")
    ]
    public init(defaultProvider: String = "deepseek", providers: [String: ProviderConfig] = defaultProviders, autoCopy: Bool = true, commands: [CommandConfig] = defaultCommands) {
        self.defaultProvider = defaultProvider; self.providers = providers; self.autoCopy = autoCopy; self.commands = commands
    }
    enum CodingKeys: String, CodingKey { case defaultProvider, providers, autoCopy, commands }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultProvider = try c.decodeIfPresent(String.self, forKey: .defaultProvider) ?? "deepseek"
        providers = try c.decodeIfPresent([String: ProviderConfig].self, forKey: .providers) ?? Self.defaultProviders
        autoCopy = try c.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? true
        commands = try c.decodeIfPresent([CommandConfig].self, forKey: .commands) ?? Self.defaultCommands
    }
}

public struct ResolvedProvider: Equatable, Sendable {
    public let name: String
    public let baseURL: String
    public let model: String
    public let apiKeyEnv: String
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
    return ResolvedProvider(name: name, baseURL: provider.baseURL, model: command.model ?? provider.model, apiKeyEnv: provider.apiKeyEnv)
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
