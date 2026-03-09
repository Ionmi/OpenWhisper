import Foundation

@Observable
final class LLMSettings {
    var isEnabled: Bool {
        didSet { save() }
    }
    var source: LLMSource {
        didSet { save() }
    }
    var selectedLocalModel: String {
        didSet { save() }
    }
    var remoteBaseURL: String {
        didSet { save() }
    }
    var remoteAPIKey: String {
        didSet { save() }
    }
    var remoteModelName: String {
        didSet { save() }
    }

    enum LLMSource: String, Codable, CaseIterable, Identifiable {
        case local
        case remote

        var id: String { rawValue }
        var label: String {
            switch self {
            case .local: "Local (on-device)"
            case .remote: "Remote (API)"
            }
        }
    }

    private struct Storage: Codable {
        var isEnabled: Bool
        var source: LLMSource
        var selectedLocalModel: String
        var remoteBaseURL: String
        var remoteAPIKey: String
        var remoteModelName: String
    }

    init() {
        if let stored = JSONStorageAdapter.load(Storage.self, from: "llm-settings.json") {
            isEnabled = stored.isEnabled
            source = stored.source
            selectedLocalModel = stored.selectedLocalModel
            remoteBaseURL = stored.remoteBaseURL
            remoteAPIKey = stored.remoteAPIKey
            remoteModelName = stored.remoteModelName
        } else {
            isEnabled = false
            source = .local
            selectedLocalModel = ""
            remoteBaseURL = ""
            remoteAPIKey = ""
            remoteModelName = ""
        }
    }

    private func save() {
        let storage = Storage(
            isEnabled: isEnabled,
            source: source,
            selectedLocalModel: selectedLocalModel,
            remoteBaseURL: remoteBaseURL,
            remoteAPIKey: remoteAPIKey,
            remoteModelName: remoteModelName
        )
        JSONStorageAdapter.save(storage, to: "llm-settings.json")
    }
}
