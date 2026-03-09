import Foundation

final class JSONSnippetAdapter: SnippetPort {
    private let filename = "snippets.json"
    private var entries: [SnippetEntry] = []

    init() { entries = load() }

    func load() -> [SnippetEntry] {
        JSONStorageAdapter.load([SnippetEntry].self, from: filename) ?? []
    }

    func save(_ entries: [SnippetEntry]) {
        self.entries = entries
        JSONStorageAdapter.save(entries, to: filename)
    }

    func addEntry(_ entry: SnippetEntry) {
        entries.append(entry)
        save(entries)
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save(entries)
    }

    func match(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.first { $0.trigger.lowercased() == trimmed }?.text
    }
}
