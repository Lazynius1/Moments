import SwiftUI
import FirebaseAuth
import Kingfisher
import AVKit
import AVFoundation
import MapKit

// MARK: - ✅ COMPONENTES MODERNOS

// ✅ Botón de stories moderno
struct ModernStoryButton: View {
    let colorScheme: ColorScheme
    let action: () -> Void
    @StateObject private var uploadProgressManager = StoryUploadProgressManager.shared

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Fondo más sutil - casi transparente como estilo nativo
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ?
                          Color(hex: "FAF9F6").opacity(0.05) :
                          Color(hex: "0B1215").opacity(0.03))
                    .frame(width: 36, height: 36)

                Image(systemName: uploadProgressManager.isUploading ? "arrow.up" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ?
                                   Color.white.opacity(0.9) :
                                   Color.black.opacity(0.8))

                if uploadProgressManager.isUploading {
                    // Progreso más discreto
                    Circle()
                        .stroke(adaptiveColors.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 32, height: 32)

                    Circle()
                        .trim(from: 0, to: uploadProgressManager.progress)
                        .stroke(adaptiveColors.accent, lineWidth: 2)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: uploadProgressManager.progress)
                }
            }
        }
        .scaleEffect(uploadProgressManager.isUploading ? 0.95 : 1.0)
        .animation(
            MotionPolicy.animation(MotionPolicy.Spring.press, value: uploadProgressManager.isUploading),
            value: uploadProgressManager.isUploading
        )
    }
}

// ✅ Botón de notificaciones integrado
struct ModernNotificationButton: View {
    let hasNotification: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Fondo rojo sutil cuando hay notificaciones
                if hasNotification {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.08))
                        .frame(width: 36, height: 36)
                }

                // ✅ CAMBIAR: Corazón rojo cuando hay notificaciones
                Image(systemName: hasNotification ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(hasNotification ?
                        .red :  // ✅ ROJO cuando hay notificaciones
                                     (colorScheme == .dark ?
                                      Color.white.opacity(0.9) :
                                        Color.black.opacity(0.8)))
            }
        }
        .buttonStyle(.momentsPressIcon)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.row, value: hasNotification), value: hasNotification)
    }
}

// ✅ Botón de mensajes integrado
struct ModernMessageButton: View {
    let hasMessage: Bool
    let messageCount: Int // ✅ AGREGAR esta línea
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "paperplane")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ?
                                   Color.white.opacity(0.9) :
                                   Color.black.opacity(0.8))

                // ✅ CAMBIAR: Badge con número en lugar de punto
                if hasMessage && messageCount > 0 {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: messageCount > 9 ? 20 : 16, height: 16)

                        Text("\(min(messageCount, 99))")
                            .font(.system(size: messageCount > 9 ? 10 : 11, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .offset(x: 10, y: -10)
                    .scaleEffect(hasMessage ? 1.0 : 0.1)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.row, value: hasMessage), value: hasMessage)
                }
            }
        }
        .buttonStyle(.momentsPressIcon)
    }
}

// ✅ Loading moderno tipo "respiración" para más posts
struct ModernLoadingMoreView: View {
    let colorScheme: ColorScheme
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.6

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Círculo que "respira" con gradiente de Moments
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
                .scaleEffect(scale)
                .opacity(opacity)
                .animation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                    value: scale
                )

            Text("feed.loadingMore")
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(adaptiveColors.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: adaptiveColors.shadowColor.opacity(0.3), radius: 6, x: 0, y: 3)
        .onAppear {
            guard !MotionPolicy.reduceMotion else {
                scale = 1.0
                opacity = 1.0
                return
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scale = 1.2
                opacity = 1.0
            }
        }
    }
}

// ✅ Estado vacío moderno


// ✅ ACTUALIZADO: ModernPostCardView con círculo de historia en el header
struct ModernPostCardView: View {
    let moment: Moment
    let availableHeight: CGFloat
    let colorScheme: ColorScheme
    let onComment: () -> Void
    let onNearEnd: () -> Void
    let onHashtagTap: (String) -> Void
    let onLocationTap: (String, CLLocationCoordinate2D?) -> Void
    let onContextMenu: (Moment) -> Void
    var onTagTap: ((String) -> Void)? = nil // ✅ Tag Navigation Callback
    var onOpenUserProfile: ((String) -> Void)? = nil
    var onAuthorAvatarTap: ((String, Bool) -> Void)? = nil
    var onAuthorAvatarLongPress: ((String, CGRect) -> Void)? = nil
    var profileZoomNamespace: Namespace.ID? = nil
    var onPeek: ((String, CGFloat, Bool) -> Void)? = nil // ✅ PEEK: (imageURL, realRatio, isPressing)
    /// Sesión Reels de esta superficie (feed / perfil / explore…). Evita mezclar con `VideoMomentsIndex.shared`.
    var reelsVideos: [VideoMoment]? = nil
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(FeedViewModel.self) private var feedViewModel
    @State private var currentImageIndex = 0
    @State private var detectedAspectRatio: CGFloat
    @State private var followButtonState: FollowButtonState = .canFollow
    @State private var isSaved: Bool = false
    @State private var isFollowLoading: Bool = false
    @State private var showingUnfollowConfirmation = false
    @State private var isSaveLoading: Bool = false
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    @State private var showTags: Bool = false // ✅ NUEVO: Estado global para etiquetas en el post
    @State private var isImmersive: Bool = false // ✅ NUEVO: Modo inmersivo
    @State private var realAspectRatio: CGFloat = 1.0 // ✅ Ratio real sin cap (para long press reveal)
    @State private var isAuthorAvatarPressing = false
    @State private var authorAvatarAnchorCapture = FeedStoryCircleAnchorCapture()

    // ✅ ACTUALIZADO: AspectRatioType mejorado con soporte para reels
    @State private var aspectRatioType: AspectRatioType = .square
    @State private var resolvedCardHeight: CGFloat = 300
    @State private var isFirstAppear = true

    private var cardHeight: CGFloat {
        max(resolvedCardHeight, 200)
    }

