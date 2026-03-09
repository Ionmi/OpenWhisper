import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            HotkeySettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Shortcut", systemImage: "keyboard")
                }
            ModelSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
            AppearanceSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)

                Picker("Language", selection: $settings.selectedLanguage) {
                    ForEach(Constants.SupportedLanguages.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            }

            Section("Output") {
                Picker("After transcription", selection: $settings.outputMode) {
                    ForEach(Constants.OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(settings.outputMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Microphone") {
                    if appState.permissionsManager.hasMicrophonePermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else {
                        Button("Request") {
                            Task {
                                await appState.permissionsManager.requestMicrophonePermission()
                            }
                        }
                        .controlSize(.small)
                    }
                }

                LabeledContent("Accessibility") {
                    if appState.permissionsManager.hasAccessibilityPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    } else {
                        Button("Open Settings") {
                            appState.permissionsManager.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.permissionsManager.checkAllPermissions()
            appState.permissionsManager.startPolling()
        }
        .onDisappear {
            appState.permissionsManager.stopPolling()
        }
    }
}

// MARK: - Shortcut Tab

struct HotkeySettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var isRecordingHotkey = false

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("Shortcut Mode") {
                Picker("Mode", selection: $settings.shortcutMode) {
                    ForEach(Constants.ShortcutMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(settings.shortcutMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global Shortcut") {
                LabeledContent("Current hotkey") {
                    Text(appState.settings.hotkeyDisplayString)
                        .fontDesign(.monospaced)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                if isRecordingHotkey {
                    Text("Press new key combination…")
                        .foregroundStyle(.orange)
                        .onAppear {
                            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                                if !mods.isEmpty && event.keyCode != 0 {
                                    appState.settings.hotkeyKeyCode = event.keyCode
                                    appState.settings.hotkeyModifiers = UInt32(mods.rawValue)
                                    appState.hotkeyService?.updateHotkey(
                                        keyCode: event.keyCode,
                                        modifiers: UInt32(mods.rawValue)
                                    )
                                    isRecordingHotkey = false
                                }
                                return nil
                            }
                        }
                } else {
                    HStack {
                        Button("Record New Hotkey") {
                            isRecordingHotkey = true
                        }

                        Button("Reset to Default (\u{2325}Space)") {
                            appState.settings.hotkeyKeyCode = Constants.defaultHotkeyKeyCode
                            appState.settings.hotkeyModifiers = Constants.defaultHotkeyModifiers
                            appState.hotkeyService?.updateHotkey(
                                keyCode: Constants.defaultHotkeyKeyCode,
                                modifiers: Constants.defaultHotkeyModifiers
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.shortcutMode) {
            appState.updateShortcutMode()
        }
    }
}

// MARK: - Appearance Tab

struct AppearanceSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section("Recording Indicator") {
                HStack(spacing: 16) {
                    ForEach(Constants.IndicatorStyle.allCases) { style in
                        IndicatorPreview(
                            style: style,
                            isSelected: settings.indicatorStyle == style
                        )
                        .onTapGesture {
                            settings.indicatorStyle = style
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Section("Position") {
                Picker("Position", selection: $settings.indicatorPosition) {
                    ForEach(Constants.IndicatorPosition.allCases) { pos in
                        Text(pos.label).tag(pos)
                    }
                }

                Text("You can also drag the indicator while recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live Preview") {
                Toggle("Show live transcription in indicator", isOn: $settings.showLivePreview)
                    .toggleStyle(.switch)
                    .tint(.green)

                Text("The indicator expands to show transcribed text in real time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Model Tab

struct ModelSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(Constants.SupportedModels.all, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                if appState.isLoadingModel {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if appState.isModelLoaded {
                    LabeledContent("Status") {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Download & Load Model") {
                        Task {
                            await appState.loadTranscriptionEngine()
                        }
                    }
                }
            }

            Section("Info") {
                Text("Models are downloaded automatically by WhisperKit on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Storage: ~/Library/Application Support/OpenWhisper/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    private let repoURL = URL(string: "https://github.com/Ionmi/OpenWhisper")!
    private let issuesURL = URL(string: "https://github.com/Ionmi/OpenWhisper/issues")!

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("OpenWhisper")
                        .font(.title2.bold())
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                }
                Text("Local voice-to-text for macOS. Runs entirely on-device using OpenAI's Whisper model.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Links") {
                Link(destination: repoURL) {
                    LabeledContent {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.tertiary)
                    } label: {
                        Label("GitHub Repository", systemImage: "link")
                    }
                }
                Link(destination: issuesURL) {
                    LabeledContent {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.tertiary)
                    } label: {
                        Label("Report Issue", systemImage: "ladybug")
                    }
                }
            }

            Section("License") {
                Text("MIT License")
                Text("Made with ❤️ by Ionmi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
