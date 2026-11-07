import Foundation

/// Which engine answers "Explain with AI" and "Analyze Results".
enum LLMProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case onDevice, azureOpenAI, openAI, anthropic, gemini, ollama, openAICompatible

    var id: Self { self }

    var title: String {
        switch self {
        case .onDevice: return "Apple Intelligence (on-device)"
        case .azureOpenAI: return "Azure OpenAI"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .ollama: return "Ollama (local)"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }

    /// True when requests leave this Mac (Ollama and custom endpoints may be local; we still warn).
    var isCloud: Bool {
        switch self {
        case .onDevice, .ollama: return false
        default: return true
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .onDevice, .ollama: return false
        case .openAICompatible: return false   // optional
        default: return true
        }
    }

    var usesDeployment: Bool { self == .azureOpenAI }

    var usesEndpoint: Bool {
        switch self {
        case .azureOpenAI, .ollama, .openAICompatible: return true
        default: return false
        }
    }

    var defaultConfig: LLMProviderConfig {
        switch self {
        case .onDevice: return LLMProviderConfig()
        case .azureOpenAI: return LLMProviderConfig(endpoint: "https://YOUR-RESOURCE.openai.azure.com", model: "", deployment: "", apiVersion: "2024-10-21")
        case .openAI: return LLMProviderConfig(endpoint: "https://api.openai.com/v1", model: "gpt-4.1-mini")
        case .anthropic: return LLMProviderConfig(endpoint: "https://api.anthropic.com", model: "claude-sonnet-5-5")
        case .gemini: return LLMProviderConfig(endpoint: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-2.5-flash")
        case .ollama: return LLMProviderConfig(endpoint: "http://localhost:11434/v1", model: "llama3.2")
        case .openAICompatible: return LLMProviderConfig(endpoint: "http://localhost:1234/v1", model: "")
        }
    }

    var setupHint: String {
        switch self {
        case .onDevice: return "Runs on this Mac. Needs macOS 26+ with Apple Intelligence turned on."
        case .azureOpenAI: return "Endpoint and key are in the Azure portal under your Azure OpenAI resource › Keys and Endpoint. The deployment is the name you gave the model deployment in Azure AI Foundry."
        case .openAI: return "Create a key at platform.openai.com › API keys."
        case .anthropic: return "Create a key at console.anthropic.com › API Keys."
        case .gemini: return "Create a key at aistudio.google.com › Get API key. Uses Gemini's OpenAI-compatible endpoint."
        case .ollama: return "Install Ollama and run `ollama pull llama3.2`. The endpoint can be another Mac or a NAS on your network."
        case .openAICompatible: return "Any server with an OpenAI-style /chat/completions API: LM Studio, OpenRouter, Groq, Mistral, vLLM, LiteLLM…"
        }
    }
}

struct LLMProviderConfig: Codable, Equatable, Sendable {
    var endpoint = ""
    var model = ""
    /// Azure only.
    var deployment = ""
    /// Azure only.
    var apiVersion = ""
}

/// Persisted AI settings. API keys are kept in the Keychain, not here.
struct AISettings: Codable, Equatable, Sendable {
    var provider: LLMProviderKind = .onDevice
    var configs: [LLMProviderKind: LLMProviderConfig] = [:]
    /// Send only the last two path components instead of the full `~/…` path.
    var shortenPaths = false

    static let defaultsKey = "aiSettings"

    func config(for kind: LLMProviderKind) -> LLMProviderConfig {
        configs[kind] ?? kind.defaultConfig
    }

    static func load(_ defaults: UserDefaults = .standard) -> AISettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AISettings.self, from: data) else { return AISettings() }
        return settings
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    static func apiKey(for kind: LLMProviderKind) -> String? {
        KeychainStore.read(kind.rawValue).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func setAPIKey(_ key: String, for kind: LLMProviderKind) {
        KeychainStore.write(key, for: kind.rawValue)
    }

    /// A ready-to-use client for the selected remote provider, or nil for on-device / incomplete setup.
    func remoteClient() -> RemoteLLMClient? {
        guard provider != .onDevice else { return nil }
        let client = RemoteLLMClient(kind: provider, config: config(for: provider), apiKey: Self.apiKey(for: provider))
        return client.configurationProblem == nil ? client : nil
    }
}
