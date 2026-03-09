# OpenWhisper v2 Features Design

Date: 2026-03-09

## Overview

Add 10 new features to OpenWhisper while adopting hexagonal architecture for long-term maintainability.

## Architecture: Hexagonal (Ports & Adapters)

All major components communicate through Swift protocols (ports). Implementations (adapters) are swappable.

```
Ports (protocols):
├── AudioCapturePort        → AVAudioEngineAdapter, AUVoiceProcessingAdapter
├── TranscriptionPort       → WhisperKitAdapter (existing TranscriptionEngine)
├── NoiseSuppressionPort    → AppleVoiceProcessingAdapter
├── VoiceActivityPort       → SileroVADAdapter
├── TextProcessingPort      → RegexProcessor, LLMProcessor
├── LLMPort                 → LocalLLMAdapter (llama.cpp), RemoteLLMAdapter (OpenAI-compatible API)
├── DictionaryPort          → JSONDictionaryAdapter
├── SnippetPort             → JSONSnippetAdapter
├── AppDetectionPort        → NSWorkspaceAdapter
└── TextOutputPort          → PasteAdapter, ClipboardAdapter (existing)
```

Storage: `~/Library/Application Support/OpenWhisper/` for all user data (models, dictionaries, snippets, settings).

## Feature 1: Audio Pipeline (AEC + Noise Suppression + VAD)

### 1a. AEC (Acoustic Echo Cancellation)

**Problem**: User plays music/videos while dictating. System audio bleeds into mic.

**Solution**:
- Capture system audio output via Core Audio Taps (macOS 14.4+) as reference signal
- Use AUVoiceProcessingIO audio unit which provides built-in AEC + noise suppression
- Feed the reference signal to AEC to subtract system audio from mic input

**Requirements**:
- macOS 14.4+ minimum target
- NSAudioCaptureUsageDescription in Info.plist
- User permission prompt for audio capture

### 1b. Noise Suppression

**Solution**: AUVoiceProcessingIO includes native Apple noise suppression (fans, keyboard, street noise). No external libraries needed.

### 1c. VAD (Voice Activity Detection)

**Problem**: Whisper hallucinates on silence/music-only segments.

**Solution**:
- Integrate Silero VAD (ONNX model, ~2MB)
- Segment audio: only feed speech segments to Whisper
- Skip silence and noise-only sections
- Reduces hallucinations and improves transcription speed

**Pipeline**:
```
[Mic] → [AUVoiceProcessingIO (AEC + noise suppression)] → [VAD segmentation] → [WhisperKit] → [Post-processing]
```

## Feature 2: Dictionary (Personal Vocabulary)

**Problem**: Technical terms transcribed incorrectly (e.g., "git ignore" instead of ".gitignore").

**Solution**:
- JSON storage: `~/Library/Application Support/OpenWhisper/dictionary.json`
- Format: `[{"from": "git ignore", "to": ".gitignore"}, ...]`
- Case-insensitive matching applied after transcription
- UI: editable table in Settings with add/delete/edit

**Built-in defaults** (optional, user can disable):
- Common programming terms: `.gitignore`, `npm`, `JavaScript`, `TypeScript`, `GitHub`, `localhost`, `API`, `JSON`, `webpack`, `Node.js`, etc.

## Feature 3: Filler Word Removal

**Problem**: Transcription includes "eh", "um", "bueno", "o sea", etc.

**Solution**:
- Per-language filler lists stored in JSON
- Regex-based removal after transcription
- Configurable: user can add/remove fillers per language
- Applied before other post-processing steps

**Default fillers**:
- Spanish: "eh", "um", "ah", "bueno", "o sea", "pues", "a ver", "digamos", "este", "vale vale"
- English: "um", "uh", "like", "you know", "I mean", "sort of", "kind of", "basically", "actually"
- (Other languages populated with common fillers)

## Feature 4: Smart Punctuation

