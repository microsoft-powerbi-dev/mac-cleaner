import XCTest
@testable import MacCleaner

final class RemoteLLMTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    // MARK: Requests

    func testAzureRequest() throws {
        let client = RemoteLLMClient(
            kind: .azureOpenAI,
            config: LLMProviderConfig(endpoint: "https://contoso.openai.azure.com/", model: "", deployment: "gpt-4o-mini", apiVersion: "2024-10-21"),
            apiKey: "azure-key"
        )
        let request = try client.makeRequest(system: "sys", user: "hi")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://contoso.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2024-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "azure-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let json = try body(request)
        XCTAssertNil(json["model"])
        XCTAssertNotNil(json["max_completion_tokens"])
        XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertEqual((json["messages"] as? [[String: String]])?.map { $0["role"]! }, ["system", "user"])
    }

    func testOpenAIAndCompatibleRequests() throws {
        let openAI = RemoteLLMClient(kind: .openAI, config: LLMProviderKind.openAI.defaultConfig, apiKey: "sk-1")
        let r1 = try openAI.makeRequest(system: "s", user: "u")
        XCTAssertEqual(r1.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(r1.value(forHTTPHeaderField: "Authorization"), "Bearer sk-1")
        XCTAssertEqual(try body(r1)["model"] as? String, "gpt-4.1-mini")

        let ollama = RemoteLLMClient(kind: .ollama, config: LLMProviderKind.ollama.defaultConfig, apiKey: nil)
        let r2 = try ollama.makeRequest(system: "s", user: "u")
        XCTAssertEqual(r2.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(r2.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(try body(r2)["max_tokens"])

        let gemini = RemoteLLMClient(kind: .gemini, config: LLMProviderKind.gemini.defaultConfig, apiKey: "g")
        XCTAssertEqual(try gemini.makeRequest(system: "s", user: "u").url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    }

    func testAnthropicRequest() throws {
        let client = RemoteLLMClient(kind: .anthropic, config: LLMProviderKind.anthropic.defaultConfig, apiKey: "ant")
        let request = try client.makeRequest(system: "sys", user: "hi")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "ant")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let json = try body(request)
        XCTAssertEqual(json["system"] as? String, "sys")
        XCTAssertEqual(json["model"] as? String, "claude-sonnet-5-5")
        XCTAssertNotNil(json["max_tokens"])
    }

    func testConfigurationProblems() {
        XCTAssertNotNil(RemoteLLMClient(kind: .openAI, config: LLMProviderKind.openAI.defaultConfig, apiKey: nil).configurationProblem)
        XCTAssertNotNil(RemoteLLMClient(kind: .azureOpenAI, config: LLMProviderKind.azureOpenAI.defaultConfig, apiKey: "k").configurationProblem)
        var azure = LLMProviderKind.azureOpenAI.defaultConfig
        azure.endpoint = "https://x.openai.azure.com"
        XCTAssertNotNil(RemoteLLMClient(kind: .azureOpenAI, config: azure, apiKey: "k").configurationProblem)   // no deployment
        azure.deployment = "d"
        XCTAssertNil(RemoteLLMClient(kind: .azureOpenAI, config: azure, apiKey: "k").configurationProblem)
        XCTAssertNil(RemoteLLMClient(kind: .ollama, config: LLMProviderKind.ollama.defaultConfig, apiKey: nil).configurationProblem)
    }

    // MARK: Responses

    func testParsesChatCompletionsAndMessages() throws {
        let chat = #"{"choices":[{"message":{"role":"assistant","content":"hello"}}]}"#
        XCTAssertEqual(try RemoteLLMClient.parseText(kind: .azureOpenAI, data: Data(chat.utf8)), "hello")
        let messages = #"{"content":[{"type":"text","text":"hi "},{"type":"text","text":"there"}]}"#
        XCTAssertEqual(try RemoteLLMClient.parseText(kind: .anthropic, data: Data(messages.utf8)), "hi there")
        XCTAssertThrowsError(try RemoteLLMClient.parseText(kind: .openAI, data: Data(#"{"choices":[]}"#.utf8)))
        XCTAssertEqual(RemoteLLMClient.errorMessage(from: Data(#"{"error":{"message":"bad key"}}"#.utf8)), "bad key")
    }

    func testLenientJSONAndRatings() throws {
        struct Reply: Decodable { let headline: String }
        let fenced = "Sure!\n```json\n{\"headline\": \"ok\"}\n```"
        XCTAssertEqual(try RemoteAdvisor.decode(Reply.self, from: fenced).headline, "ok")
        XCTAssertThrowsError(try RemoteAdvisor.decode(Reply.self, from: "no json here"))
        XCTAssertEqual(RemoteAdvisor.rating("safe_to_delete"), .safeToDelete)
        XCTAssertEqual(RemoteAdvisor.rating("Review first"), .reviewFirst)
        XCTAssertEqual(RemoteAdvisor.rating("KEEP"), .keep)
        XCTAssertNil(RemoteAdvisor.rating("banana"))
        XCTAssertEqual(RemoteAdvisor.display(home + "/a/b/c/file.mov", shorten: true), "…/c/file.mov")
    }

    // MARK: Advisor with a fake model

    private struct FakeLLM: LLMCompleting {
        let reply: String
        var fail = false
        var displayName: String { "Fake · test" }
        func complete(system: String, user: String) async throws -> String {
            if fail { throw LLMError.http(status: 401, message: "nope") }
            return reply
        }
    }

    private let reckless = #"{"fileType":"Mail","whatItIs":"x","safety":"safeToDelete","reasoning":"y","preventGrowth":["a"],"cleanupSteps":["b"],"suggestMove":false}"#

    func testModelCannotBeMorePermissiveThanRules() async {
        let item = AdvisorItem(url: URL(fileURLWithPath: home + "/Library/Mail/V10"), isDirectory: true, size: 1, kind: .other)
        let advice = await DiskAdvisor.advise(item, client: FakeLLM(reply: reckless))
        XCTAssertEqual(advice.engine, .remote("Fake · test"))
        XCTAssertEqual(advice.safety, .keep)
    }

    func testModelAnswerUsedForUnknownItem() async {
        let item = AdvisorItem(url: URL(fileURLWithPath: home + "/Library/Developer/Xcode/DerivedData/App"), isDirectory: true, size: 1, kind: .developer)
        let advice = await DiskAdvisor.advise(item, client: FakeLLM(reply: reckless))
        XCTAssertEqual(advice.fileType, "Mail")
        XCTAssertEqual(advice.safety, .safeToDelete)
        XCTAssertNil(advice.notice)
    }

    func testFailureFallsBackToRulesWithNotice() async {
        var settings = AISettings()
        settings.provider = .openAI
        let item = AdvisorItem(url: URL(fileURLWithPath: home + "/Library/Caches/com.example"), isDirectory: true, size: 1, kind: .cache)
        let advice = await DiskAdvisor.advise(item, settings: settings, client: FakeLLM(reply: "", fail: true))
        XCTAssertEqual(advice.engine, .rules)
        XCTAssertTrue(advice.notice?.contains("401") == true)
    }

    func testSettingsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RemoteLLMTests-\(UUID().uuidString)"))
        var settings = AISettings()
        settings.provider = .azureOpenAI
        settings.configs[.azureOpenAI] = LLMProviderConfig(endpoint: "https://e", model: "", deployment: "d", apiVersion: "v")
        settings.save(defaults)
        XCTAssertEqual(AISettings.load(defaults), settings)
        XCTAssertEqual(AISettings.load(defaults).config(for: .openAI), LLMProviderKind.openAI.defaultConfig)
    }
}
