import Foundation
import AppKit

@Observable
@MainActor
final class AutoDictionaryService {
    var pendingSuggestion: DictionarySuggestion?

    struct DictionarySuggestion: Identifiable {
        let id = UUID()
        let originalWord: String
        let correctedWord: String
    }

    private var lastTranscribedText: String = ""
    private var dictionaryAdapter: DictionaryPort?
    private var monitorTimer: Timer?

    func configure(dictionaryAdapter: DictionaryPort) {
        self.dictionaryAdapter = dictionaryAdapter
    }

    func startMonitoring(transcribedText: String) {
        lastTranscribedText = transcribedText
        stopMonitoring()

        var checksRemaining = 10
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                checksRemaining -= 1
                if checksRemaining <= 0 {
                    self.stopMonitoring()
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func acceptSuggestion() {
        guard let suggestion = pendingSuggestion, let adapter = dictionaryAdapter else { return }
        adapter.addEntry(DictionaryEntry(from: suggestion.originalWord, to: suggestion.correctedWord))
        pendingSuggestion = nil
    }

    func dismissSuggestion() {
        pendingSuggestion = nil
    }
}
