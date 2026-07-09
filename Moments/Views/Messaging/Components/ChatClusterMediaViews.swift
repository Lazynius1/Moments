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
            if message.isDeleted {
                flushCluster()
                result.append(.single(message))
                continue
            }

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
    var repliedMessage: EnhancedMessage? = nil
    var otherParticipantName: String = ""
    let isCurrentUser: Bool
    let showAvatar: Bool
    let otherUserId: String?
    let isOtherParticipantUnavailable: Bool
    let onAvatarTap: () -> Void
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onOpenCluster: ([EnhancedMessage]) -> Void
    let onLongPress: (EnhancedMessage, CGRect, CGFloat) -> Void
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    let onReply: ([EnhancedMessage]) -> Void
    let onReplyTap: ((String) -> Void)?
    let displayReactions: (String) -> [String: [String]]?
    let onReaction: (EnhancedMessage, String) -> Void
    let uploadProgress: [String: Double]
    let showSeenLabel: Bool
    var isMenuSelected: Bool = false
    var isBubbleFlashing: Bool = false
    @Binding var timestampRevealOffset: CGFloat

    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    @Environment(\.colorScheme) var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    if isCurrentUser {
                        Color.clear
                            .chatTimestampRevealGutter(timestampRevealOffset: $timestampRevealOffset)
                    }

                    if !isCurrentUser {
                        ChatIncomingAvatarGutter(
                            showAvatar: showAvatar,
                            otherUserId: otherUserId,
                            isUnavailable: isOtherParticipantUnavailable,
                            onTap: onAvatarTap
                        )
                    }

                    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                        if let repliedMessage {
                            StackedReplyQuote(
                                repliedMessage: repliedMessage,
                                isOutgoingRow: isCurrentUser,
                                otherParticipantName: otherParticipantName,
                                onTap: { onReplyTap?(repliedMessage.id) }
                            )
                        }
                        MediaGridBubble(
                            messages: messages,
                            isCurrentUser: isCurrentUser,
                            uploadProgress: uploadProgress,
                            displayReactions: displayReactions,
                            onReaction: onReaction,
                            onMomentNavigation: onMomentNavigation,
                            onOpenCluster: onOpenCluster,
                            onLongPress: onLongPress,
                            onHydrateMedia: onHydrateMedia,
                            isMenuSelected: isMenuSelected,
                            isBubbleFlashing: isBubbleFlashing,
                            dragOffset: $dragOffset,
                            hasTriggeredHaptic: $hasTriggeredHaptic,
                            onReply: { onReply(messages) }
                        )
                    }

                    if !isCurrentUser {
                        Color.clear
                            .chatTimestampRevealGutter(timestampRevealOffset: $timestampRevealOffset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)

                if let anchorMessage = messages.last {
                    MessageTimestamp(
                        message: anchorMessage,
                        isCurrentUser: isCurrentUser,
                        showSeenLabel: showSeenLabel,
                        overrideStatus: ClusterMessageStatusAggregator.aggregate(messages)
                    )
                    .frame(width: 55)
                    .padding(.leading, 12)
                    .opacity(Double(min(-timestampRevealOffset / 40, 1.0)))
                }
            }
            .padding(.trailing, -67) // 55 width + 12 leading padding = 67 off-screen
            .offset(x: timestampRevealOffset)
        .padding(.horizontal, 8)
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

// MARK: - Fanned photo pile

enum ClusterMediaLayout {
    static let frontWidth: CGFloat = 196
    static let frontHeight: CGFloat = 244
    static let cornerRadius: CGFloat = 12
    // El abanico sólo crece hacia arriba, así que el hueco inferior es mínimo.
    static let fanBottomPadding: CGFloat = 10
    static let maxVisible: Int = 5

    /// Padding superior necesario según cuántas cartas se muestren (sólo el
    /// desplazamiento real hacia arriba + margen para la rotación).
    static func fanTopPadding(for visibleCount: Int) -> CGFloat {
        let slice = offsets.prefix(max(visibleCount, 1))
        let maxUp = slice.map { -$0.height }.max() ?? 0
        return maxUp + 10
    }

    /// Padding lateral necesario según el desplazamiento real a los lados.
    static func fanSidePadding(for visibleCount: Int) -> CGFloat {
        let slice = offsets.prefix(max(visibleCount, 1))
        let maxSide = slice.map { abs($0.width) }.max() ?? 0
        return maxSide + 12
    }

