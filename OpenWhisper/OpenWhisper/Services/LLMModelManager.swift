import Foundation

@Observable
@MainActor
final class LLMModelManager {
    var isDownloading = false
    var downloadProgress: Double = 0
    var downloadingModelID: String = ""
    var statusMessage: String = ""

    /// Byte-based download tracking
    private var downloadStartTime: Date?
    private var lastCallbackTime: Date?
    private var downloadedBytes: Double = 0
    private var totalBytes: Double = 0

    struct RecommendedModel: Identifiable {
        let id: String
        let name: String
        let size: String
        let sizeGB: Double
        let languages: String
        let license: String
        let huggingFaceID: String
    }

    static let recommendedModels: [RecommendedModel] = [
        RecommendedModel(
            id: "qwen3-4b",
            name: "Qwen3 4B",
            size: "~2.5 GB",
            sizeGB: 2.5,
            languages: "119 languages",
            license: "Apache 2.0",
            huggingFaceID: "mlx-community/Qwen3-4B-4bit"
        ),
        RecommendedModel(
            id: "gemma3-4b",
            name: "Gemma 3 4B IT",
            size: "~2.4 GB",
            sizeGB: 2.4,
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceID: "mlx-community/gemma-3-4b-it-4bit"
        ),
        RecommendedModel(
            id: "phi4-mini",
            name: "Phi-4 Mini",
            size: "~2.5 GB",
            sizeGB: 2.5,
            languages: "23 languages",
            license: "MIT",
            huggingFaceID: "mlx-community/Phi-4-mini-instruct-4bit"
        ),
        RecommendedModel(
            id: "qwen3-1.7b",
            name: "Qwen3 1.7B (Lightweight)",
            size: "~1.2 GB",
            sizeGB: 1.2,
            languages: "119 languages",
            license: "Apache 2.0",
            huggingFaceID: "mlx-community/Qwen3-1.7B-4bit"
        ),
        RecommendedModel(
            id: "gemma3n-e2b",
            name: "Gemma 3n E2B (Ultra-light)",
            size: "~1.2 GB",
            sizeGB: 1.2,
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceID: "mlx-community/gemma-3n-E2B-it-4bit"
        ),
    ]

    /// MLX model cache directory: ~/Library/Caches/models/
    private static let cacheBase: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("models")

    /// Returns the local cache directory URL for a given HuggingFace model ID.
    func cachedModelURL(_ huggingFaceID: String) -> URL? {
        guard let base = Self.cacheBase else { return nil }
        let modelDir = base.appendingPathComponent(huggingFaceID)
        // Verify it has at least one .safetensors file
        guard FileManager.default.fileExists(atPath: modelDir.path),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path),
              contents.contains(where: { $0.hasSuffix(".safetensors") })
        else { return nil }
        return modelDir
    }

    /// Check if a model is already cached on disk.
    func isModelCached(_ huggingFaceID: String) -> Bool {
        cachedModelURL(huggingFaceID) != nil
    }

    /// Delete cached model files from disk.
    func deleteModel(_ huggingFaceID: String) throws {
        guard let base = Self.cacheBase else { return }
        let modelDir = base.appendingPathComponent(huggingFaceID)
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return }
        try FileManager.default.removeItem(at: modelDir)
    }

    /// Downloads an MLX model with accurate byte-based progress (also loads into
    /// memory as required by the MLX API, but callers decide whether to activate it).
    func download(_ model: RecommendedModel, using adapter: MLXLLMAdapter) async throws {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        downloadingModelID = model.huggingFaceID

        // Reset byte tracking
        downloadedBytes = 0
        totalBytes = model.sizeGB * 1_000_000_000
        downloadStartTime = nil
        lastCallbackTime = nil
        statusMessage = "Preparing download..."

        do {
            try await adapter.loadModel(huggingFaceID: model.huggingFaceID) { [weak self] _, speed in
                Task { @MainActor in
                    guard let self else { return }

                    let now = Date()

                    // Accumulate downloaded bytes from speed × elapsed time
                    if let lastTime = self.lastCallbackTime, let speed, speed > 0 {
                        let delta = now.timeIntervalSince(lastTime)
                        self.downloadedBytes += speed * delta
                        self.downloadedBytes = min(self.downloadedBytes, self.totalBytes)
                    }

                    if self.downloadStartTime == nil, let speed, speed > 0 {
                        self.downloadStartTime = now
                    }
                    self.lastCallbackTime = now

                    let downloadedGB = self.downloadedBytes / 1_000_000_000
                    let realProgress = self.downloadedBytes / self.totalBytes

                    self.downloadProgress = realProgress

                    if realProgress >= 0.99 {
                        self.statusMessage = "Finishing..."
                    } else if let speed, speed > 0 {
                        let percent = Int(realProgress * 100)
                        let mbps = speed / 1_000_000
                        self.statusMessage = String(
                            format: "%d%%  (%.0f MB/s)",
                            percent, mbps
                        )
                    }
                }
            }
            statusMessage = ""
            isDownloading = false
            downloadingModelID = ""
        } catch {
            statusMessage = ""
            isDownloading = false
            downloadProgress = 0
            downloadingModelID = ""
            throw error
        }
    }

    /// Loads an already-cached model into GPU memory.
    func loadCached(_ model: RecommendedModel, using adapter: MLXLLMAdapter) async throws {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 1.0
        downloadingModelID = model.huggingFaceID
        statusMessage = "Loading into GPU..."

        do {
            try await adapter.loadModel(huggingFaceID: model.huggingFaceID, progressHandler: nil)
            statusMessage = ""
            isDownloading = false
            downloadingModelID = ""
        } catch {
            statusMessage = ""
            isDownloading = false
            downloadProgress = 0
            downloadingModelID = ""
            throw error
        }
    }
}
