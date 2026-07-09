import SwiftUI
import FirebaseAuth

// MARK: - ✅ Menú Contextual Moderno (Botón de entrada)
import FirebaseFirestore
import Kingfisher
import AVFoundation
import UIKit

private func buildMomentShareLink(_ moment: Moment) -> String {
    guard let momentId = moment.id else {
        return "https://momentsapp.app/moment"
    }
    
    var components = URLComponents(string: "https://momentsapp.app/moment/\(momentId)")
    if !moment.authorId.isEmpty {
        components?.queryItems = [URLQueryItem(name: "a", value: moment.authorId)]
    }
    
    return components?.url?.absoluteString ?? "https://momentsapp.app/moment/\(momentId)"
}

struct ModernMomentContextMenu: View {
    let moment: Moment
    @State private var showActionSheet = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var showReportSheet = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    
    var body: some View {
        ZStack {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showActionSheet = true
                }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.clear
                            .momentsChromeGlass(in: Circle())
                    )
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
            .sheet(isPresented: $showEditSheet) {
                EditMomentView(
                    moment: moment,
                    onSave: { payload in
                        updateMoment(payload: payload)
                    }
                )
            }
            .alert(NSLocalizedString("contextMenu.delete.title", comment: "Delete moment alert title"), isPresented: $showDeleteAlert) {
                Button(NSLocalizedString("contextMenu.delete.cancel", comment: "Cancel button"), role: .cancel) { }
                Button(NSLocalizedString("contextMenu.delete.confirm", comment: "Delete button"), role: .destructive) {
                    deleteMoment()
                }
            } message: {
                Text(NSLocalizedString("contextMenu.delete.message", comment: "Delete moment confirmation message"))
            }
            /*.sheet(isPresented: $showReportSheet) {
                ReportBottomSheet(moment: moment)
            }*/
            
            // ✅ Overlay del menú contextual unificado (con Sharing y Reporte integrado)
            if showActionSheet {
                ModernContextMenuOverlay(
                    moment: moment,
                    isPresented: $showActionSheet,
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
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(1000)
            }
        }
    }
    
    private func updateMoment(payload: EditMomentPayload) {
        guard let momentId = moment.id else { return }
        
        firestoreService.updateMomentDetails(
            userId: moment.authorId,
            momentId: momentId,
            content: payload.content,
            audience: payload.audience.rawValue,
            customListId: payload.customListId,
            customViewers: payload.customViewers,
            taggedUsers: payload.taggedUsers,
            mentionedUsers: payload.mentionedUsers,
            location: payload.locationName.isEmpty ? nil : payload.locationName,
            locationCoordinate: payload.locationCoordinate.map {
                Moment.LocationCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            },
            mediaItems: payload.mediaItems
        ) { _ in }
    }
    
    private func deleteMoment() {
        guard let momentId = moment.id else { return }
        
        isDeleting = true
        
        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { _ in
            DispatchQueue.main.async {
                self.isDeleting = false
                LocalPersistenceService.shared.deleteMoment(momentId: momentId)
            }
        }
    }
}

// MARK: - ✅ Overlay del Menú Contextual Moderno
enum ContextMenuViewState {
    case main
    case hiddenLayerMetrics
    case hiddenLayerMetricDetail
    case sharing
    case messaging
    case preparingStory
    case reporting
}

struct ModernContextMenuOverlay: View {
    let moment: Moment
    @Binding var isPresented: Bool
    
    @State private var viewState: ContextMenuViewState = .main
    
    // ✅ ESTADOS PARA HISTORIA
    @State private var createdSticker: StickerItem?
    @State private var backgroundMedia: [CreatorMedia]? = nil
    @State private var errorMessage: String?
    @State private var showCreatorFullScreen = false // ✅ NUEVO: Control fullScreen
    @State private var hiddenLayerMetrics: HiddenLayerMetricsSnapshot?
    @State private var isLoadingHiddenLayerMetrics = false
    @State private var hiddenLayerMetricsError: String?
    @State private var selectedMetricsLayer: MomentHiddenLayer?
    @State private var selectedLayerDiscoveries: [HiddenLayerDiscovery] = []
    @State private var selectedLayerDiscoveriesCursor: DocumentSnapshot?
    @State private var isLoadingSelectedLayerDiscoveries = false
    @State private var canLoadMoreSelectedLayerDiscoveries = false
    @State private var storyRoute: StoryUserPresentationRoute?

    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    
    private let privacyService = PrivacyService()
    
