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
            .sheet(isPresented: $showEditSheet) {
                EditMomentView(
                    moment: moment,
                    editedContent: $editedContent,
                    onSave: { newContent in
                        updateMoment(newContent: newContent)
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
    
    private func updateMoment(newContent: String) {
        guard let momentId = moment.id else { return }
        
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
        
        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { [self] error in
            DispatchQueue.main.async {
                self.isDeleting = false
                
                if let error = error {
                } else {
                    LocalPersistenceService.shared.deleteMoment(momentId: momentId)
                }
            }
        }
    }
}

// MARK: - ✅ Overlay del Menú Contextual Moderno
enum ContextMenuViewState {
    case main
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
                            onEdit: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isPresented = false
                                }
                                onEdit()
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
                            withAnimation(.spring()) {
                                viewState = .sharing
                            }
                        })
                        .transition(.opacity)
                        
                    case .reporting:
                        ModernReportContent(
                            moment: moment,
                            story: nil,
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
                    RoundedRectangle(cornerRadius: 32)
                        .fill(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
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
    }
    
    private func handleBack() {
        switch viewState {
        case .main:
            withAnimation(.easeOut(duration: 0.3)) { isPresented = false }
        case .sharing:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .main }
        case .messaging:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .sharing }
        case .preparingStory:
            withAnimation(.spring()) { viewState = .sharing }
        case .reporting:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewState = .main }
        }
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
        
        // 3. Obtener las imágenes reales de Kingfisher caché
        DispatchQueue.main.async {
            var profileImg: UIImage? = nil
            var contentImg: UIImage? = nil
            
            let group = DispatchGroup()
            
            // Cargar imagen de perfil
            if urls.count > 1 {
                group.enter()
                KingfisherManager.shared.retrieveImage(with: urls[1]) { result in
                    if let image = try? result.get().image {
                        profileImg = image
                    }
                    group.leave()
                }
            }
            
            // Cargar imagen de contenido
            group.enter()
            KingfisherManager.shared.retrieveImage(with: urls[0]) { result in
                if let image = try? result.get().image {
                    contentImg = image
                }
                group.leave()
            }
            
            group.notify(queue: .main) {
                self.performFinalRender(profile: profileImg, content: contentImg)
            }
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
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onReport: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Handle superior
            RoundedRectangle(cornerRadius: 2.5)
                .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)
            
            // ✅ Título con info del usuario
            HStack(spacing: 12) {
                AsyncProfileImageView(userId: moment.authorId)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("Momento • \(formatRelativeTime(moment.timestamp))")
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
                
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            
            // ✅ Acciones principales
            VStack(spacing: 8) {
                // ✅ Acciones del propietario
                if isMyMoment {
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
            .padding(.bottom, 40) // ✅ Más padding para que no esté pegado al borde
            
            // ✅ Botón cancelar
            Button(NSLocalizedString("contextMenu.cancel", comment: "Cancel button")) {
                onCancel()
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 30) // ✅ Safe area bottom + padding extra
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ✅ Botón de acción del menú contextual
struct ContextMenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
    
    private var backgroundColor: Color {
        if isPressed {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
        }
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
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
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor.opacity(0.6))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.4))
                
                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 13))
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
                .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}
