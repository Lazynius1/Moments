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
                
                // ✅ Header centrado como MomentDetailView
                locationDetailHeader
                    .padding(.horizontal, 20)
                    .padding(.top ) // ✅ REDUCIDO: Menos padding superior
                    .zIndex(10)
                    .offset(x: dragOffset * 0.3)
                    .opacity(backgroundOpacity)
                
                // ✅ Contenido principal con drag
                VStack(spacing: 0) {
                    Spacer().frame(height: safeAreaTop + 60) // ✅ REDUCIDO: Menos espacio para el header
                    
                    locationMomentsCarousel(geometry: geometry)
                }
                .offset(x: dragOffset)
                .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                
                // ✅ NUEVO: Overlay del menú contextual
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
                            showShareSheet = true
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
        alert(NSLocalizedString("locationMomentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
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
    
    // ✅ Header centrado como MomentDetailView
    private var locationDetailHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                
                HStack(spacing: 12) {
                    // ✅ Icono de ubicación con gradiente
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 45, height: 45)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "00A896").opacity(0.6), Color(hex: "00A896").opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 2) {
                        Text(locationName)
                            .font(.custom("Poppins-SemiBold", size: 20))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text("\(currentIndex + 1) de \(locationMoments.count)")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(.gray.opacity(0.8))
                            
                            if !locationMoments.isEmpty {
                                Text("•")
                                    .font(.custom("Poppins-Regular", size: 12))
                                    .foregroundColor(.gray.opacity(0.6))
                                
                                Text(String(format: NSLocalizedString("locationMomentDetail.photoCount", comment: "Photo count"), locationMoments.count))
                                    .font(.custom("Poppins-Regular", size: 12))
                                    .foregroundColor(.gray.opacity(0.8))
                            }
                        }
                    }
                }

                Spacer()
                
                            // ✅ Botón de menú contextual
            Button(action: {
                if currentIndex < locationMoments.count {
                    contextMenuMoment = locationMoments[currentIndex]
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showContextMenu = true
                    }
                }
            }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
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
            }
            .padding(.horizontal, 20)
            
            // ✅ NUEVO: Indicador de progreso visual mejorado
            if locationMoments.count > 1 {
                VStack(spacing: 8) {
                    // ✅ Barra de progreso con animación
                    HStack(spacing: 4) {
                        ForEach(0..<locationMoments.count, id: \.self) { index in
                            Capsule()
                                .fill(
                                    currentIndex == index ?
                                    LinearGradient(
                                        colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 3)
                                .frame(maxWidth: .infinity)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // ✅ NUEVO: Información contextual del momento actual
                    if currentIndex < locationMoments.count {
                        let currentMoment = locationMoments[currentIndex]
                        HStack(spacing: 12) {
                            // ✅ Avatar del autor
                            AsyncProfileImageView(userId: currentMoment.authorId)
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color(hex: "00A896").opacity(0.6), lineWidth: 1)
                                )
                            
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Text("@\(currentMoment.username)")
                                        .font(.custom("Poppins-SemiBold", size: 12))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                                    
                                    // ✅ INSIGNIA DE VERIFICADO
                                    VerifiedBadgeView(userId: currentMoment.authorId, size: 10)
                                }
                                
                                Text(timeAgo(from: currentMoment.timestamp))
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            // ✅ NUEVO: Indicador de audiencia
                            HStack(spacing: 4) {
                                Image(systemName: getAudienceIcon(currentMoment.audience ?? "everyone"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(getAudienceColor(currentMoment.audience ?? "everyone"))
                                
                                Text(getAudienceText(currentMoment.audience ?? "everyone"))
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal, 20)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                    }
                }
                .padding(.top, 8)
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
        default: return Color(hex: "00A896")
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
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
                    }
                )
                .tag(index)
                .environmentObject(firestoreService)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
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
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var aspectRatioType: AspectRatioType = .square
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    enum AspectRatioType {
        case square, portrait, landscape, reels
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 400
            case .portrait: return 500
            case .landscape: return 280
            case .reels: return 600
            }
        }
        
        var exactRatio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8
            case .landscape: return 1.78
            case .reels: return 0.5625
            }
        }
    }
    
    private var cardHeight: CGFloat {
        let maxWidth = UIScreen.main.bounds.width - 30
        
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
        guard calculatedHeight > 0 && calculatedHeight.isFinite else {
            return aspectRatioType.maxHeight
        }
        
        let maxAllowedHeight = min(aspectRatioType.maxHeight, availableHeight - 80)
        let finalHeight = min(calculatedHeight, maxAllowedHeight)
        let safeHeight = max(finalHeight, 200)
        return safeHeight
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Imagen principal con aspect ratio dinámico
            ZStack(alignment: .bottom) {
                locationMomentImageView
                
                // ✅ Botones de acción estilo feed
                ModernDetailActionButtons(
                    moment: moment,
                    isSaved: .constant(isSaved),
                    isSaveLoading: .constant(isSaveLoading),
                    commentCount: .constant(commentCount),
                    onComment: onComment,
                    onSave: onSave
                )
                .environmentObject(firestoreService)
            }
            
            // ✅ Contenido del momento si no está vacío
            if !moment.content.isEmpty {
                locationMomentContentText
            }
            
            // ✅ Comentarios inline (como MomentDetailView)
            if !moment.disableComments {
                locationInlineCommentsSection
            }
            
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.top, 20)
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
                aspectRatio: detectedAspectRatio > 0 && detectedAspectRatio.isFinite ? detectedAspectRatio : 1.0,
                allMoments: [moment], // Solo el momento actual
                currentMoment: moment // El momento actual
            )
            .frame(height: cardHeight)
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
        }
    }
    
    // ✅ Texto del contenido (como MomentDetailView)
    private var locationMomentContentText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(moment.content)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                .multilineTextAlignment(.leading)
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
                    .foregroundColor(Color(hex: "00A896"))
                
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
                                colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                Spacer()
                
                Button(NSLocalizedString("locationMomentDetail.viewAll", comment: "View all")) {
                    onComment()
                }
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(Color(hex: "00A896"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "00A896").opacity(0.1))
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
                                    .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1.5)
                            )
                        
                        Image(systemName: "bubble.left")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "00A896"))
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
                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 6, x: 0, y: 3)
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
                                        colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
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
        .padding(.bottom, 40)
    }
    
    // ✅ NUEVO: Función para detectar aspect ratio
    private func detectAspectRatio() {
        // Si ya tenemos mediaItems, detectar del primero
        if let firstItem = mediaItems.first {
            switch firstItem.type {
            case .image:
                // Para imágenes, usar el aspect ratio detectado
                if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
                    classifyAspectRatio(detectedAspectRatio)
                }
            case .video:
                // Para videos, usar el aspect ratio detectado
                if detectedAspectRatio > 0 && detectedAspectRatio.isFinite {
                    classifyAspectRatio(detectedAspectRatio)
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
                    
                    Text(timeAgo(from: comment.timestamp))
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
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
