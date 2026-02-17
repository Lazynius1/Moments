import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation

// MARK: - ✅ Vista detallada para momentos de ubicación con diseño moderno
struct LocationMomentDetailView: View {
    let locationMoments: [Moment]
    let initialIndex: Int
    let locationName: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject private var firestoreService = FirestoreService()
    @State private var currentIndex: Int
    @State private var showingComments = false
    @State private var selectedMoment: Moment?
    @State private var scrollOffset: CGFloat = 0
    
    // ✅ NUEVOS: Estados para drag transition
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var backgroundOpacity: Double = 1.0
    
    // ✅ Estados para interacciones
    @State private var commentCounts: [String: Int] = [:]
    @State private var savedStates: [String: Bool] = [:]
    @State private var loadingStates: [String: Bool] = [:]
    
    // ✅ NUEVOS: Estados para menú contextual
    @State private var showContextMenu = false
    @State private var contextMenuMoment: Moment?
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    init(locationMoments: [Moment], initialIndex: Int, locationName: String, isPresented: Binding<Bool>) {
        self.locationMoments = locationMoments
        self.initialIndex = initialIndex
        self.locationName = locationName
        self._isPresented = isPresented
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        print(".")
        return GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            
            ZStack(alignment: .top) {
                // ✅ Fondo moderno como el feed
                modernBackgroundView
                    .ignoresSafeArea(.all)
                    .opacity(backgroundOpacity)
                
                // ✅ Header fijo premium (estilo Feed) - Ahora ignorando safe area para posicionamiento absoluto
                locationDetailHeader(safeAreaTop: safeAreaTop)
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                colorScheme == .light ? 
                                Color.white.opacity(0.15) : 
                                Color.black.opacity(0.4)
                            )
                            .ignoresSafeArea(edges: .top)
                    )
                    .ignoresSafeArea(edges: .top) // ✅ CLAVE: Ignorar safe area para subirlo al máximo
                    .zIndex(10)
                    .overlay(
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 0.5)
                        }
                    )
                    .zIndex(10)
                    .offset(x: dragOffset * 0.3)
                    .opacity(backgroundOpacity)
                
                locationMomentsCarousel(geometry: geometry)
                    .padding(.top, locationMoments.count > 1 ? 95 : 80) // Vuelto a un valor seguro pero optimizado
                    .offset(x: dragOffset)
                    .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                
                // ✅ NUEVO: Overlay del menú contextual
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
                            showReportSheet = true
                        },
                        onCopyLink: {
                            if let momentId = moment.id {
                                UIPasteboard.general.string = "https://moments.app/moment/\(momentId)"
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
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
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
        .alert(NSLocalizedString("locationMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("locationMomentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("locationMomentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
            Text("locationMomentDetail.delete.message")
        }
        .sheet(isPresented: $showReportSheet) {
            if let moment = contextMenuMoment {
                ReportBottomSheet(moment: moment)
            }
        }
        .onAppear {
            currentIndex = initialIndex
            loadAllMomentsData()
        }
        .gesture(
            // ✅ Drag gesture suave como MomentDetailView
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if value.translation.width > 0 {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = value.translation.width
                            isDragging = true
                            let progress = min(value.translation.width / 200, 1.0)
                            backgroundOpacity = 1.0 - (progress * 0.4)
                        }
                    }
                }
                .onEnded { value in
                    let dismissThreshold: CGFloat = 120
                    let velocity = value.predictedEndTranslation.width
                    
                    if value.translation.width > dismissThreshold || velocity > 300 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            dragOffset = UIScreen.main.bounds.width
                            backgroundOpacity = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            dragOffset = 0
                            isDragging = false
                            backgroundOpacity = 1.0
                        }
                    }
                }
        )
    }
    
    // ✅ Fondo moderno como el feed
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
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
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.02)
        }
    }
    
    // ✅ Header centrado rediseñado (Estilo ZStack para equilibrio perfecto)
    private func locationDetailHeader(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                // 1. Botón Atrás (Alineado a la izquierda)
                HStack {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold)) // Un poco más refinado
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    Spacer()
                }
                
                // 2. Información de Ubicación (Perfectamente Centrada)
                HStack(spacing: 10) {
                    // Icono de ubicación con diseño Glow
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 38, height: 38) // Ligeramente más compacto
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "007AFF").opacity(0.6), Color(hex: "007AFF").opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 1) { // Alineación leading para el texto, pero el bloque está centrado
                        Text(locationName)
                            .font(.custom("Poppins-SemiBold", size: 17)) // Tamaño ajustado
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Text("\(currentIndex + 1) de \(locationMoments.count)")
                                .font(.custom("Poppins-Medium", size: 11))
                                .foregroundColor(.gray.opacity(0.9))
                            
                            if !locationMoments.isEmpty {
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text(String(format: NSLocalizedString("locationMomentDetail.photoCount", comment: "Photo count"), locationMoments.count))
                                    .font(.custom("Poppins-Regular", size: 11))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.horizontal, 40) // Evitar solapamiento con el botón de atrás
            }
            .padding(.horizontal, 16)
            .padding(.top, safeAreaTop > 0 ? safeAreaTop + 6 : 10) // Bajado para quedar justo debajo del notch (ajuste fino)
            .padding(.bottom, 8) // Espacio interno equilibrado
            
            // ✅ Indicador de progreso integrado
            if locationMoments.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<locationMoments.count, id: \.self) { index in
                        Capsule()
                            .fill(
                                currentIndex == index ?
                                LinearGradient(
                                    colors: [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2.5) // Más sutil
                            .frame(maxWidth: .infinity)
                            .animation(.easeInOut(duration: 0.3), value: currentIndex)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 0)
            }
        }
    }
    
    // ✅ NUEVOS: Helpers para información contextual
    private func getAudienceIcon(_ audience: String) -> String {
        switch audience {
        case "everyone": return "globe"
        case "connections": return "person.2"
        case "bestFriends": return "heart"
        case "custom", "customList": return "person.3"
        default: return "globe"
        }
    }
    
    private func getAudienceColor(_ audience: String) -> Color {
        switch audience {
        case "everyone": return .green
        case "connections": return .blue
        case "bestFriends": return .pink
        case "custom", "customList": return .orange
        default: return Color(hex: "007AFF")
        }
    }
    
    private func getAudienceText(_ audience: String) -> String {
        switch audience {
        case "everyone": return "Público"
        case "connections": return "Conexiones"
        case "bestFriends": return "Mejores amigos"
        case "custom", "customList": return "Personalizado"
        default: return "Público"
        }
    }
    
    
    // ✅ NUEVOS: Funciones auxiliares para menú contextual
    private func updateMoment(newContent: String) {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        let firestoreService = FirestoreService()
        firestoreService.updateMoment(
            userId: moment.authorId,
            momentId: momentId,
            content: newContent
        ) { error in
            if let error = error {
            } else {
                // ✅ Actualizar el momento en el array local
                if let index = locationMoments.firstIndex(where: { $0.id == moment.id }) {
                    // TODO: Actualizar el array de momentos si es necesario
                }
            }
        }
    }
    
    private func deleteMoment() {
        guard let moment = contextMenuMoment,
              let momentId = moment.id else { return }
        
        isDeleting = true
        let firestoreService = FirestoreService()
        
        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                self.isDeleting = false
                
                if let error = error {
                } else {
                    // ✅ Cerrar la vista si se elimina el momento actual
                    if let index = locationMoments.firstIndex(where: { $0.id == moment.id }) {
                        if index == currentIndex {
                            // Si es el momento actual, cerrar la vista
                            withAnimation(.easeOut(duration: 0.3)) {
                                isPresented = false
                            }
                        } else {
                            // Si no es el actual, solo remover del array
                            // TODO: Actualizar el array de momentos si es necesario
                        }
                    }
                }
            }
        }
    }
    
    private func locationMomentsCarousel(geometry: GeometryProxy) -> some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(locationMoments.enumerated()), id: \.offset) { index, moment in
                LocationMomentCard(
                    moment: moment,
                    availableHeight: geometry.size.height - 160,
                    colorScheme: colorScheme,
                    commentCount: commentCounts[moment.id ?? ""] ?? 0,
                    isSaved: savedStates[moment.id ?? ""] ?? false,
                    isSaveLoading: loadingStates[moment.id ?? ""] ?? false,
                    onComment: {
                        selectedMoment = moment
                        showingComments = true
                    },
                    onSave: {
                        toggleSave(for: moment)
                    },
                    onContextMenu: {
                        contextMenuMoment = moment
                        showContextMenu = true
                    }
                )
                .tag(index)
                .environmentObject(firestoreService)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: currentIndex) { newIndex in
        }
    }
    
    private func loadAllMomentsData() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        for moment in locationMoments {
            guard let momentId = moment.id else { continue }
            
            loadCommentCount(for: moment)
            
            firestoreService.checkIfSaved(userId: currentUserId, momentId: momentId) { result in
                switch result {
                case .success(let saved):
                    DispatchQueue.main.async {
                        self.savedStates[momentId] = saved
                    }
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func loadCommentCount(for moment: Moment) {
        guard let momentId = moment.id else { return }
        
        firestoreService.db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if let error = error {
                    return
                }
                
                DispatchQueue.main.async {
                    let count = snapshot?.documents.count ?? 0
                    self.commentCounts[momentId] = count
                }
            }
    }
    
    private func toggleSave(for moment: Moment) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        loadingStates[momentId] = true
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            savedStates[momentId] = !(savedStates[momentId] ?? false)
        }
        
        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { error in
            DispatchQueue.main.async {
                self.loadingStates[momentId] = false
                if let error = error {
                    withAnimation {
                        self.savedStates[momentId] = !(self.savedStates[momentId] ?? false)
                    }
                }
            }
        }
    }
}

