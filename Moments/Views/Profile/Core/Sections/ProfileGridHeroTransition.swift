import SwiftUI

// MARK: - Detail video gate (hero expand: solo el flying hero reproduce hasta fase .detail)

private struct ProfileDetailVideoPlaybackKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var profileDetailVideoPlaybackEnabled: Bool {
        get { self[ProfileDetailVideoPlaybackKey.self] }
        set { self[ProfileDetailVideoPlaybackKey.self] = newValue }
    }
}

private struct ProfileHeroShowsChromeKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ProfileHeroChromeOpacityKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct ProfileHeroShowsAudienceKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Avatar/cápsula del hero: ocultar durante el crossfade al detalle.
    var profileHeroShowsChrome: Bool {
        get { self[ProfileHeroShowsChromeKey.self] }
        set { self[ProfileHeroShowsChromeKey.self] = newValue }
    }

    /// Footer del peek: se desvanece antes que el media al cerrar.
    var profileHeroChromeOpacity: CGFloat {
        get { self[ProfileHeroChromeOpacityKey.self] }
        set { self[ProfileHeroChromeOpacityKey.self] = newValue }
    }

    /// Icono de audiencia en el footer: solo perfil propio (privado en perfil ajeno).
    var profileHeroShowsAudience: Bool {
        get { self[ProfileHeroShowsAudienceKey.self] }
        set { self[ProfileHeroShowsAudienceKey.self] = newValue }
    }
}

private struct ProfileDetailDirectVideoPlaybackKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Entrada hero → detalle: el player del detalle no depende del umbral de visibilidad del feed.
    var profileDetailDirectVideoPlayback: Bool {
        get { self[ProfileDetailDirectVideoPlaybackKey.self] }
        set { self[ProfileDetailDirectVideoPlaybackKey.self] = newValue }
    }
}

private struct ProfileGridHeroTransitionCoordinatorKey: EnvironmentKey {
    static let defaultValue: ProfileGridHeroTransitionCoordinator? = nil
}

extension EnvironmentValues {
    var profileGridHeroTransitionCoordinator: ProfileGridHeroTransitionCoordinator? {
        get { self[ProfileGridHeroTransitionCoordinatorKey.self] }
        set { self[ProfileGridHeroTransitionCoordinatorKey.self] = newValue }
    }
}

// MARK: - Entry kind

enum ProfileMomentDetailEntryKind: Equatable {
    case direct
    case hero(sourceFrame: CGRect)
}

// MARK: - Thumbnail frame reporting

struct ProfileGridThumbnailFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func profileGridThumbnailFrameReporter(momentId: String, coordinateSpace: CoordinateSpaceProtocol) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ProfileGridThumbnailFramePreferenceKey.self,
                    value: [momentId: geometry.frame(in: coordinateSpace)]
                )
            }
        }
    }

    /// La celda origen queda vacía mientras el hero sale y vuelve al cerrar.
    func profileGridLiftedSource(moment: Moment, gridIndex: Int) -> some View {
        modifier(ProfileGridLiftedSourceModifier(moment: moment, gridIndex: gridIndex))
    }
}

private struct ProfileGridLiftedSourceModifier: ViewModifier {
    @Environment(\.profileGridHeroTransitionCoordinator) private var coordinator
    @Environment(\.colorScheme) private var colorScheme

    let moment: Moment
    let gridIndex: Int

    private var holeBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    func body(content: Content) -> some View {
        if let coordinator {
            ProfileGridLiftedSourceContent(
                coordinator: coordinator,
                moment: moment,
                gridIndex: gridIndex,
                holeBackground: holeBackground
            ) {
                content
            }
        } else {
            content
        }
    }
}

// Observa el coordinator para que la celda se re-renderice al cambiar peekProgress
// y el hueco se vacíe al salir el hero y se rellene al volver.
private struct ProfileGridLiftedSourceContent<Content: View>: View {
    @ObservedObject var coordinator: ProfileGridHeroTransitionCoordinator
    let moment: Moment
    let gridIndex: Int
    let holeBackground: Color
    @ViewBuilder let content: () -> Content

    private var contentOpacity: CGFloat {
        coordinator.liftedGridSourceContentOpacity(moment: moment, gridIndex: gridIndex)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(holeBackground)
                .opacity(1 - contentOpacity)

            content()
                .opacity(contentOpacity)
        }
    }
}

// MARK: - Layout

// MARK: - Motion (curvas y presentación estilo Apple)

enum ProfileGridHeroMotion {
    static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    static func easeOut(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return 1 - pow(1 - x, 3)
    }

    static func remap(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return min(max((value - start) / (end - start), 0), 1)
    }
}

struct ProfileGridHeroPresentation {
    let frame: CGRect
    let cornerRadius: CGFloat
    let scale: CGFloat
    let opacity: CGFloat
    let shadowRadius: CGFloat
    let shadowOpacity: CGFloat
}

