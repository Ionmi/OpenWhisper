import Foundation
import MLX
import MLXLLM
import MLXLMCommon

final class MLXLLMAdapter: LLMPort, @unchecked Sendable {
    private var modelContainer: ModelContainer?
    private let lock = NSLock()
    private var _isModelLoaded = false

    var isModelLoaded: Bool {
        lock.withLock { _isModelLoaded }
    }

    func loadModel(name: String, path: URL) async throws {
        lock.withLock {
            _isModelLoaded = false
            modelContainer = nil
        }

        let config = ModelConfiguration(directory: path)
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        )

        lock.withLock {
            modelContainer = container
            _isModelLoaded = true
        }
    }

    func loadModel(huggingFaceID: String, progressHandler: (@Sendable (Double, Double?) -> Void)?) async throws {
        lock.withLock {
            _isModelLoaded = false
            modelContainer = nil
        }

        let config = ModelConfiguration(id: huggingFaceID)
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { progress in
            let speed = progress.userInfo[.throughputKey] as? Double
            progressHandler?(progress.fractionCompleted, speed)
        }

        lock.withLock {
            modelContainer = container
            _isModelLoaded = true
        }
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        let container = lock.withLock { modelContainer }
        guard let container else {
            throw LLMError.modelNotLoaded
        }

        let messages: [Chat.Message] = [
            .system(systemPrompt),
            .user(userPrompt),
        ]
        let userInput = UserInput(
            chat: messages,
            additionalContext: ["enable_thinking": false]
        )

        let input = try await container.prepare(input: userInput)
        let params = GenerateParameters(maxTokens: 4096, temperature: 0.1)

        var output = ""
        let stream = try await container.generate(input: input, parameters: params)
        for await generation in stream {
            if let chunk = generation.chunk {
                output += chunk
            }
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func warmUp(systemPrompt: String) async {
        let container = lock.withLock { modelContainer }
        guard let container else { return }

        let messages: [Chat.Message] = [
            .system(systemPrompt),
            .user("."),
        ]
        let userInput = UserInput(
            chat: messages,
            additionalContext: ["enable_thinking": false]
        )

        guard let input = try? await container.prepare(input: userInput) else { return }
        let params = GenerateParameters(maxTokens: 1, temperature: 0.0)

        let stream = try? await container.generate(input: input, parameters: params)
        if let stream {
            for await _ in stream {}
        }
    }

    func unloadModel() {
        lock.withLock {
            modelContainer = nil
            _isModelLoaded = false
        }
    }
}
