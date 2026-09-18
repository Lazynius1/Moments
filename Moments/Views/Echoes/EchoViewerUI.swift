import SwiftUI
import Kingfisher
import FirebaseFirestore
import FirebaseAuth
import MapKit
import CoreLocation
import UIKit

/// Visor de Echo: un hecho, varios ángulos (posts). Mazo de capas + selector de perspectiva.
struct EchoViewerUI: View {
    let echoId: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: EchoViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var showLockoutAlert = false
    @State private var showIncompleteDecision = false
    @State private var selectedLocationPresentation: EchoLocationPresentation?
    @State private var deckSwipeAxis: DeckSwipeAxis?
    @State private var carouselIndex = 0

    private enum DeckSwipeAxis {
        case horizontal
        case vertical
    }

    private struct EchoLocationPresentation: Identifiable {
        let id: String
        let locationName: String
        let coordinate: CLLocationCoordinate2D
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    init(echoId: String, initialEcho: Echo? = nil) {
        self.echoId = echoId
        self._viewModel = StateObject(wrappedValue: EchoViewModel(echoId: echoId, initialEcho: initialEcho))
    }

    var body: some View {
        ZStack {
            adaptiveColors.surfaceBackground.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .tint(adaptiveColors.primary)
            } else if let echo = viewModel.echo {
                VStack(spacing: 0) {
                    sessionHeader(echo: echo)

                    if viewModel.canBrowseMedia, viewModel.currentPost != nil {
                        deckStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.isHistoricalIncomplete {
                        Spacer(minLength: 0)
                    } else {
                        waitingStateView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if viewModel.canBrowseMedia, !viewModel.groupedPerspectives.isEmpty {
                        perspectiveChooser
                    }
                }
            }

            if showLockoutAlert {
                glassAlertView
            }

            if showIncompleteDecision {
                incompleteDecisionOverlay
            }
        }
        .statusBarHidden(false)
        .environment(\.profileDetailDirectVideoPlayback, true)
        .onAppear {
            showIncompleteDecision = viewModel.isHistoricalIncomplete
            viewModel.loadEcho()
        }
        .onChange(of: viewModel.isHistoricalIncomplete) { _, isIncomplete in
            showIncompleteDecision = isIncomplete
        }
        .onChange(of: viewModel.currentPost?.momentId) { _, _ in
            carouselIndex = 0
        }
        .onChange(of: viewModel.currentPerspectiveIndex) { _, _ in
            carouselIndex = 0
        }
        .onChange(of: viewModel.currentPost.map { viewModel.visibleSlides(for: $0).count } ?? 0) { _, count in
            if carouselIndex >= count {
                carouselIndex = max(0, count - 1)
            }
        }
        .fullScreenCover(item: $selectedLocationPresentation) { presentation in
            LocationMapView(
                locationName: presentation.locationName,
                coordinate: presentation.coordinate,
                echoHistoryUserId: Auth.auth().currentUser?.uid,
                echoHistoryOnly: true,
                isPresented: Binding(
                    get: { selectedLocationPresentation != nil },
                    set: { if !$0 { selectedLocationPresentation = nil } }
                )
            )
        }
    }

    // MARK: - Session header (hecho, no story bars)

    private func sessionHeader(echo: Echo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                openInAppMap(for: echo)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(adaptiveColors.primary.opacity(0.88))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(echo.locationName ?? NSLocalizedString("echo.viewer.location.fallback", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(adaptiveColors.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(sessionSubtitle(echo: echo))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(adaptiveColors.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!viewModel.canOpenLocationMap)
            .opacity(viewModel.canOpenLocationMap ? 1 : 0.55)

            Spacer(minLength: 8)

            Menu {
                if let uid = Auth.auth().currentUser?.uid {
                    Button(role: .destructive) {
                        leaveEchoAction(userId: uid)
                    } label: {
                        Label(NSLocalizedString("echo.viewer.leave", comment: ""), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
                    .frame(width: 36, height: 36)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(adaptiveColors.primary)
                    .frame(width: 36, height: 36)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func sessionSubtitle(echo: Echo) -> String {
        let time = MomentsFormat.smartDate(from: echo.createdAt, context: .timeOnly)
        let count = viewModel.groupedPerspectives.count
        if count > 0 {
            return "\(time) · \(count)"
        }
        return time
    }

    // MARK: - Deck

    private var deckStage: some View {
        GeometryReader { proxy in
            let hasSidePeeks = viewModel.groupedPerspectives.count > 1
            let peekWidth: CGFloat = 18
            // Capas = otros autores (perspectivas), no carrusel ni posts del mismo autor.
            // Peek siempre a la derecha; en el último autor → izquierda (fin).
            let authorsBehind = viewModel.currentPerspectiveIndex
            let authorsAhead = max(
                0,
                viewModel.groupedPerspectives.count - viewModel.currentPerspectiveIndex - 1
            )
            let isLastAuthor = viewModel.groupedPerspectives.isEmpty
                || viewModel.currentPerspectiveIndex >= viewModel.groupedPerspectives.count - 1
            let peekLeading = isLastAuthor
            let stackCount = isLastAuthor ? authorsBehind : authorsAhead
            let visibleLayerCount = min(stackCount, 3)
            let deckLayerDepths = visibleLayerCount > 0
                ? Array((1...visibleLayerCount).reversed())
                : [Int]()
            // Shift 4/4 (derecha por defecto; izquierda solo al final).
            let sidePeekStep: CGFloat = 4
            let bottomPeekStep: CGFloat = 4
            let maxDeckDepth = CGFloat(deckLayerDepths.max() ?? 0)
            let deckSideOverflow = maxDeckDepth * sidePeekStep
            let deckBottomOverflow = maxDeckDepth * bottomPeekStep
            // Abrir mazo al swipe horizontal hacia el siguiente autor.
            let dragReveal = max(
                0,
                min(1, (peekLeading ? dragOffset.width : -dragOffset.width) / 72)
            )
            let cardWidth = proxy.size.width
                - (hasSidePeeks ? peekWidth * 2 : 20)
                - deckSideOverflow
            let post = viewModel.currentPost
            let caption = resolvedCaption(for: post)
            let hasCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let slides = post.map { viewModel.visibleSlides(for: $0) } ?? []
            let slideCount = slides.count
            let hasSlideDots = slideCount > 1
            let slideDotsOutside: CGFloat = hasSlideDots ? 18 : 0
            let captionOutside: CGFloat = (hasCaption ? 52 : 0) + slideDotsOutside
            let maxCardHeight = proxy.size.height - captionOutside - deckBottomOverflow - 6
            let mediaRatio = resolvedMediaAspectRatio(for: post)
            let mediaHeight = deckMediaHeight(
                cardWidth: cardWidth,
                mediaRatio: mediaRatio,
                maxCardHeight: maxCardHeight
            )
            let headerHeight: CGFloat = 48
            let cardHeight = headerHeight + mediaHeight
            let canGoPrev = viewModel.currentPerspectiveIndex > 0
            let canGoNext = viewModel.currentPerspectiveIndex < viewModel.groupedPerspectives.count - 1

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .center, spacing: 0) {
                        if hasSidePeeks {
                            perspectiveHandle(
                                leading: true,
                                width: peekWidth,
                                height: cardHeight * 0.5,
                                enabled: canGoPrev
                            ) {
                                HapticManager.shared.selection()
                                viewModel.switchPerspective(to: viewModel.currentPerspectiveIndex - 1)
                            }
                        } else {
                            Color.clear.frame(width: 10)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            // Capas más grandes que la frontal: perfil por el lado del peek + abajo.
                            ZStack(alignment: peekLeading ? .topTrailing : .topLeading) {
                                ForEach(deckLayerDepths, id: \.self) { depth in
                                    let d = CGFloat(depth)
                                    let grow = d * sidePeekStep + dragReveal * 1.5
                                    let growY = d * bottomPeekStep + dragReveal * 1.5
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(
                                            colorScheme == .dark
                                                ? Color(hex: "3A4550")
                                                : Color(hex: "C9C4BA")
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .stroke(adaptiveColors.primary.opacity(0.35), lineWidth: 1)
                                        )
                                        .frame(
                                            width: cardWidth + grow,
                                            height: cardHeight + growY
                                        )
                                        .zIndex(Double(visibleLayerCount - depth))
                                }

                                if let post {
                                    let isAvailable = viewModel.momentAvailability[post.momentId] ?? true
                                    let perspective = viewModel.groupedPerspectives.indices.contains(viewModel.currentPerspectiveIndex)
                                        ? viewModel.groupedPerspectives[viewModel.currentPerspectiveIndex]
                                        : nil
                                    deckFrontCard(
                                        post: post,
                                        perspective: perspective,
                                        isAvailable: isAvailable,
                                        width: cardWidth,
                                        headerHeight: headerHeight,
                                        mediaHeight: mediaHeight,
                                        mediaRatio: mediaRatio
                                    )
                                    .offset(x: dragOffset.width * 0.35, y: dragOffset.height * 0.35)
                                    .id("\(viewModel.currentPerspectiveIndex)-\(post.momentId)")
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                        removal: .opacity.combined(with: .offset(y: -28)).combined(with: .opacity)
                                    ))
                                    .zIndex(10)
                                }
                            }
                            .frame(
                                width: cardWidth + deckSideOverflow,
                                height: cardHeight + deckBottomOverflow,
                                alignment: peekLeading ? .topTrailing : .topLeading
                            )
                            .animation(.easeOut(duration: 0.22), value: viewModel.currentPerspectiveIndex)
                            .animation(.easeOut(duration: 0.22), value: visibleLayerCount)
                            .animation(.easeOut(duration: 0.22), value: peekLeading)
                            .gesture(deckDragGesture(allowsHorizontal: true))
                            .overlay(alignment: .trailing) {
                                layerDots
                                    .padding(.trailing, peekLeading ? 8 : 8 + deckSideOverflow)
                                    .padding(.bottom, deckBottomOverflow)
                            }

                            // Slides del post: puntos tipo IG debajo de la card.
                            if hasSlideDots {
                                MomentCarouselPageIndicators(
                                    count: slideCount,
                                    currentIndex: $carouselIndex,
                                    tone: .onCanvas
                                )
                                .frame(maxWidth: cardWidth)
                                .frame(width: cardWidth, alignment: .center)
                                .padding(.top, 8)
                                .padding(.leading, peekLeading ? deckSideOverflow : 0)
                                .animation(.easeInOut(duration: 0.18), value: carouselIndex)
                            }

                            if hasCaption, let post {
                                MomentCaptionView(
                                    moment: captionMoment(for: post, caption: caption),
                                    style: .echo,
                                    colorScheme: colorScheme,
                                    onHashtagTap: { _ in }
                                )
                                .frame(width: cardWidth, alignment: .leading)
                                .padding(.leading, peekLeading ? deckSideOverflow : 0)
                                .padding(.top, hasSlideDots ? 4 : 0)
                            }
                        }

                        if hasSidePeeks {
                            perspectiveHandle(
                                leading: false,
                                width: peekWidth,
                                height: cardHeight * 0.5,
                                enabled: canGoNext
                            ) {
                                HapticManager.shared.selection()
                                viewModel.switchPerspective(to: viewModel.currentPerspectiveIndex + 1)
                            }
                        } else {
                            Color.clear.frame(width: 10)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func advancePostMedia(for post: EchoDeckPost, direction: Int) {
        let slides = viewModel.visibleSlides(for: post)
        guard slides.count > 1 else { return }
        let count = slides.count
        let next = (carouselIndex + direction + count) % count
        guard next != carouselIndex else { return }
        HapticManager.shared.selection()
        withAnimation(.easeInOut(duration: 0.2)) {
            carouselIndex = next
        }
    }

    /// Debug: fuerza un caption largo para validar truncado / ver más / traducción.
    private let debugForceEchoCaption = true
    private let debugEchoCaptionText =
        "Debug Echo: un momento compartido desde este ángulo con bastante texto para probar el truncado a una línea, el ver más del feed y la fila de traducción debajo."

    private func resolvedCaption(for post: EchoDeckPost?) -> String {
        guard let post else {
            return debugForceEchoCaption ? debugEchoCaptionText : ""
        }
        let cached = viewModel.postCaptions[post.momentId]
            ?? viewModel.postMoments[post.momentId]?.content
            ?? ""
        let trimmed = cached.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, debugForceEchoCaption {
            return debugEchoCaptionText
        }
        return cached
    }

    private func captionMoment(for post: EchoDeckPost, caption: String) -> Moment {
        let base = viewModel.playbackMoment(for: post)
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != base.content.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return base
        }
        return Moment(
            id: base.id ?? post.momentId,
            authorId: base.authorId,
            username: base.username,
            content: caption,
            imagePath: base.imagePath,
            videoUrl: base.videoUrl,
            timestamp: base.timestamp,
            reactions: base.reactions,
            commentCount: base.commentCount,
            profileImagePath: base.profileImagePath,
            taggedUsers: base.taggedUsers,
            mentionedUsers: base.mentionedUsers,
            location: base.location,
            locationCoordinate: base.locationCoordinate,
            audience: base.audience,
            mediaItems: base.mediaItems,
            aspectRatio: base.aspectRatio,
            customListId: base.customListId,
            thumbnailUrl: base.thumbnailUrl,
            videoDuration: base.videoDuration,
            videoFileSize: base.videoFileSize,
            videoResolution: base.videoResolution,
            disableComments: base.disableComments,
            hideLikeCounts: base.hideLikeCounts,
            allowSharing: base.allowSharing,
            scheduledDate: base.scheduledDate,
            isArchived: base.isArchived,
            archivedAt: base.archivedAt,
            isPinned: base.isPinned,
            pinnedAt: base.pinnedAt,
            gridPreviewScale: base.gridPreviewScale,
            gridPreviewOffsetX: base.gridPreviewOffsetX,
            gridPreviewOffsetY: base.gridPreviewOffsetY,
            gridPreviewFitMode: base.gridPreviewFitMode,
            gridPreviewBackground: base.gridPreviewBackground,
            hasHiddenLayers: base.hasHiddenLayers,
            hiddenLayerCount: base.hiddenLayerCount,
            isModerationHidden: base.isModerationHidden,
            originalAudience: base.originalAudience,
            reviewRequired: base.reviewRequired,
            canRestore: base.canRestore
        )
    }

    private func resolvedMediaAspectRatio(for post: EchoDeckPost?) -> CGFloat {
        guard let post else { return 1 }
        let raw = viewModel.postAspectRatios[post.momentId] ?? post.aspectRatio
        return parseAspectRatio(raw)
    }

    /// Ratio width/height exacto cuando viene como "W:H"; sin forzar 4:5 del feed.
    private func parseAspectRatio(_ raw: String?) -> CGFloat {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 1 }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.split(separator: ":")
        if parts.count == 2,
           let width = Double(parts[0]),
           let height = Double(parts[1]),
           height > 0 {
            let ratio = CGFloat(width / height)
            if ratio.isFinite, ratio > 0 { return ratio }
        }
        let canonical = ProcessedMedia.AspectRatio(from: normalized).value
        return (canonical > 0 && canonical.isFinite) ? canonical : 1
    }

    /// Media a ratio nativo; tope suave para no comerse el stage, sin encoger de más.
    private func deckMediaHeight(
        cardWidth: CGFloat,
        mediaRatio: CGFloat,
        maxCardHeight: CGFloat
    ) -> CGFloat {
        let headerReserve: CGFloat = 48
        let available = max(200, maxCardHeight - headerReserve)
        let ideal = cardWidth / max(mediaRatio, 0.01)
        let softCap = cardWidth * 1.45
        return min(max(ideal, 200), available, softCap)
    }

    private func perspectiveHandle(
        leading: Bool,
        width: CGFloat,
        height: CGFloat,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: leading ? 0 : 14,
            bottomLeadingRadius: leading ? 0 : 14,
            bottomTrailingRadius: leading ? 14 : 0,
            topTrailingRadius: leading ? 14 : 0,
            style: .continuous
        )
        return Button(action: action) {
            shape
                .fill(adaptiveColors.primary.opacity(colorScheme == .dark ? 0.16 : 0.22))
                .overlay(
                    shape.stroke(
                        adaptiveColors.primary.opacity(colorScheme == .dark ? 0.14 : 0.32),
                        lineWidth: 1
                    )
                )
                .frame(width: width, height: height)
                .contentShape(shape)
        }
        .buttonStyle(EchoHandleButtonStyle(enabled: enabled))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(
            leading
                ? NSLocalizedString("echo.viewer.perspective.previous", comment: "")
                : NSLocalizedString("echo.viewer.perspective.next", comment: "")
        )
    }

    private func deckFrontCard(
        post: EchoDeckPost,
        perspective: GroupedPerspective?,
        isAvailable: Bool,
        width: CGFloat,
        headerHeight: CGFloat,
        mediaHeight: CGFloat,
        mediaRatio: CGFloat
    ) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            // Chrome de card: solo la franja superior.
            HStack(spacing: 10) {
                if let perspective {
                    AsyncProfileImageView(userId: perspective.authorId)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(adaptiveColors.primary.opacity(0.16), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(perspective.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(adaptiveColors.primary)
                            .lineLimit(1)
                        Text(relativeTimeText(from: post.timestamp))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(adaptiveColors.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: headerHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(adaptiveColors.surfaceBackground)

            // Contenido edge-to-edge (sin padding).
            ZStack {
                let slides = viewModel.visibleSlides(for: post)
                if isAvailable, !slides.isEmpty {
                    EchoDeckCarousel(
                        slides: slides,
                        currentIndex: $carouselIndex,
                        isAvailable: true,
                        moment: viewModel.playbackMoment(for: post),
                        mediaRatio: mediaRatio,
                        adaptiveColors: adaptiveColors,
                        onMediaTap: { direction in
                            advancePostMedia(for: post, direction: direction)
                        }
                    )
                } else {
                    unavailablePlaceholder
                }
            }
            .frame(width: width, height: mediaHeight)
            .clipped()
        }
        .frame(width: width)
        .background(adaptiveColors.surfaceBackground)
        .clipShape(cardShape)
        .overlay(cardShape.stroke(adaptiveColors.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.1), radius: 8, x: 0, y: 3)
    }

    private var layerDots: some View {
        Group {
            if viewModel.currentPerspectiveIndex < viewModel.groupedPerspectives.count {
                let posts = viewModel.groupedPerspectives[viewModel.currentPerspectiveIndex].posts
                if posts.count > 1 {
                    VStack(spacing: 6) {
                        ForEach(0..<posts.count, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index == viewModel.currentVerticalIndex
                                        ? adaptiveColors.primary.opacity(0.9)
                                        : adaptiveColors.primary.opacity(0.22)
                                )
                                .frame(
                                    width: index == viewModel.currentVerticalIndex ? 4 : 3,
                                    height: index == viewModel.currentVerticalIndex ? 18 : 9
                                )
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: viewModel.currentVerticalIndex)
                }
            }
        }
    }

    private func deckDragGesture(allowsHorizontal: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard viewModel.canBrowseMedia else { return }
                if deckSwipeAxis == nil {
                    if allowsHorizontal, abs(value.translation.width) > abs(value.translation.height) {
                        deckSwipeAxis = .horizontal
                    } else if abs(value.translation.height) > abs(value.translation.width) {
                        deckSwipeAxis = .vertical
                    }
                }
                switch deckSwipeAxis {
                case .horizontal where allowsHorizontal:
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                case .vertical:
                    dragOffset = CGSize(width: 0, height: value.translation.height)
                default:
                    dragOffset = .zero
                }
            }
            .onEnded { value in
                defer {
                    dragOffset = .zero
                    deckSwipeAxis = nil
                }
                guard viewModel.canBrowseMedia else { return }
                let threshold: CGFloat = 56
                switch deckSwipeAxis {
                case .horizontal where allowsHorizontal:
                    if value.translation.width < -threshold {
                        HapticManager.shared.selection()
                        viewModel.switchPerspective(to: viewModel.currentPerspectiveIndex + 1)
                    } else if value.translation.width > threshold {
                        HapticManager.shared.selection()
                        viewModel.switchPerspective(to: viewModel.currentPerspectiveIndex - 1)
                    }
                case .vertical:
                    if value.translation.height < -threshold {
                        HapticManager.shared.selection()
                        viewModel.switchVerticalIndex(to: viewModel.currentVerticalIndex + 1)
                    } else if value.translation.height > threshold {
                        HapticManager.shared.selection()
                        viewModel.switchVerticalIndex(to: viewModel.currentVerticalIndex - 1)
                    }
                default:
                    break
                }
            }
    }

    // MARK: - Perspective chooser (ángulo)

    private var perspectiveChooser: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(viewModel.groupedPerspectives.enumerated()), id: \.element.id) { index, perspective in
                    Button {
                        guard index != viewModel.currentPerspectiveIndex else { return }
                        HapticManager.shared.selection()
                        viewModel.switchPerspective(to: index)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottomTrailing) {
                                AsyncProfileImageView(userId: perspective.authorId)
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                viewModel.currentPerspectiveIndex == index
                                                    ? adaptiveColors.accent
                                                    : adaptiveColors.primary.opacity(0.18),
                                                lineWidth: viewModel.currentPerspectiveIndex == index ? 2.5 : 1
                                            )
                                    )
                                    .scaleEffect(viewModel.currentPerspectiveIndex == index ? 1.04 : 1)
                                    .animation(.easeOut(duration: 0.18), value: viewModel.currentPerspectiveIndex)

                                if perspective.posts.count > 1 {
                                    Text("\(perspective.posts.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(adaptiveColors.primary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(adaptiveColors.surfaceBackground)
                                                .overlay(Capsule().stroke(adaptiveColors.primary.opacity(0.16), lineWidth: 1))
                                        )
                                        .offset(x: 4, y: 2)
                                }
                            }

                            Text(perspective.username)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(
                                    viewModel.currentPerspectiveIndex == index
                                        ? adaptiveColors.primary
                                        : adaptiveColors.secondary
                                )
                                .lineLimit(1)
                                .frame(maxWidth: 72)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollClipDisabled()
        .padding(.top, 2)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(adaptiveColors.surfaceBackground)
    }

    // MARK: - States / overlays (preserved)

    private var unavailablePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(adaptiveColors.secondary)
            Text(NSLocalizedString("echo.viewer.unavailable", comment: ""))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(adaptiveColors.surfaceBackground)
    }

    private var waitingStateView: some View {
        VStack(spacing: 24) {
            EchoesIconView(
                size: EchoesIconMetrics.viewerLoading,
                gradient: EchoesIconView.echoesBrandGradient
            )
            .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
            .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: viewModel.isLoading)

            VStack(spacing: 8) {
                Text(NSLocalizedString("echo.viewer.waiting.title", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(adaptiveColors.primary)

                Text(NSLocalizedString("echo.viewer.waiting.subtitle", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(adaptiveColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: -10) {
                ForEach(viewModel.echo?.participants ?? []) { participant in
                    AsyncProfileImageView(userId: participant.userId)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                participant.status == .accepted ? Color.orange : adaptiveColors.primary.opacity(0.2),
                                lineWidth: 2
                            )
                        )
                        .opacity(participant.status == .accepted ? 1.0 : 0.4)
                }
            }
            .padding(.top, 10)
        }
    }

    private var incompleteDecisionOverlay: some View {
        let primaryTextColor = colorScheme == .dark ? Color.white : Color.black
        let secondaryTextColor = primaryTextColor.opacity(0.72)
        let dividerColor = primaryTextColor.opacity(0.12)

        return ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(NSLocalizedString("echo.viewer.incomplete.title", comment: ""))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(primaryTextColor)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("echo.viewer.incomplete.body", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 0.5)

                Button {
                    if let uid = Auth.auth().currentUser?.uid {
                        leaveEchoAction(userId: uid)
                    }
                } label: {
                    Text(NSLocalizedString("echo.viewer.incomplete.delete", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 0.5)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showIncompleteDecision = false
                    }
                } label: {
                    Text(NSLocalizedString("echo.viewer.incomplete.keep", comment: ""))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(primaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .frame(maxWidth: 320)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
            .zIndex(5000)
        }
    }

    private func relativeTimeText(from date: Date?) -> String {
        guard let date else { return "" }
        return MomentsFormat.relativeTime(from: date)
    }

    private func leaveEchoAction(userId: String) {
        guard let echoId = viewModel.echo?.id else {
            dismiss()
            return
        }

        EchoService.shared.leaveEcho(echoId: echoId, userId: userId) { error in
            if let error = error {
                if (error as NSError).code == 403 {
                    DispatchQueue.main.async {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            showLockoutAlert = true
                        }
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                dismiss()
            }
        }
    }

    private var glassAlertView: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showLockoutAlert = false }
                }

            VStack(spacing: 18) {
                Text(NSLocalizedString("echo.leave.locked", comment: ""))
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                Button {
                    withAnimation { showLockoutAlert = false }
                } label: {
                    Text(NSLocalizedString("echo.viewer.ok", comment: ""))
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.black.opacity(0.22)))
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                }
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.24))
                    .overlay {
                        Color.clear
                            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
            )
            .padding(.horizontal, 40)
            .transition(MotionPolicy.Transition.enterPop)
        }
    }

    private func openInAppMap(for echo: Echo) {
        guard viewModel.canOpenLocationMap else { return }
        HapticManager.shared.lightImpact()
        let resolvedLocationName = (echo.locationName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        selectedLocationPresentation = EchoLocationPresentation(
            id: echo.id ?? UUID().uuidString,
            locationName: resolvedLocationName.isEmpty
                ? NSLocalizedString("echo.viewer.location.fallback", comment: "")
                : resolvedLocationName,
            coordinate: CLLocationCoordinate2D(
                latitude: echo.location.latitude,
                longitude: echo.location.longitude
            )
        )
    }
}

// MARK: - Carrusel dentro de la postal del mazo

private struct EchoDeckCarousel: View {
    let slides: [EchoMomentRef]
    @Binding var currentIndex: Int
    let isAvailable: Bool
    let moment: Moment
    let mediaRatio: CGFloat
    let adaptiveColors: AdaptiveColors
    /// -1 = anterior, +1 = siguiente
    var onMediaTap: ((Int) -> Void)? = nil

    @State private var scrollPosition: Int?
    @State private var isImmersive = false

    /// Esquina inferior-izquierda reservada al mute.
    private let muteSafeWidth: CGFloat = 72
    private let muteSafeHeight: CGFloat = 64

    private var isCarousel: Bool { slides.count > 1 }

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let pageHeight = geometry.size.height
            let canvasRatio = pageWidth / max(pageHeight, 1)

            Group {
                if isCarousel {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                                slideView(
                                    slide,
                                    width: pageWidth,
                                    height: pageHeight,
                                    canvasRatio: canvasRatio,
                                    allowsVideo: isAvailable && index == currentIndex
                                )
                                .frame(width: pageWidth, height: pageHeight)
                                .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrollPosition)
                    .onAppear { scrollPosition = currentIndex }
                    .onChange(of: currentIndex) { _, newValue in
                        guard scrollPosition != newValue else { return }
                        scrollPosition = newValue
                    }
                    .onChange(of: scrollPosition) { _, newValue in
                        guard let newValue, newValue != currentIndex else { return }
                        currentIndex = newValue
                    }
                } else if let slide = slides.first {
                    slideView(
                        slide,
                        width: pageWidth,
                        height: pageHeight,
                        canvasRatio: canvasRatio,
                        allowsVideo: isAvailable
                    )
                    .frame(width: pageWidth, height: pageHeight)
                }
            }
            .frame(width: pageWidth, height: pageHeight)
            .background(adaptiveColors.primary.opacity(0.06))
        }
    }

