import Foundation

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
}

protocol DictionaryPort {
    func load() -> [DictionaryEntry]
    func save(_ entries: [DictionaryEntry])
    func addEntry(_ entry: DictionaryEntry)
    func removeEntry(id: UUID)
}
