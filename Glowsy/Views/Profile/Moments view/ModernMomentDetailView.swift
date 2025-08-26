import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation

// MARK: - ✅ Vista detallada de momentos con diseño del feed y aspect ratios
struct ModernMomentDetailView: View {
    let moments: [Moment]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    @StateObject private var firestoreService = FirestoreService()
    @State private var currentIndex: Int
    @State private var showingComments = false
    @State private var selectedMoment: Moment?
    @State private var scrollOffset: CGFloat = 0
    
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
    
    private let privacyService = PrivacyService()
    private let firestoreService2 = FirestoreService()
    
    init(moments: [Moment], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.moments = moments
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            
            ZStack(alignment: .top) {
                // ✅ Fondo que se desvanece durante el drag
                ModernDetailBackground(scrollOffset: scrollOffset)
                    .ignoresSafeArea(.all)
                    .opacity(backgroundOpacity)
                
                // ✅ Header flotante
                ModernDetailHeader(
                    moment: moments[safe: currentIndex],
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .zIndex(10)
                .offset(x: dragOffset * 0.3) // ✅ Se mueve menos que el contenido
                .opacity(backgroundOpacity)
                
                // ✅ Contenido principal con drag
                VStack(spacing: 0) {
                    Spacer().frame(height: safeAreaTop + 17) // ✅ Espacio para el header
                    modernMomentsScrollView(
                        geometry: geometry,
                        safeAreaBottom: safeAreaBottom
                    )
                }
                .offset(x: dragOffset) // ✅ Se mueve con el drag
                .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0) // ✅ Escala durante drag
                
                // ✅ Overlay del menú contextual
                if showContextMenu, let moment = contextMenuMoment {
                    ModernContextMenuOverlay(
                        moment: moment,
                        isPresented: $showContextMenu,
                        showShareSheet: $showShareSheet,
                        onEdit: {
                            editedContent = moment.content
                            showEditSheet = true
                        },
                        onDelete: {
                            showDeleteAlert = true
                        },
                        onShare: {
                            if privacyService.canShareMoment(moment) {
                                showShareSheet = true
                            }
                        },
                        onReport: {
                            showReportSheet = true
                        },
                        onCopyLink: {
                            if let momentId = moment.id {
                                UIPasteboard.general.string = "https://moments.app/moment/\(momentId)"
                            }
                        }
                    )
                    .zIndex(1000)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingComments) {
            if let moment = selectedMoment {
                ModernCommentsView(moment: moment)
                    .environmentObject(firestoreService)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let moment = contextMenuMoment {
                EditMomentView(
                    moment: moment,
                    editedContent: $editedContent,
                    onSave: { newContent in
                        updateMoment(newContent: newContent)
                    }
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let moment = contextMenuMoment {
                ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
            }
        }
        .alert(NSLocalizedString("modernMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("modernMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("modernMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
                            Text("modernMomentDetail.delete.message")
        }
        .sheet(isPresented: $showReportSheet) {
            if let moment = contextMenuMoment {
                ReportBottomSheet(moment: moment)
            }
        }
        .sheet(isPresented: $showExploreWithHashtag) {
            ExploreView(initialSearchQuery: selectedHashtag)
        }
        .onAppear {
            currentIndex = initialIndex
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
    
    // ✅ ScrollView principal MODIFICADO para conectar con el menú contextual
    private func modernMomentsScrollView(geometry: GeometryProxy, safeAreaBottom: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 40) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                        ModernDetailMomentCard(
                            moment: moment,
                            availableHeight: geometry.size.height - 200,
                            onComment: {
                                selectedMoment = moment
                                showingComments = true
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
                            }
                        )
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
    private func updateMoment(newContent: String) {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        firestoreService2.updateMoment(
            userId: moment.authorId,
            momentId: momentId,
            content: newContent
        ) { error in
            if let error = error {
            } else {
            }
        }
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

    var body: some View {
        HStack {
            Spacer()
            
            if let moment = moment {
                HStack(spacing: 12) {
                    AsyncProfileImageView(userId: moment.authorId)
                        .frame(width: 45, height: 45)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.4), Color(hex: "00A896").opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                    
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(moment.username)
                                .font(.custom("Poppins-SemiBold", size: 20))
                                .foregroundColor(.primary)
                            
                            // ✅ INSIGNIA DE VERIFICADO
                            VerifiedBadgeView(userId: moment.authorId, size: 16)
                        }
                        
                        Text(timeAgo(from: moment.timestamp))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}


// MARK: - ✅ Tarjeta de momento detallada con aspect ratios dinámicos CORREGIDA
struct ModernDetailMomentCard: View {
    let moment: Moment
    let availableHeight: CGFloat
    let onComment: () -> Void
    let onContextMenu: () -> Void
    let onHashtagTap: (String) -> Void
    
    @EnvironmentObject private var firestoreService: FirestoreService
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
    @State private var isSaved: Bool = false
    @State private var isSaveLoading: Bool = false
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    
    // ✅ Estado para detectar tipo de aspecto con alturas específicas
    @State private var aspectRatioType: AspectRatioType = .square
    
    enum AspectRatioType {
        case square, portrait, landscape, reels
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 400      // ✅ Para 1:1 (1080x1080)
            case .portrait: return 500    // ✅ Para 4:5 (1080x1350)
            case .landscape: return 280   // ✅ Para 16:9 - más compacto
            case .reels: return 600       // ✅ NUEVO: Para 9:16 (reels/stories) - más alto
            }
        }
        
        // ✅ Aspect ratios exactos basados en las dimensiones reales
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
        // ✅ NUEVO: Usar el campo mediaItems del momento (múltiples archivos)
        if let mediaItems = moment.mediaItems, !mediaItems.isEmpty {
            return mediaItems
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
    
    // ✅ CORREGIDO: Cálculo de altura con validaciones completas
    private var cardHeight: CGFloat {
        let maxWidth = UIScreen.main.bounds.width - 30
        
        // ✅ Validar que maxWidth sea positivo
        guard maxWidth > 0 else {
            return 300 // Fallback seguro
        }
        
        // ✅ Validar aspect ratio detectado
        let aspectRatio: CGFloat
        if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
            aspectRatio = detectedAspectRatio
        } else {
            aspectRatio = aspectRatioType.exactRatio
        }
        
        // ✅ Calcular altura con validación
        let calculatedHeight = maxWidth / aspectRatio
        // ✅ Validar que la altura calculada sea válida
        guard calculatedHeight > 0 && calculatedHeight.isFinite else {
            return aspectRatioType.maxHeight // Usar altura máxima como fallback
        }
        // ✅ Aplicar límites seguros
        let maxAllowedHeight = min(aspectRatioType.maxHeight, max(availableHeight - 80, 200))
        let finalHeight = min(calculatedHeight, maxAllowedHeight)
        // ✅ Validación final - asegurar altura mínima
        let safeHeight = max(finalHeight, 200) // Mínimo 200pt
        return safeHeight
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // ✅ Contenido principal con diseño del feed
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottom) {
                    // ✅ Media content con altura validada (código igual)
                    ZStack {
                        EnhancedCarouselView(
                            mediaItems: mediaItems,
                            currentIndex: $currentImageIndex,
                            aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                            allMoments: [moment], // ✅ AGREGAR: Solo el momento actual
                            currentMoment: moment // ✅ AGREGAR: El momento actual
                        )
                        .frame(height: max(cardHeight, 200))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 10)
                        .onAppear {
                            detectAspectRatio()
                        }
                        
                        // Indicadores de media múltiple mejorados...
                        if mediaItems.count > 1 {
                            VStack {
                                HStack(spacing: 8) {
                                    ForEach(0..<mediaItems.count, id: \.self) { index in
                                        Capsule()
                                            .fill(currentImageIndex == index ? getIndicatorColor(for: index) : Color.white.opacity(0.3))
                                            .frame(width: currentImageIndex == index ? 30 : 10, height: 6)
                                            .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
                                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                    }
                                }
                                .padding(.top, 20)
                                Spacer()
                            }
                        }
                        
                        // Descripción expandible...
                        if !moment.content.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    DetailExpandableContentView(
                                        content: moment.content,
                                        colorScheme: .dark,
                                        onHashtagTap: onHashtagTap
                                    )
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                    
                    // ✅ Botones de acción estilo feed
                    ModernDetailActionButtons(
                        moment: moment,
                        isSaved: $isSaved,
                        isSaveLoading: $isSaveLoading,
                        commentCount: $commentCount,
                        onComment: onComment,
                        onSave: toggleSave
                    )
                    .environmentObject(firestoreService)
                }
                
                // ✅ CORREGIDO: Botón simple que ejecuta el callback
                Button(action: onContextMenu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.4), Color.gray.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .padding(.top, 10)
                .padding(.trailing, 15)
            }
            .padding(.horizontal, 15)
        }
        .onAppear {
            if !hasLoadedInitialData {
                loadMomentData()
                hasLoadedInitialData = true
            }
        }
    }
    
    // ✅ CORREGIDO: Detectar aspect ratio con mejor manejo de videos y validaciones
    private func detectAspectRatio() {
        // ✅ PRIMERO: Intentar usar aspect ratio guardado en el momento
        if let savedAspectRatio = moment.aspectRatio {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            
            DispatchQueue.main.async {
                // ✅ Validar que el valor sea finito y positivo
                let ratioValue = aspectRatioFromDB.value
                if ratioValue > 0 && ratioValue.isFinite {
                    self.detectedAspectRatio = ratioValue
                } else {
                    self.detectedAspectRatio = 1.0 // Fallback a square
                }
                
                // Clasificar el tipo con ratios exactos
                switch aspectRatioFromDB {
                case .landscape:
                    self.aspectRatioType = .landscape
                case .portrait:
                    self.aspectRatioType = .portrait
                case .square:
                    self.aspectRatioType = .square
                case .nineBySixteen:
                    self.aspectRatioType = .reels // ✅ CORREGIDO: Usar reels para 9:16
                }
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
            KFImage(URL(string: firstItem.url))
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
            DispatchQueue.main.async {
                self.detectedAspectRatio = 0.5625 // 9÷16 = 0.5625
                self.aspectRatioType = .reels
            }
            
            if let url = URL(string: firstItem.url) {
                let asset = AVAsset(url: url)
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
                if let error = error {
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
                if let error = error {
                    withAnimation {
                        self.isSaved.toggle()
                    }
                }
            }
        }
    }
}

// MARK: - ✅ Botones de acción para vista detallada
struct ModernDetailActionButtons: View {
    let moment: Moment
    @Binding var isSaved: Bool
    @Binding var isSaveLoading: Bool
    @Binding var commentCount: Int
    let onComment: () -> Void
    let onSave: () -> Void
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            
            VStack(spacing: 14) {
                // ✅ Reaction Button
                EpicReactionButton(moment: moment)
                    .environmentObject(firestoreService)
                
                // ✅ Comment button mejorado
                Button(action: onComment) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: commentCount > 0 ?
                                                [Color.blue.opacity(0.7), Color.purple.opacity(0.7)] :
                                                [Color.white.opacity(0.4), Color(hex: "00A896").opacity(0.4)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                            
                            Image(systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: commentCount > 0 ?
                                        [Color.blue, Color.purple] :
                                        [Color.white.opacity(0.9), Color(hex: "00A896")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        if commentCount > 0 {
                            Text("\(commentCount)")
                                .font(.custom("Poppins-SemiBold", size: 12))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .scaleEffect(commentCount > 0 ? 1.08 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: commentCount)
                
                // ✅ Save button mejorado
                Button(action: onSave) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 54, height: 54)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: isSaved ?
                                            [Color.yellow.opacity(0.7), Color.orange.opacity(0.7)] :
                                            [Color.white.opacity(0.4), Color(hex: "00A896").opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        
                        if isSaveLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.9)
                                .tint(Color(hex: "00A896"))
                        } else {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: isSaved ?
                                        [Color.yellow, Color.orange] :
                                        [Color.white.opacity(0.9), Color(hex: "00A896")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                }
                .scaleEffect(isSaved ? 1.15 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSaved)
                .disabled(isSaveLoading)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
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
    private let maxCharacters = 15
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ✅ MEJORADO: Usar HashtagText personalizado con tap gestures específicos
            if isExpanded {
                DetailHashtagText(
                    content: content,
                    colorScheme: colorScheme,
                    onHashtagTap: onHashtagTap
                )
            } else {
                DetailHashtagText(
                    content: String(content.prefix(maxCharacters)) + (content.count > maxCharacters ? "..." : ""),
                    colorScheme: colorScheme,
                    onHashtagTap: onHashtagTap
                )
            }
            
            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "ver menos" : "ver más")
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(.white)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color(hex: "00A896").opacity(0.5)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                }
                .scaleEffect(isExpanded ? 1.05 : 0.98)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color(hex: "00A896").opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
        .onAppear {
            needsExpansion = content.count > maxCharacters
        }
    }
}

struct DetailHashtagText: View {
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    
    var body: some View {
        // ✅ SOLUCIÓN FINAL: Usar Text con enlaces tappables
        Text(buildAttributedString())
            .font(.custom("Poppins-Regular", size: 15))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
            .environment(\.openURL, OpenURLAction { url in
                // ✅ Manejar taps en hashtags a través de URLs personalizadas
                if url.scheme == "hashtag", let hashtag = url.host {
                    onHashtagTap(hashtag)
                    return .handled
                }
                return .systemAction
            })
    }
    
    // ✅ CLAVE: Construir AttributedString con enlaces en hashtags
    private func buildAttributedString() -> AttributedString {
        var attributed = AttributedString(content)
        
        // Color base para todo el texto
        attributed.foregroundColor = .white.opacity(0.95)
        
        // Buscar y procesar hashtags
        let pattern = "#(\\w+)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = NSString(string: content)
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: content, range: range).reversed() // Reversed para no alterar índices
            
            for match in matches {
                // Obtener el hashtag completo y el término sin #
                let fullHashtag = nsString.substring(with: match.range) // #barcelona
                let hashtagTerm = nsString.substring(with: match.range(at: 1)) // barcelona
                
                // Convertir a rangos de Swift
                if let swiftRange = Range(match.range, in: content),
                   let attributedRange = swiftRange.toAttributedStringRange(in: attributed) {
                    
                    // Aplicar estilo al hashtag
                    attributed[attributedRange].foregroundColor = Color(hex: "667eea")
                    attributed[attributedRange].font = .custom("Poppins-SemiBold", size: 15)
                    attributed[attributedRange].link = URL(string: "hashtag://\(hashtagTerm)")
                }
            }
        }
        
        return attributed
    }
}

// MARK: - ✅ Resto de componentes (mantener igual)
struct ModernDetailBackground: View {
    let scrollOffset: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Mismo fondo que el Feed - negro suave y elegante
                Color(hex: "0A0A0A")
                    .ignoresSafeArea()
            } else {
                // Fondo claro elegante
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white,
                        Color(hex: "f8f9fa"),
                        Color(hex: "e9ecef"),
                        Color.white
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.08 + abs(scrollOffset) * 0.0002)
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