    init(moment: Moment,
         availableHeight: CGFloat,
         colorScheme: ColorScheme,
         onComment: @escaping () -> Void,
         onNearEnd: @escaping () -> Void,
         onHashtagTap: @escaping (String) -> Void,
         onLocationTap: @escaping (String, CLLocationCoordinate2D?) -> Void,
         onContextMenu: @escaping (Moment) -> Void,
         onTagTap: ((String) -> Void)? = nil,
         onOpenUserProfile: ((String) -> Void)? = nil,
         onAuthorAvatarTap: ((String, Bool) -> Void)? = nil,
         onAuthorAvatarLongPress: ((String, CGRect) -> Void)? = nil,
         profileZoomNamespace: Namespace.ID? = nil,
         onPeek: ((String, CGFloat, Bool) -> Void)? = nil,
         reelsVideos: [VideoMoment]? = nil) {

        self.moment = moment
        self.availableHeight = availableHeight
        self.colorScheme = colorScheme
        self.onComment = onComment
        self.onNearEnd = onNearEnd
        self.onHashtagTap = onHashtagTap
        self.onLocationTap = onLocationTap
        self.onContextMenu = onContextMenu
        self.onTagTap = onTagTap
        self.onOpenUserProfile = onOpenUserProfile
        self.onAuthorAvatarTap = onAuthorAvatarTap
        self.onAuthorAvatarLongPress = onAuthorAvatarLongPress
        self.profileZoomNamespace = profileZoomNamespace
        self.onPeek = onPeek
        self.reelsVideos = reelsVideos
        _commentCount = State(initialValue: moment.commentCount)

        // ✅ CRÍTICO: Inicialización estática con metadatos SIEMPRE
        // Evitamos que el layout "baile" al cargar confiando en la DB
        if let ratioStr = moment.aspectRatio, !ratioStr.isEmpty {
            let ratio = ProcessedMedia.AspectRatio(from: ratioStr).value
            let safeRatio = (ratio > 0 && ratio.isFinite) ? ratio : 1.0

            // ✅ Guardar el ratio REAL para el long press reveal
            _realAspectRatio = State(initialValue: safeRatio)

            // Todo contenido más vertical que 4:5 se cropea en el feed.
            // Vídeos se ven completos al hacer tap (Reels viewer).
            let displayRatio: CGFloat
            if safeRatio < 0.8 {
                displayRatio = 0.8
            } else {
                displayRatio = safeRatio
            }

            _detectedAspectRatio = State(initialValue: displayRatio)

            if displayRatio < 0.7 { _aspectRatioType = State(initialValue: .reels) }
            else if displayRatio < 0.9 { _aspectRatioType = State(initialValue: .portrait) }
            else if displayRatio < 1.3 { _aspectRatioType = State(initialValue: .square) }
            else { _aspectRatioType = State(initialValue: .landscape) }
        } else {
            _detectedAspectRatio = State(initialValue: 1.0)
            _realAspectRatio = State(initialValue: 1.0)
            _aspectRatioType = State(initialValue: .square)
        }
    }

