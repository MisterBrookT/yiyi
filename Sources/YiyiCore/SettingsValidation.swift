import Foundation

public enum SettingsSaveError: Error, LocalizedError {
    case conflict
    case invalidURL
    case missingModel
    case hyperKeyDisabled

    public var errorDescription: String? {
        switch self {
        case .conflict: "Settings changed outside this window. Cancel and reopen Settings to load the latest values."
        case .invalidURL: "Enter an HTTP or HTTPS base URL, usually ending in /v1."
        case .missingModel: "Enter the model name supplied by your server."
        case .hyperKeyDisabled: "Choose a Hyper Key, or record a regular keyboard shortcut."
        }
    }
}

/// Credentials must not silently move to a different origin (including TLS downgrades).
public func requiresKeyDestinationConfirmation(from old: String, to new: String) -> Bool {
    func origin(_ value: String) -> String? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        return "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }
    return origin(old) != origin(new)
}

public func validateConnection(_ provider: ProviderConfig) throws {
    guard let url = URL(string: provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
          ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
          url.query == nil, url.fragment == nil,
          !url.path.hasSuffix("/chat/completions") else { throw SettingsSaveError.invalidURL }
    guard !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SettingsSaveError.missingModel }
}
