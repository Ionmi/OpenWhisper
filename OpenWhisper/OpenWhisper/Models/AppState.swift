import SwiftUI

@Observable
@MainActor
final class AppState {
    var currentState: RecordingState = .idle
    var lastTranscription: TranscriptionResult?
    var transcriptionHistory: [TranscriptionResult] = []
    var errorMessage: String?
    var isModelLoaded = false
    var isLoadingModel = false
    var modelLoadProgress: Double = 0
    var audioLevel: Float = 0

    /// Live preview text shown in the pill during recording
    var livePreviewText = ""

    let settings = AppSettings()

    // Services
    var audioCaptureService: AudioCaptureService?
    var transcriptionEngine: (any TranscriptionPort)?
    var hotkeyService: HotkeyService?
    var textOutputService: TextOutputService?
    var permissionsManager = PermissionsManager()
    var floatingRecorder: FloatingRecorderController?
    private var isSetUp = false
    private var audioLevelTimer: Timer?

    // Streaming state
    private var streamingTimer: Timer?
    private var streamedText = ""
    private var streamedWordCount = 0
    private var isStreamTranscribing = false
    private var lastStreamedSampleCount = 0

    // MARK: - Recording

    func startRecording() {
        guard currentState == .idle else { return }

        guard let audioCaptureService else {
            errorMessage = "Audio service not initialized. Try restarting the app."
            return
        }

        guard isModelLoaded else {
            errorMessage = "No model loaded. Open Settings to download one."
            return
        }

        do {
            try audioCaptureService.startRecording()
            currentState = .recording
            errorMessage = nil
            streamedText = ""
            streamedWordCount = 0
            livePreviewText = ""
            lastStreamedSampleCount = 0
            hotkeyService?.isActive = true
            floatingRecorder?.show()
            startAudioLevelPolling()
            startStreamingTranscription()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    /// Confirm transcription — do a final transcription pass then paste/copy/save
    func confirmRecording() {
        guard currentState == .recording else { return }
        stopStreamingTranscription()
        stopAudioLevelPolling()
        audioLevel = 0
        hotkeyService?.isActive = false

        let audioSamples = audioCaptureService?.stopRecording() ?? []
        currentState = .transcribing
        livePreviewText = ""
        floatingRecorder?.showConfirmation()

        guard !audioSamples.isEmpty else {
            currentState = .idle
            streamedText = ""
            return
        }

        let language = settings.selectedLanguage

        Task {
            var finalText = streamedText

            // Do one final transcription of the complete audio for best accuracy
            if let engine = transcriptionEngine {
                do {
                    let text = try await engine.transcribe(
                        audioSamples: audioSamples,
                        language: language == "auto" ? nil : language
                    )
                    let cleaned = Self.cleanTranscription(text)
                    if !cleaned.isEmpty {
                        finalText = cleaned
                    }
                } catch {
                    // Fall back to last streamed text
                }
            }

            finalText = Self.cleanTranscription(finalText)

            guard !finalText.isEmpty else {
                streamedText = ""
                currentState = .idle
                return
            }

            // Save to history
            let result = TranscriptionResult(
                text: finalText,
                timestamp: Date(),
                duration: Double(audioSamples.count) / 16000.0
            )
            lastTranscription = result
            transcriptionHistory.insert(result, at: 0)
            if transcriptionHistory.count > 50 {
                transcriptionHistory = Array(transcriptionHistory.prefix(50))
            }

            // Output based on mode
            switch settings.outputMode {
            case .pasteAutomatic:
                textOutputService?.pasteText(finalText)
            case .clipboardOnly:
                textOutputService?.copyToClipboard(finalText)
            case .historyOnly:
                break
            }

            streamedText = ""
            currentState = .idle
        }
    }

    /// ESC pressed → cancel, discard everything
    func cancelRecording() {
        guard currentState == .recording else { return }
        stopStreamingTranscription()
        stopAudioLevelPolling()
        floatingRecorder?.hide()
        audioLevel = 0
        hotkeyService?.isActive = false

        _ = audioCaptureService?.stopRecording()

        streamedText = ""
        livePreviewText = ""
        currentState = .idle
        errorMessage = nil
    }

    // MARK: - Streaming Transcription

    private func startStreamingTranscription() {
        streamingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performStreamTranscription()
            }
        }
    }

