import Foundation

struct TranscriptionResult: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let duration: TimeInterval

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
