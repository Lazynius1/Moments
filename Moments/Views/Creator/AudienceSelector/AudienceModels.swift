import FirebaseFirestore
import Foundation

enum ContentAudience: String, Codable, CaseIterable {
    case everyone = "everyone"
    case connections = "connections"
    case bestFriends = "bestFriends"
    case custom = "custom"
    case customList = "customList"
    case onlyMe = "onlyMe"

    var title: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone audience type")
        case .connections: return NSLocalizedString("audience.type.connections", comment: "Connections audience type")
        case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type")
        case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom audience type")
        case .customList: return NSLocalizedString("audience.type.customList", comment: "Custom list audience type")
        case .onlyMe: return NSLocalizedString("audience.type.onlyMe", comment: "Only me audience type")
        }
    }

    var description: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.description.everyone", comment: "Everyone audience description")
        case .connections: return NSLocalizedString("audience.description.connections", comment: "Connections audience description")
        case .bestFriends: return NSLocalizedString("audience.description.bestFriends", comment: "Best friends audience description")
        case .custom: return NSLocalizedString("audience.description.custom", comment: "Custom audience description")
        case .customList: return NSLocalizedString("audience.description.customList", comment: "Custom list audience description")
        case .onlyMe: return NSLocalizedString("audience.description.onlyMe", comment: "Only me audience description")
        }
    }

    var icon: String {
        switch self {
        case .everyone: return "globe"
        case .connections: return "person.2.fill"
        case .bestFriends: return "star.fill"
        case .custom: return "person.crop.circle.badge.plus"
        case .customList: return "list.bullet.rectangle"
        case .onlyMe: return "lock.fill"
        }
    }

    var assetName: String {
        switch self {
        case .everyone: return "AudienceEveryoneIcon"
        case .connections: return "AudienceMutualsIcon"
        case .bestFriends: return "AudienceBestFriendsIcon"
        case .custom: return "AudienceCustomIcon"
        case .customList: return "AudienceCustomListIcon"
        case .onlyMe: return "AudienceOnlyMeIcon"
        }
    }

    static func fromCaptionAudienceSetting(
        _ setting: CaptionAndDetailsView.AudienceSetting,
        hasCustomList: Bool
    ) -> ContentAudience {
        if setting == .custom && hasCustomList {
            return .customList
        }
        switch setting {
        case .everyone: return .everyone
        case .mutuals, .admirers: return .connections
        case .bestFriends: return .bestFriends
        case .custom: return .custom
        case .onlyMe: return .onlyMe
        }
    }

    static func fromAudienceValue(_ value: String?) -> ContentAudience {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "everyone"

        switch normalized {
        case "connections", "mutuals", "mutual", "admirers":
            return .connections
        case "bestfriends", "best_friends", "best-friends":
            return .bestFriends
        case "customlist":
            return .customList
        case "custom":
            return .custom
        case "onlyme", "only_me", "only-me":
            return .onlyMe
        default:
            return .everyone
        }
    }
}

struct CustomAudienceList: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let name: String
    let description: String?
    let members: [String]
    let createdAt: Date
    let updatedAt: Date
    let color: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case members
        case createdAt
        case updatedAt
        case color
        case icon
    }

    init(
        id: String? = nil,
        name: String,
        description: String? = nil,
        members: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        color: String? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.color = color
        self.icon = icon
    }

    static func == (lhs: CustomAudienceList, rhs: CustomAudienceList) -> Bool {
        lhs.id == rhs.id
    }
}

extension CustomAudienceList {
    static let predefinedColors = [
        "FF6B6B",
        "4ECDC4",
        "45B7D1",
        "FFA07A",
        "98D8C8",
        "F7DC6F",
        "BB8FCE",
        "85C1E2"
    ]

    static let predefinedIcons = [
        "person.3.fill",
        "briefcase.fill",
        "house.fill",
        "graduationcap.fill",
        "heart.fill",
        "star.fill",
        "flag.fill",
        "bolt.fill"
    ]
}
