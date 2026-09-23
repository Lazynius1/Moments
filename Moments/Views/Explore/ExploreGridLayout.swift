import SwiftUI
import Kingfisher
import AVFoundation

// MARK: - Explore bento layout (exclusivo de Explore)

enum ExploreBentoTileKind: Equatable {
    case unit
    case tall
    case hero

    var colSpan: Int {
        switch self {
        case .unit, .tall: 1
        case .hero: 2
        }
    }

    var rowSpan: Int {
        switch self {
        case .unit: 1
        case .tall, .hero: 2
        }
    }
}

enum ExploreGridVisualRole: Equatable {
    case photo
    case video
    case reelHero
    case reelTall
}

struct ExploreGridTileDescriptor: Equatable {
    let layoutKind: ExploreBentoTileKind
    let visualRole: ExploreGridVisualRole
    let showsPlayCue: Bool
    let showsDuration: Bool

    var usesPortraitCrop: Bool {
        visualRole == .reelHero || visualRole == .reelTall
    }

    static func standard(for moment: Moment, layoutKind: ExploreBentoTileKind = .unit) -> ExploreGridTileDescriptor {
        let isVideo = moment.hasVideoMedia
        let visualRole: ExploreGridVisualRole

        if moment.isReelCandidate, layoutKind == .hero {
            visualRole = .reelHero
        } else if moment.isReelCandidate {
            visualRole = .reelTall
        } else if isVideo {
            visualRole = .video
        } else {
            visualRole = .photo
        }

        return ExploreGridTileDescriptor(
            layoutKind: layoutKind,
            visualRole: visualRole,
            showsPlayCue: isVideo,
            showsDuration: isVideo && moment.isReelCandidate
        )
    }
}

enum ExploreBentoTileAssigner {
    static func assign(moments: [Moment]) -> [ExploreGridTileDescriptor] {
        moments.map { ExploreGridTileDescriptor.standard(for: $0) }
    }
}

enum ExploreMomentsGridMetrics {
    static let spacing: CGFloat = 1
    static let columns = 2
    static let portraitAspectRatio: CGFloat = 4.0 / 5.0

    static func columnWidth(for availableWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        return (availableWidth - totalSpacing) / CGFloat(columns)
    }

    static func tileSize(kind: ExploreBentoTileKind, unitWidth: CGFloat, spacing: CGFloat = spacing) -> CGSize {
        switch kind {
        case .unit:
            return CGSize(width: unitWidth, height: unitWidth / portraitAspectRatio)
        case .tall:
            return CGSize(width: unitWidth, height: unitWidth / portraitAspectRatio * 2 + spacing)
        case .hero:
            return CGSize(
                width: unitWidth * 2 + spacing,
                height: unitWidth / portraitAspectRatio * 2 + spacing
            )
        }
    }

    static func bentoHeight(tileKinds: [ExploreBentoTileKind], availableWidth: CGFloat) -> CGFloat {
        guard !tileKinds.isEmpty else { return 0 }

        let unitWidth = columnWidth(for: availableWidth)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for kind in tileKinds {
            let tileSize = tileSize(kind: kind, unitWidth: unitWidth)
            let colSpan = kind.colSpan
            var bestColumn = 0
            var bestY = CGFloat.greatestFiniteMagnitude

            for startColumn in 0...(columns - colSpan) {
                let y = columnHeights[startColumn..<(startColumn + colSpan)].map { height in
                    height > 0 ? height + spacing : 0
                }.max() ?? 0
                if y < bestY || (y == bestY && startColumn < bestColumn) {
                    bestY = y
                    bestColumn = startColumn
                }
            }

            let newBottom = bestY + tileSize.height
            for column in bestColumn..<(bestColumn + colSpan) {
                columnHeights[column] = newBottom
            }
        }

        return columnHeights.max() ?? 0
    }
}

func exploreBentoGridHeight(moments: [Moment], availableWidth: CGFloat) -> CGFloat {
    let descriptors = ExploreBentoTileAssigner.assign(moments: moments)
    return ExploreMomentsGridMetrics.bentoHeight(
        tileKinds: descriptors.map(\.layoutKind),
        availableWidth: availableWidth
    )
}

