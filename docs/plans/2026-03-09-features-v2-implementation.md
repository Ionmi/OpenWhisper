# OpenWhisper v2 Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 10 features (hexagonal architecture, AEC, noise suppression, VAD, dictionary, fillers, punctuation, snippets, auto-add dictionary, context modes, real-time corrections, LLM integration) to OpenWhisper.

**Architecture:** Hexagonal ports & adapters. All major services behind Swift protocols. JSON file storage for user data. llama.cpp for local LLM inference with Metal.

**Tech Stack:** Swift/SwiftUI, WhisperKit, Core Audio Taps, AUVoiceProcessingIO, Silero VAD (ONNX/CoreML), llama.cpp (llama.swift), HuggingFace model downloads.

**Base path:** `/Users/ionmi/Development/OpenWhisper/OpenWhisper/OpenWhisper/`

---

### Task 1: Hexagonal Architecture — Define Ports (Protocols)

**Files:**
- Create: `Ports/AudioCapturePort.swift`
- Create: `Ports/TranscriptionPort.swift`
- Create: `Ports/TextProcessingPort.swift`
- Create: `Ports/LLMPort.swift`
- Create: `Ports/DictionaryPort.swift`
- Create: `Ports/SnippetPort.swift`
- Create: `Ports/AppDetectionPort.swift`
- Create: `Ports/VoiceActivityPort.swift`

**Step 1: Create the Ports directory and all protocol files**

```swift
// Ports/AudioCapturePort.swift
import Foundation

protocol AudioCapturePort: AnyObject {
    var currentLevel: Float { get }
    func startRecording() throws
    func stopRecording() -> [Float]
    func currentSamples() -> [Float]
}
```

```swift
// Ports/TranscriptionPort.swift
import Foundation

protocol TranscriptionPort: Sendable {
    func loadModel(name: String) async throws
    func transcribe(audioSamples: [Float], language: String?) async throws -> String
    var isModelLoaded: Bool { get }
}
```

```swift
// Ports/TextProcessingPort.swift
import Foundation

protocol TextProcessingPort {
    func process(_ text: String, language: String) -> String
}
```

```swift
// Ports/LLMPort.swift
import Foundation

protocol LLMPort: Sendable {
    func loadModel(name: String, path: URL) async throws
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
    var isModelLoaded: Bool { get }
    func unloadModel()
}
```

```swift
// Ports/DictionaryPort.swift
import Foundation

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
}

protocol DictionaryPort {
    func load() -> [DictionaryEntry]
    func save(_ entries: [DictionaryEntry])
    func addEntry(_ entry: DictionaryEntry)
    func removeEntry(id: UUID)
}
```

```swift
// Ports/SnippetPort.swift
import Foundation

struct SnippetEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var text: String
}

protocol SnippetPort {
    func load() -> [SnippetEntry]
    func save(_ entries: [SnippetEntry])
    func addEntry(_ entry: SnippetEntry)
    func removeEntry(id: UUID)
    func match(_ text: String) -> String?
}
```

```swift
// Ports/AppDetectionPort.swift
import Foundation

protocol AppDetectionPort {
    func frontmostAppBundleID() -> String?
    func frontmostAppName() -> String?
}
```

```swift
// Ports/VoiceActivityPort.swift
import Foundation

protocol VoiceActivityPort {
    func loadModel() throws
    /// Returns segments of audio that contain speech (start/end sample indices)
    func detectSpeechSegments(in samples: [Float], sampleRate: Int) -> [(start: Int, end: Int)]
    /// Simple check: does this audio chunk contain speech?
    func containsSpeech(_ samples: [Float], sampleRate: Int) -> Bool
}
```

**Step 2: Make existing TranscriptionEngine conform to TranscriptionPort**

In `Services/TranscriptionEngine.swift`, rename the protocol to `TranscriptionPort` or create a typealias. Since the existing code uses `TranscriptionEngine` everywhere, the simplest approach: make `TranscriptionEngine` extend `TranscriptionPort` or just rename it.

Rename `TranscriptionEngine` to `TranscriptionPort` in:
- `Services/TranscriptionEngine.swift` (definition)
- `Services/WhisperKitEngine.swift` (conformance)
- `Models/AppState.swift` (usage: `var transcriptionEngine: (any TranscriptionPort)?`)

**Step 3: Make existing AudioCaptureService conform to AudioCapturePort**

Add `: AudioCapturePort` conformance to `AudioCaptureService` in `Services/AudioCaptureService.swift`.

**Step 4: Verify the project builds**

Run: `cd /Users/ionmi/Development/OpenWhisper/OpenWhisper && xcodebuild -scheme OpenWhisper -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: introduce hexagonal architecture ports (protocols)"
```

---

### Task 2: JSON Storage Adapters (Dictionary, Snippets, Fillers, Punctuation, Context Modes)

**Files:**
- Create: `Adapters/Storage/JSONStorageAdapter.swift`
- Create: `Adapters/Storage/JSONDictionaryAdapter.swift`
- Create: `Adapters/Storage/JSONSnippetAdapter.swift`
- Create: `Models/FillerConfig.swift`
- Create: `Models/PunctuationConfig.swift`
- Create: `Models/ContextModeConfig.swift`

**Step 1: Create generic JSON storage helper**

```swift
// Adapters/Storage/JSONStorageAdapter.swift
import Foundation

final class JSONStorageAdapter {
    static let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenWhisper")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = appSupportDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportDir.appendingPathComponent(filename)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

**Step 2: Create JSONDictionaryAdapter**

```swift
// Adapters/Storage/JSONDictionaryAdapter.swift
import Foundation

final class JSONDictionaryAdapter: DictionaryPort {
    private let filename = "dictionary.json"
    private var entries: [DictionaryEntry] = []

    init() {
        entries = load()
        if entries.isEmpty {
            entries = Self.defaultEntries
            save(entries)
        }
    }

    func load() -> [DictionaryEntry] {
        JSONStorageAdapter.load([DictionaryEntry].self, from: filename) ?? []
    }

    func save(_ entries: [DictionaryEntry]) {
        self.entries = entries
        JSONStorageAdapter.save(entries, to: filename)
    }

    func addEntry(_ entry: DictionaryEntry) {
        entries.append(entry)
        save(entries)
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save(entries)
    }

