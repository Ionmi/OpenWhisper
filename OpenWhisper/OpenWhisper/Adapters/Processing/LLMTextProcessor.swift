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

        let systemPrompt = Self.buildSystemPrompt(tone: tone, dictionaryTerms: dictString)
        let result = try await llm.generate(systemPrompt: systemPrompt, userPrompt: text)
        return result.isEmpty ? text : result
    }

    static func buildSystemPrompt(tone: String = "neutral", dictionaryTerms: String = "") -> String {
        let dict = dictionaryTerms.isEmpty ? "" : " Use these terms:\(dictionaryTerms)."
        return "Fix dictated text with minimal changes. Only fix grammar, remove false starts and self-corrections. Keep the original words and structure. Tone:\(tone).\(dict) Reply with ONLY the fixed text."
    }
}
