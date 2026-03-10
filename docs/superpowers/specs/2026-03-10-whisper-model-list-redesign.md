# Whisper Model List Redesign

**Date:** 2026-03-10

## Goal

Replace the simple `Picker` in `ModelSettingsTab` with a rich card list matching the LLM tab: sections per model family, per-model download/load/delete actions, progress bar, and hardware+language-aware Recommended badge.

## Data Layer

### `Constants.SupportedModels` — replace string list with struct

```swift
struct WhisperModel: Identifiable {
    let id: String          // e.g. "base.en"
    let family: String      // "tiny" | "base" | "small" | "medium" | "large"
    let displayName: String // e.g. "Base (English)"
    let size: String        // e.g. "~145 MB"
    let sizeGB: Double      // for hardware recommendation tiers
    let quality: String     // e.g. "Fast, English only"
    let isEnglishOnly: Bool
}
```

`SupportedModels.all: [WhisperModel]` — 10 models in family order.
`SupportedModels.families: [String]` — ["tiny", "base", "small", "medium", "large"] for section grouping.

### `MachineProfile` — add Whisper recommendation

```swift
var recommendedWhisperFamily: String
// < 8 GB  → "tiny"
// 8 GB    → "base"
// 16 GB   → "small"
// 32 GB   → "medium"
// 64 GB+  → "large"
```

Recommended model ID = cross `recommendedWhisperFamily` with `AppSettings.selectedLanguage`:
- `"en"` → `.en` variant (e.g. `"base.en"`)
- any other → multilingual (e.g. `"base"`)

Computed in the view: `MachineProfile.current.recommendedWhisperModelID(for: selectedLanguage)`.

## ModelManager Integration

Add `modelManager: ModelManager` to `AppState` (instantiated in `init`, same pattern as `llmModelManager`). This exposes:
- `availableLocalModels: [String]` — downloaded model folder names
- `isDownloading: Bool`
- `downloadProgress: Double`
- `deleteModel(_ name: String)`

`AppState.loadTranscriptionEngine()` already triggers download via WhisperKit; `modelManager.refreshLocalModels()` is called after load completes.

## UI — ModelSettingsTab

`Form` with `.formStyle(.grouped)`. One `Section` per family label (Tiny, Base, Small, Medium, Large).

Each model row (same structure as LLM tab):

```
[Name + badges]          [Action button(s)]
[size — quality]
[─── progress bar ───]   ← only when downloading this model
```

**Badges:** `Active` (green), `Recommended` (blue) — same capsule style as LLM tab.

**Action states:**
| State | Button |
|---|---|
| Downloading | ProgressView spinner + status text |
| Downloaded + active | "Loaded" (disabled) + trash icon |
| Downloaded + inactive | "Load" + trash icon |
| Not downloaded | "Download" |

Only one model can be active at a time. Download disabled while any download is in progress.

## Files Changed

1. `Constants.swift` — replace string list with `WhisperModel` struct + `families`
2. `MachineProfile.swift` — add `recommendedWhisperFamily` + `recommendedWhisperModelID(for:)`
3. `AppState.swift` — add `modelManager: ModelManager`, call `refreshLocalModels()` after load
4. `SettingsView.swift` — rewrite `ModelSettingsTab` using new data + `modelManager`