private struct ExploreBentoTileKindLayoutKey: LayoutValueKey {
    static let defaultValue: ExploreBentoTileKind = .unit
}

private extension View {
    func exploreBentoTileKind(_ kind: ExploreBentoTileKind) -> some View {
        layoutValue(key: ExploreBentoTileKindLayoutKey.self, value: kind)
    }
}

struct ExploreBentoLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    init(columns: Int = ExploreMomentsGridMetrics.columns, spacing: CGFloat = ExploreMomentsGridMetrics.spacing) {
        self.columns = max(columns, 1)
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width > 0 else {
            return CGSize(width: proposal.width ?? 0, height: 0)
        }
        return CGSize(width: width, height: totalHeight(totalWidth: width, subviews: subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let unitWidth = unitWidth(totalWidth: bounds.width)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let kind = subview[ExploreBentoTileKindLayoutKey.self]
            let tileSize = ExploreMomentsGridMetrics.tileSize(kind: kind, unitWidth: unitWidth, spacing: spacing)
            let placement = bestPlacement(colSpan: kind.colSpan, columnHeights: columnHeights)
            let x = bounds.minX + (unitWidth + spacing) * CGFloat(placement.startColumn)

            subview.place(
                at: CGPoint(x: x, y: bounds.minY + placement.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: tileSize.width, height: tileSize.height)
            )

            let newBottom = placement.y + tileSize.height
            for column in placement.startColumn..<(placement.startColumn + kind.colSpan) {
                columnHeights[column] = newBottom
            }
        }
    }

    private func totalHeight(totalWidth: CGFloat, subviews: Subviews) -> CGFloat {
        let unitWidth = unitWidth(totalWidth: totalWidth)
        var columnHeights = Array(repeating: CGFloat(0), count: columns)

        for subview in subviews {
            let kind = subview[ExploreBentoTileKindLayoutKey.self]
            let tileSize = ExploreMomentsGridMetrics.tileSize(kind: kind, unitWidth: unitWidth, spacing: spacing)
            let placement = bestPlacement(colSpan: kind.colSpan, columnHeights: columnHeights)
            let newBottom = placement.y + tileSize.height

            for column in placement.startColumn..<(placement.startColumn + kind.colSpan) {
                columnHeights[column] = newBottom
            }
        }

        return columnHeights.max() ?? 0
    }

    private func unitWidth(totalWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        return (totalWidth - totalSpacing) / CGFloat(columns)
    }

    private struct Placement {
        let startColumn: Int
        let y: CGFloat
    }

    private func bestPlacement(colSpan: Int, columnHeights: [CGFloat]) -> Placement {
        var best = Placement(startColumn: 0, y: .greatestFiniteMagnitude)

        for startColumn in 0...(columns - colSpan) {
            let y = columnHeights[startColumn..<(startColumn + colSpan)].map { height in
                height > 0 ? height + spacing : 0
            }.max() ?? 0

            if y < best.y || (y == best.y && startColumn < best.startColumn) {
                best = Placement(startColumn: startColumn, y: y)
            }
        }

        return best
    }
}

private struct ExploreBentoGridPlacement: Equatable {
    let frame: CGRect
    let kind: ExploreBentoTileKind
}

