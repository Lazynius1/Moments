import SwiftUI
import Kingfisher
import AVFoundation
import AVKit
import FirebaseAuth

// MARK: - View-Once Message Bubble
struct ViewOnceMessageBubble: View {
    @ObservedObject var message: EnhancedMessage
    let isCurrentUser: Bool
    let otherParticipantName: String
    let progress: Double? // ✅ New: Real-time upload progress
    var onOpenViewer: ((Bool) -> Void)? = nil
    var zoomNamespace: Namespace.ID? = nil
    var zoomSourceID: String? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var shimmerOffset: CGFloat = -1

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var replayAvailable: Bool {
        message.allowReplay == true
            && message.replayAvailableInCurrentChatSession
            && !message.replayConsumedInCurrentChatSession
            && !message.hasBeenReplayedBy(userId: currentUserId)
    }

    private var effectiveViewed: Bool {
        message.isViewed || message.replayAvailableInCurrentChatSession
    }
    
    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            if isCurrentUser {
                // Mensaje del usuario actual - muestra estado
                ViewOnceSentBubble(
                    message: message,
                    progress: progress,
                    adaptiveColors: adaptiveColors
                )
            } else {
                // Caso Receptor: Unread, Replay disponible u Opened
                ZStack(alignment: isCurrentUser ? .trailing : .leading) {
                    ViewOnceOpenedBubble(
                        message: message,
                        adaptiveColors: adaptiveColors
                    )
                    .opacity(effectiveViewed && !replayAvailable ? 1 : 0)

                    ViewOnceReplayBubble(
                        message: message,
                        adaptiveColors: adaptiveColors,
                        onTap: { openReplay() }
                    )
                    .opacity(effectiveViewed && replayAvailable ? 1 : 0)
                    .allowsHitTesting(effectiveViewed && replayAvailable)

                    ViewOnceUnreadBubble(
                        message: message,
                        adaptiveColors: adaptiveColors,
                        onTap: {
                            openViewOnceMessage()
                        }
                    )
                    .opacity(effectiveViewed ? 0 : 1)
                    .allowsHitTesting(!effectiveViewed)
                }
            }
        }
        .modifier(ViewOnceZoomSourceModifier(namespace: zoomNamespace, sourceID: zoomSourceID))
    }

    private func openViewOnceMessage() {
        // ✅ Solo se puede abrir si NO ha sido visto
        guard !effectiveViewed else {
            return
        }

        onOpenViewer?(false)
    }

    private func openReplay() {
        guard replayAvailable else {
            return
        }
        onOpenViewer?(true)
    }
}

private struct ViewOnceZoomSourceModifier: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String?

    func body(content: Content) -> some View {
        if let namespace, let sourceID {
            content.matchedTransitionSource(id: sourceID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        } else {
            content
        }
    }
}

// Píldora compacta compartida por los estados del view-once.
private struct ViewOncePillBubble: View {
    let adaptiveColors: AdaptiveColors
    let glyph: AnyView
    let label: String
    var labelWeight: Font.Weight = .semibold
    var labelOpacity: CGFloat = 1.0
    var showsDashedRing = true
    var showsUnreadDot = false

    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if showsDashedRing {
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7))
                        .frame(width: 30, height: 30)
                }
                glyph
            }
            .frame(width: 30, height: 30)

            Text(label)
                .font(.system(size: legacyPoppinsSize(14), weight: labelWeight))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(labelOpacity))

            if showsUnreadDot {
                Circle()
                    .fill(signatureGradient)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(adaptiveColors.messageBubbleBackground.opacity(0.3))
            }
        )
        .overlay(
            Capsule().stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.8)
        )
    }
}

private func viewOnceTypeText(for message: EnhancedMessage) -> String {
    switch message.type {
    case .viewOnceImage:
        return NSLocalizedString("chat.viewOnce.photo", comment: "")
    case .viewOnceVideo:
        return NSLocalizedString("chat.viewOnce.video", comment: "")
    default:
        return NSLocalizedString("chat.viewOnce.media", comment: "")
    }
}

// MARK: - Simplified View-Once Unread Bubble
struct ViewOnceUnreadBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ViewOncePillBubble(
                adaptiveColors: adaptiveColors,
                glyph: AnyView(
                    Image(systemName: message.type == .viewOnceVideo ? "play.fill" : "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(adaptiveColors.messageTextColor)
                ),
                label: viewOnceTypeText(for: message),
                showsUnreadDot: true
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - View-Once Replay Bubble (allow replay: una repetición disponible)
struct ViewOnceReplayBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ViewOncePillBubble(
                adaptiveColors: adaptiveColors,
                glyph: AnyView(
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(adaptiveColors.messageTextColor)
                ),
                label: NSLocalizedString("chat.viewOnce.tapToReplay", comment: "Tap to replay")
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - View-Once Opened Bubble
struct ViewOnceOpenedBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors

    var body: some View {
        ViewOncePillBubble(
            adaptiveColors: adaptiveColors,
            glyph: AnyView(
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.4))
            ),
            label: NSLocalizedString("chat.viewOnce.alreadyViewed", comment: "Already viewed"),
            labelWeight: .medium,
            labelOpacity: 0.45
        )
    }
}

// MARK: - View-Once Sent Bubble
struct ViewOnceSentBubble: View {
    let message: EnhancedMessage
    let progress: Double? // ✅ New
    let adaptiveColors: AdaptiveColors

    private var statusText: String {
        if message.isViewed {
            if message.allowReplay == true, message.replayedBy?.isEmpty == false {
                return NSLocalizedString("chat.viewOnce.replayed", comment: "Replayed")
            }
            return NSLocalizedString("chat.viewOnce.viewed", comment: "Viewed")
        }
        return viewOnceTypeText(for: message)
    }

    var body: some View {
        ZStack {
            ViewOncePillBubble(
                adaptiveColors: adaptiveColors,
                glyph: AnyView(
                    Group {
                        if message.status == .sending, let uploadProgress = progress {
                            MediaProgressRing(progress: uploadProgress, size: 26, lineWidth: 2)
                        } else if message.isViewed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
                        } else {
                            Image(systemName: message.type == .viewOnceVideo ? "play.fill" : "camera.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(adaptiveColors.messageTextColor)
                        }
                    }
                ),
                label: statusText,
                labelWeight: message.isViewed ? .medium : .semibold,
                labelOpacity: message.isViewed ? 0.5 : 1.0
            )
        }
    }
}
