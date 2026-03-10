import Foundation

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No transcription model is loaded."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .modelNotFound(let name):
            return "Model '\(name)' not found."
        }
    }
}

struct TranscriptionOutput {
    let text: String
    let detectedLanguage: String
}

protocol TranscriptionPort: Sendable {
    func loadModel(name: String, progressHandler: ((Double, Double?) -> Void)?) async throws
    func transcribe(audioSamples: [Float], language: String?) async throws -> TranscriptionOutput
    var isModelLoaded: Bool { get }
}

extension TranscriptionPort {
    func loadModel(name: String) async throws {
        try await loadModel(name: name, progressHandler: nil)
    }
}
