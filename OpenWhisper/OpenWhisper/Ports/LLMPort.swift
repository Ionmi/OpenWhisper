import Foundation

protocol LLMPort: Sendable {
    func loadModel(name: String, path: URL) async throws
    func loadModel(huggingFaceID: String, progressHandler: (@Sendable (Double, Double?) -> Void)?) async throws
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
    func warmUp(systemPrompt: String) async
    var isModelLoaded: Bool { get }
    func unloadModel()
}

extension LLMPort {
    func loadModel(huggingFaceID: String, progressHandler: (@Sendable (Double, Double?) -> Void)? = nil) async throws {
        // Default no-op for adapters that don't support HuggingFace loading
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
