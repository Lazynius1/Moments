import SwiftUI

/// Burbuja para mensajes GIF: animación en bucle con chrome mínimo (estilo IG DM).
struct ChatGifMessageBubble: View {
    @ObservedObject var message: EnhancedMessage
    let progress: Double?

    @Environment(\.colorScheme) private var colorScheme

    private var isSending: Bool { message.status == .sending }

    private var gifURL: URL? {
        guard let urlString = message.mediaUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    private var aspectRatio: CGFloat {
        // Sin metadatos de tamaño usamos un ratio agradable por defecto.
        return 1.0
    }

    var body: some View {
        ZStack {
            if let gifURL, !message.isMediaPendingResolution {
                AnimatedGIFView(url: gifURL)
                    .id(gifURL.absoluteString)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(width: 200, height: 200)
                    .overlay {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.4))
                    }
            }

            if isSending {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .overlay {
                        ProgressView(value: progress ?? 0)
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
            }
        }
    }
}
