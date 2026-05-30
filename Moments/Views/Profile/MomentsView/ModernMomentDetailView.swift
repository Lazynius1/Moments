import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation

// MARK: - ✅ Vista detallada de momentos con diseño del feed y aspect ratios
struct ModernMomentDetailView: View {
    let moments: [Moment]
    let initialIndex: Int
    let topContentInset: CGFloat
    let onDismiss: () -> Void
    
    @StateObject private var firestoreService = FirestoreService()
    @State private var currentIndex: Int
    
    // ✅ LONG PRESS PEEK: Estado para overlay a nivel de la vista
    @State private var peekImageURL: String? = nil
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekIsProtected = false
    @State private var selectedMoment: Moment?
    @State private var scrollOffset: CGFloat = 0
    @State private var trackedMomentViewIds: Set<String> = []
    
    // ✅ Estados para el menú contextual
    @State private var showContextMenu = false
    @State private var contextMenuMoment: Moment?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    
    // ✅ NUEVOS: Estados para drag transition
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var backgroundOpacity: Double = 1.0
    
    // ✅ NUEVOS: Estados para navegación al explorer
    @State private var selectedHashtag: String = ""
    @State private var showExploreWithHashtag: Bool = false
    
    // ✅ NUEVOS: Navegación de perfil desde tags
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId: String = ""
    @State private var selectedLocationMoment: Moment? // ✅ Usar Item Binding para evitar race conditions en SwiftUI
    
    private let privacyService = PrivacyService()
    private let firestoreService2 = FirestoreService()
    
    init(moments: [Moment], initialIndex: Int, topContentInset: CGFloat = 64, onDismiss: @escaping () -> Void) {
        self.moments = moments
        self.initialIndex = initialIndex
        self.topContentInset = topContentInset
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack { // ✅ Root ZStack para overlays globales
            GeometryReader { geometry in
                let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            
            ZStack(alignment: .top) {
                // ✅ Fondo que se desvanece durante el drag
                ModernDetailBackground(scrollOffset: scrollOffset)
                    .ignoresSafeArea(.all)
                    .opacity(backgroundOpacity)
                
                // ✅ Header fijo superior con efecto cristal
                ModernDetailHeader(
                    moment: moments[safe: currentIndex],
                    safeAreaTop: safeAreaTop,
                    onDismiss: onDismiss,
                    onAvatarTap: { userId, hasStory in
                        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !normalizedUserId.isEmpty else { return }
                        if hasStory {
                            selectedStoryUserId = normalizedUserId
                            showSpecificUserStories = true
                        } else {
                            selectedUserId = normalizedUserId
                            showUserProfile = true
                        }
                    }
                )
                .ignoresSafeArea(.container, edges: .top) // ✅ El header debe ignorar el safe area para pegarse al notch
                .zIndex(10)
                
                // ✅ Contenido principal
                VStack(spacing: 0) {
                    modernMomentsScrollView(
                        geometry: geometry,
                        safeAreaBottom: safeAreaBottom,
                        topContentInset: topContentInset
                    )
                }
                .offset(x: dragOffset)
                .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0) // ✅ Escala durante drag
                
                // ✅ (Eliminado overlay anterior dentro del GeometryReader)
            }
        }
        
        // ✅ Overlays Globales (Root ZStack)
        
        // 1. Context Menu Overlay
        if showContextMenu, let moment = contextMenuMoment {
            ModernContextMenuOverlay(
                moment: moment,
                isPresented: $showContextMenu,
                onEdit: {
                    editedContent = moment.content
                    showEditSheet = true
                },
                onDelete: {
                    showDeleteAlert = true
                },
                onReport: {
                    // showReportSheet = true // ❌ Ya no se usa sheet
                }
            )
            .zIndex(1000)
            .transition(.opacity)
        }
        
        // 2. Share Sheet Overlay (Sin fondo nativo)
        if showShareSheet, let moment = contextMenuMoment {
            ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1001)
        }
        
