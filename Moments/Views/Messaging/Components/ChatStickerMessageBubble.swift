import SwiftUI

/// Burbuja para stickers: flota sobre el fondo del chat, SIN burbuja glass (estilo IG DM).
struct ChatStickerMessageBubble: View {
    @ObservedObject var message: EnhancedMessage
    let isSending: Bool
    let progress: Double?

    @Environment(\.colorScheme) private var colorScheme

    private let stickerSize: CGFloat = 140

    private var stickerURL: URL? {
        guard let urlString = message.mediaUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        ZStack {
            if let stickerURL, !message.isMediaPendingResolution {
                AnimatedGIFView(url: stickerURL)
                    .id(stickerURL.absoluteString)
                    .frame(width: stickerSize, height: stickerSize)
                    .clipped()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.4))
                    .frame(width: stickerSize, height: stickerSize)
            }

            if isSending {
                ProgressView(value: progress ?? 0)
                    .progressViewStyle(.circular)
                    .tint(colorScheme == .dark ? .white : .black)
            }
        }
        .frame(width: stickerSize, height: stickerSize)
        .opacity(isSending ? 0.7 : 1)
    }
}
