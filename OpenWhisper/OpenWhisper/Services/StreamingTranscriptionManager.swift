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

    // MARK: - Output

    /// Words confirmed by LocalAgreement-2 (won't change)
    private(set) var confirmedWords: [TranscriptionWord] = []

    /// Current hypothesis words (may change on next pass)
    private(set) var hypothesisWords: [TranscriptionWord] = []

    /// Previous hypothesis for LocalAgreement comparison.
    /// IMPORTANT: stores only the UNCONFIRMED tail from the previous pass,
    /// not the full output. This keeps it aligned with subsequent passes
    /// that start from the confirmed audio cursor.
    private var previousHypothesis: [TranscriptionWord] = []

    /// Audio timestamp (seconds) up to which words are confirmed.
    /// Audio before this point does not need re-transcription.
    private(set) var confirmedEndSeconds: Float = 0

    /// Detected language from the most recent transcription pass
    private(set) var detectedLanguage: String = ""

    // MARK: - Computed

    /// Full text: confirmed + current hypothesis
    var currentText: String {
        let confirmed = confirmedWords.map(\.word).joined()
        let hypothesis = hypothesisWords.map(\.word).joined()
        return (confirmed + hypothesis).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only confirmed (stable) text
    var confirmedText: String {
        confirmedWords.map(\.word).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Processing

    /// Process a new transcription result from a streaming pass.
    /// Applies LocalAgreement-2: compares with previous hypothesis,
    /// promotes the longest common word prefix to confirmed status.
    func process(output: TranscriptionOutput) {
        detectedLanguage = output.detectedLanguage
        let newWords = output.words

        guard !newWords.isEmpty else {
            hypothesisWords = []
            return
        }

        // LocalAgreement-2: find longest common prefix between
        // previous hypothesis and current hypothesis.
        // Both start from the same audio cursor, so word[0] should align.
        let prefixLength = longestCommonPrefix(previousHypothesis, newWords)

        if prefixLength > 0 {
            // Promote the agreed prefix to confirmed
            let agreedWords = Array(newWords.prefix(prefixLength))
            confirmedWords.append(contentsOf: agreedWords)

            // Advance cursor to end of last confirmed word
            if let lastConfirmed = agreedWords.last {
                confirmedEndSeconds = lastConfirmed.end
            }

            // Remaining words are the new hypothesis
            hypothesisWords = Array(newWords.dropFirst(prefixLength))
        } else {
            // No agreement yet — entire output is hypothesis
            hypothesisWords = newWords
        }

        // Save ONLY the unconfirmed portion for next comparison.
        // This is critical: next pass starts from confirmedEndSeconds,
        // so its output will align with these unconfirmed words, not
        // the confirmed ones.
        previousHypothesis = Array(newWords.dropFirst(prefixLength))
    }

    /// Finalize: accept all remaining hypothesis words as confirmed.
    /// Called when the user stops recording.
    func finalize(lastOutput: TranscriptionOutput?) {
        if let lastOutput, !lastOutput.words.isEmpty {
            // One more agreement check against remaining hypothesis
            let finalWords = lastOutput.words
            let prefixLength = longestCommonPrefix(previousHypothesis, finalWords)

            if prefixLength > 0 {
                let agreedWords = Array(finalWords.prefix(prefixLength))
                confirmedWords.append(contentsOf: agreedWords)
                // Accept remaining as confirmed too (it's the final pass)
                confirmedWords.append(contentsOf: Array(finalWords.dropFirst(prefixLength)))
            } else {
                // No agreement — accept all final words
                confirmedWords.append(contentsOf: finalWords)
            }
        } else {
            // No final output — accept current hypothesis as-is
            confirmedWords.append(contentsOf: hypothesisWords)
        }

        hypothesisWords = []
        previousHypothesis = []

        if let last = confirmedWords.last {
            confirmedEndSeconds = last.end
        }
    }

    /// Reset all state for a new recording session.
    func reset() {
        confirmedWords = []
        hypothesisWords = []
        previousHypothesis = []
        confirmedEndSeconds = 0
        detectedLanguage = ""
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