    @State private var liveAuthorUsername: String = ""
    @State private var showSpecificUserStories = false
    private let privacyService = PrivacyService()

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var displayAuthorUsername: String {
        let fallback = moment.username
        let live = liveAuthorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    // ✅ MEJORADO: AspectRatioType con soporte completo para todos los formatos
    enum AspectRatioType {
        case square, portrait, landscape, reels

        var maxHeight: CGFloat {
            switch self {
            case .square: return 400      // Para 1:1 (1080x1080)
            case .portrait: return 500    // Para 4:5 (1080x1350)
            case .landscape: return 300   // Para 16:9 - más compacto
            case .reels: return 600       // ✅ AJUSTADO: Para 9:16 (reels) - altura más razonable para el feed
            }
        }

        // ✅ NUEVO: Aspect ratios exactos basados en las dimensiones reales
        var exactRatio: CGFloat {
            switch self {
            case .square: return 1.0      // 1080÷1080 = 1.0
            case .portrait: return 0.8    // 1080÷1350 = 0.8
            case .landscape: return 1.78  // 16÷9 = 1.778
            case .reels: return 0.5625    // 9÷16 = 0.5625 (formato vertical de reels)
            }
        }

        var displayName: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .landscape: return "16:9"
            case .reels: return "9:16"
            }
        }
    }

    private var mediaItems: [MediaItem] {
        // ✅ MODERACIÓN: Usar visibleMediaItems para excluir archivos moderados del carrusel
        let visible = moment.visibleMediaItems
        if !visible.isEmpty {
            return visible
        }

        guard moment.shouldUseLegacyMediaFallback else {
            return [MediaItem(type: .image, url: "")]
        }

        // ✅ FALLBACK: Para momentos legacy que solo tienen imagePath/videoUrl
        var items: [MediaItem] = []
        if let imagePath = moment.imagePath, !imagePath.isEmpty {
            items.append(MediaItem(type: .image, url: imagePath))
        }
        if let videoUrl = moment.videoUrl, !videoUrl.isEmpty {
            items.append(MediaItem(type: .video, url: videoUrl))
        }
        return items.isEmpty ? [MediaItem(type: .image, url: "")] : items
    }

    private func refreshCardHeight() {
        let containerSize = CGSize(
            width: FeedMomentCardLayout.mediaContentWidth,
            height: availableHeight
        )
        resolvedCardHeight = calculateCardHeight(for: containerSize)
    }

    private func calculateCardHeight(for containerSize: CGSize) -> CGFloat {
        let maxWidth = containerSize.width
        guard maxWidth > 0 else { return 300 }

        let ratio = (detectedAspectRatio > 0 && detectedAspectRatio.isFinite) ? detectedAspectRatio : 1.0
        let idealHeight = maxWidth / ratio

        let maxAllowed = containerSize.height * 0.95
        return max(min(idealHeight, maxAllowed), 150)
    }

    var body: some View {
        VStack(spacing: 3) {
            // Header del post con círculo de historia
            postHeaderView
                .opacity(isImmersive ? 0 : 1)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)

            // Contenido principal
            ZStack(alignment: .bottom) {
                ZStack {
                    EnhancedCarouselView(
                        mediaItems: mediaItems,
                        currentIndex: $currentImageIndex,
                        showTags: $showTags,
                        aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                        currentMoment: moment,
                        onTagTap: onTagTap,
                        reelsVideos: reelsVideos,
                        isImmersive: $isImmersive
                    )
                    .frame(height: cardHeight)
                    .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                    .animation(MotionPolicy.animation(.spring(response: 0.4, dampingFraction: 0.8), value: isImmersive), value: isImmersive)
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.22) : .black.opacity(0.08),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                    .onAppear {
                        detectAspectRatio()
                        refreshCardHeight()
                    }
                    .onChange(of: availableHeight) { _, _ in
                        refreshCardHeight()
                    }
                    .carouselImmersivePeekGesture(
                        isImmersive: $isImmersive,
                        mediaItems: mediaItems,
                        currentImageIndex: currentImageIndex,
                        detectedAspectRatio: detectedAspectRatio,
                        realAspectRatio: realAspectRatio,
                        onPeek: onPeek
                    )

                    if moment.hasHiddenLayers,
                       moment.hiddenLayerCount > 0,
                       mediaItems.count == 1,
                       mediaItems.first?.type == .image,
                       currentImageIndex == 0 {
                        HiddenLayersOverlayView(moment: moment, isImmersive: isImmersive, requiresFocusForIntro: true)
                            .frame(height: cardHeight)
                            .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                            .zIndex(3)
                    }

                    if mediaItems.count > 1 {
                        VStack {
                            MomentCarouselPageIndicators(
                                count: mediaItems.count,
                                currentIndex: currentImageIndex
                            )
                            .padding(.top, 20)
                            Spacer()
                        }
                        .opacity(isImmersive ? 0 : 1)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)
                    }

                    let currentMediaItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : nil
                    if let currentMediaItem, !currentMediaItem.isHiddenByModeration,
                       let tags = currentMediaItem.tags, !tags.isEmpty {
                        // Esquina inferior izquierda (encima del caption) - Estilo Glass
                        VStack {
                            Spacer()
                            HStack {
                                Button(action: {
                                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                        showTags.toggle()
                                    }
                                }) {
                                    ZStack {
                                        // Background Glass
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 38, height: 38)

                                            .frame(width: 38, height: 38)

                                        // Icon tinted if active
                                        AttachmentIconView(icon: .tagged, preset: .overlayTaggedGlass, tintColor: showTags ? Color(hex: "007AFF") : .white)
                                    }
                                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                                }
                                .padding(.leading, 12)
                                .padding(.bottom, 20)
                                Spacer()
                            }
                        }
                        .zIndex(110)
                        .opacity(isImmersive ? 0 : 1)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)
                    }

                    // ✅ NUEVO: Indicador de aspect ratio (solo para debug si está habilitado)
                    if ProcessInfo.processInfo.environment["DEBUG_ASPECT_RATIO"] != nil {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(aspectRatioType.displayName)")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(.white)
                                    .padding(.trailing, 20)
                                    .padding(.top, 20)
                            }
                            Spacer()
                        }
                    }

                }

                ModernActionButtons(
                    moment: moment,
                    isSaved: $isSaved,
                    isSaveLoading: $isSaveLoading,
                    commentCount: $commentCount,
                    onComment: onComment,
                    onSave: toggleSave,
                    onContextMenu: { onContextMenu(moment) }, // ✅ NUEVO
                    isImmersive: $isImmersive // ✅ NUEVO
                )
                .environmentObject(firestoreService)
            }
            .padding(.horizontal, FeedMomentCardLayout.actionRowHorizontalPadding)

            MomentCaptionView(
                moment: moment,
                style: .feed,
                colorScheme: colorScheme,
                onHashtagTap: onHashtagTap
            )
            .opacity(isImmersive ? 0 : 1)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)
        }
        .feedMomentVisibility(momentId: GlobalVideoManager.profileVideoConsumerId(for: moment))
        .onAppear {
            if !hasLoadedInitialData {
                loadAllPostData()
                refreshAuthorUsername()
                hasLoadedInitialData = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFirstAppear = false
                }
            } else if liveAuthorUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                refreshAuthorUsername()
            }
            refreshCardHeight()
            onNearEnd()
        }
        .onChange(of: firestoreService.savedMomentIds) { _, _ in
            guard let currentUserId = Auth.auth().currentUser?.uid,
                  let momentId = moment.id,
                  firestoreService.hasLoadedSavedMoments(for: currentUserId) else { return }
            isSaved = firestoreService.savedMomentIds.contains(momentId)
        }
        .onChange(of: moment.authorId) { _, _ in
            liveAuthorUsername = ""
            refreshAuthorUsername()
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let userId = notification.userInfo?["userId"] as? String,
                  userId == moment.authorId,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            followButtonState = state
        }

        .fullScreenCover(isPresented: $showSpecificUserStories) {
            StoriesView(startWithUserId: Binding(
                get: { moment.authorId },
                set: { _ in }
            ))
            .environmentObject(firestoreService)
            .onAppear {


            }
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                performFollowToggle()
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
    }

    // Header del post con círculo de historia
    private var postHeaderView: some View {
        HStack(spacing: 8) {
            StoryRingAvatarView(
                userId: moment.authorId,
                size: 44,
                profileZoomNamespace: profileZoomNamespace
            )
            .scaleEffect(isAuthorAvatarPressing ? 0.94 : 1)
            .opacity(isAuthorAvatarPressing ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: isAuthorAvatarPressing)
            .contentShape(Circle())
            .modifier(FeedStoryCirclePressModifier(
                isPressing: $isAuthorAvatarPressing,
                onTap: resolveAuthorAvatarTap,
                onLongPress: onAuthorAvatarLongPress.map { callback in
                    { [authorAvatarAnchorCapture] in
                        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !authorId.isEmpty else { return }
                        callback(authorId, authorAvatarAnchorCapture.resolvedFrame)
                    }
                }
            ))
            .background {
                ZStack {
                    FeedStoryCircleAnchorProbe(capture: authorAvatarAnchorCapture)
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { authorAvatarAnchorCapture.globalFrame = geometry.frame(in: .global) }
                            .onChange(of: geometry.frame(in: .global)) { _, newValue in
                                authorAvatarAnchorCapture.globalFrame = newValue
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 4) {
                    Button(action: openAuthorProfile) {
                        Text(displayAuthorUsername)
                            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                            .foregroundStyle(adaptiveColors.primary)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // ✅ INSIGNIA DE VERIFICADO
                    if moment.authorId == Auth.auth().currentUser?.uid {
                        // Para el usuario actual, verificar si está verificado
                        CurrentUserVerifiedBadge(size: 14)
                    } else {
                        // Para otros usuarios, verificar si están verificados
                        VerifiedBadgeView(userId: moment.authorId, size: 14)
                    }

                    Text("·")
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(adaptiveColors.tertiary)

                    Text(moment.timestamp.timeAgoDisplay())
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(adaptiveColors.tertiary)
                }

                if let location = moment.location, !location.isEmpty {
                    Button(action: {
                        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedLocation.isEmpty else {
                            return
                        }

                        onLocationTap(trimmedLocation, moment.locationCoordinate?.toCLLocationCoordinate2D)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(adaptiveColors.accent)

                            Text(location)
                                .font(.system(size: legacyPoppinsSize(13)))
                                .foregroundStyle(adaptiveColors.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Spacer()

            if moment.authorId != Auth.auth().currentUser?.uid {
                ModernFollowButton(
                    state: followButtonState,
                    isLoading: isFollowLoading,
                    colorScheme: colorScheme,
                    action: toggleFollow
                )
            }
        }
        .padding(.horizontal, FeedMomentCardLayout.headerHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func handleAuthorAvatarTap(hasStory: Bool) {
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else { return }

        if let onAuthorAvatarTap {
            onAuthorAvatarTap(authorId, hasStory)
        } else if hasStory {
            showSpecificUserStories = true
        } else {
            openAuthorProfile()
        }
    }

    private func resolveAuthorAvatarTap() {
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else { return }

        guard let viewerId = Auth.auth().currentUser?.uid else {
            handleAuthorAvatarTap(hasStory: false)
            return
        }

        StoryRingResolverService.shared.resolve(
            viewerId: viewerId,
            authorId: authorId,
            privacyService: privacyService,
            useCache: true
        ) { snapshot in
            DispatchQueue.main.async {
                handleAuthorAvatarTap(hasStory: snapshot.hasStory)
            }
        }
    }

    // ✅ MEJORADO: Función detectAspectRatio - SIEMPRE usar el aspect ratio guardado si está disponible
    private func detectAspectRatio() {
        // ✅ PRIMERO Y PRINCIPAL: Usar aspect ratio guardado en la base de datos (no recalcular)
        if let savedAspectRatio = moment.aspectRatio, !savedAspectRatio.isEmpty {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            let expectedRatioValue = aspectRatioFromDB.value

            // Todo contenido más vertical que 4:5 se cropea
            let displayRatio: CGFloat
            if expectedRatioValue < 0.8 && expectedRatioValue > 0 {
                displayRatio = 0.8
            } else if expectedRatioValue > 0 && expectedRatioValue.isFinite {
                displayRatio = expectedRatioValue
            } else {
                displayRatio = 1.0
            }

            // Solo actualizar si el valor actual es diferente
            if detectedAspectRatio != displayRatio {
                DispatchQueue.main.async {
                    self.realAspectRatio = expectedRatioValue // ✅ Siempre guardar el real
                    self.detectedAspectRatio = displayRatio
                    self.refreshCardHeight()

                    // Clasificar el tipo
                    if displayRatio < 0.7 { self.aspectRatioType = .reels }
                    else if displayRatio < 0.9 { self.aspectRatioType = .portrait }
                    else if displayRatio < 1.3 { self.aspectRatioType = .square }
                    else { self.aspectRatioType = .landscape }
                }
            }
            return
        }

        // ✅ SOLO FALLBACK: Si NO hay aspect ratio guardado, detectar una sola vez
        // Evitar detectar múltiples veces para el mismo momento
        guard detectedAspectRatio == 1.0 || detectedAspectRatio == 0 else {
            return // Ya se detectó
        }

        // ✅ FALLBACK: Si no hay aspect ratio guardado, detectar una sola vez
        guard let firstItem = mediaItems.first, !firstItem.url.isEmpty else {

            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.8 // Fallback a 4:5
                self.aspectRatioType = .portrait
                self.refreshCardHeight()
            }
            return
        }

        if firstItem.type == .image {

            if let url = URL(string: firstItem.url) {
                KingfisherManager.shared.retrieveImage(with: url) { result in
                    switch result {
                    case .success(let value):
                        let imageSize = value.image.size
                        let ratio = imageSize.width / imageSize.height
                        DispatchQueue.main.async {
                            if ratio > 0 && ratio.isFinite {
                                self.detectedAspectRatio = ratio
                                self.classifyAspectRatio(ratio)
                            } else {
                                self.detectedAspectRatio = 1.0
                                self.aspectRatioType = .square
                            }
                        }
                    case .failure:
                        DispatchQueue.main.async {
                            self.detectedAspectRatio = 0.8
                            self.aspectRatioType = .portrait
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.detectedAspectRatio = 0.8
                    self.aspectRatioType = .portrait
                }
            }
        } else {
            // ✅ MEJORADO: Para videos, detectar si es vertical (reels) o horizontal (landscape)


            // Por defecto, asumir formato reels para videos (9:16)
            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.5625 // 9÷16 = 0.5625
                self.aspectRatioType = .reels
            }

            if let url = URL(string: firstItem.url) {
                let asset = AVURLAsset(url: url)
                Task {
                    do {
                        let track = try await asset.loadTracks(withMediaType: .video).first
                        if let track = track {
                            let size = try await track.load(.naturalSize)
                            let videoRatio = size.width / size.height

                            DispatchQueue.main.async {
                                self.detectedAspectRatio = videoRatio
                                self.classifyAspectRatio(videoRatio)
                            }
                        }
                    } catch {

                    }
                }
            }
        }
    }

    // ✅ NUEVA: Función helper para clasificar aspect ratios
    private func classifyAspectRatio(_ ratio: CGFloat) {
        let tolerance: CGFloat = 0.05

        if abs(ratio - 1.0) < tolerance {
            // Square: ~1.0 (como 1080x1080)
            self.aspectRatioType = .square

        } else if abs(ratio - 0.8) < tolerance {
            // Portrait 4:5: ~0.8 (como 1080x1350)
            self.aspectRatioType = .portrait

        } else if abs(ratio - 0.5625) < tolerance {
            // Reels 9:16: ~0.5625 (como 1080x1920)
            self.aspectRatioType = .reels

        } else if ratio > 1.4 {
            // Landscape: > 1.4 (16:9 = 1.778)
            self.aspectRatioType = .landscape

        } else if ratio < 0.7 {
            // Muy vertical: usar como reels
            self.aspectRatioType = .reels

        } else {
            // Default entre ratios: usar square
            self.aspectRatioType = .square

        }
    }

    // Resto de funciones sin cambios
    private func loadAllPostData() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }

        // ✅ PERF: Usar contador denormalizado del moment para evitar query por card
        commentCount = moment.commentCount

        if moment.authorId != currentUserId {
            if let cachedState = FollowStateStore.shared.state(for: moment.authorId) {
                followButtonState = cachedState
            }

            privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: moment.authorId) { state in
                DispatchQueue.main.async {
                    let reconciledState = FollowStateStore.shared.reconciledState(state, for: self.moment.authorId)
                    self.followButtonState = reconciledState
                    FollowStateStore.shared.setState(reconciledState, for: self.moment.authorId)
                }
            }
        }

        if firestoreService.hasLoadedSavedMoments(for: currentUserId) {
            isSaved = firestoreService.savedMomentIds.contains(momentId)
        } else {
            firestoreService.checkIfSaved(userId: currentUserId, momentId: momentId) { result in
                if case .success(let saved) = result {
                    DispatchQueue.main.async {
                        self.isSaved = saved
                    }
                }
            }
        }
    }

    private func openAuthorProfile() {
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else { return }

        if let onOpenUserProfile {
            onOpenUserProfile(authorId)
        } else {
            LegacyNavigationBridge.userProfileInFeed(userId: authorId)
        }
    }

    private func refreshAuthorUsername() {
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveAuthorUsername = ""
            return
        }

        // Mostrar de inmediato el username denormalizado del propio moment para
        // evitar parpadeo y una lectura forzada por cada card visible.
        let embedded = moment.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !embedded.isEmpty {
            liveAuthorUsername = embedded
        }

        // Usar el caché con TTL (getUser) en lugar de forzar refetch (refreshUser).
        UserCacheService.shared.getUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !fetchedUsername.isEmpty else { return }
            DispatchQueue.main.async {
                guard self.moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines) == authorId else { return }
                self.liveAuthorUsername = fetchedUsername
            }
        }
    }

    private func loadCommentCount() {
        guard let momentId = moment.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        // ✅ VALIDAR: Solo cargar comentarios si el usuario puede ver el momento
        firestoreService.canViewContent(currentUserId: currentUserId, targetUserId: moment.authorId) { result in
            switch result {
            case .success(let canView):
                guard canView else { return } // No cargar comentarios si no puede ver el momento

                // ✅ Solo cargar comentarios si tiene permisos
                self.firestoreService.db.collection("users").document(self.moment.authorId)
                    .collection("moments").document(momentId)
                    .collection("comments")
                    .getDocuments { snapshot, error in
                        if error != nil {
                            return
                        }

                        DispatchQueue.main.async {
                            let newCount = snapshot?.documents.count ?? 0
                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                                self.commentCount = newCount
                            }
                        }
                    }

            case .failure(_):
                // Si falla la verificación de permisos, no cargar comentarios
                return
            }
        }
    }

    private func toggleFollow() {
        if followButtonState == .following {
            showingUnfollowConfirmation = true
            return
        }

        performFollowToggle()
    }

    private func performFollowToggle() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard followButtonState.isActionable else { return }

        let previousState = followButtonState
        let optimisticState: FollowButtonState = {
            switch previousState {
            case .following:
                return .canFollow
            case .canRequestFollow:
                return .requestPendingCancellable
            case .requestPendingCancellable:
                return .canRequestFollow
            case .canFollow:
                return .following
            default:
                return previousState
            }
        }()

        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            self.followButtonState = optimisticState
        }
        FollowStateStore.shared.setState(optimisticState, for: moment.authorId)

        isFollowLoading = true

        if previousState == .following {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error != nil {
                        // Revert on error
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            self.followButtonState = previousState
                        }
                        FollowStateStore.shared.setState(previousState, for: self.moment.authorId)
                    }
                }
            }
        } else if previousState == .requestPendingCancellable {
            firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error != nil {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            self.followButtonState = previousState
                        }
                        FollowStateStore.shared.setState(previousState, for: self.moment.authorId)
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error != nil {
                        // Revert on error
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            self.followButtonState = previousState
                        }
                        FollowStateStore.shared.setState(previousState, for: self.moment.authorId)
                    }
                }
            }
        }
    }

    private func toggleSave() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }

        // ✅ OPTIMISTIC UPDATE
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            self.isSaved.toggle()
        }

        isSaveLoading = true

        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { error in
            DispatchQueue.main.async {
                self.isSaveLoading = false
                if error != nil {
                    // Revert on error
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
}
// ✅ COMPONENTES AUXILIARES (reusables)

// Enhanced Carousel View — ScrollView paging (sin lazy-swap ni TabView)
struct EnhancedCarouselView: View {
    let mediaItems: [MediaItem]
    @Binding var currentIndex: Int
    @Binding var showTags: Bool
    let aspectRatio: CGFloat
    let currentMoment: Moment
    var onTagTap: ((String) -> Void)? = nil
    var reelsVideos: [VideoMoment]? = nil
    var allowsVideoPlayback: Bool = true
    @Binding var isImmersive: Bool

    @State private var scrollPosition: Int?

    private var isCarousel: Bool { mediaItems.count > 1 }

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let pageHeight = geometry.size.height

            if isCarousel {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                            MediaItemView(
                                item: item,
                                aspectRatio: aspectRatio,
                                prefersUnifiedCarouselFrame: true,
                                currentMoment: currentMoment,
                                showTags: $showTags,
                                onTagTap: onTagTap,
                                reelsVideos: reelsVideos,
                                allowsVideoPlayback: allowsVideoPlayback && index == currentIndex,
                                isImmersive: $isImmersive
                            )
                            .frame(width: pageWidth, height: pageHeight)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrollPosition)
                .scrollClipDisabled(false)
                .onAppear {
                    scrollPosition = currentIndex
                }
                .onChange(of: currentIndex) { _, newValue in
                    guard scrollPosition != newValue else { return }
                    scrollPosition = newValue
                }
                .onChange(of: scrollPosition) { _, newValue in
                    guard let newValue, newValue != currentIndex else { return }
                    currentIndex = newValue
                }
            } else if let item = mediaItems.first {
                MediaItemView(
                    item: item,
                    aspectRatio: aspectRatio,
                    prefersUnifiedCarouselFrame: false,
                    currentMoment: currentMoment,
                    showTags: $showTags,
                    onTagTap: onTagTap,
                    reelsVideos: reelsVideos,
                    allowsVideoPlayback: allowsVideoPlayback,
                    isImmersive: $isImmersive
                )
                .frame(width: pageWidth, height: pageHeight)
            }
        }
    }
}

