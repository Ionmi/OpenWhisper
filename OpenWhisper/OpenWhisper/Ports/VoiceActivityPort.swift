import Foundation

protocol VoiceActivityPort {
    func loadModel() throws
    func detectSpeechSegments(in samples: [Float], sampleRate: Int) -> [(start: Int, end: Int)]
    func containsSpeech(_ samples: [Float], sampleRate: Int) -> Bool
}