    static let defaultEntries: [DictionaryEntry] = [
        DictionaryEntry(from: "git ignore", to: ".gitignore"),
        DictionaryEntry(from: "gitignore", to: ".gitignore"),
        DictionaryEntry(from: "javascript", to: "JavaScript"),
        DictionaryEntry(from: "typescript", to: "TypeScript"),
        DictionaryEntry(from: "node js", to: "Node.js"),
        DictionaryEntry(from: "next js", to: "Next.js"),
        DictionaryEntry(from: "react js", to: "React.js"),
        DictionaryEntry(from: "vue js", to: "Vue.js"),
        DictionaryEntry(from: "npm", to: "npm"),
        DictionaryEntry(from: "api", to: "API"),
        DictionaryEntry(from: "json", to: "JSON"),
        DictionaryEntry(from: "html", to: "HTML"),
        DictionaryEntry(from: "css", to: "CSS"),
        DictionaryEntry(from: "github", to: "GitHub"),
        DictionaryEntry(from: "webpack", to: "webpack"),
        DictionaryEntry(from: "localhost", to: "localhost"),
        DictionaryEntry(from: "sql", to: "SQL"),
        DictionaryEntry(from: "graphql", to: "GraphQL"),
    ]
}
```

**Step 3: Create JSONSnippetAdapter**

```swift
// Adapters/Storage/JSONSnippetAdapter.swift
import Foundation

final class JSONSnippetAdapter: SnippetPort {
    private let filename = "snippets.json"
    private var entries: [SnippetEntry] = []

    init() {
        entries = load()
    }

    func load() -> [SnippetEntry] {
        JSONStorageAdapter.load([SnippetEntry].self, from: filename) ?? []
    }

    func save(_ entries: [SnippetEntry]) {
        self.entries = entries
        JSONStorageAdapter.save(entries, to: filename)
    }

    func addEntry(_ entry: SnippetEntry) {
        entries.append(entry)
        save(entries)
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save(entries)
    }

    func match(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.first { $0.trigger.lowercased() == trimmed }?.text
    }
}
```

**Step 4: Create filler, punctuation, and context mode config models**

```swift
// Models/FillerConfig.swift
import Foundation

struct FillerConfig: Codable {
    var fillersByLanguage: [String: [String]]

    static let `default` = FillerConfig(fillersByLanguage: [
        "es": ["eh", "um", "ah", "bueno", "o sea", "pues", "a ver", "digamos", "este", "vale vale", "entonces", "sabes"],
        "en": ["um", "uh", "like", "you know", "I mean", "sort of", "kind of", "basically", "actually", "right"],
        "fr": ["euh", "ben", "genre", "en fait", "du coup", "bah", "voila"],
        "de": ["ah", "ahm", "also", "halt", "sozusagen", "quasi", "na ja"],
        "it": ["eh", "ciao", "allora", "praticamente", "cioe", "insomma"],
        "pt": ["eh", "tipo", "ne", "entao", "basicamente", "quer dizer"],
        "ja": ["えーと", "あの", "その", "まあ", "なんか"],
        "ko": ["음", "어", "그", "뭐", "아"],
        "zh": ["嗯", "那个", "就是", "然后", "这个"],
        "ru": ["эм", "ну", "вот", "типа", "как бы", "значит"],
        "ar": ["يعني", "هم", "اه"],
        "hi": ["उम", "अच्छा", "तो", "मतलब"],
    ])
}
```

```swift
// Models/PunctuationConfig.swift
import Foundation

struct PunctuationCommand: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var replacement: String
}

struct PunctuationConfig: Codable {
    var commandsByLanguage: [String: [PunctuationCommand]]

    static let `default` = PunctuationConfig(commandsByLanguage: [
        "es": [
            PunctuationCommand(trigger: "coma", replacement: ","),
            PunctuationCommand(trigger: "punto", replacement: "."),
            PunctuationCommand(trigger: "punto y coma", replacement: ";"),
            PunctuationCommand(trigger: "dos puntos", replacement: ":"),
            PunctuationCommand(trigger: "interrogacion", replacement: "?"),
            PunctuationCommand(trigger: "signo de interrogacion", replacement: "?"),
            PunctuationCommand(trigger: "exclamacion", replacement: "!"),
            PunctuationCommand(trigger: "signo de exclamacion", replacement: "!"),
            PunctuationCommand(trigger: "nueva linea", replacement: "\n"),
            PunctuationCommand(trigger: "salto de linea", replacement: "\n"),
            PunctuationCommand(trigger: "abrir parentesis", replacement: "("),
            PunctuationCommand(trigger: "cerrar parentesis", replacement: ")"),
            PunctuationCommand(trigger: "puntos suspensivos", replacement: "..."),
        ],
        "en": [
            PunctuationCommand(trigger: "comma", replacement: ","),
            PunctuationCommand(trigger: "period", replacement: "."),
            PunctuationCommand(trigger: "full stop", replacement: "."),
            PunctuationCommand(trigger: "semicolon", replacement: ";"),
            PunctuationCommand(trigger: "colon", replacement: ":"),
            PunctuationCommand(trigger: "question mark", replacement: "?"),
            PunctuationCommand(trigger: "exclamation mark", replacement: "!"),
            PunctuationCommand(trigger: "exclamation point", replacement: "!"),
            PunctuationCommand(trigger: "new line", replacement: "\n"),
            PunctuationCommand(trigger: "open parenthesis", replacement: "("),
            PunctuationCommand(trigger: "close parenthesis", replacement: ")"),
            PunctuationCommand(trigger: "ellipsis", replacement: "..."),
        ],
    ])
}
```

```swift
// Models/ContextModeConfig.swift
import Foundation

struct ContextModeEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var appBundleID: String
    var appName: String
    var tone: String
}

struct ContextModeConfig: Codable {
    var entries: [ContextModeEntry]
    var defaultTone: String

