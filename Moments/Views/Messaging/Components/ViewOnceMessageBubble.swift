import SwiftUI
import Kingfisher
import AVFoundation
import AVKit

// MARK: - View-Once Message Bubble
struct ViewOnceMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let otherParticipantName: String
    let progress: Double? // ✅ New: Real-time upload progress
    let onViewed: () -> Void
    @State private var isViewed = false
    @State private var showFullScreen = false
    @Environment(\.colorScheme) var colorScheme
    @State private var shimmerOffset: CGFloat = -1
    
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
                // Caso Receptor: Unread o Opened
                ZStack {
                    ViewOnceOpenedBubble(
                        message: message,
                        adaptiveColors: adaptiveColors
                    )
                    .opacity(message.isViewed ? 1 : 0)
                    
                    ViewOnceUnreadBubble(
                        message: message,
                        adaptiveColors: adaptiveColors,
                        onTap: {
                            openViewOnceMessage()
                        }
                    )
                    .opacity(message.isViewed ? 0 : 1)
                    .allowsHitTesting(!message.isViewed)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            ViewOnceImmersiveViewer(
                message: message,
                authorName: isCurrentUser ? NSLocalizedString("chat.reply.you", comment: "You") : otherParticipantName,
                onViewed: {
                    isViewed = true
                    onViewed()
                }
            )
        }
    }
    
    private func openViewOnceMessage() {
        // ✅ Solo se puede abrir si NO ha sido visto
        guard !message.isViewed else {
            return
        }
        
        showFullScreen = true
    }
}

// MARK: - Simplified View-Once Unread Bubble
struct ViewOnceUnreadBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    let onTap: () -> Void
    
    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon with Glass background
                ZStack {
                    Circle()
                        .fill(adaptiveColors.messageBubbleBackground)
                        .frame(width: 50, height: 50)
                    
                    AttachmentIconView(icon: .ephemeral, preset: .viewOnceBubble, tintColor: .white)
                        .overlay(
                            signatureGradient
                                .mask(AttachmentIconView(icon: .ephemeral, preset: .viewOnceBubble, tintColor: .white))
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(getTypeText())
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(adaptiveColors.messageTextColor)
                    
                    Text("chat.viewOnce.tapToView")
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundColor(adaptiveColors.messageTextColor.opacity(0.8))
                    
                    // Simple message with signature colors
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("chat.viewOnce.autoDelete")
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    }
                    .foregroundColor(.clear)
                    .overlay(
                        signatureGradient
                            .mask(
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                    Text("chat.viewOnce.autoDelete")
                                        .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                                }
                            )
                    )
                }
                
                Spacer()
                
                // Unopened indicator with Glow
                ZStack {
                    Circle()
                        .fill(signatureGradient)
                        .frame(width: 10, height: 10)
                        .blur(radius: 2)
                    
                    Circle()
                        .fill(signatureGradient)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .fill(adaptiveColors.messageBubbleBackground.opacity(0.3))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(signatureGradient.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func getIconName() -> String {
        switch message.type {
        case .viewOnceImage:
            return "camera.circle.fill"
        case .viewOnceVideo:
            return "video.circle.fill"
        default:
            return "camera.circle.fill"
        }
    }
    
    private func getTypeText() -> String {
        switch message.type {
        case .viewOnceImage:
            return NSLocalizedString("chat.viewOnce.photo", comment: "")
        case .viewOnceVideo:
            return NSLocalizedString("chat.viewOnce.video", comment: "")
        default:
            return NSLocalizedString("chat.viewOnce.media", comment: "")
        }
    }
}

// MARK: - View-Once Opened Bubble
struct ViewOnceOpenedBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    
    var body: some View {
        HStack(spacing: 12) {
            // Opened icon
            Image(systemName: "eye.slash.circle")
                .font(.system(size: 20))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(getTypeText())
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
                
                Text("chat.viewOnce.alreadyViewed")
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.3))
                    .italic()
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(adaptiveColors.messageBubbleBackground.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(adaptiveColors.messageBubbleStroke.opacity(0.5), lineWidth: 0.5)
                )
        )
    }
    
    private func getTypeText() -> String {
        switch message.type {
        case .viewOnceImage:
            return NSLocalizedString("chat.viewOnce.photoOpened", comment: "")
        case .viewOnceVideo:
            return NSLocalizedString("chat.viewOnce.videoOpened", comment: "")
        default:
            return NSLocalizedString("chat.viewOnce.mediaOpened", comment: "")
        }
    }
}

// MARK: - View-Once Sent Bubble
struct ViewOnceSentBubble: View {
    let message: EnhancedMessage
    let progress: Double? // ✅ New
    let adaptiveColors: AdaptiveColors
    
    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(getTypeText())
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundColor(adaptiveColors.messageTextColor)
                
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 10))
                    Text("chat.viewOnce.viewOnce")
                        .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                }
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7))
                
                if message.isViewed {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("chat.viewOnce.viewed")
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                    }
                    .foregroundColor(.green.opacity(0.8))
                } else {
                    Text("chat.viewOnce.sent")
                        .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                        .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
                }
            }
            
            Spacer()
            
            // Sent icon with signature gradient
            ZStack {
                Circle()
                    .fill(adaptiveColors.messageBubbleBackground.opacity(0.5))
                    .frame(width: 36, height: 36)
                
                AttachmentIconView(icon: .ephemeral, preset: .viewOnceBadge, tintColor: .white)
                    .overlay(
                        signatureGradient
                            .mask(AttachmentIconView(icon: .ephemeral, preset: .viewOnceBadge, tintColor: .white))
                    )
                
                // ✅ Progress Overlay (Smaller)
                if message.status == .sending, let uploadProgress = progress {
                    MediaProgressRing(progress: uploadProgress, size: 36, lineWidth: 2.5)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(adaptiveColors.messageBubbleBackground.opacity(0.2))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(signatureGradient.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func getIconName() -> String {
        switch message.type {
        case .viewOnceImage:
            return "camera.fill"
        case .viewOnceVideo:
            return "video.fill"
        default:
            return "camera.fill"
        }
    }
    
    private func getTypeText() -> String {
        switch message.type {
        case .viewOnceImage:
            return NSLocalizedString("chat.viewOnce.photo", comment: "")
        case .viewOnceVideo:
            return NSLocalizedString("chat.viewOnce.video", comment: "")
        default:
            return NSLocalizedString("chat.viewOnce.media", comment: "")
        }
    }
}


