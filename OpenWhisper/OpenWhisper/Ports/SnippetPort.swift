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
