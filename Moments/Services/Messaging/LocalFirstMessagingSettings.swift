import Foundation

enum LocalFirstMessagingSettings {
    private static let key = "useLocalFirstMessaging"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

extension Foundation.Notification.Name {
    static let messagesIngested = Foundation.Notification.Name("MessagesIngested")
}