    private var isMyMoment: Bool {
        moment.authorId == Auth.auth().currentUser?.uid
    }
    
    private var canShare: Bool {
        privacyService.canShareMoment(moment)
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(viewState == .preparingStory ? 0.4 : 0.01)
                .ignoresSafeArea()
                .overlay(
                    Color.black.opacity(viewState == .main || viewState == .sharing ? 0.3 : 0.0)
                )
                .onTapGesture {
                    handleBack()
                }
            
            VStack {
                Spacer()
                
                ZStack {
                    switch viewState {
                    case .main:
                        ModernContextMenuContent(
                            moment: moment,
                            isMyMoment: isMyMoment,
                            canShare: canShare,
                            hiddenLayerMetrics: hiddenLayerMetrics,
                            isLoadingHiddenLayerMetrics: isLoadingHiddenLayerMetrics,
                            hiddenLayerMetricsError: hiddenLayerMetricsError,
                            onEdit: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isPresented = false
                                }
                                onEdit()
                            },
                            onOpenHiddenLayerMetrics: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .hiddenLayerMetrics
                                }
                            },
                            onDelete: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isPresented = false
                                }
                                onDelete()
                            },
                            onShare: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .sharing
                                }
                            },
                            onReport: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .reporting
                                }
                                onReport()
                            },
                            onCancel: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))

                    case .hiddenLayerMetrics:
                        HiddenLayerMetricsListView(
                            metrics: hiddenLayerMetrics,
                            isLoading: isLoadingHiddenLayerMetrics,
                            errorMessage: hiddenLayerMetricsError,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .main
                                }
                            },
                            onSelectLayer: { layer in
                                selectedMetricsLayer = layer
                                resetSelectedLayerDiscoveries()
                                loadSelectedLayerDiscoveries()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .hiddenLayerMetricDetail
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))

                    case .hiddenLayerMetricDetail:
                        HiddenLayerMetricDetailView(
                            layer: selectedMetricsLayer,
                            discoveries: selectedLayerDiscoveries,
                            isLoadingMore: isLoadingSelectedLayerDiscoveries,
                            canLoadMore: canLoadMoreSelectedLayerDiscoveries,
                            onLoadMore: loadSelectedLayerDiscoveries,
                            onAvatarTap: openDiscoveryAvatarTarget,
                            onRowTap: openDiscoveryProfile,
                            totalLayers: hiddenLayerMetrics?.totalLayerCount ?? 0,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .hiddenLayerMetrics
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        
                    case .sharing:
                        MainActionsView(
                            moment: moment,
                            onClose: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            },
                            onSendMessage: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .messaging
                                }
                            },
                            onAddToStory: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .preparingStory
                                    preFetchAndRender()
                                }
                            },
                            onExternalShare: { shareExternally() }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        
                    case .messaging:
                        ModernShareSheet(
                            moment: moment,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .sharing
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        
                    case .preparingStory:
                        PreparingStoryOverlay(errorMessage: errorMessage, onCancel: {
                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                                viewState = .sharing
                            }
                        })
                        .transition(.opacity)

                    case .reporting:
                        ModernReportContent(
                            moment: moment,
                            story: nil,
                            reportedUserId: nil,
                            reportedUsername: nil,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewState = .main
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isPresented = false
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        
                    }
                }
                .background(
                    Color.clear
                        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            loadHiddenLayerMetricsIfNeeded()
        }
        // ✅ FULL SCREEN COVER para el editor de historias (Flujo clásico)
        .fullScreenCover(isPresented: $showCreatorFullScreen, onDismiss: {
            // Al cerrar el editor, cerramos también el menú
            isPresented = false
        }) {
            if let sticker = createdSticker {
                CreatorView(
                    isCreatingStory: .constant(true),
                    showCreatorView: $showCreatorFullScreen,
                    initialSticker: sticker,
                    initialMedia: backgroundMedia,
                    openInStoryMode: false
                )
                .id(sticker.id)
            }
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.userId))
                .environmentObject(FirestoreService.shared)
                .ignoresSafeArea(.keyboard)
        }
    }
    
    private func handleBack() {
        switch viewState {
        case .main:
            withAnimation(.easeOut(duration: 0.3)) { isPresented = false }
        case .hiddenLayerMetrics:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .main }
        case .hiddenLayerMetricDetail:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .hiddenLayerMetrics }
        case .sharing:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .main }
        case .messaging:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .sharing }
        case .preparingStory:
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) { viewState = .sharing }
        case .reporting:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .main }
        }
    }

    private func loadHiddenLayerMetricsIfNeeded() {
        guard isMyMoment, moment.hasHiddenLayers, moment.hiddenLayerCount > 0, let momentId = moment.id else { return }
        guard !isLoadingHiddenLayerMetrics else { return }

        isLoadingHiddenLayerMetrics = true
        hiddenLayerMetricsError = nil

        FirestoreService.shared.fetchHiddenLayerMetrics(
            userId: moment.authorId,
            momentId: momentId
        ) { result in
            DispatchQueue.main.async {
                isLoadingHiddenLayerMetrics = false
                switch result {
                case .success(let metrics):
                    hiddenLayerMetrics = metrics
                case .failure:
                    hiddenLayerMetricsError = NSLocalizedString("hiddenLayers.metrics.error", value: "No se pudieron cargar las métricas.", comment: "Hidden layer metrics error")
                }
            }
        }
    }

    private func resetSelectedLayerDiscoveries() {
        selectedLayerDiscoveries = []
        selectedLayerDiscoveriesCursor = nil
        isLoadingSelectedLayerDiscoveries = false
        canLoadMoreSelectedLayerDiscoveries = false
    }

    private func loadSelectedLayerDiscoveries() {
        guard let layer = selectedMetricsLayer, let momentId = moment.id else { return }
        guard !isLoadingSelectedLayerDiscoveries else { return }

        if selectedLayerDiscoveriesCursor != nil, !canLoadMoreSelectedLayerDiscoveries {
            return
        }

        isLoadingSelectedLayerDiscoveries = true

        FirestoreService.shared.fetchHiddenLayerDiscoveriesPage(
            userId: moment.authorId,
            momentId: momentId,
            layerId: layer.id,
            pageSize: 8,
            startAfter: selectedLayerDiscoveriesCursor
        ) { result in
            DispatchQueue.main.async {
                isLoadingSelectedLayerDiscoveries = false
                switch result {
                case .success(let payload):
                    let (discoveries, lastDocument, hasMore) = payload
                    if selectedLayerDiscoveriesCursor == nil {
                        selectedLayerDiscoveries = discoveries
                    } else {
                        selectedLayerDiscoveries.append(contentsOf: discoveries)
                    }
                    selectedLayerDiscoveriesCursor = lastDocument
                    canLoadMoreSelectedLayerDiscoveries = hasMore && lastDocument != nil
                case .failure:
                    canLoadMoreSelectedLayerDiscoveries = false
                }
            }
        }
    }

    private func openDiscoveryAvatarTarget(userId: String, hasStory: Bool) {
        guard !userId.isEmpty else { return }
        if hasStory {
            storyRoute = StoryUserPresentationRoute(userId: userId)
        } else {
            openDiscoveryProfile(userId: userId)
        }
    }

    private func openDiscoveryProfile(userId: String) {
        guard !userId.isEmpty else { return }
        LegacyNavigationBridge.profile(userId: userId)
    }
    
    // ✅ LÓGICA DE COMPARTIR INTEGRADA (Copiada de share.swift para consistencia)
    private func shareExternally() {
        guard moment.id != nil else { return }
        let freshUsername = UserCacheService.shared.getCachedUser(userId: moment.authorId)?.username ?? moment.username
        let shareText = String(format: NSLocalizedString("share.moment.by", comment: ""), freshUsername)
        let shareUrlString = buildMomentShareLink(moment)
        let shareUrl = URL(string: shareUrlString)!
        
        let activityController = UIActivityViewController(
            activityItems: [shareText, shareUrl],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let presenter = topViewController(from: window.rootViewController) {
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            presenter.present(activityController, animated: true)
        }
        
        withAnimation(.easeOut(duration: 0.3)) { isPresented = false }
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
    
    // ✅ MÉTODOS DE RENDERIZADO INTEGRADOS
    private func preFetchAndRender() {
        guard let imageUrlString = moment.imagePath ?? moment.videoUrl,
              let contentUrl = URL(string: imageUrlString) else {
            errorMessage = "No se pudo obtener la imagen del momento"
            return
        }
        
        // 1. Obtener la ruta de la foto de perfil desde Firestore
        let db = Firestore.firestore()
        db.collection("users").document(moment.authorId).getDocument { snapshot, error in
            if let error = error {
                print("❌ Error fetching profile path: \(error.localizedDescription)")
                // Continuamos aunque falle la de perfil, usará placeholder
                renderSticker(urls: [contentUrl])
                return
            }
            
            var urlsToPrefetch = [contentUrl]
            if let data = snapshot?.data(), let profilePath = data["profileImagePath"] as? String, let profileUrl = URL(string: profilePath) {
                urlsToPrefetch.append(profileUrl)
            }
            
            renderSticker(urls: urlsToPrefetch)
        }
    }
    
    private func renderSticker(urls: [URL]) {
        // 2. Pre-fetch todas las imágenes para tenerlas en caché
        ImagePrefetchManager.shared.prefetch(urls: urls)
        
        // 3. Obtener las imágenes reales de Kingfisher — async/await para evitar mutaciones concurrentes
        Task { @MainActor in
            async let profileImgTask: UIImage? = urls.count > 1
                ? (try? await KingfisherManager.shared.retrieveImage(with: urls[1]).image)
                : nil
            async let contentImgTask: UIImage? = try? await KingfisherManager.shared.retrieveImage(with: urls[0]).image

            let profileImg = await profileImgTask
            let contentImg = await contentImgTask

            self.performFinalRender(profile: profileImg, content: contentImg)
        }
    }
    
    private func performFinalRender(profile: UIImage?, content: UIImage?) {
        // Asumiendo que ShareMomentSticker está disponible globalmente
        let stickerView = ShareMomentSticker(moment: moment, profileImage: profile, contentImage: content, renderClean: true)
            .environment(\.colorScheme, .dark)
            .frame(width: 260)
        
        let renderer = ImageRenderer(content: stickerView)
        renderer.scale = UIScreen.main.scale
        
        if let uiImage = renderer.uiImage {
            let position = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
            
            let interactionData = StickerItem.StickerInteractionData(
                username: moment.username,
                userId: moment.authorId,
                hashtag: nil,
                location: nil,
                locationCoordinate: nil,
                pollData: nil,
                questionText: nil,
                weatherSymbol: nil,
                caption: moment.content.isEmpty ? nil : moment.content,
                profileImagePath: moment.profileImagePath,
                momentId: moment.id,
                mediaCount: moment.mediaItems?.count ?? 1
            )
            
            let sticker = StickerItem(
                image: uiImage,
                position: position,
                type: .shareMoment,
                interactionData: interactionData,
                videoURL: moment.videoUrl != nil ? URL(string: moment.videoUrl!) : nil
            )
            
            self.createdSticker = sticker
            self.backgroundMedia = nil
            
            // Opcional: Ocultar el estado de carga
             withAnimation {
                 self.viewState = .sharing // Volver a sharing
             }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // ✅ Abrir en FullScreenCover (Comportamiento clásico)
                self.showCreatorFullScreen = true
            }
        } else {
            errorMessage = "Error al generar el sticker"
        }
    }
}

