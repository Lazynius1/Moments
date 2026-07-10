import SwiftUI
import UIKit

struct NovaGroundingSource: Identifiable, Codable, Equatable, Hashable {
    let title: String
    let url: String

    var id: String { url }
}

struct NovaGroundingPayload: Codable, Equatable {
    let sources: [NovaGroundingSource]
    let searchSuggestionsHTML: String?
}

// MARK: - Mantener el modelo ChatMessage igual
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    let image: UIImage? // ✅ NUEVO: Soporte para imágenes
    let imageStoragePath: String?
    let isUser: Bool
    let timestamp: Date
    let isHistorical: Bool // ✅ NUEVO: Flag para mensajes históricos
    let isSystem: Bool // Flag para mensajes del sistema
    var groundingSources: [NovaGroundingSource]
    var searchSuggestionsHTML: String?

    init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        image: UIImage? = nil,
        imageStoragePath: String? = nil,
        isHistorical: Bool = false,
        isSystem: Bool = false,
        groundingSources: [NovaGroundingSource] = [],
        searchSuggestionsHTML: String? = nil
    ) {
        self.id = id
        self.text = text
        self.image = image
        self.imageStoragePath = imageStoragePath
        self.isUser = isUser
        self.timestamp = Date()
        self.isHistorical = isHistorical // ✅ Por defecto es nuevo mensaje
        self.isSystem = isSystem
        self.groundingSources = groundingSources
        self.searchSuggestionsHTML = searchSuggestionsHTML
    }

    static func ==(lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.image == rhs.image &&
               lhs.imageStoragePath == rhs.imageStoragePath &&
               lhs.isUser == rhs.isUser &&
               lhs.isHistorical == rhs.isHistorical &&
               lhs.isSystem == rhs.isSystem &&
               lhs.groundingSources == rhs.groundingSources &&
               lhs.searchSuggestionsHTML == rhs.searchSuggestionsHTML
    }
}
