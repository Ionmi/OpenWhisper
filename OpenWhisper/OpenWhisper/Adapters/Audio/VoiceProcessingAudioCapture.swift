import AVFoundation
import Foundation
import os

final class VoiceProcessingAudioCapture: AudioCapturePort {
    private var audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = OSAllocatedUnfairLock()
    private var isRecording = false

    var currentLevel: Float = 0
    private static let targetSampleRate: Double = 16000

    func startRecording() throws {
        guard !isRecording else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        // Reset engine to clear any stale state
        audioEngine = AVAudioEngine()

        let inputNode = audioEngine.inputNode

        // Reference the output node so the engine knows about both I/O endpoints.
        // VPIO is a bidirectional unit and needs the output path to exist.
        _ = audioEngine.outputNode
        audioEngine.mainMixerNode.outputVolume = 0

        // Enable voice processing (AEC + noise suppression).
        // Must happen BEFORE reading inputNode format — VPIO changes it.
        do {
            try inputNode.setVoiceProcessingEnabled(true)

            // Disable audio ducking — VPIO ducks other apps by default
            inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
        } catch {
            #if DEBUG
            print("[VoiceProcessingAudioCapture] Voice processing unavailable: \(error)")
            #endif
        }

        let rawFormat = inputNode.outputFormat(forBus: 0)
        guard rawFormat.sampleRate > 0, rawFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        // VPIO outputs multi-channel (e.g. 9ch). Request mono in the tap so
        // AVAudioEngine downmixes to the voice-processed signal automatically.
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rawFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
            throw AudioCaptureError.formatError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: monoFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Self.targetSampleRate / monoFormat.sampleRate
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
                convertedBuffer.frameLength > 0,
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

        // Disable voice processing on a detached task so it doesn't block
        // the caller. Use .default priority to match the QoS of the audio
        // threads this call synchronises with, avoiding priority inversion.
        let engine = audioEngine
        Task.detached(priority: .medium) {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            engine.reset()
        }

        isRecording = false

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }
}
