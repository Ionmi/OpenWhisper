import Foundation
import SwiftLlama

final class LocalLLMAdapter: LLMPort, @unchecked Sendable {
    private var llamaService: LlamaService?
    private let lock = NSLock()
    private var _isModelLoaded = false

    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isModelLoaded
    }

    func loadModel(name: String, path: URL) async throws {
        lock.lock()
        _isModelLoaded = false
        llamaService = nil
        lock.unlock()

        let service = LlamaService(
            modelUrl: path,
            config: .init(batchSize: 512, maxTokenCount: 512, useGPU: true)
        )

        lock.lock()
        llamaService = service
        _isModelLoaded = true
        lock.unlock()
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        lock.lock()
        let service = llamaService
        lock.unlock()

        guard let service else {
            throw LLMError.modelNotLoaded
        }

        let messages: [LlamaChatMessage] = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: userPrompt),
        ]

        do {
            let response = try await service.respond(
                to: messages,
                samplingConfig: .init(temperature: 0.1, seed: 42)
            )
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.generationFailed(error.localizedDescription)
        }
    }

    func warmUp(systemPrompt: String) async {
        lock.lock()
        let service = llamaService
        lock.unlock()
        guard let service else { return }
        _ = try? await service.respond(
            to: [
                LlamaChatMessage(role: .system, content: systemPrompt),
                LlamaChatMessage(role: .user, content: "test"),
            ],
            samplingConfig: .init(temperature: 0.1, seed: 42)
        )
    }

    func unloadModel() {
        lock.lock()
        llamaService = nil
        _isModelLoaded = false
        lock.unlock()
    }
}

enum LLMError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "No LLM model is loaded."
        case .generationFailed(let reason): "LLM generation failed: \(reason)"
        }
    }
}
