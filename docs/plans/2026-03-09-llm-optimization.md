# LLM Optimization: Progressive Processing & Smart Recommendations

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make LLM text refinement feel instant by processing during recording (not after), pre-warming the model, and recommending the right model based on the user's hardware.

**Architecture:** Three changes: (1) A `MachineProfile` utility that detects chip, GPU cores, RAM, and bandwidth tier to recommend models. (2) Pre-warm the LLM with the system prompt on model load so KV cache is hot. (3) Progressive LLM — run refinement on streaming transcription during recording so the result is ready before the user stops.

**Tech Stack:** Swift, SwiftLlama (llama.cpp), macOS sysctl/IOKit APIs

---

### Task 1: MachineProfile — Hardware Detection

**Files:**
- Create: `OpenWhisper/OpenWhisper/Services/MachineProfile.swift`

**Step 1: Create MachineProfile**

This struct detects the Mac's hardware and recommends the best LLM model.

```swift
import Foundation
import IOKit

struct MachineProfile: Sendable {
    let chipName: String          // "Apple M2 Pro"
    let gpuCoreCount: Int         // 19
    let cpuCoreCount: Int         // 12
    let totalRAMGB: Double        // 32.0
    let bandwidthTier: BandwidthTier

    enum BandwidthTier: Comparable, Sendable {
        case low       // ≤68 GB/s  (M1 base)
        case medium    // ~100 GB/s (M2/M3/M4 base)
        case high      // ~150-200 GB/s (Pro chips)
        case veryHigh  // ~273+ GB/s (M4 Pro, Max, Ultra)
    }

    static let current = MachineProfile()

    init() {
        // Chip name via sysctl
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        chipName = String(cString: brand)

        // CPU cores
        cpuCoreCount = ProcessInfo.processInfo.processorCount

        // RAM
        totalRAMGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        // GPU cores via IOKit
        gpuCoreCount = Self.detectGPUCores()

        // Bandwidth tier from chip name
        bandwidthTier = Self.classifyBandwidth(chip: chipName)
    }

    /// Recommend the best model ID from LLMModelManager.recommendedModels
    var recommendedModelID: String {
        // Not enough RAM for any model
        if totalRAMGB < 8 { return "gemma3n-e2b" }

        switch bandwidthTier {
        case .low:
            // M1 base — small model only
            return "gemma3n-e2b"
        case .medium:
            // M2/M3/M4 base — 2B is fast enough
            return totalRAMGB >= 16 ? "qwen3.5-2b" : "gemma3n-e2b"
        case .high:
            // Pro chips — 4B runs well
            return totalRAMGB >= 16 ? "qwen3.5-4b" : "qwen3.5-2b"
        case .veryHigh:
            // M4 Pro, Max, Ultra — 4B flies
            return "qwen3.5-4b"
        }
    }

    /// Human-readable hardware summary for the UI
    var summary: String {
        "\(chipName) · \(gpuCoreCount) GPU cores · \(Int(totalRAMGB)) GB RAM"
    }

    /// Estimated tokens/sec for a given model size in GB
    func estimatedTokensPerSec(modelSizeGB: Double) -> Int {
        let bandwidthGBs: Double = switch bandwidthTier {
        case .low: 68
        case .medium: 100
        case .high: 200
        case .veryHigh: 400
        }
        guard modelSizeGB > 0 else { return 0 }
        return Int(bandwidthGBs / modelSizeGB)
    }

    // MARK: - Private

    private static func detectGPUCores() -> Int {
        let matching = IOServiceMatching("AGXAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }

        if let prop = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0) {
            return (prop.takeRetainedValue() as? NSNumber)?.intValue ?? 0
        }
        return 0
    }

    private static func classifyBandwidth(chip: String) -> BandwidthTier {
        let lower = chip.lowercased()

        // Ultra chips
        if lower.contains("ultra") { return .veryHigh }

        // Max chips
        if lower.contains("max") { return .veryHigh }

        // M4 Pro or newer Pro (M4 Pro = 273 GB/s)
        if lower.contains("m4") && lower.contains("pro") { return .veryHigh }

        // M5+ Pro
        if let gen = extractGeneration(lower), gen >= 5, lower.contains("pro") { return .veryHigh }

        // M1/M2/M3 Pro (200 GB/s range)
        if lower.contains("pro") { return .high }

        // M4 base (120 GB/s) — better than M2/M3 base
        if lower.contains("m4") { return .medium }

        // M5+ base — assume at least medium
        if let gen = extractGeneration(lower), gen >= 5 { return .medium }

        // M2/M3 base (100 GB/s)
        if lower.contains("m2") || lower.contains("m3") { return .medium }

        // M1 base (68 GB/s)
        if lower.contains("m1") { return .low }

        // Unknown / Intel — assume low
        return .low
    }

    private static func extractGeneration(_ chip: String) -> Int? {
        // Match "m4", "m5", "m12" etc.
        guard let range = chip.range(of: #"m(\d+)"#, options: .regularExpression) else { return nil }
        let match = chip[range]
        guard let numRange = match.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(match[numRange])
    }
}
```