enum ProfileGridHeroLayout {
    static let maxCardWidth: CGFloat = 350
    static let peekCornerRadius: CGFloat = FeedMomentCardLayout.mediaCornerRadius
    static let detailCornerRadius: CGFloat = FeedMomentCardLayout.mediaCornerRadius
    static let thumbnailCornerRadius: CGFloat = FeedMomentCardLayout.mediaCornerRadius
    static let horizontalPadding: CGFloat = 16
    static let detailHeaderBlockHeight: CGFloat = 80
    static let menuSpacing: CGFloat = 14
    static let peekFooterHeight: CGFloat = 56
    /// Mínimo width/height → retrato más alto (3:4 → altura = width × 4/3)
    static let peekMinWidthOverHeight: CGFloat = 3.0 / 4.0
    /// Máximo width/height → landscape (16:9)
    static let peekMaxWidthOverHeight: CGFloat = 16.0 / 9.0

    // Lift (vídeo ref. ~0.52s abrir / ~0.36s cerrar): smooth, sin rebote.
    static let peekLiftAnimation = Animation.smooth(duration: 0.46, extraBounce: 0)
    static let peekDismissAnimation = Animation.smooth(duration: 0.31, extraBounce: 0)
    static let peekSpring = peekLiftAnimation
    static let expandSpring = Animation.spring(response: 0.48, dampingFraction: 0.9)
    static let retractSpring = Animation.spring(response: 0.5, dampingFraction: 0.96)
    static let dismissSpring = peekDismissAnimation
    static let revealSmooth = Animation.smooth(duration: 0.34, extraBounce: 0)
    static let hideSmooth = Animation.smooth(duration: 0.26, extraBounce: 0)

    static let retractPeekSplit: CGFloat = 0.34
    static let retractFadeStart: CGFloat = 0.74

    /// El hueco aparece en los primeros ~14% del lift; al cerrar vuelve en el tramo final.
    static func liftedSourceThumbnailOpacity(peekProgress: CGFloat) -> CGFloat {
        ProfileGridHeroMotion.smoothstep(1 - min(1, peekProgress / 0.14))
    }

    /// Crece anclado en la celda, luego flota al centro (no lerp lineal único).
    static func peekHeroFrame(origin: CGRect, destination: CGRect, progress: CGFloat) -> CGRect {
        let growT = ProfileGridHeroMotion.smoothstep(min(1, progress / 0.50))
        let moveT = ProfileGridHeroMotion.smoothstep(
            ProfileGridHeroMotion.remap(progress, start: 0.20, end: 0.92)
        )

        let grownWidth = origin.width + (destination.width - origin.width) * growT
        let grownHeight = origin.height + (destination.height - origin.height) * growT
        let grownX = origin.midX - grownWidth / 2
        let grownY = origin.midY - grownHeight / 2

        return CGRect(
            x: grownX + (destination.origin.x - grownX) * moveT,
            y: grownY + (destination.origin.y - grownY) * moveT,
            width: grownWidth + (destination.width - grownWidth) * moveT,
            height: grownHeight + (destination.height - grownHeight) * moveT
        )
    }

    static func peekHeroCornerRadius(progress: CGFloat) -> CGFloat {
        let t = ProfileGridHeroMotion.smoothstep(
            ProfileGridHeroMotion.remap(progress, start: 0.08, end: 0.62)
        )
        return lerp(thumbnailCornerRadius, peekCornerRadius, t: t)
    }

    static func gridSourceKey(moment: Moment, index: Int) -> String {
        moment.id ?? "profile-grid-\(index)"
    }

    static func parsedAspectRatio(_ value: String?) -> CGFloat {
        guard let value,
              let separator = value.firstIndex(where: { $0 == ":" || $0 == "/" }) else {
            return 1
        }
        let lhs = Double(value[..<separator]) ?? 1
        let rhs = Double(value[value.index(after: separator)...]) ?? 1
        guard rhs > 0 else { return 1 }
        return CGFloat(lhs / rhs)
    }

    static func clampedPeekWidthOverHeight(_ aspectRatio: String?) -> CGFloat {
        let ratio = parsedAspectRatio(aspectRatio)
        return min(max(ratio, peekMinWidthOverHeight), peekMaxWidthOverHeight)
    }

    static func mediaHeight(width: CGFloat, aspectRatio: String?) -> CGFloat {
        width / clampedPeekWidthOverHeight(aspectRatio)
    }

    static func peekCardHeight(width: CGFloat, aspectRatio: String?) -> CGFloat {
        mediaHeight(width: width, aspectRatio: aspectRatio) + peekFooterHeight
    }

    static func cardWidth(for containerWidth: CGFloat) -> CGFloat {
        min(containerWidth - 32, maxCardWidth)
    }

