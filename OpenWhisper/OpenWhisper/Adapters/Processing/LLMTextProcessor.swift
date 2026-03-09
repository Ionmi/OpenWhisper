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

        let systemPrompt = Self.buildSystemPrompt(language: language, tone: tone, dictionaryTerms: dictString)
        let result = try await llm.generate(systemPrompt: systemPrompt, userPrompt: text)
        return result.isEmpty ? text : result
    }

    static func buildSystemPrompt(language: String, tone: String, dictionaryTerms: String) -> String {
        // Minimal prompt — fewer tokens = faster inference on small models.
        // /no_think disables chain-of-thought on Qwen/DeepSeek models.
        let lang = switch language {
        case "es": "español"
        case "en": "English"
        default: language
        }
        let dict = dictionaryTerms.isEmpty ? "" : " Terms:\(dictionaryTerms)."
        return "/no_think\nFix dictated \(lang) text. Tone:\(tone). Fix grammar, remove false starts/repetitions/self-corrections. Keep meaning, don't translate.\(dict) Output ONLY corrected text."
    }
}
