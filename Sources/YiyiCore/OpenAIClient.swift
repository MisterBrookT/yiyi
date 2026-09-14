import Foundation

public struct ChatCompletionResponse: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public struct Message: Decodable, Sendable { public let content: String? }
        public let message: Message
        public let finishReason: String?
        enum CodingKeys: String, CodingKey { case message, finishReason = "finish_reason" }
    }
    public let choices: [Choice]
}

public struct ProviderErrorPayload: Decodable, Sendable {
    public struct Detail: Decodable, Sendable { public let message: String }
    public let error: Detail
}

public enum OpenAIError: Error, LocalizedError, Equatable {
    case invalidURL, invalidResponse, emptyResponse, truncated, http(Int, String), provider(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid provider URL"
        case .invalidResponse: "Invalid response from provider"
        case .emptyResponse: "Provider returned no text"
        case .truncated: "Provider hit the token limit before answering; lower reasoning effort or shorten the selection"
        case let .http(status, body): "HTTP \(status): \(body)"
        case let .provider(message): message
        }
    }
}

public func parseChatCompletion(_ data: Data) throws -> String {
    if let payload = try? JSONDecoder().decode(ProviderErrorPayload.self, from: data) { throw OpenAIError.provider(payload.error.message) }
    let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    guard let choice = response.choices.first else { throw OpenAIError.emptyResponse }
    guard let text = choice.message.content, !text.isEmpty else {
        throw choice.finishReason == "length" ? OpenAIError.truncated : OpenAIError.emptyResponse
    }
    return text
}

public func buildChatCompletionBody(prompt: String, provider: ResolvedProvider) throws -> Data {
    var body: [String: Any] = [
        "model": provider.model,
        "messages": [["role": "user", "content": prompt]],
        "max_tokens": 4096,
        "reasoning_effort": provider.reasoningEffort.rawValue
    ]
    if let temperature = provider.temperature {
        body["temperature"] = temperature
    }
    return try JSONSerialization.data(withJSONObject: body)
}

// MARK: - Anthropic Messages API

public struct AnthropicMessageResponse: Decodable, Sendable {
    public struct Block: Decodable, Sendable {
        public let type: String
        public let text: String?
    }
    public let content: [Block]
    public let stopReason: String?
    enum CodingKeys: String, CodingKey { case content, stopReason = "stop_reason" }
}

public struct AnthropicErrorPayload: Decodable, Sendable {
    public struct Detail: Decodable, Sendable { public let message: String }
    public let type: String
    public let error: Detail
}

/// Anthropic has no `reasoning_effort`; map the shared scale onto a thinking budget.
/// `none` sends no thinking block at all.
public func anthropicThinkingBudget(for effort: ReasoningEffort) -> Int? {
    switch effort {
    case .none: nil
    case .minimal: 1024
    case .low: 2048
    case .medium: 8192
    case .high: 16384
    }
}

public func buildAnthropicMessagesBody(prompt: String, provider: ResolvedProvider) throws -> Data {
    let budget = anthropicThinkingBudget(for: provider.reasoningEffort)
    var body: [String: Any] = [
        "model": provider.model,
        "messages": [["role": "user", "content": prompt]],
        // The budget must be strictly smaller than max_tokens; leave room for the answer itself.
        "max_tokens": 4096 + (budget ?? 0)
    ]
    if let budget {
        body["thinking"] = ["type": "enabled", "budget_tokens": budget]
    } else if let temperature = provider.temperature {
        // Anthropic rejects temperature alongside extended thinking.
        body["temperature"] = temperature
    }
    return try JSONSerialization.data(withJSONObject: body)
}

public func parseAnthropicMessage(_ data: Data) throws -> String {
    if let payload = try? JSONDecoder().decode(AnthropicErrorPayload.self, from: data), payload.type == "error" {
        throw OpenAIError.provider(payload.error.message)
    }
    let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
    let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
    guard !text.isEmpty else {
        throw response.stopReason == "max_tokens" ? OpenAIError.truncated : OpenAIError.emptyResponse
    }
    return text
}

// MARK: - Request assembly

/// Builds the full HTTP request for either protocol. Pure, so both paths are unit-testable.
public func buildCompletionRequest(prompt: String, provider: ResolvedProvider, apiKey: String) throws -> URLRequest {
    guard let base = URL(string: provider.baseURL) else { throw OpenAIError.invalidURL }
    let root = base.appendingPathComponent("/")
    var request: URLRequest
    switch provider.apiStyle {
    case .openAI:
        guard let url = URL(string: "chat/completions", relativeTo: root) else { throw OpenAIError.invalidURL }
        request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try buildChatCompletionBody(prompt: prompt, provider: provider)
    case .anthropic:
        guard let url = URL(string: "messages", relativeTo: root) else { throw OpenAIError.invalidURL }
        request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try buildAnthropicMessagesBody(prompt: prompt, provider: provider)
    }
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("yiyi", forHTTPHeaderField: "X-Title")
    request.timeoutInterval = 60
    return request
}

public func parseCompletion(_ data: Data, style: APIStyle) throws -> String {
    switch style {
    case .openAI: try parseChatCompletion(data)
    case .anthropic: try parseAnthropicMessage(data)
    }
}

public struct OpenAIClient: Sendable {
    public init() {}
    public func complete(prompt: String, provider: ResolvedProvider, apiKey: String) async throws -> String {
        let request = try buildCompletionRequest(prompt: prompt, provider: provider, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(decoding: data.prefix(500), as: UTF8.self)
            throw OpenAIError.http(http.statusCode, snippet)
        }
        return try parseCompletion(data, style: provider.apiStyle)
    }
}
