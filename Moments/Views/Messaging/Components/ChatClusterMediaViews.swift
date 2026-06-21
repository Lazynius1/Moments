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
    let onOpenCluster: ([EnhancedMessage]) -> Void
    let onLongPress: (EnhancedMessage) -> Void
    let onHydrateMedia: ((EnhancedMessage) -> Void)?
    let onReply: ([EnhancedMessage]) -> Void
    let onReplyTap: ((String) -> Void)?
    let displayReactions: (String) -> [String: [String]]?
    let onReaction: (EnhancedMessage, String) -> Void
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

// MARK: - Instagram-style fanned photo pile

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

    /// Rotación y desplazamiento de cada carta visible (índice 0 = frontal). Stack
    /// compacto estilo Instagram: las cartas de atrás asoman poco (sobre todo hacia
    /// arriba) con rotaciones sutiles. La frontal va ligeramente inclinada.
    static let rotations: [Double] = [-4, 3, -2.5, 4, -3]
    static let offsets: [CGSize] = [
        CGSize(width: 0, height: 0),
        CGSize(width: 10, height: -10),
        CGSize(width: -8, height: -19),
        CGSize(width: 14, height: -27),
        CGSize(width: -6, height: -34)
    ]
}

/// Pila de fotos en abanico estilo Instagram: la primera media al frente y las
/// siguientes asomando rotadas detrás (fotos reales), con una etiqueta de conteo
/// encima. Al tocar abre la galería de selección.
struct MediaGridBubble: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let uploadProgress: [String: Double]
    let displayReactions: (String) -> [String: [String]]?
    let onReaction: (EnhancedMessage, String) -> Void
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onOpenCluster: ([EnhancedMessage]) -> Void
    let onLongPress: (EnhancedMessage) -> Void
    let onHydrateMedia: ((EnhancedMessage) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var frontMessage: EnhancedMessage { messages[0] }

    var body: some View {
        let count = messages.count
        let visible = Array(messages.prefix(ClusterMediaLayout.maxVisible))
        let topPad = ClusterMediaLayout.fanTopPadding(for: visible.count)
        let sidePad = ClusterMediaLayout.fanSidePadding(for: visible.count)

        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
            countLabel(count: count)

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
                messages.forEach { onHydrateMedia?($0) }
            }
            .onTapGesture {
                onOpenCluster(messages)
            }
            .chatMessageLongPress {
                onLongPress(frontMessage)
            }
        }
        .id(clusterReactionIdentity)
    }

    private func countLabel(count: Int) -> some View {
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
        .overlay(alignment: .topTrailing) {
            if isFront {
                ClusterCountBadge()
                    .padding(8)
            }
        }
        .overlay(alignment: isCurrentUser ? .bottomLeading : .bottomTrailing) {
            if isFront, let reactions = displayReactions(message.id), !reactions.isEmpty {
                MessageReactionChip(
                    reactions: reactions,
                    onTap: { emoji in onReaction(message, emoji) },
                    cluster: true
                )
                .padding(6)
                .zIndex(10)
            }
        }
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            tileContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if message.status == .sending {
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

struct ClusterWrapper: Identifiable {
    let messages: [EnhancedMessage]
    var id: String {
        messages.first?.id ?? "empty-cluster"
    }
}

// MARK: - Fullscreen cluster gallery (Instagram-style)

struct ClusterGalleryDetailRoute: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

/// Galería a pantalla completa estilo Instagram: rejilla de 2 columnas tipo
/// masonry que respeta el aspect ratio real de cada media. Al tocar una, hace una
/// transición de pantalla (push) al visor de detalle (inyectado) abriendo ese item.
struct ClusterGalleryView<Detail: View>: View {
    let messages: [EnhancedMessage]
    let onClose: () -> Void
    /// Visor de detalle inyectado: recibe la media tocada y un cierre para volver
    /// (pop) a la galería.
    @ViewBuilder let detail: (EnhancedMessage, @escaping () -> Void) -> Detail

    @Environment(\.colorScheme) private var colorScheme
    @State private var path: [ClusterGalleryDetailRoute] = []
    private let spacing: CGFloat = 14

    var body: some View {
        NavigationStack(path: $path) {
            grid
                .navigationDestination(for: ClusterGalleryDetailRoute.self) { route in
                    detail(messages[min(max(route.index, 0), messages.count - 1)]) {
                        if !path.isEmpty { path.removeLast() }
                    }
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    private var grid: some View {
        GeometryReader { geo in
            let columnWidth = (geo.size.width - spacing * 3) / 2
            let columns = distribute(messages)

            ZStack(alignment: .topLeading) {
                background

                ScrollView(showsIndicators: false) {
                    HStack(alignment: .top, spacing: spacing) {
                        column(columns.0, width: columnWidth)
                        column(columns.1, width: columnWidth)
                    }
                    .padding(.horizontal, spacing)
                    .padding(.top, 72)
                    .padding(.bottom, 40)
                }

                closeButton
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }

    private var background: some View {
        (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .ignoresSafeArea()
    }

    private var closeButton: some View {
        MomentsGlassIconButton(systemName: "xmark", size: 38, iconSize: 16) {
            onClose()
        }
    }

    private func column(_ items: [EnhancedMessage], width: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(items) { message in
                card(message, width: width)
            }
        }
    }

    private func card(_ message: EnhancedMessage, width: CGFloat) -> some View {
        let ratio = aspectRatio(for: message)
        let height = width / ratio
        let index = messages.firstIndex(where: { $0.id == message.id }) ?? 0
        return Button {
            path.append(ClusterGalleryDetailRoute(index: index))
        } label: {
            MediaGridTileView(
                message: message,
                progress: nil,
                downsamplingSize: CGSize(
                    width: width * UIScreen.main.scale,
                    height: height * UIScreen.main.scale
                )
            )
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(ScaleButtonStyle())
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
