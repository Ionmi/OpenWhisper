import Foundation

final class LLMTextProcessor {
    private let llm: LLMPort
    private let appDetector: AppDetectionPort
    private let contextConfig: ContextModeConfig
    private let dictionaryAdapter: DictionaryPort

    init(
        llm: LLMPort,
        appDetector: AppDetectionPort,
        contextConfig: ContextModeConfig = .default,
        dictionaryAdapter: DictionaryPort
    ) {
        self.llm = llm
        self.appDetector = appDetector
        self.contextConfig = contextConfig
        self.dictionaryAdapter = dictionaryAdapter
    }

    func process(_ text: String, language: String) async throws -> String {
        guard llm.isModelLoaded else { return text }

        let tone: String
        if let bundleID = appDetector.frontmostAppBundleID(),
           let entry = contextConfig.entries.first(where: { $0.appBundleID == bundleID }) {
            tone = entry.tone
        } else {
            tone = contextConfig.defaultTone
        }

        let dictEntries = dictionaryAdapter.load()
        let dictString = dictEntries.isEmpty ? "" : dictEntries.map { "\($0.from)->\($0.to)" }.joined(separator: ",")

        let systemPrompt = Self.buildSystemPrompt(tone: tone, dictionaryTerms: dictString, language: language)
        let result = try await llm.generate(systemPrompt: systemPrompt, userPrompt: text)
        return result.isEmpty ? text : result
    }

    private static let languageNames: [String: String] = [
        "en": "English", "es": "Spanish", "fr": "French", "de": "German",
        "it": "Italian", "pt": "Portuguese", "ja": "Japanese", "ko": "Korean",
        "zh": "Chinese", "ru": "Russian", "ar": "Arabic", "hi": "Hindi",
    ]

    static func buildSystemPrompt(tone: String = "neutral", dictionaryTerms: String = "", language: String = "en") -> String {
        let langName = languageNames[language] ?? "the same as the input"
        var rules = """
You clean up dictated text. The text is in \(langName). Your output MUST be in \(langName). NEVER translate.
Rules:
1. Add punctuation and fix capitalization.
2. Remove stutters ("I I", "the the").
3. NEVER add words that were not spoken.
4. NEVER change the meaning.
"""
        if !dictionaryTerms.isEmpty {
            rules += "\n5. Apply these replacements when you recognize a match (even if split across words or misspelled): \(dictionaryTerms)."
        }
        rules += "\nTone: \(tone). Output ONLY the cleaned text."
        return rules
    }
}
