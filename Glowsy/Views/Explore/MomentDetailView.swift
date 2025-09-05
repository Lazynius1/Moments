import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation

struct MomentDetailView: View {
    let moment: Moment
    @StateObject private var viewModel: MomentDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCommentsSheet: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var showShareSheet: Bool = false
    @State private var showContextMenu: Bool = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    
    // ✅ NUEVOS: Estados para drag transition y aspect ratio
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var backgroundOpacity: Double = 1.0
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var aspectRatioType: AspectRatioType = .square
    
    // ✅ NUEVOS: Estados para expansión de contenido
    @State private var isContentExpanded: Bool = false
    @State private var needsContentExpansion: Bool = false
    
    // ✅ NUEVO: Estado para navegación al perfil
    @State private var navigateToProfile: Bool = false

    init(moment: Moment) {
        self.moment = moment
        _viewModel = StateObject(wrappedValue: MomentDetailViewModel(moment: moment))
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            
            ZStack(alignment: .top) {
                // ✅ Fondo moderno como el feed
                modernBackgroundView
                    .ignoresSafeArea(.all)
                    .opacity(backgroundOpacity)
                
                // ✅ Header centrado como ModernMomentDetailView
                modernHeaderSection
                    .padding(.horizontal, 20)
                    .padding(.top, safeAreaTop + 12)
                    .zIndex(10)
                    .offset(x: dragOffset * 0.3)
                    .opacity(backgroundOpacity)
                
                // ✅ Contenido principal con drag
                VStack(spacing: 0) {
                    Spacer().frame(height: safeAreaTop + 80) // Espacio para el header
                    
                    if viewModel.isLoading {
                        MomentLoadingStateView()
                    } else if let errorMessage = viewModel.errorMessage {
                        MomentErrorStateView(message: errorMessage) {
                            dismiss()
                        }
                    } else {
                        contentScrollView
                    }
                }
                .offset(x: dragOffset)
                .scaleEffect(isDragging ? max(0.85, 1 - abs(dragOffset) / 1000) : 1.0)
                
                // ✅ Context menu overlay
                if showContextMenu {
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
        .onAppear {
            setupView()
        }
        .sheet(isPresented: $showingCommentsSheet) {
            ModernCommentsView(moment: moment)
                .environmentObject(FirestoreService())
        }
        .sheet(isPresented: $showEditSheet) {
            EditMomentView(
                moment: moment,
                editedContent: $editedContent,
                onSave: { newContent in
                    updateMoment(newContent: newContent)
                }
            )
        }
       .alert(NSLocalizedString("momentDetail.delete.title", comment: "Delete moment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("momentDetail.delete.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("momentDetail.delete.confirm", comment: "Delete"), role: .destructive) {
                deleteMoment()
            }
        } message: {
           Text("momentDetail.delete.message")
        }
        .sheet(isPresented: $showReportSheet) {
            ReportBottomSheet(moment: moment)
        }
        .overlay(
            Group {
                if showShareSheet {
                    ModernShareBottomSheet(moment: moment, isPresented: $showShareSheet)
                        .zIndex(1000)
                }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardSize = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                keyboardHeight = keyboardSize.cgRectValue.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .gesture(
            // ✅ Drag gesture suave como ModernMomentDetailView
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
                            dismiss()
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
        .sheet(isPresented: $navigateToProfile) {
            UserProfileView(userId: moment.authorId)
        }
    }
    
    // MARK: - Componentes Modernos
    
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
    
    private var modernHeaderSection: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    if !moment.authorId.isEmpty {
                        navigateToProfile = true
                    }
                }) {
                    AsyncProfileImageView(userId: moment.authorId)
                        .frame(width: 45, height: 45)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Button(action: {
                            if !moment.authorId.isEmpty {
                                navigateToProfile = true
                            }
                        }) {
                            Text(moment.username)
                                .font(.custom("Poppins-SemiBold", size: 20))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: moment.authorId, size: 16)
                    }
                    
                    Text(timeAgo(from: moment.timestamp))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray.opacity(0.8))
                }
            }

            Spacer()
            