    static func peekCardFrame(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets,
        moment: Moment,
        showPinConfirm: Bool,
        menuBlockHeight: CGFloat
    ) -> CGRect {
        let width = cardWidth(for: containerSize.width)
        let height = peekCardHeight(width: width, aspectRatio: moment.aspectRatio)
        let x = (containerSize.width - width) / 2

        let menuHeight: CGFloat = showPinConfirm ? 220 : menuBlockHeight
        let stackHeight = height + menuSpacing + menuHeight
        let minCenter = safeAreaInsets.top + 20 + (stackHeight / 2)
        let maxCenter = containerSize.height - safeAreaInsets.bottom - 20 - (stackHeight / 2)
        let preferred = containerSize.height / 2
        let centerY: CGFloat = {
            if minCenter > maxCenter { return containerSize.height / 2 }
            return max(minCenter, min(preferred, maxCenter))
        }()

        let cardTopY = centerY - (stackHeight / 2)
        return CGRect(x: x, y: cardTopY, width: width, height: height)
    }

    static func detailMediaFrame(
        screenSize: CGSize,
        safeAreaInsets: EdgeInsets,
        moment: Moment,
        availableHeight: CGFloat
    ) -> CGRect {
        let width = screenSize.width - (horizontalPadding * 2)
        let ratio = parsedAspectRatio(moment.aspectRatio)
        let calculatedHeight = width / max(ratio, 0.55)
        let maxHeight: CGFloat = ratio < 0.85 ? 550 : (ratio > 1.2 ? 300 : 450)
        let height = min(calculatedHeight, maxHeight)
        let x = horizontalPadding
        let y = safeAreaInsets.top + detailHeaderBlockHeight
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func lerp(_ a: CGRect, _ b: CGRect, t: CGFloat, easing: (CGFloat) -> CGFloat = ProfileGridHeroMotion.smoothstep) -> CGRect {
        let clamped = easing(min(max(t, 0), 1))
        return CGRect(
            x: a.origin.x + (b.origin.x - a.origin.x) * clamped,
            y: a.origin.y + (b.origin.y - a.origin.y) * clamped,
            width: a.width + (b.width - a.width) * clamped,
            height: a.height + (b.height - a.height) * clamped
        )
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat, easing: (CGFloat) -> CGFloat = ProfileGridHeroMotion.smoothstep) -> CGFloat {
        let clamped = easing(min(max(t, 0), 1))
        return a + (b - a) * clamped
    }

    static func fallbackThumbnailFrame(in containerSize: CGSize) -> CGRect {
        let side = min(containerSize.width / 3 - 8, 140)
        return CGRect(
            x: (containerSize.width - side) / 2,
            y: containerSize.height * 0.42,
            width: side,
            height: side
        )
    }
}

// MARK: - Coordinator

@MainActor
final class ProfileGridHeroTransitionCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case menuPeek(ProfileGridMomentMenuSelection)
        case expanding(ProfileMomentDetailRoute)
        case retracting(ProfileMomentDetailRoute)
        case detail(ProfileMomentDetailRoute)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var sourceFrame: CGRect = .zero
    @Published var peekProgress: CGFloat = 0
    @Published var expandProgress: CGFloat = 0
    @Published var collapseProgress: CGFloat = 0
    @Published var menuOpacity: CGFloat = 0
    @Published var detailContentOpacity: CGFloat = 0
    @Published var scrimOpacity: CGFloat = 0
    @Published var showPinConfirm = false
    @Published var toastMessage: String?
    @Published var isDismissingInteractively = false
    @Published private(set) var menuKind: ProfileGridHeroMenuKind = .owner

    // Context menu callbacks (configured by the profile view owner)
    var onEdit: ((Moment) -> Void)? = nil
    var onDelete: ((Moment) -> Void)? = nil
    var onArchive: ((Moment) -> Void)? = nil
    var onAdjustPreview: ((Moment) -> Void)? = nil
    var onPin: ((Moment, Bool, Bool) -> Void)? = nil

    /// Navegación zoom iOS 18 → detalle (NavigationStack).
    var openZoomDetail: ((ProfileMomentZoomDestination) -> Void)? = nil
    var clearZoomNavigation: (() -> Void)? = nil

    /// Lista activa para zoom (guardados, filtros, etc.).
    var zoomMomentsSnapshot: [Moment] = []

    private var thumbnailFrames: [String: CGRect] = [:]

    var activeMoment: Moment? {
        if let selection = menuSelection {
            return selection.moment
        }
        if let route = activeRoute {
            return route.moments[safe: route.initialIndex]
        }
        return nil
    }

    var isInteractive: Bool {
        switch phase {
        case .idle: return false
        default: return true
        }
    }

    var showsDetailLayer: Bool {
        switch phase {
        case .expanding, .detail, .retracting:
            return true
        default:
            return false
        }
    }

    var activeRoute: ProfileMomentDetailRoute? {
        switch phase {
        case .expanding(let route), .detail(let route), .retracting(let route):
            return route
        default:
            return nil
        }
    }

    /// Durante `expanding` el vídeo lo lleva el flying hero; en el crossfade pasa al detalle.
    var allowsDetailVideoPlayback: Bool {
        switch phase {
        case .detail, .retracting:
            return true
        case .expanding:
            return detailContentOpacity > 0.12
        default:
            return false
        }
    }

    /// Cápsula/avatar del hero: solo visible antes del crossfade al detalle.
    var showsFlyingHeroChrome: Bool {
        switch phase {
        case .expanding:
            return detailContentOpacity < 0.08
        default:
            return true
        }
    }

