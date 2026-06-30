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

    var pinsToBottom: Bool {
        if case .bottom = self { return true }
        return false
    }
}

/// Ya no se persiste posición de scroll entre sesiones (paridad Instagram: cada apertura va al
/// fondo o al primer no leído). Solo se conserva la limpieza de claves antiguas para usuarios que
/// actualizan desde versiones que sí guardaban este estado.
enum ChatScrollStateStore {
    private static let keyPrefix = "chatScrollState"
    private static let defaults = UserDefaults.standard

    static func clear(for conversationId: String, userId: String? = Auth.auth().currentUser?.uid) {
        guard let key = storageKey(conversationId: conversationId, userId: userId) else { return }
        defaults.removeObject(forKey: key)
    }

    static func clearAll(userId: String? = Auth.auth().currentUser?.uid) {
        guard let userId, !userId.isEmpty else { return }
        let prefix = "\(keyPrefix).\(userId)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func storageKey(conversationId: String, userId: String?) -> String? {
        let cleanConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let userId, !userId.isEmpty, !cleanConversationId.isEmpty else { return nil }
        return "\(keyPrefix).\(userId).\(cleanConversationId)"
    }
}