struct MediaItemView: View {
    @Environment(\.displayScale) private var displayScale
    let item: MediaItem
    let aspectRatio: CGFloat
    let prefersUnifiedCarouselFrame: Bool
    let currentMoment: Moment
    @Binding var showTags: Bool
    var onTagTap: ((String) -> Void)? = nil
    var reelsVideos: [VideoMoment]? = nil
    var allowsVideoPlayback: Bool = true
    @Binding var isImmersive: Bool

    @State private var reelsSession: ReelsSessionPresentation? = nil
    @State private var isVisible = false
    @State private var loadedAspectRatio: CGFloat? = nil
    @ObservedObject private var videoIndex = VideoMomentsIndex.shared

    private struct ReelsSessionPresentation: Identifiable {
        let id = UUID()
        let videos: [VideoMoment]
        let startIndex: Int
        let startSeconds: Double
    }

    private var resolvedItemAspectRatio: CGFloat {
        if let loadedAspectRatio, loadedAspectRatio.isFinite, loadedAspectRatio > 0 {
            return loadedAspectRatio
        }
        guard let ratio = item.resolvedAspectRatioValue, ratio.isFinite, ratio > 0 else {
            return aspectRatio
        }
        return ratio
    }

    private var usesBlurredFitLayout: Bool {
        guard prefersUnifiedCarouselFrame else { return false }
        return MomentCarouselLayoutRules.presentationMode(
            for: resolvedItemAspectRatio,
            canvasAspectRatio: aspectRatio
        ) == .fitWithBlur
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack { // ✅ CAMBIADO: ZStack para que el overlay esté ENCIMA
                if !prefersUnifiedCarouselFrame {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                }

                if item.isHiddenByModeration {
                    ModeratedMediaItemView(item: item)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                } else if item.type == .image {
                    if usesBlurredFitLayout {
                        CarouselMediaBackdropView(item: item)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }

                    Group {
                        if usesBlurredFitLayout {
                            KFImage(URL(string: item.url))
                                .placeholder { Color.clear }
                                .cancelOnDisappear(true)
                                .onSuccess { result in
                                    let ratio = result.image.size.width / max(result.image.size.height, 1)
                                    if ratio.isFinite, ratio > 0 {
                                        loadedAspectRatio = ratio
                                    }
                                }
                                .setProcessor(
                                    DownsamplingImageProcessor(size: geometry.size)
                                )
                                .scaleFactor(displayScale)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            KFImage(URL(string: item.url))
                                .placeholder { Color.clear }
                                .cancelOnDisappear(true)
                                .onSuccess { result in
                                    let ratio = result.image.size.width / max(result.image.size.height, 1)
                                    if ratio.isFinite, ratio > 0 {
                                        loadedAspectRatio = ratio
                                    }
                                }
                                .setProcessor(
                                    DownsamplingImageProcessor(size: geometry.size)
                                )
                                .scaleFactor(displayScale)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle()) // ✅ Asegurar área de tap
                    .simultaneousGesture( // ✅ USAR simultaneousGesture para mayor fiabilidad en TabView
                        TapGesture().onEnded {
                            if let tags = item.tags, !tags.isEmpty {
                                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                    showTags.toggle()
                                }
                            }
                        }
                    )
                } else {
                    // ✅ VIDEOS: Con crop inteligente para el feed
                    CroppedVideoPlayer(
                        item: item,
                        aspectRatio: aspectRatio,
                        prefersUnifiedCarouselFrame: prefersUnifiedCarouselFrame,
                        currentMoment: currentMoment,
                        allowsVideoPlayback: allowsVideoPlayback,
                        onTap: {
                            if let tags = item.tags, !tags.isEmpty {
                                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                    showTags.toggle()
                                }
                            } else {
                                openReelsViewer()
                            }
                        },
                        isImmersive: $isImmersive // ✅ NUEVO
                    )
                }

                // ✅ Overlay de etiquetas
                if !item.isHiddenByModeration, let tags = item.tags, !tags.isEmpty {
                    PhotoTagOverlayView(tags: tags, isVisible: showTags, onTagTap: onTagTap)
                        .zIndex(20)
                }
            }
        }
        .clipped()
        .opacity(prefersUnifiedCarouselFrame ? 1.0 : (isVisible ? 1.0 : 0.8))
        .scaleEffect(prefersUnifiedCarouselFrame ? 1.0 : (isVisible ? 1.0 : 0.98))
        .animation(prefersUnifiedCarouselFrame ? nil : .easeInOut(duration: 0.4), value: isVisible)
        .onAppear {
            if prefersUnifiedCarouselFrame {
                isVisible = true
            } else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isVisible = true
                }
            }
        }
        .onDisappear {
            if !prefersUnifiedCarouselFrame {
                isVisible = false
            }
        }
        .fullScreenCover(item: $reelsSession, onDismiss: {
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                isImmersive = false
            }
            let handoffMedia: MediaItem? = prefersUnifiedCarouselFrame ? item : nil
            GlobalVideoManager.shared.completeReelsFeedHandoff(for: currentMoment, mediaItem: handoffMedia)
            // Reanudar el vídeo del feed que estaba activo antes de abrir Reels.
            GlobalVideoManager.shared.playVideo(feedVideoConsumerId)
        }) { session in
            ReelsViewer(
                videos: session.videos,
                startIndex: session.startIndex,
                initialStartSeconds: session.startSeconds
            )
            .environmentObject(FirestoreService.shared)
        }
    }

    private var feedVideoConsumerId: String {
        if prefersUnifiedCarouselFrame {
            GlobalVideoManager.profileVideoConsumerId(for: currentMoment, mediaItem: item)
        } else {
            GlobalVideoManager.profileVideoConsumerId(for: currentMoment)
        }
    }

    private var resolvedReelsVideos: [VideoMoment] {
        reelsVideos ?? videoIndex.videoMoments
    }

    private var resolvedReelsStartIndex: Int {
        guard let momentId = currentMoment.id else { return 0 }
        if let reelsVideos {
            return reelsVideos.firstIndex { $0.moment.id == momentId } ?? 0
        }
        return videoIndex.reelsStartIndex(for: momentId)
    }

    private func openReelsViewer() {
        // Congelar la cola al abrir: el feed puede regenerar `videoMoments` mientras swipas.
        let sessionVideos = resolvedReelsVideos
        guard !sessionVideos.isEmpty else { return }
        let start = resolvedReelsStartIndex
        let safeStart = min(max(0, start), sessionVideos.count - 1)
        // Pausar todos los reproductores del feed para evitar doble reproducción
        // (audio/decoders duplicados) mientras Reels está en primer plano.
        let handoffMedia: MediaItem? = prefersUnifiedCarouselFrame ? item : nil
        GlobalVideoManager.shared.markReelsFeedHandoff(for: currentMoment, mediaItem: handoffMedia)
        GlobalVideoManager.shared.pauseAllVideos()
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
            isImmersive = true
        }
        reelsSession = ReelsSessionPresentation(
            videos: sessionVideos,
            startIndex: safeStart,
            startSeconds: currentPlaybackStartSeconds
        )
    }

    private var currentPlaybackStartSeconds: Double {
        GlobalVideoManager.shared.playbackPosition(forMomentId: feedVideoConsumerId)
    }
}

