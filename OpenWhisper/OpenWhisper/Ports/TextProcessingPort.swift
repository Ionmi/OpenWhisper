import Foundation

protocol TextProcessingPort {
    func process(_ text: String, language: String) -> String
}
