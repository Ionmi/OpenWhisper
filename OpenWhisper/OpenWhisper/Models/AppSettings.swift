import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

@Observable
final class AppSettings {
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var hotkeyKeyCode: UInt16 {
        didSet { save(Int(hotkeyKeyCode), forKey: Constants.Defaults.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        didSet { save(Int(hotkeyModifiers), forKey: Constants.Defaults.hotkeyModifiers) }
    }

    var selectedModel: String {
        didSet { save(selectedModel, forKey: Constants.Defaults.selectedModel) }
    }

    var selectedLanguage: String {
        didSet { save(selectedLanguage, forKey: Constants.Defaults.selectedLanguage) }
    }

    var uiLanguage: String {
        didSet {
            save(uiLanguage, forKey: Constants.Defaults.uiLanguage)
            let resolved = Constants.SupportedUILanguages.resolvedCode(for: uiLanguage)
            UserDefaults.standard.set([resolved], forKey: "AppleLanguages")
        }
    }

    var onboardingCompleted: Bool {
        didSet { save(onboardingCompleted, forKey: Constants.Defaults.onboardingCompleted) }
    }

    var indicatorPosition: Constants.IndicatorPosition {
        didSet { save(indicatorPosition.rawValue, forKey: Constants.Defaults.indicatorPosition) }
    }

    var indicatorStyle: Constants.IndicatorStyle {
        didSet { save(indicatorStyle.rawValue, forKey: Constants.Defaults.indicatorStyle) }
    }

    var shortcutMode: Constants.ShortcutMode {
        didSet { save(shortcutMode.rawValue, forKey: Constants.Defaults.shortcutMode) }
    }

    var outputMode: Constants.OutputMode {
        didSet { save(outputMode.rawValue, forKey: Constants.Defaults.outputMode) }
    }

    var showLivePreview: Bool {
        didSet { save(showLivePreview, forKey: Constants.Defaults.showLivePreview) }
    }

    var launchAtLogin: Bool {
        didSet {
            save(launchAtLogin, forKey: Constants.Defaults.launchAtLogin)
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure
                launchAtLogin = !launchAtLogin
                save(launchAtLogin, forKey: Constants.Defaults.launchAtLogin)
            }
        }
    }

    private func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    var hotkeyDisplayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        if flags.contains(.control) { parts.append("^") }
        if flags.contains(.option) { parts.append("\u{2325}") }
        if flags.contains(.shift) { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: Constants.Defaults.hotkeyKeyCode) != nil {
            hotkeyKeyCode = UInt16(d.integer(forKey: Constants.Defaults.hotkeyKeyCode))
        } else {
            hotkeyKeyCode = Constants.defaultHotkeyKeyCode
        }
        if d.object(forKey: Constants.Defaults.hotkeyModifiers) != nil {
            hotkeyModifiers = UInt32(d.integer(forKey: Constants.Defaults.hotkeyModifiers))
        } else {
            hotkeyModifiers = Constants.defaultHotkeyModifiers
        }
        selectedModel = d.string(forKey: Constants.Defaults.selectedModel)
            ?? Constants.SupportedModels.defaultModel
        selectedLanguage = d.string(forKey: Constants.Defaults.selectedLanguage)
            ?? Constants.SupportedLanguages.defaultLanguage
        onboardingCompleted = d.bool(forKey: Constants.Defaults.onboardingCompleted)

        if let posStr = d.string(forKey: Constants.Defaults.indicatorPosition),
           let pos = Constants.IndicatorPosition(rawValue: posStr) {
            indicatorPosition = pos
        } else {
            indicatorPosition = .bottomCenter
        }

        if let styleStr = d.string(forKey: Constants.Defaults.indicatorStyle),
           let style = Constants.IndicatorStyle(rawValue: styleStr) {
            indicatorStyle = style
        } else {
            indicatorStyle = .pill
        }

        if let modeStr = d.string(forKey: Constants.Defaults.shortcutMode),
           let mode = Constants.ShortcutMode(rawValue: modeStr) {
            shortcutMode = mode
        } else {
            shortcutMode = .auto
        }

        if let outStr = d.string(forKey: Constants.Defaults.outputMode),
           let out = Constants.OutputMode(rawValue: outStr) {
            outputMode = out
        } else {
            outputMode = .pasteAutomatic
        }

        if d.object(forKey: Constants.Defaults.showLivePreview) != nil {
            showLivePreview = d.bool(forKey: Constants.Defaults.showLivePreview)
        } else {
            showLivePreview = true
        }

        uiLanguage = d.string(forKey: Constants.Defaults.uiLanguage) ?? Constants.SupportedUILanguages.defaultLanguage
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "\u{21A9}"
        case kVK_Tab: return "\u{21E5}"
        case kVK_Escape: return "\u{238B}"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        default: return "Key(\(keyCode))"
        }
    }
}
