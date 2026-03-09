import Foundation

@Observable
@MainActor
final class LLMModelManager {
    var availableLocalModels: [String] = []
    var isDownloading = false
    var downloadProgress: Double = 0

    static let modelsDirectory: URL = {
        let dir = JSONStorageAdapter.appSupportDir.appendingPathComponent("LLMModels")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    struct RecommendedModel: Identifiable {
        let id: String
        let name: String
        let size: String
        let sizeGB: Double
        let languages: String
        let license: String
        let huggingFaceRepo: String
        let filename: String
    }

    static let recommendedModels: [RecommendedModel] = [
        RecommendedModel(
            id: "qwen3.5-4b",
            name: "Qwen3.5 4B (Recommended)",
            size: "~2.7 GB",
            sizeGB: 2.7,
            languages: "201 languages",
            license: "Apache 2.0",
            huggingFaceRepo: "unsloth/Qwen3.5-4B-GGUF",
            filename: "Qwen3.5-4B-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "gemma3-4b",
            name: "Gemma 3 4B IT",
            size: "~2.4 GB",
            sizeGB: 2.4,
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceRepo: "google/gemma-3-4b-it-qat-q4_0-gguf",
            filename: "gemma-3-4b-it-q4_0.gguf"
        ),
        RecommendedModel(
            id: "phi4-mini",
            name: "Phi-4 Mini",
            size: "~2.5 GB",
            sizeGB: 2.5,
            languages: "23 languages",
            license: "MIT",
            huggingFaceRepo: "bartowski/microsoft_Phi-4-mini-instruct-GGUF",
            filename: "Phi-4-mini-instruct-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "qwen3.5-2b",
            name: "Qwen3.5 2B (Lightweight)",
            size: "~1.5 GB",
            sizeGB: 1.5,
            languages: "201 languages",
            license: "Apache 2.0",
            huggingFaceRepo: "unsloth/Qwen3.5-2B-GGUF",
            filename: "Qwen3.5-2B-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "gemma3n-e2b",
            name: "Gemma 3n E2B (Ultra-light)",
            size: "~1.2 GB",
            sizeGB: 1.2,
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceRepo: "unsloth/gemma-3n-E2B-it-GGUF",
            filename: "gemma-3n-E2B-it-Q4_K_M.gguf"
        ),
    ]

    init() {
        refreshLocalModels()
    }

    func refreshLocalModels() {
        let dir = Self.modelsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            availableLocalModels = []
            return
        }
        availableLocalModels = contents
            .filter { $0.pathExtension == "gguf" }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private var downloadDelegate: DownloadProgressDelegate?
    private var downloadSession: URLSession?

    func downloadModel(_ model: RecommendedModel) async throws {
        isDownloading = true
        downloadProgress = 0

        let url = URL(string: "https://huggingface.co/\(model.huggingFaceRepo)/resolve/main/\(model.filename)")!
        let destination = Self.modelsDirectory.appendingPathComponent(model.filename)

        let resolvedPath = destination.standardizedFileURL.path
        let basePath = Self.modelsDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(basePath + "/") else {
            isDownloading = false
            throw LLMModelError.invalidPath
        }

        do {
            let delegate = DownloadProgressDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            downloadDelegate = delegate

            // Create a dedicated session so the delegate receives progress callbacks
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            downloadSession = session

            let (tempURL, _) = try await session.download(from: url)

            // Remove any existing file at the destination before moving
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            refreshLocalModels()
            isDownloading = false
            downloadDelegate = nil
            downloadSession?.invalidateAndCancel()
            downloadSession = nil
        } catch {
            isDownloading = false
            downloadProgress = 0
            downloadDelegate = nil
            downloadSession?.invalidateAndCancel()
            downloadSession = nil
            throw error
        }
    }

    func deleteModel(_ filename: String) throws {
        let modelFile = Self.modelsDirectory.appendingPathComponent(filename)
        let resolvedPath = modelFile.standardizedFileURL.path
        let basePath = Self.modelsDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(basePath + "/") else {
            throw LLMModelError.invalidPath
        }
        try FileManager.default.removeItem(at: modelFile)
        refreshLocalModels()
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download(from:) call; no action needed here.
    }
}

enum LLMModelError: LocalizedError {
    case invalidPath
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath: "Invalid model file path."
        case .downloadFailed: "Failed to download model."
        }
    }
}