        // 3. ✅ LONG PRESS PEEK: Overlay a pantalla completa
        if isPeeking, let imageURL = peekImageURL {
            ZStack {
                ScreenshotProtectedView(isProtected: peekIsProtected, fillsContainer: true) {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                        
                        KFImage(URL(string: imageURL))
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: UIScreen.main.bounds.width - 32,
                                height: (UIScreen.main.bounds.width - 32) / peekAspectRatio
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPeeking)
            .allowsHitTesting(false)
            .zIndex(999)
        }
    }
    .navigationBarHidden(true)
        .sheet(
            isPresented: Binding(
                get: { selectedMoment != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedMoment = nil
                    }
                }
            )
        ) {
            if let moment = selectedMoment {
                ModernCommentsView(moment: moment)
                    .environmentObject(firestoreService)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let moment = contextMenuMoment {
                EditMomentView(
                    moment: moment,
                    onSave: { payload in
                        updateMoment(payload: payload)
                    }
                )
            }
        }
        // .sheet(isPresented: $showShareSheet) REMOVED
        .alert(NSLocalizedString("modernMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("modernMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("modernMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
                            Text("modernMomentDetail.delete.message")
        }
        /*.sheet(isPresented: $showReportSheet) {
            if let moment = contextMenuMoment {
                ReportBottomSheet(moment: moment)
            }
        }*/
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        // ✅ Sheet de perfil para navegación de tags
        .sheet(isPresented: $showUserProfile, onDismiss: {
            selectedUserId = ""
        }) {
            if !selectedUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserProfileView(userId: selectedUserId)
            }
        }
        .fullScreenCover(isPresented: $showSpecificUserStories, onDismiss: {
            selectedStoryUserId = ""
        }) {
            StoriesView(
                startWithUserId: Binding(
                    get: { selectedStoryUserId },
                    set: { selectedStoryUserId = $0 }
                )
            )
            .environmentObject(firestoreService)
            .ignoresSafeArea(.keyboard)
        }
        .fullScreenCover(item: $selectedLocationMoment) { moment in
            LocationMapView(
                locationName: resolvedLocationName(moment.location ?? ""),
                coordinate: moment.locationCoordinate?.toCLLocationCoordinate2D,
                isPresented: Binding(
                    get: { selectedLocationMoment != nil },
                    set: { if !$0 { selectedLocationMoment = nil } }
                )
            )
        }
        .onAppear {
            currentIndex = initialIndex
            trackMomentViewIfNeeded(for: moments[safe: initialIndex])
        }
        .onChange(of: currentIndex) { _, newIndex in
            trackMomentViewIfNeeded(for: moments[safe: newIndex])
        }
        .gesture(
            // ✅ NUEVO: Drag gesture suave e interactivo
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    // ✅ Solo drag horizontal hacia la derecha
                    if value.translation.width > 0 {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = value.translation.width
                            isDragging = true
                            
                            // ✅ Calcular opacity basado en el drag (más drag = más transparente)
                            let progress = min(value.translation.width / 200, 1.0)
                            backgroundOpacity = 1.0 - (progress * 0.4) // ✅ Máximo 40% transparencia
                        }
                    }
                }
                .onEnded { value in
                    let dismissThreshold: CGFloat = 120
                    let velocity = value.predictedEndTranslation.width
                    
                    if value.translation.width > dismissThreshold || velocity > 300 {
                        // ✅ Dismiss con animación suave
                        withAnimation(.easeOut(duration: 0.3)) {
                            dragOffset = UIScreen.main.bounds.width
                            backgroundOpacity = 0.0
                        }
                        
                        // ✅ Ejecutar dismiss después de la animación
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        // ✅ Volver a la posición original
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            dragOffset = 0
                            isDragging = false
                            backgroundOpacity = 1.0
                        }
                    }
                }
        )
    }
    
    private func trackMomentViewIfNeeded(for moment: Moment?) {
        guard let moment = moment, let momentId = moment.id else { return }
        guard !moment.authorId.isEmpty else { return }
        guard !trackedMomentViewIds.contains(momentId) else { return }
        
        trackedMomentViewIds.insert(momentId)
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .momentView, with: moment.authorId)
        }
    }
    
    private func resolvedLocationName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return NSLocalizedString("feed.location.default", comment: "Default location name")
    }
    
    private func openLocationMap(for moment: Moment) {
        self.selectedLocationMoment = moment
    }
    
    // ✅ ScrollView principal MODIFICADO para conectar con el menú contextual
    private func modernMomentsScrollView(geometry: GeometryProxy, safeAreaBottom: CGFloat, topContentInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 40) {
                    Color.clear
                        .frame(height: topContentInset)

                    ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                        ScreenshotProtectedView(
                            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                        ) {
                            ModernDetailMomentCard(
                                moment: moment,
                                availableHeight: geometry.size.height - 200,
                                onComment: {
                                    selectedMoment = moment
                                },
                                onContextMenu: {
                                    contextMenuMoment = moment
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        showContextMenu = true
                                    }
                                },
                                onHashtagTap: { hashtag in
                                    selectedHashtag = "#\(hashtag)"
                                    showExploreWithHashtag = true
                                },
                                onTagTap: { userId in
                                    // ✅ NAVEGACIÓN A PERFIL
                                    selectedUserId = userId
                                    showUserProfile = true
                                },
                                onLocationTap: {
                                    openLocationMap(for: moment)
                                },
                                onPeek: { imageURL, ratio, isPressing in
                                    // ✅ LONG PRESS PEEK
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        if isPressing {
                                            peekImageURL = imageURL
                                            peekAspectRatio = ratio
                                            peekIsProtected = (moment.audience?.lowercased() ?? "") != "everyone"
                                            isPeeking = true
                                        } else {
                                            isPeeking = false
                                            peekIsProtected = false
                                        }
                                    }
                                }
                            )
                        }
                        .id(index)
                        .environmentObject(firestoreService)
                        .onAppear {
                            if index != currentIndex {
                                currentIndex = index
                            }
                        }
                    }
                }
                .padding(.top, 0)
                .padding(.bottom, safeAreaBottom + 40)
            }
            .coordinateSpace(name: "scroll")
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(initialIndex, anchor: .center)
                }
            }
        }
    }
    
    // ✅ Resto de funciones (updateMoment, deleteMoment, etc.)...
    private func updateMoment(payload: EditMomentPayload) {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        firestoreService2.updateMomentDetails(
            userId: moment.authorId,
            momentId: momentId,
            content: payload.content,
            audience: payload.audience.rawValue,
            customListId: payload.customListId,
            customViewers: payload.customViewers,
            taggedUsers: payload.taggedUsers,
            location: payload.locationName.isEmpty ? nil : payload.locationName,
            locationCoordinate: payload.locationCoordinate.map {
                Moment.LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            mediaItems: payload.mediaItems
        ) { _ in }
    }
    
    private func deleteMoment() {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        firestoreService2.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
            }
        }
    }
    
    private func scrollToMoment(at index: Int) {
        currentIndex = index
    }
}

