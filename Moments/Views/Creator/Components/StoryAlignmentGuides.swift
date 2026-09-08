import Combine
import Kingfisher
import SwiftUI
import UIKit

enum StoryAlignmentGuideMetrics {
    static let snapThreshold: CGFloat = 8
    static let displayThreshold: CGFloat = 12
    static let lineWidth: CGFloat = 1.5
    static let color = Color(hex: "5AC8FA")
    static let sideInset: CGFloat = 16
    static let headerCenterY: CGFloat = 26
    static let headerHeight: CGFloat = 40
    static var headerBottomY: CGFloat { headerCenterY + headerHeight / 2 }
    static func bottomEdgeY(canvasHeight: CGFloat) -> CGFloat { canvasHeight - headerBottomY }
    static let chromeOpacity: Double = 0.62
    static let topScrimHeight: CGFloat = 96
    static let dotDash: [CGFloat] = [0.2, 6.5]
    static let markArm: CGFloat = 11
    static let markGap: CGFloat = 3.5
}

struct StoryAlignmentGuideSnapshot: Equatable {
    var showsVerticalCenter = false
    var showsHorizontalCenter = false
    var showsLeft = false
    var showsRight = false
    var showsTopEdge = false
    var showsBottomEdge = false

    static let empty = StoryAlignmentGuideSnapshot()

    var isEmpty: Bool {
        !showsVerticalCenter && !showsHorizontalCenter && !showsLeft && !showsRight && !showsTopEdge && !showsBottomEdge
    }

    var engagementTokens: Set<String> {
        var tokens = Set<String>()
        if showsVerticalCenter { tokens.insert("vc") }
        if showsHorizontalCenter { tokens.insert("hc") }
        if showsLeft { tokens.insert("left") }
        if showsRight { tokens.insert("right") }
        if showsTopEdge { tokens.insert("top") }
        if showsBottomEdge { tokens.insert("bottom") }
        return tokens
    }
}

final class StoryAlignmentGuideBroker: ObservableObject {
    @Published var isActive = false
    @Published var snapshot = StoryAlignmentGuideSnapshot.empty

    func publish(_ next: StoryAlignmentGuideSnapshot) {
        if !isActive {
            isActive = true
        }
        guard snapshot != next else { return }
        storyAlignmentHapticIfNeeded(from: snapshot, to: next)
        snapshot = next
    }

    func clear() {
        guard isActive || snapshot != .empty else { return }
        isActive = false
        snapshot = .empty
    }
}

func storyAlignmentHapticIfNeeded(
    from previous: StoryAlignmentGuideSnapshot,
    to next: StoryAlignmentGuideSnapshot
) {
    let gained = next.engagementTokens.subtracting(previous.engagementTokens)
    guard !gained.isEmpty else { return }
    HapticManager.shared.selection()
}

func storySanitizedLayoutSize(_ size: CGSize, fallback: CGFloat = 120) -> CGSize {
    let width = size.width.isFinite && size.width > 1 ? min(size.width, 2048) : fallback
    let height = size.height.isFinite && size.height > 1 ? min(size.height, 2048) : fallback
    return CGSize(width: width, height: height)
}

func storyApplyAlignmentSnap(
    proposed: CGPoint,
    itemSize: CGSize,
    canvasSize: CGSize
) -> CGPoint {
    guard canvasSize.width > 8, canvasSize.height > 8 else { return proposed }
    let threshold = StoryAlignmentGuideMetrics.snapThreshold
    let width = max(itemSize.width, 1)
    let height = max(itemSize.height, 1)
    let midX = canvasSize.width / 2
    let midY = canvasSize.height / 2
    let inset = StoryAlignmentGuideMetrics.sideInset
    let headerBottom = StoryAlignmentGuideMetrics.headerBottomY
    let bottomEdge = StoryAlignmentGuideMetrics.bottomEdgeY(canvasHeight: canvasSize.height)
    var x = proposed.x
    var y = proposed.y

    if abs(proposed.x - midX) <= threshold {
        x = midX
    } else {
        let left = proposed.x - width / 2
        let right = proposed.x + width / 2
        if abs(left - inset) <= threshold {
            x = inset + width / 2
        } else if abs(right - (canvasSize.width - inset)) <= threshold {
            x = canvasSize.width - inset - width / 2
        }
    }

    if abs(proposed.y - midY) <= threshold {
        y = midY
    } else {
        let top = proposed.y - height / 2
        let bottom = proposed.y + height / 2
        if abs(top - headerBottom) <= threshold {
            y = headerBottom + height / 2
        } else if abs(bottom - bottomEdge) <= threshold {
            y = bottomEdge - height / 2
        }
    }

    return CGPoint(x: x, y: y)
}

