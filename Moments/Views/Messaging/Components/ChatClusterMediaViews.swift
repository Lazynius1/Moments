import SwiftUI
import Kingfisher

enum ClusterMessageStatusAggregator {
    private static let priority: [MessageStatus: Int] = [
        .failed: -2,
        .pending: -1,
        .sending: 0,
        .sent: 1,
        .delivered: 2,
        .read: 3
    ]

    /// Estado agregado del álbum: el menos avanzado gana (p. ej. 1 de 4 enviando → sending).
    static func aggregate(_ messages: [EnhancedMessage]) -> MessageStatus {
        guard !messages.isEmpty else { return .sent }
        return messages.map(\.status).min {
            (priority[$0] ?? 0) < (priority[$1] ?? 0)
        } ?? .sent
    }
}

enum ClusterMessageGrouper {
    /// Ventana de ráfaga: fotos/videos consecutivos del mismo remitente sin batch explícito.
    private static let burstWindow: TimeInterval = 60

    static func shouldAppendToCluster(_ message: EnhancedMessage, cluster: [EnhancedMessage]) -> Bool {
        guard let last = cluster.last else { return true }
        guard message.senderId == last.senderId else { return false }

        let messageBatch = message.mediaBatchId?.isEmpty == false ? message.mediaBatchId : nil
        let lastBatch = last.mediaBatchId?.isEmpty == false ? last.mediaBatchId : nil

        if let messageBatch, let lastBatch {
            return messageBatch == lastBatch
        }
        if messageBatch != nil, lastBatch != nil, messageBatch != lastBatch {
            return false
        }

        let delta = message.timestamp.timeIntervalSince(last.timestamp)
        return delta >= 0 && delta <= burstWindow
    }

    static func group(_ input: [EnhancedMessage]) -> [MessageItem] {
        var result: [MessageItem] = []
        var currentCluster: [EnhancedMessage] = []

        func flushCluster() {
            guard !currentCluster.isEmpty else { return }
            result.append(currentCluster.count > 1 ? .mediaCluster(currentCluster) : .single(currentCluster[0]))
            currentCluster = []
        }

        for message in input {
            let isClusterable = message.type == .image || message.type == .video

            if isClusterable {
                if currentCluster.isEmpty || shouldAppendToCluster(message, cluster: currentCluster) {
                    currentCluster.append(message)
                } else {
                    flushCluster()
                    currentCluster.append(message)
                }
            } else {
                flushCluster()
                result.append(.single(message))
            }
        }

        flushCluster()
        return result
    }
}

