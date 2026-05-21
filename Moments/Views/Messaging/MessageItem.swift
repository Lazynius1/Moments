import SwiftUI

enum MessageItem: Identifiable {
    case single(EnhancedMessage)
    case mediaCluster([EnhancedMessage])
    
    var id: String {
        switch self {
        case .single(let m): return m.id
        case .mediaCluster(let ms): return ms.first?.id ?? UUID().uuidString
        }
    }
}