// MARK: - ✅ Contenido del Menú Contextual
struct ModernContextMenuContent: View {
    let moment: Moment
    let isMyMoment: Bool
    let canShare: Bool
    let hiddenLayerMetrics: HiddenLayerMetricsSnapshot?
    let isLoadingHiddenLayerMetrics: Bool
    let hiddenLayerMetricsError: String?
    let onEdit: () -> Void
    let onOpenHiddenLayerMetrics: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Título con info del usuario
            HStack(spacing: 12) {
                AsyncProfileImageView(userId: moment.authorId)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("Momento • \(formatRelativeTime(moment.timestamp))")
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
                
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // ✅ Acciones principales
            VStack(spacing: 8) {
                // ✅ Acciones del propietario
                if isMyMoment {
                    if moment.hasHiddenLayers, moment.hiddenLayerCount > 0 {
                        HiddenLayerMetricsSummaryCard(
                            metrics: hiddenLayerMetrics,
                            isLoading: isLoadingHiddenLayerMetrics,
                            errorMessage: hiddenLayerMetricsError,
                            action: onOpenHiddenLayerMetrics
                        )
                    }

                    ContextMenuButton(
                        icon: "pencil",
                        title: NSLocalizedString("contextMenu.editMoment", comment: "Edit moment button"),
                        subtitle: NSLocalizedString("contextMenu.editMoment.subtitle", comment: "Edit moment subtitle"),
                        iconColor: .blue,
                        action: onEdit
                    )
                    
                    ContextMenuButton(
                        icon: "trash",
                        title: NSLocalizedString("contextMenu.deleteMoment", comment: "Delete moment button"),
                        subtitle: NSLocalizedString("contextMenu.deleteMoment.subtitle", comment: "Delete moment subtitle"),
                        iconColor: .red,
                        action: onDelete
                    )
                    
                    Divider()
                        .background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .padding(.vertical, 8)
                }
                
                // ✅ Compartir (solo si audiencia es "everyone")
                if canShare {
                    ContextMenuButton(
                        icon: "paperplane.fill",
                        title: NSLocalizedString("contextMenu.shareMoment", comment: "Share moment button"),
                        subtitle: NSLocalizedString("contextMenu.shareMoment.subtitle", comment: "Share moment subtitle"),
                        iconColor: .green,
                        action: onShare
                    )
                } else {
                    ContextMenuButtonDisabled(
                        icon: "paperplane.fill",
                        title: NSLocalizedString("contextMenu.shareMoment", comment: "Share moment button"),
                        subtitle: NSLocalizedString("contextMenu.shareMoment.disabled", comment: "Share moment disabled subtitle"),
                        iconColor: .gray
                    )
                }
                
                // ✅ Reportar (solo si no es mi momento)
                if !isMyMoment {
                    Divider()
                        .background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .padding(.vertical, 8)
                    
                    ContextMenuButton(
                        icon: "flag",
                        title: NSLocalizedString("contextMenu.reportMoment", comment: "Report moment button"),
                        subtitle: NSLocalizedString("contextMenu.reportMoment.subtitle", comment: "Report moment subtitle"),
                        iconColor: .red,
                        action: onReport
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        MomentsFormat.relativeTime(from: date)
    }
}

private struct HiddenLayerMetricsSummaryCard: View {
    let metrics: HiddenLayerMetricsSnapshot?
    let isLoading: Bool
    let errorMessage: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MomentRowButton(action: action) {
            VStack(spacing: 0) {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08))
                    .padding(.bottom, 10)

                HStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            colorScheme == .dark ? .white : .black,
                            Color.yellow.opacity(colorScheme == .dark ? 0.82 : 0.72)
                        )
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("hiddenLayers.metrics.title", value: "Capas ocultas", comment: "Hidden layers metrics title"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text(summaryText)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    if let leadingChip {
                        Text(leadingChip)
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.72))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.35))
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var summaryText: String {
        if isLoading {
            return NSLocalizedString("hiddenLayers.metrics.loading", value: "Cargando actividad de tus secretos…", comment: "Hidden layers metrics loading")
        }

        if errorMessage != nil {
            return NSLocalizedString("hiddenLayers.metrics.error", value: "No se pudieron cargar las métricas.", comment: "Hidden layers metrics error")
        }

        guard let metrics else {
            return NSLocalizedString("hiddenLayers.metrics.empty.subtitle", value: "Cuando alguien toque una capa, lo verás aquí", comment: "Hidden layers metrics empty subtitle")
        }

        if metrics.totalDiscoveries == 0 {
            return NSLocalizedString("hiddenLayers.metrics.empty.title", value: "Aún nadie ha descubierto tus secretos", comment: "Hidden layers metrics empty title")
        }

        return String(
            format: NSLocalizedString("hiddenLayers.metrics.summary", value: "%1$d descubrimientos en %2$d secretos", comment: "Hidden layers metrics summary"),
            metrics.totalDiscoveries,
            metrics.discoveredLayerCount
        )
    }