// MARK: - ✅ Tarjeta de momento de ubicación REFACTORIZADA
struct LocationMomentCard: View {
    let moment: Moment
    let availableHeight: CGFloat
    let colorScheme: ColorScheme
    let commentCount: Int
    let isSaved: Bool
    let isSaveLoading: Bool
    let onComment: () -> Void
    let onSave: () -> Void
    let onContextMenu: () -> Void
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var showTags: Bool = false // ✅ NUEVO: Control de etiquetas
    @State private var isImmersive: Bool = false // ✅ NUEVO: Soporte para modo inmersivo
    @State private var aspectRatioType: AspectRatioType = .square
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    enum AspectRatioType {
        case square, portrait, landscape, reels
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 450
            case .portrait: return 550
            case .landscape: return 300
            case .reels: return 1000 // Inmersivo
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
    
    private var cardHeight: CGFloat {
        let maxWidth = UIScreen.main.bounds.width - 32
        
        guard maxWidth > 0 else {
            return 400 // Fallback seguro
        }
        
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
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // ✅ El contenido ahora se agrupa en un "card" visual único
                VStack(spacing: 0) {
                    // ✅ Info del autor al principio de la tarjeta
                    authorContextualPill
                        .padding(.top, 8) // Pequeño espacio desde el header
                        .padding(.bottom, 6)
                    
                    // ✅ Imagen principal con aspect ratio dinámico
                    ZStack(alignment: .bottom) {
                        locationMomentImageView
                        
                        // ✅ Glow Rail (Mismo que en Feed)
                        ModernActionButtons(
                            moment: moment,
                            isSaved: .constant(isSaved),
                            isSaveLoading: .constant(isSaveLoading),
                            commentCount: .constant(commentCount),
                            onComment: onComment,
                            onSave: onSave,
                            onContextMenu: onContextMenu,
                            isImmersive: $isImmersive
                        )
                        .environmentObject(firestoreService)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                
                // ✅ Contenido del momento si no está vacío
                if !moment.content.isEmpty {
                    locationMomentContentText
                }
                
                // ✅ Comentarios inline (como MomentDetailView)
                if !moment.disableComments {
                    locationInlineCommentsSection
                }
                
                // Espacio inferior eliminado
            }
            .padding(.horizontal, 15)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
    
    // ✅ NUEVO: Pill de autor contextual para la tarjeta
    private var authorContextualPill: some View {
        HStack(spacing: 12) {
            AsyncProfileImageView(userId: moment.authorId)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(hex: "007AFF").opacity(0.6), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text("\(moment.username)")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(adaptiveColors.primary)
                    
                    VerifiedBadgeView(userId: moment.authorId, size: 12)
                }
                
                Text(moment.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(adaptiveColors.tertiary)
            }
            
            Spacer()
            
            // Indicador de audiencia
            HStack(spacing: 4) {
                Image(systemName: getAudienceIcon(moment.audience ?? "everyone"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(getAudienceColor(moment.audience ?? "everyone"))
                
                Text(getAudienceText(moment.audience ?? "everyone"))
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(adaptiveColors.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
        .padding(.horizontal, 12)
    } // Cierra authorContextualPill
    
    // Helpers para la pill (reutilizados)
    private func getAudienceIcon(_ audience: String) -> String {
        switch audience {
        case "everyone": return "globe"
        case "connections": return "person.2"
        case "bestFriends": return "heart"
        default: return "globe"
        }
    }
    
    private func getAudienceColor(_ audience: String) -> Color {
        switch audience {
        case "everyone": return .green
        case "connections": return .blue
        case "bestFriends": return .pink
        default: return Color(hex: "007AFF")
        }
    }
    
    private func getAudienceText(_ audience: String) -> String {
        switch audience {
        case "everyone": return "Público"
        case "connections": return "Conexiones"
        case "bestFriends": return "Mejores amigos"
        default: return "Público"
        }
    }
    
    
    // ✅ NUEVO: Computed property para mediaItems (consistente con otras vistas)
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
    
    // ✅ NUEVO: Estado para carrusel
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
    
    // ✅ Imagen principal con aspect ratio dinámico
    private var locationMomentImageView: some View {
        ZStack {
            // ✅ NUEVO: EnhancedCarouselView para múltiples archivos
                EnhancedCarouselView(
                    mediaItems: mediaItems,
                    currentIndex: $currentImageIndex,
                    showTags: $showTags, // ✅ PASAR binding
                    aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                    allMoments: [moment], // Solo el momento actual
                    currentMoment: moment, // El momento actual
                    isImmersive: $isImmersive // ✅ NUEVO
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
                        }
                    }
                }, perform: {})
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.2), radius: 12, x: 0, y: 8)
            .onAppear {
                detectAspectRatio()
            }
            
            // ✅ NUEVO: Indicadores de media múltiple mejorados
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
            
            // ✅ NUEVO: BOTONES DE ETIQUETAS (Nivel superior del card)
            let currentMediaItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : nil
            if let tags = currentMediaItem?.tags, !tags.isEmpty {
                // Esquina superior izquierda
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.spring()) {
                                showTags.toggle()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(showTags ? Color(hex: "007AFF") : Color.black.opacity(0.6))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        Spacer()
                    }
                    Spacer()
                }
                .zIndex(100)

                // Esquina inferior izquierda (encima del caption)
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
                                    .frame(width: 36, height: 36)
                                
                                // Border Gradient Glass
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: showTags ? [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.6)] : [.white.opacity(0.6), .white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 36, height: 36)
                                
                                // Icon tinted if active
                                Image(systemName: showTags ? "person.fill" : "person.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(showTags ? Color(hex: "007AFF") : .white)
                            }
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, moment.content.isEmpty ? 15 : 15) // En este card el diseño es diferente
                        Spacer()
                    }
                }
                .zIndex(110)
            }
        }
    }
    
    // ✅ Texto del contenido (como MomentDetailView)
    private var locationMomentContentText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(moment.content)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                .multilineTextAlignment(.leading)
                .padding(.trailing, isImmersive ? 0 : 140) // ✅ Protección contra el rail
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // ✅ Comentarios inline (como MomentDetailView)
    private var locationInlineCommentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header de comentarios
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "007AFF"))
                
                Text("locationMomentDetail.comments")
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if commentCount > 0 {
                    Text("(\(commentCount))")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                Spacer()
                
                Button(NSLocalizedString("locationMomentDetail.viewAll", comment: "View all")) {
                    onComment()
                }
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(Color(hex: "007AFF"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "007AFF").opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            
            if commentCount == 0 {
                // Estado vacío de comentarios
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "007AFF").opacity(0.3), lineWidth: 1.5)
                            )
                        
                        Image(systemName: "bubble.left")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "007AFF"))
                    }
                    
                    VStack(spacing: 8) {
                        Text("locationMomentDetail.noComments.title")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                        
                        Text("locationMomentDetail.noComments.description")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(NSLocalizedString("locationMomentDetail.comment", comment: "Comment")) {
                        onComment()
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "007AFF"), Color(hex: "007AFF").opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color(hex: "007AFF").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 0) // Eliminado padding inferior
    }
    
    // ✅ NUEVO: Función para detectar aspect ratio
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
                    self.aspectRatioType = .reels
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
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 1, height: 1) // ✅ Frame mínimo para que funcione
        } else if firstItem.type == .video {
            // Para videos, usar el aspect ratio detectado
            if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
                classifyAspectRatio(detectedAspectRatio)
            } else if !firstItem.url.isEmpty {
                // Si no se ha detectado, detectarlo ahora
                detectVideoAspectRatio(from: firstItem.url)
            }
        }
    }
    
    private func detectVideoAspectRatio(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        Task {
            do {
                let asset = AVAsset(url: url)
                let track = try await asset.loadTracks(withMediaType: .video).first
                
                if let track = track {
                    let size = try await track.load(.naturalSize)
                    let videoRatio = size.width / size.height
                    
                    await MainActor.run {
                        if videoRatio > 0 && videoRatio.isFinite {
                            self.detectedAspectRatio = videoRatio
                            self.classifyAspectRatio(videoRatio)
                        }
                    }
                }
            } catch {
                // Usar ratio por defecto
                await MainActor.run {
                    self.detectedAspectRatio = 1.0
                    self.classifyAspectRatio(1.0)
                }
            }
        }
    }
    
    // ✅ Clasificar aspect ratio
    private func classifyAspectRatio(_ ratio: CGFloat) {
        let tolerance: CGFloat = 0.05
        
        if abs(ratio - 1.0) < tolerance {
            self.aspectRatioType = .square
        } else if abs(ratio - 0.8) < tolerance {
            self.aspectRatioType = .portrait
        } else if abs(ratio - 0.5625) < tolerance {
            self.aspectRatioType = .reels
        } else if ratio > 1.4 {
            self.aspectRatioType = .landscape
        } else if ratio < 0.7 {
            self.aspectRatioType = .reels
        } else {
            self.aspectRatioType = .square
        }
    }
}

