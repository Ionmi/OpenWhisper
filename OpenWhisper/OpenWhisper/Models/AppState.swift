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
    var isLLMLoaded = false

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
    let modelManager = ModelManager()

    // Services (v2)
    var dictionaryAdapter: (any DictionaryPort)?
    var snippetAdapter: (any SnippetPort)?
    var textProcessor: (any TextProcessingPort)?
    var voiceActivityDetector: (any VoiceActivityPort)?
    var appDetector: (any AppDetectionPort)?
    var llmModelManager: LLMModelManager?
    var mlxLLMAdapter: MLXLLMAdapter?
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
    private var detectedLanguage = ""

    // LLM state
    private var lastLLMInputText = ""

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

        // Show pill immediately for responsiveness, before audio engine starts.
        currentState = .recording
        errorMessage = nil
        streamedText = ""
        streamedWordCount = 0
        livePreviewText = ""
        lastStreamedSampleCount = 0
        detectedLanguage = ""
        lastLLMInputText = ""
        hotkeyService?.isActive = true
        floatingRecorder?.show()

        do {
            try audioCaptureService.startRecording()
            startAudioLevelPolling()
            startStreamingTranscription()
        } catch {
            // Audio failed — revert to idle
            currentState = .idle
            hotkeyService?.isActive = false
            floatingRecorder?.hide()
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

        // Change state immediately so UI updates, but keep audio engine
        // running briefly to flush any pending buffers.
        currentState = .transcribing
        livePreviewText = ""

        let language = settings.selectedLanguage

        Task {
            // Let the audio engine keep recording for a short window so
            // any in-flight buffers are delivered to the tap callback.
            try? await Task.sleep(for: .milliseconds(300))

            let audioSamples = audioCaptureService?.stopRecording() ?? []

            guard !audioSamples.isEmpty else {
                floatingRecorder?.hide()
                streamedText = ""
                currentState = .idle
                return
            }

            defer {
                streamedText = ""
                currentState = .idle
            }

            var finalText = streamedText

            // 1. Filter audio through VAD if enabled
            var processedSamples = audioSamples
            if audioSettings.vadEnabled, let vad = voiceActivityDetector {
                let segments = vad.detectSpeechSegments(in: audioSamples, sampleRate: 16000)
                if !segments.isEmpty {
                    processedSamples = segments.flatMap { Array(audioSamples[$0.start..<min($0.end, audioSamples.count)]) }
                }
            }

            // 2. Pad with trailing silence so Whisper can properly
            //    transcribe the very last words (avoids cut-off).
            let silencePadding = [Float](repeating: 0, count: 4800) // 300ms at 16kHz
            processedSamples += silencePadding

            // 3. Final transcription of the complete audio for best accuracy
            if let engine = transcriptionEngine {
                do {
                    let output = try await engine.transcribe(
                        audioSamples: processedSamples,
                        language: language == "auto" ? nil : language
                    )
                    detectedLanguage = output.detectedLanguage
                    let cleaned = Self.cleanTranscription(output.text)
                    if !cleaned.isEmpty {
                        finalText = cleaned
                    }
                } catch {
                    // Fall back to last streamed text
                }
            }

            finalText = Self.cleanTranscription(finalText)

            guard !finalText.isEmpty else {
                floatingRecorder?.hide()
                return
            }

            // 4. Check snippet match — if exact match, use snippet and skip processing
            if let snippetMatch = snippetAdapter?.match(finalText) {
                finalText = snippetMatch
            } else {
                // 5. Regex processing pipeline (dictionary, fillers, punctuation)
                if let processor = textProcessor {
                    finalText = processor.process(finalText, language: language)
                }
            }

            // 6. LLM refinement — always run on the final transcription text.
            if llmSettings.isEnabled, llmAdapter?.isModelLoaded == true, let llmProcessor {
                lastLLMInputText = ""

                currentState = .processing
                floatingRecorder?.showProcessing()
                let textToRefine = finalText
                let llmLang = detectedLanguage.isEmpty ? language : detectedLanguage
                if let refined = try? await llmProcessor.process(textToRefine, language: llmLang),
                   !refined.isEmpty {
                    finalText = refined
                }
            } else {
                lastLLMInputText = ""
            }

            // 7. Output — show confirmation now that all processing is done
            floatingRecorder?.showConfirmation()
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
        }
    }

    /// ESC pressed → cancel, discard everything
    func cancelRecording() {
        guard currentState == .recording else { return }
        stopStreamingTranscription()
        lastLLMInputText = ""
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
                let output = try await engine.transcribe(
                    audioSamples: samples,
                    language: language == "auto" ? nil : language
                )
                detectedLanguage = output.detectedLanguage

                guard currentState == .recording else {
                    isStreamTranscribing = false
                    return
                }

                let cleaned = Self.cleanTranscription(output.text)
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

        // Use voice processing (AEC + noise suppression) when enabled in settings
        if audioSettings.aecEnabled || audioSettings.noiseSuppressionEnabled {
            audioCaptureService = VoiceProcessingAudioCapture()
        } else {
            audioCaptureService = AudioCaptureService()
        }

        textOutputService = TextOutputService()
        floatingRecorder = FloatingRecorderController(appState: self)

        // v2 services
        let dictionary = JSONDictionaryAdapter()
        dictionaryAdapter = dictionary
        snippetAdapter = JSONSnippetAdapter()
        textProcessor = RegexTextProcessor(dictionaryAdapter: dictionary)

        let vad = EnergyVADAdapter()
        try? vad.loadModel()
        voiceActivityDetector = vad

        let detector = NSWorkspaceAppDetector()
        appDetector = detector
        llmModelManager = LLMModelManager()

        // LLM adapters (both created, active one chosen by settings)
        let mlx = MLXLLMAdapter()
        mlxLLMAdapter = mlx
        let remote = RemoteLLMAdapter(
            baseURL: llmSettings.remoteBaseURL,
            apiKey: llmSettings.remoteAPIKey,
            modelName: llmSettings.remoteModelName
        )
        remoteLLMAdapter = remote

        // Select active adapter based on settings
        let activeAdapter: any LLMPort = llmSettings.source == .remote ? remote : mlx
        llmAdapter = activeAdapter

        // Load context modes from saved config (or use defaults)
        let contextConfig = JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default

        llmProcessor = LLMTextProcessor(
            llm: activeAdapter,
            appDetector: detector,
            contextConfig: contextConfig,
            dictionaryAdapter: dictionary
        )

        // Auto-select model: prefer already cached, then recommended
        if llmSettings.selectedLocalModel.isEmpty || llmModelManager?.isModelCached(llmSettings.selectedLocalModel) == false {
            // Try to find a cached model
            if let cached = LLMModelManager.recommendedModels.first(where: { llmModelManager?.isModelCached($0.huggingFaceID) == true }) {
                llmSettings.selectedLocalModel = cached.huggingFaceID
            } else if llmSettings.selectedLocalModel.isEmpty {
                // Nothing cached — set recommended as default (will download on first use)
                let recommended = MachineProfile.current.recommendedModelID
                if let model = LLMModelManager.recommendedModels.first(where: { $0.id == recommended }) {
                    llmSettings.selectedLocalModel = model.huggingFaceID
                }
            }
        }

        // Auto-load cached MLX model on startup when LLM is enabled

        if llmSettings.isEnabled,
           llmSettings.source == .local,
           !llmSettings.selectedLocalModel.isEmpty,
           llmModelManager?.isModelCached(llmSettings.selectedLocalModel) == true {
            let modelID = llmSettings.selectedLocalModel
            let tone = (JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default).defaultTone
            Task { @MainActor in
                do {
                    try await mlx.loadModel(huggingFaceID: modelID, progressHandler: nil)
                    self.isLLMLoaded = true
                    let warmUpPrompt = LLMTextProcessor.buildSystemPrompt(tone: tone)
                    await mlx.warmUp(systemPrompt: warmUpPrompt)
                } catch {
                    self.isLLMLoaded = false
                    self.errorMessage = "Failed to load LLM model: \(error.localizedDescription)"
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
        let activeAdapter: (any LLMPort)?
        if llmSettings.source == .remote {
            activeAdapter = remoteLLMAdapter ?? mlxLLMAdapter
        } else {
            activeAdapter = mlxLLMAdapter
        }
        guard let activeAdapter else { return }
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

    /// Load a local LLM model by HuggingFace ID
    func loadLocalLLMModel(_ huggingFaceID: String) async {
        guard let mlx = mlxLLMAdapter else { return }
        isLLMLoaded = false
        do {
            try await mlx.loadModel(huggingFaceID: huggingFaceID, progressHandler: nil)
            llmSettings.selectedLocalModel = huggingFaceID
            isLLMLoaded = true
            updateLLMConfiguration()
            let tone = (JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default).defaultTone
            let warmUpPrompt = LLMTextProcessor.buildSystemPrompt(tone: tone)
            await mlx.warmUp(systemPrompt: warmUpPrompt)
        } catch {
            errorMessage = "Failed to load LLM: \(error.localizedDescription)"
        }
    }

    func loadTranscriptionEngine() async {
        guard !isLoadingModel else { return }
        let modelID = settings.selectedModel
        let totalBytes = (Constants.SupportedModels.all.first { $0.id == modelID }?.sizeGB ?? 1.0) * 1_000_000_000
        var downloadedBytes = 0.0
        var lastCallbackTime: Date?

        let engine = WhisperKitEngine()
        do {
            isModelLoaded = false
            isLoadingModel = true
            modelLoadProgress = 0
            errorMessage = nil
            try await engine.loadModel(name: modelID) { [weak self] _, speed in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let now = Date()
                    if let last = lastCallbackTime, let speed, speed > 0 {
                        downloadedBytes += speed * now.timeIntervalSince(last)
                        downloadedBytes = min(downloadedBytes, totalBytes)
                    }
                    if let speed, speed > 0 { lastCallbackTime = now }
                    self.modelLoadProgress = downloadedBytes / totalBytes
                }
            }
            transcriptionEngine = engine
            isModelLoaded = true
            modelLoadProgress = 1
            modelManager.refreshLocalModels()
            isLoadingModel = false
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            isLoadingModel = false
            modelLoadProgress = 0
        }
    }

    func deleteWhisperModel(_ modelID: String) {
        if settings.selectedModel == modelID {
            isModelLoaded = false
        }
        try? modelManager.deleteModel(modelID)
    }
}