**Step 2: Commit**

```bash
git add OpenWhisper/OpenWhisper/Services/MachineProfile.swift
git commit -m "feat: add MachineProfile for hardware detection and model recommendation"
```

---

### Task 2: Pre-warm LLM on Model Load

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Adapters/LLM/LocalLLMAdapter.swift`
- Modify: `OpenWhisper/OpenWhisper/Ports/LLMPort.swift`

**Step 1: Add `warmUp` method to LLMPort**

```swift
protocol LLMPort: Sendable {
    func loadModel(name: String, path: URL) async throws
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
    func warmUp(systemPrompt: String) async  // NEW — pre-populate KV cache
    var isModelLoaded: Bool { get }
    func unloadModel()
}
```

**Step 2: Implement warmUp in LocalLLMAdapter**

In `LocalLLMAdapter.swift`, add the warmUp method. Also reduce `maxTokenCount` from 2048 to 512 since our transcriptions are short:

```swift
func loadModel(name: String, path: URL) async throws {
    lock.lock()
    _isModelLoaded = false
    llamaService = nil
    lock.unlock()

    let service = LlamaService(
        modelUrl: path,
        config: .init(batchSize: 512, maxTokenCount: 512, useGPU: true)
    )

    lock.lock()
    llamaService = service
    _isModelLoaded = true
    lock.unlock()
}

/// Pre-warm the KV cache with the system prompt so first real call is fast.
func warmUp(systemPrompt: String) async {
    lock.lock()
    let service = llamaService
    lock.unlock()

    guard let service else { return }

    // Generate with a trivial user prompt — the system prompt tokens get cached.
    // The response is discarded; we only care about populating the KV cache.
    _ = try? await service.respond(
        to: [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: "test"),
        ],
        samplingConfig: .init(temperature: 0.1, seed: 42)
    )
}
```

**Step 3: Add default warmUp to RemoteLLMAdapter**

```swift
// In RemoteLLMAdapter.swift — no-op, remote doesn't need warm-up
func warmUp(systemPrompt: String) async {
    // No-op for remote APIs
}
```

**Step 4: Trigger warm-up after model load in AppState.setupServices()**

In `AppState.swift`, after the LLM model is loaded, trigger warm-up:

```swift
// Auto-load local LLM model if one is selected
if llmSettings.source == .local, !llmSettings.selectedLocalModel.isEmpty {
    let modelPath = LLMModelManager.modelsDirectory.appendingPathComponent(llmSettings.selectedLocalModel)
    if FileManager.default.fileExists(atPath: modelPath.path) {
        Task {
            try? await local.loadModel(name: llmSettings.selectedLocalModel, path: modelPath)
            // Pre-warm KV cache with system prompt
            let language = settings.selectedLanguage
            let tone = (JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default).defaultTone
            let warmUpPrompt = LLMTextProcessor.buildSystemPrompt(language: language, tone: tone, dictionaryTerms: "")
            await local.warmUp(systemPrompt: warmUpPrompt)
        }
    }
}
```

Also in `loadLocalLLMModel()`:

```swift
func loadLocalLLMModel(_ filename: String) async {
    guard let local = localLLMAdapter else { return }
    let modelPath = LLMModelManager.modelsDirectory.appendingPathComponent(filename)
    guard FileManager.default.fileExists(atPath: modelPath.path) else { return }
    do {
        try await local.loadModel(name: filename, path: modelPath)
        llmSettings.selectedLocalModel = filename
        updateLLMConfiguration()
        // Pre-warm
        let language = settings.selectedLanguage
        let tone = (JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default).defaultTone
        let warmUpPrompt = LLMTextProcessor.buildSystemPrompt(language: language, tone: tone, dictionaryTerms: "")
        await local.warmUp(systemPrompt: warmUpPrompt)
    } catch {
        errorMessage = "Failed to load LLM: \(error.localizedDescription)"
    }
}
```

**Step 5: Expose `buildSystemPrompt` as a static method in LLMTextProcessor**

In `LLMTextProcessor.swift`, rename `systemPrompt(language:tone:dictionaryTerms:)` to be `public static`:

```swift
static func buildSystemPrompt(language: String, tone: String, dictionaryTerms: String) -> String {
    // ... existing implementation (currently named systemPrompt)
}
```

Update the internal call in `process()` to use the new name.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: pre-warm LLM KV cache on model load for faster first inference"
```

