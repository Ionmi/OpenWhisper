import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(UpdaterService.self) private var updaterService
    @Environment(\.openWindow) private var openWindow

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            statusSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            // Last transcription
            transcriptionSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // Menu items
            actionsSection
                .padding(.vertical, 4)
                .padding(.bottom, 4)
        }
        .frame(width: 280)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
            Spacer()
            if appState.isLoadingModel {
                ProgressView()
                    .controlSize(.small)
            }
        }

        if let error = appState.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .padding(.top, 2)
        }

        if !appState.isModelLoaded {
            if appState.isLoadingModel {
                Text("Loading \(appState.settings.selectedModel)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                Button {
                    Task {
                        await appState.loadTranscriptionEngine()
                    }
                } label: {
                    Text("Load Model (\(appState.settings.selectedModel))")
                        .font(.subheadline)
                }
                .buttonStyle(.link)
                .padding(.top, 2)
            }
        }

        Text("\(appState.settings.hotkeyDisplayString) to dictate")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.top, 1)
    }

    // MARK: - Transcription

    @ViewBuilder
    private var transcriptionSection: some View {
        if let result = appState.lastTranscription {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Last Transcription")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(result.formattedTimestamp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(result.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.accessoryBar)
                .controlSize(.small)
                .contentTransition(.symbolEffect(.replace))
            }
        } else {
            Text("No transcriptions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        if !appState.settings.onboardingCompleted {
            MenuItemButton("Run Setup…", systemImage: "sparkles") {
                openWindow(id: "onboarding")
            }
            Divider().padding(.horizontal, 8)
        }

        MenuItemButton("Settings…", systemImage: "gearshape") {
            let app = appState
            let updater = updaterService
            NSApp.keyWindow?.close()
            DispatchQueue.main.async {
                SettingsWindowController.show(appState: app, updaterService: updater)
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider().padding(.horizontal, 8)

        MenuItemButton("Quit OpenWhisper", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if !appState.isModelLoaded && appState.currentState == .idle {
            return .gray
        }
        return switch appState.currentState {
        case .idle: .green
        case .recording: .red
        case .transcribing: .orange
        case .processing: .purple
        }
    }

    private var statusText: String {
        if appState.isLoadingModel {
            return "Loading…"
        }
        if !appState.isModelLoaded && appState.currentState == .idle {
            return "No Model"
        }
        return switch appState.currentState {
        case .idle: "Ready"
        case .recording: "Recording…"
        case .transcribing: "Transcribing…"
        case .processing: "Processing…"
        }
    }
}

// MARK: - Menu Item Button (native macOS menu style)

private struct MenuItemButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isHovered ? .white : .secondary)
                Text(title)
                    .foregroundStyle(isHovered ? .white : .primary)
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}

