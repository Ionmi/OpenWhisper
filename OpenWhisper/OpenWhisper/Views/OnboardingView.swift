import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: modelStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation bar
            HStack {
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                }
            }
            .padding()
        }
        .frame(width: 540, height: 480)
    }

    private var canContinue: Bool {
        switch currentStep {
        case 1:
            return appState.permissionsManager.hasMicrophonePermission
        case 2:
            return appState.isModelLoaded
        default:
            return true
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to OpenWhisper")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("A local voice transcription tool that lives in your menu bar.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "mic.fill", text: "Press a hotkey to start voice dictation")
                featureRow(icon: "cpu", text: "Transcription runs locally on your Mac — nothing leaves your device")
                featureRow(icon: "doc.on.clipboard", text: "Text is pasted at your cursor automatically")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 24)

            Text("Permissions")
                .font(.title)
                .fontWeight(.bold)

            Text("OpenWhisper needs two permissions to work.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                permissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture your voice for transcription.",
                    isGranted: appState.permissionsManager.hasMicrophonePermission
                ) {
                    Task {
                        await appState.permissionsManager.requestMicrophonePermission()
                    }
                }

                permissionCard(
                    icon: "universalaccess",
                    title: "Accessibility",
                    description: "Required for the global hotkey and pasting text.",
                    isGranted: appState.permissionsManager.hasAccessibilityPermission
                ) {
                    appState.permissionsManager.requestAccessibilityPermission()
                }
            }

            if !appState.permissionsManager.hasAccessibilityPermission {
                Text("Tap Grant to open System Settings. Add OpenWhisper to the Accessibility list, then come back — this page updates automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            appState.permissionsManager.checkAllPermissions()
        }
        .task(id: currentStep) {
            // Poll accessibility permission while on this step
            guard currentStep == 1 else { return }
            while !Task.isCancelled {
                appState.permissionsManager.checkAccessibilityPermission()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Step 3: Model Download

    private var modelStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 24)

            Text("Download a Model")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose a speech recognition model. This is a one-time download stored locally on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            @Bindable var settings = appState.settings

            // Model picker — compact dropdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.headline)

                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(Constants.SupportedModels.all, id: \.self) { model in
                        if let info = Constants.SupportedModels.descriptions[model] {
                            Text("\(model)  (\(info.size) — \(info.quality))").tag(model)
                        } else {
                            Text(model).tag(model)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if let info = Constants.SupportedModels.descriptions[settings.selectedModel] {
                    Text("\(info.size) — \(info.quality)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Language picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.headline)

                Picker("Language", selection: $settings.selectedLanguage) {
                    ForEach(Constants.SupportedLanguages.all, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if settings.selectedModel.hasSuffix(".en") && settings.selectedLanguage != "en" {
                    Text("English-only models ignore the language setting and always transcribe in English.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Download action / status
            if appState.isLoadingModel {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading & loading model…")
                        .foregroundStyle(.secondary)
                }
            } else if appState.isModelLoaded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Model ready!")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download & Load") {
                    Task {
                        await appState.loadTranscriptionEngine()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("OpenWhisper is ready to use.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                instructionRow(
                    step: "1",
                    text: "Press **\(appState.settings.hotkeyDisplayString)** to start dictation"
                )
                instructionRow(
                    step: "2",
                    text: "Speak — text appears in real time at your cursor"
                )
                instructionRow(
                    step: "3",
                    text: "Press **Enter** to confirm or **ESC** to cancel"
                )
            }
            .padding(.top, 4)

            Text("Look for the waveform icon in your menu bar to check status or change settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Get Started") {
                appState.settings.onboardingCompleted = true
                appState.setupServices()
                dismissWindow(id: "onboarding")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Circle())
            Text(.init(text))
                .font(.body)
        }
    }
}