// MARK: - Clustering UI Components
struct GlassmorphicClusterRow: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let showAvatar: Bool
    let otherUserId: String?
    let isOtherParticipantUnavailable: Bool
    let onAvatarTap: () -> Void
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onOpenMedia: (EnhancedMessage) -> Void
    let onLongPress: (EnhancedMessage) -> Void
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    let onReply: ([EnhancedMessage]) -> Void
    let onReplyTap: ((String) -> Void)?
    let uploadProgress: [String: Double]
    let showSeenLabel: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background Reply Icon (appears when swiping)
            if dragOffset > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(adaptiveColors.userAccentColor)
                    .opacity(Double(min(dragOffset / 60, 1.0)))
                    .offset(x: min(dragOffset - 30, 0))
                    .padding(.leading, 12)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if !isCurrentUser {
                    if showAvatar {
                        Button(action: onAvatarTap) {
                            if isOtherParticipantUnavailable {
                                ProfileUnavailableAvatar(size: 32)
                            } else {
                                GlassmorphicAvatar(userId: otherUserId ?? "")
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }

                if isCurrentUser { Spacer(minLength: 50) }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    MediaGridBubble(
                        messages: messages,
                        isCurrentUser: isCurrentUser,
                        uploadProgress: uploadProgress,
                        onMomentNavigation: onMomentNavigation,
                        onOpenMedia: onOpenMedia,
                        onLongPress: onLongPress,
                        onHydrateMedia: onHydrateMedia
                    )

                    if let anchorMessage = messages.last {
                        ClusterMessageFooter(
                            messages: messages,
                            anchorMessage: anchorMessage,
                            isCurrentUser: isCurrentUser,
                            showSeenLabel: showSeenLabel
                        )
                    }
                }

                if !isCurrentUser { Spacer(minLength: 50) }
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle())
            .chatReplySwipeGesture(
                dragOffset: $dragOffset,
                hasTriggeredHaptic: $hasTriggeredHaptic,
                onReply: { onReply(messages) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

private struct ClusterMessageFooter: View {
    let messages: [EnhancedMessage]
    @ObservedObject var anchorMessage: EnhancedMessage
    let isCurrentUser: Bool
    let showSeenLabel: Bool

    var body: some View {
        Group {
            ForEach(messages) { message in
                ClusterMessageStatusObserver(message: message)
            }
            MessageTimestamp(
                message: anchorMessage,
                isCurrentUser: isCurrentUser,
                showSeenLabel: showSeenLabel,
                overrideStatus: ClusterMessageStatusAggregator.aggregate(messages)
            )
            .id(messages.map { "\($0.id)-\($0.status.rawValue)" }.joined(separator: "|"))
        }
    }
}

private struct ClusterMessageStatusObserver: View {
    @ObservedObject var message: EnhancedMessage
    var body: some View {
        EmptyView()
    }
}

struct MediaGridBubble: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let uploadProgress: [String: Double]
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onOpenMedia: (EnhancedMessage) -> Void
    let onLongPress: (EnhancedMessage) -> Void
    let onHydrateMedia: ((EnhancedMessage) -> Void)?

    var body: some View {
        let count = messages.count
        let columns = count >= 2 ? 2 : 1
        let gridSpacing: CGFloat = 6
        let gridWidth: CGFloat = 220
        let horizontalInset: CGFloat = 6
        let availableWidth = gridWidth - (horizontalInset * 2)
        let cellWidth = columns == 2 ? (availableWidth - gridSpacing) / 2 : availableWidth
        let cellHeight: CGFloat = count >= 3 ? 94 : cellWidth
        let gridItems = Array(repeating: GridItem(.fixed(cellWidth), spacing: gridSpacing), count: columns)
        let displayedMessages = Array(messages.prefix(4).enumerated())

        LazyVGrid(columns: gridItems, spacing: gridSpacing) {
            ForEach(displayedMessages, id: \.element.id) { index, message in
                MediaGridTileView(
                    message: message,
                    progress: uploadProgress[message.id],
                    downsamplingSize: CGSize(width: cellWidth * UIScreen.main.scale, height: cellHeight * UIScreen.main.scale)
                )
                .onAppear {
                    onHydrateMedia?(message)
                }
                .frame(width: cellWidth, height: cellHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    Group {
                        if index == 3 && count > 4 {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    Text("+\(count - 4)")
                                        .font(.custom("Poppins-SemiBold", size: 20))
                                        .foregroundColor(.white)
                                )
                                .allowsHitTesting(false)
                        }
                    }
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    onOpenMedia(message)
                }
                .chatMessageLongPress {
                    onLongPress(message)
                }
            }
        }
        .frame(width: gridWidth)
        .padding(horizontalInset)
        .chatMessageLongPress {
            if let anchor = messages.last {
                onLongPress(anchor)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial.opacity(0.3))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .id(messages.map(\.id).joined(separator: "-"))
    }
}

struct MediaGridTileView: View {
    @ObservedObject var message: EnhancedMessage
    let progress: Double?
    let downsamplingSize: CGSize
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            if message.type == .image {
                if message.isMediaPendingResolution {
                    ChatMediaResolvingPlaceholder()
                } else if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                    ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                } else {
                    placeholder(icon: "photo.fill")
                }
            } else if message.type == .video {
                if message.isMediaPendingResolution {
                    ChatMediaResolvingPlaceholder()
                } else if let thumbnailUrl = message.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                    ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                } else {
                    placeholder(icon: "video.fill")
                }

                Circle()
                    .fill(Color(hex: "0B1215").opacity(0.42))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
            } else {
                placeholder(icon: "doc.fill")
            }

            if message.status == .sending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color(hex: "0B1215").opacity(0.38)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 42, lineWidth: 3)
                }
            }
        }
        .background(Color(hex: "FAF9F6").opacity(colorScheme == .dark ? 0.06 : 0.22))
        .clipped()
    }

    @ViewBuilder
    private func placeholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.1) : Color(hex: "0B1215").opacity(0.06))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
}

