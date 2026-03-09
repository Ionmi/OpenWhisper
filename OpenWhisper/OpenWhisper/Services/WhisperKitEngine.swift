import Foundation
import WhisperKit

final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var _isModelLoaded = false

    var isModelLoaded: Bool { _isModelLoaded }

    func loadModel(name: String) async throws {
        _isModelLoaded = false
        // Use Application Support instead of ~/Documents (which is TCC-protected on modern macOS)
        let kit = try await WhisperKit(
            model: name,
            downloadBase: Constants.modelsDirectory,
            verbose: false,
            prewarm: true
        )
        whisperKit = kit
        _isModelLoaded = true
    }

    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let language {
            options.language = language
        }

        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw TranscriptionError.transcriptionFailed("No speech detected.")
        }
        return text
    }
}
