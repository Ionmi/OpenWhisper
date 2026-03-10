import Foundation

@Observable
@MainActor
final class ModelManager {
    var availableLocalModels: [String] = []
    var downloadableModels: [Constants.SupportedModels.WhisperModel] = Constants.SupportedModels.all
    var isDownloading = false
    var downloadProgress: Double = 0

    init() {
        refreshLocalModels()
    }

    func refreshLocalModels() {
        // WhisperKit stores models at:
        //   <modelsDirectory>/models/argmaxinc/whisperkit-coreml/openai_whisper-<modelID>/
        let whisperKitDir = Constants.modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: whisperKitDir,
            includingPropertiesForKeys: nil
        ) else {
            availableLocalModels = []
            return
        }
        availableLocalModels = contents
            .filter { $0.hasDirectoryPath }
            .compactMap { url -> String? in
                let name = url.lastPathComponent
                guard name.hasPrefix("openai_whisper-") else { return nil }
                return String(name.dropFirst("openai_whisper-".count))
            }
            .sorted()
    }

    var storageUsed: String {
        let modelsDir = Constants.modelsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "0 MB"
        }

        var totalSize: Int64 = 0
        for url in contents {
            if let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
                totalSize += Int64(size)
            }
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    func deleteModel(_ name: String) throws {
        // WhisperKit stores models at:
        //   <modelsDirectory>/models/argmaxinc/whisperkit-coreml/openai_whisper-<modelID>/
        let whisperKitDir = Constants.modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
        let modelDir = whisperKitDir.appendingPathComponent("openai_whisper-\(name)")
        // Validate the resolved path is within the models directory to prevent path traversal
        let resolvedPath = modelDir.standardizedFileURL.path
        let basePath = Constants.modelsDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(basePath + "/") else {
            throw ModelManagerError.invalidModelPath
        }
        try FileManager.default.removeItem(at: modelDir)
        refreshLocalModels()
    }
}

enum ModelManagerError: LocalizedError {
    case invalidModelPath

    var errorDescription: String? {
        switch self {
        case .invalidModelPath:
            return "Invalid model path."
        }
    }
}
