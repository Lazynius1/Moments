import SwiftUI

enum BentoTileKind: Equatable {
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

enum ProfileGridVisualRole: Equatable {
    case photo
    case video
    case reelHero
    case reelTall
    case featuredPinned
}

struct ProfileGridTileDescriptor: Equatable {
    let layoutKind: BentoTileKind
    let visualRole: ProfileGridVisualRole
    let showsPlayCue: Bool
    let showsDuration: Bool
    let showsPin: Bool
    let showsScheduledCue: Bool

    var usesPortraitCrop: Bool {
        visualRole == .reelHero || visualRole == .reelTall
    }

    static func standard(for moment: Moment, layoutKind: BentoTileKind = .unit) -> ProfileGridTileDescriptor {
        let isVideo = moment.hasVideoMedia
        let visualRole: ProfileGridVisualRole

        if moment.isPinned == true, layoutKind == .hero {
            visualRole = moment.isReelCandidate ? .reelHero : .featuredPinned
        } else if moment.isReelCandidate, layoutKind == .hero {
            visualRole = .reelHero
        } else if moment.isReelCandidate, layoutKind == .tall {
            visualRole = .reelTall
        } else if isVideo {
            visualRole = .video
        } else {
            visualRole = .photo
        }

        return ProfileGridTileDescriptor(
            layoutKind: layoutKind,
            visualRole: visualRole,
            showsPlayCue: isVideo,
            showsDuration: isVideo && (layoutKind == .hero || layoutKind == .tall),
            showsPin: moment.isPinned == true,
            showsScheduledCue: moment.isScheduled
        )
    }
}

enum ProfileBentoTileAssigner {
    static func assign(moments: [Moment]) -> [ProfileGridTileDescriptor] {
        guard !moments.isEmpty else { return [] }

        // Hero/tall se decide en orden cronológico (ignorando pines) y se aplica por id.
        // Así pinear solo reordena + badge, sin promover a hero ni cambiar tamaños.
        let chronological = moments.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return (lhs.id ?? "") < (rhs.id ?? "")
        }

        var chronoKinds = Array(repeating: BentoTileKind.unit, count: chronological.count)
        if let heroIndex = heroCandidateIndex(in: chronological) {
            chronoKinds[heroIndex] = .hero
        }

        var tallCount = 0
        for index in chronological.indices {
            guard index < 12 else { break }
            guard chronoKinds[index] == .unit else { continue }
            guard tallCount < 2 else { break }
            guard chronological[index].isReelCandidate else { continue }
            chronoKinds[index] = .tall
            tallCount += 1
        }

        var kindsByMomentId: [String: BentoTileKind] = [:]
        for (moment, kind) in zip(chronological, chronoKinds) {
            if let id = moment.id {
                kindsByMomentId[id] = kind
            }
        }

        return moments.map { moment in
            let kind = moment.id.flatMap { kindsByMomentId[$0] } ?? .unit
            return ProfileGridTileDescriptor.standard(for: moment, layoutKind: kind)
        }
    }

    static func simple(moments: [Moment]) -> [ProfileGridTileDescriptor] {
        moments.map { ProfileGridTileDescriptor.standard(for: $0) }
    }

    private static func heroCandidateIndex(in moments: [Moment]) -> Int? {
        let candidates = Array(moments.indices.prefix(min(moments.count, 9)))
        return candidates.first(where: { moments[$0].isReelCandidate })
    }
}

private struct BentoTileKindLayoutKey: LayoutValueKey {
    static let defaultValue: BentoTileKind = .unit
}

extension View {
    func bentoTileKind(_ kind: BentoTileKind) -> some View {
        layoutValue(key: BentoTileKindLayoutKey.self, value: kind)
    }
}

struct ProfileBentoLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    init(columns: Int = ProfileMomentsGridMetrics.columns, spacing: CGFloat = ProfileMomentsGridMetrics.spacing) {
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
            let kind = subview[BentoTileKindLayoutKey.self]
            let tileSize = ProfileMomentsGridMetrics.tileSize(kind: kind, unitWidth: unitWidth, spacing: spacing)
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
            let kind = subview[BentoTileKindLayoutKey.self]
            let tileSize = ProfileMomentsGridMetrics.tileSize(kind: kind, unitWidth: unitWidth, spacing: spacing)
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

struct ProfileMomentsBentoGrid<Cell: View>: View {
    let moments: [Moment]
    let availableWidth: CGFloat
    let descriptors: [ProfileGridTileDescriptor]
    @ViewBuilder let cell: (Moment, CGFloat, Int, ProfileGridTileDescriptor) -> Cell

    private var bentoHeight: CGFloat {
        ProfileMomentsGridMetrics.bentoHeight(
            tileKinds: descriptors.map(\.layoutKind),
            availableWidth: availableWidth
        )
    }

    var body: some View {
        let columnWidth = ProfileMomentsGridMetrics.columnWidth(for: availableWidth)

        ProfileBentoLayout {
            ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                let descriptor = index < descriptors.count ? descriptors[index] : ProfileGridTileDescriptor.standard(for: moment)
                cell(moment, columnWidth, index, descriptor)
                    .bentoTileKind(descriptor.layoutKind)
            }
        }
        .frame(width: availableWidth, height: bentoHeight, alignment: .topLeading)
    }
}