private enum ExploreBentoGridPlacementCalculator {
    static func placements(
        descriptors: [ExploreGridTileDescriptor],
        availableWidth: CGFloat,
        spacing: CGFloat = ExploreMomentsGridMetrics.spacing,
        columns: Int = ExploreMomentsGridMetrics.columns
    ) -> [ExploreBentoGridPlacement] {
        guard availableWidth > 0, !descriptors.isEmpty else { return [] }

        let unitWidth = ExploreMomentsGridMetrics.columnWidth(for: availableWidth)
        var columnHeights = Array(repeating: CGFloat(0), count: max(columns, 1))
        var result: [ExploreBentoGridPlacement] = []
        result.reserveCapacity(descriptors.count)

        for descriptor in descriptors {
            let kind = descriptor.layoutKind
            let tileSize = ExploreMomentsGridMetrics.tileSize(
                kind: kind,
                unitWidth: unitWidth,
                spacing: spacing
            )
            let placement = bestPlacement(
                colSpan: kind.colSpan,
                columnHeights: columnHeights,
                columns: columns,
                spacing: spacing
            )
            let x = (unitWidth + spacing) * CGFloat(placement.startColumn)
            result.append(
                ExploreBentoGridPlacement(
                    frame: CGRect(x: x, y: placement.y, width: tileSize.width, height: tileSize.height),
                    kind: kind
                )
            )

            let newBottom = placement.y + tileSize.height
            for column in placement.startColumn..<(placement.startColumn + kind.colSpan) {
                columnHeights[column] = newBottom
            }
        }

        return result
    }

    private static func bestPlacement(
        colSpan: Int,
        columnHeights: [CGFloat],
        columns: Int,
        spacing: CGFloat
    ) -> (startColumn: Int, y: CGFloat) {
        var bestColumn = 0
        var bestY = CGFloat.greatestFiniteMagnitude

        for startColumn in 0...(columns - colSpan) {
            let y = columnHeights[startColumn..<(startColumn + colSpan)].map { height in
                height > 0 ? height + spacing : 0
            }.max() ?? 0
            if y < bestY || (y == bestY && startColumn < bestColumn) {
                bestY = y
                bestColumn = startColumn
            }
        }
        return (bestColumn, bestY)
    }
}

private struct ExploreBentoVisibleIndex: Identifiable {
    let index: Int
    let id: String
}

private struct ExploreBentoGridLayoutKey: Equatable {
    let descriptors: [ExploreGridTileDescriptor]
    let width: CGFloat
}

private struct ExploreBentoGridContainer<Cell: View>: View {
    @Environment(\.momentsViewportSize) private var momentsViewportSize

    let moments: [Moment]
    let availableWidth: CGFloat
    let descriptors: [ExploreGridTileDescriptor]
    @ViewBuilder let cell: (Moment, CGFloat, Int, ExploreGridTileDescriptor) -> Cell

    @State private var viewportBucket: Int = 0
    @State private var cachedLayoutKey: ExploreBentoGridLayoutKey?
    @State private var cachedPlacements: [ExploreBentoGridPlacement] = []

    private var layoutKey: ExploreBentoGridLayoutKey {
        ExploreBentoGridLayoutKey(descriptors: descriptors, width: availableWidth)
    }

    private func makePlacements(for key: ExploreBentoGridLayoutKey) -> [ExploreBentoGridPlacement] {
        ExploreBentoGridPlacementCalculator.placements(
            descriptors: key.descriptors,
            availableWidth: key.width
        )
    }

    private func visibleItems(
        placements: [ExploreBentoGridPlacement]
    ) -> [ExploreBentoVisibleIndex] {
        guard !placements.isEmpty else { return [] }

        // The bucket changes once per tile-sized scroll interval. This keeps
        // preference updates cheap while retaining a generous prefetch window.
        let unitWidth = max(ExploreMomentsGridMetrics.columnWidth(for: availableWidth), 1)
        let viewportTop = CGFloat(viewportBucket) * unitWidth
        let buffer = max(unitWidth * 3, 600)
        let visibleRect = CGRect(
            x: 0,
            y: max(0, viewportTop - buffer),
            width: availableWidth,
            height: momentsViewportSize.height + buffer * 2
        )

        return placements.enumerated().compactMap { index, placement in
            guard placement.frame.intersects(visibleRect) else { return nil }
            let moment = moments[index]
            let stableID: String
            if let momentID = moment.id {
                stableID = "\(moment.authorId)|\(momentID)"
            } else {
                stableID = "\(moment.authorId)|\(moment.timestamp.timeIntervalSince1970)|\(index)"
            }
            return ExploreBentoVisibleIndex(index: index, id: stableID)
        }
    }

