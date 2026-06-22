import SwiftUI
import Kingfisher

// MARK: - Momento efímero en chat (diseño propio: ámbar/dorado, sin anillo story ni view-once)

enum ChatEphemeralLayout {
    case compact
    case standard

    var width: CGFloat {
        switch self {
        case .compact: return 76
        case .standard: return 188
        }
    }

    var height: CGFloat {
        switch self {
        case .compact: return 118
        case .standard: return 240
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 14
        case .standard: return 18
        }
    }

    var iconPreset: AttachmentIconPreset {
        switch self {
        case .compact: return .storyEphemeral
        case .standard: return .chatEphemeralPlaceholder
        }
    }
}

enum ChatEphemeralTimeFormatting {
    static func remainingSeconds(until expirationDate: Date, now: Date = Date()) -> TimeInterval {
        max(0, expirationDate.timeIntervalSince(now))
    }

    static func shortLabel(for remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 24 {
            return "\(hours / 24)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    static func shortLabel(until expirationDate: Date, now: Date = Date()) -> String {
        shortLabel(for: remainingSeconds(until: expirationDate, now: now))
    }
}

private enum ChatEphemeralPalette {
    static let accent = Color(hex: "FFCC33")
    static let accentSecondary = Color(hex: "FF9500")

    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "1C1C1E"),
                Color(hex: "2A2418")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentBorder: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct ChatEphemeralMessageContent: View {
    @ObservedObject var message: EnhancedMessage
    let layout: ChatEphemeralLayout
    var onHydrateMedia: ((EnhancedMessage) -> Void)?
    var onOpenMedia: ((EnhancedMessage) -> Void)?
    @State private var showContent = false

    @Environment(\.colorScheme) private var colorScheme

    private var previewImageURL: String? {
        message.thumbnailUrl ?? message.mediaUrl
    }

    private var resolvedMediaURL: URL? {
        if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
            return url
        }
        if let thumbnailUrl = message.thumbnailUrl, let url = URL(string: thumbnailUrl) {
            return url
        }
        return nil
    }

    var body: some View {
        Group {
            if message.isDeleted || !isEphemeralValid() {
                ChatEphemeralExpiredCard(layout: layout)
            } else if !showContent && !message.isViewed {
                ChatEphemeralTapCard(
                    layout: layout,
                    previewImageURL: previewImageURL,
                    expirationDate: message.expirationDate
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        showContent = true
                    }
                    onHydrateMedia?(message)
                    markAsViewedIfNeeded()
                }
            } else if let url = resolvedMediaURL {
                ChatEphemeralImageCard(
                    layout: layout,
                    imageUrl: url,
                    expirationDate: message.expirationDate
                ) {
                    onOpenMedia?(message)
                }
            } else if message.isMediaPendingResolution {
                ChatEphemeralResolvingCard(layout: layout)
            } else {
                ChatEphemeralExpiredCard(layout: layout)
            }
        }
        .onAppear {
            showContent = message.isViewed
            onHydrateMedia?(message)
        }
    }

    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }

    private func markAsViewedIfNeeded() {
        guard !message.isViewed else { return }
        ChatService().markEphemeralAsViewed(
            conversationId: message.conversationId,
            messageId: message.id
        ) { _ in }
    }
}

struct ChatEphemeralTapCard: View {
    let layout: ChatEphemeralLayout
    let previewImageURL: String?
    let expirationDate: Date?
    let onTap: () -> Void

    var body: some View {
        ZStack {
            chatEphemeralBackdrop

            Color.black.opacity(colorScheme == .dark ? 0.42 : 0.32)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                AttachmentIconView(
                    icon: .ephemeral,
                    preset: layout.iconPreset,
                    tintColor: ChatEphemeralPalette.accent.opacity(0.95)
                )
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text("chat.tapToView")
                        .font(.custom("Poppins-SemiBold", size: layout == .compact ? 11 : 13))
                        .foregroundColor(.white)

                    Text("chat.ephemeral.title")
                        .font(.custom("Poppins-Regular", size: layout == .compact ? 10 : 11))
                        .foregroundColor(.white.opacity(0.78))

                    if let expirationDate, expirationDate > Date() {
                        Text(
                            String(
                                format: NSLocalizedString("stories.expiresIn", comment: ""),
                                ChatEphemeralTimeFormatting.shortLabel(until: expirationDate)
                            )
                        )
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(ChatEphemeralPalette.accent.opacity(0.9))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, layout == .compact ? 10 : 14)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .stroke(ChatEphemeralPalette.accentBorder, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    private var chatEphemeralBackdrop: some View {
        if let previewImageURL,
           !previewImageURL.isEmpty,
           let url = URL(string: previewImageURL),
           url.isFileURL || url.scheme?.hasPrefix("http") == true {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .blur(radius: layout == .compact ? 18 : 24)
                .saturation(0.65)
        } else {
            ChatEphemeralPalette.cardGradient
        }
    }
}

struct ChatEphemeralImageCard: View {
    let layout: ChatEphemeralLayout
    let imageUrl: URL
    let expirationDate: Date?
    let onTap: () -> Void

    var body: some View {
        KFImage(imageUrl)
            .resizable()
            .scaledToFill()
            .frame(width: layout.width, height: layout.height)
            .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let expirationDate, expirationDate > Date() {
                    Text(ChatEphemeralTimeFormatting.shortLabel(until: expirationDate))
                        .font(.custom("Poppins-Medium", size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.55))
                                .overlay(
                                    Capsule()
                                        .stroke(ChatEphemeralPalette.accent.opacity(0.5), lineWidth: 0.5)
                                )
                        )
                        .padding(8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                    .stroke(ChatEphemeralPalette.accent.opacity(0.45), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
            .onTapGesture(perform: onTap)
    }
}

struct ChatEphemeralResolvingCard: View {
    let layout: ChatEphemeralLayout

    var body: some View {
        ZStack {
            ChatEphemeralPalette.cardGradient

            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: ChatEphemeralPalette.accent))
                Text("common.loading")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .stroke(ChatEphemeralPalette.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

struct ChatEphemeralExpiredCard: View {
    let layout: ChatEphemeralLayout

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))

            VStack(spacing: 8) {
                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(.system(size: layout == .compact ? 18 : 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))

                Text("stories.ephemeral.expired")
                    .font(.custom("Poppins-Medium", size: layout == .compact ? 10 : 12))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
