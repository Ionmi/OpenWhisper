# Whisper Model List Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the simple Picker in ModelSettingsTab with a rich card list matching the LLM tab — sections per model family, per-model download/load/delete, progress bar, and hardware+language-aware Recommended badge.

**Architecture:** Add a `WhisperModel` struct to `Constants`, extend `MachineProfile` with a Whisper-specific recommendation, wire `ModelManager` into `AppState`, then rewrite `ModelSettingsTab` following the exact same card pattern as `LLMSettingsTab`.

**Tech Stack:** Swift, SwiftUI, AppKit, WhisperKit (model loading via `AppState.loadTranscriptionEngine`)

---

## Chunk 1: Data layer

### Task 1: Replace string list with `WhisperModel` struct in Constants

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Utilities/Constants.swift` (lines 131–155)

The `SupportedModels` enum currently holds a flat string array and a descriptions dict. Replace both with a typed struct and a static model list. Keep `defaultModel` and the `all` computed property name so existing call sites (`settings.selectedModel`, `appState.loadTranscriptionEngine`) keep compiling without changes — `selectedModel` stores the model `id` (string), which stays the same.

- [ ] **Step 1: Add `WhisperModel` struct and replace `SupportedModels` content**

Replace the entire `SupportedModels` enum body in `Constants.swift`:

```swift
enum SupportedModels {
    struct WhisperModel: Identifiable {
        let id: String
        let family: String          // "tiny" | "base" | "small" | "medium" | "large"
        let displayName: String
        let size: String            // human-readable e.g. "~145 MB"
        let sizeGB: Double          // numeric for recommendation tiers
        let quality: String         // short description
        let isEnglishOnly: Bool
    }

    static let all: [WhisperModel] = [
        WhisperModel(id: "tiny",           family: "tiny",   displayName: "Tiny",             size: "~75 MB",   sizeGB: 0.075, quality: String(localized: "Fastest, lower accuracy"),     isEnglishOnly: false),
        WhisperModel(id: "tiny.en",        family: "tiny",   displayName: "Tiny (English)",    size: "~75 MB",   sizeGB: 0.075, quality: String(localized: "Fastest, English only"),        isEnglishOnly: true),
        WhisperModel(id: "base",           family: "base",   displayName: "Base",             size: "~145 MB",  sizeGB: 0.145, quality: String(localized: "Fast, good accuracy"),           isEnglishOnly: false),
        WhisperModel(id: "base.en",        family: "base",   displayName: "Base (English)",    size: "~145 MB",  sizeGB: 0.145, quality: String(localized: "Fast, English only"),            isEnglishOnly: true),
        WhisperModel(id: "small",          family: "small",  displayName: "Small",            size: "~465 MB",  sizeGB: 0.465, quality: String(localized: "Balanced speed & accuracy"),     isEnglishOnly: false),
        WhisperModel(id: "small.en",       family: "small",  displayName: "Small (English)",   size: "~465 MB",  sizeGB: 0.465, quality: String(localized: "Balanced, English only"),        isEnglishOnly: true),
        WhisperModel(id: "medium",         family: "medium", displayName: "Medium",           size: "~1.5 GB",  sizeGB: 1.5,   quality: String(localized: "High accuracy, slower"),          isEnglishOnly: false),
        WhisperModel(id: "medium.en",      family: "medium", displayName: "Medium (English)",  size: "~1.5 GB",  sizeGB: 1.5,   quality: String(localized: "High accuracy, English only"),    isEnglishOnly: true),
        WhisperModel(id: "large-v3",       family: "large",  displayName: "Large v3",         size: "~3 GB",    sizeGB: 3.0,   quality: String(localized: "Best accuracy, slowest"),          isEnglishOnly: false),
        WhisperModel(id: "large-v3-turbo", family: "large",  displayName: "Large v3 Turbo",   size: "~1.6 GB",  sizeGB: 1.6,   quality: String(localized: "Near-best accuracy, faster"),      isEnglishOnly: false),
    ]

    static let families: [String] = ["tiny", "base", "small", "medium", "large"]

    static let defaultModel = "base"
}
```

- [ ] **Step 2: Fix the one call site that iterates the old string array**

`OnboardingView.swift` has:
```swift
Picker("Model", selection: $settings.selectedModel) {
    ForEach(Constants.SupportedModels.all, id: \.self) { model in
        Text(model).tag(model)
    }
}
```
Replace with:
```swift
Picker("Model", selection: $settings.selectedModel) {
    ForEach(Constants.SupportedModels.all) { model in
        Text(model.displayName).tag(model.id)
    }
}
```

- [ ] **Step 3: Build to verify no errors**

```bash
cd /Users/ionmi/Development/OpenWhisper/OpenWhisper
xcodebuild -scheme OpenWhisper -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED` with no `error:` lines.

- [ ] **Step 4: Commit**

```bash
git add OpenWhisper/OpenWhisper/Utilities/Constants.swift OpenWhisper/OpenWhisper/Views/OnboardingView.swift
git commit -m "refactor: replace SupportedModels string list with WhisperModel struct"
```

---

### Task 2: Add Whisper recommendation to MachineProfile

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Services/MachineProfile.swift`