    private var chips: [String] {
        guard let metrics, metrics.totalDiscoveries > 0 else { return [] }
        var values: [String] = []

        if let topLayer = metrics.topLayer {
            values.append(
                String(
                    format: NSLocalizedString("hiddenLayers.metrics.chip.top", value: "Más descubierta: %@", comment: "Hidden layers metrics top chip"),
                    topLayer.metricsDisplayName
                )
            )
        }

        if metrics.uniquePeopleCount > 0 {
            values.append(
                String(
                    format: NSLocalizedString("hiddenLayers.metrics.chip.people", value: "%d personas", comment: "Hidden layers metrics people chip"),
                    metrics.uniquePeopleCount
                )
            )
        }

        values.append(
            String(
                format: NSLocalizedString("hiddenLayers.metrics.chip.coverage", value: "Cobertura %.0f%%", comment: "Hidden layers metrics coverage chip"),
                metrics.coverageRatio * 100
            )
        )

        return Array(values.prefix(3))
    }

    private var leadingChip: String? {
        chips.first
    }
}

private struct HiddenLayerMetricsListView: View {
    let metrics: HiddenLayerMetricsSnapshot?
    let isLoading: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onSelectLayer: (MomentHiddenLayer) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ContextSubheaderView(
                title: NSLocalizedString("hiddenLayers.metrics.title", value: "Capas ocultas", comment: "Hidden layers metrics title"),
                onBack: onBack
            )

            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(NSLocalizedString("hiddenLayers.metrics.loading", value: "Cargando actividad de tus secretos…", comment: "Hidden layers metrics loading"))
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.56))
                }
                .padding(.vertical, 32)
            } else if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.56))
                        .padding(.vertical, 32)
            } else if let metrics {
                VStack(alignment: .leading, spacing: 0) {
                    inlineMetricsStrip(metrics: metrics)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                    ForEach(Array(metrics.layers.enumerated()), id: \.element.id) { index, layer in
                        MomentRowButton(action: {
                            onSelectLayer(layer)
                        }) {
                            HiddenLayerMetricsRow(
                                layer: layer,
                                discoveries: metrics.recentDiscoveriesByLayer[layer.id] ?? []
                            )
                        }

                        if index < metrics.layers.count - 1 {
                            Divider()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                .padding(.leading, 68)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineMetricsStrip(metrics: HiddenLayerMetricsSnapshot) -> some View {
        HStack(spacing: 10) {
            inlineMetricText("\(metrics.totalDiscoveries)", NSLocalizedString("hiddenLayers.metrics.card.discoveries", value: "Descubrimientos", comment: ""))
            bullet
            inlineMetricText("\(metrics.uniquePeopleCount)", NSLocalizedString("hiddenLayers.metrics.card.people", value: "Personas", comment: ""))
            bullet
            inlineMetricText("\(Int((metrics.coverageRatio * 100).rounded()))%", NSLocalizedString("hiddenLayers.metrics.card.coverage", value: "Cobertura", comment: ""))
        }
        .font(.system(size: legacyPoppinsSize(12)))
        .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.58))
    }

    private func inlineMetricText(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text(label)
        }
    }

    private var bullet: some View {
        Circle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.16))
            .frame(width: 3, height: 3)
    }
}

