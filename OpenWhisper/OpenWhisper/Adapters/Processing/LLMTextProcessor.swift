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

        // Determine tone from frontmost app
        let tone: String
        if let bundleID = appDetector.frontmostAppBundleID(),
           let entry = contextConfig.entries.first(where: { $0.appBundleID == bundleID }) {
            tone = entry.tone
        } else {
            tone = contextConfig.defaultTone
        }

        // Build dictionary terms string
        let dictEntries = dictionaryAdapter.load()
        let dictString = dictEntries.map { "\($0.from) -> \($0.to)" }.joined(separator: ", ")

        // Build system prompt in the same language as input to prevent drift
        let systemPrompt = Self.systemPrompt(language: language, tone: tone, dictionaryTerms: dictString)

        let result = try await llm.generate(systemPrompt: systemPrompt, userPrompt: text)
        return result.isEmpty ? text : result
    }

    private static func systemPrompt(language: String, tone: String, dictionaryTerms: String) -> String {
        switch language {
        case "es":
            return """
            Eres un post-procesador de texto para dictado por voz. Reglas:
            - Corrige auto-correcciones (ej: "2... en realidad 3" -> "3")
            - Elimina arranques falsos y repeticiones
            - Corrige errores gramaticales
            - Tono: \(tone)
            - Conserva el significado original y el idioma. NO traduzcas.
            - Usa estas palabras exactas del diccionario: \(dictionaryTerms)
            - Devuelve SOLO el texto corregido, nada mas.
            """
        case "en":
            return """
            You are a text post-processor for voice dictation. Rules:
            - Fix self-corrections (e.g., "2... actually 3" -> "3")
            - Remove false starts and repetitions
            - Fix grammar errors
            - Tone: \(tone)
            - Preserve original meaning and language. Do NOT translate.
            - Use these exact dictionary spellings: \(dictionaryTerms)
            - Output ONLY the corrected text, nothing else.
            """
        default:
            return """
            You are a text post-processor for voice dictation. Rules:
            - Fix self-corrections (e.g., "2... actually 3" -> "3")
            - Remove false starts and repetitions
            - Fix grammar errors
            - Tone: \(tone)
            - Preserve original meaning and language. Do NOT translate.
            - The input text is in language code: \(language). Keep it in that language.
            - Use these exact dictionary spellings: \(dictionaryTerms)
            - Output ONLY the corrected text, nothing else.
            """
        }
    }
}
