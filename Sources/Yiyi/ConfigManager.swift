import Foundation
import YiyiCore

@MainActor final class ConfigManager {
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/yiyi")
    var fileURL: URL { directory.appendingPathComponent("config.json") }
    private(set) var config = YiyiConfig()

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

    func setDefaultProvider(_ name: String) throws { config.defaultProvider = name; try save() }

    func apiKey(for providerName: String) throws -> String {
        let keyFile = directory.appendingPathComponent("apikey")
        let fallback = try? String(contentsOf: keyFile, encoding: .utf8)
        return try resolveAPIKey(providerName: providerName, config: config, environment: ProcessInfo.processInfo.environment, dotEnv: environmentFromDotEnv(), defaultProviderKey: fallback)
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
