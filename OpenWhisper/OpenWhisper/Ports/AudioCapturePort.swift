import Foundation

protocol AudioCapturePort: AnyObject {
    var currentLevel: Float { get }
    func startRecording() throws
    func stopRecording() -> [Float]
    func currentSamples() -> [Float]
}