// MARK: - ✅ Header centrado y limpio
struct ModernDetailHeader: View {
    let moment: Moment?
    let safeAreaTop: CGFloat
    let onDismiss: () -> Void
    let onAvatarTap: (String, Bool) -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var liveUsername: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Relleno ajustado para el área segura (notch)
            Color.clear
                .frame(height: max(24, safeAreaTop - 6))

            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())

                if let moment = moment {
                    let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)

                    HStack(spacing: 10) {
                            StoryRingAvatarView(
                                userId: authorId,
                                size: 38,
                            lineWidth: 2.2,
                            showBaseStroke: true,
                            baseStrokeColor: .white.opacity(0.15),
                            baseStrokeWidth: 0.5,
                            onTap: { hasStory in
                                guard !authorId.isEmpty else { return }
                                onAvatarTap(authorId, hasStory)
                            }
                        )
                        
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Text(displayUsername(for: moment))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(.primary)
                                
                                VerifiedBadgeView(userId: authorId, size: 13)
                            }
                            
                            Text(moment.timestamp.timeAgoDisplay())
                                .font(.custom("Poppins-Regular", size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                            
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .liquidGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 14)
        }
        .onAppear {
            resolveAuthorUsername()
        }
        .onChange(of: moment?.authorId) { _, _ in
            resolveAuthorUsername()
        }
        .onChange(of: moment?.username) { _, _ in
            if liveUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolveAuthorUsername()
            }
        }
    }

    private func displayUsername(for moment: Moment) -> String {
        let fresh = liveUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return fresh.isEmpty ? moment.username : fresh
    }

    private func resolveAuthorUsername() {
        guard let moment = moment else { return }
        let authorId = moment.authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorId.isEmpty else {
            liveUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: authorId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                let currentAuthorId = self.moment?.authorId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard currentAuthorId == authorId else { return }
                self.liveUsername = fetchedUsername
            }
        }
    }
}