private struct HiddenLayerMetricsRow: View {
    let layer: MomentHiddenLayer
    let discoveries: [HiddenLayerDiscovery]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            HiddenLayerMetricLayerPreview(layer: layer, style: .compact)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(layer.metricsDisplayName)
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    if let status = layer.metricsStatusText {
                        Text(status)
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.65))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                    }
                }

                HStack(spacing: 10) {
                    Text(String(format: NSLocalizedString("hiddenLayers.metrics.row.discoveries", value: "%d descubrimientos", comment: ""), layer.discoverCount ?? 0))
                    Text(String(format: NSLocalizedString("hiddenLayers.metrics.row.people", value: "%d personas", comment: ""), layer.uniqueDiscovererCount ?? 0))
                }
                .font(.system(size: legacyPoppinsSize(11)))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.56))

                if let latest = discoveries.first {
                    Text(String(
                        format: NSLocalizedString("hiddenLayers.metrics.row.latest", value: "Última: %@", comment: ""),
                        MomentsFormat.smartDate(from: latest.discoveredAt, context: .mediumDateTime)
                    ))
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.3))
        }
        .padding(.vertical, 12)
    }
}

private struct HiddenLayerMetricDetailView: View {
    let layer: MomentHiddenLayer?
    let discoveries: [HiddenLayerDiscovery]
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let onLoadMore: () -> Void
    let onAvatarTap: (String, Bool) -> Void
    let onRowTap: (String) -> Void
    let totalLayers: Int
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ContextSubheaderView(
                title: layer?.metricsDisplayName ?? NSLocalizedString("hiddenLayers.metrics.detail", value: "Detalle", comment: ""),
                onBack: onBack
            )

