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

    var id: String {
        switch self {
        case .header(let date): return "header-\(date.timeIntervalSince1970)"
        case .message(let item): return item.id
        case .buzz(let event): return "buzz-\(event.id)"
        }
    }
}
