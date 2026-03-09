import Foundation

protocol LLMPort: Sendable {
    func loadModel(name: String, path: URL) async throws
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
    var isModelLoaded: Bool { get }
    func unloadModel()
}