    /// Footer/info: entra tarde, cuando el media ya creció.
    var heroChromeRevealOpacity: CGFloat {
        switch phase {
        case .menuPeek:
            return ProfileGridHeroMotion.smoothstep(
                ProfileGridHeroMotion.remap(peekProgress, start: 0.50, end: 0.88)
            )
        case .expanding:
            return detailContentOpacity < 0.08 ? 1 : 0
        default:
            return 1
        }
    }

    var menuSelection: ProfileGridMomentMenuSelection? {
        if case .menuPeek(let selection) = phase { return selection }
        return nil
    }

    func ingestThumbnailFrames(_ frames: [String: CGRect]) {
        thumbnailFrames.merge(frames) { _, new in new }
    }

    private func momentFrameKey(_ moment: Moment, index: Int) -> String {
        ProfileGridHeroLayout.gridSourceKey(moment: moment, index: index)
    }

    func isLiftedGridSource(moment: Moment, gridIndex: Int) -> Bool {
        guard case .menuPeek(let selection) = phase else { return false }
        return momentFrameKey(moment, index: gridIndex) == momentFrameKey(selection.moment, index: selection.index)
    }

    /// Opacidad del contenido de la miniatura origen (0 = hueco vacío, 1 = visible).
    func liftedGridSourceContentOpacity(moment: Moment, gridIndex: Int) -> CGFloat {
        guard isLiftedGridSource(moment: moment, gridIndex: gridIndex) else { return 1 }
        return ProfileGridHeroLayout.liftedSourceThumbnailOpacity(peekProgress: peekProgress)
    }

    func menuBlockHeight(for moment: Moment) -> CGFloat {
        if showPinConfirm { return 220 }
        switch menuKind {
        case .visitor:
            return 52
        case .owner:
            let menuRowCount = moment.canAdjustGridPreview ? 5 : 4
            return CGFloat(46 * menuRowCount)
        }
    }

    func openMenu(moment: Moment, index: Int, kind: ProfileGridHeroMenuKind = .owner) {
        showPinConfirm = false
        toastMessage = nil
        menuKind = kind
        let key = momentFrameKey(moment, index: index)
        sourceFrame = thumbnailFrames[key] ?? .zero
        expandProgress = 0
        collapseProgress = 0
        detailContentOpacity = 0
        phase = .menuPeek(ProfileGridMomentMenuSelection(moment: moment, index: index))

        GlobalVideoManager.shared.pauseAllVideos()
        GlobalVideoManager.shared.clearProfilePlaybackHandoffState()

        withAnimation(ProfileGridHeroLayout.peekLiftAnimation) {
            peekProgress = 1
            scrimOpacity = 1
            menuOpacity = 1
        }
    }

    func dismissMenu() {
        guard case .menuPeek(let selection) = phase else { return }
        showPinConfirm = false

        pauseProfileHeroVideo(for: selection.moment)

        withAnimation(ProfileGridHeroLayout.peekDismissAnimation) {
            peekProgress = 0
            scrimOpacity = 0
            menuOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, case .menuPeek = self.phase else { return }
            self.phase = .idle
            GlobalVideoManager.shared.clearProfilePlaybackHandoffState()
        }
    }

    func openDirectDetail(
        moments: [Moment],
        initialIndex: Int,
        feedKind: ProfileMomentZoomFeedKind
    ) {
        guard let moment = moments[safe: initialIndex] else { return }

        zoomMomentsSnapshot = moments

        GlobalVideoManager.shared.pauseAllVideos()
        GlobalVideoManager.shared.clearProfilePlaybackHandoffState()

        if moment.hasVideoMedia {
            let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
            GlobalVideoManager.shared.resetPlaybackPosition(forMomentId: consumerId)
            GlobalVideoManager.shared.releasePreservedPlayer(consumerId: consumerId)
        }

        openZoomDetail?(ProfileMomentZoomDestination(
            zoomSourceID: momentFrameKey(moment, index: initialIndex),
            initialIndex: initialIndex,
            initialMomentId: moment.id,
            feedKind: feedKind,
            restrictPlaybackToInitialIndex: false
        ))
    }

    func expandToDetail(
        moments: [Moment],
        initialIndex: Int,
        feedKind: ProfileMomentZoomFeedKind,
        openCommentsOnAppear: Bool = false
    ) {
        guard case .menuPeek(let selection) = phase else { return }
        openZoomDetailFromMenu(
            moments: moments,
            selection: selection,
            feedKind: feedKind,
            openCommentsOnAppear: openCommentsOnAppear
        )
    }