// MARK: - ✅ Botones de acción REFACTORIZADOS
struct LocationActionButtons: View {
    let moment: Moment  // ✅ CAMBIO AQUÍ
    let commentCount: Int
    let isSaved: Bool
    let isSaveLoading: Bool
    let colorScheme: ColorScheme
    let onComment: () -> Void
    let onSave: () -> Void
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComment) {
                HStack(spacing: 4) {
                    Image(systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: commentCount > 0 ?
                                [Color.blue, Color.purple] :
                                adaptiveColors.buttonGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(adaptiveColors.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: commentCount > 0 ?
                                        [Color.blue.opacity(0.6), Color.purple.opacity(0.6)] :
                                        adaptiveColors.buttonStroke,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .scaleEffect(commentCount > 0 ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: commentCount)
            
            Button(action: onSave) {
                HStack(spacing: 4) {
                    if isSaveLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .tint(adaptiveColors.accent)
                    } else {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: isSaved ?
                                    [Color.yellow, Color.orange] :
                                    adaptiveColors.buttonGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: isSaved ?
                                        [Color.yellow.opacity(0.6), Color.orange.opacity(0.6)] :
                                        adaptiveColors.buttonStroke,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .scaleEffect(isSaved ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSaved)
            .disabled(isSaveLoading)
            
            Spacer()
        }
    }
}

// MARK: - ✅ Contenido expandible (sin cambios - ya está bien)
struct LocationExpandableContentView: View {
    let content: String
    let colorScheme: ColorScheme
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    
    private let maxLines = 2
    private let maxCharacters = 80
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(adaptiveColors.primary)
                .lineLimit(isExpanded ? nil : maxLines)
                .multilineTextAlignment(.leading)
                .shadow(color: adaptiveColors.shadowColor.opacity(0.8), radius: 2, x: 0, y: 1)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
                .background(
                    Text(content)
                        .font(.custom("Poppins-Regular", size: 13))
                        .lineLimit(maxLines)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.onAppear {
                                    DispatchQueue.main.async {
                                        needsExpansion = content.count > maxCharacters
                                    }
                                }
                            }
                        )
                        .hidden()
                )
            
            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Text(isExpanded ? "menos" : "más")
                            .font(.custom("Poppins-SemiBold", size: 11))
                            .foregroundColor(adaptiveColors.primary)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: adaptiveColors.overlayStroke,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 2, x: 0, y: 1)
                }
                .scaleEffect(isExpanded ? 1.0 : 0.96)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isExpanded)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
        .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
    }
}