func storyAlignAndKeepVisible(
    proposed: CGPoint,
    itemSize: CGSize,
    canvasSize: CGSize,
    overTrash: Bool,
    broker: StoryAlignmentGuideBroker
) -> CGPoint {
    guard !overTrash else {
        broker.clear()
        return storyKeepOverlayVisibleCenter(proposed, canvasSize: canvasSize)
    }
    let snapped = storyApplyAlignmentSnap(
        proposed: proposed,
        itemSize: itemSize,
        canvasSize: canvasSize
    )
    let clamped = storyKeepOverlayVisibleCenter(snapped, canvasSize: canvasSize)
    broker.publish(
        storyAlignmentGuides(
            center: clamped,
            itemSize: itemSize,
            canvasSize: canvasSize
        )
    )
    return clamped
}

func storyAlignmentGuides(
    center: CGPoint,
    itemSize: CGSize,
    canvasSize: CGSize
) -> StoryAlignmentGuideSnapshot {
    guard canvasSize.width > 8, canvasSize.height > 8 else { return .empty }
    let threshold = StoryAlignmentGuideMetrics.displayThreshold
    let width = max(itemSize.width, 1)
    let height = max(itemSize.height, 1)
    let left = center.x - width / 2
    let right = center.x + width / 2
    let top = center.y - height / 2
    let bottom = center.y + height / 2
    let inset = StoryAlignmentGuideMetrics.sideInset
    let headerBottom = StoryAlignmentGuideMetrics.headerBottomY
    let bottomEdge = StoryAlignmentGuideMetrics.bottomEdgeY(canvasHeight: canvasSize.height)

    return StoryAlignmentGuideSnapshot(
        showsVerticalCenter: abs(center.x - canvasSize.width / 2) <= threshold,
        showsHorizontalCenter: abs(center.y - canvasSize.height / 2) <= threshold,
        showsLeft: abs(left - inset) <= threshold,
        showsRight: abs(right - (canvasSize.width - inset)) <= threshold,
        showsTopEdge: abs(top - headerBottom) <= threshold,
        showsBottomEdge: abs(bottom - bottomEdge) <= threshold
    )
}

struct StoryAlignmentGuidesOverlay: View {
    @ObservedObject var broker: StoryAlignmentGuideBroker
    let canvasSize: CGSize

    var body: some View {
        let snapshot = broker.snapshot
        ZStack {
            if snapshot.showsTopEdge {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.46),
                        Color.black.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: canvasSize.width, height: StoryAlignmentGuideMetrics.topScrimHeight)
                .position(
                    x: canvasSize.width / 2,
                    y: StoryAlignmentGuideMetrics.topScrimHeight / 2
                )

                StoryAlignmentHeaderChromePreview()
                    .padding(.horizontal, 16)
                    .frame(width: canvasSize.width, height: StoryAlignmentGuideMetrics.headerHeight, alignment: .center)
                    .position(x: canvasSize.width / 2, y: StoryAlignmentGuideMetrics.headerCenterY)
                    .opacity(StoryAlignmentGuideMetrics.chromeOpacity)
            }