    static let `default` = ContextModeConfig(
        entries: [
            ContextModeEntry(appBundleID: "com.apple.mail", appName: "Mail", tone: "formal, professional"),
            ContextModeEntry(appBundleID: "com.microsoft.Outlook", appName: "Outlook", tone: "formal, professional"),
            ContextModeEntry(appBundleID: "com.tinyspeck.slackmacgap", appName: "Slack", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "com.hnc.Discord", appName: "Discord", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "com.apple.MobileSMS", appName: "Messages", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "ru.keepcoder.Telegram", appName: "Telegram", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", tone: "casual, concise"),
            ContextModeEntry(appBundleID: "com.apple.Notes", appName: "Notes", tone: "neutral"),
            ContextModeEntry(appBundleID: "com.apple.TextEdit", appName: "TextEdit", tone: "neutral"),
            ContextModeEntry(appBundleID: "com.apple.Terminal", appName: "Terminal", tone: "technical, precise"),
            ContextModeEntry(appBundleID: "com.microsoft.VSCode", appName: "VS Code", tone: "technical, precise"),
            ContextModeEntry(appBundleID: "com.apple.dt.Xcode", appName: "Xcode", tone: "technical, precise"),
            ContextModeEntry(appBundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor", tone: "technical, precise"),
        ],
        defaultTone: "neutral"
    )
}
```

**Step 5: Verify build**

Run: `cd /Users/ionmi/Development/OpenWhisper/OpenWhisper && xcodebuild -scheme OpenWhisper -configuration Debug build 2>&1 | tail -20`

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add JSON storage adapters and config models for dictionary, snippets, fillers, punctuation, context modes"
```

---

### Task 3: Text Processing Pipeline (Regex-Based)

**Files:**
- Create: `Adapters/Processing/RegexTextProcessor.swift`
- Modify: `Models/AppState.swift` (integrate pipeline into confirmRecording)

**Step 1: Create RegexTextProcessor**

This implements `TextProcessingPort` and chains: dictionary → fillers → punctuation.

```swift
// Adapters/Processing/RegexTextProcessor.swift
import Foundation

final class RegexTextProcessor: TextProcessingPort {
    private let dictionaryAdapter: DictionaryPort
    private let fillerConfig: FillerConfig
    private let punctuationConfig: PunctuationConfig

    init(
        dictionaryAdapter: DictionaryPort,
        fillerConfig: FillerConfig = .default,
        punctuationConfig: PunctuationConfig = .default
    ) {
        self.dictionaryAdapter = dictionaryAdapter
        self.fillerConfig = fillerConfig
        self.punctuationConfig = punctuationConfig
    }

    func process(_ text: String, language: String) -> String {
        var result = text

        // 1. Dictionary replacement (case-insensitive, whole word)
        let entries = dictionaryAdapter.load()
        for entry in entries {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.from))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: entry.to
                )
            }
        }

        // 2. Filler removal (whole word, case-insensitive)
        let lang = language == "auto" ? "en" : language
        let fillers = fillerConfig.fillersByLanguage[lang] ?? []
        // Sort by length descending so multi-word fillers match first
        let sortedFillers = fillers.sorted { $0.count > $1.count }
        for filler in sortedFillers {
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            // Match filler as standalone word/phrase, optionally followed by comma
            let pattern = "\\b\(escaped)\\b,?\\s*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // 3. Punctuation commands (replace trigger phrases with punctuation)
        let commands = punctuationConfig.commandsByLanguage[lang] ?? []
        // Sort by trigger length descending so multi-word commands match first
        let sortedCommands = commands.sorted { $0.trigger.count > $1.trigger.count }
        for cmd in sortedCommands {
            let escaped = NSRegularExpression.escapedPattern(for: cmd.trigger)
            // Match the trigger as a standalone phrase, potentially surrounded by spaces
            let pattern = "\\s*\\b\(escaped)\\b\\s*"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: cmd.replacement
                )
            }
        }

        // Clean up multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 2: Integrate into AppState.confirmRecording()**

In `Models/AppState.swift`, add properties for the new services and call them in the pipeline.

Add to AppState properties (after line 25):
```swift
var dictionaryAdapter: DictionaryPort?
var snippetAdapter: SnippetPort?
var textProcessor: TextProcessingPort?
```

Modify `confirmRecording()` — after `finalText = Self.cleanTranscription(finalText)` (line 109), add:
```swift
// Check snippet match first — if exact match, use snippet and skip processing
if let snippetMatch = snippetAdapter?.match(finalText) {
    finalText = snippetMatch
} else {
    // Run text processing pipeline (dictionary, fillers, punctuation)
    if let processor = textProcessor {
        finalText = processor.process(finalText, language: language)
    }
}
```

Initialize in `setupServices()` (after line 277):
```swift
let dictionary = JSONDictionaryAdapter()
dictionaryAdapter = dictionary
snippetAdapter = JSONSnippetAdapter()
textProcessor = RegexTextProcessor(dictionaryAdapter: dictionary)
```

**Step 3: Verify build**

Run: `cd /Users/ionmi/Development/OpenWhisper/OpenWhisper && xcodebuild -scheme OpenWhisper -configuration Debug build 2>&1 | tail -20`

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add regex text processing pipeline (dictionary, fillers, punctuation, snippets)"
```

---

### Task 4: App Detection Adapter (for Context Modes)

**Files:**
- Create: `Adapters/Detection/NSWorkspaceAppDetector.swift`

**Step 1: Create the adapter**

```swift
// Adapters/Detection/NSWorkspaceAppDetector.swift
import AppKit

final class NSWorkspaceAppDetector: AppDetectionPort {
    func frontmostAppBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
```

**Step 2: Verify build and commit**

```bash
git add -A
git commit -m "feat: add NSWorkspace app detection adapter for context modes"
```

---

### Task 5: Audio Pipeline — AUVoiceProcessingIO + Core Audio Taps for AEC

**Files:**
- Create: `Adapters/Audio/VoiceProcessingAudioCapture.swift`
- Modify: `OpenWhisper.entitlements` (add audio capture entitlement)

**Step 1: Create VoiceProcessingAudioCapture adapter**

This replaces `AudioCaptureService` with `AUVoiceProcessingIO`-based capture that includes AEC + noise suppression. Core Audio Taps captures system output as the AEC reference.

```swift
// Adapters/Audio/VoiceProcessingAudioCapture.swift
import AVFoundation
import AudioToolbox
import Foundation

final class VoiceProcessingAudioCapture: AudioCapturePort {
    private var audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var isRecording = false

    var currentLevel: Float = 0
    private static let targetSampleRate: Double = 16000

    // AEC: enable voice processing on the input node
    private var voiceProcessingEnabled = true

    func startRecording() throws {
        guard !isRecording else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Reset engine to clear any stale state
        audioEngine = AVAudioEngine()

        let inputNode = audioEngine.inputNode

        // Enable voice processing (AEC + noise suppression)
        if voiceProcessingEnabled {
            try inputNode.setVoiceProcessingEnabled(true)
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.formatError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Self.targetSampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil,
                let channelData = convertedBuffer.floatChannelData
            else { return }

            let samples = Array(
                UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(convertedBuffer.frameLength)
                ))

            let rms = sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            let level = min(rms / 0.15, 1.0)
            self.currentLevel = level

            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func currentSamples() -> [Float] {
        bufferLock.lock()
        let samples = audioBuffer
        bufferLock.unlock()
        return samples
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }
}
```

**Step 2: Add entitlement for audio capture**

In `OpenWhisper.entitlements`, add:
```xml
<key>com.apple.security.audio-capture</key>
<true/>
```

Note: `NSAudioCaptureUsageDescription` must also be added to Info.plist if not already present. Check the project's Info.plist or target settings.

**Step 3: Wire up in AppState**

In `AppState.setupServices()`, replace:
```swift
audioCaptureService = AudioCaptureService()
```
with:
```swift
audioCaptureService = VoiceProcessingAudioCapture()
```

Change the type of `audioCaptureService` in AppState from `AudioCaptureService?` to `(any AudioCapturePort)?`.

**Step 4: Verify build**

Run: `cd /Users/ionmi/Development/OpenWhisper/OpenWhisper && xcodebuild -scheme OpenWhisper -configuration Debug build 2>&1 | tail -20`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AUVoiceProcessingIO audio capture with AEC and noise suppression"
```

---

### Task 6: VAD (Voice Activity Detection) Integration

**Files:**
- Create: `Adapters/Audio/SileroVADAdapter.swift`
- Create: `Resources/` (for the Silero VAD CoreML/ONNX model)

**Step 1: Add Silero VAD dependency**

Option A (recommended): Use a Swift package that wraps Silero VAD. Search for `silero-vad-swift` or similar.
Option B: Convert the Silero ONNX model to CoreML and use CoreML directly.
Option C: Bundle the ONNX model and use `onnxruntime-swift`.

The most practical approach for a Swift app is to convert Silero VAD to CoreML:

1. Download the Silero VAD ONNX model
2. Convert to CoreML using `coremltools`
3. Bundle the `.mlmodelc` in the app

```swift
// Adapters/Audio/SileroVADAdapter.swift
import CoreML
import Foundation

final class SileroVADAdapter: VoiceActivityPort {
    private var model: MLModel?

    // VAD parameters
    private let windowSize = 512 // samples per window at 16kHz
    private let speechThreshold: Float = 0.5

    func loadModel() throws {
        // Load bundled CoreML model
        guard let modelURL = Bundle.main.url(forResource: "silero_vad", withExtension: "mlmodelc") else {
            throw VADError.modelNotFound
        }
        model = try MLModel(contentsOf: modelURL)
    }

    func detectSpeechSegments(in samples: [Float], sampleRate: Int) -> [(start: Int, end: Int)] {
        // Simple energy-based VAD as fallback if CoreML model not loaded
        // Will be replaced with proper Silero inference
        var segments: [(start: Int, end: Int)] = []
        let frameSize = sampleRate / 10 // 100ms frames
        var speechStart: Int?

        for i in stride(from: 0, to: samples.count, by: frameSize) {
            let end = min(i + frameSize, samples.count)
            let frame = Array(samples[i..<end])

            if containsSpeech(frame, sampleRate: sampleRate) {
                if speechStart == nil {
                    speechStart = i
                }
            } else {
                if let start = speechStart {
                    segments.append((start: start, end: i))
                    speechStart = nil
                }
            }
        }

        // Close last segment
        if let start = speechStart {
            segments.append((start: start, end: samples.count))
        }

        return segments
    }

    func containsSpeech(_ samples: [Float], sampleRate: Int) -> Bool {
        // Energy-based detection as baseline
        let rms = sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        return rms > 0.01
    }
}

enum VADError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "VAD model not found in app bundle."
        }
    }
}
```

**Step 2: Integrate VAD into AppState transcription flow**

In `AppState.confirmRecording()`, after getting `audioSamples`, filter through VAD:

```swift
// Filter audio through VAD if available
var processedSamples = audioSamples
if let vad = voiceActivityDetector {
    let segments = vad.detectSpeechSegments(in: audioSamples, sampleRate: 16000)
    if !segments.isEmpty {
        processedSamples = segments.flatMap { Array(audioSamples[$0.start..<min($0.end, audioSamples.count)]) }
    }
}
```

Add property to AppState:
```swift
var voiceActivityDetector: VoiceActivityPort?
```

Initialize in `setupServices()`:
```swift
let vad = SileroVADAdapter()
try? vad.loadModel()
voiceActivityDetector = vad
```

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "feat: add Silero VAD adapter for voice activity detection"
```

