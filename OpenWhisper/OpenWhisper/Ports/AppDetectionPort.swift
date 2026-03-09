import Foundation

protocol AppDetectionPort {
    func frontmostAppBundleID() -> String?
    func frontmostAppName() -> String?
}
