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

    func loadModel(name: String, progressHandler: ((Double, Double?) -> Void)? = nil) async throws {
        lock.withLock {
            _isModelLoaded = false
        }

        let localModelFolder = Constants.modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent("openai_whisper-\(name)")

        let modelFolder: URL
        if FileManager.default.fileExists(atPath: localModelFolder.path) {
            // Model already downloaded — skip network verification.
            modelFolder = localModelFolder
        } else {
            // Download with progress reporting.
            modelFolder = try await WhisperKit.download(
                variant: name,
                downloadBase: Constants.modelsDirectory,
                progressCallback: { progress in
                    let speed = progress.userInfo[.throughputKey] as? Double
                    progressHandler?(progress.fractionCompleted, speed)
                }
            )
        }

        // Load the model from disk.
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

    func transcribe(audioSamples: [Float], language: String?, clipTimestamps: [Float] = [], prefixTokens: [Int]? = nil) async throws -> TranscriptionOutput {
        let kit = lock.withLock { whisperKit }

        guard let kit else {
            throw TranscriptionError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let language {
            options.language = language
        }
        options.wordTimestamps = true
        options.chunkingStrategy = ChunkingStrategy.none
        if !clipTimestamps.isEmpty {
            options.clipTimestamps = clipTimestamps
        }
        if let prefixTokens, !prefixTokens.isEmpty {
            options.prefixTokens = prefixTokens
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

        let words: [TranscriptionWord] = results.flatMap { result in
            result.allWords.map { wt in
                TranscriptionWord(
                    word: wt.word,
                    start: wt.start,
                    end: wt.end,
                    probability: wt.probability,
                    tokens: wt.tokens
                )
            }
        }

        if text.isEmpty {
            throw TranscriptionError.transcriptionFailed("No speech detected.")
        }
        return TranscriptionOutput(text: text, detectedLanguage: detectedLanguage, words: words)
    }
}
