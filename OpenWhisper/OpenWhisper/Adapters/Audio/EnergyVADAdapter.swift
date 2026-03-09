import Foundation

final class EnergyVADAdapter: VoiceActivityPort {
    private let speechThreshold: Float = 0.01
    private let frameDurationMs: Int = 100
    /// Extra samples to keep after each speech segment ends (prevents cutting last words)
    private let tailMarginMs: Int = 300

    func loadModel() throws {
        // Energy-based VAD — no model file needed
    }

    func detectSpeechSegments(in samples: [Float], sampleRate: Int) -> [(start: Int, end: Int)] {
        var segments: [(start: Int, end: Int)] = []
        let frameSize = sampleRate * frameDurationMs / 1000
        let tailMargin = sampleRate * tailMarginMs / 1000
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
                    segments.append((start: start, end: min(i + tailMargin, samples.count)))
                    speechStart = nil
                }
            }
        }

        if let start = speechStart {
            segments.append((start: start, end: samples.count))
        }

        // Merge overlapping segments caused by tail margin
        guard !segments.isEmpty else { return segments }
        var merged: [(start: Int, end: Int)] = [segments[0]]
        for seg in segments.dropFirst() {
            if seg.start <= merged[merged.count - 1].end {
                merged[merged.count - 1] = (start: merged[merged.count - 1].start, end: max(merged[merged.count - 1].end, seg.end))
            } else {
                merged.append(seg)
            }
        }

        return merged
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