    var body: some View {
        let key = layoutKey
        let placements = cachedLayoutKey == key
            ? cachedPlacements
            : makePlacements(for: key)
        let columnWidth = ExploreMomentsGridMetrics.columnWidth(for: availableWidth)
        let visibleItems = visibleItems(placements: placements)
        let bentoHeight = placements.map { $0.frame.maxY }.max() ?? 0

        ZStack(alignment: .topLeading) {
            ForEach(visibleItems) { item in
                let index = item.index
                let moment = moments[index]
                let descriptor = descriptors[index]
                cell(moment, columnWidth, index, descriptor)
                    .frame(
                        width: placements[index].frame.width,
                        height: placements[index].frame.height
                    )
                    .position(
                        x: placements[index].frame.midX,
                        y: placements[index].frame.midY
                    )
            }
        }
        .frame(width: availableWidth, height: bentoHeight, alignment: .topLeading)
        .onGeometryChange(for: Int.self) { proxy in
            guard availableWidth > 0 else { return 0 }
            let unitWidth = max(ExploreMomentsGridMetrics.columnWidth(for: availableWidth), 1)
            let localViewportTop = max(0, -proxy.frame(in: .global).minY)
            return Int(floor(localViewportTop / unitWidth))
        } action: { _, bucket in
            if bucket != viewportBucket {
                viewportBucket = bucket
            }
        }
        .onChange(of: key, initial: true) { _, newKey in
            guard cachedLayoutKey != newKey else { return }
            cachedPlacements = makePlacements(for: newKey)
            cachedLayoutKey = newKey
        }
    }
}

// MARK: - Grid público de Explore

struct ExploreMomentsBentoGrid: View {
    let moments: [Moment]
    var zoomNamespace: Namespace.ID? = nil
    var zoomIDPrefix: String = "explore"
    let onMomentTap: (Moment, Int, [Moment]) -> Void

    /// Ancho que propone la pantalla (o la columna del Duo), no la ventana entera.
    @State private var availableWidth: CGFloat = 0

    private var descriptors: [ExploreGridTileDescriptor] {
        ExploreBentoTileAssigner.assign(moments: moments)
    }

    private var gridHeight: CGFloat {
        guard availableWidth > 1 else { return 0 }
        return exploreBentoGridHeight(moments: moments, availableWidth: availableWidth)
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: max(gridHeight, 1))
            .overlay(alignment: .topLeading) {
                if availableWidth > 1 {
                    ExploreBentoGridContainer(
                        moments: moments,
                        availableWidth: availableWidth,
                        descriptors: descriptors
                    ) { moment, itemWidth, index, descriptor in
                        ScreenshotProtectedView(
                            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                        ) {
                            ExploreMomentThumbnail(
                                moment: moment,
                                unitWidth: itemWidth,
                                descriptor: descriptor,
                                zoomNamespace: zoomNamespace,
                                zoomSourceID: exploreZoomSourceID(moment: moment, index: index),
                                onTap: {
                                    onMomentTap(moment, index, moments)
                                }
                            )
                        }
                    }
                    .frame(width: availableWidth, height: gridHeight, alignment: .topLeading)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                guard width > 1, abs(width - availableWidth) > 0.5 else { return }
                availableWidth = width
            }
    }

    private func exploreZoomSourceID(moment: Moment, index: Int) -> String {
        moment.id ?? "\(zoomIDPrefix)-\(index)"
    }
}

// MARK: - Celda de momento (exclusiva de Explore)

