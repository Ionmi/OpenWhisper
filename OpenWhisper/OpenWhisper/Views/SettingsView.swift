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
            AudioSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }
            PostProcessingSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Processing", systemImage: "text.badge.checkmark")
                }
            ContextModesSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Context", systemImage: "app.badge")
                }
            LLMSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("LLM", systemImage: "brain")
                }
            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 450)
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

// MARK: - Audio Tab

struct AudioSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var audioSettings = appState.audioSettings
        Form {
            Section("Noise Reduction") {
                Toggle("Echo Cancellation (AEC)", isOn: $audioSettings.aecEnabled)
                Text("Removes system audio (music, videos) from your microphone input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Noise Suppression", isOn: $audioSettings.noiseSuppressionEnabled)
                Text("Reduces background noise (fan, keyboard, street).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice Detection") {
                Toggle("Voice Activity Detection (VAD)", isOn: $audioSettings.vadEnabled)
                Text("Only transcribes when speech is detected. Reduces false transcriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Post-Processing Tab

struct PostProcessingSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var dictionaryEntries: [DictionaryEntry] = []
    @State private var snippetEntries: [SnippetEntry] = []
    @State private var newDictFrom = ""
    @State private var newDictTo = ""
    @State private var newSnippetTrigger = ""
    @State private var newSnippetText = ""

    var body: some View {
        Form {
            Section("Dictionary") {
                ForEach(dictionaryEntries) { entry in
                    HStack {
                        Text(entry.from)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(entry.to)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontWeight(.medium)
                        Button(role: .destructive) {
                            appState.dictionaryAdapter?.removeEntry(id: entry.id)
                            dictionaryEntries = appState.dictionaryAdapter?.load() ?? []
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("From", text: $newDictFrom)
                    TextField("To", text: $newDictTo)
                    Button("Add") {
                        guard !newDictFrom.isEmpty, !newDictTo.isEmpty else { return }
                        appState.dictionaryAdapter?.addEntry(DictionaryEntry(from: newDictFrom, to: newDictTo))
                        dictionaryEntries = appState.dictionaryAdapter?.load() ?? []
                        newDictFrom = ""
                        newDictTo = ""
                    }
                }
            }

            Section("Snippets") {
                ForEach(snippetEntries) { entry in
                    HStack {
                        Text(entry.trigger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontWeight(.medium)
                        Text(String(entry.text.prefix(40)) + (entry.text.count > 40 ? "..." : ""))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            appState.snippetAdapter?.removeEntry(id: entry.id)
                            snippetEntries = appState.snippetAdapter?.load() ?? []
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Trigger phrase", text: $newSnippetTrigger)
                    TextField("Expanded text", text: $newSnippetText)
                    Button("Add") {
                        guard !newSnippetTrigger.isEmpty, !newSnippetText.isEmpty else { return }
                        appState.snippetAdapter?.addEntry(SnippetEntry(trigger: newSnippetTrigger, text: newSnippetText))
                        snippetEntries = appState.snippetAdapter?.load() ?? []
                        newSnippetTrigger = ""
                        newSnippetText = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            dictionaryEntries = appState.dictionaryAdapter?.load() ?? []
            snippetEntries = appState.snippetAdapter?.load() ?? []
        }
    }
}

// MARK: - Context Modes Tab

struct ContextModesSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var entries: [ContextModeEntry] = []
    @State private var defaultTone = "neutral"

    var body: some View {
        Form {
            Section("Per-App Tone") {
                Text("When LLM is enabled, text is adjusted to match the tone configured for each app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(entries) { entry in
                    HStack {
                        Text(entry.appName)
                            .frame(width: 100, alignment: .leading)
                        Text(entry.tone)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Default Tone") {
                TextField("Default tone for unlisted apps", text: $defaultTone)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Text("Requires LLM to be enabled in the LLM settings tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let config = JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default
            entries = config.entries
            defaultTone = config.defaultTone
        }
    }
}

// MARK: - LLM Tab

struct LLMSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var llmSettings = appState.llmSettings
        Form {
            Section {
                Toggle("Enable LLM Post-Processing", isOn: $llmSettings.isEnabled)
                    .toggleStyle(.switch)

                Text("Uses AI to fix self-corrections, adjust tone, and improve grammar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if llmSettings.isEnabled {
                Section("Source") {
                    Picker("Source", selection: $llmSettings.source) {
                        ForEach(LLMSettings.LLMSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if llmSettings.source == .local {
                    Section("Local Model") {
                        if let manager = appState.llmModelManager {
                            if manager.availableLocalModels.isEmpty {
                                Text("No models downloaded yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Model", selection: $llmSettings.selectedLocalModel) {
                                    ForEach(manager.availableLocalModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                            }

                            if manager.isDownloading {
                                ProgressView(value: manager.downloadProgress)
                                    .progressViewStyle(.linear)
                                Text("Downloading... \(Int(manager.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Available Models") {
                        ForEach(LLMModelManager.recommendedModels) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .fontWeight(.medium)
                                    Text("\(model.size) — \(model.languages) — \(model.license)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if appState.llmModelManager?.availableLocalModels.contains(model.filename) == true {
                                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                } else {
                                    Button("Download") {
                                        Task {
                                            try? await appState.llmModelManager?.downloadModel(model)
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                } else {
                    Section("Remote API") {
                        TextField("Base URL", text: $llmSettings.remoteBaseURL)
                            .textFieldStyle(.roundedBorder)
                        SecureField("API Key (optional)", text: $llmSettings.remoteAPIKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Model name", text: $llmSettings.remoteModelName)
                            .textFieldStyle(.roundedBorder)
                        Text("Compatible with OpenAI API format (OpenAI, Ollama, OpenRouter, LM Studio, etc.)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
