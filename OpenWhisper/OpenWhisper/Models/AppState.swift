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
    var loadedModelID: String?
    var hasSelectedModelLoaded: Bool {
        isModelLoaded && loadedModelID == settings.selectedModel
    }
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

    // Whisper download byte-tracking (mirrors LLMModelManager pattern)
    private var whisperDownloadedBytes: Double = 0
    private var whisperLastCallbackTime: Date?

    // Streaming state
    private var streamingTask: Task<Void, Never>?
    private let streamingManager = StreamingTranscriptionManager()

    // LLM state
    private var lastLLMInputText = ""

    // MARK: - Recording

    func startRecording() {
        guard currentState == .idle else { return }

        permissionsManager.checkMicrophonePermission()
        guard permissionsManager.hasMicrophonePermission else {
            errorMessage = "Microphone permission is required to start recording. Grant access in Settings."
            return
        }

        guard let audioCaptureService else {
            errorMessage = "Audio service not initialized. Try restarting the app."
            return
        }

        guard hasSelectedModelLoaded else {
            errorMessage = "No model loaded for the selected model. Open Settings to download or load it."
            return
        }

        // Show pill immediately for responsiveness
        currentState = .recording
        errorMessage = nil
        streamingManager.reset()
        livePreviewText = ""
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

    /// Confirm transcription — final pass on unconfirmed tail, then paste/copy/save
    func confirmRecording() {
        guard currentState == .recording else { return }
        stopStreamingTranscription()
        stopAudioLevelPolling()
        audioLevel = 0
        hotkeyService?.isActive = false

        currentState = .transcribing
        livePreviewText = ""
        floatingRecorder?.showTranscribing()

        let language = settings.selectedLanguage

        Task {
            // Flush in-flight audio buffers (tap delivers at ~256-4096 sample intervals)
            try? await Task.sleep(for: .milliseconds(300))

            let recordedAudioSamples = audioCaptureService?.stopRecording() ?? []

            guard !recordedAudioSamples.isEmpty else {
                floatingRecorder?.hide()
                streamingManager.reset()
                currentState = .idle
                return
            }

            let audioSamples = transcriptionSamples(from: recordedAudioSamples)
            guard !audioSamples.isEmpty else {
                floatingRecorder?.hide()
                return
            }

            defer {
                streamingManager.reset()
                currentState = .idle
            }

            // Final pass: transcribe full audio with clipTimestamps from the agreed anchor.
            var lastOutput: TranscriptionOutput? = nil

            if let engine = transcriptionEngine {
                lastOutput = try? await engine.transcribe(
                    audioSamples: audioSamples,
                    language: language == "auto" ? nil : language,
                    clipTimestamps: [streamingManager.clipTimestamp],
                    prefixTokens: streamingManager.prefixTokens.isEmpty ? nil : streamingManager.prefixTokens
                )
            }

            streamingManager.finalize(lastOutput: lastOutput)

            var finalText = AppState.cleanTranscription(streamingManager.confirmedText)

            guard !finalText.isEmpty else {
                floatingRecorder?.hide()
                return
            }

            // Post-processing pipeline
            if let snippetMatch = snippetAdapter?.match(finalText) {
                finalText = snippetMatch
            } else if let processor = textProcessor {
                finalText = processor.process(finalText, language: language)
            }

            // LLM refinement
            let detLang = streamingManager.detectedLanguage
            if llmSettings.isEnabled, llmAdapter?.isModelLoaded == true, let llmProcessor {
                lastLLMInputText = ""
                currentState = .processing
                floatingRecorder?.showProcessing()
                let llmLang = detLang.isEmpty ? language : detLang
                if let refined = try? await llmProcessor.process(finalText, language: llmLang),
                   !refined.isEmpty {
                    finalText = refined
                }
            } else {
                lastLLMInputText = ""
            }

            // Output
            floatingRecorder?.showConfirmation()
            let result = TranscriptionResult(
                text: finalText,
                timestamp: Date(),
                duration: Double(recordedAudioSamples.count) / 16000.0
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

        streamingManager.reset()
        livePreviewText = ""
        currentState = .idle
        errorMessage = nil
    }

    // MARK: - Streaming Transcription

    private func startStreamingTranscription() {
        streamingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performStreamTranscription()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func stopStreamingTranscription() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func performStreamTranscription() async {
        guard currentState == .recording,
              let engine = transcriptionEngine,
              let audioCaptureService
        else { return }

        let samples = transcriptionSamples(from: audioCaptureService.currentSamples())
        guard samples.count > 8000 else { return }

        let language = settings.selectedLanguage

        do {
            let output = try await engine.transcribe(
                audioSamples: samples,
                language: language == "auto" ? nil : language,
                clipTimestamps: [streamingManager.clipTimestamp],
                prefixTokens: streamingManager.prefixTokens.isEmpty ? nil : streamingManager.prefixTokens
            )
            guard currentState == .recording else { return }

            streamingManager.process(output: output)

            let preview = streamingManager.currentText
            if livePreviewText != preview {
                livePreviewText = preview
            }
        } catch {
            // Silently ignore intermediate errors
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

        // Remove consecutive repeated n-grams (Whisper hallucination artifact).
        // Handles "llamado llamado", "tiene más tiene más", etc.
        result = removeConsecutiveRepeats(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects and removes consecutively repeated word sequences (1–4 word n-grams).
    private static func removeConsecutiveRepeats(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 2 else { return text }

        var cleaned: [String] = []
        var i = 0
        while i < words.count {
            var matched = false
            // Try n-gram sizes from 4 down to 1
            for n in stride(from: min(4, (words.count - i) / 2), through: 1, by: -1) {
                let end = i + n
                let repeatEnd = end + n
                guard repeatEnd <= words.count else { continue }

                let gram = words[i..<end].map { $0.lowercased() }
                let next = words[end..<repeatEnd].map { $0.lowercased() }

                if gram == next {
                    // Keep the first occurrence, skip the duplicate
                    cleaned.append(contentsOf: words[i..<end])
                    i = repeatEnd
                    matched = true
                    break
                }
            }
            if !matched {
                cleaned.append(words[i])
                i += 1
            }
        }

        return cleaned.joined(separator: " ")
    }

    private func transcriptionSamples(from samples: [Float]) -> [Float] {
        guard audioSettings.vadEnabled,
              let voiceActivityDetector
        else { return samples }

        let segments = voiceActivityDetector.detectSpeechSegments(in: samples, sampleRate: 16_000)
        guard !segments.isEmpty else {
            return []
        }

        var filteredSamples: [Float] = []
        filteredSamples.reserveCapacity(
            segments.reduce(into: 0) { partialResult, segment in
                partialResult += max(0, min(samples.count, segment.end) - max(0, segment.start))
            }
        )

        for segment in segments {
            let startIndex = max(0, segment.start)
            let endIndex = min(samples.count, segment.end)
            guard startIndex < endIndex else { continue }
            filteredSamples.append(contentsOf: samples[startIndex..<endIndex])
        }

        return filteredSamples
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
        let requestedModelID = settings.selectedModel
        let totalBytes = (Constants.SupportedModels.all.first { $0.id == requestedModelID }?.sizeGB ?? 1.0) * 1_000_000_000

        let engine = WhisperKitEngine()
        do {
            isModelLoaded = false
            isLoadingModel = true
            loadedModelID = nil
            transcriptionEngine = nil
            modelLoadProgress = 0
            whisperDownloadedBytes = 0
            whisperLastCallbackTime = nil
            errorMessage = nil
            try await engine.loadModel(name: requestedModelID) { [weak self] _, speed in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let now = Date()
                    if let last = self.whisperLastCallbackTime, let speed, speed > 0 {
                        self.whisperDownloadedBytes += speed * now.timeIntervalSince(last)
                        self.whisperDownloadedBytes = min(self.whisperDownloadedBytes, totalBytes)
                    }
                    if let speed, speed > 0 { self.whisperLastCallbackTime = now }
                    self.modelLoadProgress = self.whisperDownloadedBytes / totalBytes
                }
            }

            guard settings.selectedModel == requestedModelID else {
                isLoadingModel = false
                modelLoadProgress = 0
                errorMessage = "Model selection changed while loading. Load the newly selected model to continue."
                return
            }

            transcriptionEngine = engine
            loadedModelID = requestedModelID
            isModelLoaded = true
            modelLoadProgress = 1
            modelManager.refreshLocalModels()
            isLoadingModel = false
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            loadedModelID = nil
            isLoadingModel = false
            modelLoadProgress = 0
        }
    }

    func deleteWhisperModel(_ modelID: String) {
        if loadedModelID == modelID {
            isModelLoaded = false
            loadedModelID = nil
            transcriptionEngine = nil
        }
        try? modelManager.deleteModel(modelID)
    }
}