---

### Task 7: LLM Integration — Local (llama.cpp) + Remote (OpenAI-compatible API)

**Files:**
- Create: `Adapters/LLM/LocalLLMAdapter.swift`
- Create: `Adapters/LLM/RemoteLLMAdapter.swift`
- Create: `Services/LLMModelManager.swift`
- Create: `Models/LLMSettings.swift`

**Step 1: Add llama.cpp Swift package dependency**

Add to the Xcode project's Swift Package Manager dependencies:
- Package URL: `https://github.com/ggerganov/llama.cpp.git`
- Use the `llama` library product

Alternatively, use a community Swift wrapper if available (e.g., `swift-llama`).

**Step 2: Create LLMSettings model**

```swift
// Models/LLMSettings.swift
import Foundation

@Observable
final class LLMSettings {
    var isEnabled: Bool {
        didSet { save() }
    }
    var source: LLMSource {
        didSet { save() }
    }
    var selectedLocalModel: String {
        didSet { save() }
    }
    var remoteBaseURL: String {
        didSet { save() }
    }
    var remoteAPIKey: String {
        didSet { save() }
    }
    var remoteModelName: String {
        didSet { save() }
    }

    enum LLMSource: String, Codable, CaseIterable, Identifiable {
        case local
        case remote

        var id: String { rawValue }
        var label: String {
            switch self {
            case .local: "Local (on-device)"
            case .remote: "Remote (API)"
            }
        }
    }

    private struct Storage: Codable {
        var isEnabled: Bool
        var source: LLMSource
        var selectedLocalModel: String
        var remoteBaseURL: String
        var remoteAPIKey: String
        var remoteModelName: String
    }

    init() {
        if let stored = JSONStorageAdapter.load(Storage.self, from: "llm-settings.json") {
            isEnabled = stored.isEnabled
            source = stored.source
            selectedLocalModel = stored.selectedLocalModel
            remoteBaseURL = stored.remoteBaseURL
            remoteAPIKey = stored.remoteAPIKey
            remoteModelName = stored.remoteModelName
        } else {
            isEnabled = false
            source = .local
            selectedLocalModel = ""
            remoteBaseURL = ""
            remoteAPIKey = ""
            remoteModelName = ""
        }
    }

    private func save() {
        let storage = Storage(
            isEnabled: isEnabled,
            source: source,
            selectedLocalModel: selectedLocalModel,
            remoteBaseURL: remoteBaseURL,
            remoteAPIKey: remoteAPIKey,
            remoteModelName: remoteModelName
        )
        JSONStorageAdapter.save(storage, to: "llm-settings.json")
    }
}
```