`MachineProfile` already has `totalRAMGB` and `recommendedModelID` for LLM. Add a parallel computed property for Whisper. Whisper runs on CPU/CoreML so RAM size (not bandwidth) is the right axis.

- [ ] **Step 1: Add `recommendedWhisperFamily` and `recommendedWhisperModelID(for:)` to `MachineProfile`**

Add after the existing `recommendedModelID` property:

```swift
/// Recommended Whisper model family based on RAM.
var recommendedWhisperFamily: String {
    switch totalRAMGB {
    case ..<8:   return "tiny"
    case 8..<16: return "base"
    case 16..<32: return "small"
    case 32..<64: return "medium"
    default:     return "large"
    }
}

/// Recommended Whisper model ID, taking the user's selected language into account.
/// If language is "en", returns the English-only variant; otherwise multilingual.
func recommendedWhisperModelID(for language: String) -> String {
    let family = recommendedWhisperFamily
    let preferEnglish = language == "en"
    if preferEnglish {
        // large family has no .en variant — fall back to large-v3-turbo
        if family == "large" { return "large-v3-turbo" }
        return "\(family).en"
    }
    if family == "large" { return "large-v3" }
    return family
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme OpenWhisper -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add OpenWhisper/OpenWhisper/Services/MachineProfile.swift
git commit -m "feat: add recommendedWhisperModelID(for:) to MachineProfile"
```

---

### Task 3: Wire ModelManager into AppState

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Models/AppState.swift`

`ModelManager` (in `Services/ModelManager.swift`) already tracks `availableLocalModels`, `isDownloading`, `downloadProgress`, and `deleteModel()`. It just isn't exposed on `AppState`. The LLM tab reads from `appState.llmModelManager` — do the same for `modelManager`.

- [ ] **Step 1: Add `modelManager` to `AppState`**

In `AppState.swift`, in the `// Services (existing)` block, add:
```swift
let modelManager = ModelManager()
```

- [ ] **Step 2: Call `refreshLocalModels()` after model load completes**

Find `loadTranscriptionEngine()` in `AppState.swift`. After `isModelLoaded = true` is set (successful load path), add:
```swift
modelManager.refreshLocalModels()
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -scheme OpenWhisper -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add OpenWhisper/OpenWhisper/Models/AppState.swift
git commit -m "feat: expose ModelManager on AppState"
```

---

## Chunk 2: UI

### Task 4: Rewrite ModelSettingsTab

**Files:**
- Modify: `OpenWhisper/OpenWhisper/Views/SettingsView.swift` (lines 424–471)

Replace the entire `ModelSettingsTab` struct. The new implementation follows the LLM tab pattern exactly: one `Section` per family, each row a `VStack` with name+badges on top and size+quality below, action buttons trailing, progress bar below when downloading.

Key state to read from `appState`:
- `appState.modelManager.availableLocalModels` — `[String]` of downloaded model folder names (same as model id)
- `appState.modelManager.isDownloading` — Bool
- `appState.modelManager.downloadProgress` — Double 0–1
- `appState.settings.selectedModel` — currently loaded model id
- `appState.isModelLoaded` — Bool
- `appState.isLoadingModel` — Bool (true while downloading+loading)

The download action calls `appState.loadTranscriptionEngine()` after setting `settings.selectedModel`. The load action (for already-cached models) also calls `appState.loadTranscriptionEngine()`. Delete calls `appState.modelManager.deleteModel(model.id)` and resets `settings.selectedModel` if needed.

- [ ] **Step 1: Replace `ModelSettingsTab` with the new implementation**

Replace everything from `struct ModelSettingsTab` through its closing `}` (lines 424–471) with:

```swift
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
                            // Download or load action
                            settings.selectedModel = model.id
                            Task { await appState.loadTranscriptionEngine() }
                        } onDelete: {
                            if settings.selectedModel == model.id {
                                appState.isModelLoaded = false
                            }
                            try? appState.modelManager.deleteModel(model.id)
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
                        Text("Downloading…")
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
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
            }
        }
    }

    @Environment(AppState.self) private var appState
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme OpenWhisper -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Smoke test in the app**

Run the app from Xcode (Cmd+R). Open Settings → Model tab. Verify:
- Models appear grouped under Tiny / Base / Small / Medium / Large sections
- Currently loaded model shows "Active" badge
- Recommended model shows "Recommended" badge (changes if you switch Language in General tab)
- Download button appears for models not on disk
- Load button appears for cached-but-not-active models
- Trash button appears for cached models
- Downloading a model shows spinner + progress bar

- [ ] **Step 4: Commit**

```bash
git add OpenWhisper/OpenWhisper/Views/SettingsView.swift
git commit -m "feat: redesign ModelSettingsTab as rich card list matching LLM tab"
```
