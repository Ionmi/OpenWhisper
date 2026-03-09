import AVFoundation
import Foundation

final class AudioCaptureService {
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var isRecording = false

    /// Current audio level (0.0–1.0), updated from the audio tap.
    var currentLevel: Float = 0

    private static let targetSampleRate: Double = 16000

    func startRecording() throws {
        guard !isRecording else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        // Create output format at 16kHz mono Float32 for Whisper
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        // Create converter from input format to 16kHz mono
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

            // Compute RMS audio level for visual feedback
            let rms = sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            // Map RMS to 0–1 range (typical speech RMS is 0.01–0.3)
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

    /// Returns a snapshot of the current audio buffer without stopping recording.
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

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case formatError
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device found."
        case .formatError:
            return "Failed to configure audio format."
        case .permissionDenied:
            return "Microphone permission denied."
        }
    }
}