struct ClusterMediaViewer: View {
    let messages: [EnhancedMessage]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int

    init(messages: [EnhancedMessage], startIndex: Int) {
        self.messages = messages
        self.startIndex = startIndex

        let safeInitialIndex: Int
        if messages.isEmpty {
            safeInitialIndex = 0
        } else {
            safeInitialIndex = min(max(startIndex, 0), messages.count - 1)
        }
        _selectedIndex = State(initialValue: safeInitialIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    ClusterMediaViewerPage(message: message)
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))

            HStack {
                Text("\(min(selectedIndex + 1, max(messages.count, 1)))/\(max(messages.count, 1))")
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .statusBar(hidden: true)
    }
}

struct ClusterMediaViewerPage: View {
    let message: EnhancedMessage
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var seekTarget: Double? = nil
    @State private var isPaused = false

    var body: some View {
        Group {
            if message.type == .video, let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                ZStack(alignment: .bottom) {
                    MomentsVideoPlayer(
                        url: url,
                        isLooping: true,
                        isPaused: isPaused,
                        videoGravity: .resizeAspect,
                        onDurationReceived: { value in
                            duration = value
                        },
                        onProgressUpdate: { value in
                            if !isPaused {
                                currentTime = value
                            }
                        },
                        onVideoFinished: {},
                        externalSeekTime: $seekTarget
                    )
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPaused.toggle()
                    }

                    MomentsVideoPlaybackTimeline(
                        currentTime: currentTime,
                        duration: duration,
                        horizontalPadding: 18,
                        onSeek: { targetTime in
                            currentTime = targetTime
                            seekTarget = targetTime
                        }
                    )
                    .padding(.bottom, 22)
                }
            } else if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if let thumbnailUrl = message.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.6))
                    )
                    .padding(28)
            }
        }
    }
}

struct ClusterWrapper: Identifiable {
    let messages: [EnhancedMessage]
    var id: String {
        messages.first?.id ?? "empty-cluster"
    }
}

// MARK: - Media Selection Sheet for Clusters
struct GlassmorphicMediaSelectionSheet: View {
    let messages: [EnhancedMessage]
    let onSelect: (EnhancedMessage) -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("chat.reply.select_item")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(adaptiveColors.primary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(adaptiveColors.primary.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(messages) { message in
                        Button(action: { onSelect(message) }) {
                            ZStack {
                                if message.type == .image, let urlString = message.mediaUrl, let url = URL(string: urlString) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                } else if message.type == .video {
                                    if let thumbUrl = message.thumbnailUrl, let url = URL(string: thumbUrl) {
                                        KFImage(url)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.1))
                                    }

                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "play.fill")
                                                .foregroundColor(.white)
                                                .font(.system(size: 16))
                                        )
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(adaptiveColors.primary.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(
            RoundedCorner(radius: 30, corners: [.topLeft, .topRight])
                .stroke(adaptiveColors.primary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedCorner(radius: 30, corners: [.topLeft, .topRight]))
    }
}

// MARK: - Helper Styles
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MomentsPressButtonStyle(scale: 0.94, pressedOpacity: 0.9, haptic: .none)
            .makeBody(configuration: configuration)
    }
}
