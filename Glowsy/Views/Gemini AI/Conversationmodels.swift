import Foundation
import UIKit
import FirebaseFirestore

// MARK: - Modelo de Título de Conversación
struct ConversationTitle: Identifiable, Codable {
    let id: String
    let title: String
    let lastUpdated: Date
    let messageCount: Int
    let userId: String

    init(id: String = UUID().uuidString, title: String, lastUpdated: Date = Date(), messageCount: Int, userId: String) {
        self.id = id
        self.title = title
        self.lastUpdated = lastUpdated
        self.messageCount = messageCount
        self.userId = userId
    }

    // Para Firestore
    var dictionary: [String: Any] {
        return [
            "id": id,
            "title": title,
            "lastUpdated": Timestamp(date: lastUpdated),
            "messageCount": messageCount,
            "userId": userId
        ]
    }

    // Desde Firestore
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let title = dictionary["title"] as? String,
              let timestamp = dictionary["lastUpdated"] as? Timestamp,
              let messageCount = dictionary["messageCount"] as? Int,
              let userId = dictionary["userId"] as? String else {
            return nil
        }

        self.id = id
        self.title = title
        self.lastUpdated = timestamp.dateValue()
        self.messageCount = messageCount
        self.userId = userId
    }
}

// MARK: - Modelo de Conversación Completa
struct SavedConversation: Identifiable, Codable {
    let id: String
    let title: String
    let messages: [SavedChatMessage]
    let createdAt: Date
    let lastUpdated: Date
    let userId: String

    init(id: String = UUID().uuidString, title: String, messages: [SavedChatMessage], createdAt: Date = Date(), lastUpdated: Date = Date(), userId: String) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.userId = userId
    }

    // Para Firestore
    var dictionary: [String: Any] {
        return [
            "id": id,
            "title": title,
            "messages": messages.map { $0.dictionary },
            "createdAt": Timestamp(date: createdAt),
            "lastUpdated": Timestamp(date: lastUpdated),
            "userId": userId
        ]
    }

    // Desde Firestore
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let title = dictionary["title"] as? String,
              let messagesArray = dictionary["messages"] as? [[String: Any]],
              let createdTimestamp = dictionary["createdAt"] as? Timestamp,
              let lastUpdatedTimestamp = dictionary["lastUpdated"] as? Timestamp,
              let userId = dictionary["userId"] as? String else {
            return nil
        }

        let messages = messagesArray.compactMap { SavedChatMessage(dictionary: $0) }

        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdTimestamp.dateValue()
        self.lastUpdated = lastUpdatedTimestamp.dateValue()
        self.userId = userId
    }
}

// MARK: - Modelo de Mensaje Guardado
struct SavedChatMessage: Identifiable, Codable {
    let id: String
    let text: String
    let isUser: Bool
    let imageData: String?

    init(id: String = UUID().uuidString, text: String, isUser: Bool, imageData: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.imageData = imageData
    }

    // Convertir desde ChatMessage
    init(from chatMessage: ChatMessage) {
        self.id = chatMessage.id.uuidString
        self.text = chatMessage.text
        self.isUser = chatMessage.isUser
        self.imageData = Self.encodeImage(chatMessage.image)
    }

    // Para Firestore
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "text": text,
            "isUser": isUser,
        ]

        if let imageData {
            dict["imageData"] = imageData
        }

        return dict
    }

    // Desde Firestore
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let text = dictionary["text"] as? String,
              let isUser = dictionary["isUser"] as? Bool else {

            return nil
        }

        self.id = id
        self.text = text
        self.isUser = isUser
        self.imageData = dictionary["imageData"] as? String
    }

    // Convertir a ChatMessage
    func toChatMessage() -> ChatMessage {
        let image = Self.decodeImage(imageData)
        return ChatMessage(text: text, isUser: isUser, image: image, isHistorical: true)
    }

    private static func encodeImage(_ image: UIImage?) -> String? {
        guard let image else { return nil }

        let resized = resizeImageIfNeeded(image, maxDimension: 1400)
        if let jpegData = resized.jpegData(compressionQuality: 0.72) {
            return jpegData.base64EncodedString()
        }
        if let pngData = resized.pngData() {
            return pngData.base64EncodedString()
        }
        return nil
    }

    private static func decodeImage(_ base64: String?) -> UIImage? {
        guard let base64,
              let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    private static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let currentMax = max(size.width, size.height)
        guard currentMax > maxDimension, currentMax > 0 else { return image }

        let scale = maxDimension / currentMax
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Extensiones para facilitar conversiones
extension Array where Element == ChatMessage {
    func toSavedMessages() -> [SavedChatMessage] {
        // ✅ NO GUARDAR MENSAJES DEL SISTEMA (se generan automáticamente)
        return self.filter { !$0.isSystem }.map { SavedChatMessage(from: $0) }
    }
}

extension Array where Element == SavedChatMessage {
    func toChatMessages() -> [ChatMessage] {
        return self.map { $0.toChatMessage() }
    }
}
