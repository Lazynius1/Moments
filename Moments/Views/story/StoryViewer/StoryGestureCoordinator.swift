import SwiftUI
enum StoryGestureIntent: Hashable {
    case deckSwipe
    case storyNavigationTap
    case holdPause
    case replySwipe
    case revealScratch
    case interactiveStickerTap
    case interactiveStickerPan
    case chainControlTap
}
enum StoryGestureSuppressionScope: Int, Comparable, Hashable {
    case allowAll = 0
    case suppressDeck = 1
    case suppressStoryNavigation = 2
    case suppressViewerGestures = 3
    static func < (lhs: StoryGestureSuppressionScope, rhs: StoryGestureSuppressionScope) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
struct StoryGestureRegion: Equatable, Identifiable {
    let id: String
    let rect: CGRect
    let intents: Set<StoryGestureIntent>
    let suppressionScope: StoryGestureSuppressionScope
}
/// Árbitro único de gestos del visor (tap, hold, deck, reply, stickers, reveal).
@MainActor
struct StoryGestureCoordinator {
    static let navigationSideWidthFraction: CGFloat = 0.20
    static let minNavigationSideWidth: CGFloat = 64
    static let revealSidePassthroughFraction: CGFloat = 0.14
    let topProtectedHeight: CGFloat = 180
    let topRightProtectedInset: CGFloat = 120
    let topRightProtectedHeight: CGFloat = 220
    let bottomProtectedInset: CGFloat = 170

    func isInTopProtectedChrome(_ point: CGPoint, screenSize: CGSize) -> Bool {
        if point.y < topProtectedHeight {
            return true
        }
        if point.y < topRightProtectedHeight && point.x > screenSize.width - topRightProtectedInset {
            return true
        }
        return false
    }

    func isInBottomProtectedChrome(_ point: CGPoint, screenSize: CGSize) -> Bool {
        point.y > screenSize.height - bottomProtectedInset
    }

    func navigationSideWidth(for canvasWidth: CGFloat) -> CGFloat {
        max(canvasWidth * Self.navigationSideWidthFraction, Self.minNavigationSideWidth)
    }
    
    func leftNavigationFrame(in canvasRect: CGRect) -> CGRect {
        CGRect(
            x: canvasRect.minX,
            y: canvasRect.minY,
            width: navigationSideWidth(for: canvasRect.width),
            height: canvasRect.height
        )
    }
    
    func rightNavigationFrame(in canvasRect: CGRect) -> CGRect {
        CGRect(
            x: canvasRect.maxX - navigationSideWidth(for: canvasRect.width),
            y: canvasRect.minY,
            width: navigationSideWidth(for: canvasRect.width),
            height: canvasRect.height
        )
    }
    
    func isInNavigationEdgeBand(_ point: CGPoint, canvasRect: CGRect) -> Bool {
        leftNavigationFrame(in: canvasRect).contains(point) || rightNavigationFrame(in: canvasRect).contains(point)
     }
    
    func region(
        containing point: CGPoint,
        in regions: [StoryGestureRegion],
        supporting intent: StoryGestureIntent? = nil
    ) -> StoryGestureRegion? {
        regions.first { region in
            guard region.rect.contains(point) else { return false }
            guard let intent else { return true }
            return region.intents.contains(intent)
        }
    }

    
    func shouldAllowDeckSwipeStart(
        at point: CGPoint,
        screenRect: CGRect,
        regions: [StoryGestureRegion],
        gate: StoryDeckGestureGate?
    ) -> Bool {
        guard gate?.suppressDeckNavigation != true else { return false }
        let leftBand = CGRect(
            x: screenRect.minX,
            y: screenRect.minY,
            width: navigationSideWidth(for: screenRect.width),
            height: screenRect.height
        )
        let rightBand = CGRect(
            x: screenRect.maxX - navigationSideWidth(for: screenRect.width),
            y: screenRect.minY,
            width: navigationSideWidth(for: screenRect.width),
            height: screenRect.height
        )
        guard leftBand.contains(point) || rightBand.contains(point) else { return false }
        if let region = region(containing: point, in: regions, supporting: .deckSwipe) {
            return region.suppressionScope < .suppressDeck
        }
        return true
        
    }
    
    func shouldAllowHoldStart(
        at point: CGPoint,
        screenSize: CGSize,
        canvasRect: CGRect,
        regions: [StoryGestureRegion],
        gate: StoryDeckGestureGate?,
        isKeyboardVisible: Bool,
        overlaysBlocked: Bool
    ) -> Bool {
        guard !isKeyboardVisible, !overlaysBlocked else { return false }
        guard gate?.suppressViewerGestures != true, gate?.suppressStoryNavigationGestures != true else { return false }
        guard !isInTopProtectedChrome(point, screenSize: screenSize) else { return false }
        guard !isInBottomProtectedChrome(point, screenSize: screenSize) else { return false }
        guard !isInNavigationEdgeBand(point, canvasRect: canvasRect) else { return false }
        return region(containing: point, in: regions, supporting: .holdPause) == nil
    }

    func shouldAllowUnifiedViewerDragStart(
        at point: CGPoint,
        screenSize: CGSize,
        canvasRect: CGRect,
        regions: [StoryGestureRegion],
        gate: StoryDeckGestureGate?,
        overlaysBlocked: Bool
    ) -> Bool {
        guard !overlaysBlocked else { return false }
        guard gate?.suppressViewerGestures != true, gate?.suppressStoryNavigationGestures != true else { return false }
        guard !isInTopProtectedChrome(point, screenSize: screenSize) else { return false }
        guard !isInNavigationEdgeBand(point, canvasRect: canvasRect) else { return false }
        return region(containing: point, in: regions, supporting: .replySwipe) == nil
    }


    func shouldSuppressNavigationTap(
        at point: CGPoint,
        in canvasRect: CGRect,
        regions: [StoryGestureRegion],
        gate: StoryDeckGestureGate?
    ) -> Bool {
        guard leftNavigationFrame(in: canvasRect).contains(point) || rightNavigationFrame(in: canvasRect).contains(point) else {
            return true
        }
        if gate?.suppressStoryNavigationGestures == true || gate?.suppressViewerGestures == true {
            return true
        }
        if let region = region(containing: point, in: regions, supporting: .storyNavigationTap) {
            return region.suppressionScope >= .suppressStoryNavigation
        }
        return false
    }
    func isInTopOrBottomProtectedChrome(_ point: CGPoint, screenSize: CGSize) -> Bool {
        if point.y < topProtectedHeight {
            return true
        }
        if point.y < topRightProtectedHeight && point.x > screenSize.width - topRightProtectedInset {
            return true
        }
        if point.y > screenSize.height - bottomProtectedInset {
            return true
        }
        return false
    }
}