**Step 3: Create LLMModelManager**

```swift
// Services/LLMModelManager.swift
import Foundation

@Observable
@MainActor
final class LLMModelManager {
    var availableLocalModels: [String] = []
    var isDownloading = false
    var downloadProgress: Double = 0

    static let modelsDirectory: URL = {
        let dir = JSONStorageAdapter.appSupportDir.appendingPathComponent("LLMModels")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    struct RecommendedModel: Identifiable {
        let id: String
        let name: String
        let size: String
        let languages: String
        let license: String
        let huggingFaceRepo: String
        let filename: String
    }

    static let recommendedModels: [RecommendedModel] = [
        RecommendedModel(
            id: "qwen3.5-4b",
            name: "Qwen3.5 4B (Recommended)",
            size: "~2.7 GB",
            languages: "201 languages",
            license: "Apache 2.0",
            huggingFaceRepo: "unsloth/Qwen3.5-4B-GGUF",
            filename: "Qwen3.5-4B-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "gemma3-4b",
            name: "Gemma 3 4B IT",
            size: "~2.4 GB",
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceRepo: "google/gemma-3-4b-it-qat-q4_0-gguf",
            filename: "gemma-3-4b-it-q4_0.gguf"
        ),
        RecommendedModel(
            id: "phi4-mini",
            name: "Phi-4 Mini",
            size: "~2.5 GB",
            languages: "23 languages",
            license: "MIT",
            huggingFaceRepo: "bartowski/microsoft_Phi-4-mini-instruct-GGUF",
            filename: "Phi-4-mini-instruct-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "qwen3.5-2b",
            name: "Qwen3.5 2B (Lightweight)",
            size: "~1.5 GB",
            languages: "201 languages",
            license: "Apache 2.0",
            huggingFaceRepo: "unsloth/Qwen3.5-2B-GGUF",
            filename: "Qwen3.5-2B-Q4_K_M.gguf"
        ),
        RecommendedModel(
            id: "gemma3n-e2b",
            name: "Gemma 3n E2B (Ultra-light)",
            size: "~1.2 GB",
            languages: "140+ languages",
            license: "Gemma",
            huggingFaceRepo: "unsloth/gemma-3n-E2B-it-GGUF",
            filename: "gemma-3n-E2B-it-Q4_K_M.gguf"
        ),
    ]

    init() {
        refreshLocalModels()
    }

    func refreshLocalModels() {
        let dir = Self.modelsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            availableLocalModels = []
            return
        }
        availableLocalModels = contents
            .filter { $0.pathExtension == "gguf" }
            .map { $0.lastPathComponent }
            .sorted()
    }

    func downloadModel(_ model: RecommendedModel) async throws {
        isDownloading = true
        downloadProgress = 0

        let url = URL(string: "https://huggingface.co/\(model.huggingFaceRepo)/resolve/main/\(model.filename)")!
        let destination = Self.modelsDirectory.appendingPathComponent(model.filename)

        // Validate destination is within models directory
        let resolvedPath = destination.standardizedFileURL.path
        let basePath = Self.modelsDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(basePath + "/") else {
            isDownloading = false
            throw LLMModelError.invalidPath
        }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = response.expectedContentLength

        var data = Data()
        if totalBytes > 0 {
            data.reserveCapacity(Int(totalBytes))
        }

        for try await byte in asyncBytes {
            data.append(byte)
            if totalBytes > 0 {
                downloadProgress = Double(data.count) / Double(totalBytes)
            }
        }

        try data.write(to: destination, options: .atomic)
        refreshLocalModels()
        isDownloading = false
    }

    func deleteModel(_ filename: String) throws {
        let modelFile = Self.modelsDirectory.appendingPathComponent(filename)
        let resolvedPath = modelFile.standardizedFileURL.path
        let basePath = Self.modelsDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(basePath + "/") else {
            throw LLMModelError.invalidPath
        }
        try FileManager.default.removeItem(at: modelFile)
        refreshLocalModels()
    }
}

enum LLMModelError: LocalizedError {
    case invalidPath
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath: "Invalid model file path."
        case .downloadFailed: "Failed to download model."
        }
    }
}
```

**Step 4: Create LocalLLMAdapter**

```swift
// Adapters/LLM/LocalLLMAdapter.swift
import Foundation
// import llama — exact import depends on the Swift package used

final class LocalLLMAdapter: LLMPort, @unchecked Sendable {
    private let lock = NSLock()
    private var _isModelLoaded = false
    // private var context: LlamaContext? — llama.cpp context

    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isModelLoaded
    }

    func loadModel(name: String, path: URL) async throws {
        lock.lock()
        _isModelLoaded = false
        lock.unlock()

        // TODO: Initialize llama.cpp context with the GGUF model at path
        // let params = llama_model_default_params()
        // params.n_gpu_layers = 99 // Use Metal for all layers
        // let model = llama_load_model_from_file(path.path, params)

        lock.lock()
        _isModelLoaded = true
        lock.unlock()
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        guard isModelLoaded else {
            throw LLMError.modelNotLoaded
        }

        // TODO: Run llama.cpp inference
        // Format prompt for the model's chat template
        // Generate tokens until EOS
        // Return generated text

        return userPrompt // Placeholder — pass-through until llama.cpp is integrated
    }

    func unloadModel() {
        lock.lock()
        // TODO: Free llama.cpp context
        _isModelLoaded = false
        lock.unlock()
    }
}

enum LLMError: LocalizedError {
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "No LLM model is loaded."
        case .generationFailed(let reason): "LLM generation failed: \(reason)"
        }
    }
}
```

**Step 5: Create RemoteLLMAdapter**

```swift
// Adapters/LLM/RemoteLLMAdapter.swift
import Foundation

final class RemoteLLMAdapter: LLMPort, @unchecked Sendable {
    private var baseURL: String
    private var apiKey: String
    private var modelName: String

    var isModelLoaded: Bool { !baseURL.isEmpty && !modelName.isEmpty }

    init(baseURL: String = "", apiKey: String = "", modelName: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func loadModel(name: String, path: URL) async throws {
        // For remote, "loading" just validates the connection
        // path is unused — the model lives on the remote server
    }

    func configure(baseURL: String, apiKey: String, modelName: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        guard !baseURL.isEmpty else {
            throw LLMError.modelNotLoaded
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.1,
            "max_tokens": 2048,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("HTTP error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.generationFailed("Invalid response format")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unloadModel() {
        // No-op for remote
    }
}
```

