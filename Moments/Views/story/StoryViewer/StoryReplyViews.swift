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

// MARK: - Story reply preview (DM)

private enum StoryReplyPreviewMetrics {
    /// Miniatura vertical tipo IG (más alta que antes).
    static let width: CGFloat = 76
    static let height: CGFloat = 118
    static let cornerRadius: CGFloat = 14
}

private var storyReplyRingGradient: LinearGradient {
    LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Story Reply Message Bubble
struct StoryReplyMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    /// Otro participante del chat 1:1 (para inferir autor en mensajes antiguos sin `storyAuthorId`).
    let otherParticipantId: String?
    @State private var showEphemeralContent: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 8) {
            if let storyReplyData = message.storyReplyData {
                Text(
                    isCurrentUser
                        ? NSLocalizedString("stories.replied", comment: "")
                        : NSLocalizedString("stories.repliedTo", comment: "")
                )
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(adaptiveColors.replyBarSecondaryText)
                .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)

                storyReplyThreadedColumn(storyReplyData: storyReplyData)
            } else {
                storyReplyBody
            }
        }
        .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
        .padding(.vertical, 2)
        .onAppear {
            checkAndTriggerCleanupIfNeeded()
        }
    }

    @ViewBuilder
    private var storyReplyBody: some View {
        if message.type == .ephemeral {
            if message.isDeleted || !isEphemeralValid() {
                StoryReplyEphemeralExpiredCard()
            } else {
                EphemeralStoryReplyContent(
                    message: message,
                    isCurrentUser: isCurrentUser,
                    showContent: $showEphemeralContent
                )
            }
        } else {
            StoryTextReplyContent(
                message: message,
                isCurrentUser: isCurrentUser
            )
        }
    }

    @ViewBuilder
    private func storyReplyThreadedColumn(storyReplyData: [String: String]) -> some View {
        let threadSpacing: CGFloat = 10
        let messageInset = 2.5 + threadSpacing
        let lineColor = adaptiveColors.replyBarSecondaryText.opacity(colorScheme == .dark ? 0.55 : 0.4)

        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 10) {
            HStack(alignment: .top, spacing: threadSpacing) {
                if !isCurrentUser {
                    Capsule()
                        .fill(lineColor)
                        .frame(width: 2.5, height: StoryReplyPreviewMetrics.height)
                }

                StoryReplyGatedThumbnailView(
                    storyReplyData: storyReplyData,
                    messageSenderId: message.senderId,
                    otherParticipantId: otherParticipantId
                )

                if isCurrentUser {
                    Capsule()
                        .fill(lineColor)
                        .frame(width: 2.5, height: StoryReplyPreviewMetrics.height)
                }
            }

            storyReplyBody
                .padding(.leading, isCurrentUser ? 0 : messageInset)
                .padding(.trailing, isCurrentUser ? messageInset : 0)
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

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        if let content = message.content {
            let cleanContent = content.hasPrefix("💬 ") ? String(content.dropFirst(2)) : content

            Text(cleanContent)
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(adaptiveColors.messageTextColor)
                .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        }
    }
}

// MARK: - Acceso a preview (tipo Instagram: autor sí, resto si sigue activa)

struct StoryReplyGatedThumbnailView: View {
    let storyReplyData: [String: String]
    let messageSenderId: String
    let otherParticipantId: String?

