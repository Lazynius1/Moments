import SwiftUI
import AVFoundation
import AVKit
import FirebaseAuth
import Combine

// ✅ PRIVACIDAD: ReelsViewer solo muestra videos que ya pasaron los filtros de privacidad
struct ReelsViewer: View {
    let videos: [VideoMoment]
    let startIndex: Int
    @State private var currentIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    init(videos: [VideoMoment], startIndex: Int = 0) {
        self.videos = videos
        self.startIndex = startIndex
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
                            onClose: {
                                dismiss()
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
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
            }
            
            // Solo botón de cerrar en la esquina superior derecha
            VStack {
                HStack {
                    Spacer()
                    
                    Button(action: {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.4))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 30) // Alineado con los otros elementos
                
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

struct ReelVideoView: View {
    let video: VideoMoment
    let isCurrentVideo: Bool
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
    @State private var showingStories = false
    @State private var storiesUserId: String = ""
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var firestoreService: FirestoreService
    
    // ✅ NUEVO: Instancia de PrivacyService para verificar historias
    private let privacyService = PrivacyService()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Player completamente fullscreen sin controles nativos
                if let player = playerManager.player {
                    VideoPlayerRepresentable(
                        player: player,
                        showControls: .constant(false), // Siempre oculto
                        progress: $playerManager.progress,
                        isBuffering: $playerManager.isBuffering
                    )
                    .aspectRatio(contentMode: videoContentMode)  // ✅ Dinámico según orientación
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    .background(Color.black)
                    .clipped()
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        // Solo toggle play/pause silencioso como TikTok
                        playerManager.togglePlayback()
                    }
                    .onTapGesture(count: 2) {
                        // Double tap para like
                        handleDoubleTap()
                    }
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
                                Text(playerManager.isLoaded ? "Iniciando..." : "Cargando video...")
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(.white)
                                    .transition(.opacity)
                                
                                if playerManager.isBuffering {
                                    Text("Optimizando calidad...")
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
                
                // Double tap heart animation - usando feel reaction color
                if isDoubleTapAnimating {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.pink) // Color de la reacción "feel"
                        .scaleEffect(isDoubleTapAnimating ? 1.5 : 0.1)
                        .opacity(isDoubleTapAnimating ? 0 : 1)
                        .animation(.spring(response: 0.6, dampingFraction: 0.6), value: isDoubleTapAnimating)
                }
                
                // Sin controles visuales - solo play/pause silencioso como TikTok
                
                // Información del usuario en la parte superior (a la altura del botón cerrar)
                VStack {
                    // Top gradient para legibilidad
                    LinearGradient(
                        colors: [Color.black.opacity(0.4), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .overlay(
                        VStack {
                            // User info a la misma altura que el botón cerrar
                            HStack(spacing: 12) {
                                Button(action: {
                                    if !video.moment.authorId.isEmpty {
                                        if hasStory {
                                            // ✅ Si tiene historias, abrir StoriesView
                                            storiesUserId = video.moment.authorId
                                            showingStories = true
                                        } else {
                                            // ✅ Si no tiene historias, ir al perfil
                                            navigateToProfile = true
                                        }
                                    }
                                }) {
                                    AsyncProfileImageView(userId: video.moment.authorId)
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(storyRingGradient, lineWidth: hasStory ? 2.5 : 0)
                                        )
                                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(video.moment.username)
                                            .font(.custom("Poppins-SemiBold", size: 15))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                        
                                        // ✅ INSIGNIA DE VERIFICADO - Igual que en FeedView
                                        if video.moment.authorId == Auth.auth().currentUser?.uid {
                                            // Para el usuario actual, verificar si está verificado
                                            CurrentUserVerifiedBadge(size: 14)
                                        } else {
                                            // Para otros usuarios, verificar si están verificados
                                            VerifiedBadgeView(userId: video.moment.authorId, size: 14)
                                        }
                                    }
                                    
                                    HStack(spacing: 8) {
                                        // Timestamp
                                        Text(formatTimeAgo(video.moment.timestamp))
                                            .font(.custom("Poppins-Regular", size: 12))
                                            .foregroundColor(.white.opacity(0.8))
                                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                                        
                                        // Location si existe
                                        if let location = video.moment.location, !location.isEmpty {
                                            HStack(spacing: 2) {
                                                Image(systemName: "location.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white.opacity(0.7))
                                                
                                                Text(location)
                                                    .font(.custom("Poppins-Regular", size: 12))
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 30) // Subido más arriba para evitar montajes
                            
                            Spacer()
                        }
                    )
                    
                    Spacer()
                }
                
                // Content overlay con gradients mejorados (más abajo)
                VStack {
                    Spacer()
                    
                    // Bottom gradient for better text readability
                    ZStack(alignment: .bottom) {
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 160)
                        
                        HStack(alignment: .bottom) {
                            // Left side - Content únicamente
                            VStack(alignment: .leading, spacing: 12) {
                                // Content with hashtags
                                if !video.moment.content.isEmpty {
                                    ClickableHashtagsView(
                                        content: video.moment.content,
                                        colorScheme: .dark,
                                        onHashtagTap: { hashtag in
                                        }
                                    )
                                    .lineLimit(4)
                                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                }
                            }
                            .padding(.leading, 20)
                            
                            Spacer()
                            
                            // Right side actions - más elegantes
                            VStack(spacing: 20) {
                                // Reacciones
                                if !video.moment.hideLikeCounts {
                                    EpicReactionButton(moment: video.moment)
                                        .environmentObject(firestoreService)
                                }
                                
                                // Comentarios
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
                                
                                // Compartir
                                if video.moment.allowSharing {
                                    EnhancedReelActionButton(
                                        icon: "arrowshape.turn.up.right.fill",
                                        count: nil,
                                        isActive: false,
                                        activeColor: .green,
                                        action: shareVideo
                                    )
                                }
                                
                                // More options
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
                            .padding(.trailing, 20)
                        }
                        .padding(.bottom, 80)
                    }
                }
                
                // Enhanced progress bar interactiva
                VStack {
                    Spacer()
                    
                    if playerManager.duration > 0 {
                        VStack(spacing: 8) {
                            // Progress bar interactiva estilo TikTok
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background track
                                    Capsule()
                                        .fill(Color.white.opacity(0.4))
                                        .frame(height: 3)
                                    
                                    // Progress fill
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: max(0, geometry.size.width * playerManager.progress), height: 3)
                                    
                                    // Invisible handle area para mejor UX
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 44) // Área de toque más grande
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    // Calcular nueva posición suavemente
                                                    let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                                                    
                                                    // Update inmediato del progress visual
                                                    playerManager.updateProgress(to: newProgress)
                                                    
                                                    // Seek más frecuente pero optimizado
                                                    playerManager.seekToProgress(newProgress)
                                                }
                                                .onEnded { value in
                                                    // Seek final preciso
                                                    let finalProgress = max(0, min(1, value.location.x / geometry.size.width))
                                                    playerManager.seekToProgress(finalProgress, precise: true)
                                                    
                                                    // Continuar reproduciendo
                                                    if !playerManager.isPlaying {
                                                        playerManager.play()
                                                    }
                                                }
                                        )
                                        .onTapGesture { location in
                                            // Tap directo en la línea
                                            let tapProgress = max(0, min(1, location.x / geometry.size.width))
                                            playerManager.seekToProgress(tapProgress, precise: true)
                                        }
                                }
                            }
                            .frame(height: 44) // Área de toque amplia pero visualmente delgada
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 10) // Bajada más abajo para evitar montajes
                    }
                }
                
                // Context Menu Overlay
                if showContextMenu {
                    ModernContextMenuOverlay(
                        moment: video.moment,
                        isPresented: $showContextMenu,
                        showShareSheet: $showShareSheet,
                        onEdit: {
                            // No implementado en reels por ahora
                        },
                        onDelete: {
                            showDeleteAlert = true
                        },
                        onShare: {
                            if video.moment.allowSharing {
                                showShareSheet = true
                            }
                        },
                        onReport: {
                            showReportSheet = true
                        },
                        onCopyLink: {
                            if let momentId = video.moment.id {
                                UIPasteboard.general.string = "https://moments.app/moment/\(momentId)"
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }
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
        }
        .sheet(isPresented: $showReportSheet) {
            ReportBottomSheet(moment: video.moment)
        }
        .sheet(isPresented: $navigateToProfile) {
            UserProfileView(userId: video.moment.authorId)
        }
        .sheet(isPresented: $showingStories) {
            StoriesView(startWithUserId: .constant(storiesUserId))
        }
        .alert("Eliminar momento", isPresented: $showDeleteAlert) {
            Button("Eliminar", role: .destructive) {
                deleteMoment()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("¿Estás seguro de que quieres eliminar este momento? Esta acción no se puede deshacer.")
        }
        .onAppear {
            if isCurrentVideo {
                // Delay mínimo para evitar problemas de memoria
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setupVideo()
                    loadVideoData()
                    checkUserStories() // ✅ NUEVO: Verificar historias del usuario
                }
            }
        }
        .onChange(of: isCurrentVideo) { isActive in
            if isActive {
                // Pequeño delay para transiciones suaves
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    setupVideo()
                    loadVideoData()
                }
            } else {
                // Pausar inmediatamente cuando no está activo
                playerManager.pause()
            }
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
    
    // ✅ NUEVO: Gradiente para anillo de historias (igual que en el feed)
    private var storyRingGradient: LinearGradient {
        if hasUnseenStory {
            // ✅ HISTORIA NO VISTA: Gradiente azul → morado → rosa
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasStory {
            // ✅ HISTORIA YA VISTA: Gris según el tema
            return LinearGradient(
                colors: colorScheme == .dark ?
                [Color.gray.opacity(0.5), Color.gray.opacity(0.7)] :
                [Color.gray.opacity(0.7), Color.gray.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // ✅ SIN HISTORIAS: Sin anillo (transparente)
            return LinearGradient(
                colors: [Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // ✅ NUEVO: Función para verificar historias del usuario (con filtrado de privacidad como en el feed)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = video.moment.authorId
        guard !otherUserId.isEmpty else { return }
        
        // ✅ USAR LA MISMA LÓGICA DEL FEED: Verificar historias con filtrado de privacidad
        firestoreService.db.collection("users").document(otherUserId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
                    return
                }
                
                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }
                
                guard !stories.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
                    return
                }
                
                // ✅ FILTRADO DE PRIVACIDAD: Solo contar historias que se pueden ver
                let group = DispatchGroup()
                var visibleStories: [Story] = []
                var hasUnseen = false
                
                for story in stories {
                    group.enter()
                    // ✅ USAR PRIVACY SERVICE como en el feed
                    self.privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                        if canView {
                            visibleStories.append(story)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    if !visibleStories.isEmpty {
                        self.hasStory = true
                        
                        // ✅ VERIFICAR SI HAY HISTORIAS NO VISTAS (solo de las visibles)
                        var hasUnseenVisible = false
                        let viewGroup = DispatchGroup()
                        
                        for story in visibleStories {
                            viewGroup.enter()
                            self.firestoreService.db.collection("users").document(story.authorId)
                                .collection("stories").document(story.id ?? "")
                                .collection("viewers").document(currentUserId)
                                .getDocument { viewerDoc, _ in
                                    let wasViewed = viewerDoc?.exists == true
                                    if !wasViewed {
                                        hasUnseenVisible = true
                                    }
                                    viewGroup.leave()
                                }
                        }
                        
                        viewGroup.notify(queue: .main) {
                            self.hasUnseenStory = hasUnseenVisible
                        }
                    } else {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
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
                if let error = error {
                    // Aquí podrías mostrar un alert de error
                } else {
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
            if let error = error {
            } else {
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isDoubleTapAnimating = false
        }
    }
    
    // Sin controles visuales - comportamiento como TikTok
    
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
        guard let url = URL(string: video.videoUrl) else { return }
        playerManager.setupPlayer(with: url)
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
        let shareText = "¡Mira este video en Moments!"
        let shareURL = URL(string: "https://moments.app/moment/\(momentId)")
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareText, shareURL].compactMap { $0 },
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityViewController, animated: true)
        }
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
        .onChange(of: hasReacted) { reacted in
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
            if let error = error {
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
            if let error = error {
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
                    // Glassmorphism background
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(
                                    isActive
                                    ? activeColor.opacity(0.6)
                                    : Color.white.opacity(0.2),
                                    lineWidth: isActive ? 2 : 1
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                    
                    // Icon with better styling
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isActive ? activeColor : .white)
                        .scaleEffect(isActive ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
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

// Enhanced Video Player Manager con seek optimizado para TikTok
class ReelVideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering = false
    @Published var isLoaded = false
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var playerItem: AVPlayerItem?
    private var isSeeking = false
    private var lastSeekTime: Date = Date()
    
    func setupPlayer(with url: URL) {
        // Limpiar player anterior si existe
        cleanup()
        
        
        // Crear player item con configuración optimizada
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetAllowsCellularAccessKey: true
        ])
        
        playerItem = AVPlayerItem(asset: asset)
        
        // Configurar player item para mejor rendimiento
        playerItem?.preferredForwardBufferDuration = 3.0 // Buffer más pequeño para seeks rápidos
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        // Crear player
        player = AVPlayer(playerItem: playerItem)
        
        // Configuración optimizada del reproductor
        player?.automaticallyWaitsToMinimizeStalling = false // Más responsivo
        player?.allowsExternalPlayback = false
        player?.volume = 0.8
        
        // Configurar sesión de audio una sola vez
        configureAudioSession()
        
        // Observar estados del player item
        observePlayerItem()
        
        // Configurar loop mejorado
        setupLooping()
        
        // Observar playback
        observePlayback()
    }
    
    // MARK: - Seek optimizado estilo TikTok
    func updateProgress(to newProgress: Double) {
        // Update visual inmediato sin esperar al seek
        DispatchQueue.main.async {
            self.progress = newProgress
        }
    }
    
    func seekToProgress(_ targetProgress: Double, precise: Bool = false) {
        guard let player = player, duration > 0 else { return }
        
        let targetTime = targetProgress * duration
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        if precise {
            // Seek preciso para tap y final de drag
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
                if completed {
                    self?.isSeeking = false
                }
            }
        } else {
            // Seek rápido durante drag (menos preciso pero más fluido)
            let now = Date()
            lastSeekTime = now
            
            // Throttle seeks para mejor performance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self, self.lastSeekTime == now else { return }
                
                player.seek(to: cmTime, toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                           toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
            }
        }
        
        isSeeking = true
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .allowBluetooth])
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
                    self?.play()
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
                    self?.player?.play()
                }
            }
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
    
    init(moment: Moment) {
        self.moment = moment
        self.videoUrl = moment.videoUrl ?? ""
    }
}

extension Array where Element == Moment {
    var videoMoments: [VideoMoment] {
        return self.compactMap { moment in
            guard let videoUrl = moment.videoUrl, !videoUrl.isEmpty else { return nil }
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
