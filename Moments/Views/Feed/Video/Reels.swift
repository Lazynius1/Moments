import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine

private struct ReelsStoryRoute: Identifiable {
    let id: String
}

// ✅ PRIVACIDAD: ReelsViewer solo muestra videos que ya pasaron los filtros de privacidad
struct ReelsViewer: View {
    let videos: [VideoMoment]
    let startIndex: Int
    let initialStartSeconds: Double
    @State private var currentIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    init(videos: [VideoMoment], startIndex: Int = 0, initialStartSeconds: Double = 0) {
        self.videos = videos
        self.startIndex = startIndex
        self.initialStartSeconds = initialStartSeconds
        self._currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        ZStack {
            // Fondo negro puro para fullscreen
            Color.black
                .ignoresSafeArea(.all)
            
            if !videos.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        ReelVideoView(
                            video: video,
                            isCurrentVideo: currentIndex == index,
                            startAtSeconds: index == startIndex ? initialStartSeconds : 0,
                            onClose: {
                                dismiss()
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
                .ignoresSafeArea(.container, edges: .all)
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            
                            if value.translation.height > 50 {
                                haptic.impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    if currentIndex > 0 {
                                        currentIndex -= 1
                                    }
                                }
                            } else if value.translation.height < -50 {
                                haptic.impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    if currentIndex < videos.count - 1 {
                                        currentIndex += 1
                                    }
                                }
                            } else if abs(value.translation.width) > 100 {
                                // Swipe horizontal para cerrar
                                haptic.impactOccurred()
                                dismiss()
                            }
                        }
                )
                .onAppear {
                    // ✅ INSTANT PLAYBACK: Precargar los primeros videos al abrir
                     preloadUpcomingVideos(from: currentIndex)
                }
                .onChange(of: currentIndex) { _, newIndex in
                    // ✅ INSTANT PLAYBACK: Precargar dinámicamente al scrollear
                    preloadUpcomingVideos(from: newIndex)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
    
    // ✅ INSTANT PLAYBACK: Lógica de preloading para Reels
    private func preloadUpcomingVideos(from index: Int) {
        // Precargar los siguientes 6 videos (variantes ABR incluidas)
        let preloadCount = 6
        let endIndex = min(index + preloadCount, videos.count)
        
        if index + 1 < endIndex {
            let upcomingVideos = videos[(index + 1)..<endIndex]
            let urls = upcomingVideos.flatMap(\.preloadURLStrings)
            VideoPreloader.shared.preloadAssets(urls: urls)
        }
    }
}

struct ReelVideoView: View {
    let video: VideoMoment
    let isCurrentVideo: Bool
    let startAtSeconds: Double
    let onClose: () -> Void
    
    @StateObject private var playerManager = ReelVideoPlayerManager()
    @State private var showUserActions = false
    @State private var showComments = false
    @State private var commentCount: Int = 0
    @State private var isDoubleTapAnimating = false
    @State private var showContextMenu = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var showDeleteAlert = false
    @State private var navigateToProfile = false
    @State private var hasStory = false
    @State private var hasUnseenStory = false
    @State private var storyCount: Int = 0
    @State private var storyViewedStatus: [Bool] = []
    @State private var storyAudiences: [String?] = []
    @State private var storyRoute: ReelsStoryRoute?
    @State private var liveAuthorUsername: String = ""
    @State private var isDraggingProgress = false
    @State private var wasPlayingBeforeDrag = false
    @State private var isReelCaptionExpanded = false
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var firestoreService: FirestoreService
    private let privacyService = PrivacyService()

    private var displayAuthorUsername: String {
        let fallback = video.moment.username
        let live = liveAuthorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    private var bottomBarBackgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var chromePrimaryColor: Color {
        colorScheme == .dark ? .white : Color(hex: "0B1215")
    }

    private var chromeSecondaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.78) : Color(hex: "0B1215").opacity(0.72)
    }

