import Foundation

/// Implements the LocalAgreement-2 streaming policy for real-time transcription.
///
/// Algorithm (from UFAL "Turning Whisper into Real-Time Transcription"):
/// 1. Each transcription pass produces a list of hypothesis words with timestamps.
/// 2. Compare current hypothesis with previous hypothesis.
/// 3. The longest common prefix (by word text) becomes "confirmed" — stable output.
/// 4. The audio cursor advances to the end of the last confirmed word.
/// 5. On finalize, the remaining hypothesis is accepted as confirmed.
///
/// Key invariant: `previousHypothesis` always stores ONLY the unconfirmed
/// portion of the last pass (not confirmed words). This ensures alignment
/// with the next pass, which starts from the confirmed audio cursor.
@MainActor
final class StreamingTranscriptionManager {

    private(set) var confirmedWords: [TranscriptionWord] = []
    private(set) var hypothesisWords: [TranscriptionWord] = []

    /// Stores only the UNCONFIRMED tail from the previous pass.
    /// Keeps alignment with subsequent passes that start from the confirmed cursor.
    private var previousHypothesis: [TranscriptionWord] = []

    /// Audio before this point does not need re-transcription.
    private(set) var confirmedEndSeconds: Float = 0
    private(set) var detectedLanguage: String = ""

    /// Cached confirmed text — appended to when words are promoted, avoids
    /// rebuilding from the full array on every access.
    private var cachedConfirmedText = ""

    // MARK: - Computed

    var currentText: String {
        let hypothesis = hypothesisWords.map(\.word).joined()
        return (cachedConfirmedText + hypothesis).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var confirmedText: String {
        cachedConfirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Processing

    func process(output: TranscriptionOutput) {
        detectedLanguage = output.detectedLanguage
        let newWords = output.words

        guard !newWords.isEmpty else {
            hypothesisWords = []
            return
        }

        let prefixLength = longestCommonPrefix(previousHypothesis, newWords)

        if prefixLength > 0 {
            let agreedWords = Array(newWords.prefix(prefixLength))
            confirmWords(agreedWords)
            hypothesisWords = Array(newWords.dropFirst(prefixLength))
        } else {
            hypothesisWords = newWords
        }

        // Next pass starts from confirmedEndSeconds, so only store unconfirmed tail.
        previousHypothesis = Array(newWords.dropFirst(prefixLength))
    }

    /// Accept remaining hypothesis when the user stops recording.
    func finalize(lastOutput: TranscriptionOutput?) {
        if let lastOutput, !lastOutput.words.isEmpty {
            let finalWords = lastOutput.words
            let prefixLength = longestCommonPrefix(previousHypothesis, finalWords)
            // Final pass supersedes any prior hypothesis — accept all words.
            confirmWords(Array(finalWords))
        } else {
            confirmWords(hypothesisWords)
        }

        hypothesisWords = []
        previousHypothesis = []
    }

    func reset() {
        confirmedWords = []
        hypothesisWords = []
        previousHypothesis = []
        confirmedEndSeconds = 0
        detectedLanguage = ""
        cachedConfirmedText = ""
    }

    private func confirmWords(_ words: [TranscriptionWord]) {
        guard !words.isEmpty else { return }
        confirmedWords.append(contentsOf: words)
        cachedConfirmedText += words.map(\.word).joined()
        if let last = words.last {
            confirmedEndSeconds = last.end
        }
    }

    // MARK: - LocalAgreement

    /// Find the longest common prefix between two word sequences.
    /// Words match by normalized text (trimmed, lowercased, punctuation stripped).
    private func longestCommonPrefix(_ a: [TranscriptionWord], _ b: [TranscriptionWord]) -> Int {
        let limit = min(a.count, b.count)
        var length = 0
        for i in 0..<limit {
            if normalizeWord(a[i].word) == normalizeWord(b[i].word) {
                length = i + 1
            } else {
                break
            }
        }
        return length
    }

    /// Normalize a word for comparison.
    /// WhisperKit may attach punctuation differently between passes
    /// (e.g., "hello," vs "hello"), so strip trailing punctuation.
    private func normalizeWord(_ word: String) -> String {
        var w = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip trailing punctuation for more robust matching
        while let last = w.last, last.isPunctuation {
            w.removeLast()
        }
        return w
    }
}
