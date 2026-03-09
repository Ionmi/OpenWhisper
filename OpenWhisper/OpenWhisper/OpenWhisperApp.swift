import SwiftUI

@main
struct OpenWhisperApp: App {
    @State private var appState = AppState()
    @State private var didAutoSetup = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
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

        Settings {
            SettingsView()
                .environment(appState)
        }
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
