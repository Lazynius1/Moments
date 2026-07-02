import Foundation

enum ChatScrollDebug {
    private static let prefix = "[ChatScroll]"

    static func log(_ message: String) {
        print("\(prefix) \(message)")
    }
}
