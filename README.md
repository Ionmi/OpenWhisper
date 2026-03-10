# OpenWhisper

Local voice-to-text for macOS. Press a hotkey, speak, and your words appear at the cursor. Runs entirely on-device using OpenAI's Whisper model — no cloud, no subscriptions, no data leaves your Mac.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

<!-- TODO: Add screenshot or GIF demo here
![OpenWhisper Demo](assets/demo.gif)
-->

## Privacy

OpenWhisper processes all audio locally on your Mac. Your voice recordings are never sent to any server. The Whisper model runs on-device, and transcription history is stored only in your local preferences. No analytics, no telemetry, no network requests beyond the initial model download.

## Features

- **Global hotkey** (Option + Space) — works from any app
- **Three shortcut modes** — Auto (smart press/hold detection), Toggle, or Hold
- **Streaming transcription** — see live text preview while you speak
- **On-device LLM post-processing** — refine transcriptions with punctuation, capitalization, and grammar using local MLX models (Qwen3, Gemma, Phi-4) or a remote OpenAI-compatible API
- **Context-aware tone** — automatic tone adjustment based on the active app (formal for Mail, casual for Slack, etc.)
- **Voice Activity Detection** — energy-based VAD filters silence while preserving speech boundaries
- **Voice processing** — echo cancellation (AEC) and noise suppression via Apple's Voice Processing I/O
- **Text processing pipeline** — dictionary replacements, filler word removal, punctuation commands, and snippet expansion
- **Auto-dictionary learning** — monitors corrections to learn custom word replacements
- **13+ languages** with auto-detect
- **10 Whisper models** — from tiny (fast) to large-v3 (accurate)
- **Menu bar app** — lives in your status bar, out of your way
- **Floating indicator** — pill or minimal style, 6 screen positions
- **Multiple output modes** — paste at cursor, clipboard only, or history only
- **Transcription history** — last 50 recordings accessible from the menu bar
- **Native Settings UI** — macOS System Settings style with hardware-based LLM model recommendations
- **Guided onboarding** — permissions setup and model download on first launch

## Installation

### Homebrew (recommended)

```bash
brew tap Ionmi/tap
brew install --cask openwhisper
```

### Manual download

1. Download the latest `.dmg` from [Releases](https://github.com/ionmi/OpenWhisper/releases)
2. Drag **OpenWhisper** to your Applications folder
3. Since the app is not signed with an Apple Developer certificate, macOS will block it on first launch. Remove the quarantine flag:

```bash
xattr -cr /Applications/OpenWhisper.app
```

4. Open OpenWhisper from Applications

### Build from source

**Requirements:** macOS 14+, Xcode 15+

```bash
git clone https://github.com/ionmi/OpenWhisper.git
cd OpenWhisper/OpenWhisper
open OpenWhisper.xcodeproj
```

Build and run from Xcode (Cmd + R).

> **Note for contributors:** The project uses automatic code signing. You may need to update the development team in Xcode's Signing & Capabilities tab to your own Apple ID.

## First launch

OpenWhisper will guide you through setup:

1. **Microphone permission** — required for audio capture
2. **Accessibility permission** — required for the global hotkey and text pasting
3. **Model download** — select a Whisper model (recommended: `base` for a good speed/accuracy balance)

## Usage

| Action | Default |
|--------|---------|
| Start/stop dictation | Option + Space |
| Cancel recording | Escape |
| Confirm (toggle mode) | Enter |

Your transcribed text is automatically pasted at the cursor position. Change this behavior in Settings to clipboard-only or history-only mode.

### Shortcut modes

- **Auto** — short press toggles recording, long press (> 0.3s) records while held
- **Toggle** — press to start, Enter to confirm, Escape to cancel
- **Hold** — hold to record, release to transcribe

### Models

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| tiny | ~75 MB | Fastest | Basic |
| base | ~150 MB | Fast | Good |
| small | ~500 MB | Moderate | Better |
| medium | ~1.5 GB | Slow | Great |
| large-v3 | ~3 GB | Slowest | Best |

English-only variants (`.en`) are available for tiny, base, small, and medium — they're faster and more accurate for English.

Models are downloaded on first use and stored in `~/Library/Application Support/OpenWhisper/Models/`.

## Supported languages

Auto-detect, English, Spanish, French, German, Italian, Portuguese, Dutch, Russian, Chinese, Japanese, Korean, Arabic.

## Troubleshooting

### "OpenWhisper can't be opened because Apple cannot check it for malicious software"

Run this in Terminal:

```bash
xattr -cr /Applications/OpenWhisper.app
```

### Hotkey not working

Make sure Accessibility permission is granted: **System Settings > Privacy & Security > Accessibility > OpenWhisper**.

### No audio captured

Check Microphone permission: **System Settings > Privacy & Security > Microphone > OpenWhisper**.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) before submitting a pull request.

All changes require review and approval before merging.

## License

[MIT](LICENSE)