            // ✅ Botón de menú contextual
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showContextMenu = true
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
    }
    
    private var contentScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // ✅ Contenido del momento con aspect ratio dinámico
                momentContentCard
                
                // ✅ Comentarios inline (mantener para que la vista no se vea vacía)
                if !moment.disableComments {
                    inlineCommentsSection
                }
                
                // Espaciado para el teclado
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: keyboardHeight)
            }
        }
        .coordinateSpace(name: "scroll")
    }
    
    private var momentContentCard: some View {
        VStack(spacing: 0) {
            // ✅ Imagen principal con aspect ratio dinámico
            ZStack(alignment: .bottom) {
                momentImageView
                
                // ✅ Botones de acción estilo feed
                ModernDetailActionButtons(
                    moment: moment,
                    isSaved: $viewModel.isSaved,
                    isSaveLoading: .constant(false),
                    commentCount: .constant(viewModel.comments.count),
                    onComment: { showingCommentsSheet = true },
                    onSave: viewModel.toggleSave
                )
                .environmentObject(FirestoreService())
            }
            
            // ✅ Contenido del momento si no está en la imagen
            if !moment.content.isEmpty {
                momentContentText
            }
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
            Color(hex: "#5b2c6f"), // Azul
            Color(hex: "#40dfcf"), // Turquesa
            Color(hex: "#ff6b6b"), // Rojo coral
            Color(hex: "#4ecdc4"), // Verde azulado
            Color(hex: "#45b7d1"), // Azul claro
            Color(hex: "#96ceb4"), // Verde menta
            Color(hex: "#feca57")  // Amarillo
        ]
        
        return colors[index % colors.count]
    }
    
    private var momentImageView: some View {
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
        }
    }
    
    // ✅ NUEVO: Función para detectar aspect ratio (igual que ModernMomentDetailView)
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
    
    // ✅ Cálculo de altura con aspect ratio dinámico
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
        
        let maxAllowedHeight = min(aspectRatioType.maxHeight, UIScreen.main.bounds.height * 0.6)
        let finalHeight = min(calculatedHeight, maxAllowedHeight)
        let safeHeight = max(finalHeight, 200)
        return safeHeight
    }
    
    private var momentContentText: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(moment.content)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(isContentExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.3), value: isContentExpanded)
                    .onAppear {
                        // Detectar si el contenido necesita expansión
                        needsContentExpansion = moment.content.count > 50 || moment.content.contains("\n")
                    }
                
                // Botón "ver más" solo si el contenido es largo
                if needsContentExpansion {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isContentExpanded.toggle()
                        }
                    }) {
                        Text(isContentExpanded ? "ver menos" : "ver más")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(Color(hex: "00A896"))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
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
    

    
    // MARK: - Comentarios Inline
    
    private var inlineCommentsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header de comentarios mejorado
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "00A896"))
                
                Text("momentDetail.comments")
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if viewModel.comments.count > 0 {
                    Text("(\(viewModel.comments.count))")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
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
                
                Button(NSLocalizedString("momentDetail.viewAll", comment: "View all")) {
                    showingCommentsSheet = true
                }
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            
            if viewModel.comments.isEmpty {
                // Estado vacío de comentarios mejorado
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                        
                        Image(systemName: "bubble.left")
                            .font(.system(size: 24))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    VStack(spacing: 8) {
                        Text("momentDetail.noComments.title")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                        
                        Text("momentDetail.noComments.description")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(NSLocalizedString("momentDetail.comment", comment: "Comment")) {
                        showingCommentsSheet = true
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.white.opacity(0.3), radius: 6, x: 0, y: 3)
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
                                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
            } else {
                // Mostrar primeros comentarios mejorados
                LazyVStack(spacing: 16) {
                    ForEach(Array(viewModel.comments.prefix(3))) { comment in
                        InlineCommentRow(comment: comment)
                    }
                    
                    if viewModel.comments.count > 3 {
                        Button(action: { showingCommentsSheet = true }) {
                            HStack(spacing: 8) {
                                Text(String(format: NSLocalizedString("momentDetail.viewRemainingComments", comment: "View remaining comments"), viewModel.comments.count - 3))
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .foregroundColor(Color(hex: "00A896"))
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "00A896"))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
    }
    
    // MARK: - Aspect Ratio Types (copiado de ModernMomentDetailView)
    
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
    
    // MARK: - Funciones Auxiliares
    
    private func setupView() {
        viewModel.loadAuthorProfile()
        viewModel.fetchComments()
        viewModel.checkIfLiked()
        viewModel.checkIfSaved()
    }
    
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
    
    // ✅ NUEVO: Función para detectar aspect ratio de videos
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

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func updateMoment(newContent: String) {
        guard let momentId = moment.id else { return }
        
        let firestoreService = FirestoreService()
        firestoreService.updateMoment(
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
        guard let momentId = moment.id else { return }
        
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
                    self.dismiss()
                }
            }
        }
    }
}

// MARK: - Función auxiliar para URLs de imágenes (reutilizada)
 func getImageURL(from path: String) -> URL? {
    if path.hasPrefix("https://") {
        return URL(string: path)
    }
    let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
    let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
}

// MARK: - Componentes Auxiliares Reutilizables

struct ExploreModernFollowButton: View {
    let isFollowing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isFollowing ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .semibold))
                
                Text(isFollowing ? "Siguiendo" : "Seguir")
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .foregroundColor(isFollowing ? Color(hex: "00A896") : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isFollowing {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "00A896").opacity(0.4), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
            )
            .shadow(
                color: isFollowing ? .clear : Color(hex: "00A896").opacity(0.4),
                radius: isFollowing ? 0 : 6,
                x: 0,
                y: isFollowing ? 0 : 3
            )
        }
        .disabled(isFollowing)
        .scaleEffect(isFollowing ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
    }
}

