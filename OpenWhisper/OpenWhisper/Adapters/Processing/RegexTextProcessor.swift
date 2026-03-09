import Foundation

final class RegexTextProcessor: TextProcessingPort {
    private let dictionaryAdapter: DictionaryPort
    private let fillerConfig: FillerConfig
    private let punctuationConfig: PunctuationConfig

    init(
        dictionaryAdapter: DictionaryPort,
        fillerConfig: FillerConfig = .default,
        punctuationConfig: PunctuationConfig = .default
    ) {
        self.dictionaryAdapter = dictionaryAdapter
        self.fillerConfig = fillerConfig
        self.punctuationConfig = punctuationConfig
    }

    func process(_ text: String, language: String) -> String {
        var result = text

        // 1. Dictionary replacement (case-insensitive, whole word)
        let entries = dictionaryAdapter.load()
        for entry in entries {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.from))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: entry.to
                )
            }
        }

        // 2. Filler removal (whole word, case-insensitive)
        let lang = language == "auto" ? "en" : language
        let fillers = fillerConfig.fillersByLanguage[lang] ?? []
        let sortedFillers = fillers.sorted { $0.count > $1.count }
        for filler in sortedFillers {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            let pattern = "\\b\(escaped)\\b,?\\s*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // 3. Punctuation commands
        let commands = punctuationConfig.commandsByLanguage[lang] ?? []
        let sortedCommands = commands.sorted { $0.trigger.count > $1.trigger.count }
        for cmd in sortedCommands {
            let escaped = NSRegularExpression.escapedPattern(for: cmd.trigger)
            let pattern = "\\s*\\b\(escaped)\\b\\s*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: cmd.replacement
                )
            }
        }

        // Clean up multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