            if let layer {
                Group {
                    if shouldUseScrollableDetail {
                        ScrollView(.vertical, showsIndicators: false) {
                            detailContent(layer: layer, scrollable: true)
                        }
                        .padding(.top, 8)
                    } else {
                        detailContent(layer: layer, scrollable: false)
                    }
                }
            }
        }
    }

    private var shouldUseScrollableDetail: Bool {
        canLoadMore || discoveries.count >= 8
    }

    @ViewBuilder
    private func detailContent(layer: MomentHiddenLayer, scrollable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HiddenLayerMetricLayerPreview(layer: layer, style: .detail)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(layer.metricsDisplayName)
                                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)

                                if let status = layer.metricsStatusText {
                                    Text(status)
                                        .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.65))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                                }
                            }

                    HStack(spacing: 10) {
                        inlineStatText("\(layer.discoverCount ?? 0)", NSLocalizedString("hiddenLayers.metrics.card.discoveries", value: "Descubrimientos", comment: ""))
                        inlineDivider
                        inlineStatText("\(layer.uniqueDiscovererCount ?? 0)", NSLocalizedString("hiddenLayers.metrics.card.people", value: "Personas", comment: ""))
                        inlineDivider
                        inlineStatText("\(detailCoveragePercent(for: layer))%", NSLocalizedString("hiddenLayers.metrics.card.coverage", value: "Cobertura", comment: ""))
                    }
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.56))
                }
            }

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))

            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("hiddenLayers.metrics.latestPeople", value: "Últimas personas", comment: "Latest people title"))
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if discoveries.isEmpty {
                    Text(NSLocalizedString("hiddenLayers.metrics.latestPeople.empty", value: "Todavía no hay actividad reciente en esta capa.", comment: "No recent discoveries"))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.56))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(discoveries.enumerated()), id: \.element.id) { index, discovery in
                            HiddenLayerDiscoveryPersonRow(
                                discovery: discovery,
                                onAvatarTap: onAvatarTap,
                                onRowTap: onRowTap
                            )
                            .onAppear {
                                if scrollable, index == discoveries.count - 1, canLoadMore {
                                    onLoadMore()
                                }
                            }

                            if index < discoveries.count - 1 {
                                Divider()
                                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                    .padding(.leading, 44)
                            }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 12)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func inlineStatText(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text(label)
        }
    }

    private var inlineDivider: some View {
        Circle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.16))
            .frame(width: 3, height: 3)
    }

    private func detailCoveragePercent(for layer: MomentHiddenLayer) -> Int {
        guard totalLayers > 0 else { return 0 }
        return Int((Double((layer.discoverCount ?? 0) > 0 ? 1 : 0) / Double(totalLayers) * 100).rounded())
    }
}