**Problem**: User wants to dictate punctuation via voice commands.

**Solution**:
- Detect trigger phrases and replace with punctuation characters
- Per-language command lists
- Applied after filler removal, before other processing

**Default commands (Spanish)**:
- "coma" → `,`
- "punto" → `.`
- "punto y coma" → `;`
- "dos puntos" → `:`
- "interrogación" / "signo de interrogación" → `?`
- "exclamación" / "signo de exclamación" → `!`
- "nueva línea" / "salto de línea" → `\n`
- "abrir paréntesis" → `(`
- "cerrar paréntesis" → `)`

**Default commands (English)**:
- "comma" → `,`
- "period" / "full stop" → `.`
- "question mark" → `?`
- "exclamation mark" / "exclamation point" → `!`
- "new line" → `\n`
- "open parenthesis" → `(`
- "close parenthesis" → `)`

## Feature 5: Snippets (Voice-Activated Templates)

**Problem**: User wants to insert predefined text blocks by saying a trigger phrase.

**Solution**:
- JSON storage: `~/Library/Application Support/OpenWhisper/snippets.json`
- Format: `[{"trigger": "firma email", "text": "Saludos cordiales,\nIon"}, ...]`
- After transcription, if cleaned text matches a trigger exactly → replace with snippet text
- UI: CRUD table in Settings

**Matching**: Case-insensitive, trimmed. Full match only (not partial).

## Feature 6: Auto-Add to Dictionary

**Problem**: User manually correcting the same words repeatedly.

**Solution**:
- After pasting transcribed text, monitor the text field briefly via Accessibility API
- If user edits a word within ~5 seconds, compare with original transcription
- Show a discrete notification: "Add 'X' → 'Y' to dictionary?"
- If accepted, add to dictionary.json

**Constraint**: Only works with Accessibility permission (already required for hotkey). Non-intrusive — notification only, no forced popups.

## Feature 7: Context Modes (Per-App Tone)

**Problem**: User wants formal tone in email, casual in chat.

**Solution**:
- Detect frontmost app via `NSWorkspace.shared.frontmostApplication`
- Configurable mapping: app bundle ID → tone/instructions
- Tone is injected as part of the LLM system prompt (requires LLM feature enabled)
- Without LLM: no effect (regex processing is tone-agnostic)

**Default mappings**:
- Mail, Outlook → "formal, professional"
- Slack, Discord, Messages, Telegram, WhatsApp → "casual, concise"
- Notes, TextEdit → "neutral"
- Terminal, VS Code, Xcode → "technical"
- All others → "neutral" (configurable default)

**UI**: Table in Settings: App name + bundle ID + tone selector/custom prompt.

## Feature 8: Real-Time Corrections (LLM)

**Problem**: User says "2... en realidad 3" and wants just "3".

**Solution**:
- When LLM is enabled, the final post-processing step sends text through the LLM
- System prompt instructs: fix self-corrections, false starts, repeated phrases
- System prompt language matches input language (auto-detected or user-selected)
- Combined with context mode tone if applicable

**LLM prompt template**:
```
You are a text post-processor for voice dictation. Rules:
- Fix self-corrections (e.g., "2... actually 3" → "3")
- Remove false starts and repetitions
- Fix grammar errors
- Apply tone: {tone}
- Preserve original meaning and language. Do NOT translate.
- Output ONLY the corrected text, nothing else.

User dictionary (use these exact spellings): {dictionary_terms}

Text to process:
{transcribed_text}
```

## Feature 9: LLM Integration

### Local LLM (llama.cpp + Metal)

**Recommended models** (downloadable from HuggingFace):