    @State private var canViewStory = false
    @State private var denialReason: SharedStoryAccessDenialReason = .expired
    @State private var isLoading = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if isLoading {
                StoryReplyThumbnailSkeleton()
            } else if canViewStory {
                StoryReplyThumbnailView(storyReplyData: storyReplyData)
            } else {
                StoryReplyUnavailableThumbnail(
                    reason: denialReason,
                    storyReplyData: storyReplyData
                )
            }
        }
        .onAppear {
            validateAccess()
        }
    }

    private func validateAccess() {
        guard let storyId = storyReplyData["storyId"],
              let viewerId = Auth.auth().currentUser?.uid else {
            canViewStory = false
            denialReason = .restricted
            isLoading = false
            return
        }

        let authorId = resolvedStoryAuthorId(viewerId: viewerId)
        guard !authorId.isEmpty else {
            canViewStory = false
            denialReason = .restricted
            isLoading = false
            return
        }

        let payloadExpiration = storyReplyData["storyExpiration"].flatMap { TimeInterval($0) }

        SharedStoryAccessEvaluator.evaluate(
            authorId: authorId,
            storyId: storyId,
            payloadExpiration: payloadExpiration,
            viewerId: viewerId
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    canViewStory = true
                    denialReason = .expired
                case .failure(let reason):
                    canViewStory = false
                    denialReason = reason
                }
                isLoading = false
            }
        }
    }

    private func resolvedStoryAuthorId(viewerId: String) -> String {
        if let authorId = storyReplyData["storyAuthorId"], !authorId.isEmpty {
            return authorId
        }
        // Mensajes legacy: quien respondió no es el autor de la historia.
        if messageSenderId == viewerId {
            return otherParticipantId ?? ""
        }
        return viewerId
    }
}

private struct StoryReplyThumbnailSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: StoryReplyPreviewMetrics.cornerRadius, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
            .frame(width: StoryReplyPreviewMetrics.width, height: StoryReplyPreviewMetrics.height)
            .overlay {
                ProgressView()
                    .tint(colorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
    }
}

private struct StoryReplyUnavailableThumbnail: View {
    let reason: SharedStoryAccessDenialReason
    let storyReplyData: [String: String]

    @Environment(\.colorScheme) private var colorScheme

    private var previewURL: String? {
        let preview = storyReplyData["storyPreviewUrl"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preview, !preview.isEmpty { return preview }
        return storyReplyData["storyMediaUrl"]
    }

    private var iconName: String {
        switch reason {
        case .expired:
            return "clock.fill"
        case .blocked:
            return "hand.raised.fill"
        case .privateAccount:
            return "lock.fill"
        default:
            return "lock.fill"
        }
    }

    var body: some View {
        let innerRadius = StoryReplyPreviewMetrics.cornerRadius - 2
        let innerWidth = StoryReplyPreviewMetrics.width - 4
        let innerHeight = StoryReplyPreviewMetrics.height - 4

        ZStack {
            Group {
                if let previewURL,
                   let url = URL(string: previewURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 18)
                        .saturation(0.35)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.15))
                }
            }
            .frame(width: innerWidth, height: innerHeight)
            .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))

            Color.black.opacity(0.55)

            VStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Text(LocalizedStringKey(reason.titleKey))
                    .font(.custom("Poppins-SemiBold", size: 9))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: StoryReplyPreviewMetrics.cornerRadius, style: .continuous)
                .stroke(storyReplyRingGradient.opacity(0.45), lineWidth: 2)
        )
        .frame(width: StoryReplyPreviewMetrics.width, height: StoryReplyPreviewMetrics.height)
    }
}

struct StoryReplyThumbnailView: View {
    let storyReplyData: [String: String]

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var isVideo: Bool {
        storyReplyData["storyMediaType"] == "video"
    }

    var body: some View {
        let innerRadius = StoryReplyPreviewMetrics.cornerRadius - 2
        let innerWidth = StoryReplyPreviewMetrics.width - 4
        let innerHeight = StoryReplyPreviewMetrics.height - 4

        ZStack {
            Group {
                if let storyMediaUrl = storyReplyData["storyMediaUrl"],
                   let url = URL(string: storyMediaUrl) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12)
                        }
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.15))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(adaptiveColors.replyBarSecondaryText)
                        )
                }
            }
            .frame(width: innerWidth, height: innerHeight)
            .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))

            if isVideo {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: StoryReplyPreviewMetrics.cornerRadius, style: .continuous)
                .stroke(storyReplyRingGradient, lineWidth: 2)
        )
        .frame(width: StoryReplyPreviewMetrics.width, height: StoryReplyPreviewMetrics.height)
    }
}

// MARK: - Ephemeral en respuesta a historia (misma huella vertical que el preview)

