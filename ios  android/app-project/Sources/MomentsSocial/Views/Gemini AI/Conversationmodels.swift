import Foundation

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
    
    init(id: String = UUID().uuidString, text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
    
    // Convertir desde ChatMessage
    init(from chatMessage: ChatMessage) {
        self.id = chatMessage.id.uuidString
        self.text = chatMessage.text
        self.isUser = chatMessage.isUser
    }
    
    // Para Firestore
    var dictionary: [String: Any] {
        return [
            "id": id,
            "text": text,
            "isUser": isUser,
        ]
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
    }
    
    // Convertir a ChatMessage
    func toChatMessage() -> ChatMessage {
        
        let chatMessage = ChatMessage(text: text, isUser: isUser, isHistorical: true)
        
        
        return chatMessage
    }
}

// MARK: - Extensiones para facilitar conversiones
extension Array where Element == ChatMessage {
    func toSavedMessages() -> [SavedChatMessage] {
        return self.map { SavedChatMessage(from: $0) }
    }
}

extension Array where Element == SavedChatMessage {
    func toChatMessages() -> [ChatMessage] {
        return self.map { $0.toChatMessage() }
    }
}
