import SwiftUI

/// Icono del tipo de mensaje en solicitudes y previews.
/// Usa assets custom cuando existen; si no, cae a SF Symbol.
struct MessageTypeIconView: View {
    let type: MessageType
    var tintColor: Color = .secondary
    var fontWeight: Font.Weight = .regular

    var body: some View {
        if let icon = type.attachmentIcon {
            AttachmentIconView(icon: icon, preset: .messageRequestRow, tintColor: tintColor)
        } else {
            Image(systemName: type.iconName)
                .font(.system(size: AttachmentIconMetrics.messageRequestRow, weight: fontWeight))
                .foregroundStyle(tintColor)
        }
    }
}

extension MessageType {
    var attachmentIcon: AttachmentIcon? {
        switch self {
        case .gif:
            return .gif
        case .location:
            return .location
        case .image:
            return .photos
        case .ephemeral, .viewOnceImage, .viewOnceVideo:
            return .ephemeral
        case .sharedMoment, .sharedProfile:
            return .share
        default:
            return nil
        }
    }
}