    func openZoomDetailFromMenu(
        moments: [Moment],
        selection: ProfileGridMomentMenuSelection,
        feedKind: ProfileMomentZoomFeedKind,
        openCommentsOnAppear: Bool = false
    ) {
        guard case .menuPeek = phase else { return }

        let resolvedIndex = resolvedDetailIndex(for: selection, in: moments)
        let moment = moments[safe: resolvedIndex] ?? selection.moment
        let sourceID = momentFrameKey(selection.moment, index: selection.index)

        if moment.hasVideoMedia {
            let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
            GlobalVideoManager.shared.markProfileHeroHandoff(forMomentId: consumerId)
            FeedVisibilityCoordinator.shared.pinActiveVideo(momentId: consumerId)
        }

        HapticManager.shared.lightImpact()

        withAnimation(ProfileGridHeroLayout.peekDismissAnimation) {
            peekProgress = 0
            scrimOpacity = 0
            menuOpacity = 0
        }
        phase = .idle

        openZoomDetail?(ProfileMomentZoomDestination(
            zoomSourceID: sourceID,
            initialIndex: resolvedIndex,
            initialMomentId: moment.id,
            feedKind: feedKind,
            restrictPlaybackToInitialIndex: true,
            openCommentsOnAppear: openCommentsOnAppear
        ))
    }

    func dismissDetail() {
        clearZoomNavigation?()
        resetToIdle()
    }

    private func resolvedDetailIndex(
        for selection: ProfileGridMomentMenuSelection,
        in moments: [Moment]
    ) -> Int {
        if let momentId = selection.moment.id,
           let matchedIndex = moments.firstIndex(where: { $0.id == momentId }) {
            return matchedIndex
        }
        return min(max(selection.index, 0), max(moments.count - 1, 0))
    }

    private func resolvedSourceFrame(for selection: ProfileGridMomentMenuSelection) -> CGRect {
        let key = momentFrameKey(selection.moment, index: selection.index)
        let frame = thumbnailFrames[key]
        if let frame, frame.width > 1, frame.height > 1 {
            return frame
        }
        return sourceFrame.width > 1 ? sourceFrame : .zero
    }

    func resetToIdle() {
        phase = .idle
        peekProgress = 0
        expandProgress = 0
        collapseProgress = 0
        menuOpacity = 0
        detailContentOpacity = 0
        scrimOpacity = 0
        showPinConfirm = false
        isDismissingInteractively = false
        menuKind = .owner
        GlobalVideoManager.shared.clearProfilePlaybackHandoffState()
    }

    private func pauseProfileHeroVideo(for moment: Moment) {
        guard moment.hasVideoMedia else { return }
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        GlobalVideoManager.shared.pauseVideo(consumerId)
        GlobalVideoManager.shared.releasePreservedPlayer(consumerId: consumerId)
    }

    private func activateDetailVideoIfNeeded(moments: [Moment], initialIndex: Int) {
        guard let moment = moments[safe: initialIndex], moment.hasVideoMedia else { return }
        let consumerId = GlobalVideoManager.profileVideoConsumerId(for: moment)
        // Pin exclusivo → ningún otro video puede robar el slot activo.
        FeedVisibilityCoordinator.shared.pinActiveVideo(momentId: consumerId)
        GlobalVideoManager.shared.playVideo(consumerId)
    }

    var flyingHeroOpacity: CGFloat {
        switch phase {
        case .menuPeek:
            return 1
        case .expanding:
            return max(0, 1 - detailContentOpacity)
        case .retracting:
            let fadeStart = ProfileGridHeroLayout.retractFadeStart
            guard collapseProgress > fadeStart else { return 1 }
            let fadeT = ProfileGridHeroMotion.easeOut(
                (collapseProgress - fadeStart) / max(1 - fadeStart, 0.01)
            )
            return max(0, 1 - fadeT)
        case .detail, .idle:
            return 0
        }
    }

    var menuPresentationOffset: CGFloat {
        let reveal = ProfileGridHeroMotion.smoothstep(
            ProfileGridHeroMotion.remap(menuOpacity, start: 0.38, end: 1)
        )
        return (1 - reveal) * 12
    }

    var menuPresentationScale: CGFloat {
        let reveal = ProfileGridHeroMotion.smoothstep(
            ProfileGridHeroMotion.remap(menuOpacity, start: 0.38, end: 1)
        )
        return 0.97 + reveal * 0.03
    }

    var scrimPresentationOpacity: CGFloat {
        switch phase {
        case .menuPeek:
            return 0.30 * ProfileGridHeroMotion.smoothstep(
                ProfileGridHeroMotion.remap(peekProgress, start: 0.05, end: 0.70)
            )
        default:
            return 0.28 * ProfileGridHeroMotion.smoothstep(scrimOpacity)
        }
    }

    func menuRowRevealProgress(index: Int) -> CGFloat {
        let start = CGFloat(index) * 0.07
        let end = start + 0.52
        return ProfileGridHeroMotion.easeOut(
            ProfileGridHeroMotion.remap(menuOpacity, start: start, end: end)
        )
    }

    var detailBackdropOpacityForLayer: CGFloat {
        switch phase {
        case .retracting:
            return ProfileGridHeroMotion.easeOut(1 - collapseProgress)
        case .expanding:
            return expandProgress * 0.92
        default:
            return max(detailContentOpacity, expandProgress)
        }
    }

