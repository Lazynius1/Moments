import SwiftUI
import UIKit

// MARK: - Mantener el modelo ChatMessage igual
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    let image: UIImage? // ✅ NUEVO: Soporte para imágenes
    let isUser: Bool
    let timestamp: Date
    let isHistorical: Bool // ✅ NUEVO: Flag para mensajes históricos
    let isSystem: Bool // ✅ NUEVO: Flag para mensajes del sistema (como WhatsApp)

    init(text: String, isUser: Bool, image: UIImage? = nil, isHistorical: Bool = false, isSystem: Bool = false) {
        self.text = text
        self.image = image
        self.isUser = isUser
        self.timestamp = Date()
        self.isHistorical = isHistorical // ✅ Por defecto es nuevo mensaje
        self.isSystem = isSystem
    }

    static func ==(lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.text == rhs.text &&
               lhs.image == rhs.image &&
               lhs.isUser == rhs.isUser &&
               lhs.isHistorical == rhs.isHistorical &&
               lhs.isSystem == rhs.isSystem
    }
}
