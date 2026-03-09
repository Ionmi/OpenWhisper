import Foundation
import Security

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
            remoteAPIKey = KeychainHelper.load() ?? ""
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
            remoteAPIKey: "",
            remoteModelName: remoteModelName
        )
        JSONStorageAdapter.save(storage, to: "llm-settings.json")
        KeychainHelper.save(remoteAPIKey)
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    private static let service = "me.OpenWhisper.llm-api-key"
    private static let account = "remoteAPIKey"

    static func save(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let existing = SecItemCopyMatching(query as CFDictionary, nil)

        if existing == errSecSuccess {
            let updates: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
