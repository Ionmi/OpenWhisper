import Foundation

final class RemoteLLMAdapter: LLMPort, @unchecked Sendable {
    private var baseURL: String
    private var apiKey: String
    private var modelName: String
    private let lock = NSLock()

    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !baseURL.isEmpty && !modelName.isEmpty
    }

    init(baseURL: String = "", apiKey: String = "", modelName: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func loadModel(name: String, path: URL) async throws {
        // For remote, "loading" just validates configuration
    }

    func configure(baseURL: String, apiKey: String, modelName: String) {
        lock.lock()
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        lock.unlock()
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        let (currentBaseURL, currentApiKey, currentModelName) = lock.withLock {
            (baseURL, apiKey, modelName)
        }

        guard !currentBaseURL.isEmpty else {
            throw LLMError.modelNotLoaded
        }

        guard let url = URL(string: "\(currentBaseURL)/chat/completions") else {
            throw LLMError.generationFailed("Invalid base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !currentApiKey.isEmpty {
            request.setValue("Bearer \(currentApiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": currentModelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.1,
            "max_tokens": 4096,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("HTTP error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.generationFailed("Invalid response format")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func warmUp(systemPrompt: String) async {
        // No-op for remote APIs
    }

    func unloadModel() {
        lock.lock()
        baseURL = ""
        apiKey = ""
        modelName = ""
        lock.unlock()
    }
}