// MARK: - ✅ MENÚ CONTEXTUAL REFACTORIZADO
struct LocationMomentContextMenu: View {
    let moment: Moment  // ✅ CAMBIO AQUÍ
    let colorScheme: ColorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Menu {
            Button(action: {
                // ✅ USAR moment.location y moment.username
                UIPasteboard.general.string = "Foto de \(moment.username) en \(moment.location ?? "")"
            }) {
                Label("Copiar enlace", systemImage: "link")
            }
            
            Button(action: shareLocationMoment) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            
            if moment.authorId != Auth.auth().currentUser?.uid {
                Divider()
                
                Button(action: {
                    // TODO: Implementar reporte
                }) {
                    Label("Reportar", systemImage: "flag")
                }
                .foregroundColor(.red)
            }
            
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(adaptiveColors.primary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: adaptiveColors.shadowColor, radius: 4, x: 0, y: 2)
        }
        .menuStyle(.borderlessButton)
    }
    
    private func shareLocationMoment() {
        let items: [Any] = [
            "Foto de \(moment.username) en \(moment.location ?? "")",
            moment.imagePath ?? ""  // ✅ USAR moment.imagePath
        ]
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootViewController.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            rootViewController.present(activityVC, animated: true)
        }
    }
}

// MARK: - ✅ Botón seguir (sin cambios - ya está bien)
struct FollowButtonForLocation: View {
    let targetUserId: String
    let colorScheme: ColorScheme
    @State private var isFollowing = false
    @State private var isLoading = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: toggleFollow) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                
                Text(isFollowing ? "Siguiendo" : "Seguir")
                    .font(.custom("Poppins-SemiBold", size: 11))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: isFollowing ?
                            [Color.gray.opacity(0.6), Color.gray.opacity(0.8)] :
                            [adaptiveColors.accent, adaptiveColors.accent.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: adaptiveColors.accent.opacity(0.3), radius: 3, x: 0, y: 1)
        }
        .disabled(isLoading)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLoading)
        .onAppear {
            checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        FirestoreService().isFollowing(currentUserId: currentUserId, targetUserId: targetUserId) { following in
            DispatchQueue.main.async {
                self.isFollowing = following
            }
        }
    }
    
    private func toggleFollow() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        let firestoreService = FirestoreService()
        
        if isFollowing {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = false
                        }
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ✅ Fila de comentario (sin cambios - ya está bien)
struct LocationCommentRow: View {
    let comment: Comment
    let colorScheme: ColorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncProfileImageView(userId: comment.authorId)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Text(comment.username)
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(adaptiveColors.primary)
                        
                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: comment.authorId, size: 10)
                    }
                    
                    Text(comment.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(adaptiveColors.tertiary)
                    
                    Spacer()
                }
                
                Text(comment.content)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(adaptiveColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
        .shadow(color: adaptiveColors.shadowColor, radius: 3, x: 0, y: 1)
    }
    
}
