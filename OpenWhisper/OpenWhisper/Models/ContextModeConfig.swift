import Foundation

struct ContextModeEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var appBundleID: String
    var appName: String
    var tone: String
}

struct ContextModeConfig: Codable {
    var entries: [ContextModeEntry]
    var defaultTone: String

    static let `default` = ContextModeConfig(
        entries: [
            ContextModeEntry(appBundleID: "com.apple.mail", appName: "Mail", tone: "formal, professional"),
            ContextModeEntry(appBundleID: "com.microsoft.Outlook", appName: "Outlook", tone: "formal, professional"),
            ContextModeEntry(appBundleID: "com.tinyspeck.slackmacgap", appName: "Slack", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "com.hnc.Discord", appName: "Discord", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "com.apple.MobileSMS", appName: "Messages", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "ru.keepcoder.Telegram", appName: "Telegram", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "com.apple.Notes", appName: "Notes", tone: "neutral"),
            ContextModeEntry(appBundleID: "com.apple.TextEdit", appName: "TextEdit", tone: "neutral"),
            ContextModeEntry(appBundleID: "com.apple.Terminal", appName: "Terminal", tone: "technical, precise"),
            ContextModeEntry(appBundleID: "com.microsoft.VSCode", appName: "VS Code", tone: "technical, precise"),
            ContextModeEntry(appBundleID: "com.apple.dt.Xcode", appName: "Xcode", tone: "technical, precise"),
            ContextModeEntry(appBundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor", tone: "technical, precise"),
        ],
        defaultTone: "neutral"
    )
}