private struct CarouselMediaBackdropView: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            backdropContent
                .blur(radius: 20)
                .saturation(0.9)
                .drawingGroup(opaque: false)
                .overlay(Color.black.opacity(0.18))

            LinearGradient(
                colors: [.black.opacity(0.18), .clear, .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backdropContent: some View {
        if item.type == .image {
            KFImage(URL(string: item.url))
                .placeholder { Color.black.opacity(0.2) }
                .resizable()
                .scaledToFill()
        } else if let thumbnailUrl = item.thumbnailUrl, !thumbnailUrl.isEmpty {
            KFImage(URL(string: thumbnailUrl))
                .placeholder { Color.black.opacity(0.2) }
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }
}

private struct ModeratedMediaItemView: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .center) {
            moderatedBackground

            LinearGradient(
                colors: [.black.opacity(0.52), .black.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(NSLocalizedString("mediaModeration.hidden.title", comment: "Hidden content title"))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(.white)

                Text(NSLocalizedString("mediaModeration.hidden.subtitle", comment: "Hidden content subtitle"))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var moderatedBackground: some View {
        if item.type == .image {
            KFImage(URL(string: item.url))
                .placeholder { Color.black.opacity(0.28) }
                .resizable()
                .scaledToFill()
                .blur(radius: 20)
                .saturation(0)
                .overlay(Color.black.opacity(0.18))
                .clipped()
        } else if let thumbnailUrl = item.thumbnailUrl, !thumbnailUrl.isEmpty {
            KFImage(URL(string: thumbnailUrl))
                .placeholder { Color.black.opacity(0.28) }
                .resizable()
                .scaledToFill()
                .blur(radius: 20)
                .saturation(0)
                .overlay(Color.black.opacity(0.18))
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.4))
        }
    }
}

struct CroppedVideoPlayer: View {
    let item: MediaItem
    let aspectRatio: CGFloat
    let prefersUnifiedCarouselFrame: Bool
    let currentMoment: Moment
    var allowsVideoPlayback: Bool = true
    let onTap: () -> Void
    @Binding var isImmersive: Bool // ✅ NUEVO

    @Environment(\.profileDetailDirectVideoPlayback) private var profileDetailDirectVideoPlayback
    @State private var isVisible = false
    /// Solo la preferencia de mute de sesión — no observar `GlobalVideoManager` entero
    /// (activeVideoId / ticks de progreso re-renderizaban todas las celdas y cortaban el scroll).
    @State private var soundEnabledInSession = GlobalVideoManager.shared.userHasEnabledSoundInSession

    private var videoConsumerId: String {
        if prefersUnifiedCarouselFrame {
            GlobalVideoManager.profileVideoConsumerId(for: currentMoment, mediaItem: item)
        } else {
            GlobalVideoManager.profileVideoConsumerId(for: currentMoment)
        }
    }

    private var detailVideoActivationMode: VideoPlaybackActivationMode {
        profileDetailDirectVideoPlayback ? .alwaysWhenVisible : .feedVisibility
    }

    /// URL del tier adaptativo (misma que prebuffer), no el `item.url` crudo.
    private var playbackURLString: String {
        VideoPlaybackSelector.shared.source(for: item, moment: currentMoment)?.playbackURL.absoluteString
            ?? item.url
    }

    /// Botón de silencio/volumen — se oculta cuando isImmersive (ReelsViewer abierto).
    private var muteToggleButton: some View {
        Button {
            GlobalVideoManager.shared.toggleMute(videoConsumerId)
        } label: {
            let isMuted = !soundEnabledInSession
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.48), in: Circle())
        }
        .buttonStyle(.momentsPressIcon)
        .accessibilityLabel(
            NSLocalizedString(
                soundEnabledInSession
                    ? "feed.a11y.mute"
                    : "feed.a11y.unmute",
                comment: "Mute or unmute video"
            )
        )
    }

    private var resolvedItemAspectRatio: CGFloat {
        guard let ratio = item.resolvedAspectRatioValue, ratio.isFinite, ratio > 0 else {
            return aspectRatio
        }
        return ratio
    }

    private var usesBlurredFitLayout: Bool {
        guard prefersUnifiedCarouselFrame else { return false }
        return MomentCarouselLayoutRules.presentationMode(
            for: resolvedItemAspectRatio,
            canvasAspectRatio: aspectRatio
        ) == .fitWithBlur
    }

    @ViewBuilder
    private var videoPosterFallback: some View {
        if let posterURLString = currentMoment.videoPosterURLString(for: item),
           let url = URL(string: posterURLString) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else if let thumbnailUrl = item.thumbnailUrl,
                  !thumbnailUrl.isEmpty,
                  let url = URL(string: thumbnailUrl) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            Color.black.opacity(0.12)
        }
    }

    var body: some View {
        ZStack {
            if !allowsVideoPlayback {
                videoPosterFallback
            } else if usesBlurredFitLayout {
                CarouselMediaBackdropView(item: item)

                ModernVideoPlayer(
                    url: playbackURLString,
                    aspectRatio: resolvedItemAspectRatio,
                    videoId: videoConsumerId,
                    chromeStyle: .socialReels,
                    posterURLString: currentMoment.videoPosterURLString(for: item),
                    mediaItem: item,
                    moment: currentMoment,
                    activationMode: detailVideoActivationMode,
                    consumesDetailHandoff: profileDetailDirectVideoPlayback
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)

                VStack {
                    HStack {
                        Spacer()
                        LiveVideoTimeLabel(
                            consumerId: videoConsumerId,
                            totalDuration: item.videoDuration ?? currentMoment.videoDuration
                        )
                        .padding(.trailing, 8)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .opacity(isImmersive ? 0 : 1)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)
            } else if isReelsFormat {
                // ✅ REELS en feed: player + poster hasta readyToPlay
                ZStack {
                    ModernVideoPlayer(
                        url: playbackURLString,
                        aspectRatio: aspectRatio,
                        videoId: videoConsumerId,
                        chromeStyle: .socialReels,
                        allowsPauseInteraction: false,
                        posterURLString: currentMoment.videoPosterURLString(for: item),
                        mediaItem: item,
                        moment: currentMoment,
                        activationMode: detailVideoActivationMode,
                        consumesDetailHandoff: profileDetailDirectVideoPlayback
                    )

                    // ✅ OVERLAY con gradiente sutil nativo
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "0B1215").opacity(0.0),
                            Color(hex: "0B1215").opacity(0.3)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // ✅ OVERLAY invisible para capturar taps (en el fondo, zIndex bajo)
                    Button(action: {
                        onTap()
                    }) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .zIndex(1) // ✅ Overlay en el fondo

                    // ✅ INDICADORES mejorados nativos (por encima del overlay)
                    VStack {
                        HStack {
                            // ✅ Badge "Reels" nativo (esquina superior izquierda)
                            HStack(spacing: 4) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(NSLocalizedString("feed.reels.badge", comment: "Reels badge"))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.purple.opacity(0.8),
                                                Color.pink.opacity(0.8)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .padding(.leading, 12)
                            .padding(.top, 12)

                            Spacer()

                            // Tiempo en vivo — se oculta al abrir el ReelsViewer
                            LiveVideoTimeLabel(
                                consumerId: videoConsumerId,
                                totalDuration: item.videoDuration ?? currentMoment.videoDuration
                            )
                            .padding(.trailing, 12)
                            .padding(.top, 12)
                        }

                        Spacer()
                    }
                    .zIndex(100)
                    .opacity(isImmersive ? 0 : 1)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)
                }
            } else {
                // ✅ VIDEOS HORIZONTALES: Mantener diseño actual
                ZStack {
                    ModernVideoPlayer(
                        url: playbackURLString,
                        aspectRatio: feedDisplayRatio,
                        videoId: videoConsumerId,
                        chromeStyle: .socialReels,
                        posterURLString: currentMoment.videoPosterURLString(for: item),
                        mediaItem: item,
                        moment: currentMoment,
                        activationMode: detailVideoActivationMode,
                        consumesDetailHandoff: profileDetailDirectVideoPlayback
                    )

                    // ✅ INDICADORES sutiles para videos horizontales
                    VStack {
                        HStack {
                            Spacer()
                            LiveVideoTimeLabel(
                                consumerId: videoConsumerId,
                                totalDuration: item.videoDuration ?? currentMoment.videoDuration
                            )
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                        }

                        Spacer()

                        HStack {
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(6)
                                .background(Color(hex: "0B1215").opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(.trailing, 8)
                                .padding(.bottom, 8)
                        }
                    }
                    .opacity(isImmersive ? 0 : 1)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isImmersive), value: isImmersive)
                }
            }
        }
        // Botón mute siempre visible en detalle — el ReelsViewer tiene el suyo propio.
        .overlay(alignment: .bottomLeading) {
            if allowsVideoPlayback {
                muteToggleButton
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .onReceive(GlobalVideoManager.shared.$userHasEnabledSoundInSession) { enabled in
            soundEnabledInSession = enabled
        }
    }

    // ✅ MEJORADO: Detectar si es formato reels (9:16)
    private var isReelsFormat: Bool {
        aspectRatio < 0.7 || currentMoment.aspectRatio == "9:16"
    }

    // ✅ LÓGICA DE CROP: Solo para videos horizontales
    private var feedDisplayRatio: CGFloat {
        if aspectRatio < 0.7 { // Es video vertical (reels 9:16)
            return aspectRatio // ✅ Mostrar ratio completo para reels (no crop)
        }
        return aspectRatio // Otros formatos mantienen su ratio
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

// Progress Circle (mantener igual que antes)
struct StoryProgressCircle: View {
    let progress: Double
    let isUploading: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: isUploading ?
                        [Color.blue, Color.purple] :
                        [Color.orange, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: progress), value: progress)
        }
    }
}

