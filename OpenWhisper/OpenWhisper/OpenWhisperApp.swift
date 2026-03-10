import SwiftUI

@main
struct OpenWhisperApp: App {
    @State private var appState = AppState()
    @State private var updaterService = UpdaterService()
    @State private var didAutoSetup = false

    init() {
        Self.applyStoredLanguage()
    }

    /// Language codes supported for UI localization beyond English.
    private static let supportedUICodes: Set<String> = ["es"]

    /// Reads the stored uiLanguage preference and applies it to AppleLanguages
    /// so SwiftUI picks up the correct locale for all String(localized:) lookups.
    /// Must run before any UI is created.
    private static func applyStoredLanguage() {
        let stored = UserDefaults.standard.string(forKey: Constants.Defaults.uiLanguage)
            ?? Constants.SupportedUILanguages.defaultLanguage
        let code: String
        if stored == Constants.SupportedUILanguages.defaultLanguage {
            let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
            code = supportedUICodes.contains(systemCode) ? systemCode : "en"
        } else {
            code = stored
        }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(updaterService)
        } label: {
            StatusIndicatorView(state: appState.currentState)
                .task {
                    // The label is created at app launch (not lazily)
                    performAutoSetupIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Window("OpenWhisper Setup", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        // Settings window is managed by SettingsWindowController (AppKit)
    }

    private func performAutoSetupIfNeeded() {
        guard !didAutoSetup, appState.settings.onboardingCompleted else { return }
        didAutoSetup = true
        appState.permissionsManager.checkAllPermissions()
        appState.setupServices()
        Task {
            // Request microphone permission if not yet granted
            if !appState.permissionsManager.hasMicrophonePermission {
                await appState.permissionsManager.requestMicrophonePermission()
            }
            await appState.loadTranscriptionEngine()
        }
    }
}
