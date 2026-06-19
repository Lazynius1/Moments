import SwiftUI

enum ChatGifLayout {
    static let maxWidth: CGFloat = 240
    static let maxHeight: CGFloat = 280
    static let minSide: CGFloat = 100
    static let fallbackSize = CGSize(width: 200, height: 150)

    static func displaySize(width: Int?, height: Int?) -> CGSize {
        guard let width, let height, width > 0, height > 0 else {
            return fallbackSize
        }

        let ratio = CGFloat(width) / CGFloat(height)
        var displayW: CGFloat
        var displayH: CGFloat

        if ratio >= 1 {
            displayW = min(CGFloat(width), maxWidth)
            displayH = displayW / ratio
            if displayH > maxHeight {
                displayH = maxHeight
                displayW = displayH * ratio
            }
        } else {
            displayH = min(CGFloat(height), maxHeight)
            displayW = displayH * ratio
            if displayW > maxWidth {
                displayW = maxWidth
                displayH = displayW / ratio
            }
        }

        displayW = max(displayW, minSide)
        displayH = max(displayH, minSide)
        return CGSize(width: displayW.rounded(), height: displayH.rounded())
    }
}

/// Burbuja para mensajes GIF: animación en bucle con chrome mínimo (estilo IG DM).
struct ChatGifMessageBubble: View {
    @ObservedObject var message: EnhancedMessage
    let progress: Double?

    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedIntrinsicSize: CGSize?

    private var isSending: Bool { message.status == .sending }

    private var gifURL: URL? {
        guard let urlString = message.mediaUrl, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    private var displaySize: CGSize {
        if let loadedIntrinsicSize {
            return ChatGifLayout.displaySize(
                width: Int(loadedIntrinsicSize.width.rounded()),
                height: Int(loadedIntrinsicSize.height.rounded())
            )
        }
        return ChatGifLayout.displaySize(width: message.mediaWidth, height: message.mediaHeight)
    }

    var body: some View {
        ZStack {
            if let gifURL, !message.isMediaPendingResolution {
                AnimatedGIFView(url: gifURL, onIntrinsicSize: { size in
                    guard size.width > 0, size.height > 0 else { return }
                    loadedIntrinsicSize = size
                })
                .id(gifURL.absoluteString)
                .frame(width: displaySize.width, height: displaySize.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(width: displaySize.width, height: displaySize.height)
                    .overlay {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.4))
                    }
            }

            if isSending {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: displaySize.width, height: displaySize.height)
                    .overlay {
                        ProgressView(value: progress ?? 0)
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
            }
        }
        .fixedSize()
    }
}
