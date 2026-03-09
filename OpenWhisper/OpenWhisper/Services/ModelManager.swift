import Foundation

@Observable
@MainActor
final class ModelManager {
    var availableLocalModels: [String] = []
    var downloadableModels: [String] = Constants.SupportedModels.all
    var isDownloading = false
    var downloadProgress: Double = 0

    init() {
        refreshLocalModels()
    }

    func refreshLocalModels() {
        let modelsDir = Constants.modelsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: nil
        ) else {
            availableLocalModels = []
            return
        }
        availableLocalModels = contents
            .filter { $0.hasDirectoryPath }
            .map { $0.lastPathComponent }
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
        let modelDir = Constants.modelsDirectory.appendingPathComponent(name)
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