private enum StoryReplyEphemeralMetrics {
    static let width = StoryReplyPreviewMetrics.width
    static let height = StoryReplyPreviewMetrics.height
    static let cornerRadius = StoryReplyPreviewMetrics.cornerRadius
}

private func storyReplyFormatTimeLeft(_ timeInterval: TimeInterval) -> String {
    let hours = Int(timeInterval) / 3600
    let minutes = Int(timeInterval) % 3600 / 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

struct StoryReplyEphemeralTapCard: View {
    let previewImageURL: String?
    let expirationDate: Date?
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            storyReplyEphemeralBackdrop

            Color.black.opacity(0.35)

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                Spacer()

                SharedDMPreviewBottomGradient()

                VStack(spacing: 4) {
                    Text("stories.tapToView")
                        .font(.custom("Poppins-SemiBold", size: 11))
                        .foregroundColor(.white)

                    if let expirationDate, expirationDate > Date() {
                        Text(
                            String(
                                format: NSLocalizedString("stories.expiresIn", comment: ""),
                                storyReplyFormatTimeLeft(expirationDate.timeIntervalSince(Date()))
                            )
                        )
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: StoryReplyEphemeralMetrics.width, height: StoryReplyEphemeralMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous)
                .stroke(storyReplyRingGradient, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var storyReplyEphemeralBackdrop: some View {
        if let previewImageURL,
           !previewImageURL.isEmpty,
           let url = URL(string: previewImageURL) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .blur(radius: 22)
                .saturation(0.7)
        } else {
            Rectangle()
                .fill(adaptiveColors.messageBubbleBackground)
        }
    }
}

struct StoryReplyEphemeralImageCard: View {
    let imageUrl: URL
    let expirationDate: Date?

    @State private var showFullScreen = false

    var body: some View {
        KFImage(imageUrl)
            .resizable()
            .scaledToFill()
            .frame(width: StoryReplyEphemeralMetrics.width, height: StoryReplyEphemeralMetrics.height)
            .clipShape(RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let expirationDate, expirationDate > Date() {
                    Text(storyReplyFormatTimeLeft(expirationDate.timeIntervalSince(Date())))
                        .font(.custom("Poppins-Regular", size: 9))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous))
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
}

struct StoryReplyEphemeralExpiredCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(adaptiveColors.messageBubbleBackground)

            Color.black.opacity(0.45)

            VStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))

                Text("stories.ephemeral.expired")
                    .font(.custom("Poppins-SemiBold", size: 10))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: StoryReplyEphemeralMetrics.width, height: StoryReplyEphemeralMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StoryReplyEphemeralMetrics.cornerRadius, style: .continuous)
                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
        )
    }
}

struct EphemeralStoryReplyContent: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @Binding var showContent: Bool
    @State private var hasBeenViewed: Bool = false

    var body: some View {
        Group {
            if !showContent && !hasBeenViewed && isEphemeralValid() {
                StoryReplyEphemeralTapCard(
                    previewImageURL: message.mediaUrl,
                    expirationDate: message.expirationDate
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showContent = true
                        hasBeenViewed = true
                    }
                }
            } else if (showContent || hasBeenViewed) && isEphemeralValid(),
                      let mediaUrl = message.mediaUrl,
                      let url = URL(string: mediaUrl) {
                StoryReplyEphemeralImageCard(
                    imageUrl: url,
                    expirationDate: message.expirationDate
                )
            } else {
                StoryReplyEphemeralExpiredCard()
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
}

// MARK: - Clickable Ephemeral Image Content (efímera genérica en chat, no story reply)
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
            .overlay(alignment: .topTrailing) {
                if let expirationDate, expirationDate > Date() {
                    Text(storyReplyFormatTimeLeft(expirationDate.timeIntervalSince(Date())))
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
            }
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
                Color.clear.momentsChromeGlass(in: Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }

    func storyGlassmorphic() -> some View {
        self
            .background(
                Color.clear.momentsChromeGlass(in: Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}
