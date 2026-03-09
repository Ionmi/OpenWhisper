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
        lock.withLock {
            _isModelLoaded = false
            llamaService = nil
        }

        let service = LlamaService(
            modelUrl: path,
            config: .init(batchSize: 512, maxTokenCount: 512, useGPU: true)
        )

        lock.withLock {
            llamaService = service
            _isModelLoaded = true
        }
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        let service = lock.withLock { llamaService }

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
            return Self.stripThinkingBlocks(response)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw LLMError.generationFailed(error.localizedDescription)
        }
    }

    func warmUp(systemPrompt: String) async {
        let service = lock.withLock { llamaService }
        guard let service else { return }
        // Send a minimal prompt to populate KV cache with system prompt tokens.
        // Use "." as user input to minimize generation output.
        _ = try? await service.respond(
            to: [
                LlamaChatMessage(role: .system, content: systemPrompt),
                LlamaChatMessage(role: .user, content: "."),
            ],
            samplingConfig: .init(temperature: 0.0, seed: 0)
        )
    }

    /// Strip `<think>...</think>` blocks that some models (Qwen3.5, DeepSeek) produce.
    private static func stripThinkingBlocks(_ text: String) -> String {
        // Remove <think>...</think> blocks (greedy, handles multiline)
        guard let regex = try? NSRegularExpression(
            pattern: #"<think>[\s\S]*?</think>"#,
            options: .caseInsensitive
        ) else { return text }
        var result = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
        // Also handle unclosed <think> blocks (model hit token limit mid-thinking)
        if let thinkRange = result.range(of: "<think>", options: .caseInsensitive) {
            result = String(result[..<thinkRange.lowerBound])
        }
        return result
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