// ✅ SOLUCIONADO: Vista expandible con detección precisa de hashtags
struct ExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false

    private let maxLines = 2
    private let maxCharacters = 15

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MomentHashtagText(
                content: isExpanded ? content : String(content.prefix(maxCharacters)) + (content.count > maxCharacters ? "..." : ""),
                textFont: .system(size: 14),
                hashtagFont: .system(size: 14, weight: .semibold),
                baseColor: .white,
                mentionColor: Color(hex: "007AFF"),
                textAlignment: .leading,
                shadowColor: .black.opacity(0.4),
                shadowRadius: 3,
                shadowX: 0,
                shadowY: 1,
                onHashtagTap: onHashtagTap,
                onMentionTap: MomentMentionNavigation.openProfile(forUsername:)
            )

            if needsExpansion {
                Button(action: {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "feed.seeLess" : "feed.seeMore")
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                            .foregroundStyle(.white)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
                }
                .scaleEffect(isExpanded ? 1.0 : 0.95)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isExpanded), value: isExpanded)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

// MARK: - Carrusel: peek inmersivo sin interferir con el swipe horizontal

private struct CarouselImmersivePeekModifier: ViewModifier {
    @Binding var isImmersive: Bool
    let mediaItems: [MediaItem]
    let currentImageIndex: Int
    let detectedAspectRatio: CGFloat
    let realAspectRatio: CGFloat
    var onPeek: ((String, CGFloat, Bool) -> Void)? = nil