struct InlineCommentRow: View {
    let comment: Comment
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar pequeño
            AsyncProfileImageView(userId: comment.authorId)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Username y tiempo
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text(comment.username)
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: comment.authorId, size: 10)
                    }
                    
                    Text("•")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text(timeAgo(from: comment.timestamp))
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                // Contenido del comentario
                Text(comment.content)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                
                // Indicador de likes si los hay
                if let likeCount = comment.reactions["like"]?.count, likeCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                        
                        Text("\(likeCount)")
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Botón de Reacciones Vertical (Expansión hacia arriba)
struct VerticalReactionButton: View {
    let moment: Moment
    @State private var currentReaction: ReactionType?
    @State private var totalReactionCount: Int = 0
    @State private var hasReacted: Bool = false
    @State private var showReactionPicker = false
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Picker de reacciones que aparece ARRIBA del botón
            if showReactionPicker {
                VStack(spacing: 8) {
                    ForEach(ReactionType.allCases.reversed(), id: \.self) { reaction in
                        Button(action: {
                            addReaction(reaction)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showReactionPicker = false
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [reaction.color.opacity(0.6), reaction.color.opacity(0.8)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: reaction.color.opacity(0.3), radius: 4, x: 0, y: 2)
                                
                                Image(systemName: reaction.filledIcon)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [reaction.color, reaction.color.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                        .scaleEffect(showReactionPicker ? 1.0 : 0.1)
                        .opacity(showReactionPicker ? 1.0 : 0.0)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.7)
                            .delay(Double(ReactionType.allCases.reversed().firstIndex(of: reaction) ?? 0) * 0.05),
                            value: showReactionPicker
                        )
                    }
                }
                .padding(.bottom, 12)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
            
            // ✅ Botón principal (siempre visible)
            VStack(spacing: 6) {
                Button(action: {
                    if hasReacted {
                        removeReaction()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showReactionPicker.toggle()
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: hasReacted ?
                                            [currentReaction?.color.opacity(0.6) ?? Color.white.opacity(0.3),
                                             currentReaction?.color.opacity(0.8) ?? Color(hex: "00A896").opacity(0.3)] :
                                            [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: hasReacted ? (currentReaction?.filledIcon ?? "heart.fill") : "heart")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: hasReacted ?
                                    [currentReaction?.color ?? .red, currentReaction?.color.opacity(0.8) ?? .pink] :
                                    [Color.white.opacity(0.8), Color(hex: "00A896")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .scaleEffect(hasReacted ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hasReacted)
                
                // Contador de reacciones
                // ✅ NUEVO: El autor siempre ve el contador, los demás solo si no está oculto
                if totalReactionCount > 0 && (moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts) {
                    Text("\(totalReactionCount)")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                }
            }
        }
        .onAppear {
            loadReactionState()
        }
        .onTapGesture {
            // Cerrar picker si se toca fuera
            if showReactionPicker {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showReactionPicker = false
                }
            }
        }
    }
    
    private func loadReactionState() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Verificar si el usuario ya reaccionó y con qué reacción
        for reactionType in ReactionType.allCases {
            if let userIds = moment.reactions[reactionType.rawValue],
               userIds.contains(currentUserId) {
                hasReacted = true
                currentReaction = reactionType
                break
            }
        }
        
        // Calcular total de reacciones
        totalReactionCount = moment.reactions.values.reduce(0) { total, userIds in
            total + userIds.count
        }
    }
    
    private func addReaction(_ reactionType: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // Actualización optimista
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReacted = true
            currentReaction = reactionType
            totalReactionCount += 1
        }
        
        firestoreService.addReaction(
            to: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                // Revertir si hay error
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = false
                        self.currentReaction = nil
                        self.totalReactionCount -= 1
                    }
                }
            }
        }
    }
    
    private func removeReaction() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        // Actualización optimista
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReacted = false
            currentReaction = nil
            totalReactionCount -= 1
        }
        
        firestoreService.removeReaction(
            from: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                // Revertir si hay error
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = true
                        self.currentReaction = reactionType
                        self.totalReactionCount += 1
                    }
                }
            }
        }
    }
}