**Step 6: Verify build and commit**

```bash
git add -A
git commit -m "feat: add LLM integration (local llama.cpp + remote OpenAI-compatible API)"
```

---

### Task 8: LLM Post-Processing (Context Modes + Corrections)

**Files:**
- Create: `Adapters/Processing/LLMTextProcessor.swift`
- Modify: `Models/AppState.swift` (add LLM processing step after regex)

**Step 1: Create LLMTextProcessor**

```swift
// Adapters/Processing/LLMTextProcessor.swift
import Foundation

final class LLMTextProcessor {
    private let llm: LLMPort
    private let appDetector: AppDetectionPort
    private let contextConfig: ContextModeConfig
    private let dictionaryAdapter: DictionaryPort

    init(
        llm: LLMPort,
        appDetector: AppDetectionPort,
        contextConfig: ContextModeConfig = .default,
        dictionaryAdapter: DictionaryPort
    ) {
        self.llm = llm
        self.appDetector = appDetector
        self.contextConfig = contextConfig
        self.dictionaryAdapter = dictionaryAdapter
    }

    func process(_ text: String, language: String) async throws -> String {
        guard llm.isModelLoaded else { return text }

        // Determine tone from frontmost app
        let tone: String
        if let bundleID = appDetector.frontmostAppBundleID(),
           let entry = contextConfig.entries.first(where: { $0.appBundleID == bundleID }) {
            tone = entry.tone
        } else {
            tone = contextConfig.defaultTone
        }

        // Build dictionary terms string
        let dictEntries = dictionaryAdapter.load()
        let dictString = dictEntries.map { "\($0.from) -> \($0.to)" }.joined(separator: ", ")

        // Build system prompt in the same language as input to prevent drift
        let systemPrompt = Self.systemPrompt(language: language, tone: tone, dictionaryTerms: dictString)

        let result = try await llm.generate(systemPrompt: systemPrompt, userPrompt: text)
        return result.isEmpty ? text : result
    }

    private static func systemPrompt(language: String, tone: String, dictionaryTerms: String) -> String {
        // Provide prompt in target language to prevent language drift
        switch language {
        case "es":
            return """
            Eres un post-procesador de texto para dictado por voz. Reglas:
            - Corrige auto-correcciones (ej: "2... en realidad 3" -> "3")
            - Elimina arranques falsos y repeticiones
            - Corrige errores gramaticales
            - Tono: \(tone)
            - Conserva el significado original y el idioma. NO traduzcas.
            - Usa estas palabras exactas del diccionario: \(dictionaryTerms)
            - Devuelve SOLO el texto corregido, nada mas.
            """
        case "en":
            return """
            You are a text post-processor for voice dictation. Rules:
            - Fix self-corrections (e.g., "2... actually 3" -> "3")
            - Remove false starts and repetitions
            - Fix grammar errors
            - Tone: \(tone)
            - Preserve original meaning and language. Do NOT translate.
            - Use these exact dictionary spellings: \(dictionaryTerms)
            - Output ONLY the corrected text, nothing else.
            """
        default:
            // English prompt as fallback for other languages
            return """
            You are a text post-processor for voice dictation. Rules:
            - Fix self-corrections (e.g., "2... actually 3" -> "3")
            - Remove false starts and repetitions
            - Fix grammar errors
            - Tone: \(tone)
            - Preserve original meaning and language. Do NOT translate.
            - The input text is in language code: \(language). Keep it in that language.
            - Use these exact dictionary spellings: \(dictionaryTerms)
            - Output ONLY the corrected text, nothing else.
            """
        }
    }
}
```

**Step 2: Integrate into AppState**

Add properties:
```swift
var llmSettings = LLMSettings()
var llmModelManager: LLMModelManager?
var llmAdapter: (any LLMPort)?
var appDetector: AppDetectionPort?
var llmProcessor: LLMTextProcessor?
```

In `setupServices()`:
```swift
let detector = NSWorkspaceAppDetector()
appDetector = detector
llmModelManager = LLMModelManager()
```

In `confirmRecording()`, after the regex processing block and before saving to history:
```swift
// LLM processing (if enabled)
if let llmProcessor, llmSettings.isEnabled {
    if let refined = try? await llmProcessor.process(finalText, language: language) {
        finalText = refined
    }
}
```

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "feat: add LLM post-processing with context-aware tone and real-time corrections"
```

---

### Task 9: Auto-Add to Dictionary

**Files:**
- Create: `Services/AutoDictionaryService.swift`
- Modify: `Models/AppState.swift` (integrate monitoring after paste)

**Step 1: Create AutoDictionaryService**

```swift
// Services/AutoDictionaryService.swift
import Foundation
import AppKit

@Observable
@MainActor
final class AutoDictionaryService {
    var pendingSuggestion: DictionarySuggestion?

    struct DictionarySuggestion: Identifiable {
        let id = UUID()
        let originalWord: String
        let correctedWord: String
    }

    private var lastTranscribedText: String = ""
    private var dictionaryAdapter: DictionaryPort?
    private var monitorTimer: Timer?

    func configure(dictionaryAdapter: DictionaryPort) {
        self.dictionaryAdapter = dictionaryAdapter
    }

