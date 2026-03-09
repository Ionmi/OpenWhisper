import AVFoundation
import Foundation

final class VoiceProcessingAudioCapture: AudioCapturePort {
    private var audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
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

        // Enable voice processing (AEC + noise suppression)
        try inputNode.setVoiceProcessingEnabled(true)

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