    @ViewBuilder
    private func slideView(
        _ slide: EchoMomentRef,
        width: CGFloat,
        height: CGFloat,
        canvasRatio: CGFloat,
        allowsVideo: Bool
    ) -> some View {
        let slideRatio = parseSlideRatio(slide.aspectRatio) ?? mediaRatio
        let mode = MomentCarouselLayoutRules.presentationMode(
            for: slideRatio,
            canvasAspectRatio: canvasRatio
        )
        let isFit = mode == .fitWithBlur
        let mediaItem = mediaItem(for: slide)

        ZStack {
            if slide.mediaType == "video" {
                CroppedVideoPlayer(
                    item: mediaItem,
                    aspectRatio: slideRatio,
                    prefersUnifiedCarouselFrame: true,
                    currentMoment: moment,
                    allowsVideoPlayback: allowsVideo,
                    onTap: {},
                    isImmersive: $isImmersive
                )
                .frame(width: width, height: height)
                .clipped()
            } else {
                if isFit {
                    KFImage(URL(string: slide.thumbnailUrl ?? slide.mediaUrl))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .blur(radius: 18)
                        .opacity(0.55)
                }

                KFImage(URL(string: slide.thumbnailUrl ?? slide.mediaUrl))
                    .resizable()
                    .aspectRatio(contentMode: mode.swiftUIContentMode)
                    .frame(width: width, height: height)
                    .clipped()
            }

            if isCarousel, onMediaTap != nil {
                carouselTapZones(width: width, height: height)
            }
        }
    }

    /// Izquierda = anterior (salvo mute), derecha = siguiente.
    private func carouselTapZones(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onMediaTap?(-1) }

                Color.clear
                    .frame(width: muteSafeWidth, height: muteSafeHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onMediaTap?(1) }
        }
        .frame(width: width, height: height)
    }

    private func mediaItem(for slide: EchoMomentRef) -> MediaItem {
        if let match = moment.mediaItems?.first(where: { $0.url == slide.mediaUrl }) {
            return match
        }
        return MediaItem(
            type: slide.mediaType == "video" ? .video : .image,
            url: slide.mediaUrl,
            aspectRatio: slide.aspectRatio ?? moment.aspectRatio,
            thumbnailUrl: slide.thumbnailUrl
        )
    }

    private func parseSlideRatio(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ":")
        if parts.count == 2,
           let width = Double(parts[0]),
           let height = Double(parts[1]),
           height > 0 {
            let ratio = CGFloat(width / height)
            if ratio.isFinite, ratio > 0 { return ratio }
        }
        return nil
    }
}

private struct EchoHandleButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enabled ? 0.92 : 1)
            .opacity(configuration.isPressed && enabled ? 0.75 : 1)
            .brightness(configuration.isPressed && enabled ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