    @State private var immersiveActivationTask: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: 12,
                pressing: { isPressing in
                    if isPressing {
                        scheduleActivation()
                    } else {
                        cancelActivation()
                        endImmersive()
                    }
                },
                perform: {}
            )
            .onDisappear {
                cancelActivation()
                if isImmersive {
                    endImmersive()
                }
            }
    }

    private func scheduleActivation() {
        cancelActivation()

        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                isImmersive = true
                HapticManager.shared.mediumImpact()

                let currentItem = mediaItems.indices.contains(currentImageIndex)
                    ? mediaItems[currentImageIndex]
                    : mediaItems.first
                let shouldUseFullscreenPeek = mediaItems.count > 1 &&
                    currentItem?.type == .image &&
                    currentItem?.isHiddenByModeration != true

                guard let item = currentItem,
                      item.type == .image,
                      !item.isHiddenByModeration else { return }

                let currentItemRatio = item.resolvedAspectRatioValue ?? realAspectRatio
                guard currentItemRatio > 0,
                      currentItemRatio.isFinite,
                      shouldUseFullscreenPeek || abs(currentItemRatio - detectedAspectRatio) > 0.035 else { return }

                onPeek?(item.url, currentItemRatio, true)
            }
        }

        immersiveActivationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }

    private func cancelActivation() {
        immersiveActivationTask?.cancel()
        immersiveActivationTask = nil
    }

    private func endImmersive() {
        guard isImmersive else { return }
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
            isImmersive = false
            onPeek?("", 1.0, false)
        }
    }
}

