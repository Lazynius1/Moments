import Foundation
import FirebaseFirestore

enum AccountHistoryEventType: String, Codable, CaseIterable {
    case join = "join"
    case username = "username"
    case bio = "bio"
    case website = "website"
    case privacy = "privacy"
    
    var localizedName: String {
        switch self {
        case .join: return NSLocalizedString("accountHistory.type.join", comment: "")
        case .username: return NSLocalizedString("accountHistory.type.username", comment: "")
        case .bio: return NSLocalizedString("accountHistory.type.bio", comment: "")
        case .website: return NSLocalizedString("accountHistory.type.website", comment: "")
        case .privacy: return NSLocalizedString("accountHistory.type.privacy", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .join: return "person.badge.plus"
        case .username: return "person.text.rectangle"
        case .bio: return "text.alignleft"
        case .website: return "link"
        case .privacy: return "lock"
        }
    }
}

struct AccountHistoryItem: Identifiable, Codable {
    @DocumentID var id: String?
    let type: AccountHistoryEventType
    let oldValue: String?
    let newValue: String?
    let timestamp: Date

    init(id: String? = nil, type: AccountHistoryEventType, oldValue: String? = nil, newValue: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = timestamp
    }
}
