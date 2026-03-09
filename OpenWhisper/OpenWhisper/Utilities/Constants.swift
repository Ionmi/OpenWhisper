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
            case .topCenter: "Top Center"
            case .bottomCenter: "Bottom Center"
            case .topLeft: "Top Left"
            case .topRight: "Top Right"
            case .bottomLeft: "Bottom Left"
            case .bottomRight: "Bottom Right"
            }
        }
    }

    enum IndicatorStyle: String, CaseIterable, Identifiable {
        case pill = "pill"
        case minimal = "minimal"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pill: "Pill"
            case .minimal: "Minimal"
            }
        }

        var description: String {
            switch self {
            case .pill: "Red dot with waveform bars"
            case .minimal: "Compact dot only"
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
            case .auto: "Auto"
            case .toggle: "Toggle"
            case .hold: "Hold"
            }
        }

        var description: String {
            switch self {
            case .auto: "Quick press to toggle, hold to record while pressed"
            case .toggle: "Press to start, Enter to confirm, ESC to cancel"
            case .hold: "Hold to record, release to confirm"
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
            case .pasteAutomatic: "Paste automatically"
            case .clipboardOnly: "Copy to clipboard"
            case .historyOnly: "History only"
            }
        }

        var description: String {
            switch self {
            case .pasteAutomatic: "Pastes text at cursor when confirmed"
            case .clipboardOnly: "Copies text to clipboard when confirmed"
            case .historyOnly: "Only saves to transcription history"
            }
        }
    }

    enum SupportedModels {
        static let all = [
            "tiny", "tiny.en",
            "base", "base.en",
            "small", "small.en",
            "medium", "medium.en",
            "large-v3", "large-v3-turbo",
        ]
        static let defaultModel = "base"

        static let descriptions: [String: (size: String, quality: String)] = [
            "tiny":           ("~75 MB",  "Fastest, lower accuracy"),
            "tiny.en":        ("~75 MB",  "Fastest, English only"),
            "base":           ("~145 MB", "Fast, good accuracy"),
            "base.en":        ("~145 MB", "Fast, English only"),
            "small":          ("~465 MB", "Balanced speed & accuracy"),
            "small.en":       ("~465 MB", "Balanced, English only"),
            "medium":         ("~1.5 GB", "High accuracy, slower"),
            "medium.en":      ("~1.5 GB", "High accuracy, English only"),
            "large-v3":       ("~3 GB",   "Best accuracy, slowest"),
            "large-v3-turbo": ("~1.6 GB", "Near-best accuracy, faster"),
        ]
    }

    enum SupportedLanguages {
        static let all: [(code: String, name: String)] = [
            ("auto", "Auto-detect"),
            ("en", "English"),
            ("es", "Spanish"),
            ("fr", "French"),
            ("de", "German"),
            ("it", "Italian"),
            ("pt", "Portuguese"),
            ("ja", "Japanese"),
            ("ko", "Korean"),
            ("zh", "Chinese"),
            ("ru", "Russian"),
            ("ar", "Arabic"),
            ("hi", "Hindi"),
        ]
        static let defaultLanguage = "en"
    }
}