    /// Rotación y desplazamiento de cada carta visible (índice 0 = frontal).
    static let rotations: [Double] = [-4, 3, -2.5, 4, -3]
    static let offsets: [CGSize] = [
        CGSize(width: 0, height: 0),
        CGSize(width: 10, height: -10),
        CGSize(width: -8, height: -19),
        CGSize(width: 14, height: -27),
        CGSize(width: -6, height: -34)
    ]
}

struct MediaGridBubble: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let uploadProgress: [String: Double]
    let displayReactions: (String) -> [String: [String]]?
    let onReaction: (EnhancedMessage, String) -> Void
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onOpenCluster: ([EnhancedMessage]) -> Void
    let onLongPress: (EnhancedMessage, CGRect, CGFloat) -> Void
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    var isMenuSelected: Bool = false
    var isBubbleFlashing: Bool = false
    @Binding var dragOffset: CGFloat
    @Binding var hasTriggeredHaptic: Bool
    let onReply: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var frontMessage: EnhancedMessage { messages[0] }

    private var isVanishProtected: Bool {
        messages.contains { $0.isVanishModeMessage == true }
    }

    var body: some View {
        if messages.allSatisfy(\.isDeleted) {
            DeletedMessageBubble(message: frontMessage, isCurrentUser: isCurrentUser)
        } else {
            mediaGridBody
        }
    }

    private var mediaGridBody: some View {
        let activeMessages = messages.filter { !$0.isDeleted }
        let count = activeMessages.count
        let visible = Array(activeMessages.prefix(ClusterMediaLayout.maxVisible))
        let topPad = ClusterMediaLayout.fanTopPadding(for: visible.count)
        let sidePad = ClusterMediaLayout.fanSidePadding(for: visible.count)

        return VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
            countLabel(count: count, messages: activeMessages)

            ChatBubbleReplySwipeContainer(
                dragOffset: $dragOffset,
                hasTriggeredHaptic: $hasTriggeredHaptic,
                isOutgoing: isCurrentUser,
                cornerRadius: ChatBubbleAnchorMetrics.clusterCornerRadius,
                onReply: onReply
            ) {
                ChatMessageBubbleChrome(
                    isMenuSelected: isMenuSelected,
                    isOutgoing: isCurrentUser,
                    cornerRadius: ChatBubbleAnchorMetrics.clusterCornerRadius,
                    colorScheme: colorScheme,
                    isFlashing: isBubbleFlashing,
                    onLongPress: { frame, radius in
                        onLongPress(activeMessages.first ?? frontMessage, frame, radius)
                    }
                ) {
                    let grid = ZStack {
                        ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { index, message in
                            photoCard(message: message, isFront: index == 0)
                                .rotationEffect(.degrees(ClusterMediaLayout.rotations[index]))
                                .offset(ClusterMediaLayout.offsets[index])
                                .zIndex(Double(10 - index))
                        }
                    }
                    .frame(width: ClusterMediaLayout.frontWidth, height: ClusterMediaLayout.frontHeight)
                    .padding(.top, topPad)
                    .padding(.horizontal, sidePad)
                    .padding(.bottom, ClusterMediaLayout.fanBottomPadding)
                    .contentShape(Rectangle())
                    .onAppear {
                        activeMessages.forEach { onHydrateMedia?($0) }
                    }
                    .onTapGesture {
                        onOpenCluster(activeMessages)
                    }

                    if isVanishProtected {
                        ScreenshotProtectedView(
                            isProtected: true,
                            cornerRadius: ChatBubbleAnchorMetrics.clusterCornerRadius
                        ) {
                            grid
                        }
                    } else {
                        grid
                    }
                }
            }
        }
        .id(clusterReactionIdentity)
    }

    private func countLabel(count: Int, messages: [EnhancedMessage]) -> some View {
        let hasVideo = messages.contains { $0.type == .video }
        let key: String
        if isCurrentUser {
            key = hasVideo ? "chat.cluster.sentItems" : "chat.cluster.sentPhotos"
        } else {
            key = hasVideo ? "chat.cluster.receivedItems" : "chat.cluster.receivedPhotos"
        }
        return Text(String(format: NSLocalizedString(key, comment: ""), count))
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
    }

    private func photoCard(message: EnhancedMessage, isFront: Bool) -> some View {
        MediaGridTileView(
            message: message,
            progress: uploadProgress[message.id],
            downsamplingSize: CGSize(
                width: ClusterMediaLayout.frontWidth * UIScreen.main.scale,
                height: ClusterMediaLayout.frontHeight * UIScreen.main.scale
            )
        )
        .frame(width: ClusterMediaLayout.frontWidth, height: ClusterMediaLayout.frontHeight)
        .clipShape(RoundedRectangle(cornerRadius: ClusterMediaLayout.cornerRadius, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if message.type == .video {
                ChatVideoPlayBadge(size: 14, padding: 6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isFront {
                ClusterCountBadge()
                    .padding(8)
            }
        }
        .overlay(alignment: isCurrentUser ? .bottomLeading : .bottomTrailing) {
            if isFront, let reactions = displayReactions(message.id), !reactions.isEmpty {
                let hang = MessageReactionMetrics.hangOffset(compact: false, cluster: true)
                let edge = MessageReactionMetrics.horizontalHangOffset(compact: false, anchoredInsideBounds: false)
                // El chip se expande a un área táctil de 44pt centrada; compensamos el inset
                // transparente para que el badge quede visualmente donde estaba.
                let hitInset = MessageReactionMetrics.clusterHitTargetInset(compact: false)
                MessageReactionChip(
                    reactions: reactions,
                    onTap: { emoji in onReaction(message, emoji) },
                    cluster: true
                )
                .offset(
                    x: isCurrentUser ? (edge - hitInset) : (-edge + hitInset),
                    y: hang + hitInset
                )
                .zIndex(10)
            }
        }
        .padding(
            .bottom,
            isFront && (displayReactions(message.id).map { !$0.isEmpty } ?? false)
                ? MessageReactionMetrics.reactionRowSpacing(compact: false, cluster: true)
                : 0
        )
    }

    private var clusterReactionIdentity: String {
        messages
            .map { "\($0.id)-\(reactionTileIdentity(for: $0.id))" }
            .joined(separator: "|")
    }

    private func reactionTileIdentity(for messageId: String) -> String {
        guard let reactions = displayReactions(messageId), !reactions.isEmpty else { return "" }
        return reactions
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
    }
}

private struct ClusterCountBadge: View {
    var body: some View {
        Image("CarouselPostIcon")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
    }
}

struct MediaGridTileView: View {
    @ObservedObject var message: EnhancedMessage
    let progress: Double?
    let downsamplingSize: CGSize
    var isDownloadingMedia: Bool = false
    var downloadProgress: Double? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            tileContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDownloadingMedia {
                ChatMediaDownloadProgressOverlay(
                    progress: downloadProgress ?? 0.03,
                    ringSize: 42,
                    lineWidth: 3
                )
            } else if message.status == .sending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color(hex: "0B1215").opacity(0.38)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 42, lineWidth: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Color(hex: "FAF9F6").opacity(colorScheme == .dark ? 0.06 : 0.22))
    }

    @ViewBuilder
    private var tileContent: some View {
        ZStack {
            if message.type == .image {
                if isDownloadingMedia {
                    if let preview = message.previewThumbnailURLForDisplay, let url = URL(string: preview) {
                        ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                            .blur(radius: 18)
                    } else {
                        ChatMediaResolvingPlaceholder()
                    }
                } else if message.isMediaAwaitingManualDownload {
                    if let preview = message.previewThumbnailURLForDisplay, let url = URL(string: preview) {
                        ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                            .blur(radius: 18)
                            .overlay { ChatMediaDownloadOverlay(sizeLabel: message.formattedDownloadSize) }
                    } else {
                        ChatMediaManualDownloadPlaceholder(sizeLabel: message.formattedDownloadSize)
                    }
                } else if message.isMediaPendingResolution {
                    ChatMediaResolvingPlaceholder()
                } else if let mediaUrl = message.mediaUrl,
                          let url = URL(string: mediaUrl),
                          message.localMediaFileIsReachable(url) {
                    ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                } else {
                    placeholder(icon: "photo.fill")
                }
            } else if message.type == .video {
                if isDownloadingMedia {
                    if let preview = message.previewThumbnailURLForDisplay, let url = URL(string: preview) {
                        ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                            .blur(radius: 18)
                    } else {
                        ChatMediaResolvingPlaceholder()
                    }
                } else if message.isMediaAwaitingManualDownload {
                    if let preview = message.previewThumbnailURLForDisplay, let url = URL(string: preview) {
                        ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                            .blur(radius: 18)
                            .overlay { ChatMediaDownloadOverlay(sizeLabel: message.formattedDownloadSize) }
                    } else {
                        ChatMediaManualDownloadPlaceholder(sizeLabel: message.formattedDownloadSize, showsVideoBadge: true)
                    }
                } else if message.isMediaPendingResolution || message.needsVideoThumbnailForDisplay {
                    ChatMediaResolvingPlaceholder()
                } else if let thumbnailUrl = message.thumbnailUrl,
                          let url = URL(string: thumbnailUrl),
                          message.localMediaFileIsReachable(url) {
                    ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                } else {
                    placeholder(icon: "video.fill")
                }
            } else {
                placeholder(icon: "doc.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func placeholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: ClusterMediaLayout.cornerRadius, style: .continuous)
            .fill(colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.1) : Color(hex: "0B1215").opacity(0.06))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
}

struct ClusterWrapper: Identifiable, Hashable {
    let messages: [EnhancedMessage]
    var id: String {
        messages.first?.id ?? "empty-cluster"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClusterWrapper, rhs: ClusterWrapper) -> Bool {
        lhs.id == rhs.id
    }
}

/// Identidad estable para push de galería (no cambia cuando se actualiza la media).
struct ClusterGallerySelection: Identifiable, Hashable {
    let anchorMessageId: String
    let messageIds: [String]
    var id: String { anchorMessageId }
}

// MARK: - Fullscreen cluster gallery

struct ClusterGalleryDetailRoute: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

/// Host del detalle en push: `dismiss()` hace pop al grid en el stack padre (como perfil).
private struct ClusterGalleryDetailHost<Detail: View>: View {
    let message: EnhancedMessage
    @ViewBuilder let detail: (EnhancedMessage, @escaping () -> Void) -> Detail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        detail(message) { dismiss() }
    }
}

enum ClusterGalleryPresentation {
    /// Presentación modal (p. ej. legacy fullScreenCover): cierra con ✕.
    case modal
    /// Push en el `NavigationStack` padre: retrocede con chevron.
    case pushed
}

enum ClusterGalleryScope {
    /// Álbum puntual (cluster en el chat): solo la media recibida, sin pestañas.
    case cluster
    /// Galería compartida de la conversación (ajustes): pestañas Media + Links.
    case conversationShared
}

enum ClusterGalleryTab: String, CaseIterable, Identifiable {
    case media = "chat.gallery.tab.media"
    case links = "chat.gallery.tab.links"

    var id: String { rawValue }
}

struct ClusterGalleryView<Detail: View>: View {
    let messages: [EnhancedMessage]
    let currentUserId: String
    var scope: ClusterGalleryScope = .cluster
    var presentation: ClusterGalleryPresentation = .modal
    var initialTab: ClusterGalleryTab = .media
    let onClose: () -> Void
    var onHydrateMedia: ((EnhancedMessage) -> Void)? = nil
    var onOpenMedia: ((EnhancedMessage, @escaping (EnhancedMessage) -> Void) -> Void)? = nil
    var isDownloadingMedia: ((String) -> Bool)? = nil
    var downloadProgress: ((String) -> Double?)? = nil
    var onDeleteForMe: (([EnhancedMessage]) -> Void)? = nil
    var onDeleteForEveryone: (([EnhancedMessage]) -> Void)? = nil
    /// Visor de detalle inyectado: recibe la media tocada y un cierre para volver
    /// (pop) a la galería.
    @ViewBuilder let detail: (EnhancedMessage, @escaping () -> Void) -> Detail

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var modalPath: [ClusterGalleryDetailRoute] = []
    @State private var pushedDetailRoute: ClusterGalleryDetailRoute?
    @State private var detailNavigationEpoch = 0
    @State private var isSelectionMode = false
    @State private var selectedIds = Set<String>()
    @State private var showDeleteConfirmation = false

    @State private var selectedTab: ClusterGalleryTab
    private let spacing: CGFloat = 14

    init(
        messages: [EnhancedMessage],
        currentUserId: String,
        scope: ClusterGalleryScope = .cluster,
        presentation: ClusterGalleryPresentation = .modal,
        initialTab: ClusterGalleryTab = .media,
        onClose: @escaping () -> Void,
        onHydrateMedia: ((EnhancedMessage) -> Void)? = nil,
        onOpenMedia: ((EnhancedMessage, @escaping (EnhancedMessage) -> Void) -> Void)? = nil,
        isDownloadingMedia: ((String) -> Bool)? = nil,
        downloadProgress: ((String) -> Double?)? = nil,
        onDeleteForMe: (([EnhancedMessage]) -> Void)? = nil,
        onDeleteForEveryone: (([EnhancedMessage]) -> Void)? = nil,
        @ViewBuilder detail: @escaping (EnhancedMessage, @escaping () -> Void) -> Detail
    ) {
        self.messages = messages
        self.currentUserId = currentUserId
        self.scope = scope
        self.presentation = presentation
        self.initialTab = initialTab
        self.onClose = onClose
        self.onHydrateMedia = onHydrateMedia
        self.onOpenMedia = onOpenMedia
        self.isDownloadingMedia = isDownloadingMedia
        self.downloadProgress = downloadProgress
        self.onDeleteForMe = onDeleteForMe
        self.onDeleteForEveryone = onDeleteForEveryone
        self.detail = detail
        _selectedTab = State(initialValue: initialTab)
    }

    private var galleryMessageIds: [String] {
        messages.filter { !$0.isDeleted }.compactMap(\.id)
    }

    private var visibleMessages: [EnhancedMessage] {
        let filtered = messages.filter { !$0.isDeleted }
        switch scope {
        case .cluster:
            return filtered.filter(Self.isGalleryMedia)
        case .conversationShared:
            switch selectedTab {
            case .media:
                return filtered.filter(Self.isGalleryMedia)
            case .links:
                return filtered.filter {
                    $0.type == .text && ChatLinkOpener.containsLink(in: $0.content ?? "")
                }
            }
        }
    }

    private static func isGalleryMedia(_ message: EnhancedMessage) -> Bool {
        message.type == .image || message.type == .video
    }

    private func extractURL(from text: String) -> String {
        ChatLinkOpener.firstURL(in: text)?.absoluteString ?? ""
    }

    private var selectedMessages: [EnhancedMessage] {
        visibleMessages.filter { selectedIds.contains($0.id) }
    }

    private var messagesEligibleForDeleteForEveryone: [EnhancedMessage] {
        selectedMessages.filter { Self.canDeleteForEveryone($0, currentUserId: currentUserId) }
    }

    var body: some View {
        Group {
            switch presentation {
            case .modal:
                NavigationStack(path: $modalPath) {
                    grid
                        .navigationDestination(for: ClusterGalleryDetailRoute.self) { route in
                            detailScreen(for: route) {
                                if !modalPath.isEmpty { modalPath.removeLast() }
                            }
                        }
                }
            case .pushed:
                grid
                    .navigationDestination(item: $pushedDetailRoute) { route in
                        detailScreen(for: route) {
                            pushedDetailRoute = nil
                        }
                    }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            detailNavigationEpoch &+= 1
        }
        .onChange(of: galleryMessageIds) { oldIds, newIds in
            selectedIds = selectedIds.intersection(Set(visibleMessages.compactMap(\.id)))
            if newIds.isEmpty, !oldIds.isEmpty {
                closeGallery()
            } else if selectedIds.isEmpty {
                isSelectionMode = false
            }
        }
        .onChange(of: selectedTab) { _, _ in
            selectedIds = selectedIds.intersection(Set(visibleMessages.compactMap(\.id)))
            if selectedIds.isEmpty {
                isSelectionMode = false
            }
        }
        .confirmationDialog(
            Text("chat.gallery.deletePrompt"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("chat.action.deleteForMe", role: .destructive) {
                onDeleteForMe?(selectedMessages)
                exitSelectionMode()
            }
            if !messagesEligibleForDeleteForEveryone.isEmpty {
                Button("chat.action.deleteForEveryone", role: .destructive) {
                    onDeleteForEveryone?(messagesEligibleForDeleteForEveryone)
                    exitSelectionMode()
                }
            }
            Button("common.cancel", role: .cancel) {}
        }
    }

    private var screenBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var galleryTitle: String {
        NSLocalizedString("chat.gallery.title", comment: "")
    }

    private func closeGallery() {
        switch presentation {
        case .modal:
            onClose()
        case .pushed:
            detailNavigationEpoch &+= 1
            pushedDetailRoute = nil
            dismiss()
        }
    }

    @ViewBuilder
    private func detailScreen(for route: ClusterGalleryDetailRoute, dismissDetail: @escaping () -> Void) -> some View {
        if let message = messageForDetailRoute(route) {
            ClusterGalleryDetailHost(message: message, detail: detail)
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
    }

    private func messageForDetailRoute(_ route: ClusterGalleryDetailRoute) -> EnhancedMessage? {
        guard !visibleMessages.isEmpty else { return nil }
        let index = min(max(route.index, 0), visibleMessages.count - 1)
        return visibleMessages[index]
    }

    @ToolbarContentBuilder
    private var galleryToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ProfileChromeIconButton(
                systemName: presentation == .modal ? "xmark" : "chevron.left",
                foregroundColor: MomentsChromeGlass.contentColor(for: colorScheme),
                preset: presentation == .modal ? .toolbarAction : .navigationBack,
                action: closeGallery
            )
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelectionMode ? "common.cancel" : "chat.gallery.select") {
                toggleSelectionMode()
            }
            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            .foregroundColor(isSelectionMode ? .red : MomentsChromeGlass.contentColor(for: colorScheme))
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text(String(format: NSLocalizedString("chat.gallery.selectedCount", comment: ""), selectedIds.count))
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundColor(MomentsChromeGlass.contentColor(for: colorScheme))

            Spacer()

            Button(action: { showDeleteConfirmation = true }) {
                Label("common.delete", systemImage: "trash")
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
            .disabled(selectedIds.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.3), lineWidth: 1)
                )
        )
    }

    private var grid: some View {
        VStack(spacing: 0) {
            if scope == .conversationShared {
                HStack(spacing: 0) {
                    ForEach(ClusterGalleryTab.allCases) { tab in
                        Button {
                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.row) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(NSLocalizedString(tab.rawValue, comment: ""))
                                    .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                                    .foregroundColor(selectedTab == tab ? MomentsChromeGlass.contentColor(for: colorScheme) : .gray)
                                    .frame(maxWidth: .infinity)

                                Rectangle()
                                    .fill(selectedTab == tab ? Color.blue : Color.clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(screenBackground)
            }

            ScrollView(showsIndicators: false) {
                if scope == .conversationShared, selectedTab == .links {
                    LazyVStack(spacing: spacing) {
                        ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                            linkGridCell(message, index: index)
                        }
                    }
                    .padding(.horizontal, spacing)
                    .padding(.vertical, 16)
                } else {
                    let columns = distribute(visibleMessages)
                    HStack(alignment: .top, spacing: spacing) {
                        masonryColumn(columns.0)
                        masonryColumn(columns.1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, spacing)
                    .padding(.vertical, 16)
                }
            }
        }
        .background {
            screenBackground.ignoresSafeArea()
        }
        .navigationTitle(galleryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(presentation == .pushed)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { galleryToolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                selectionBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            visibleMessages.forEach { onHydrateMedia?($0) }
        }
    }

    private func masonryColumn(_ items: [EnhancedMessage]) -> some View {
        VStack(spacing: spacing) {
            ForEach(items) { message in
                mediaCard(message)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
    }

    private func mediaCard(_ message: EnhancedMessage) -> some View {
        let ratio = aspectRatio(for: message)
        let index = visibleMessages.firstIndex(where: { $0.id == message.id }) ?? 0
        let isSelected = selectedIds.contains(message.id)

        return Button {
            if isSelectionMode {
                toggleSelection(message.id)
            } else {
                openMessageDetail(at: index, message: message)
            }
        } label: {
            mediaCardLabel(message: message, aspectRatio: ratio, isSelected: isSelected)
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard !isSelectionMode else { return }
                enterSelectionMode(selecting: message.id)
            }
        )
        .frame(minWidth: 0, maxWidth: .infinity)
        .onAppear {
            onHydrateMedia?(message)
        }
    }

    @ViewBuilder
    private func mediaCardLabel(
        message: EnhancedMessage,
        aspectRatio ratio: CGFloat,
        isSelected: Bool
    ) -> some View {
        let isVideo = message.type == .video
        let isDownloading = isDownloadingMedia?(message.id) ?? false

        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                MediaGridTileView(
                    message: message,
                    progress: nil,
                    downsamplingSize: CGSize(
                        width: 400 * UIScreen.main.scale,
                        height: max(400 / ratio, 1) * UIScreen.main.scale
                    ),
                    isDownloadingMedia: isDownloading,
                    downloadProgress: downloadProgress?(message.id)
                )
            }
            .overlay(alignment: .bottomLeading) {
                if isVideo, !isDownloading {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                        if let durationStr = message.formattedDuration {
                            Text(durationStr)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                        }
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isSelectionMode, isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    private func linkGridCell(_ message: EnhancedMessage, index: Int) -> some View {
        let isSelected = selectedIds.contains(message.id)
        let linkRawUrl = extractURL(from: message.content ?? "")
        let linkHost = URL(string: linkRawUrl)?.host ?? ""
        let linkContent = message.content ?? ""

        return Button {
            if isSelectionMode {
                toggleSelection(message.id)
            } else {
                openMessageDetail(at: index, message: message)
            }
        } label: {
            linkCard(message: message, linkHost: linkHost, linkContent: linkContent)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .overlay {
                    if isSelectionMode, isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.38))
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                            .padding(8)
                    }
                }
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard !isSelectionMode else { return }
                enterSelectionMode(selecting: message.id)
            }
        )
    }

    private func toggleSelectionMode() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
            if isSelectionMode {
                exitSelectionMode()
            } else {
                isSelectionMode = true
            }
        }
    }

    private func linkCard(message: EnhancedMessage, linkHost: String, linkContent: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                if !linkHost.isEmpty {
                    Text(linkHost)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            Spacer()
            Text(linkContent)
                .font(.system(size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.85))
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 1)
        )
    }

    private func openMessageDetail(at index: Int, message: EnhancedMessage) {
        if scope == .conversationShared, selectedTab == .links {
            if let content = message.content {
                ChatLinkOpener.openFirstLink(in: content)
            }
            return
        }

        let route = ClusterGalleryDetailRoute(index: index)
        let open = {
            switch presentation {
            case .modal:
                modalPath.append(route)
            case .pushed:
                pushedDetailRoute = route
            }
        }

        guard message.type == .image || message.type == .video else {
            open()
            return
        }

        guard message.needsDownloadForPlayback else {
            open()
            return
        }

        // Solo descargar; el usuario vuelve a pulsar cuando esté listo.
        onOpenMedia?(message) { _ in }
    }

    private func enterSelectionMode(selecting messageId: String) {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
            isSelectionMode = true
            selectedIds = [messageId]
        }
    }

    private func toggleSelection(_ messageId: String) {
        if selectedIds.contains(messageId) {
            selectedIds.remove(messageId)
            if selectedIds.isEmpty {
                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                    isSelectionMode = false
                }
            }
        } else {
            selectedIds.insert(messageId)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds.removeAll()
    }

    private static func canDeleteForEveryone(_ message: EnhancedMessage, currentUserId: String) -> Bool {
        message.senderId == currentUserId
            && !message.isDeleted
            && !message.isRead
            && Date().timeIntervalSince(message.timestamp) < 7200
    }

    private func aspectRatio(for message: EnhancedMessage) -> CGFloat {
        if let w = message.mediaWidth, let h = message.mediaHeight, w > 0, h > 0 {
            return min(max(CGFloat(w) / CGFloat(h), 0.5), 1.9)
        }
        return 0.8
    }

    /// Reparte las medias en dos columnas balanceando la altura acumulada.
    private func distribute(_ items: [EnhancedMessage]) -> ([EnhancedMessage], [EnhancedMessage]) {
        var left: [EnhancedMessage] = []
        var right: [EnhancedMessage] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for message in items {
            let relativeHeight = 1 / aspectRatio(for: message)
            if leftHeight <= rightHeight {
                left.append(message)
                leftHeight += relativeHeight
            } else {
                right.append(message)
                rightHeight += relativeHeight
            }
        }
        return (left, right)
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
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
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
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .bottomLeading) {
                                if message.type == .video {
                                    ChatVideoPlayBadge(size: 18, padding: 10)
                                }
                            }
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
