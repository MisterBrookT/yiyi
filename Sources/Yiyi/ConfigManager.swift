import Foundation
import YiyiCore

@MainActor final class ConfigManager {
    let directory: URL = {
        if let path = ProcessInfo.processInfo.environment["YIYI_CONFIG_DIR"], !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/yiyi")
    }()
    var fileURL: URL { directory.appendingPathComponent("config.json") }
    private(set) var config = YiyiConfig()
    var onChange: (() -> Void)?

    func load() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            config = try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: fileURL))
        }
        try save()
    }

    func save() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }

    private func update(_ mutation: (inout YiyiConfig) -> Void) throws {
        mutation(&config)
        try save()
        onChange?()
    }

    func setDefaultProvider(_ name: String) throws { try update { $0.defaultProvider = name } }
    func setProvider(_ name: String, model: String? = nil, apiKey: String?? = nil, temperature: Double?? = nil, reasoningEffort: ReasoningEffort? = nil) throws {
        try update {
            guard var provider = $0.providers[name] else { return }
            if let model { provider.model = model }
            if let apiKey { provider.apiKey = apiKey }
            if let temperature { provider.temperature = temperature }
            if let reasoningEffort { provider.reasoningEffort = reasoningEffort }
            $0.providers[name] = provider
        }
    }
    func setCommand(_ index: Int, name: String? = nil, prompt: String? = nil, hotkey: String? = nil, provider: String?? = nil, model: String?? = nil, reasoningEffort: ReasoningEffort?? = nil) throws {
        try update {
            guard $0.commands.indices.contains(index) else { return }
            if let name { $0.commands[index].name = name }
            if let prompt { $0.commands[index].prompt = prompt }
            if let hotkey { $0.commands[index].hotkey = hotkey }
            if let provider { $0.commands[index].provider = provider }
            if let model { $0.commands[index].model = model }
            if let reasoningEffort { $0.commands[index].reasoningEffort = reasoningEffort }
        }
    }
    func addCommand() throws {
        try update { $0.commands.append(CommandConfig(name: "New command", hotkey: "", prompt: "Translate the following text:\n\n{selection}")) }
    }
    func deleteCommand(at index: Int) throws { try update { if $0.commands.indices.contains(index) { $0.commands.remove(at: index) } } }
    func setSuperKey(_ value: SuperKey) throws { try update { $0.superKey = value } }
    func setAutoCopy(_ value: Bool) throws { try update { $0.autoCopy = value } }

    func apiKey(for providerName: String) throws -> String {
        let fallback = try? String(contentsOf: directory.appendingPathComponent("apikey"), encoding: .utf8)
        return try resolveAPIKey(providerName: providerName, config: config, environment: ProcessInfo.processInfo.environment, dotEnv: environmentFromDotEnv(), defaultProviderKey: fallback)
    }

    func apiKeyStatus(for name: String) -> String {
        guard let provider = config.providers[name] else { return "missing: unknown provider '\(name)'" }
        if let key = provider.apiKey, !key.isEmpty { return "key source: providers.\(name).apiKey in config" }
        if !(ProcessInfo.processInfo.environment[provider.apiKeyEnv] ?? "").isEmpty { return "key source: environment \(provider.apiKeyEnv)" }
        if !(environmentFromDotEnv()[provider.apiKeyEnv] ?? "").isEmpty { return "key source: ~/.config/yiyi/.env (\(provider.apiKeyEnv))" }
        let fallback = (try? String(contentsOf: directory.appendingPathComponent("apikey"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == config.defaultProvider, !(fallback ?? "").isEmpty { return "key source: ~/.config/yiyi/apikey" }
        return "missing: set providers.\(name).apiKey, \(provider.apiKeyEnv), ~/.config/yiyi/.env, or \(name == config.defaultProvider ? "~/.config/yiyi/apikey" : "make this provider default to use ~/.config/yiyi/apikey")"
    }

    func providerAvailability(_ name: String) -> (usable: Bool, reason: String?) {
        do { _ = try apiKey(for: name); return (true, nil) }
        catch { return (false, error.localizedDescription) }
    }

    private func environmentFromDotEnv() -> [String: String] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(".env"), encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.first == "\"" && value.last == "\"" || value.first == "'" && value.last == "'") { value.removeFirst(); value.removeLast() }
            result[name] = value
        }
        return result
    }
}
