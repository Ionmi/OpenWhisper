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

struct TranscriptionWord: Sendable {
    let word: String
    let start: Float
    let end: Float
    let probability: Float
    let tokens: [Int]
}

struct TranscriptionOutput: Sendable {
    let text: String
    let detectedLanguage: String
    let words: [TranscriptionWord]
}

protocol TranscriptionPort: Sendable {
    func loadModel(name: String, progressHandler: ((Double, Double?) -> Void)?) async throws
    func transcribe(audioSamples: [Float], language: String?, clipTimestamps: [Float], prefixTokens: [Int]?) async throws -> TranscriptionOutput
    var isModelLoaded: Bool { get }
}

extension TranscriptionPort {
    func loadModel(name: String) async throws {
        try await loadModel(name: name, progressHandler: nil)
    }

    func transcribe(audioSamples: [Float], language: String?) async throws -> TranscriptionOutput {
        try await transcribe(audioSamples: audioSamples, language: language, clipTimestamps: [], prefixTokens: nil)
    }
}
