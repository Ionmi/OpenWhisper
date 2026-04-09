import Foundation

/// Implements eager-mode streaming transcription based on WhisperKit's approach.
///
/// Algorithm:
/// 1. Each pass transcribes the full audio with `clipTimestamps` and `prefixTokens`.
/// 2. Filter words to those starting at or after `lastAgreedSeconds`.
/// 3. Compare with previous hypothesis via longest common prefix.
/// 4. When the common prefix has enough words (≥ confirmationsNeeded),
///    confirm all but the last `confirmationsNeeded` words.
/// 5. The last `confirmationsNeeded` agreed words become the anchor for the next pass.
/// 6. On finalize, accept the remaining hypothesis.
@MainActor
final class StreamingTranscriptionManager {

    private(set) var confirmedWords: [TranscriptionWord] = []
    private(set) var hypothesisWords: [TranscriptionWord] = []

    /// The last N agreed words used as anchor for the next pass.
    private(set) var lastAgreedWords: [TranscriptionWord] = []

    /// Audio timestamp of the first agreed anchor word.
    private(set) var lastAgreedSeconds: Float = 0
    private(set) var detectedLanguage: String = ""

    /// Previous pass words (filtered to >= lastAgreedSeconds).
    private var prevWords: [TranscriptionWord] = []

    /// How many agreed words to keep as an uncommitted buffer.
    private let confirmationsNeeded: Int = 2

    /// Cached confirmed text.
    private var cachedConfirmedText = ""

    // MARK: - Computed

    var currentText: String {
        let confirmed = cachedConfirmedText
        let anchor = lastAgreedWords.map(\.word).joined()
        let hypothesis = hypothesisWords.map(\.word).joined()
        return (confirmed + anchor + hypothesis).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var confirmedText: String {
        let anchor = lastAgreedWords.map(\.word).joined()
        return (cachedConfirmedText + anchor).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tokens from the last agreed words — feed these as `prefixTokens` to the next pass.
    var prefixTokens: [Int] {
        lastAgreedWords.flatMap(\.tokens)
    }

    /// The timestamp to pass as `clipTimestamps` for the next transcription pass.
    var clipTimestamp: Float {
        lastAgreedSeconds
    }

    // MARK: - Processing

    func process(output: TranscriptionOutput) {
        detectedLanguage = output.detectedLanguage

        // Filter words to those at or after the agreed anchor point.
        let newWords = output.words.filter { $0.start >= lastAgreedSeconds }

        guard !newWords.isEmpty else {
            hypothesisWords = []
            return
        }

        let commonPrefix = longestCommonPrefix(prevWords, newWords)

        if commonPrefix.count >= confirmationsNeeded {
            // Promote all but the last N agreed words to confirmed.
            let toConfirm = Array(commonPrefix.prefix(commonPrefix.count - confirmationsNeeded))
            confirmWords(toConfirm)

            // Keep last N as the anchor for the next pass.
            lastAgreedWords = Array(commonPrefix.suffix(confirmationsNeeded))
            lastAgreedSeconds = lastAgreedWords.first!.start

            // Hypothesis is everything after the common prefix.
            hypothesisWords = Array(newWords.dropFirst(commonPrefix.count))
        } else {
            // Not enough agreement — keep showing as hypothesis, don't advance anchor.
            hypothesisWords = newWords
        }

        prevWords = newWords
    }

    /// Accept remaining hypothesis when the user stops recording.
    func finalize(lastOutput: TranscriptionOutput?) {
        let wordsToFinalize: [TranscriptionWord]
        if let lastOutput, !lastOutput.words.isEmpty {
            wordsToFinalize = lastOutput.words.filter { $0.start >= lastAgreedSeconds }
        } else {
            wordsToFinalize = lastAgreedWords + hypothesisWords
        }

        // Deduplicate against already-confirmed words before finalizing.
        let deduped = deduplicateAgainstConfirmed(wordsToFinalize)
        confirmWords(deduped)

        // Clear anchor words since they were just confirmed via deduped.
        lastAgreedWords = []
        hypothesisWords = []
        prevWords = []
    }

    func reset() {
        confirmedWords = []
        hypothesisWords = []
        lastAgreedWords = []
        prevWords = []
        lastAgreedSeconds = 0
        detectedLanguage = ""
        cachedConfirmedText = ""
    }

    // MARK: - Private

    private func confirmWords(_ words: [TranscriptionWord]) {
        guard !words.isEmpty else { return }
        confirmedWords.append(contentsOf: words)
        cachedConfirmedText += words.map(\.word).joined()
    }

    /// Remove leading words that duplicate the tail of already-confirmed words (UFAL approach).
    private func deduplicateAgainstConfirmed(_ words: [TranscriptionWord]) -> [TranscriptionWord] {
        guard !words.isEmpty, !confirmedWords.isEmpty else { return words }

        var result = words
        let maxCheck = min(5, min(confirmedWords.count, result.count))

        for n in stride(from: maxCheck, through: 1, by: -1) {
            let confirmedTail = confirmedWords.suffix(n).map { normalizeWord($0.word) }
            let newHead = result.prefix(n).map { normalizeWord($0.word) }

            if confirmedTail == Array(newHead) {
                result = Array(result.dropFirst(n))
                break
            }
        }

        return result
    }

    // MARK: - LocalAgreement

    private func longestCommonPrefix(_ a: [TranscriptionWord], _ b: [TranscriptionWord]) -> [TranscriptionWord] {
        let limit = min(a.count, b.count)
        var length = 0
        for i in 0..<limit {
            if normalizeWord(a[i].word) == normalizeWord(b[i].word) {
                length = i + 1
            } else {
                break
            }
        }
        return Array(b.prefix(length))
    }

    private func normalizeWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isPunctuation }
    }
}