    private var chromeTertiaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : Color(hex: "0B1215").opacity(0.58)
    }

    private var bottomBarHeight: CGFloat {
        68
    }

    @ViewBuilder
    private var reelCommentBar: some View {
        HStack {
            if !video.moment.disableComments {
                Button(action: {
                    showComments = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(chromeTertiaryColor)

                        Text(NSLocalizedString("comments.add.placeholder", comment: "Add comment placeholder"))
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(chromeTertiaryColor)

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .frame(height: bottomBarHeight)
        .background(bottomBarBackgroundColor)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom

            ZStack {
                // Video Player completamente fullscreen sin controles nativos
                if let player = playerManager.player {
                    VideoPlayerRepresentable(
                        player: player,
                        videoGravity: .resizeAspect,
                        showControls: .constant(false), // Siempre oculto
                        progress: $playerManager.progress,
                        isBuffering: $playerManager.isBuffering
                    )
                    .aspectRatio(contentMode: videoContentMode)  // ✅ Dinámico según orientación
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .clipped()
                    .ignoresSafeArea(.all)
                } else {
                    // Loading state mejorado y más rápido
                    ZStack {
                        // Background con blur sutil
                        Rectangle()
                            .fill(.black)
                        
                        VStack(spacing: 24) {
                            // Loading animation más elegante
                            ZStack {
                                // Círculo exterior
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                    .frame(width: 50, height: 50)
                                
                                // Círculo animado
                                Circle()
                                    .trim(from: 0, to: 0.8)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white, Color.white.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                    )
                                    .frame(width: 50, height: 50)
                                    .rotationEffect(.degrees(playerManager.isBuffering ? 360 : 0))
                                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: playerManager.isBuffering)
                            }
                            .onAppear {
                                playerManager.isBuffering = true
                            }
                            
                            VStack(spacing: 8) {
                                Text(
                                    playerManager.isLoaded
                                    ? NSLocalizedString("feed.reels.video.starting", comment: "Reels starting state")
                                    : NSLocalizedString("feed.reels.video.loading", comment: "Reels loading state")
                                )
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(.white)
                                    .transition(.opacity)
                                
                                if playerManager.isBuffering {
                                    Text(NSLocalizedString("feed.reels.video.optimizing", comment: "Reels optimizing quality"))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                        .transition(.opacity)
                                }
                            }
                        }
                        
                        // Opcional: Mostrar imagen del momento si existe mientras carga el video
                        if let imagePath = video.moment.imagePath, !imagePath.isEmpty {
                            AsyncImage(url: URL(string: imagePath)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .opacity(0.2)
                                    .blur(radius: 3)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                            }
                        }
                    }
                }
                
                // Capa invisible para capturar gestos de reproducción y likes en el fondo,
                // evitando que interfieran con los botones interactivos del overlay superior.
                Color.black.opacity(0.001)
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        // Solo toggle play/pause silencioso
                        playerManager.togglePlayback()
                    }
                    .onTapGesture(count: 2) {
                        // Double tap para like
                        handleDoubleTap()
                    }
                
                // Double tap heart animation - usando feel reaction color
                if isDoubleTapAnimating {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.pink) // Color de la reacción "feel"
                        .scaleEffect(isDoubleTapAnimating ? 1.5 : 0.1)
                        .opacity(isDoubleTapAnimating ? 0 : 1)
                        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: isDoubleTapAnimating)
                }
                
                // Sin controles visuales - solo play/pause silencioso
                VStack(spacing: 0) {
                    HStack {
                        Spacer()

                        VStack(spacing: 10) {
                            Button(action: {
                                let haptic = UIImpactFeedbackGenerator(style: .medium)
                                haptic.impactOccurred()
                                onClose()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(chromePrimaryColor)
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.001))
                                    .contentShape(Circle())
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                playerManager.toggleMute()
                            }) {
                                Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(chromePrimaryColor)
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.001))
                                    .contentShape(Circle())
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                playerManager.isMuted
                                ? NSLocalizedString("feed.video.unmute", comment: "Unmute video")
                                : NSLocalizedString("feed.video.mute", comment: "Mute video")
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(4, safeTop + 2))

                    Spacer()

                    // Gradiente con altura estática — sin animación propia de frame.
                    // Esto elimina la "doble animación" que causaba que el header
                    // y el caption se movieran de forma desincronizada al expandir.
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.2), Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button(action: {
                                        if !video.moment.authorId.isEmpty {
                                            if hasStory {
                                                storyRoute = ReelsStoryRoute(id: video.moment.authorId)
                                            } else {
                                                navigateToProfile = true
                                            }
                                        }
                                    }) {
                                        AsyncProfileImageView(userId: video.moment.authorId)
                                            .frame(width: 42, height: 42)
                                            .clipShape(Circle())
                                            .overlay(
                                                StorySegmentedRing(
                                                    storyCount: storyCount,
                                                    hasStory: hasStory,
                                                    hasUnseenStory: hasUnseenStory,
                                                    storyViewedStatus: storyViewedStatus,
                                                    storyAudiences: storyAudiences,
                                                    isOwnStory: video.moment.authorId == Auth.auth().currentUser?.uid,
                                                    colorScheme: colorScheme,
                                                    ringSize: 42,
                                                    lineWidth: 2.5
                                                )
                                            )
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(displayAuthorUsername)
                                                    .font(.custom("Poppins-SemiBold", size: 15))
                                                    .foregroundColor(chromePrimaryColor)
                                                    .lineLimit(1)

                                            if video.moment.authorId == Auth.auth().currentUser?.uid {
                                                CurrentUserVerifiedBadge(size: 14)
                                            } else {
                                                VerifiedBadgeView(userId: video.moment.authorId, size: 14)
                                            }
                                        }

                                        HStack(spacing: 8) {
                                            Text(formatTimeAgo(video.moment.timestamp))
                                                .font(.custom("Poppins-Regular", size: 12))
                                                .foregroundColor(chromeSecondaryColor)

                                            if let location = video.moment.location, !location.isEmpty {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "location.fill")
                                                        .font(.system(size: 9))
                                                    Text(location)
                                                        .lineLimit(1)
                                                }
                                                .font(.custom("Poppins-Regular", size: 12))
                                                .foregroundColor(chromeTertiaryColor)
                                            }
                                        }
                                    }
                                }

                                MomentCaptionView(
                                    moment: video.moment,
                                    style: .reels,
                                    colorScheme: colorScheme,
                                    onHashtagTap: { _ in },
                                    isReelsCaptionExpanded: $isReelCaptionExpanded
                                )
                                .padding(.leading, -12)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(spacing: 18) {
                                EpicReactionButton(
                                    moment: video.moment,
                                    showCount: video.moment.authorId == Auth.auth().currentUser?.uid || !video.moment.hideLikeCounts,
                                    size: 56,
                                    emojiSize: 28,
                                    pickerXOffset: -110
                                )
                                .environmentObject(firestoreService)

                                if !video.moment.disableComments {
                                    EnhancedReelActionButton(
                                        icon: "bubble.left.fill",
                                        count: commentCount,
                                        isActive: commentCount > 0,
                                        activeColor: .blue,
                                        action: {
                                            showComments = true
                                        }
                                    )
                                }

                                let aud = video.moment.audience?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                                let isEveryone = aud.isEmpty || aud == "everyone"
                                if video.moment.allowSharing && isEveryone {
                                    EnhancedReelActionButton(
                                        icon: "arrowshape.turn.up.right.fill",
                                        count: nil,
                                        isActive: false,
                                        activeColor: .green,
                                        action: {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                showShareSheet = true
                                            }
                                        }
                                    )
                                }

                                EnhancedReelActionButton(
                                    icon: "ellipsis",
                                    count: nil,
                                    isActive: false,
                                    activeColor: .white,
                                    action: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            showContextMenu.toggle()
                                        }
                                    }
                                )
                            }
                            .padding(.bottom, 6)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 22)
                        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isReelCaptionExpanded)
                    }
                }



                // Context Menu Overlay
                if showContextMenu {
                    ModernContextMenuOverlay(
                        moment: video.moment,
                        isPresented: $showContextMenu,
                        onEdit: {
                            // No implementado en reels por ahora
                        },
                        onDelete: {
                            showDeleteAlert = true
                        },
                        onReport: {
                            // showReportSheet = true // ❌ Ya no se usa sheet
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(1000)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showContextMenu)
                }
                
                // Share Sheet
                if showShareSheet {
                    ModernShareBottomSheet(moment: video.moment, isPresented: $showShareSheet)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .zIndex(1001)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showShareSheet)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea(.container, edges: .all)
            .overlay(alignment: .bottom) {
                VStack(spacing: -6) {
                    if playerManager.duration > 0 {
                        let barHeight: CGFloat = isDraggingProgress ? 6 : 2.5
                        let thumbSize: CGFloat = 12

                            ZStack(alignment: .leading) {
                                // Background track
                                Rectangle()
                                    .fill(Color.white.opacity(0.24))
                                    .frame(height: barHeight)

                                // Active progress with brand gradient
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "4158D0"), Color(hex: "C850C0")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geometry.size.width * playerManager.progress), height: barHeight)

                                // Thumb (Circle dot) - displayed when dragging/holding
                                if isDraggingProgress {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: thumbSize, height: thumbSize)
                                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                                        .offset(x: (geometry.size.width * playerManager.progress) - (thumbSize / 2))
                                        .transition(.scale.combined(with: .opacity))
                                }

                                // Interactive touch area (larger height for comfortable scrubbing)
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 30)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                if !isDraggingProgress {
                                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                                    haptic.impactOccurred()

                                                    // Guardar estado de reproducción y pausar
                                                    wasPlayingBeforeDrag = playerManager.isPlaying
                                                    playerManager.pause()

                                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                                        isDraggingProgress = true
                                                    }
                                                }
                                                let stableTouchX = value.startLocation.x + value.translation.width
                                                let newProgress = max(0, min(1, stableTouchX / geometry.size.width))
                                                playerManager.updateProgress(to: newProgress)
                                                playerManager.seekToProgress(newProgress)
                                            }
                                            .onEnded { value in
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                    isDraggingProgress = false
                                                }
                                                let stableTouchX = value.startLocation.x + value.translation.width
                                                let finalProgress = max(0, min(1, stableTouchX / geometry.size.width))
                                                playerManager.seekToProgress(finalProgress, precise: true)

                                                // Reanudar reproducción si estaba reproduciendo
                                                if wasPlayingBeforeDrag {
                                                    playerManager.play()
                                                }
                                            }
                                    )
                            }
                            .frame(width: geometry.size.width, height: 12)
                            .zIndex(1)
                    }

                    reelCommentBar
                        .zIndex(0)
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        /*.sheet(isPresented: $showReportSheet) {
            ReportBottomSheet(moment: video.moment)
        }*/
        .sheet(isPresented: $navigateToProfile) {
            UserProfileView(userId: video.moment.authorId)
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.id))
        }
        .alert("reels.delete.title", isPresented: $showDeleteAlert) {
            Button("common.delete", role: .destructive) {
                deleteMoment()
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("reels.delete.message")
        }
        .onAppear {
            if isCurrentVideo {
                setupVideo()
                loadVideoData()
                checkUserStories()
                refreshAuthorUsername()
                preloadNextVideos()
            }
        }
        .onChange(of: isCurrentVideo) { _, isActive in
            if isActive {
                setupVideo()
                loadVideoData()
                refreshAuthorUsername()
            } else {
                // Pausar inmediatamente cuando no está activo
                playerManager.pause()
            }
        }
        .onChange(of: video.moment.id) { _, _ in
            isReelCaptionExpanded = false
        }
        .onDisappear {
            // Cleanup inmediato al desaparecer
            playerManager.cleanup()
        }
        .sheet(isPresented: $showComments) {
            ModernCommentsView(moment: video.moment)
                .environmentObject(firestoreService)
                .onDisappear {
                    loadCommentCount()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    private var videoContentMode: ContentMode {
        // Si el video es vertical/cuadrado → llenar pantalla
        // Si es horizontal → mostrar completo
        if video.moment.aspectRatio == "9:16" ||
           video.moment.aspectRatio == "1:1" ||
           video.moment.aspectRatio == "4:5" {
            return .fill  // Videos verticales llenan pantalla
        } else {
            return .fit   // Videos horizontales se muestran completos
        }
    }
    
    // MARK: - Funciones auxiliares
    
    // ✅ NUEVO: Función para verificar historias del usuario (con filtrado de privacidad como en el feed)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = video.moment.authorId
        guard !otherUserId.isEmpty else { return }

        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: otherUserId,
            privacyService: privacyService,
            db: firestoreService.db
        ) { snapshot in
            self.hasStory = snapshot.hasStory
            self.hasUnseenStory = snapshot.hasUnseenStory
            self.storyCount = snapshot.storyCount
            self.storyViewedStatus = snapshot.storyViewedStatus
            self.storyAudiences = snapshot.storyAudiences
        }
    }

    private func refreshAuthorUsername() {
        let authorId = video.moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveAuthorUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.video.moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines) == authorId else { return }
                self.liveAuthorUsername = fetchedUsername
            }
        }
    }
    
    private func deleteMoment() {
        guard let momentId = video.moment.id else { return }
        
        // Cerrar context menu
        withAnimation(.easeInOut(duration: 0.3)) {
            showContextMenu = false
        }
        
        // Eliminar de Firestore (igual que en FeedView)
        firestoreService.deleteMoment(
            userId: video.moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                if error != nil {
                    // Aquí podrías mostrar un alert de error
                } else {
                    // ✅ SwiftData: Eliminar del caché local
                    LocalPersistenceService.shared.deleteMoment(momentId: momentId)
                    // Cerrar el reels viewer
                    onClose()
                }
            }
        }
    }
    
    private func handleDoubleTap() {
        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.impactOccurred()
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
            isDoubleTapAnimating = true
        }
        
        // ✅ ACTIVAR REACCIÓN "FEEL" DIRECTAMENTE CON DOBLE TAP
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = video.moment.id else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isDoubleTapAnimating = false
            }
            return
        }
        
        // Agregar reacción "feel" directamente
        firestoreService.addReaction(
            to: momentId,
            reaction: ReactionType.feel.rawValue,
            userId: currentUserId,
            authorId: video.moment.authorId
        ) { error in
            if error != nil {
            } else {
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isDoubleTapAnimating = false
        }
    }
    
    // Sin controles visuales - comportamiento optimizado
    
    // Funciones auxiliares para formateo
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // ... (resto de funciones existentes)
    private func setupVideo() {
        let url = video.playbackURL ?? URL(string: video.videoUrl)
        guard let url else { return }
        playerManager.setupPlayer(with: url, startAtSeconds: startAtSeconds)
    }
    
    private func loadVideoData() {
        loadCommentCount()
    }
    
    private func loadCommentCount() {
        guard let momentId = video.moment.id else { return }
        
        firestoreService.db.collection("users").document(video.moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.commentCount = snapshot?.documents.count ?? 0
                    }
                }
            }
    }
    
    
    private func shareVideo() {
        guard let momentId = video.moment.id else { return }
        let aud = video.moment.audience?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isEveryone = aud.isEmpty || aud == "everyone"
        guard video.moment.allowSharing && isEveryone else { return }
        let shareText = "¡Mira este video en Moments!"
        var components = URLComponents(string: "https://momentsapp.app/moment/\(momentId)")
        if !video.moment.authorId.isEmpty {
            components?.queryItems = [URLQueryItem(name: "a", value: video.moment.authorId)]
        }
        let shareURL = components?.url
        
        let activityViewController = UIActivityViewController(
            activityItems: ([shareText] as [Any]) + ([shareURL].compactMap { $0 } as [Any]),
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityViewController, animated: true)
        }
    }
    
    // ✅ INSTANT PLAYBACK: Lógica de preloading inteligente
    private func preloadNextVideos() {
        // Encontrar el index actual (esto es un poco hacky porque ReelsViewer controla el index, 
        // pero ReelVideoView no lo conoce directamente. 
        // Sin embargo, podemos inferirlo o simplemente precargar los videos "alrededor" de este si tuviéramos acceso a la lista.
        // DADO QUE ReelVideoView solo conoce "un" video, esta lógica debería estar en ReelsViewer (el padre).
        // Moveré esta lógica arriba, pero aquí podemos al menos asegurar que ESTE video esté listo.
        // VideoPreloader.shared.preload(urls: [video.videoUrl]) 
        // (Esto ya se hace al init el player, así que aquí es redundante)
    }
}

