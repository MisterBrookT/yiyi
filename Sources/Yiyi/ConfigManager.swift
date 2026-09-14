import Foundation
import Darwin
import YiyiCore

@MainActor final class ConfigManager {
    let directory: URL
    private let persistsChanges: Bool

    init() {
        if let path = ProcessInfo.processInfo.environment["YIYI_CONFIG_DIR"], !path.isEmpty { directory = URL(fileURLWithPath: path, isDirectory: true) }
        else { directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/yiyi") }
        persistsChanges = true
    }

    private init(draftOf manager: ConfigManager) {
        directory = manager.directory
        config = manager.config
        persistsChanges = false
    }

    func makeDraft() -> ConfigManager { ConfigManager(draftOf: self) }
    func resetDraft(to value: YiyiConfig) {
        precondition(!persistsChanges)
        config = value
        onChange?()
    }

    func apply(_ value: YiyiConfig, replacing expected: YiyiConfig) throws {
        precondition(persistsChanges)
        let disk = try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: fileURL))
        guard config == expected, disk == expected else { throw SettingsSaveError.conflict }
        try persist(value)
        config = value
        onChange?()
    }
    var fileURL: URL { directory.appendingPathComponent("config.json") }
    private(set) var config = YiyiConfig()
    var onChange: (() -> Void)?

    func load() throws {
        precondition(persistsChanges)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            config = try JSONDecoder().decode(YiyiConfig.self, from: Data(contentsOf: fileURL))
        }
        _ = migrateLegacySuperKeyBindings(in: &config)
        try save()
    }

    func save() throws {
        precondition(persistsChanges)
        try persist(config)
    }

    private func persist(_ candidate: YiyiConfig) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let temporary = directory.appendingPathComponent(".config-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: try encoder.encode(candidate), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, fileURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func update(_ mutation: (inout YiyiConfig) -> Void) throws {
        if persistsChanges { try updatePersistedConfig(&config, mutation: mutation, persist: persist) }
        else { mutation(&config) }
        onChange?()
    }

    func setDefaultProvider(_ name: String) throws {
        guard config.providers[name] != nil else { throw ProviderResolutionError.unknownProvider(name) }
        try update { $0.defaultProvider = name }
    }
    func setProvider(
        _ name: String,
        baseURL: String? = nil,
        model: String? = nil,
        apiKeyEnv: String? = nil,
        apiKey: String?? = nil,
        temperature: Double?? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        apiStyle: APIStyle? = nil
    ) throws {
        try update {
            guard var provider = $0.providers[name] else { return }
            if let apiStyle { provider.apiStyle = apiStyle }
            if let baseURL { provider.baseURL = baseURL }
            if let model { provider.model = model }
            if let apiKeyEnv { provider.apiKeyEnv = apiKeyEnv }
            if let apiKey { provider.apiKey = apiKey }
            if let temperature { provider.temperature = temperature }
            if let reasoningEffort { provider.reasoningEffort = reasoningEffort }
            $0.providers[name] = provider
        }
    }
    func addProvider(named rawName: String) throws {
        let name = try validateProviderName(rawName, existing: Set(config.providers.keys))
        try update {
            $0.providers[name] = ProviderConfig(baseURL: "https://api.example.com/v1", model: "model", apiKeyEnv: "\(name.uppercased().replacingOccurrences(of: "-", with: "_"))_API_KEY")
        }
    }
    func deleteProvider(named name: String) throws {
        guard name != config.defaultProvider else { throw ConfigValidationError.defaultProviderCannotBeRemoved(name) }
        try update {
            $0.providers.removeValue(forKey: name)
            for index in $0.commands.indices where $0.commands[index].provider == name { $0.commands[index].provider = nil }
        }
    }
    func setCommand(_ index: Int, name: String? = nil, prompt: String? = nil, hotkey: String? = nil, provider: String?? = nil, model: String?? = nil, reasoningEffort: ReasoningEffort?? = nil) throws {
        try validateCommand(name: name, hotkey: hotkey, prompt: prompt, commands: config.commands, excluding: index)
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
        try update { $0.commands.append(makeNewCommand(existing: $0.commands)) }
    }
    func deleteCommand(at index: Int) throws {
        try update {
            guard $0.commands.indices.contains(index) else { return }
            $0.commands.remove(at: index)
            if $0.pointerTrigger.commandIndex == index { $0.pointerTrigger.enabled = false; $0.pointerTrigger.commandIndex = 0 }
            else if $0.pointerTrigger.commandIndex > index { $0.pointerTrigger.commandIndex -= 1 }
        }
    }
    func setPointerTrigger(_ value: PointerTriggerConfig) throws { try update { $0.pointerTrigger = value } }
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
