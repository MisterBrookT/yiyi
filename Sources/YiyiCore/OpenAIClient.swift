import Foundation

public struct ChatCompletionResponse: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Message: Decodable, Sendable { public let content: String }
        public let message: Message
    }
    public let choices: [Choice]
}

public struct ProviderErrorPayload: Decodable, Sendable {
    public struct Detail: Decodable, Sendable { public let message: String }
    public let error: Detail
}

public enum OpenAIError: Error, LocalizedError, Equatable {
    case invalidURL, invalidResponse, emptyResponse, http(Int, String), provider(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid provider URL"
        case .invalidResponse: "Invalid response from provider"
        case .emptyResponse: "Provider returned no text"
        case let .http(status, body): "HTTP \(status): \(body)"
        case let .provider(message): message
        }
    }
}

public func parseChatCompletion(_ data: Data) throws -> String {
    if let payload = try? JSONDecoder().decode(ProviderErrorPayload.self, from: data) { throw OpenAIError.provider(payload.error.message) }
    let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    guard let text = response.choices.first?.message.content, !text.isEmpty else { throw OpenAIError.emptyResponse }
    return text
}

public func buildChatCompletionBody(prompt: String, provider: ResolvedProvider) throws -> Data {
    var body: [String: Any] = [
        "model": provider.model,
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": 1024
    ]
    if let temperature = provider.temperature {
        body["temperature"] = temperature
    }
    if provider.reasoningEffort != .none {
        body["reasoning_effort"] = provider.reasoningEffort.rawValue
    }
    return try JSONSerialization.data(withJSONObject: body)
}

public struct OpenAIClient: Sendable {
    public init() {}
    public func complete(prompt: String, provider: ResolvedProvider, apiKey: String) async throws -> String {
        guard let base = URL(string: provider.baseURL), let url = URL(string: "chat/completions", relativeTo: base.appendingPathComponent("/")) else { throw OpenAIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("yiyi", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = try buildChatCompletionBody(prompt: prompt, provider: provider)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(decoding: data.prefix(500), as: UTF8.self)
            throw OpenAIError.http(http.statusCode, snippet)
        }
        return try parseChatCompletion(data)
    }
}