// Enhanced Reaction Button
struct EnhancedReelReactionButton: View {
    let moment: Moment
    @Binding var currentReaction: ReactionType?
    @Binding var hasReacted: Bool
    @Binding var reactionCount: Int
    
    @State private var showReactionPicker = false
    @State private var pulseAnimation = false
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                if hasReacted {
                    removeReaction()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showReactionPicker = true
                    }
                }
            }) {
                ZStack {
                    // Background with glassmorphism effect
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(
                                    hasReacted
                                    ? (currentReaction?.color.opacity(0.6) ?? Color.red.opacity(0.6))
                                    : Color.white.opacity(0.2),
                                    lineWidth: hasReacted ? 2 : 1
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    // Pulse effect when reacted
                    if hasReacted && pulseAnimation {
                        Circle()
                            .stroke(currentReaction?.color ?? .red, lineWidth: 2)
                            .frame(width: 56, height: 56)
                            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                            .opacity(pulseAnimation ? 0 : 1)
                            .animation(.easeOut(duration: 0.6), value: pulseAnimation)
                    }
                    
                    // Heart icon with better styling
                    Image(systemName: hasReacted ? (currentReaction?.filledIcon ?? "heart.fill") : "heart")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(hasReacted ? (currentReaction?.color ?? .red) : .white)
                        .scaleEffect(hasReacted ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hasReacted)
                }
            }
            
            // Count with better styling
            if reactionCount > 0 {
                Text(formatCount(reactionCount))
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.8)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            }
            
            // Reaction picker with better animations
            if showReactionPicker {
                VStack(spacing: 12) {
                    ForEach(ReactionType.allCases.prefix(3), id: \.self) { reaction in
                        Button(action: {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            
                            addReaction(reaction)
                            showReactionPicker = false
                        }) {
                            Image(systemName: reaction.filledIcon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(reaction.color)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.9)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(reaction.color.opacity(0.6), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
                        }
                        .scaleEffect(0.9)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(ReactionType.allCases.firstIndex(of: reaction) ?? 0) * 0.1), value: showReactionPicker)
                    }
                }
                .padding(.vertical, 12)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: hasReacted) { _, reacted in
            if reacted {
                pulseAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pulseAnimation = false
                }
            }
        }
    }
    
    private func addReaction(_ reactionType: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReacted = true
            currentReaction = reactionType
            reactionCount += 1
        }
        
        firestoreService.addReaction(
            to: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if error != nil {
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = false
                        self.currentReaction = nil
                        self.reactionCount -= 1
                    }
                }
            }
        }
    }
    
    private func removeReaction() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReacted = false
            currentReaction = nil
            reactionCount -= 1
        }
        
        firestoreService.removeReaction(
            from: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if error != nil {
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = true
                        self.currentReaction = reactionType
                        self.reactionCount += 1
                    }
                }
            }
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}