struct ProfiileImageView: View {
    let imagePath: String?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let imagePath = imagePath, let url = getImageURL(from: imagePath) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
                            )
                    }
                    .onFailure { error in
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.3))
                            .foregroundColor(.white.opacity(0.6))
                    )
            }
        }
    }
}

// Estados de carga (reutilizar los existentes)
struct MomentLoadingStateView: View {
    @State private var rotationAngle: Double = 0
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 48, height: 48)
                
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotationAngle)
            }
            
            VStack(spacing: 6) {
                Text("momentDetail.loading")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("momentDetail.loadingTime")
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray.opacity(0.8))
            }
        }
        .padding(.top, 80)
        .onAppear { rotationAngle = 360 }
    }
}

struct MomentErrorStateView: View {
    let message: String
    let onClose: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
                    )
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                Text("momentDetail.error.title")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(message)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("momentDetail.close")
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.red.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 80)
    }
}

// MARK: - ViewModel actualizado para incluir reacciones y comentarios modernos
class MomentDetailViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var hasLiked: Bool = false
    @Published var isSaved: Bool = false
    @Published var isFollowing: Bool = false
    @Published var likeCount: Int
    @Published var newComment: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var authorProfile: AppUser?
    @Published var isEditingComment: Bool = false
    @Published var editingCommentContent: String = ""
    @Published var editingCommentId: String?
    @Published var reactionCounts: [String: Int] = [:]
    @Published var userReaction: ReactionType?

    private let moment: Moment
    private let firestoreService = FirestoreService()
    private let currentUserId: String?
    private var reactionListener: ListenerRegistration?

    init(moment: Moment) {
        self.moment = moment
        self.currentUserId = Auth.auth().currentUser?.uid
        self.likeCount = moment.reactions["heart"]?.count ?? 0
        loadAuthorProfile()
        setupReactionListener()
    }
    
    deinit {
        reactionListener?.remove()
    }
    
    // MARK: - Reacciones modernas
    
    private func setupReactionListener() {
        guard let momentId = moment.id else { return }
        
        reactionListener = firestoreService.listenToReactions(
            for: momentId,
            authorId: moment.authorId
        ) { [weak self] reactions in
            DispatchQueue.main.async {
                self?.updateReactionCounts(reactions)
                self?.checkUserReaction(reactions)
            }
        }
    }
    
    private func updateReactionCounts(_ reactions: [String: [String]]) {
        var counts: [String: Int] = [:]
        for (reactionType, userIds) in reactions {
            counts[reactionType] = userIds.count
        }
        self.reactionCounts = counts
    }
    
    private func checkUserReaction(_ reactions: [String: [String]]) {
        guard let currentUserId = currentUserId else { return }
        
        for (reactionType, userIds) in reactions {
            if userIds.contains(currentUserId) {
                self.userReaction = ReactionType(rawValue: reactionType)
                return
            }
        }
        self.userReaction = nil
    }

    func fetchComments() {
        guard let momentId = moment.id else {
            errorMessage = "ID de Moment inválido."
            return
        }

        let momentOwnerId = moment.authorId
        isLoading = true
        
        // ✅ USAR EL NUEVO MÉTODO DE COMENTARIOS CON CALLBACK ACTUALIZADO
        firestoreService.fetchComments(for: momentId, userId: momentOwnerId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let (comments, _)):
                    self?.comments = comments
                case .failure(let error):
                    self?.errorMessage = "Error al cargar comentarios: \(error.localizedDescription)"
                }
            }
        }
    }

    func addComment(content: String) {
        guard let momentId = moment.id, let currentUserId = currentUserId else {
            errorMessage = "No se pudo añadir el comentario."
            return
        }

        let momentOwnerId = moment.authorId
        
        // ✅ USAR EL NUEVO MÉTODO DE COMENTARIOS SIN parentCommentId PARA COMENTARIOS PRINCIPALES
        firestoreService.addComment(
            to: momentId,
            userId: momentOwnerId,
            authorId: currentUserId,
            content: content,
            parentCommentId: nil  // ✅ Sin parent para comentarios principales
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.fetchComments()
                case .failure(let error):
                    self?.errorMessage = "Error al añadir comentario: \(error.localizedDescription)"
                    self?.newComment = content
                }
            }
        }
    }

    func updateComment() {
        guard let momentId = moment.id, let currentUserId = currentUserId, let commentId = editingCommentId else {
            errorMessage = "No se pudo actualizar el comentario."
            return
        }

        let momentOwnerId = moment.authorId
        firestoreService.updateComment(
            momentId: momentId,
            userId: momentOwnerId,
            commentId: commentId,
            content: editingCommentContent
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isEditingComment = false
                    self?.editingCommentId = nil
                    self?.editingCommentContent = ""
                    self?.fetchComments()
                case .failure(let error):
                    self?.errorMessage = "Error al actualizar comentario: \(error.localizedDescription)"
                }
            }
        }
    }

    func deleteComment(comment: Comment) {
        guard let momentId = moment.id, let currentUserId = currentUserId, let commentId = comment.id else {
            errorMessage = "No se pudo eliminar el comentario."
            return
        }

        let momentOwnerId = moment.authorId
        firestoreService.deleteComment(
            to: momentId,
            commentId: commentId,
            userId: momentOwnerId,
            authorId: currentUserId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.fetchComments()
                case .failure(let error):
                    self?.errorMessage = "Error al eliminar comentario: \(error.localizedDescription)"
                }
            }
        }
    }

    func checkIfLiked() {
        guard let currentUserId = currentUserId else { return }
        hasLiked = moment.reactions["heart"]?.contains(currentUserId) ?? false
    }

    func toggleLike() {
        guard let currentUserId = currentUserId, let momentId = moment.id else {
            errorMessage = "No se pudo actualizar la reacción."
            return
        }

        let reactionType = "heart"
        firestoreService.addReaction(to: momentId, reaction: reactionType, userId: currentUserId, authorId: moment.authorId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error al actualizar like: \(error.localizedDescription)"
                } else {
                    self?.hasLiked.toggle()
                    self?.likeCount = self?.hasLiked == true ? (self?.likeCount ?? 0) + 1 : (self?.likeCount ?? 0) - 1
                }
            }
        }
    }

    func checkIfSaved() {
        guard let currentUserId = currentUserId, let momentId = moment.id else { return }
        firestoreService.checkIfSaved(userId: currentUserId, momentId: momentId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let isSaved):
                    self?.isSaved = isSaved
                case .failure(_):
                    break
                }
            }
        }
    }

    func toggleSave() {
        guard let currentUserId = currentUserId, let momentId = moment.id else {
            errorMessage = "No se pudo guardar el Moment."
            return
        }

        firestoreService.toggleSaveMoment(userId: currentUserId, momentId: momentId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error al guardar Moment: \(error.localizedDescription)"
                } else {
                    self?.isSaved.toggle()
                }
            }
        }
    }

    func followUser() {
        guard let currentUserId = currentUserId, let targetUserId = authorProfile?.id else {
            errorMessage = "No se pudo seguir al usuario."
            return
        }

        firestoreService.followUser(currentUserId: currentUserId, targetUserId: targetUserId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                } else {
                    self?.isFollowing = true
                }
            }
        }
    }

    func shareMoment() {
        guard let imagePath = moment.imagePath, let url = getImageURL(from: imagePath) else { return }
        let shareText = "Mira este Moment en Glowsy: \(moment.content)"
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            let activityVC = UIActivityViewController(activityItems: [shareText, url], applicationActivities: nil)
            rootViewController.present(activityVC, animated: true, completion: nil)
        }
    }

    func loadAuthorProfile() {
        firestoreService.fetchUserProfile(userId: moment.authorId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let profile):
                    self?.authorProfile = profile
                    self?.checkIfFollowing()
                case .failure(_):
                    break
                }
            }
        }
    }

    private func checkIfFollowing() {
        guard let currentUserId = currentUserId, let targetUserId = authorProfile?.id else { return }
        firestoreService.fetchConnections(userId: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let connections):
                    self?.isFollowing = connections.contains { $0.userId == targetUserId }
                case .failure(_):
                    break
                }
            }
        }
    }
}