// MARK: - ✅ Tarjeta de momento detallada con aspect ratios dinámicos CORREGIDA
struct ModernDetailMomentCard: View {
    let moment: Moment
    let availableHeight: CGFloat
    let onComment: () -> Void
    let onContextMenu: () -> Void
    let onHashtagTap: (String) -> Void
    var onTagTap: ((String) -> Void)? = nil // ✅ Tag Navigation
    var onLocationTap: (() -> Void)? = nil
    var onPeek: ((String, CGFloat, Bool) -> Void)? = nil // ✅ PEEK callback
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme
    @State private var currentImageIndex = 0
    
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
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var realAspectRatio: CGFloat = 1.0 // ✅ Ratio real sin cap
    @State private var isSaved: Bool = false
    @State private var isSaveLoading: Bool = false
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    @State private var showTags: Bool = false // ✅ NUEVO: Control de etiquetas
    @State private var isImmersive: Bool = false // ✅ NUEVO: Soporte para modo inmersivo
    @State private var aspectRatioType: AspectRatioType = .square
    
    enum AspectRatioType {
        case square, portrait, landscape, reels
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 450
            case .portrait: return 550
            case .landscape: return 300
            case .reels: return 1000 // Inmersivo, sin límite estricto corto
            }
        }
        
        var exactRatio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8
            case .landscape: return 16.0/9.0
            case .reels: return 9.0/16.0
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
    
    private var cardHeight: CGFloat {
        let maxWidth = UIScreen.main.bounds.width - 32
        
        guard maxWidth > 0 else { return 350 }
        
        let aspectRatio: CGFloat
        if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
            aspectRatio = detectedAspectRatio
        } else {
            aspectRatio = aspectRatioType.exactRatio
        }
        
        let calculatedHeight = maxWidth / aspectRatio
        
        // Para Reels, dejamos que crezca más libremente
        if aspectRatioType == .reels {
            let maxReelsHeight = availableHeight + 100 // Permitir que sea inmersivo
            return min(calculatedHeight, maxReelsHeight)
        }
        
        return min(calculatedHeight, aspectRatioType.maxHeight)
    }

    private var activeMediaItem: MediaItem? {
        mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : mediaItems.first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                ZStack(alignment: .topLeading) {
                    EnhancedCarouselView(
                        mediaItems: mediaItems,
                        currentIndex: $currentImageIndex,
                        showTags: $showTags,
                        aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                        allMoments: [moment],
                        currentMoment: moment,
                        onTagTap: onTagTap,
                        isImmersive: $isImmersive
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.1)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onEnded { _ in }
                    )
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressing in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.isImmersive = isPressing
                            if isPressing {
                                HapticManager.shared.mediumImpact()
                                let currentItem = activeMediaItem
                                let shouldUseFullscreenPeek = mediaItems.count > 1 &&
                                    currentItem?.type == .image &&
                                    currentItem?.isHiddenByModeration != true

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
                    .frame(height: max(cardHeight, 200))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .onAppear {
                        detectAspectRatio()
                    }

                    if moment.hasHiddenLayers,
                       moment.hiddenLayerCount > 0,
                       mediaItems.count == 1,
                       mediaItems.first?.type == .image,
                       currentImageIndex == 0 {
                        HiddenLayersOverlayView(moment: moment, isImmersive: isImmersive)
                            .frame(height: max(cardHeight, 200))
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .zIndex(3)
                    }

                    profileMediaBadges
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)

                    if mediaItems.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<mediaItems.count, id: \.self) { index in
                                Capsule()
                                    .fill(currentImageIndex == index ? .white : .white.opacity(0.4))
                                    .frame(width: currentImageIndex == index ? 24 : 6, height: 4)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentImageIndex)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, aspectRatioType == .reels ? 80 : 18)
                        .opacity(isImmersive ? 0 : 1)
                    }
                }

                ModernActionButtons(
                    moment: moment,
                    isSaved: $isSaved,
                    isSaveLoading: $isSaveLoading,
                    commentCount: $commentCount,
                    onComment: onComment,
                    onSave: toggleSave,
                    onContextMenu: onContextMenu,
                    isImmersive: $isImmersive
                )
                .environmentObject(firestoreService)
                .padding(.bottom, 6)
                .opacity(isImmersive ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isImmersive)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, x: 0, y: 12)

            MomentCaptionView(
                moment: moment,
                style: .detail,
                colorScheme: colorScheme,
                onHashtagTap: onHashtagTap
            )
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .onAppear {
            if !hasLoadedInitialData {
                loadMomentData()
                hasLoadedInitialData = true
            }
        }
    }

    @ViewBuilder
    private var profileMediaBadges: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !location.isEmpty {
                Button(action: {
                    onLocationTap?()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .bold))

                        Text(location)
                            .font(.custom("Poppins-SemiBold", size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }

            if let currentMediaItem = activeMediaItem,
               !currentMediaItem.isHiddenByModeration,
               let tags = currentMediaItem.tags,
               !tags.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        showTags.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: showTags ? "person.fill" : "person.crop.circle")
                            .font(.system(size: 11, weight: .bold))

                        Text("\(tags.count)")
                            .font(.custom("Poppins-SemiBold", size: 11))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .overlay(
                        Capsule()
                            .stroke(showTags ? Color.white.opacity(0.75) : Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ✅ CORREGIDO: Detectar aspect ratio con mejor manejo de videos y validaciones
    private func detectAspectRatio() {
        // ✅ PRIMERO: Intentar usar aspect ratio guardado en el momento
        if let savedAspectRatio = moment.aspectRatio {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            
            DispatchQueue.main.async {
                let ratioValue = aspectRatioFromDB.value
                
                // ✅ Guardar ratio REAL para long press reveal
                if ratioValue > 0 && ratioValue.isFinite {
                    self.realAspectRatio = ratioValue
                }
                
                // ✅ REGLA INSTAGRAM: Todo contenido más vertical que 4:5 se cropea
                let displayRatio: CGFloat
                if ratioValue < 0.8 && ratioValue > 0 {
                    displayRatio = 0.8
                } else if ratioValue > 0 && ratioValue.isFinite {
                    displayRatio = ratioValue
                } else {
                    displayRatio = 1.0
                }
                
                self.detectedAspectRatio = displayRatio
                
                // Clasificar el tipo
                if displayRatio < 0.7 { self.aspectRatioType = .reels }
                else if displayRatio < 0.9 { self.aspectRatioType = .portrait }
                else if displayRatio < 1.3 { self.aspectRatioType = .square }
                else { self.aspectRatioType = .landscape }
            }
            return
        }
        
        // ✅ FALLBACK: Si no hay aspect ratio guardado, detectar de la imagen
        guard let firstItem = mediaItems.first, !firstItem.url.isEmpty else {
            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.8 // Fallback a 4:5
                self.aspectRatioType = .portrait
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
                .onFailure { _ in
                    DispatchQueue.main.async {
                        self.detectedAspectRatio = 0.8 // Fallback a 4:5
                        self.aspectRatioType = .portrait
                    }
                }
        } else {
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
    
    // ✅ Cargar datos del momento
    private func loadMomentData() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // Cargar conteo de comentarios
        firestoreService.db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if let _ = error {
                    return
                }
                
                DispatchQueue.main.async {
                    let newCount = snapshot?.documents.count ?? 0
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.commentCount = newCount
                    }
                }
            }
        
        // Verificar si está guardado
        firestoreService.checkIfSaved(userId: currentUserId, momentId: momentId) { result in
            switch result {
            case .success(let saved):
                DispatchQueue.main.async {
                    self.isSaved = saved
                }
            case .failure(_):
                break
            }
        }
    }
    
    // ✅ Toggle save
    private func toggleSave() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        isSaveLoading = true
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isSaved.toggle()
        }
        
        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { error in
            DispatchQueue.main.async {
                self.isSaveLoading = false
                if let _ = error {
                    withAnimation {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
}

// MARK: - ✅ Vista expandible mejorada para detalle
struct DetailExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    
    private let maxLines = 2
    private let maxCharacters = 140

    private var baseTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.86)
    }

    private var hashtagTextColor: Color {
        colorScheme == .dark ? .white : Color(hex: "007AFF")
    }

    private var textShadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.45) : .clear
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MomentHashtagText(
                content: isExpanded ? content : String(content.prefix(maxCharacters)) + (content.count > maxCharacters ? "..." : ""),
                textFont: .custom("Poppins-Regular", size: 15),
                hashtagFont: .custom("Poppins-SemiBold", size: 15),
                baseColor: baseTextColor,
                hashtagColor: hashtagTextColor,
                mentionColor: Color(hex: "007AFF"),
                textAlignment: .leading,
                shadowColor: textShadowColor,
                shadowRadius: colorScheme == .dark ? 3 : 0,
                shadowX: 0,
                shadowY: 2,
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
                        Text(NSLocalizedString(isExpanded ? "feed.seeLess" : "feed.seeMore", comment: "See more/less"))
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(baseTextColor)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(baseTextColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .scaleEffect(isExpanded ? 1.0 : 0.95)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isExpanded)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

// MARK: - ✅ Resto de componentes (mantener igual)
struct ModernDetailBackground: View {
    let scrollOffset: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()
        }
    }
}

struct DetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