// Enhanced Action Button
struct EnhancedReelActionButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isPressed = true
                }
                
                action()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPressed = false
                    }
                }
            }) {
                ZStack {
                    Color.clear
                        .frame(width: 56, height: 56)
                        .liquidGlass(in: Circle(), interactive: true)
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                    
                    // Icon with better styling
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isActive ? activeColor : .white)
                        .scaleEffect(isActive ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)

                    if isActive {
                        Circle()
                            .stroke(activeColor.opacity(0.55), lineWidth: 1.8)
                            .frame(width: 56, height: 56)
                    }
                }
            }
            
            // Count badge
            if let count = count, count > 0 {
                Text(formatCount(count))
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.8)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            }
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}

// Enhanced Video Player Manager con seek optimizado
class ReelVideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = true
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering = false
    @Published var isLoaded = false
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var playerItem: AVPlayerItem?
    private var isSeeking = false
    private var lastSeekTime: Date = Date()
    private var pendingStartAtSeconds: Double?
    
    func setupPlayer(with url: URL, startAtSeconds: Double = 0) {
        // Limpiar player anterior si existe
        cleanup()
        pendingStartAtSeconds = startAtSeconds > 0 ? startAtSeconds : nil
        
        
        // ✅ INSTANT PLAYBACK: Usar preloader
        playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        
        // ✅ Buffer inicial optimizado: 2.5s
        // Empiezan a reproducir con solo un buffer inicial carga en background
        playerItem?.preferredForwardBufferDuration = 2.5 // Buffer inicial (2.5s) - balance perfecto
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = true // Seguir cargando mientras está pausado
        // ✅ Priorizar velocidad sobre calidad para inicio más rápido
        if #available(iOS 14.0, *) {
            playerItem?.preferredPeakBitRate = 0 // Sin límite de bitrate, usar toda la velocidad disponible
        }
        
        // Crear player
        player = AVPlayer(playerItem: playerItem)
        
        // Configuración optimizada del reproductor
        player?.automaticallyWaitsToMinimizeStalling = false // Más responsivo
        player?.allowsExternalPlayback = false
        applySessionMuteState()
        
        // Configurar sesión de audio una sola vez
        configureAudioSession()
        
        // Observar estados del player item
        observePlayerItem()
        
        // Configurar loop mejorado
        setupLooping()
        
        // Observar playback
        observePlayback()
    }
    
    // MARK: - Seek optimizado
    func updateProgress(to newProgress: Double) {
        self.progress = newProgress
    }
    
    func seekToProgress(_ targetProgress: Double, precise: Bool = false) {
        guard let player = player, duration > 0 else { return }
        
        let targetTime = targetProgress * duration
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        if precise {
            // Seek preciso al soltar
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                if completed {
                    self?.isSeeking = false
                }
            }
        } else {
            // Seek ultra-rápido y suave a keyframe durante el arrastre
            player.seek(to: cmTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        
        isSeeking = true
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
        }
    }
    
    private func observePlayerItem() {
        guard let playerItem = playerItem else { return }
        
        // Observar estado de carga
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isLoaded = true
                    self?.isBuffering = false
                    self?.applyPendingStartAndPlayIfNeeded()
                case .failed:
                    self?.isBuffering = false
                case .unknown:
                    self?.isBuffering = true
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observar buffering
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                if isEmpty && self?.isPlaying == true && self?.isSeeking == false {
                    self?.isBuffering = true
                }
            }
            .store(in: &cancellables)
        
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likelyToKeepUp in
                if likelyToKeepUp {
                    self?.isBuffering = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupLooping() {
        guard let playerItem = playerItem else { return }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { completed in
                if completed {
                    self?.pendingStartAtSeconds = nil
                    self?.player?.play()
                }
            }
        }
    }

    private func applyPendingStartAndPlayIfNeeded() {
        guard let player else {
            play()
            return
        }

        guard let startAt = pendingStartAtSeconds else {
            play()
            return
        }

        let boundedStart = max(0, startAt)
        pendingStartAtSeconds = nil
        let target = CMTime(seconds: boundedStart, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.play()
        }
    }
    
    func togglePlayback() {
        guard let player = player, isLoaded else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    func play() {
        guard let player = player, isLoaded else { return }
        player.play()
        isPlaying = true
    }
    
    func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
    }

    func toggleMute() {
        guard let player = player else { return }

        let volume = AVAudioSession.sharedInstance().outputVolume
        if isMuted && volume == 0.0 {
            return
        }

        let wasMuted = isMuted
        isMuted.toggle()
        player.isMuted = isMuted

        if wasMuted && !isMuted {
            GlobalVideoManager.shared.enableSoundForSession()
        }
    }

    private func applySessionMuteState() {
        isMuted = !GlobalVideoManager.shared.userHasEnabledSoundInSession
        player?.isMuted = isMuted
    }
    
    private func observePlayback() {
        guard let player = player else { return }
        
        // Observer menos frecuente para mejor performance durante seeks
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let currentItem = player.currentItem,
                  !self.isSeeking else { return } // No actualizar durante seeks
            
            let duration = currentItem.duration
            if CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) {
                let durationSeconds = CMTimeGetSeconds(duration)
                let currentSeconds = CMTimeGetSeconds(time)
                
                if !durationSeconds.isNaN && !currentSeconds.isNaN && durationSeconds > 0 {
                    self.duration = durationSeconds
                    self.progress = currentSeconds / durationSeconds
                }
            }
        }
    }
    
    func cleanup() {
        
        // Pausar antes de limpiar
        player?.pause()
        isPlaying = false
        
        // Remover time observer
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Cancelar publishers
        cancellables.removeAll()
        
        // Remover notificaciones
        NotificationCenter.default.removeObserver(self)
        
        // Limpiar player y player item
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        
        // Reset estados
        progress = 0
        duration = 0
        isBuffering = false
        isLoaded = false
        isSeeking = false
        isMuted = !GlobalVideoManager.shared.userHasEnabledSoundInSession
        pendingStartAtSeconds = nil
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Additional Enhancements

// Custom transition for smooth reel changes
struct ReelTransition: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
    }
}

