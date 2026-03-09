import Foundation

final class SileroVADAdapter: VoiceActivityPort {
    private let speechThreshold: Float = 0.01
    private let frameDurationMs: Int = 100

    func loadModel() throws {
        // Energy-based VAD — no model file needed
        // Future: load Silero ONNX/CoreML model here
    }

    func detectSpeechSegments(in samples: [Float], sampleRate: Int) -> [(start: Int, end: Int)] {
        var segments: [(start: Int, end: Int)] = []
        let frameSize = sampleRate * frameDurationMs / 1000
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

        if let start = speechStart {
            segments.append((start: start, end: samples.count))
        }

        return segments
    }

    func containsSpeech(_ samples: [Float], sampleRate: Int) -> Bool {
        let rms = sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        return rms > speechThreshold
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