            Canvas { context, _ in
                storyDrawAlignmentGuides(
                    context: context,
                    canvasSize: canvasSize,
                    snapshot: snapshot
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .animation(nil, value: broker.isActive)
        .animation(nil, value: snapshot)
    }
}

private func storyDrawAlignmentGuides(
    context: GraphicsContext,
    canvasSize: CGSize,
    snapshot: StoryAlignmentGuideSnapshot
) {
    guard !snapshot.isEmpty else { return }
    let color = StoryAlignmentGuideMetrics.color
    let inset = StoryAlignmentGuideMetrics.sideInset
    let headerBottom = StoryAlignmentGuideMetrics.headerBottomY
    let bottomEdge = StoryAlignmentGuideMetrics.bottomEdgeY(canvasHeight: canvasSize.height)
    let dotted = StrokeStyle(
        lineWidth: StoryAlignmentGuideMetrics.lineWidth,
        lineCap: .round,
        dash: StoryAlignmentGuideMetrics.dotDash
    )
    let mark = StrokeStyle(
        lineWidth: StoryAlignmentGuideMetrics.lineWidth,
        lineCap: .round
    )

    var xs: [CGFloat] = []
    var ys: [CGFloat] = []
    if snapshot.showsLeft { xs.append(inset) }
    if snapshot.showsVerticalCenter { xs.append(canvasSize.width / 2) }
    if snapshot.showsRight { xs.append(canvasSize.width - inset) }
    if snapshot.showsTopEdge { ys.append(headerBottom) }
    if snapshot.showsHorizontalCenter { ys.append(canvasSize.height / 2) }
    if snapshot.showsBottomEdge { ys.append(bottomEdge) }

    for x in xs {
        storyStrokeGuideLine(
            context: context,
            from: CGPoint(x: x, y: 0),
            to: CGPoint(x: x, y: canvasSize.height),
            color: color.opacity(0.88),
            style: dotted
        )
    }
    for y in ys {
        storyStrokeGuideLine(
            context: context,
            from: CGPoint(x: 0, y: y),
            to: CGPoint(x: canvasSize.width, y: y),
            color: color.opacity(0.88),
            style: dotted
        )
    }

    for x in xs {
        for y in ys {
            let isSide = x == inset || x == canvasSize.width - inset
            let isTopCorner = isSide && y == headerBottom
            let isBottomCorner = isSide && y == bottomEdge
            if isTopCorner || isBottomCorner {
                storyDrawCornerMark(
                    context: context,
                    at: CGPoint(x: x, y: y),
                    towardTrailing: x == inset,
                    towardBottom: isTopCorner,
                    color: color,
                    style: mark
                )
            } else {
                storyDrawCropPlus(
                    context: context,
                    at: CGPoint(x: x, y: y),
                    color: color,
                    style: mark
                )
            }
        }
    }
}

private func storyStrokeGuideLine(
    context: GraphicsContext,
    from: CGPoint,
    to: CGPoint,
    color: Color,
    style: StrokeStyle
) {
    var path = Path()
    path.move(to: from)
    path.addLine(to: to)
    context.stroke(path, with: .color(color), style: style)
}

private func storyDrawCropPlus(
    context: GraphicsContext,
    at point: CGPoint,
    color: Color,
    style: StrokeStyle
) {
    let arm = StoryAlignmentGuideMetrics.markArm
    let gap = StoryAlignmentGuideMetrics.markGap
    storyStrokeGuideLine(
        context: context,
        from: CGPoint(x: point.x, y: point.y - gap - arm),
        to: CGPoint(x: point.x, y: point.y - gap),
        color: color,
        style: style
    )
    storyStrokeGuideLine(
        context: context,
        from: CGPoint(x: point.x, y: point.y + gap),
        to: CGPoint(x: point.x, y: point.y + gap + arm),
        color: color,
        style: style
    )
    storyStrokeGuideLine(
        context: context,
        from: CGPoint(x: point.x - gap - arm, y: point.y),
        to: CGPoint(x: point.x - gap, y: point.y),
        color: color,
        style: style
    )
    storyStrokeGuideLine(
        context: context,
        from: CGPoint(x: point.x + gap, y: point.y),
        to: CGPoint(x: point.x + gap + arm, y: point.y),
        color: color,
        style: style
    )
}

private func storyDrawCornerMark(
    context: GraphicsContext,
    at point: CGPoint,
    towardTrailing: Bool,
    towardBottom: Bool,
    color: Color,
    style: StrokeStyle
) {
    let arm = StoryAlignmentGuideMetrics.markArm
    let h = towardTrailing ? arm : -arm
    let v = towardBottom ? arm : -arm
    storyStrokeGuideLine(
        context: context,
        from: point,
        to: CGPoint(x: point.x + h, y: point.y),
        color: color,
        style: style
    )
    storyStrokeGuideLine(
        context: context,
        from: point,
        to: CGPoint(x: point.x, y: point.y + v),
        color: color,
        style: style
    )
}

/// Ghost fijo del `glassmorphicHeader`: avatar, usuario, ellipsis y X.
private struct StoryAlignmentHeaderChromePreview: View {
    @State private var username = ""
    @State private var profileImagePath: String?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    if let profileImagePath, let url = URL(string: profileImagePath) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 38, height: 38)

                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.system(size: 28))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(username)
                            .foregroundStyle(.white)
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .lineLimit(1)

                        CurrentUserVerifiedBadge(size: 12)
                    }

                    Text(NSLocalizedString("time.now", comment: "Just now"))
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(size: legacyPoppinsSize(11)))
                }
            }

            Spacer()

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.92))
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)

                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.92))
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)
            }
        }
        .onAppear {
            let user = LocalPersistenceService.shared.loadCurrentUser()
            username = user?.username ?? ""
            profileImagePath = user?.profileImagePath
        }
    }
}