extension View {
    func reelTransition(isVisible: Bool) -> some View {
        modifier(ReelTransition(isVisible: isVisible))
    }
}

// Elegant loading shimmer effect
struct ShimmerEffect: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.3),
                Color.white.opacity(0.1),
                Color.white.opacity(0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: shimmerOffset)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }
}

// Data models and extensions (existing ones enhanced)
struct VideoMoment: Identifiable {
    let id = UUID()
    let moment: Moment
    let videoUrl: String

    var playbackURL: URL? {
        moment.videoPlaybackSource()?.playbackURL ?? URL(string: videoUrl)
    }

    var preloadURLStrings: [String] {
        if let strings = moment.videoPlaybackSource()?.preheatURLStrings, !strings.isEmpty {
            return strings
        }
        return videoUrl.isEmpty ? [] : [videoUrl]
    }

    init(moment: Moment) {
        self.moment = moment
        let resolved = moment.previewVideoURLString ?? moment.videoUrl ?? ""
        self.videoUrl = resolved
    }
}

extension Array where Element == Moment {
    var videoMoments: [VideoMoment] {
        return self.compactMap { moment in
            guard let videoUrl = moment.previewVideoURLString ?? moment.videoUrl,
                  !videoUrl.isEmpty else { return nil }
            return VideoMoment(moment: moment)
        }
    }
}

// MARK: - Preview Support
#if DEBUG
struct ReelsViewer_Previews: PreviewProvider {
    static var previews: some View {
        ReelsViewer(videos: [], startIndex: 0)
            .preferredColorScheme(.dark)
    }
}
#endif
