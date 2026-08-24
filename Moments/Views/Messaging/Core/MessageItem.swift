import SwiftUI

enum MessageItem: Identifiable {
    case single(EnhancedMessage)
    case mediaCluster([EnhancedMessage])
    
    var id: String {
        switch self {
        case .single(let m): return m.id
        // El último mensaje no cambia cuando una página anterior amplía el álbum por delante.
        // Así el prepend conserva la identidad de la fila visible.
        case .mediaCluster(let ms): return "cluster-" + (ms.last?.id ?? "empty")
        }
    }
}

/// Fila renderizable del chat: cabecera de fecha o un mensaje/cluster.
enum ChatRenderRow: Identifiable {
    case conversationIntro(PendingChatContext?)
    case requestDisclaimer(PendingChatContext?)
    case pendingRequestMessage(PendingChatTimelineMessage)
    case incomingRequestActions(isLoading: Bool)
    case outgoingRequestControls(messageCount: Int, limitReached: Bool)
    case header(Date)
    case message(MessageItem)
    case buzz(ChatBuzzEvent)
    case typing
    case historyStart

    var id: String {
        switch self {
        case .conversationIntro(let context): return "row:synthetic:conversation-intro:\(context?.id ?? "normal")"
        case .requestDisclaimer(let context): return "row:synthetic:request-disclaimer:\(context?.id ?? "normal")"
        case .pendingRequestMessage(let message): return "row:pending-request:\(message.id)"
        case .incomingRequestActions: return "row:synthetic:incoming-request-actions"
        case .outgoingRequestControls: return "row:synthetic:outgoing-request-controls"
        case .header(let date): return "row:header:\(date.timeIntervalSince1970)"
        case .message(let item): return "row:message:\(item.id)"
        case .buzz(let event): return "row:buzz:\(event.id)"
        case .typing: return "row:synthetic:typing-indicator"
        case .historyStart: return "row:synthetic:history-start"
        }
    }
}

struct ChatTimelineSection: Identifiable {
    let date: Date
    var rows: [ChatRenderRow]

    var id: String {
        "section-\(date.timeIntervalSince1970)"
    }
}
