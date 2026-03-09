import Foundation

final class LocalLLMAdapter: LLMPort, @unchecked Sendable {
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
        lock.unlock()

        // TODO: Initialize llama.cpp context with the GGUF model at path
        // let params = llama_model_default_params()
        // params.n_gpu_layers = 99 // Use Metal for all layers
        // let model = llama_load_model_from_file(path.path, params)

        lock.lock()
        _isModelLoaded = true
        lock.unlock()
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        guard isModelLoaded else {
            throw LLMError.modelNotLoaded
        }

        // TODO: Run llama.cpp inference
        return userPrompt // Placeholder — pass-through until llama.cpp is integrated
    }

    func unloadModel() {
        lock.lock()
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
