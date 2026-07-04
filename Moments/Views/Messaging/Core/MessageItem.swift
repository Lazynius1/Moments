import SwiftUI

enum MessageItem: Identifiable {
    case single(EnhancedMessage)
    case mediaCluster([EnhancedMessage])
    
    var id: String {
        switch self {
        case .single(let m): return m.id
        case .mediaCluster(let ms): return "cluster-" + ms.map(\.id).joined(separator: "-")
        }
    }
}

/// Fila renderizable del chat: cabecera de fecha o un mensaje/cluster.
enum ChatRenderRow: Identifiable {
    case header(Date)
    case message(MessageItem)
    case buzz(ChatBuzzEvent)
    case typing
    case historyStart

    var id: String {
        switch self {
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
