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
        } else if moment.isReelCandidate, layoutKind == .tall {
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
            showsDuration: isVideo && (layoutKind == .hero || layoutKind == .tall)
        )
    }
}

enum ExploreBentoTileAssigner {
    /// Patrón mosaic fijo de Explore (cada 12 ítems).
    ///
    /// El masonry coloca en orden de array, así que los héroes van en posiciones
    /// 0 y 11 del ciclo — no en 3/11 como el quilt por filas antiguo.
    /// - 0: héroe 2×2 arriba-izquierda
    /// - 1…10: unidades que rellenan alrededor
    /// - 11: héroe 2×2 abajo-derecha
    ///
    /// Además, hasta 2 verticales (1×2) en slots 4 y 7 si el momento es vídeo/reel.
    static func assign(moments: [Moment]) -> [ExploreGridTileDescriptor] {
        moments.enumerated().map { index, moment in
            let layoutKind = layoutKind(for: moment, at: index)
            return ExploreGridTileDescriptor.standard(for: moment, layoutKind: layoutKind)
        }
    }

    private static func layoutKind(for moment: Moment, at index: Int) -> ExploreBentoTileKind {
        let slot = index % 12

        switch slot {
        case 0, 11:
            return .hero
        case 4, 7 where moment.hasVideoMedia || moment.isReelCandidate:
            return .tall
        default:
            return .unit
        }
    }
}

enum ExploreMomentsGridMetrics {
    static let spacing: CGFloat = 1
    static let columns = 3

    static func columnWidth(for availableWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        return (availableWidth - totalSpacing) / CGFloat(columns)
    }

    static func tileSize(kind: ExploreBentoTileKind, unitWidth: CGFloat, spacing: CGFloat = spacing) -> CGSize {
        switch kind {
        case .unit:
            return CGSize(width: unitWidth, height: unitWidth)
        case .tall:
            return CGSize(width: unitWidth, height: unitWidth * 2 + spacing)
        case .hero:
            let side = unitWidth * 2 + spacing
            return CGSize(width: side, height: side)
        }
    }

    static func bentoHeight(tileKinds: [ExploreBentoTileKind], availableWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
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

func exploreBentoGridHeight(moments: [Moment], availableWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
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

private struct ExploreBentoGridContainer<Cell: View>: View {
    let moments: [Moment]
    let availableWidth: CGFloat
    let descriptors: [ExploreGridTileDescriptor]
    @ViewBuilder let cell: (Moment, CGFloat, Int, ExploreGridTileDescriptor) -> Cell

    private var bentoHeight: CGFloat {
        ExploreMomentsGridMetrics.bentoHeight(
            tileKinds: descriptors.map(\.layoutKind),
            availableWidth: availableWidth
        )
    }

    var body: some View {
        let columnWidth = ExploreMomentsGridMetrics.columnWidth(for: availableWidth)

        ExploreBentoLayout {
            ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                let descriptor = index < descriptors.count
                    ? descriptors[index]
                    : ExploreGridTileDescriptor.standard(for: moment)
                cell(moment, columnWidth, index, descriptor)
                    .exploreBentoTileKind(descriptor.layoutKind)
            }
        }
        .frame(width: availableWidth, height: bentoHeight, alignment: .topLeading)
    }
}

// MARK: - Grid público de Explore

struct ExploreMomentsBentoGrid: View {
    let moments: [Moment]
    var zoomNamespace: Namespace.ID? = nil
    var zoomIDPrefix: String = "explore"
    let onMomentTap: (Moment, Int, [Moment]) -> Void

    private var descriptors: [ExploreGridTileDescriptor] {
        ExploreBentoTileAssigner.assign(moments: moments)
    }

    private var gridWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var gridHeight: CGFloat {
        exploreBentoGridHeight(moments: moments, availableWidth: gridWidth)
    }

    var body: some View {
        ExploreBentoGridContainer(
            moments: moments,
            availableWidth: gridWidth,
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
        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
    }

    private func exploreZoomSourceID(moment: Moment, index: Int) -> String {
        moment.id ?? "\(zoomIDPrefix)-\(index)"
    }
}

// MARK: - Celda de momento (exclusiva de Explore)

struct ExploreMomentThumbnail: View {
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
                    fillImage(urlString: thumbnailUrl)
                } else {
                    generatedVideoThumbnail(videoURL: mediaItem.url)
                }
            } else {
                fillImage(urlString: mediaItem.url)
            }
        } else if let imagePath = moment.previewImageURLString, let url = getImageURL(from: imagePath) {
            KFImage(url)
                .placeholder { placeholder }
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
                fillImage(urlString: mediaItem.url)
            } else if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                fillImage(urlString: thumbnailUrl)
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
    private func fillImage(urlString: String) -> some View {
        if let url = getImageURL(from: urlString) {
            KFImage(url)
                .placeholder { placeholder }
                .downsampling(size: CGSize(width: cellWidth, height: cellHeight))
                .scaleFactor(UIScreen.main.scale)
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
                    .foregroundColor(.white)

                if descriptor.showsDuration, let duration = moment.videoDuration {
                    Text(Self.formatVideoDuration(duration))
                        .font(.custom("Poppins-SemiBold", size: 8))
                        .foregroundColor(.white)
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
                    .foregroundColor(.secondary.opacity(0.5))
            )
    }

    private func loadVideoThumbnail(from videoURL: String) {
        guard videoThumbnail == nil, !isLoadingVideoThumbnail else { return }
        guard let url = URL(string: videoURL) else { return }

        isLoadingVideoThumbnail = true
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        generator.generateCGImagesAsynchronously(
            forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 1))]
        ) { _, cgImage, _, _, _ in
            DispatchQueue.main.async {
                isLoadingVideoThumbnail = false
                if let cgImage {
                    videoThumbnail = UIImage(cgImage: cgImage)
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
