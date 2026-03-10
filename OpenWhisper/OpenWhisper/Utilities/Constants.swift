import Foundation
import Carbon.HIToolbox
import AppKit

enum Constants {
    static let appName = "OpenWhisper"

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport
            .appendingPathComponent(appName)
            .appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Default hotkey: Option + Space
    static let defaultHotkeyKeyCode: UInt16 = UInt16(kVK_Space)
    static let defaultHotkeyModifiers: UInt32 = UInt32(NSEvent.ModifierFlags.option.rawValue)

    enum Defaults {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let selectedModel = "selectedModel"
        static let selectedLanguage = "selectedLanguage"
        static let pasteAutomatically = "pasteAutomatically"
        static let onboardingCompleted = "onboardingCompleted"
        static let indicatorPosition = "indicatorPosition"
        static let indicatorStyle = "indicatorStyle"
        static let shortcutMode = "shortcutMode"
        static let outputMode = "outputMode"
        static let showLivePreview = "showLivePreview"
        static let launchAtLogin = "launchAtLogin"
        static let uiLanguage = "uiLanguage"
    }

    enum IndicatorPosition: String, CaseIterable, Identifiable {
        case topCenter = "topCenter"
        case bottomCenter = "bottomCenter"
        case topLeft = "topLeft"
        case topRight = "topRight"
        case bottomLeft = "bottomLeft"
        case bottomRight = "bottomRight"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .topCenter: String(localized: "Top Center")
            case .bottomCenter: String(localized: "Bottom Center")
            case .topLeft: String(localized: "Top Left")
            case .topRight: String(localized: "Top Right")
            case .bottomLeft: String(localized: "Bottom Left")
            case .bottomRight: String(localized: "Bottom Right")
            }
        }
    }

    enum IndicatorStyle: String, CaseIterable, Identifiable {
        case pill = "pill"
        case minimal = "minimal"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pill: String(localized: "Pill")
            case .minimal: String(localized: "Minimal")
            }
        }

        var description: String {
            switch self {
            case .pill: String(localized: "Red dot with waveform bars")
            case .minimal: String(localized: "Compact dot only")
            }
        }
    }

    enum ShortcutMode: String, CaseIterable, Identifiable {
        case auto = "auto"
        case toggle = "toggle"
        case hold = "hold"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto: String(localized: "Auto")
            case .toggle: String(localized: "Toggle")
            case .hold: String(localized: "Hold")
            }
        }

        var description: String {
            switch self {
            case .auto: String(localized: "Quick press to toggle, hold to record while pressed")
            case .toggle: String(localized: "Press to start, Enter to confirm, ESC to cancel")
            case .hold: String(localized: "Hold to record, release to confirm")
            }
        }
    }

    enum OutputMode: String, CaseIterable, Identifiable {
        case pasteAutomatic = "pasteAutomatic"
        case clipboardOnly = "clipboardOnly"
        case historyOnly = "historyOnly"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pasteAutomatic: String(localized: "Paste automatically")
            case .clipboardOnly: String(localized: "Copy to clipboard")
            case .historyOnly: String(localized: "History only")
            }
        }

        var description: String {
            switch self {
            case .pasteAutomatic: String(localized: "Pastes text at cursor when confirmed")
            case .clipboardOnly: String(localized: "Copies text to clipboard when confirmed")
            case .historyOnly: String(localized: "Only saves to transcription history")
            }
        }
    }

    enum SupportedModels {
        struct WhisperModel: Identifiable {
            let id: String
            let family: String
            let displayName: String
            let size: String
            let sizeGB: Double
            let quality: String
            let isEnglishOnly: Bool
        }

        static let all: [WhisperModel] = [
            WhisperModel(id: "tiny",           family: "tiny",   displayName: "Tiny",              size: "~75 MB",   sizeGB: 0.075, quality: String(localized: "Fastest, lower accuracy"),     isEnglishOnly: false),
            WhisperModel(id: "tiny.en",        family: "tiny",   displayName: "Tiny (English)",     size: "~75 MB",   sizeGB: 0.075, quality: String(localized: "Fastest, English only"),        isEnglishOnly: true),
            WhisperModel(id: "base",           family: "base",   displayName: "Base",              size: "~145 MB",  sizeGB: 0.145, quality: String(localized: "Fast, good accuracy"),           isEnglishOnly: false),
            WhisperModel(id: "base.en",        family: "base",   displayName: "Base (English)",     size: "~145 MB",  sizeGB: 0.145, quality: String(localized: "Fast, English only"),            isEnglishOnly: true),
            WhisperModel(id: "small",          family: "small",  displayName: "Small",             size: "~465 MB",  sizeGB: 0.465, quality: String(localized: "Balanced speed & accuracy"),     isEnglishOnly: false),
            WhisperModel(id: "small.en",       family: "small",  displayName: "Small (English)",    size: "~465 MB",  sizeGB: 0.465, quality: String(localized: "Balanced, English only"),        isEnglishOnly: true),
            WhisperModel(id: "medium",         family: "medium", displayName: "Medium",            size: "~1.5 GB",  sizeGB: 1.5,   quality: String(localized: "High accuracy, slower"),          isEnglishOnly: false),
            WhisperModel(id: "medium.en",      family: "medium", displayName: "Medium (English)",   size: "~1.5 GB",  sizeGB: 1.5,   quality: String(localized: "High accuracy, English only"),    isEnglishOnly: true),
            WhisperModel(id: "large-v3",       family: "large",  displayName: "Large v3",          size: "~3 GB",    sizeGB: 3.0,   quality: String(localized: "Best accuracy, slowest"),          isEnglishOnly: false),
            WhisperModel(id: "large-v3-turbo", family: "large",  displayName: "Large v3 Turbo",    size: "~1.6 GB",  sizeGB: 1.6,   quality: String(localized: "Near-best accuracy, faster"),      isEnglishOnly: false),
        ]

        static let families: [String] = ["tiny", "base", "small", "medium", "large"]

        static let defaultModel = "base"
    }

    enum SupportedLanguages {
        static var all: [(code: String, name: String)] {
            [
                ("auto", String(localized: "Auto-detect")),
                ("en", "English"),
                ("es", "Español"),
                ("fr", "Français"),
                ("de", "Deutsch"),
                ("it", "Italiano"),
                ("pt", "Português"),
                ("ja", "日本語"),
                ("ko", "한국어"),
                ("zh", "中文"),
                ("ru", "Русский"),
                ("ar", "العربية"),
                ("hi", "हिन्दी"),
            ]
        }
        static let defaultLanguage = "en"
    }

    enum SupportedUILanguages {
        static let defaultLanguage = "auto"
        static let supportedCodes: Set<String> = ["es"]

        static func resolvedCode(for stored: String) -> String {
            if stored == defaultLanguage {
                let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
                return supportedCodes.contains(systemCode) ? systemCode : "en"
            }
            return stored
        }
    }
}
