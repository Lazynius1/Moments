import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - Story Reply Message Bubble
// MARK: - Story Reply Message Bubble (Componente Principal)
struct StoryReplyMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @State private var showEphemeralContent: Bool = false

    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 8) {
            // Story preview section - always shown for story replies
            if let storyReplyData = message.storyReplyData {
                StoryReplyPreview(
                    storyReplyData: storyReplyData,
                    isCurrentUser: isCurrentUser
                )
            }

            // Content section - different based on message type
            if message.type == .ephemeral {
                // Verificar si el mensaje está marcado como eliminado O si ha expirado
                if message.isDeleted || !isEphemeralValid() {
                    // Mostrar placeholder de expirado
                    ExpiredEphemeralPlaceholder()
                } else {
                    // Ephemeral photo/video reply
                    EphemeralStoryReplyContent(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        showContent: $showEphemeralContent
                    )
                }
            } else {
                // Regular text reply
                StoryTextReplyContent(
                    message: message,
                    isCurrentUser: isCurrentUser
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .onAppear {
            // Verificar si necesita limpieza
            checkAndTriggerCleanupIfNeeded()
        }
    }

    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }

    private func checkAndTriggerCleanupIfNeeded() {
        // Si el mensaje ha expirado pero no está marcado como eliminado, triggear limpieza
        if message.type == .ephemeral && !isEphemeralValid() && !message.isDeleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                ChatService().cleanupExpiredEphemeralMessages()
            }
        }
    }
}
// MARK: - Story Text Reply Content
struct StoryTextReplyContent: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool

    var body: some View {
        if let content = message.content {
            // Remove the "💬 " prefix if it exists
            let cleanContent = content.hasPrefix("💬 ") ? String(content.dropFirst(2)) : content

            Text(cleanContent)
                .font(.custom("Poppins-Regular", size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isCurrentUser ? Color(hex: "007AFF").opacity(0.8) : Color.white.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - Placeholder para mensajes expirados
struct ExpiredEphemeralPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.circle")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.4))

                            Text("stories.ephemeral.expired")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

                            Text("stories.ephemeral.unavailable")
                .font(.custom("Poppins-Regular", size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 250, minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Story Reply Preview
struct StoryReplyPreview: View {
    let storyReplyData: [String: String]
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Story thumbnail
            if let storyMediaUrl = storyReplyData["storyMediaUrl"],
               let url = URL(string: storyMediaUrl) {
                ZStack {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Video play icon overlay if it's a video
                    if storyReplyData["storyMediaType"] == "video" {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 20, height: 20)
                            )
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.pink, .orange, .yellow]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 16))
                    )
            }

            // Story reply text with better styling
            VStack(alignment: .leading, spacing: 3) {
                Text(isCurrentUser ? NSLocalizedString("stories.replied", comment: "You replied to their story") : NSLocalizedString("stories.repliedTo", comment: "Replied to your story"))
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.white.opacity(0.9))

                // Show story type with icon
                if let storyMediaType = storyReplyData["storyMediaType"] {
                    HStack(spacing: 4) {
                        Image(systemName: storyMediaType == "video" ? "play.rectangle.fill" : "photo.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "007AFF"))

                        Text(storyMediaType == "video" ? NSLocalizedString("stories.video", comment: "Video") : NSLocalizedString("stories.photo", comment: "Photo"))
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.4),
                            Color.black.opacity(0.2)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Fixed Ephemeral Story Reply Content
struct EphemeralStoryReplyContent: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @Binding var showContent: Bool
    @State private var hasBeenViewed: Bool = false

    var body: some View {
        ZStack {
            if !showContent && !hasBeenViewed && isEphemeralValid() {
                // Tap to view state
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.purple, .pink, .orange]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 4) {
                        Text("stories.tapToView")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)

                        Text("stories.ephemeral.title")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.white.opacity(0.8))

                        // Expiration indicator with better styling
                        if let expirationDate = message.expirationDate {
                            let timeLeft = expirationDate.timeIntervalSince(Date())
                            if timeLeft > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))

                                    Text(String(format: NSLocalizedString("stories.expiresIn", comment: "Expires in"), formatTimeLeft(timeLeft)))
                                        .font(.custom("Poppins-Regular", size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.3))
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 280, minHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.15),
                                    Color.pink.opacity(0.15),
                                    Color.orange.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.purple.opacity(0.5), .pink.opacity(0.5)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showContent = true
                        hasBeenViewed = true
                        // Don't mark as "viewed" in Firebase since it can be viewed multiple times
                    }
                }
            } else if (showContent || hasBeenViewed) && isEphemeralValid() {
                // Show content - can be viewed multiple times during 24h period
                if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                    ClickableEphemeralImageContent(
                        imageUrl: url,
                        expirationDate: message.expirationDate,
                        canViewMultipleTimes: true
                    )
                }
            } else {
                // Expired
                ExpiredEphemeralPlaceholder()
            }
        }
        .onAppear {
            hasBeenViewed = message.isViewed
        }
    }

    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Clickable Ephemeral Image Content (for story replies)
struct ClickableEphemeralImageContent: View {
    let imageUrl: URL
    let expirationDate: Date?
    let canViewMultipleTimes: Bool
    @State private var showFullScreen = false

    var body: some View {
        KFImage(imageUrl)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 250, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                // Show expiration info in corner
                VStack {
                    HStack {
                        Spacer()
                        if let expirationDate = expirationDate {
                            let timeLeft = expirationDate.timeIntervalSince(Date())
                            if timeLeft > 0 {
                                Text(formatTimeLeft(timeLeft))
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.6))
                                    )
                                    .padding(8)
                            }
                        }
                    }
                    Spacer()

                    // Add click indicator
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "eye")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("stories.tapToViewComplete")
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(8)
                        }
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            .onTapGesture {
                showFullScreen = true
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                FullScreenEphemeralImageView(
                    imageUrl: imageUrl,
                    expirationDate: expirationDate
                )
            }
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Full Screen Ephemeral Image
struct FullScreenEphemeralImageView: View {
    let imageUrl: URL
    let expirationDate: Date?
    @Environment(\.dismiss) var dismiss
    @State private var timeLeft: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            KFImage(imageUrl)
                .resizable()
                .scaledToFit()

            VStack {
                HStack {
                    Button("common.close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.custom("Poppins-Medium", size: 16))

                    Spacer()

                    if timeLeft > 0 {
                        Text(String(format: NSLocalizedString("stories.expiresIn", comment: "Expires in"), formatTimeLeft(timeLeft)))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                            )
                    }
                }
                .padding()

                Spacer()
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        guard let expirationDate = expirationDate else { return }

        timeLeft = expirationDate.timeIntervalSince(Date())

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            timeLeft = max(0, expirationDate.timeIntervalSince(Date()))
            if timeLeft <= 0 {
                timer?.invalidate()
                dismiss()
            }
        }
    }

    private func formatTimeLeft(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Glassmorphic Extensions
extension View {
    func glassmorphic() -> some View {
        self
            .background(
                Color.clear.liquidGlass(in: Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }

    func storyGlassmorphic() -> some View {
        self
            .background(
                Color.clear.liquidGlass(in: Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}