extension View {
    func carouselImmersivePeekGesture(
        isImmersive: Binding<Bool>,
        mediaItems: [MediaItem],
        currentImageIndex: Int,
        detectedAspectRatio: CGFloat,
        realAspectRatio: CGFloat,
        onPeek: ((String, CGFloat, Bool) -> Void)? = nil
    ) -> some View {
        modifier(
            CarouselImmersivePeekModifier(
                isImmersive: isImmersive,
                mediaItems: mediaItems,
                currentImageIndex: currentImageIndex,
                detectedAspectRatio: detectedAspectRatio,
                realAspectRatio: realAspectRatio,
                onPeek: onPeek
            )
        )
    }
}

// MARK: - Equatable (evita re-diff del feed completo en cada update)

extension ModernPostCardView: Equatable {
    static func == (lhs: ModernPostCardView, rhs: ModernPostCardView) -> Bool {
        lhs.moment == rhs.moment
            && lhs.colorScheme == rhs.colorScheme
            && abs(lhs.availableHeight - rhs.availableHeight) < 1
            && reelsVideosFingerprint(lhs.reelsVideos) == reelsVideosFingerprint(rhs.reelsVideos)
    }

    /// Evita que `.equatable()` deje una cola Reels obsoleta al crecer el feed.
    private static func reelsVideosFingerprint(_ videos: [VideoMoment]?) -> String {
        guard let videos else { return "" }
        return videos.map(\.id).joined(separator: "|")
    }
}
