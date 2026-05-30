import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Combine

struct NotificationGroup: Identifiable {
    let id: String
    let notifications: [Notification]
    var isUnread: Bool {
        notifications.contains { $0.isPending }
    }
}