private struct HiddenLayerDiscoveryPersonRow: View {
    let discovery: HiddenLayerDiscovery
    let onAvatarTap: (String, Bool) -> Void
    let onRowTap: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MomentRowButton(action: {
            onRowTap(discovery.viewerId)
        }) {
            HStack(spacing: 12) {
                StoryRingAvatarView(
                    userId: discovery.viewerId,
                    size: 32,
                    lineWidth: 2.2,
                    onTap: { hasStory in
                        onAvatarTap(discovery.viewerId, hasStory)
                    }
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(discovery.username ?? "@\(discovery.viewerId.prefix(6))")
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(MomentsFormat.smartDate(from: discovery.discoveredAt, context: .mediumDateTime))
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.5))
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }
}

private struct HiddenLayerMetricLayerPreview: View {
    let layer: MomentHiddenLayer

    enum Style {
        case compact
        case detail
    }

    var style: Style = .compact

    var body: some View {
        ZStack {
            if layer.type == .image {
                RoundedRectangle(cornerRadius: style == .detail ? 12 : 10, style: .continuous)
                    .fill(Color.clear)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: style == .detail ? 12 : 10, style: .continuous))
                    .frame(
                        width: style == .detail ? 28 : 22,
                        height: style == .detail ? 34 : 26
                    )
            } else {
                RoundedRectangle(cornerRadius: style == .detail ? 14 : 12, style: .continuous)
                    .fill(Color.clear)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: style == .detail ? 14 : 12, style: .continuous))
            }

            switch layer.type {
            case .text:
                Text(layer.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? String((layer.text ?? "").prefix(18)) : "Aa")
                    .font(.system(size: style == .detail ? 12 : 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(style == .detail ? 8 : 6)
            case .audio:
                Image(systemName: "waveform")
                    .font(.system(size: style == .detail ? 16 : 15, weight: .semibold))
                    .foregroundColor(.white)
            case .image:
                if let mediaURL = layer.mediaURL, let url = URL(string: mediaURL) {
                    HiddenLayerRemotePolaroidPreview(
                        url: url,
                        caption: layer.caption,
                        captionStyle: layer.textStyle,
                        frameStyle: layer.imageFrameStyle ?? .classic,
                        imageOffset: CGSize(width: layer.imageOffsetX ?? 0, height: layer.imageOffsetY ?? 0),
                        imageScale: layer.imageScale ?? 1,
                        canvasSize: style == .detail ? CGSize(width: 22, height: 29) : CGSize(width: 17, height: 22)
                    )
                    .scaleEffect(style == .detail ? 0.52 : 0.45)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: style == .detail ? 16 : 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

private struct ContextSubheaderView: View {
    let title: String
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: colorScheme == .dark ? .white : .black,
                preset: .navigationBack,
                action: onBack
            )

            Text(title)
                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }
}

private extension MomentHiddenLayer {
    var metricsDisplayName: String {
        switch type {
        case .text:
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? NSLocalizedString("hiddenLayers.metrics.layer.text", value: "Texto oculto", comment: "") : String(trimmed.prefix(24))
        case .audio:
            return NSLocalizedString("hiddenLayers.metrics.layer.audio", value: "Audio oculto", comment: "")
        case .image:
            let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? NSLocalizedString("hiddenLayers.metrics.layer.image", value: "Polaroid", comment: "") : String(trimmed.prefix(24))
        }
    }

    var metricsStatusText: String? {
        if moderationState == .hidden {
            return NSLocalizedString("hiddenLayers.metrics.status.moderated", value: "Moderada", comment: "")
        }
        if moderationState == .pending {
            return NSLocalizedString("hiddenLayers.metrics.status.pending", value: "Pendiente", comment: "")
        }
        if unlockMode == .scheduled, let unlockAt, unlockAt > Date() {
            return String(
                format: NSLocalizedString("hiddenLayers.metrics.status.scheduled", value: "Se abre %@", comment: ""),
                MomentsFormat.smartDate(from: unlockAt, context: .mediumDateTime)
            )
        }
        return nil
    }
}

// MARK: - ✅ Botón de acción del menú contextual
struct ContextMenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        MomentRowButton(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(icon == "flag" ? .red : (colorScheme == .dark ? .white : .black))
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.3))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - ✅ Botón deshabilitado con explicación
struct ContextMenuButtonDisabled: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.45))
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.4))
                
                Text(subtitle)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.3))
            }
            
            Spacer()
            
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.2))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.clear)
        )
    }
}