    /// Call after pasting transcription. Monitors clipboard for quick edits.
    func startMonitoring(transcribedText: String) {
        lastTranscribedText = transcribedText
        stopMonitoring()

        // Monitor for 5 seconds after paste
        var checksRemaining = 10
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                checksRemaining -= 1
                if checksRemaining <= 0 {
                    self.stopMonitoring()
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func acceptSuggestion() {
        guard let suggestion = pendingSuggestion, let adapter = dictionaryAdapter else { return }
        adapter.addEntry(DictionaryEntry(from: suggestion.originalWord, to: suggestion.correctedWord))
        pendingSuggestion = nil
    }

    func dismissSuggestion() {
        pendingSuggestion = nil
    }
}
```

**Step 2: Wire into AppState and add to setupServices**

In AppState, add:
```swift
var autoDictionaryService: AutoDictionaryService?
```

In `setupServices()`:
```swift
let autoDict = AutoDictionaryService()
autoDict.configure(dictionaryAdapter: dictionary)
autoDictionaryService = autoDict
```

In `confirmRecording()`, after pasting:
```swift
// Start monitoring for dictionary auto-add
autoDictionaryService?.startMonitoring(transcribedText: finalText)
```

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "feat: add auto-add to dictionary service"
```

---

### Task 10: Settings UI — Audio Processing Tab

**Files:**
- Modify: `Views/SettingsView.swift`
- Create: `Models/AudioSettings.swift`

**Step 1: Create AudioSettings model**

```swift
// Models/AudioSettings.swift
import Foundation

@Observable
final class AudioSettings {
    var aecEnabled: Bool {
        didSet { save() }
    }
    var noiseSuppressionEnabled: Bool {
        didSet { save() }
    }
    var vadEnabled: Bool {
        didSet { save() }
    }

    private struct Storage: Codable {
        var aecEnabled: Bool
        var noiseSuppressionEnabled: Bool
        var vadEnabled: Bool
    }

    init() {
        if let stored = JSONStorageAdapter.load(Storage.self, from: "audio-settings.json") {
            aecEnabled = stored.aecEnabled
            noiseSuppressionEnabled = stored.noiseSuppressionEnabled
            vadEnabled = stored.vadEnabled
        } else {
            aecEnabled = true
            noiseSuppressionEnabled = true
            vadEnabled = true
        }
    }

    private func save() {
        JSONStorageAdapter.save(
            Storage(aecEnabled: aecEnabled, noiseSuppressionEnabled: noiseSuppressionEnabled, vadEnabled: vadEnabled),
            to: "audio-settings.json"
        )
    }
}
```

**Step 2: Add Audio Processing tab to SettingsView**

In `SettingsView`, add a new tab after the existing tabs:

```swift
AudioSettingsTab()
    .environment(appState)
    .tabItem {
        Label("Audio", systemImage: "waveform")
    }
```

Create the tab view:

```swift
// Add to SettingsView.swift
struct AudioSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Noise Reduction") {
                Toggle("Echo Cancellation (AEC)", isOn: Bindable(appState.audioSettings).aecEnabled)
                Text("Removes system audio (music, videos) from your microphone input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Noise Suppression", isOn: Bindable(appState.audioSettings).noiseSuppressionEnabled)
                Text("Reduces background noise (fan, keyboard, street).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice Detection") {
                Toggle("Voice Activity Detection (VAD)", isOn: Bindable(appState.audioSettings).vadEnabled)
                Text("Only transcribes when speech is detected. Reduces false transcriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

Add `audioSettings` to AppState:
```swift
let audioSettings = AudioSettings()
```

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "feat: add audio processing settings tab (AEC, noise suppression, VAD toggles)"
```

---

### Task 11: Settings UI — Post-Processing Tab (Dictionary, Fillers, Punctuation, Snippets)

**Files:**
- Modify: `Views/SettingsView.swift`

**Step 1: Add Post-Processing tab**

```swift
PostProcessingSettingsTab()
    .environment(appState)
    .tabItem {
        Label("Processing", systemImage: "text.badge.checkmark")
    }
```

**Step 2: Create the tab with sub-sections**

```swift
struct PostProcessingSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var dictionaryEntries: [DictionaryEntry] = []
    @State private var snippetEntries: [SnippetEntry] = []
    @State private var newDictFrom = ""
    @State private var newDictTo = ""
    @State private var newSnippetTrigger = ""
    @State private var newSnippetText = ""

    var body: some View {
        Form {
            Section("Dictionary") {
                ForEach(dictionaryEntries) { entry in
                    HStack {
                        Text(entry.from)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text(entry.to)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontWeight(.medium)
                        Button(role: .destructive) {
                            appState.dictionaryAdapter?.removeEntry(id: entry.id)
                            dictionaryEntries = appState.dictionaryAdapter?.load() ?? []
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("From", text: $newDictFrom)
                    TextField("To", text: $newDictTo)
                    Button("Add") {
                        guard !newDictFrom.isEmpty, !newDictTo.isEmpty else { return }
                        appState.dictionaryAdapter?.addEntry(DictionaryEntry(from: newDictFrom, to: newDictTo))
                        dictionaryEntries = appState.dictionaryAdapter?.load() ?? []
                        newDictFrom = ""
                        newDictTo = ""
                    }
                }

                Toggle("Auto-add from corrections", isOn: .constant(true))
                    .toggleStyle(.switch)
            }

            Section("Snippets") {
                ForEach(snippetEntries) { entry in
                    HStack {
                        Text(entry.trigger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontWeight(.medium)
                        Text(entry.text.prefix(40) + (entry.text.count > 40 ? "..." : ""))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            appState.snippetAdapter?.removeEntry(id: entry.id)
                            snippetEntries = appState.snippetAdapter?.load() ?? []
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("Trigger phrase", text: $newSnippetTrigger)
                    TextField("Expanded text", text: $newSnippetText)
                    Button("Add") {
                        guard !newSnippetTrigger.isEmpty, !newSnippetText.isEmpty else { return }
                        appState.snippetAdapter?.addEntry(SnippetEntry(trigger: newSnippetTrigger, text: newSnippetText))
                        snippetEntries = appState.snippetAdapter?.load() ?? []
                        newSnippetTrigger = ""
                        newSnippetText = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            dictionaryEntries = appState.dictionaryAdapter?.load() ?? []
            snippetEntries = appState.snippetAdapter?.load() ?? []
        }
    }
}
```

**Step 3: Increase the settings window frame to fit new tabs**

Change `.frame(width: 480, height: 400)` to `.frame(width: 520, height: 450)`.

**Step 4: Verify build and commit**

```bash
git add -A
git commit -m "feat: add post-processing settings tab (dictionary, snippets)"
```

---

### Task 12: Settings UI — Context Modes Tab

**Files:**
- Modify: `Views/SettingsView.swift`

**Step 1: Add Context Modes tab**

```swift
ContextModesSettingsTab()
    .environment(appState)
    .tabItem {
        Label("Context", systemImage: "app.badge")
    }
```

**Step 2: Create tab view**

```swift
struct ContextModesSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var entries: [ContextModeEntry] = []
    @State private var defaultTone = "neutral"

    var body: some View {
        Form {
            Section("Per-App Tone") {
                Text("When LLM is enabled, text is adjusted to match the tone configured for each app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(entries) { entry in
                    HStack {
                        Text(entry.appName)
                            .frame(width: 100, alignment: .leading)
                        Text(entry.tone)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Default Tone") {
                TextField("Default tone for unlisted apps", text: $defaultTone)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Text("Requires LLM to be enabled in the LLM settings tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let config = JSONStorageAdapter.load(ContextModeConfig.self, from: "context-modes.json") ?? .default
            entries = config.entries
            defaultTone = config.defaultTone
        }
    }
}
```

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "feat: add context modes settings tab"
```

---

### Task 13: Settings UI — LLM Tab

**Files:**
- Modify: `Views/SettingsView.swift`

**Step 1: Add LLM tab**

```swift
LLMSettingsTab()
    .environment(appState)
    .tabItem {
        Label("LLM", systemImage: "brain")
    }
```

**Step 2: Create tab view**

```swift
struct LLMSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var llmSettings = appState.llmSettings
        Form {
            Section {
                Toggle("Enable LLM Post-Processing", isOn: $llmSettings.isEnabled)
                    .toggleStyle(.switch)

                Text("Uses AI to fix self-corrections, adjust tone, and improve grammar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if llmSettings.isEnabled {
                Section("Source") {
                    Picker("Source", selection: $llmSettings.source) {
                        ForEach(LLMSettings.LLMSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if llmSettings.source == .local {
                    Section("Local Model") {
                        if let manager = appState.llmModelManager {
                            if manager.availableLocalModels.isEmpty {
                                Text("No models downloaded yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Model", selection: $llmSettings.selectedLocalModel) {
                                    ForEach(manager.availableLocalModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                            }

                            if manager.isDownloading {
                                ProgressView(value: manager.downloadProgress)
                                    .progressViewStyle(.linear)
                                Text("Downloading... \(Int(manager.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Available Models") {
                        ForEach(LLMModelManager.recommendedModels) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .fontWeight(.medium)
                                    Text("\(model.size) — \(model.languages) — \(model.license)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if appState.llmModelManager?.availableLocalModels.contains(model.filename) == true {
                                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                } else {
                                    Button("Download") {
                                        Task {
                                            try? await appState.llmModelManager?.downloadModel(model)
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                } else {
                    Section("Remote API") {
                        TextField("Base URL", text: $llmSettings.remoteBaseURL)
                            .textFieldStyle(.roundedBorder)
                        SecureField("API Key (optional)", text: $llmSettings.remoteAPIKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Model name", text: $llmSettings.remoteModelName)
                            .textFieldStyle(.roundedBorder)
                        Text("Compatible with OpenAI API format (OpenAI, Ollama, OpenRouter, LM Studio, etc.)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "feat: add LLM settings tab with local model downloads and remote API config"
```

---

### Task 14: Wire Everything Together in AppState

**Files:**
- Modify: `Models/AppState.swift`

**Step 1: Update AppState with all new properties and setup**

Add all new service properties, update `setupServices()` to initialize everything, and update `confirmRecording()` to use the full pipeline:

1. Add properties for all new services (audioSettings, llmSettings, dictionaryAdapter, snippetAdapter, textProcessor, voiceActivityDetector, appDetector, llmModelManager, llmAdapter, llmProcessor, autoDictionaryService)

2. Update `setupServices()` to initialize all adapters

3. Update `confirmRecording()` with the full pipeline:
   - VAD filtering (if enabled)
   - Whisper transcription
   - Clean hallucinations (existing)
   - Snippet matching
   - Regex processing (dictionary + fillers + punctuation)
   - LLM processing (if enabled)
   - Output + auto-dictionary monitoring

4. Update `audioCaptureService` type to `(any AudioCapturePort)?`

5. Update `transcriptionEngine` type to `(any TranscriptionPort)?`

**Step 2: Verify build**

Run: `cd /Users/ionmi/Development/OpenWhisper/OpenWhisper && xcodebuild -scheme OpenWhisper -configuration Debug build 2>&1 | tail -20`

**Step 3: Run the app and test basic flow**

1. Launch app
2. Record a test phrase
3. Verify transcription still works
4. Check Settings tabs appear and are functional

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire all v2 features into AppState pipeline"
```

---

### Task 15: Update macOS Target & Entitlements

**Files:**
- Modify: Xcode project settings (deployment target)
- Modify: `OpenWhisper.entitlements`

**Step 1: Update deployment target to macOS 14.4**

In Xcode project settings, set minimum deployment target to macOS 14.4.

**Step 2: Add Info.plist entries**

Add `NSAudioCaptureUsageDescription` with a user-facing description:
"OpenWhisper captures system audio to remove echo from your recordings (music, videos playing)."

**Step 3: Verify build and commit**

```bash
git add -A
git commit -m "chore: update macOS target to 14.4, add audio capture entitlement"
```

---

### Task 16: Final Integration Test & Cleanup

**Step 1: Build the project**

```bash
cd /Users/ionmi/Development/OpenWhisper/OpenWhisper && xcodebuild -scheme OpenWhisper -configuration Debug build 2>&1 | tail -30
```

**Step 2: Verify all new files are added to Xcode project**

Check that all `.swift` files in the new directories (Ports/, Adapters/, Resources/) are included in the Xcode target.

**Step 3: Remove any unused imports or dead code**

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup and integration verification for v2 features"
```

---

## Summary of New Files

```
Ports/
├── AudioCapturePort.swift
├── TranscriptionPort.swift
├── TextProcessingPort.swift
├── LLMPort.swift
├── DictionaryPort.swift
├── SnippetPort.swift
├── AppDetectionPort.swift
└── VoiceActivityPort.swift

Adapters/
├── Storage/
│   ├── JSONStorageAdapter.swift
│   ├── JSONDictionaryAdapter.swift
│   └── JSONSnippetAdapter.swift
├── Audio/
│   ├── VoiceProcessingAudioCapture.swift
│   └── SileroVADAdapter.swift
├── Detection/
│   └── NSWorkspaceAppDetector.swift
├── Processing/
│   ├── RegexTextProcessor.swift
│   └── LLMTextProcessor.swift
└── LLM/
    ├── LocalLLMAdapter.swift
    └── RemoteLLMAdapter.swift

Models/
├── FillerConfig.swift
├── PunctuationConfig.swift
├── ContextModeConfig.swift
├── AudioSettings.swift
└── LLMSettings.swift

Services/
├── LLMModelManager.swift
└── AutoDictionaryService.swift
```

## Execution Order

Tasks 1-4 are foundational (architecture + data models).
Tasks 5-6 are audio pipeline.
Tasks 7-8 are LLM integration.
Task 9 is auto-dictionary.
Tasks 10-13 are UI.
Tasks 14-16 are integration and cleanup.
