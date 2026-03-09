import Foundation

final class RemoteLLMAdapter: LLMPort, @unchecked Sendable {
    private var baseURL: String
    private var apiKey: String
    private var modelName: String

    var isModelLoaded: Bool { !baseURL.isEmpty && !modelName.isEmpty }

    init(baseURL: String = "", apiKey: String = "", modelName: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func loadModel(name: String, path: URL) async throws {
        // For remote, "loading" just validates configuration
    }

    func configure(baseURL: String, apiKey: String, modelName: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        guard !baseURL.isEmpty else {
            throw LLMError.modelNotLoaded
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.1,
            "max_tokens": 2048,
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

    func unloadModel() {
        // No-op for remote
    }
}