| Model | GGUF Size | Languages | License | Notes |
|-------|-----------|-----------|---------|-------|
| Qwen3.5-4B Q4_K_M | 2.74 GB | 201 | Apache 2.0 | **Default recommended** |
| Gemma 3 4B IT QAT | 2.36 GB | 140+ | Gemma | Google QAT, good quality |
| Phi-4-mini Q4_K_M | 2.49 GB | 23 | MIT | Best for EN/ES/EU |
| Qwen3.5-2B Q4_K_M | ~1.5 GB | 201 | Apache 2.0 | Lightweight option |
| Gemma 3n E2B Q4_K_M | ~1.2 GB | 140+ | Gemma | Ultra-light, basic corrections |

**Storage**: `~/Library/Application Support/OpenWhisper/LLMModels/`
**Download**: From HuggingFace, same UX as WhisperKit model downloads.
**Inference**: llama.cpp with Metal acceleration via Swift bindings.

### Remote LLM (API)

- OpenAI-compatible API (works with OpenAI, Ollama, OpenRouter, LM Studio, etc.)
- Configurable: base URL + API key + model name
- Default base URL: empty (disabled)

### Settings UI

- Toggle: LLM enabled/disabled (default: disabled)
- Source selector: "Local" or "Remote"
- If local: model picker with download buttons (like Whisper model selector)
- If remote: base URL, API key, model name fields
- Test button to verify connection

## Post-Processing Pipeline Order

```
1. Raw transcription from WhisperKit
2. Clean Whisper hallucinations (existing: remove [Music], phantom phrases)
3. Snippet matching (if exact match → return snippet, skip rest)
4. Dictionary replacement (regex, case-insensitive)
5. Filler word removal (regex, per-language)
6. Smart punctuation (voice command → character)
7. LLM processing (if enabled): corrections + tone + dictionary reinforcement
8. Final trim and cleanup
```

## Settings UI Layout

New tabs/sections in SettingsView:

```
Settings
├── General (existing: hotkey, output mode, launch at login)
├── Transcription (existing: model, language)
├── Audio Processing (NEW)
│   ├── Toggle: Echo cancellation (AEC)
│   ├── Toggle: Noise suppression
│   └── Toggle: Voice activity detection (VAD)
├── Post-Processing (NEW)
│   ├── Dictionary (table: from → to, add/delete/edit)
│   ├── Fillers (list per language, add/delete)
│   ├── Punctuation Commands (table: command → character)
│   ├── Snippets (table: trigger → text, add/delete/edit)
│   └── Auto-add to dictionary toggle
├── Context Modes (NEW)
│   └── Table: app → tone (add/delete/edit, default tone selector)
└── LLM (NEW)
    ├── Toggle: enabled/disabled
    ├── Source: Local / Remote
    ├── Local: model picker + download
    └── Remote: base URL + API key + model
```

## Data Storage

All user data as JSON files in `~/Library/Application Support/OpenWhisper/`:

| File | Content |
|------|---------|
| `dictionary.json` | Personal vocabulary entries |
| `fillers.json` | Filler words per language |
| `punctuation.json` | Voice punctuation commands per language |
| `snippets.json` | Voice-activated text templates |
| `context-modes.json` | App → tone mappings |
| `llm-settings.json` | LLM configuration |
| `audio-settings.json` | AEC/noise/VAD toggles |
| `Models/` | WhisperKit models (existing) |
| `LLMModels/` | LLM GGUF files |

## Dependencies to Add

| Dependency | Purpose | Integration |
|------------|---------|-------------|
| llama.cpp (llama.swift) | Local LLM inference with Metal | Swift Package |
| Silero VAD ONNX model | Voice activity detection | ONNX Runtime or CoreML conversion |
| Core Audio Taps API | System audio capture for AEC | Native macOS framework |
| AUVoiceProcessingIO | AEC + noise suppression | Native macOS AudioToolbox |

## Non-Goals (Deferred to Future)

- IDE integration (variable recognition, file referencing)
- Style personalization (learning user preferences over time via RL)
- Style history (token-level formatting control)
- Team/shared dictionaries
- Windows/iOS support