struct ExploreMomentThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    let moment: Moment
    let unitWidth: CGFloat
    let descriptor: ExploreGridTileDescriptor
    var zoomNamespace: Namespace.ID? = nil
    var zoomSourceID: String? = nil
    let onTap: () -> Void

    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    private var cellWidth: CGFloat {
        ExploreMomentsGridMetrics.tileSize(kind: descriptor.layoutKind, unitWidth: unitWidth).width
    }

    private var cellHeight: CGFloat {
        ExploreMomentsGridMetrics.tileSize(kind: descriptor.layoutKind, unitWidth: unitWidth).height
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                mediaBody
                gradientOverlay
                topChrome
                bottomChrome
            }
            .frame(width: cellWidth, height: cellHeight)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(ExploreMomentThumbnailButtonStyle())
        .modifier(ProfileMomentZoomSourceModifier(namespace: zoomNamespace, sourceID: zoomSourceID, cornerRadius: 0))
    }

    @ViewBuilder
    private var mediaBody: some View {
        if descriptor.usesPortraitCrop {
            portraitMedia
        } else if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
            if mediaItem.type == .video {
                if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                    fillImage(urlString: thumbnailUrl, feedCrop: mediaItem.feedCrop)
                } else {
                    generatedVideoThumbnail(videoURL: mediaItem.url)
                }
            } else {
                fillImage(urlString: mediaItem.url, feedCrop: mediaItem.feedCrop)
            }
        } else if let imagePath = moment.previewImageURLString, let url = getImageURL(from: imagePath) {
            KFImage(url)
                .placeholder { placeholder }
                .downsampling(size: CGSize(width: cellWidth, height: cellHeight))
                .scaleFactor(displayScale)
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
                .frame(width: cellWidth, height: cellHeight)
                .clipped()
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private var portraitMedia: some View {
        if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
            if mediaItem.type == .image {
                fillImage(urlString: mediaItem.url, feedCrop: mediaItem.feedCrop)
            } else if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                fillImage(urlString: thumbnailUrl, feedCrop: mediaItem.feedCrop)
            } else {
                generatedVideoThumbnail(videoURL: mediaItem.url)
            }
        } else if let imagePath = moment.previewImageURLString, !imagePath.isEmpty {
            fillImage(urlString: imagePath)
        } else if let video = moment.previewVideoURLString, !video.isEmpty {
            generatedVideoThumbnail(videoURL: video)
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func fillImage(urlString: String, feedCrop: MediaItemFeedCrop? = nil) -> some View {
        if let url = getImageURL(from: urlString) {
            KFImage(url)
                .placeholder { placeholder }
                .applyingFeedCrop(feedCrop)
                .downsampling(size: CGSize(width: cellWidth, height: cellHeight))
                .scaleFactor(displayScale)
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
                .frame(width: cellWidth, height: cellHeight)
                .clipped()
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func generatedVideoThumbnail(videoURL: String) -> some View {
        ZStack {
            if let thumbnail = videoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cellWidth, height: cellHeight)
                    .clipped()
            } else {
                placeholder
                    .overlay {
                        if isLoadingVideoThumbnail {
                            ProgressView()
                                .tint(Color(hex: "667eea"))
                        }
                    }
            }
        }
        .onAppear {
            loadVideoThumbnail(from: videoURL)
        }
    }

    @ViewBuilder
    private var topChrome: some View {
        VStack {
            HStack {
                if moment.isCarouselMoment {
                    MomentCarouselIndicatorIcon()
                        .padding(6)
                }
                Spacer()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if descriptor.showsPlayCue {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)

                if descriptor.showsDuration, let duration = moment.videoDuration {
                    Text(Self.formatVideoDuration(duration))
                        .font(.system(size: legacyPoppinsSize(8), weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.34))
            .clipShape(Capsule())
            .padding(6)
        }
    }

    @ViewBuilder
    private var gradientOverlay: some View {
        if descriptor.showsPlayCue {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.1),
                    Color.clear,
                    Color.black.opacity(descriptor.usesPortraitCrop ? 0.32 : 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.12))
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary.opacity(0.5))
            )
    }

    private func loadVideoThumbnail(from videoURL: String) {
        guard videoThumbnail == nil, !isLoadingVideoThumbnail else { return }

        if let cached = VideoThumbnailCache.shared.cachedThumbnail(for: videoURL) {
            videoThumbnail = cached
            return
        }

        isLoadingVideoThumbnail = true
        Task {
            let image = await VideoThumbnailCache.shared.thumbnail(for: videoURL)
            await MainActor.run {
                isLoadingVideoThumbnail = false
                if let image {
                    videoThumbnail = image
                }
            }
        }
    }

    private static func formatVideoDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ExploreMomentThumbnailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
