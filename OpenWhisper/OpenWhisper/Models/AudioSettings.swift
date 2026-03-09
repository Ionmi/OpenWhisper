import Foundation

@Observable
final class AudioSettings {
    var aecEnabled: Bool {
        didSet { save() }
    }
    var noiseSuppressionEnabled: Bool {
        didSet { save() }
    }
    var vadEnabled: Bool {
        didSet { save() }
    }

    private struct Storage: Codable {
        var aecEnabled: Bool
        var noiseSuppressionEnabled: Bool
        var vadEnabled: Bool
    }

    init() {
        if let stored = JSONStorageAdapter.load(Storage.self, from: "audio-settings.json") {
            aecEnabled = stored.aecEnabled
            noiseSuppressionEnabled = stored.noiseSuppressionEnabled
            vadEnabled = stored.vadEnabled
        } else {
            aecEnabled = false
            noiseSuppressionEnabled = false
            vadEnabled = true
        }
    }

    private func save() {
        JSONStorageAdapter.save(
            Storage(aecEnabled: aecEnabled, noiseSuppressionEnabled: noiseSuppressionEnabled, vadEnabled: vadEnabled),
            to: "audio-settings.json"
        )
    }
}
