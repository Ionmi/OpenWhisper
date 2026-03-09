import Foundation

struct PunctuationCommand: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var replacement: String
}

struct PunctuationConfig: Codable {
    var commandsByLanguage: [String: [PunctuationCommand]]

    static let `default` = PunctuationConfig(commandsByLanguage: [
        "es": [
            PunctuationCommand(trigger: "coma", replacement: ","),
            PunctuationCommand(trigger: "punto", replacement: "."),
            PunctuationCommand(trigger: "punto y coma", replacement: ";"),
            PunctuationCommand(trigger: "dos puntos", replacement: ":"),
            PunctuationCommand(trigger: "interrogacion", replacement: "?"),
            PunctuationCommand(trigger: "signo de interrogacion", replacement: "?"),
            PunctuationCommand(trigger: "exclamacion", replacement: "!"),
            PunctuationCommand(trigger: "signo de exclamacion", replacement: "!"),
            PunctuationCommand(trigger: "nueva linea", replacement: "\n"),
            PunctuationCommand(trigger: "salto de linea", replacement: "\n"),
            PunctuationCommand(trigger: "abrir parentesis", replacement: "("),
            PunctuationCommand(trigger: "cerrar parentesis", replacement: ")"),
            PunctuationCommand(trigger: "puntos suspensivos", replacement: "..."),
        ],
        "en": [
            PunctuationCommand(trigger: "comma", replacement: ","),
            PunctuationCommand(trigger: "period", replacement: "."),
            PunctuationCommand(trigger: "full stop", replacement: "."),
            PunctuationCommand(trigger: "semicolon", replacement: ";"),
            PunctuationCommand(trigger: "colon", replacement: ":"),
            PunctuationCommand(trigger: "question mark", replacement: "?"),
            PunctuationCommand(trigger: "exclamation mark", replacement: "!"),
            PunctuationCommand(trigger: "exclamation point", replacement: "!"),
            PunctuationCommand(trigger: "new line", replacement: "\n"),
            PunctuationCommand(trigger: "open parenthesis", replacement: "("),
            PunctuationCommand(trigger: "close parenthesis", replacement: ")"),
            PunctuationCommand(trigger: "ellipsis", replacement: "..."),
        ],
    ])
}
