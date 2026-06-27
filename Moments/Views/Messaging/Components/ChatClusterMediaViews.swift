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

            HStack(alignment: .bottom, spacing: 0) {
                if isCurrentUser { Spacer(minLength: 50) }

                if !isCurrentUser {
                    ChatIncomingAvatarGutter(
                        showAvatar: showAvatar,
                        otherUserId: otherUserId,
                        isUnavailable: isOtherParticipantUnavailable,
                        onTap: onAvatarTap
                    )
                }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
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
                        dragOffset: dragOffset
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
    var dragOffset: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    private var frontMessage: EnhancedMessage { messages[0] }

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

            ChatMessageBubbleChrome(
                isMenuSelected: isMenuSelected,
                isOutgoing: isCurrentUser,
                cornerRadius: ChatBubbleAnchorMetrics.clusterCornerRadius,
                colorScheme: colorScheme,
                isFlashing: isBubbleFlashing,
                dragOffset: dragOffset,
                onLongPress: { frame, radius in
                    onLongPress(activeMessages.first ?? frontMessage, frame, radius)
                }
            ) {
                ZStack {
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
                MessageReactionChip(
                    reactions: reactions,
                    onTap: { emoji in onReaction(message, emoji) },
                    cluster: true
                )
                .offset(
                    x: isCurrentUser ? edge : -edge,
                    y: hang
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

struct ClusterGalleryView<Detail: View>: View {
    let messages: [EnhancedMessage]
    let currentUserId: String
    var presentation: ClusterGalleryPresentation = .modal
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
    private let spacing: CGFloat = 14

    private var visibleMessages: [EnhancedMessage] {
        messages.filter { !$0.isDeleted }
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
        .onChange(of: visibleMessages.map(\.id)) { oldIds, newIds in
            selectedIds = selectedIds.intersection(Set(newIds))
            if newIds.isEmpty, !oldIds.isEmpty {
                closeGallery()
            } else if selectedIds.isEmpty {
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
        ScrollView(showsIndicators: false) {
            let columns = distribute(visibleMessages)
            HStack(alignment: .top, spacing: spacing) {
                masonryColumn(columns.0)
                masonryColumn(columns.1)
            }
            .padding(.horizontal, spacing)
            .padding(.bottom, 20)
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
                card(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func toggleSelectionMode() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if isSelectionMode {
                exitSelectionMode()
            } else {
                isSelectionMode = true
            }
        }
    }

    private func card(_ message: EnhancedMessage) -> some View {
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
            cardLabel(message: message, aspectRatio: ratio, isSelected: isSelected)
        }
        .buttonStyle(ScaleButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard !isSelectionMode else { return }
                enterSelectionMode(selecting: message.id)
            }
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(ratio, contentMode: .fit)
        .onAppear {
            onHydrateMedia?(message)
        }
    }

    @ViewBuilder
    private func cardLabel(
        message: EnhancedMessage,
        aspectRatio ratio: CGFloat,
        isSelected: Bool
    ) -> some View {
        MediaGridTileView(
            message: message,
            progress: nil,
            downsamplingSize: CGSize(
                width: 400 * UIScreen.main.scale,
                height: max(400 / ratio, 1) * UIScreen.main.scale
            ),
            isDownloadingMedia: isDownloadingMedia?(message.id) ?? false,
            downloadProgress: downloadProgress?(message.id)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if message.type == .video, !(isDownloadingMedia?(message.id) ?? false) {
                ChatVideoPlayBadge(size: 18, padding: 10)
            }
        }
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
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    private func openMessageDetail(at index: Int, message: EnhancedMessage) {
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

        // WhatsApp: solo descargar; el usuario vuelve a pulsar cuando esté listo.
        onOpenMedia?(message) { _ in }
    }

    private func enterSelectionMode(selecting messageId: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isSelectionMode = true
            selectedIds = [messageId]
        }
    }

    private func toggleSelection(_ messageId: String) {
        if selectedIds.contains(messageId) {
            selectedIds.remove(messageId)
            if selectedIds.isEmpty {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
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