---

### Task 3: Progressive LLM Processing During Recording

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Models/AppState.swift`

This is the core optimization. While the user records, we run LLM refinement on the streaming transcription. By the time they stop, the refined text is often ready.

**Step 1: Add progressive LLM state to AppState**

Add these properties after the existing streaming state:

```swift
// Progressive LLM state
private var progressiveLLMTask: Task<Void, Never>?
private var lastLLMInputText = ""
private var progressiveRefinedText = ""
private var isProgressiveLLMRunning = false
```

**Step 2: Add `startProgressiveLLM()` and `stopProgressiveLLM()` methods**

```swift
private func startProgressiveLLM() {
    guard llmSettings.isEnabled, llmAdapter?.isModelLoaded == true, let llmProcessor else { return }

    progressiveLLMTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))  // Check every 1.5s (less aggressive than transcription)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            let currentText = self.streamedText
            let language = self.settings.selectedLanguage

            // Only process if we have new meaningful text
            guard !currentText.isEmpty,
                  currentText.count > 10,
                  currentText != self.lastLLMInputText,
                  !self.isProgressiveLLMRunning
            else { continue }

            self.isProgressiveLLMRunning = true
            self.lastLLMInputText = currentText

            // Run LLM on background — KV cache keeps system prompt hot
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
```

**Step 3: Wire into startRecording/confirmRecording/cancelRecording**

In `startRecording()`, after `startStreamingTranscription()`:

```swift
lastLLMInputText = ""
progressiveRefinedText = ""
startProgressiveLLM()
```

In `confirmRecording()`, after `stopStreamingTranscription()`:

```swift
stopProgressiveLLM()
```

In `cancelRecording()`, after `stopStreamingTranscription()`:

```swift
stopProgressiveLLM()
lastLLMInputText = ""
progressiveRefinedText = ""
```

**Step 4: Use progressive result in confirmRecording**

Replace the background LLM refinement section (step 6 in confirmRecording) with logic that checks if we already have a progressive result:

```swift
// 6. LLM refinement — use progressive result if available, otherwise background
if let llmProcessor, llmSettings.isEnabled, llmAdapter?.isModelLoaded == true {
    let textToRefine = finalText
    let lang = language
    let outputMode = settings.outputMode

    // Check if progressive processing already refined this text
    let progressiveResult = progressiveRefinedText
    lastLLMInputText = ""
    progressiveRefinedText = ""

    if !progressiveResult.isEmpty, progressiveResult != textToRefine {
        // We have a pre-computed result — use it immediately
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
```

**Step 5: Extract `applyRefinedText` helper**

```swift
private func applyRefinedText(original: String, refined: String, result: TranscriptionResult, outputMode: Constants.OutputMode) {
    // Update history with refined text
    if lastTranscription?.text == original {
        lastTranscription = TranscriptionResult(text: refined, timestamp: result.timestamp, duration: result.duration)
    }
    if let idx = transcriptionHistory.firstIndex(where: { $0.text == original }) {
        transcriptionHistory[idx] = TranscriptionResult(text: refined, timestamp: result.timestamp, duration: result.duration)
    }
    // Replace the already-pasted text
    switch outputMode {
    case .pasteAutomatic:
        textOutputService?.replaceText(old: original, with: refined)
    case .clipboardOnly:
        textOutputService?.copyToClipboard(refined)
    case .historyOnly:
        break
    }
}
```

**Step 6: Commit**

```bash
git add OpenWhisper/OpenWhisper/Models/AppState.swift
git commit -m "feat: progressive LLM processing during recording for near-instant refinement"
```

---

### Task 4: Smart Model Recommendations in Settings UI

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Views/SettingsView.swift`
- Modify: `OpenWhisper/OpenWhisper/Services/LLMModelManager.swift`

**Step 1: Add model size as Double to RecommendedModel**

In `LLMModelManager.swift`, add `sizeGB: Double` to `RecommendedModel`:

```swift
struct RecommendedModel: Identifiable {
    let id: String
    let name: String
    let size: String
    let sizeGB: Double      // NEW — numeric for calculations
    let languages: String
    let license: String
    let huggingFaceRepo: String
    let filename: String
}
```

Update each entry in `recommendedModels` with the numeric value:
- qwen3.5-4b: `sizeGB: 2.7`
- gemma3-4b: `sizeGB: 2.4`
- phi4-mini: `sizeGB: 2.5`
- qwen3.5-2b: `sizeGB: 1.5`
- gemma3n-e2b: `sizeGB: 1.2`

**Step 2: Update Settings UI to show hardware info and recommendations**

In `SettingsView.swift`, replace the LLMMemoryInfoView section with a combined hardware info + recommendations view.

In the "Memory" section, add the machine profile summary and show "Recommended" badge on the right model:

Replace `LLMMemoryInfoView` body:

```swift
private struct LLMMemoryInfoView: View {
    @State private var memoryInfo = MemoryInfo()
    private let profile = MachineProfile.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Hardware summary
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
```

In the model list (ForEach over recommendedModels), add a "Recommended" badge:

```swift
ForEach(LLMModelManager.recommendedModels) { model in
    let isDownloaded = appState.llmModelManager?.availableLocalModels.contains(model.filename) == true
    let isActive = llmSettings.selectedLocalModel == model.filename
    let isRecommended = model.id == MachineProfile.current.recommendedModelID
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
        // ... existing download/delete buttons
    }
}
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: smart model recommendations based on hardware profile"
```

---

### Task 5: Integration & Final Wiring

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Models/AppState.swift`

**Step 1: Auto-select recommended model if none selected**

In `setupServices()`, after creating the LLM model manager, if no model is selected but one is downloaded, auto-select the recommended one (or any available):

```swift
// Auto-select model if none selected but models are available
if llmSettings.selectedLocalModel.isEmpty,
   let manager = llmModelManager,
   !manager.availableLocalModels.isEmpty {
    let recommended = MachineProfile.current.recommendedModelID
    let recommendedFilename = LLMModelManager.recommendedModels.first(where: { $0.id == recommended })?.filename
    if let filename = recommendedFilename, manager.availableLocalModels.contains(filename) {
        llmSettings.selectedLocalModel = filename
    } else if let first = manager.availableLocalModels.first {
        llmSettings.selectedLocalModel = first
    }
}
```

**Step 2: Commit**

```bash
git add OpenWhisper/OpenWhisper/Models/AppState.swift
git commit -m "feat: auto-select recommended LLM model on first launch"
```
