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
            languages: "201 languages",
            license: "Apache 2.0",
            huggingFaceRepo: "unsloth/Qwen3.5-4B-GGUF",
            filename: "Qwen3.5-4B-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "gemma3-4b",
            name: "Gemma 3 4B IT",
            size: "~2.4 GB",
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceRepo: "google/gemma-3-4b-it-qat-q4_0-gguf",
            filename: "gemma-3-4b-it-q4_0.gguf"
        ),
        RecommendedModel(
            id: "phi4-mini",
            name: "Phi-4 Mini",
            size: "~2.5 GB",
            languages: "23 languages",
            license: "MIT",
            huggingFaceRepo: "bartowski/microsoft_Phi-4-mini-instruct-GGUF",
            filename: "Phi-4-mini-instruct-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "qwen3.5-2b",
            name: "Qwen3.5 2B (Lightweight)",
            size: "~1.5 GB",
            languages: "201 languages",
            license: "Apache 2.0",
            huggingFaceRepo: "unsloth/Qwen3.5-2B-GGUF",
            filename: "Qwen3.5-2B-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "gemma3n-e2b",
            name: "Gemma 3n E2B (Ultra-light)",
            size: "~1.2 GB",
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

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = response.expectedContentLength

        var data = Data()
        if totalBytes > 0 {
            data.reserveCapacity(Int(totalBytes))
        }

        for try await byte in asyncBytes {
            data.append(byte)
            if totalBytes > 0 {
                downloadProgress = Double(data.count) / Double(totalBytes)
            }
        }

        try data.write(to: destination, options: .atomic)
        refreshLocalModels()
        isDownloading = false
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
