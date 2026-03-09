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
    let audioSettings = AudioSettings()
    let llmSettings = LLMSettings()

    // Services (existing)
    var audioCaptureService: (any AudioCapturePort)?
    var transcriptionEngine: (any TranscriptionPort)?
    var hotkeyService: HotkeyService?
    var textOutputService: TextOutputService?
    var permissionsManager = PermissionsManager()
    var floatingRecorder: FloatingRecorderController?

    // Services (v2)
    var dictionaryAdapter: (any DictionaryPort)?
    var snippetAdapter: (any SnippetPort)?
    var textProcessor: (any TextProcessingPort)?
    var voiceActivityDetector: (any VoiceActivityPort)?
    var appDetector: (any AppDetectionPort)?
    var llmModelManager: LLMModelManager?
    var localLLMAdapter: LocalLLMAdapter?
    var remoteLLMAdapter: RemoteLLMAdapter?
    var llmAdapter: (any LLMPort)?
    var llmProcessor: LLMTextProcessor?
    var autoDictionaryService: AutoDictionaryService?

    private var isSetUp = false
    private var audioLevelTimer: Timer?

    // Streaming state
    private var streamingTimer: Timer?
    private var streamedText = ""
    private var streamedWordCount = 0
    private var isStreamTranscribing = false
    private var lastStreamedSampleCount = 0

    // Progressive LLM state
    private var progressiveLLMTask: Task<Void, Never>?
    private var lastLLMInputText = ""
    private var progressiveRefinedText = ""
    private var isProgressiveLLMRunning = false

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
            lastLLMInputText = ""
            progressiveRefinedText = ""
            startProgressiveLLM()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    /// Confirm transcription — do a final transcription pass then paste/copy/save
    func confirmRecording() {
        guard currentState == .recording else { return }
        stopStreamingTranscription()
        stopProgressiveLLM()
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

            // 1. Filter audio through VAD if enabled
            var processedSamples = audioSamples
            if audioSettings.vadEnabled, let vad = voiceActivityDetector {
                let segments = vad.detectSpeechSegments(in: audioSamples, sampleRate: 16000)
                if !segments.isEmpty {
                    processedSamples = segments.flatMap { Array(audioSamples[$0.start..<min($0.end, audioSamples.count)]) }
                }
            }

            // 2. Final transcription of the complete audio for best accuracy
            if let engine = transcriptionEngine {
                do {
                    let text = try await engine.transcribe(
                        audioSamples: processedSamples,
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

            // 3. Check snippet match — if exact match, use snippet and skip processing
            if let snippetMatch = snippetAdapter?.match(finalText) {
                finalText = snippetMatch
            } else {
                // 4. Regex processing pipeline (dictionary, fillers, punctuation)
                if let processor = textProcessor {
                    finalText = processor.process(finalText, language: language)
                }
            }

            // 5. Output immediately — don't wait for LLM
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

            switch settings.outputMode {
            case .pasteAutomatic:
                textOutputService?.pasteText(finalText)
            case .clipboardOnly:
                textOutputService?.copyToClipboard(finalText)
            case .historyOnly:
                break
            }

            autoDictionaryService?.startMonitoring(transcribedText: finalText)

            streamedText = ""
            currentState = .idle

            // 6. LLM refinement — use progressive result if available, otherwise background
            if let llmProcessor, llmSettings.isEnabled, llmAdapter?.isModelLoaded == true {
                let textToRefine = finalText
                let lang = language
                let outputMode = settings.outputMode

                let progressiveResult = progressiveRefinedText
                lastLLMInputText = ""
                progressiveRefinedText = ""

                if !progressiveResult.isEmpty, progressiveResult != textToRefine {
                    // Pre-computed result ready — apply immediately
                    applyRefinedText(original: textToRefine, refined: progressiveResult, result: result, outputMode: outputMode)
                } else {
                    // Run one final LLM pass in background
                    Task.detached { [weak self] in
                        guard let self,
                              let refined = try? await llmProcessor.process(textToRefine, language: lang),
                              !refined.isEmpty, refined != textToRefine
                        else { return }
                        await MainActor.run { [self] in
                            self.applyRefinedText(original: textToRefine, refined: refined, result: result, outputMode: outputMode)
                        }
                    }
                }
            }
        }
    }

    /// ESC pressed → cancel, discard everything
    func cancelRecording() {
        guard currentState == .recording else { return }
        stopStreamingTranscription()
        stopProgressiveLLM()
        lastLLMInputText = ""
        progressiveRefinedText = ""
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

    // MARK: - Progressive LLM

    private func startProgressiveLLM() {
        guard llmSettings.isEnabled, llmAdapter?.isModelLoaded == true, let llmProcessor else { return }

        progressiveLLMTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                guard let self else { return }

                let currentText = self.streamedText
                let language = self.settings.selectedLanguage

                guard !currentText.isEmpty,
                      currentText.count > 10,
                      currentText != self.lastLLMInputText,
                      !self.isProgressiveLLMRunning
                else { continue }

                self.isProgressiveLLMRunning = true
                self.lastLLMInputText = currentText

                let refined = try? await llmProcessor.process(currentText, language: language)
                guard !Task.isCancelled else { return }

                if let refined, !refined.isEmpty, refined != currentText {
                    self.progressiveRefinedText = refined
                }
                self.isProgressiveLLMRunning = false
            }
        }
    }

    private func stopProgressiveLLM() {
        progressiveLLMTask?.cancel()
        progressiveLLMTask = nil
        isProgressiveLLMRunning = false
    }

    private func applyRefinedText(original: String, refined: String, result: TranscriptionResult, outputMode: Constants.OutputMode) {
        if lastTranscription?.text == original {
            lastTranscription = TranscriptionResult(text: refined, timestamp: result.timestamp, duration: result.duration)
        }
        if let idx = transcriptionHistory.firstIndex(where: { $0.text == original }) {
            transcriptionHistory[idx] = TranscriptionResult(text: refined, timestamp: result.timestamp, duration: result.duration)
        }
        switch outputMode {
        case .pasteAutomatic:
            textOutputService?.replaceText(old: original, with: refined)
        case .clipboardOnly:
            textOutputService?.copyToClipboard(refined)
        case .historyOnly:
            break
        }
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

        // Audio capture: always use standard capture (reliable).
        // Voice processing (AEC + noise suppression) is experimental and disabled for now.
        audioCaptureService = AudioCaptureService()

        textOutputService = TextOutputService()
        floatingRecorder = FloatingRecorderController(appState: self)

        // v2 services
        let dictionary = JSONDictionaryAdapter()
        dictionaryAdapter = dictionary
        snippetAdapter = JSONSnippetAdapter()
        textProcessor = RegexTextProcessor(dictionaryAdapter: dictionary)

        let vad = SileroVADAdapter()
        try? vad.loadModel()
        voiceActivityDetector = vad

        let detector = NSWorkspaceAppDetector()
        appDetector = detector
        llmModelManager = LLMModelManager()

        // LLM adapters (both created, active one chosen by settings)
        let local = LocalLLMAdapter()
        localLLMAdapter = local
        let remote = RemoteLLMAdapter(
            baseURL: llmSettings.remoteBaseURL,
            apiKey: llmSettings.remoteAPIKey,
            modelName: llmSettings.remoteModelName
        )
        remoteLLMAdapter = remote

        // Select active adapter based on settings
        let activeAdapter: any LLMPort = llmSettings.source == .remote ? remote : local
        llmAdapter = activeAdapter

        // Load context modes from saved config (or use defaults)
        let contextConfig = JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default

        llmProcessor = LLMTextProcessor(
            llm: activeAdapter,
            appDetector: detector,
            contextConfig: contextConfig,
            dictionaryAdapter: dictionary
        )

        // Auto-load local LLM model if one is selected
        if llmSettings.source == .local, !llmSettings.selectedLocalModel.isEmpty {
            let modelPath = LLMModelManager.modelsDirectory.appendingPathComponent(llmSettings.selectedLocalModel)
            if FileManager.default.fileExists(atPath: modelPath.path) {
                let lang = settings.selectedLanguage
                let tone = (JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default).defaultTone
                Task {
                    try? await local.loadModel(name: llmSettings.selectedLocalModel, path: modelPath)
                    let warmUpPrompt = LLMTextProcessor.buildSystemPrompt(language: lang, tone: tone, dictionaryTerms: "")
                    await local.warmUp(systemPrompt: warmUpPrompt)
                }
            }
        }

        let autoDict = AutoDictionaryService()
        autoDict.configure(dictionaryAdapter: dictionary)
        autoDictionaryService = autoDict

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

    /// Call when LLM settings change (source, model, remote config)
    func updateLLMConfiguration() {
        guard let dictionary = dictionaryAdapter,
              let detector = appDetector
        else { return }

        // Update remote adapter config
        remoteLLMAdapter?.configure(
            baseURL: llmSettings.remoteBaseURL,
            apiKey: llmSettings.remoteAPIKey,
            modelName: llmSettings.remoteModelName
        )

        // Switch active adapter
        let activeAdapter: any LLMPort
        if llmSettings.source == .remote {
            activeAdapter = remoteLLMAdapter ?? localLLMAdapter!
        } else {
            activeAdapter = localLLMAdapter!
        }
        llmAdapter = activeAdapter

        // Rebuild processor with current context config
        let contextConfig = JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default
        llmProcessor = LLMTextProcessor(
            llm: activeAdapter,
            appDetector: detector,
            contextConfig: contextConfig,
            dictionaryAdapter: dictionary
        )
    }

    /// Load a local LLM model by filename
    func loadLocalLLMModel(_ filename: String) async {
        guard let local = localLLMAdapter else { return }
        let modelPath = LLMModelManager.modelsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: modelPath.path) else { return }
        do {
            try await local.loadModel(name: filename, path: modelPath)
            llmSettings.selectedLocalModel = filename
            updateLLMConfiguration()
            // Pre-warm KV cache
            let language = settings.selectedLanguage
            let tone = (JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default).defaultTone
            let warmUpPrompt = LLMTextProcessor.buildSystemPrompt(language: language, tone: tone, dictionaryTerms: "")
            await local.warmUp(systemPrompt: warmUpPrompt)
        } catch {
            errorMessage = "Failed to load LLM: \(error.localizedDescription)"
        }
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