    func heroPresentation(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets,
        moment: Moment,
        availableHeight: CGFloat
    ) -> ProfileGridHeroPresentation {
        let peekFrame = ProfileGridHeroLayout.peekCardFrame(
            containerSize: containerSize,
            safeAreaInsets: safeAreaInsets,
            moment: moment,
            showPinConfirm: showPinConfirm,
            menuBlockHeight: menuBlockHeight(for: moment)
        )
        let detailFrame = ProfileGridHeroLayout.detailMediaFrame(
            screenSize: containerSize,
            safeAreaInsets: safeAreaInsets,
            moment: moment,
            availableHeight: availableHeight
        )

        let origin = sourceFrame.width > 1
            ? sourceFrame
            : ProfileGridHeroLayout.fallbackThumbnailFrame(in: containerSize)

        let frame: CGRect
        let cornerRadius: CGFloat
        let scale: CGFloat
        let shadowRadius: CGFloat
        let shadowOpacity: CGFloat

        switch phase {
        case .menuPeek:
            frame = ProfileGridHeroLayout.peekHeroFrame(
                origin: origin,
                destination: peekFrame,
                progress: peekProgress
            )
            cornerRadius = ProfileGridHeroLayout.peekHeroCornerRadius(progress: peekProgress)
            scale = 1
            let shadowT = ProfileGridHeroMotion.smoothstep(
                ProfileGridHeroMotion.remap(peekProgress, start: 0.18, end: 0.85)
            )
            shadowRadius = ProfileGridHeroLayout.lerp(6, 18, t: shadowT)
            shadowOpacity = ProfileGridHeroLayout.lerp(0.12, 0.24, t: shadowT)

        case .expanding, .detail:
            frame = ProfileGridHeroLayout.lerp(peekFrame, detailFrame, t: expandProgress)
            cornerRadius = ProfileGridHeroLayout.lerp(
                ProfileGridHeroLayout.peekCornerRadius,
                ProfileGridHeroLayout.detailCornerRadius,
                t: expandProgress
            )
            scale = 1
            shadowRadius = ProfileGridHeroLayout.lerp(18, 8, t: expandProgress)
            shadowOpacity = ProfileGridHeroLayout.lerp(0.24, 0.1, t: expandProgress)

        case .retracting:
            let split = ProfileGridHeroLayout.retractPeekSplit
            let t = min(max(collapseProgress, 0), 1)
            if t <= split {
                let local = t / max(split, 0.01)
                frame = ProfileGridHeroLayout.lerp(detailFrame, peekFrame, t: local, easing: ProfileGridHeroMotion.easeOut)
                cornerRadius = ProfileGridHeroLayout.lerp(
                    ProfileGridHeroLayout.detailCornerRadius,
                    ProfileGridHeroLayout.peekCornerRadius,
                    t: local,
                    easing: ProfileGridHeroMotion.easeOut
                )
                scale = 1
                shadowRadius = ProfileGridHeroLayout.lerp(8, 16, t: local)
                shadowOpacity = ProfileGridHeroLayout.lerp(0.1, 0.2, t: local)
            } else {
                let local = (t - split) / max(1 - split, 0.01)
                frame = ProfileGridHeroLayout.lerp(peekFrame, origin, t: local, easing: ProfileGridHeroMotion.easeOut)
                cornerRadius = ProfileGridHeroLayout.lerp(
                    ProfileGridHeroLayout.peekCornerRadius,
                    ProfileGridHeroLayout.thumbnailCornerRadius,
                    t: local,
                    easing: ProfileGridHeroMotion.easeOut
                )
                scale = 0.98 + (1 - local) * 0.02
                shadowRadius = ProfileGridHeroLayout.lerp(16, 4, t: local)
                shadowOpacity = ProfileGridHeroLayout.lerp(0.2, 0.08, t: local)
            }

        case .idle:
            frame = origin
            cornerRadius = ProfileGridHeroLayout.thumbnailCornerRadius
            scale = 1
            shadowRadius = 4
            shadowOpacity = 0.08
        }

        return ProfileGridHeroPresentation(
            frame: frame,
            cornerRadius: cornerRadius,
            scale: scale,
            opacity: flyingHeroOpacity,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity
        )
    }

    var shouldRenderFlyingHero: Bool {
        switch phase {
        case .menuPeek:
            return flyingHeroOpacity > 0.02
        default:
            return false
        }
    }
}

// MARK: - Flying hero shell

struct ProfileGridFlyingHeroShell<Content: View>: View {
    let presentation: ProfileGridHeroPresentation
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: presentation.frame.width, height: presentation.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous))
            .scaleEffect(presentation.scale, anchor: .center)
            .shadow(
                color: .black.opacity(presentation.shadowOpacity),
                radius: presentation.shadowRadius,
                x: 0,
                y: 8
            )
            .opacity(presentation.opacity)
            .position(x: presentation.frame.midX, y: presentation.frame.midY)
    }
}

// MARK: - Detail layer (ZStack presentation)

