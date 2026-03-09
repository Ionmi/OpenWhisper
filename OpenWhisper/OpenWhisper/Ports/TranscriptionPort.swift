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

protocol TranscriptionPort: Sendable {
    func loadModel(name: String) async throws
    func transcribe(audioSamples: [Float], language: String?) async throws -> String
    var isModelLoaded: Bool { get }
}
