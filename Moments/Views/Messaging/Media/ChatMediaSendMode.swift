import Foundation

// Modo de envío de la cámara del chat, estilo Instagram: un botón cíclico
// rota entre ver una vez, permitir repetición y guardar en el chat.
enum ChatMediaSendMode: CaseIterable {
    case viewOnce
    case allowReplay
    case keepInChat

    var next: ChatMediaSendMode {
        switch self {
        case .viewOnce: return .allowReplay
        case .allowReplay: return .keepInChat
        case .keepInChat: return .viewOnce
        }
    }

    // Glifo interior del círculo punteado; viewOnce usa el texto "1".
    var innerSystemIcon: String? {
        switch self {
        case .viewOnce: return nil
        case .allowReplay: return "play.fill"
        case .keepInChat: return "square.and.arrow.down"
        }
    }

    var label: String {
        switch self {
        case .viewOnce:
            return NSLocalizedString("chat.camera.mode.viewOnce", comment: "View once send mode")
        case .allowReplay:
            return NSLocalizedString("chat.camera.mode.allowReplay", comment: "Allow replay send mode")
        case .keepInChat:
            return NSLocalizedString("chat.camera.mode.keepInChat", comment: "Keep in chat send mode")
        }
    }
}
