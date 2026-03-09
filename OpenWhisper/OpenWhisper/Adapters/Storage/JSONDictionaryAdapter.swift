import Foundation

final class JSONDictionaryAdapter: DictionaryPort {
    private let filename = "dictionary.json"
    private var entries: [DictionaryEntry] = []

    init() {
        entries = load()
        if entries.isEmpty {
            entries = Self.defaultEntries
            save(entries)
        }
    }

    func load() -> [DictionaryEntry] {
        JSONStorageAdapter.load([DictionaryEntry].self, from: filename) ?? []
    }

    func save(_ entries: [DictionaryEntry]) {
        self.entries = entries
        JSONStorageAdapter.save(entries, to: filename)
    }

    func addEntry(_ entry: DictionaryEntry) {
        entries.append(entry)
        save(entries)
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save(entries)
    }

    static let defaultEntries: [DictionaryEntry] = [
        DictionaryEntry(from: "git ignore", to: ".gitignore"),
        DictionaryEntry(from: "gitignore", to: ".gitignore"),
        DictionaryEntry(from: "javascript", to: "JavaScript"),
        DictionaryEntry(from: "typescript", to: "TypeScript"),
        DictionaryEntry(from: "node js", to: "Node.js"),
        DictionaryEntry(from: "next js", to: "Next.js"),
        DictionaryEntry(from: "react js", to: "React.js"),
        DictionaryEntry(from: "vue js", to: "Vue.js"),
        DictionaryEntry(from: "npm", to: "npm"),
        DictionaryEntry(from: "api", to: "API"),
        DictionaryEntry(from: "json", to: "JSON"),
        DictionaryEntry(from: "html", to: "HTML"),
        DictionaryEntry(from: "css", to: "CSS"),
        DictionaryEntry(from: "github", to: "GitHub"),
        DictionaryEntry(from: "webpack", to: "webpack"),
        DictionaryEntry(from: "localhost", to: "localhost"),
        DictionaryEntry(from: "sql", to: "SQL"),
        DictionaryEntry(from: "graphql", to: "GraphQL"),
    ]
}
