import Foundation

/// Anything that can turn a system + user prompt into text. Lets tests swap in a fake.
protocol LLMCompleting: Sendable {
    var displayName: String { get }
    func complete(system: String, user: String) async throws -> String
}

enum LLMError: LocalizedError, Equatable {
    case notConfigured(String)
    case badEndpoint(String)
    case http(status: Int, message: String)
    case emptyResponse
    case unreadableAnswer

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "AI provider isn't set up: \(what)."
        case .badEndpoint(let url): return "Invalid endpoint URL: \(url)"
        case .http(let status, let message): return "The AI service returned HTTP \(status): \(message)"
        case .emptyResponse: return "The AI service returned an empty answer."
        case .unreadableAnswer: return "The AI answer wasn't in the expected format."
        }
    }
}

/// One client for every remote provider. Azure OpenAI, OpenAI, Gemini, Ollama and custom
/// servers speak the OpenAI Chat Completions format; Anthropic uses the Messages API.
struct RemoteLLMClient: LLMCompleting {
    let kind: LLMProviderKind
    let config: LLMProviderConfig
    let apiKey: String?
    var timeout: TimeInterval = 90
    var maxTokens = 1200

    var displayName: String {
        let model = kind == .azureOpenAI ? config.deployment : config.model
        return model.isEmpty ? kind.title : "\(kind.title) · \(model)"
    }

    /// What's missing before requests can be sent, or nil when ready.
    var configurationProblem: String? {
        let endpoint = config.endpoint.trimmingCharacters(in: .whitespaces)
        if kind == .onDevice { return "on-device isn't a remote provider" }
        if endpoint.isEmpty || endpoint.contains("YOUR-RESOURCE") { return "enter the endpoint URL" }
        if URL(string: endpoint)?.scheme == nil { return "the endpoint must start with https://" }
        if kind.needsAPIKey && (apiKey ?? "").isEmpty { return "enter an API key" }
        if kind == .azureOpenAI {
            if config.deployment.trimmingCharacters(in: .whitespaces).isEmpty { return "enter the deployment name" }
            if config.apiVersion.trimmingCharacters(in: .whitespaces).isEmpty { return "enter the API version" }
        } else if config.model.trimmingCharacters(in: .whitespaces).isEmpty {
            return "enter a model name"
        }
        return nil
    }

    // MARK: Request

    func makeRequest(system: String, user: String) throws -> URLRequest {
        if let problem = configurationProblem { throw LLMError.notConfigured(problem) }
        let base = config.endpoint.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString: String
        switch kind {
        case .azureOpenAI:
            let deployment = config.deployment.trimmingCharacters(in: .whitespaces)
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.deployment
            let version = config.apiVersion.trimmingCharacters(in: .whitespaces)
            urlString = "\(base)/openai/deployments/\(deployment)/chat/completions?api-version=\(version)"
        case .anthropic:
            urlString = base.hasSuffix("/v1") ? "\(base)/messages" : "\(base)/v1/messages"
        default:
            urlString = "\(base)/chat/completions"
        }
        guard let url = URL(string: urlString) else { throw LLMError.badEndpoint(urlString) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var body: [String: Any]
        switch kind {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": config.model,
                "max_tokens": maxTokens,
                "system": system,
                "messages": [["role": "user", "content": user]],
            ]
        default:
            if kind == .azureOpenAI {
                request.setValue(key, forHTTPHeaderField: "api-key")
            } else if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            body = ["messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
            if kind == .azureOpenAI || kind == .openAI {
                // Newer (reasoning) models reject `max_tokens` and a custom temperature.
                body["max_completion_tokens"] = maxTokens * 4
            } else {
                body["max_tokens"] = maxTokens
                body["temperature"] = 0.2
            }
            if kind != .azureOpenAI { body["model"] = config.model }
            // JSON mode where the provider is known to support it.
            if [.azureOpenAI, .openAI, .gemini].contains(kind) {
                body["response_format"] = ["type": "json_object"]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Response

    /// Pulls the answer text out of a Chat Completions or Anthropic Messages response.
    static func parseText(kind: LLMProviderKind, data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LLMError.emptyResponse }
        let text: String?
        if kind == .anthropic {
            let blocks = json["content"] as? [[String: Any]] ?? []
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        } else {
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = json["error"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "unknown error"
    }

    func complete(system: String, user: String) async throws -> String {
        let request = try makeRequest(system: system, user: user)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.parseText(kind: kind, data: data)
    }
}
