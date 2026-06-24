import Foundation
import FirebaseAuth

enum ChatScrollTarget: Equatable, Codable {
    case bottom(messageId: String)
    case firstUnread(messageId: String)
    case highlightedMessage(messageId: String)

    private enum Kind: String, Codable {
        case bottom
        case firstUnread
        case highlightedMessage
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case messageId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let messageId = try container.decode(String.self, forKey: .messageId)
        switch kind {
        case .bottom:
            self = .bottom(messageId: messageId)
        case .firstUnread:
            self = .firstUnread(messageId: messageId)
        case .highlightedMessage:
            self = .highlightedMessage(messageId: messageId)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bottom(let messageId):
            try container.encode(Kind.bottom, forKey: .kind)
            try container.encode(messageId, forKey: .messageId)
        case .firstUnread(let messageId):
            try container.encode(Kind.firstUnread, forKey: .kind)
            try container.encode(messageId, forKey: .messageId)
        case .highlightedMessage(let messageId):
            try container.encode(Kind.highlightedMessage, forKey: .kind)
            try container.encode(messageId, forKey: .messageId)
        }
    }

    var isFirstUnread: Bool {
        if case .firstUnread = self { return true }
        return false
    }

    var isHighlightedMessage: Bool {
        if case .highlightedMessage = self { return true }
        return false
    }

    var pinsToBottom: Bool {
        if case .bottom = self { return true }
        return false
    }
}

enum ChatScrollStateStore {
    struct State: Equatable, Codable {
        var hasCompletedInitialScroll = false
        var frozenInitialScrollTarget: ChatScrollTarget?
        var isPinnedToBottom = true
        var didProcessNotificationBuzz = false
        var scrollAnchorId: String?
        var scrollOffsetY: Double?
    }

    private static let keyPrefix = "chatScrollState"
    private static let defaults = UserDefaults.standard
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static var lastWrittenPayload: [String: Data] = [:]

    static func state(for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) -> State {
        guard let key = storageKey(conversationId: conversationId, userId: userId),
              let data = defaults.data(forKey: key),
              let decoded = try? decoder.decode(State.self, from: data) else {
            return State()
        }
        return decoded
    }

    static func update(
        for conversationId: String,
        userId: String? = Auth.auth().currentUser?.uid,
        _ update: (inout State) -> Void
    ) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        var current = state(for: conversationId, userId: userId)
        update(&current)
        guard let data = try? encoder.encode(current) else { return }
        if lastWrittenPayload[key] == data { return }
        defaults.set(data, forKey: key)
        lastWrittenPayload[key] = data
    }

    static func shouldRunInitialScroll(
        for conversationId: String,
        hasHighlightIntent: Bool,
        userId: String? = Auth.auth().currentUser?.uid
    ) -> Bool {
        if hasHighlightIntent { return true }
        let stored = state(for: conversationId, userId: userId)
        return !stored.hasCompletedInitialScroll
    }

    static func clear(for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        defaults.removeObject(forKey: key)
        lastWrittenPayload.removeValue(forKey: key)
    }

    static func clearAll(userId: String? = Auth.auth().currentUser?.uid) {
        guard let userId, !userId.isEmpty else { return }
        let prefix = "\(keyPrefix).\(userId)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
            lastWrittenPayload.removeValue(forKey: key)
        }
    }

    private static func storageKey(conversationId: String, userId: String?) -> String? {
        let cleanConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId, !userId.isEmpty, !cleanConversationId.isEmpty else { return nil }
        return "\(keyPrefix).\(userId).\(cleanConversationId)"
    }
}
