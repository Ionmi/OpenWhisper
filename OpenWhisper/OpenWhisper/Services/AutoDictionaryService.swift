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
    private var initialClipboardContent: String = ""
    private var ignoredClipboardContents: Set<String> = []
    private var lastChangeCount: Int = 0

    func configure(dictionaryAdapter: DictionaryPort) {
        self.dictionaryAdapter = dictionaryAdapter
    }

    func startMonitoring(transcribedText: String, ignoredClipboardContents: Set<String> = []) {
        lastTranscribedText = transcribedText
        stopMonitoring()
        self.ignoredClipboardContents = Set(
            ignoredClipboardContents.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let pasteboard = NSPasteboard.general
        initialClipboardContent = pasteboard.string(forType: .string) ?? ""
        lastChangeCount = pasteboard.changeCount

        var checksRemaining = 10
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                checksRemaining -= 1

                self.checkClipboardForCorrection()

                if checksRemaining <= 0 {
                    self.stopMonitoring()
                }
            }
        }
    }

    private func checkClipboardForCorrection() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let newContent = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !newContent.isEmpty,
              newContent.count < 50,
              newContent != initialClipboardContent,
              !ignoredClipboardContents.contains(newContent) else {
            return
        }

        let transcriptionLower = lastTranscribedText.lowercased()
        let newContentLower = newContent.lowercased()

        // If the new clipboard content is already in the transcription, it's not a correction
        if transcriptionLower.contains(newContentLower) {
            return
        }

        let originalWord = findClosestWord(in: lastTranscribedText, to: newContent)
        let suggestion = DictionarySuggestion(
            originalWord: originalWord,
            correctedWord: newContent
        )
        pendingSuggestion = suggestion
        stopMonitoring()
    }

    /// Find the word in the transcription most likely to have been corrected to `replacement`.
    /// Uses a simple heuristic: shared prefix of at least 2 characters, then shortest edit distance approximation by length similarity.
    private func findClosestWord(in transcription: String, to replacement: String) -> String {
        let words = transcription.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        let replacementLower = replacement.lowercased()
        let prefix = replacementLower.prefix(2)

        // First pass: words sharing the same 2-char prefix
        let prefixMatches = words.filter { $0.lowercased().hasPrefix(String(prefix)) }

        let candidates = prefixMatches.isEmpty ? words : prefixMatches

        // Pick the candidate closest in length to the replacement
        let best = candidates.min { a, b in
            abs(a.count - replacement.count) < abs(b.count - replacement.count)
        }

        return best ?? replacement
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        ignoredClipboardContents = []
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
