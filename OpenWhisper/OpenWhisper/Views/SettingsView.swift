import AppKit
import SwiftUI

// MARK: - Settings Pages

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, shortcut, model, appearance, audio, processing, context, llm, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .shortcut: String(localized: "Shortcut")
        case .model: String(localized: "Model")
        case .appearance: String(localized: "Appearance")
        case .audio: String(localized: "Audio")
        case .processing: String(localized: "Processing")
        case .context: String(localized: "Context (Beta)")
        case .llm: String(localized: "LLM (Beta)")
        case .about: String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .shortcut: "keyboard"
        case .model: "cpu"
        case .appearance: "paintbrush"
        case .audio: "waveform"
        case .processing: "text.badge.checkmark"
        case .context: "app.badge"
        case .llm: "brain"
        case .about: "info.circle"
        }
    }
}

// MARK: - Navigation State

@Observable
final class SettingsNavigation {
    var selectedPage: SettingsPage = .general
}

// MARK: - Settings Window Controller (pure AppKit)

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    static var shared: SettingsWindowController?

    private static let trackingSeparatorID = NSToolbarItem.Identifier("sidebarTrackingSeparator")
    private var splitViewController: NSSplitViewController!

    static func show(appState: AppState, updaterService: UpdaterService) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(appState: appState, updaterService: updaterService)
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(appState: AppState, updaterService: UpdaterService) {
        let navigation = SettingsNavigation()

        // Split view controller
        let splitVC = NSSplitViewController()

        // Sidebar
        let sidebarHosting = NSHostingController(
            rootView: SettingsSidebar(navigation: navigation)
        )
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 240
        sidebarItem.titlebarSeparatorStyle = .none

        // Detail
        let detailHosting = NSHostingController(
            rootView: SettingsDetailContent(navigation: navigation, appState: appState)
                .environment(updaterService)
        )
        detailHosting.safeAreaRegions = []
        let detailItem = NSSplitViewItem(viewController: detailHosting)
        detailItem.titlebarSeparatorStyle = .line

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(detailItem)

        // Window
        let window = NSWindow(contentViewController: splitVC)
        window.title = "OpenWhisper Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 660, height: 480))
        window.center()

        self.splitViewController = splitVC

        super.init(window: window)

        // Toolbar with only a tracking separator — sidebar extends behind traffic lights,
        // detail has no empty header because there are no items after the separator.
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.trackingSeparatorID {
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitViewController.splitView,
                dividerIndex: 0
            )
        }
        return nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.trackingSeparatorID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.trackingSeparatorID]
    }
}

// MARK: - Sidebar (SwiftUI in NSHostingController)

private struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        List(SettingsPage.allCases, selection: $navigation.selectedPage) { page in
            Label(page.title, systemImage: page.icon)
                .tag(page)
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Detail (SwiftUI in NSHostingController)

private struct SettingsDetailContent: View {
    var navigation: SettingsNavigation
    let appState: AppState

    var body: some View {
        Group {
            switch navigation.selectedPage {
            case .general:
                GeneralSettingsTab()
            case .shortcut:
                HotkeySettingsTab()
            case .model:
                ModelSettingsTab()
            case .appearance:
                AppearanceSettingsTab()
            case .audio:
                AudioSettingsTab()
            case .processing:
                PostProcessingSettingsTab()
            case .context:
                ContextModesSettingsTab()
            case .llm:
                LLMSettingsTab()
            case .about:
                AboutSettingsTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .environment(appState)
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

                Picker("App Language", selection: $settings.uiLanguage) {
                    Text("Auto").tag(Constants.SupportedUILanguages.defaultLanguage)
                    Text("English").tag("en")
                    Text("Español").tag("es")
                }

                if OpenWhisperApp.resolveLanguageCode(for: settings.uiLanguage) != OpenWhisperApp.appliedLanguageCode {
                    Text("Restart required to apply language change.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
    @State private var eventMonitor: Any?

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
                    HStack {
                        Text("Press new key combination…")
                            .foregroundStyle(.orange)
                        Button("Cancel") {
                            stopRecordingHotkey()
                        }
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Button("Record New Hotkey") {
                            startRecordingHotkey()
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
        .onDisappear {
            stopRecordingHotkey()
        }
    }

    private func startRecordingHotkey() {
        // Remove any existing monitor first
        stopRecordingHotkey()
        isRecordingHotkey = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !mods.isEmpty && event.keyCode != 0 {
                appState.settings.hotkeyKeyCode = event.keyCode
                appState.settings.hotkeyModifiers = UInt32(mods.rawValue)
                appState.hotkeyService?.updateHotkey(
                    keyCode: event.keyCode,
                    modifiers: UInt32(mods.rawValue)
                )
                stopRecordingHotkey()
            }
            // Only consume the event while actively recording
            return isRecordingHotkey ? nil : event
        }
    }

    private func stopRecordingHotkey() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecordingHotkey = false
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
    private let profile = MachineProfile.current

    var body: some View {
        @Bindable var settings = appState.settings
        let recommendedID = profile.recommendedWhisperModelID(for: settings.selectedLanguage)

        Form {
            ForEach(Constants.SupportedModels.families, id: \.self) { family in
                let familyModels = Constants.SupportedModels.all.filter { $0.family == family }
                Section(family.capitalized) {
                    ForEach(familyModels) { model in
                        WhisperModelRow(
                            model: model,
                            isActive: settings.selectedModel == model.id && appState.isModelLoaded,
                            isCached: appState.modelManager.availableLocalModels.contains(model.id),
                            isRecommended: model.id == recommendedID,
                            isDownloadingThis: appState.isLoadingModel && settings.selectedModel == model.id,
                            downloadProgress: appState.modelLoadProgress
                        ) {
                            settings.selectedModel = model.id
                            Task { await appState.loadTranscriptionEngine() }
                        } onDelete: {
                            appState.deleteWhisperModel(model.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct WhisperModelRow: View {
    let model: Constants.SupportedModels.WhisperModel
    let isActive: Bool
    let isCached: Bool
    let isRecommended: Bool
    let isDownloadingThis: Bool
    let downloadProgress: Double
    let onDownloadOrLoad: () -> Void
    let onDelete: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.displayName)
                            .fontWeight(.medium)
                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Text("\(model.size) — \(model.quality)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDownloadingThis {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(downloadProgress > 0 && downloadProgress < 1
                             ? "\(Int(downloadProgress * 100))%"
                             : "Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        if isCached {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete downloaded model")
                        }
                        if isActive {
                            Button("Loaded") {}
                                .controlSize(.small)
                                .disabled(true)
                        } else if isCached {
                            Button("Load") { onDownloadOrLoad() }
                                .controlSize(.small)
                                .disabled(appState.isLoadingModel)
                        } else {
                            Button("Download") { onDownloadOrLoad() }
                                .controlSize(.small)
                                .disabled(appState.isLoadingModel)
                        }
                    }
                }
            }
            if isDownloadingThis {
                ProgressView(value: downloadProgress > 0 ? downloadProgress : nil)
                    .progressViewStyle(.linear)
            }
        }
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    @Environment(UpdaterService.self) private var updaterService
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

            if updaterService.isEnabled {
                Section("Updates") {
                    Button("Check for Updates…") {
                        updaterService.checkForUpdates()
                    }
                    .disabled(!updaterService.canCheckForUpdates)

                    @Bindable var updater = updaterService
                    Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                }
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

                Text("AEC and noise suppression work together as a unit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Changes take effect on next app launch.")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
        .onChange(of: defaultTone) {
            let config = ContextModeConfig(entries: entries, defaultTone: defaultTone)
            JSONStorageAdapter.save(config, to: "context-modes.json")
            appState.updateLLMConfiguration()
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
                    .tint(.green)

                Text("Uses AI to fix punctuation, apply dictionary corrections, and adjust tone. Results may vary with smaller models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory") {
                LLMMemoryInfoView()
            }

            Section("Models") {
                ForEach(LLMModelManager.recommendedModels) { model in
                    let isActive = llmSettings.selectedLocalModel == model.huggingFaceID
                        && appState.isLLMLoaded
                    let isCached = appState.llmModelManager?.isModelCached(model.huggingFaceID) == true
                    let isRecommended = model.id == MachineProfile.current.recommendedModelID
                    let isDownloadingThis = appState.llmModelManager?.isDownloading == true
                        && appState.llmModelManager?.downloadingModelID == model.huggingFaceID
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(model.name)
                                        .fontWeight(.medium)
                                    if isActive {
                                        Text("Active")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.green.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                    if isRecommended {
                                        Text("Recommended")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                }
                                HStack(spacing: 4) {
                                    Text("\(model.size) — \(model.languages) — \(model.license)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if isRecommended {
                                        Text("~\(MachineProfile.current.estimatedTokensPerSec(modelSizeGB: model.sizeGB)) tok/s")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            Spacer()
                            if isDownloadingThis {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(appState.llmModelManager?.statusMessage ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    if isCached {
                                        Button(role: .destructive) {
                                            deleteModel(model.huggingFaceID)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Delete cached model")
                                    }
                                    if isActive {
                                        Button("Loaded") {}
                                            .controlSize(.small)
                                            .disabled(true)
                                    } else if isCached {
                                        Button("Load") {
                                            guard let mlx = appState.mlxLLMAdapter else { return }
                                            Task {
                                                do {
                                                    try await appState.llmModelManager?.loadCached(model, using: mlx)
                                                    llmSettings.selectedLocalModel = model.huggingFaceID
                                                    appState.isLLMLoaded = true
                                                    appState.updateLLMConfiguration()
                                                } catch {
                                                    appState.errorMessage = "Failed to load model: \(error.localizedDescription)"
                                                }
                                            }
                                        }
                                        .controlSize(.small)
                                        .disabled(appState.llmModelManager?.isDownloading == true)
                                    } else {
                                        Button("Download") {
                                            guard let mlx = appState.mlxLLMAdapter else { return }
                                            Task {
                                                do {
                                                    try await appState.llmModelManager?.download(model, using: mlx)
                                                } catch {
                                                    appState.errorMessage = "Download failed: \(error.localizedDescription)"
                                                }
                                            }
                                        }
                                        .controlSize(.small)
                                        .disabled(appState.llmModelManager?.isDownloading == true)
                                    }
                                }
                            }
                        }
                        if isDownloadingThis {
                            ProgressView(value: appState.llmModelManager?.downloadProgress ?? 0)
                                .progressViewStyle(.linear)
                        }
                    }
                }
            }

            if llmSettings.isEnabled {
                Section("Source") {
                    Picker("Source", selection: $llmSettings.source) {
                        ForEach(LLMSettings.LLMSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: llmSettings.source) {
                        appState.updateLLMConfiguration()
                    }
                }

                if llmSettings.source == .local {
                    Section("Local Model (MLX)") {
                        if appState.isLLMLoaded {
                            Label("Loaded: \(llmSettings.selectedLocalModel.components(separatedBy: "/").last ?? llmSettings.selectedLocalModel)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if !llmSettings.selectedLocalModel.isEmpty {
                            Label("Loading model...", systemImage: "arrow.trianglehead.2.clockwise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("No model selected. Choose one above.", systemImage: "arrow.up.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Text("MLX models run natively on Apple Silicon with Metal acceleration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .onChange(of: llmSettings.remoteBaseURL) { appState.updateLLMConfiguration() }
                    .onChange(of: llmSettings.remoteModelName) { appState.updateLLMConfiguration() }
                    .onChange(of: llmSettings.remoteAPIKey) { appState.updateLLMConfiguration() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func deleteModel(_ huggingFaceID: String) {
        if appState.llmSettings.selectedLocalModel == huggingFaceID {
            appState.mlxLLMAdapter?.unloadModel()
            appState.isLLMLoaded = false
            appState.llmSettings.selectedLocalModel = ""
        }
        try? appState.llmModelManager?.deleteModel(huggingFaceID)
    }
}

// MARK: - LLM Memory Info

private struct LLMMemoryInfoView: View {
    @State private var memoryInfo = MemoryInfo()
    private let profile = MachineProfile.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.summary)
                .font(.caption)
                .fontWeight(.medium)
            HStack {
                Text("System RAM")
                    .font(.caption)
                Spacer()
                Text("\(memoryInfo.totalGB, specifier: "%.0f") GB total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: memoryInfo.usedFraction)
                .tint(memoryInfo.usedFraction > 0.85 ? .red : memoryInfo.usedFraction > 0.7 ? .orange : .blue)

            HStack {
                Text("\(memoryInfo.usedGB, specifier: "%.1f") GB used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(memoryInfo.availableGB, specifier: "%.1f") GB available")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Text("Local models load entirely into memory (GPU via Metal on Apple Silicon). Choose a model that fits comfortably — if available RAM is low, transcription and other apps may slow down.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct MemoryInfo {
    let totalGB: Double
    let usedGB: Double
    let availableGB: Double
    var usedFraction: Double { totalGB > 0 ? usedGB / totalGB : 0 }

    init() {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let pageSize = Double(vm_kernel_page_size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let active = Double(stats.active_count) * pageSize / 1_073_741_824
            let wired = Double(stats.wire_count) * pageSize / 1_073_741_824
            let compressed = Double(stats.compressor_page_count) * pageSize / 1_073_741_824
            let used = active + wired + compressed
            totalGB = total
            usedGB = min(used, total)
            availableGB = max(total - used, 0)
        } else {
            totalGB = total
            usedGB = 0
            availableGB = total
        }
    }
}
