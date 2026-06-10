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
                    .foregroundColor(colorScheme == .dark ?
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
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: uploadProgressManager.isUploading)
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
                    .foregroundColor(hasNotification ?
                        .red :  // ✅ ROJO cuando hay notificaciones
                                     (colorScheme == .dark ?
                                      Color.white.opacity(0.9) :
                                        Color.black.opacity(0.8)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasNotification)
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
                    .foregroundColor(colorScheme == .dark ?
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
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .offset(x: 10, y: -10)
                    .scaleEffect(hasMessage ? 1.0 : 0.1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hasMessage)
                }
            }
        }
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
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(adaptiveColors.secondary)
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
    var onPeek: ((String, CGFloat, Bool) -> Void)? = nil // ✅ PEEK: (imageURL, realRatio, isPressing)
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
         onPeek: ((String, CGFloat, Bool) -> Void)? = nil) {

        self.moment = moment
        self.availableHeight = availableHeight
        self.colorScheme = colorScheme
        self.onComment = onComment
        self.onNearEnd = onNearEnd
        self.onHashtagTap = onHashtagTap
        self.onLocationTap = onLocationTap
        self.onContextMenu = onContextMenu
        self.onTagTap = onTagTap
        self.onPeek = onPeek
        _commentCount = State(initialValue: moment.commentCount)

        // ✅ CRÍTICO: Inicialización estática con metadatos SIEMPRE
        // Evitamos que el layout "baile" al cargar confiando en la DB
        if let ratioStr = moment.aspectRatio, !ratioStr.isEmpty {
            let ratio = ProcessedMedia.AspectRatio(from: ratioStr).value
            let safeRatio = (ratio > 0 && ratio.isFinite) ? ratio : 1.0

            // ✅ Guardar el ratio REAL para el long press reveal
            _realAspectRatio = State(initialValue: safeRatio)

            // ✅ REGLA INSTAGRAM: Todo contenido más vertical que 4:5 se cropea en el feed.
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

    // ✅ Estados para el círculo de historia en el header
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    @State private var storyCount: Int = 0
    @State private var storyViewedStatus: [Bool] = []
    @State private var storyAudiences: [String?] = []
    @State private var isLoadingStory: Bool = false
    @State private var liveAuthorUsername: String = ""
    @State private var showStories = false
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
            width: UIScreen.main.bounds.width - 16,
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
        VStack(spacing: 6) {
            // Header del post con círculo de historia
            postHeaderView
                .opacity(isImmersive ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isImmersive)

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
                        isImmersive: $isImmersive
                    )
                    .frame(height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: isImmersive ? 12 : 20))
                    .animation(MotionPolicy.animation(.spring(response: 0.4, dampingFraction: 0.8), value: isImmersive), value: isImmersive)
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.1),
                        radius: 12,
                        x: 0,
                        y: 8
                    )
                    .onAppear {
                        detectAspectRatio()
                        refreshCardHeight()
                    }
                    .onChange(of: availableHeight) { _, _ in
                        refreshCardHeight()
                    }
                    // ✅ NUEVO: Gesto para Modo Inmersivo
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.1)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onEnded { value in
                                // No hacemos nada en onEnded si queremos que sea momentáneo al soltar
                            }
                    )
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in
                        let currentItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : mediaItems.first
                        let shouldUseFullscreenPeek = mediaItems.count > 1 &&
                            currentItem?.type == .image &&
                            currentItem?.isHiddenByModeration != true

                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isImmersive = isPressing
                            if isPressing {
                                HapticManager.shared.mediumImpact()
                                // ✅ PEEK: Comunicar imagen al FeedView para overlay
                                if let item = currentItem, item.type == .image, !item.isHiddenByModeration {
                                    let currentItemRatio = item.resolvedAspectRatioValue ?? realAspectRatio
                                    if currentItemRatio > 0,
                                       currentItemRatio.isFinite,
                                       (shouldUseFullscreenPeek || abs(currentItemRatio - detectedAspectRatio) > 0.035) {
                                        onPeek?(item.url, currentItemRatio, true)
                                    }
                                }
                            } else {
                                onPeek?("", 1.0, false)
                            }
                        }
                    }, perform: {})

                    if moment.hasHiddenLayers,
                       moment.hiddenLayerCount > 0,
                       mediaItems.count == 1,
                       mediaItems.first?.type == .image,
                       currentImageIndex == 0 {
                        HiddenLayersOverlayView(moment: moment, isImmersive: isImmersive, requiresFocusForIntro: true)
                            .frame(height: cardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: isImmersive ? 12 : 20))
                            .zIndex(3)
                    }

                    if mediaItems.count > 1 {
                        VStack {
                            HStack(spacing: 8) {
                                ForEach(0..<mediaItems.count, id: \.self) { index in
                                    Capsule()
                                        .fill(currentImageIndex == index ? getIndicatorColor(for: index) : Color.white.opacity(0.3))
                                        .frame(width: currentImageIndex == index ? 30 : 10, height: 6)
                                        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
                                }
                            }
                            .padding(.top, 20) // ✅ Más arriba para mejor visibilidad
                            Spacer()
                        }
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }

                    let currentMediaItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : nil
                    if let currentMediaItem, !currentMediaItem.isHiddenByModeration,
                       let tags = currentMediaItem.tags, !tags.isEmpty {
                        // Esquina inferior izquierda (encima del caption) - Estilo Glass
                        VStack {
                            Spacer()
                            HStack {
                                Button(action: {
                                    withAnimation(.spring()) {
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
                                        Image(systemName: showTags ? "person.fill" : "person.circle.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(showTags ? Color(hex: "007AFF") : .white)
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
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
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
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
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
            .padding(.horizontal, 8)

            MomentCaptionView(
                moment: moment,
                style: .feed,
                colorScheme: colorScheme,
                onHashtagTap: onHashtagTap
            )
            .opacity(isImmersive ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isImmersive)
        }
        .feedMomentVisibility(momentId: moment.id ?? "\(moment.authorId)_\(moment.timestamp.timeIntervalSince1970)")
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
        HStack(spacing: 12) {
            Button(action: {
                if hasStory {
                    showSpecificUserStories = true
                } else {
                    // Si no tiene historia, ir al perfil
                    NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: moment.authorId)
                }
            }) {
                ZStack {
                    AsyncProfileImageView(userId: moment.authorId)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            StorySegmentedRing(
                                storyCount: storyCount,
                                hasStory: hasStory,
                                hasUnseenStory: hasUnseenStory,
                                storyViewedStatus: storyViewedStatus,
                                storyAudiences: storyAudiences,
                                isOwnStory: false,
                                colorScheme: colorScheme,
                                ringSize: 44,
                                lineWidth: 2.5,
                                hapticsEnabled: false
                            )
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        if moment.authorId == Auth.auth().currentUser?.uid {
                            Button(action: {
                                // Navegar al perfil propio (Tab 4) o mostrar hoja
                                NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: moment.authorId)
                            }) {
                                Text(displayAuthorUsername)
                                    .font(.custom("Poppins-SemiBold", size: 15))
                                    .foregroundColor(adaptiveColors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Button(action: {
                                // Navegar a perfil de otro usuario
                                NotificationCenter.default.post(name: NSNotification.Name("NavigateToUserProfileInFeed"), object: moment.authorId)
                            }) {
                                Text(displayAuthorUsername)
                                    .font(.custom("Poppins-SemiBold", size: 15))
                                    .foregroundColor(adaptiveColors.primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // ✅ INSIGNIA DE VERIFICADO
                        if moment.authorId == Auth.auth().currentUser?.uid {
                            // Para el usuario actual, verificar si está verificado
                            CurrentUserVerifiedBadge(size: 14)
                        } else {
                            // Para otros usuarios, verificar si están verificados
                            VerifiedBadgeView(userId: moment.authorId, size: 14)
                        }
                    }

                    Text(moment.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(adaptiveColors.tertiary)
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
                                .foregroundColor(adaptiveColors.accent)

                            Text(location)
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(adaptiveColors.secondary)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onAppear {
            checkUserStories()
        }
    }

    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        if moment.authorId == currentUserId {
            hasStory = false
            hasUnseenStory = false
            storyCount = 0
            storyViewedStatus = []
            storyAudiences = []
            isLoadingStory = false
            return
        }

        isLoadingStory = true

        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: moment.authorId,
            privacyService: privacyService,
            db: firestoreService.db
        ) { snapshot in
            self.hasStory = snapshot.hasStory
            self.hasUnseenStory = snapshot.hasUnseenStory
            self.storyCount = snapshot.storyCount
            self.storyViewedStatus = snapshot.storyViewedStatus
            self.storyAudiences = snapshot.storyAudiences
            self.isLoadingStory = false
        }
    }

    // ✅ NUEVO: Función para colores de indicadores multicolores
    private func getIndicatorColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "#5b2c6f"), // Púrpura
            Color(hex: "#007bff"), // Azul
            Color(hex: "#40dfcf"), // Turquesa
            Color(hex: "#ff6b6b"), // Rojo coral
            Color(hex: "#4ecdc4"), // Verde azulado
            Color(hex: "#45b7d1"), // Azul claro
            Color(hex: "#96ceb4"), // Verde menta
            Color(hex: "#feca57")  // Amarillo
        ]

        return colors[index % colors.count]
    }

    // ✅ MEJORADO: Función detectAspectRatio - SIEMPRE usar el aspect ratio guardado si está disponible
    private func detectAspectRatio() {
        // ✅ PRIMERO Y PRINCIPAL: Usar aspect ratio guardado en la base de datos (no recalcular)
        if let savedAspectRatio = moment.aspectRatio, !savedAspectRatio.isEmpty {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            let expectedRatioValue = aspectRatioFromDB.value

            // ✅ REGLA INSTAGRAM: Todo contenido más vertical que 4:5 se cropea
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

            _ = KFImage(URL(string: firstItem.url))
                .onSuccess { result in
                    let imageSize = result.image.size
                    let ratio = imageSize.width / imageSize.height


                    DispatchQueue.main.async {
                        // ✅ Validar ratio calculado
                        if ratio > 0 && ratio.isFinite {
                            self.detectedAspectRatio = ratio
                            self.classifyAspectRatio(ratio)
                        } else {
                            self.detectedAspectRatio = 1.0
                            self.aspectRatioType = .square
                        }
                    }
                }
                .onFailure { error in
                    DispatchQueue.main.async {
                        self.detectedAspectRatio = 0.8 // Fallback a 4:5
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

        feedViewModel.listenForCommentUpdates(momentId: momentId, authorId: moment.authorId)

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

    private func refreshAuthorUsername() {
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveAuthorUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
                            withAnimation(.easeInOut(duration: 0.3)) {
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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            self.isSaved.toggle()
        }

        isSaveLoading = true

        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { error in
            DispatchQueue.main.async {
                self.isSaveLoading = false
                if error != nil {
                    // Revert on error
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
}
// ✅ COMPONENTES AUXILIARES (reusables)

// Enhanced Carousel View — render lazy (±1 slide)
struct EnhancedCarouselView: View {
    let mediaItems: [MediaItem]
    @Binding var currentIndex: Int
    @Binding var showTags: Bool
    let aspectRatio: CGFloat
    let currentMoment: Moment
    var onTagTap: ((String) -> Void)? = nil
    @Binding var isImmersive: Bool

    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $currentIndex) {
                ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                    Group {
                        if abs(index - currentIndex) <= 1 {
                            MediaItemView(
                                item: item,
                                aspectRatio: aspectRatio,
                                prefersUnifiedCarouselFrame: mediaItems.count > 1,
                                currentMoment: currentMoment,
                                showTags: $showTags,
                                onTagTap: onTagTap,
                                isImmersive: $isImmersive
                            )
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .tag(index)
                    .frame(width: geometry.size.width)
                    .clipped()
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(MotionPolicy.animation(.easeInOut(duration: 0.4), value: currentIndex), value: currentIndex)
        }
    }
}

struct MediaItemView: View {
    let item: MediaItem
    let aspectRatio: CGFloat
    let prefersUnifiedCarouselFrame: Bool
    let currentMoment: Moment
    @Binding var showTags: Bool
    var onTagTap: ((String) -> Void)? = nil
    @Binding var isImmersive: Bool

    @State private var showReelsViewer = false
    @State private var isVisible = false
    @State private var loadedAspectRatio: CGFloat? = nil
    @ObservedObject private var videoIndex = VideoMomentsIndex.shared

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
                // ✅ SKELETON: Reserva el espacio exacto del ratio con cristal
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

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
                                .onSuccess { result in
                                    let ratio = result.image.size.width / max(result.image.size.height, 1)
                                    if ratio.isFinite, ratio > 0 {
                                        loadedAspectRatio = ratio
                                    }
                                }
                                .setProcessor(
                                    DownsamplingImageProcessor(size: geometry.size)
                                )
                                .scaleFactor(UIScreen.main.scale)
                                .cacheOriginalImage()
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            KFImage(URL(string: item.url))
                                .placeholder { Color.clear }
                                .onSuccess { result in
                                    let ratio = result.image.size.width / max(result.image.size.height, 1)
                                    if ratio.isFinite, ratio > 0 {
                                        loadedAspectRatio = ratio
                                    }
                                }
                                .setProcessor(
                                    DownsamplingImageProcessor(size: geometry.size)
                                )
                                .scaleFactor(UIScreen.main.scale)
                                .cacheOriginalImage()
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
                                withAnimation(.spring()) {
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
                        onTap: {
                            if let tags = item.tags, !tags.isEmpty {
                                withAnimation(.spring()) {
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
        .opacity(isVisible ? 1.0 : 0.8)
        .scaleEffect(isVisible ? 1.0 : 0.98)
        .animation(.easeInOut(duration: 0.4), value: isVisible)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4)) {
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
        }
        .fullScreenCover(isPresented: $showReelsViewer) {
            ReelsViewer(
                videos: videoIndex.videoMoments,
                startIndex: videoIndex.reelsStartIndex(for: currentMoment.id),
                initialStartSeconds: currentPlaybackStartSeconds
            )
            .environmentObject(FirestoreService.shared)
        }
    }

    private func openReelsViewer() {
        showReelsViewer = true
    }

    private var currentPlaybackStartSeconds: Double {
        guard let momentId = currentMoment.id else { return 0 }
        return GlobalVideoManager.shared.playbackPosition(forMomentId: momentId)
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
                    .foregroundColor(.white.opacity(0.92))

                Text(NSLocalizedString("mediaModeration.hidden.title", comment: "Hidden content title"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)

                Text(NSLocalizedString("mediaModeration.hidden.subtitle", comment: "Hidden content subtitle"))
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.78))
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
    let onTap: () -> Void
    @Binding var isImmersive: Bool // ✅ NUEVO

    @State private var isVisible = false

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

    var body: some View {
        ZStack {
            if usesBlurredFitLayout {
                CarouselMediaBackdropView(item: item)

                ModernVideoPlayer(
                    url: item.url,
                    aspectRatio: resolvedItemAspectRatio,
                    videoId: currentMoment.id ?? "video_\(UUID().uuidString)",
                    chromeStyle: .socialReels,
                    posterURLString: currentMoment.videoPosterURLString(for: item),
                    mediaItem: item,
                    moment: currentMoment
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)

                VStack {
                    HStack {
                        Spacer()

                        if let duration = item.videoDuration ?? currentMoment.videoDuration {
                            Text(formatDuration(duration))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "0B1215").opacity(0.6))
                                .cornerRadius(6)
                                .padding(.trailing, 8)
                                .padding(.top, 8)
                        }
                    }

                    Spacer()
                }
                .opacity(isImmersive ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isImmersive)
            } else if isReelsFormat {
                // ✅ REELS en feed: player + poster hasta readyToPlay
                ZStack {
                    ModernVideoPlayer(
                        url: item.url,
                        aspectRatio: aspectRatio,
                        videoId: currentMoment.id ?? "video_\(UUID().uuidString)",
                        chromeStyle: .socialReels,
                        allowsPauseInteraction: false,
                        posterURLString: currentMoment.videoPosterURLString(for: item),
                        mediaItem: item,
                        moment: currentMoment
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
                            .foregroundColor(.white)
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

                            // Duración del video (esquina superior derecha)
                            if let duration = item.videoDuration ?? currentMoment.videoDuration {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "0B1215").opacity(0.6))
                                    .cornerRadius(6)
                                    .padding(.trailing, 12)
                                    .padding(.top, 12)
                            }
                        }

                        Spacer()

                        // ✅ Indicador de expansión mejorado (centro abajo)
                        HStack {
                            Spacer()

                            HStack(spacing: 4) {
                                Text(NSLocalizedString("feed.reels.tapToView", comment: "Tap to view reels"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "0B1215").opacity(0.5))
                            )

                            Spacer()
                        }
                        .padding(.bottom, 12)
                    }
                    .zIndex(100) // ✅ Asegurar que todos los controles estén por encima del overlay
                    .opacity(isImmersive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isImmersive)
                }
            } else {
                // ✅ VIDEOS HORIZONTALES: Mantener diseño actual
                ZStack {
                    ModernVideoPlayer(
                        url: item.url,
                        aspectRatio: feedDisplayRatio,
                        videoId: currentMoment.id ?? "video_\(UUID().uuidString)",
                        chromeStyle: .socialReels,
                        posterURLString: currentMoment.videoPosterURLString(for: item),
                        mediaItem: item,
                        moment: currentMoment
                    )

                    // ✅ INDICADORES sutiles para videos horizontales
                    VStack {
                        HStack {
                            Spacer()

                            if let duration = item.videoDuration ?? currentMoment.videoDuration {
                                Text(formatDuration(duration))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "0B1215").opacity(0.6))
                                    .cornerRadius(6)
                                    .padding(.trailing, 8)
                                    .padding(.top, 8)
                            }
                        }

                        Spacer()

                        HStack {
                            Spacer()

                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(6)
                                .background(Color(hex: "0B1215").opacity(0.4))
                                .cornerRadius(6)
                                .padding(.trailing, 8)
                                .padding(.bottom, 8)
                        }
                    }
                    .opacity(isImmersive ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isImmersive)
                }
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
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
                .animation(.easeInOut(duration: 0.3), value: progress)
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
                textFont: .custom("Poppins-Regular", size: 14),
                hashtagFont: .custom("Poppins-SemiBold", size: 14),
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
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "feed.seeLess" : "feed.seeMore")
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(.white)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
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
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isExpanded)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

// MARK: - Equatable (evita re-diff del feed completo en cada update)

extension ModernPostCardView: Equatable {
    static func == (lhs: ModernPostCardView, rhs: ModernPostCardView) -> Bool {
        lhs.moment == rhs.moment
            && lhs.colorScheme == rhs.colorScheme
            && abs(lhs.availableHeight - rhs.availableHeight) < 1
    }
}