    private func stopStreamingTranscription() {
        streamingTimer?.invalidate()
        streamingTimer = nil
        isStreamTranscribing = false
    }

    private func performStreamTranscription() {
        guard currentState == .recording,
              !isStreamTranscribing,
              let engine = transcriptionEngine,
              let audioCaptureService
        else { return }

        let samples = audioCaptureService.currentSamples()
        guard samples.count > 8000, samples.count > lastStreamedSampleCount + 4800 else { return }

        isStreamTranscribing = true
        lastStreamedSampleCount = samples.count
        let language = settings.selectedLanguage

        Task {
            do {
                let text = try await engine.transcribe(
                    audioSamples: samples,
                    language: language == "auto" ? nil : language
                )

                guard currentState == .recording else {
                    isStreamTranscribing = false
                    return
                }

                let cleaned = Self.cleanTranscription(text)
                guard !cleaned.isEmpty else {
                    isStreamTranscribing = false
                    return
                }

                // Always update the full streamed text with the latest transcription
                streamedText = cleaned

                // Update live preview (shown in pill if enabled)
                livePreviewText = cleaned
            } catch {
                // Silently ignore intermediate errors
            }
            isStreamTranscribing = false
        }
    }

    // MARK: - Text Cleaning

    /// Remove Whisper hallucinations like [music], (silence), etc.
    private static func cleanTranscription(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove bracketed/parenthesized non-speech annotations
        // Matches: [Music], [music], (music), [MUSIC], [silence], [applause], etc.
        let pattern = #"\[[^\]]*\]|\([^)]*\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Remove common Whisper hallucination phrases
        let hallucinations = [
            "Thank you for watching.",
            "Thanks for watching.",
            "Thank you.",
            "Subtitles by the Amara.org community",
            "you",
        ]
        for phrase in hallucinations {
            if result.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(phrase) == .orderedSame {
                return ""
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Audio Level

    private func startAudioLevelPolling() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioLevel = self.audioCaptureService?.currentLevel ?? 0
            }
        }
    }

    private func stopAudioLevelPolling() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    // MARK: - Setup

    func setupServices() {
        guard !isSetUp else { return }
        isSetUp = true
        audioCaptureService = AudioCaptureService()
        textOutputService = TextOutputService()
        floatingRecorder = FloatingRecorderController(appState: self)

        let hotkeyService = HotkeyService(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        )
        hotkeyService.shortcutMode = settings.shortcutMode
        hotkeyService.onActivate = { [weak self] in
            // Event tap runs on main run loop — safe to call MainActor synchronously
            MainActor.assumeIsolated {
                self?.startRecording()
            }
        }
        hotkeyService.onConfirm = { [weak self] in
            MainActor.assumeIsolated {
                self?.confirmRecording()
            }
        }
        hotkeyService.onCancel = { [weak self] in
            MainActor.assumeIsolated {
                self?.cancelRecording()
            }
        }
        hotkeyService.onEventTapFailed = { [weak self] in
            MainActor.assumeIsolated {
                self?.errorMessage = "Hotkey not working — grant Accessibility permission in System Settings."
            }
        }
        hotkeyService.onEventTapCreated = { [weak self] in
            MainActor.assumeIsolated {
                if self?.errorMessage?.contains("Accessibility") == true {
                    self?.errorMessage = nil
                }
            }
        }
        hotkeyService.start()
        self.hotkeyService = hotkeyService
    }

    /// Call when shortcut mode changes in settings
    func updateShortcutMode() {
        hotkeyService?.shortcutMode = settings.shortcutMode
    }

    func loadTranscriptionEngine() async {
        guard !isLoadingModel, !isModelLoaded else { return }
        let engine = WhisperKitEngine()
        do {
            isLoadingModel = true
            errorMessage = nil
            try await engine.loadModel(name: settings.selectedModel)
            transcriptionEngine = engine
            isModelLoaded = true
            isLoadingModel = false
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            isLoadingModel = false
        }
    }
}
