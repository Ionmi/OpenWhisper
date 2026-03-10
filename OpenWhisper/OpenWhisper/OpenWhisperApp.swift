import SwiftUI

@main
struct OpenWhisperApp: App {
    @State private var appState = AppState()
    @State private var updaterService = UpdaterService()
    @State private var didAutoSetup = false

    init() {
        Self.applyStoredLanguage()
    }

    /// The language code that was actually applied at launch ("en", "es", …).
    static private(set) var appliedLanguageCode: String = "en"

    /// Resolves a stored uiLanguage value ("auto", "en", "es", …) to an actual
    /// language code, applying the same logic used at launch.
    static func resolveLanguageCode(for stored: String) -> String {
        Constants.SupportedUILanguages.resolvedCode(for: stored)
    }

    /// Reads the stored uiLanguage preference and applies it to AppleLanguages
    /// so SwiftUI picks up the correct locale for all String(localized:) lookups.
    /// Must run before any UI is created.
    private static func applyStoredLanguage() {
        let stored = UserDefaults.standard.string(forKey: Constants.Defaults.uiLanguage)
            ?? Constants.SupportedUILanguages.defaultLanguage
        let code = resolveLanguageCode(for: stored)
        appliedLanguageCode = code
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