struct ProfileGridHeroDetailLayer: View {
    @ObservedObject var coordinator: ProfileGridHeroTransitionCoordinator
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    // Context menu properties
    var moments: [Moment] = []
    var zoomFeedKind: ProfileMomentZoomFeedKind = .ownMoments

    private var pinnedMomentsCount: Int {
        moments.filter { $0.isPinned == true }.count
    }

    private let pinnedMomentsLimit = 3

    @Environment(\.colorScheme) private var colorScheme

    private let menuWidth: CGFloat = 240
    private let horizontalMargin: CGFloat = 16

    @State private var showShareSheet = false
    @State private var shareMoment: Moment?
    @StateObject private var firestoreService = FirestoreService()

    private let privacyService = PrivacyService()

    var body: some View {
        ZStack {
            // 1. Scrim backdrop for menu peek
            if coordinator.isInteractive {
                Color.black
                    .opacity(coordinator.scrimPresentationOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.dismissMenu() }
                    .zIndex(0)
            }

            // 2. Flying hero (solo menú contextual / peek)
            if coordinator.shouldRenderFlyingHero, let moment = coordinator.activeMoment {
                let presentation = coordinator.heroPresentation(
                    containerSize: containerSize,
                    safeAreaInsets: safeAreaInsets,
                    moment: moment,
                    availableHeight: containerSize.height - 200
                )

                ProfileGridFlyingHeroShell(presentation: presentation) {
                    ProfileGridHeroCard(
                        moment: moment,
                        width: presentation.frame.width,
                        onOpenMoment: {
                            if case .menuPeek(let selection) = coordinator.phase {
                                coordinator.expandToDetail(
                                    moments: moments,
                                    initialIndex: selection.index,
                                    feedKind: zoomFeedKind
                                )
                            }
                        }
                    )
                }
                .allowsHitTesting(coordinator.menuSelection != nil)
                .zIndex(3)
            }

            // 3. Menu Stack for context menu actions
            if let selection = coordinator.menuSelection {
                menuStack(for: selection)
                    .opacity(coordinator.menuOpacity)
                    .offset(y: coordinator.menuPresentationOffset)
                    .scaleEffect(coordinator.menuPresentationScale, anchor: .top)
                    .zIndex(4)
            }

            // 4. Toast alerts
            if let toastMessage = coordinator.toastMessage {
                VStack {
                    Spacer()
                    profileToast(message: toastMessage)
                        .padding(.bottom, safeAreaInsets.bottom + 96)
                }
                .frame(width: containerSize.width, height: containerSize.height)
                .zIndex(5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(coordinator.isInteractive)
        .animation(ProfileGridHeroLayout.peekLiftAnimation, value: coordinator.menuSelection?.moment.id)
        .animation(ProfileGridHeroLayout.peekLiftAnimation, value: coordinator.showPinConfirm)
        .animation(ProfileGridHeroLayout.peekLiftAnimation, value: coordinator.menuOpacity)
        .animation(ProfileGridHeroLayout.peekLiftAnimation, value: coordinator.peekProgress)
        .animation(ProfileGridHeroLayout.peekLiftAnimation, value: coordinator.scrimOpacity)
        .environment(\.profileHeroShowsChrome, coordinator.showsFlyingHeroChrome)
        .environment(\.profileHeroChromeOpacity, coordinator.heroChromeRevealOpacity)
        .environment(\.profileHeroShowsAudience, coordinator.menuKind == .owner)
        .environmentObject(firestoreService)
        .onChange(of: coordinator.toastMessage) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if coordinator.toastMessage == newValue {
                    coordinator.toastMessage = nil
                }
            }
        }
        .overlay {
            if showShareSheet, let moment = shareMoment {
                ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(200)
            }
        }
    }

    private var detailBackdrop: some View {
        (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .ignoresSafeArea(.all)
    }

    @ViewBuilder
    private func menuStack(for selection: ProfileGridMomentMenuSelection) -> some View {
        let column = selection.index % 3
        let menuAlignment: HorizontalAlignment = column == 2 ? .leading : .trailing
        let cardWidth = ProfileGridHeroLayout.cardWidth(for: containerSize.width)
        let heroFrame = coordinator.heroPresentation(
            containerSize: containerSize,
            safeAreaInsets: safeAreaInsets,
            moment: selection.moment,
            availableHeight: containerSize.height - 200
        ).frame

        VStack(alignment: menuAlignment, spacing: ProfileGridHeroLayout.menuSpacing) {
            if coordinator.showPinConfirm {
                pinConfirmPanel
            } else if coordinator.menuKind == .visitor {
                visitorActionBar(for: selection)
            } else {
                actionsMenu(for: selection.moment)
            }
        }
        .frame(width: cardWidth)
        .position(
            x: containerSize.width / 2,
            y: heroFrame.maxY + ProfileGridHeroLayout.menuSpacing + coordinator.menuBlockHeight(for: selection.moment) / 2
        )
    }

    private func visitorActionBar(for selection: ProfileGridMomentMenuSelection) -> some View {
        ProfileGridVisitorActionBar(
            moment: selection.moment,
            canShare: privacyService.canShareMoment(selection.moment),
            onComment: {
                coordinator.expandToDetail(
                    moments: moments,
                    initialIndex: selection.index,
                    feedKind: zoomFeedKind,
                    openCommentsOnAppear: true
                )
            },
            onShare: {
                shareMoment = selection.moment
                showShareSheet = true
            }
        )
        .opacity(coordinator.menuRowRevealProgress(index: 0))
        .offset(y: (1 - coordinator.menuRowRevealProgress(index: 0)) * 10)
    }

    private struct MenuRowDefinition {
        let icon: String
        let title: String
        var isDestructive = false
        let action: () -> Void
    }

    private func menuRowDefinitions(for moment: Moment) -> [MenuRowDefinition] {
        var rows: [MenuRowDefinition] = [
            MenuRowDefinition(
                icon: moment.isPinned == true ? "pin.slash" : "pin",
                title: NSLocalizedString(
                    moment.isPinned == true ? "contextMenu.unpinMoment" : "contextMenu.pinMoment",
                    comment: "Pin or unpin moment"
                ),
                action: { handlePin(moment) }
            )
        ]

        if moment.canAdjustGridPreview {
            rows.append(
                MenuRowDefinition(
                    icon: "viewfinder",
                    title: NSLocalizedString("contextMenu.adjustPreview", comment: "Adjust grid preview"),
                    action: {
                        coordinator.dismissMenu()
                        coordinator.onAdjustPreview?(moment)
                    }
                )
            )
        }

        rows.append(contentsOf: [
            MenuRowDefinition(
                icon: "archivebox",
                title: NSLocalizedString("contextMenu.archiveMoment", comment: "Archive moment"),
                action: {
                    coordinator.dismissMenu()
                    coordinator.onArchive?(moment)
                }
            ),
            MenuRowDefinition(
                icon: "pencil",
                title: NSLocalizedString("contextMenu.editMoment", comment: "Edit moment"),
                action: {
                    coordinator.dismissMenu()
                    coordinator.onEdit?(moment)
                }
            ),
            MenuRowDefinition(
                icon: "trash",
                title: NSLocalizedString("contextMenu.deleteMoment", comment: "Delete moment"),
                isDestructive: true,
                action: {
                    coordinator.dismissMenu()
                    coordinator.onDelete?(moment)
                }
            )
        ])

        return rows
    }

    @ViewBuilder
    private func actionsMenu(for moment: Moment) -> some View {
        let rows = menuRowDefinitions(for: moment)

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                ProfileGridMenuRow(
                    icon: row.icon,
                    title: row.title,
                    isDestructive: row.isDestructive,
                    action: row.action
                )
                .opacity(coordinator.menuRowRevealProgress(index: index))
                .offset(y: (1 - coordinator.menuRowRevealProgress(index: index)) * 10)
            }
        }
        .frame(width: menuWidth)
        .fixedSize(horizontal: true, vertical: true)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pinConfirmPanel: some View {
        let panelWidth = min(containerSize.width - horizontalMargin * 2, 320)

        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(NSLocalizedString("contextMenu.pinLimit.confirm.title", comment: "Pinned limit confirm title"))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("contextMenu.pinLimit.confirm.message", comment: "Pinned limit confirm message"))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.68))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            menuDivider

            MomentRowButton(action: {
                guard let moment = coordinator.menuSelection?.moment else { return }
                coordinator.onPin?(moment, true, true)
                coordinator.toastMessage = NSLocalizedString("contextMenu.pinMoment.toast.pinned", comment: "Pinned toast")
                coordinator.dismissMenu()
            }) {
                Text(NSLocalizedString("contextMenu.pinLimit.confirm", comment: "Confirm pin replacement"))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(Color(hex: "007AFF"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }

            menuDivider

            MomentRowButton(action: {
                coordinator.showPinConfirm = false
            }) {
                Text(NSLocalizedString("contextMenu.pinLimit.cancel", comment: "Cancel pin replacement"))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: true, vertical: true)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func profileToast(message: String) -> some View {
        Text(message)
            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
    }

    private var menuDivider: some View {
        Divider()
            .opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private func handlePin(_ moment: Moment) {
        if moment.isPinned == true {
            coordinator.onPin?(moment, false, false)
            coordinator.toastMessage = NSLocalizedString("contextMenu.pinMoment.toast.unpinned", comment: "Unpinned toast")
            coordinator.dismissMenu()
            return
        }

        if pinnedMomentsCount >= pinnedMomentsLimit {
            coordinator.showPinConfirm = true
            return
        }

        coordinator.onPin?(moment, true, false)
        coordinator.toastMessage = NSLocalizedString("contextMenu.pinMoment.toast.pinned", comment: "Pinned toast")
        coordinator.dismissMenu()
    }
}

struct ProfileGridMenuRow: View {
    let icon: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20, alignment: .center)

                Text(title)
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))

                Spacer(minLength: 12)
            }
            .foregroundStyle(isDestructive ? .red : (colorScheme == .dark ? .white : .black))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsMenuRow)
    }
}
