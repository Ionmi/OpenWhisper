import Foundation
import WhisperKit

final class WhisperKitEngine: TranscriptionPort, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private let lock = NSLock()
    private var _isModelLoaded = false

    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isModelLoaded
    }

    func loadModel(name: String, progressHandler: ((Double) -> Void)? = nil) async throws {
        lock.withLock {
            _isModelLoaded = false
        }

        // Step 1: Download (or verify cached) with progress reporting.
        // WhisperKit.download() checks local cache and only fetches missing files.
        let modelFolder = try await WhisperKit.download(
            variant: name,
            downloadBase: Constants.modelsDirectory,
            progressCallback: { progress in
                progressHandler?(progress.fractionCompleted)
            }
        )

        // Step 2: Load the already-downloaded model.
        let kit = try await WhisperKit(
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true
        )

        lock.withLock {
            whisperKit = kit
            _isModelLoaded = true
        }
    }

    func transcribe(audioSamples: [Float], language: String?) async throws -> TranscriptionOutput {
        let kit = lock.withLock { whisperKit }

        guard let kit else {
            throw TranscriptionError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let language {
            options.language = language
        }

        let results = try await kit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let detectedLanguage = results.first?.language ?? language ?? "en"

        if text.isEmpty {
            throw TranscriptionError.transcriptionFailed("No speech detected.")
        }
        return TranscriptionOutput(text: text, detectedLanguage: detectedLanguage)
    }
}
