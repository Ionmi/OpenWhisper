import Foundation

protocol LLMPort: Sendable {
    func loadModel(name: String, path: URL) async throws
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
    func warmUp(systemPrompt: String) async
    var isModelLoaded: Bool { get }
    func unloadModel()
}
