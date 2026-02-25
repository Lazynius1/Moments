import SwiftUI
import Kingfisher
import FirebaseAuth
import FirebaseFirestore
import AVKit

struct ConversationSettingsView: View {
    let conversation: Conversation
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ConversationSettingsViewModel()
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // background
                LinearGradient(
                    gradient: Gradient(colors: adaptiveColors.chatBackground),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Animated floating gradients (como el feed)
                GeometryReader { _ in
                    Circle()
                        .fill(adaptiveColors.accent.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: -100, y: -100)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: 200, y: 400)
                }
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        conversationHeader
                        
                        // Settings sections
                        VStack(spacing: 20) {
                            // Conversation Info
                            conversationInfoSection
                            
                            // Shared Media
                            sharedMediaSection
                            
                            // Privacy Settings
                            privacySettingsSection
                            
                            // Actions
                            actionsSection
                            
                            Spacer(minLength: 50)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("conversationSettings.title")
                        .font(.custom("Poppins-SemiBold", size: 17))
                        .foregroundColor(adaptiveColors.primary)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            viewModel.loadConversationData(conversation: conversation)
            setupOnlineStatusObserver()
        }
        .onDisappear {
            statusListener?.remove()
        }
        .sheet(isPresented: $viewModel.showAllMedia) {
            AllSharedMediaView(sharedMedia: viewModel.sharedMedia)
        }
        .sheet(isPresented: $viewModel.showFullScreenMedia) {
            if let selectedMedia = viewModel.selectedMedia {
                FullScreenMediaView(media: selectedMedia)
            }
        }
        .alert(NSLocalizedString("conversationSettings.notificationConfig.title", comment: "Notification settings"), isPresented: $viewModel.showNotificationAlert) {
            Button(NSLocalizedString("conversationSettings.understood", comment: "Understood")) {
                viewModel.showNotificationAlert = false
            }
        } message: {
            Text(viewModel.notificationAlertMessage)
        }
    }
    
    // MARK: - Header
    private var conversationHeader: some View {
        ZStack {
            // Fondo difuminado basado en el avatar (efecto inmersivo)
            if let avatarUrl = conversation.otherParticipantProfileImagePath {
                KFImage(URL(string: avatarUrl))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 220)
                    .blur(radius: 40)
                    .opacity(0.3)
                    .clipped()
            }
            
            VStack(spacing: 16) {
                // Avatar con borde premium
                ZStack {
                    if let avatarUrl = conversation.otherParticipantProfileImagePath {
                        KFImage(URL(string: avatarUrl))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(adaptiveColors.primary)
                            )
                    }
                }
                
                VStack(spacing: 6) {
                    // Name
                    Text(conversation.otherParticipantUsername ?? "Usuario")
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(adaptiveColors.primary)
                    
                    // Status (no mostrar si es invisible)
                    if otherUserStatus != .invisible {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(otherUserStatus == .online ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 8, height: 8)
                            
                            Text(otherUserStatus == .online ? NSLocalizedString("online", comment: "") : NSLocalizedString("offline", comment: ""))
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(adaptiveColors.secondary)
                            
                            if otherUserStatus != .online, let lastSeen = otherUserLastSeen {
                                Text("• \(onlineStatusService.formatLastSeen(lastSeen))")
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(adaptiveColors.tertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Conversation Info Section
    private var conversationInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(adaptiveColors.accent)
                Text(NSLocalizedString("conversationSettings.conversationInfo", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(adaptiveColors.primary)
            }
            
            VStack(spacing: 12) {
                ChatInfoRow(
                    icon: "calendar",
                    title: NSLocalizedString("conversationSettings.created", comment: "Created"),
                    value: viewModel.conversationCreatedDate
                )
                
                Divider().background(Color.white.opacity(0.05))
                
                ChatInfoRow(
                    icon: "message.fill",
                    title: NSLocalizedString("conversationSettings.messages", comment: "Messages"),
                    value: "\(viewModel.totalMessages)"
                )
                
                Divider().background(Color.white.opacity(0.05))
                
                ChatInfoRow(
                    icon: "photo.fill",
                    title: NSLocalizedString("conversationSettings.sharedPhotos", comment: "Shared photos"),
                    value: "\(viewModel.sharedPhotos)"
                )
                
                Divider().background(Color.white.opacity(0.05))
                
                ChatInfoRow(
                    icon: "video.fill",
                    title: NSLocalizedString("conversationSettings.sharedVideos", comment: "Shared videos"),
                    value: "\(viewModel.sharedVideos)"
                )
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: adaptiveColors.overlayStroke,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
    
    // MARK: - Shared Media Section
    private var sharedMediaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(adaptiveColors.accent)
                Text(NSLocalizedString("conversationSettings.sharedMedia", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                if !viewModel.sharedMedia.isEmpty {
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        viewModel.showAllMedia = true
                    }) {
                        Text(NSLocalizedString("common.viewAll", comment: "View all"))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(adaptiveColors.accent)
                    }
                }
            }
            
            if viewModel.sharedMedia.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 30))
                            .foregroundColor(adaptiveColors.tertiary)
                        Text(NSLocalizedString("conversationSettings.noSharedMedia", comment: ""))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.sharedMedia.prefix(10), id: \.id) { media in
                            SharedMediaThumbnail(media: media) {
                                HapticManager.shared.lightImpact()
                                viewModel.selectedMedia = media
                                viewModel.showFullScreenMedia = true
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: adaptiveColors.overlayStroke,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
    

    
    // MARK: - Privacy Settings Section
    private var privacySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(adaptiveColors.accent)
                Text(NSLocalizedString("conversationSettings.privacy", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(adaptiveColors.primary)
            }
            
            VStack(spacing: 16) {
                Toggle(isOn: $viewModel.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.notifications", comment: "Notifications"))
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.notifications.desc", comment: "Receive alerts for new messages"))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00A896")))
                .onChange(of: viewModel.notificationsEnabled) { _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleNotifications()
                }
                
                Divider().background(Color.white.opacity(0.05))
                
                Toggle(isOn: $viewModel.readReceiptsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.privacy.readReceipts.title", comment: ""))
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.privacy.readReceipts.description", comment: ""))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: adaptiveColors.accent))
                .onChange(of: viewModel.readReceiptsEnabled) { _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleReadReceipts()
                }
                
                Divider().background(Color.white.opacity(0.05))
                
                Toggle(isOn: $viewModel.typingIndicatorEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.typingIndicator", comment: "Typing indicator"))
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.typingIndicator.desc", comment: "Show when you are typing"))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: adaptiveColors.accent))
                .onChange(of: viewModel.typingIndicatorEnabled) { _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleTypingIndicator()
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: adaptiveColors.overlayStroke,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticManager.shared.mediumImpact()
                viewModel.clearConversation()
            }) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                    
                    Text(NSLocalizedString("conversationSettings.clearConversation", comment: "Clear conversation"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                )
            }
            
            Button(action: {
                HapticManager.shared.mediumImpact()
                viewModel.blockUser()
            }) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "slash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                    }
                    
                    Text(NSLocalizedString("conversationSettings.blockUser", comment: "Block user"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    private func setupOnlineStatusObserver() {
        let otherUserId = conversation.otherParticipantId
        
        statusListener = onlineStatusService.observeUserStatus(userId: otherUserId) { status, lastSeen in
            DispatchQueue.main.async {
                self.otherUserStatus = status
                self.otherUserLastSeen = lastSeen
            }
        }
    }
}

// MARK: - Supporting Views
struct ChatInfoRow: View {
    let icon: String
    let title: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color(hex: "00A896").opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(adaptiveColors.accent)
            }
            
            Text(title)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(adaptiveColors.secondary)
            
            Spacer()
            
            Text(value)
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(adaptiveColors.primary)
        }
    }
}

struct SharedMediaThumbnail: View {
    let media: SharedMedia
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        KFImage(URL(string: media.thumbnailUrl))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .onTapGesture {
                onTap()
            }
    }
}

// MARK: - View Model
class ConversationSettingsViewModel: ObservableObject {
    @Published var conversationCreatedDate = "Desconocida"
    @Published var totalMessages = 0
    @Published var sharedPhotos = 0
    @Published var sharedVideos = 0
    @Published var sharedMedia: [SharedMedia] = []
    @Published var showAllMedia = false
    @Published var selectedMedia: SharedMedia?
    @Published var showFullScreenMedia = false
    
    @Published var notificationsEnabled = true
    @Published var readReceiptsEnabled = true
    @Published var typingIndicatorEnabled = true
    @Published var showNotificationAlert = false
    @Published var notificationAlertMessage = ""
    
    private let chatService = ChatService.shared
    private let firestoreService = FirestoreService()
    private var currentConversation: Conversation?
    private let typingIndicatorLegacyKey = "chat_typing_indicator_enabled"
    
    private func boolFromDefaults(key: String, defaultValue: Bool) -> Bool {
        if let storedValue = UserDefaults.standard.object(forKey: key) as? Bool {
            return storedValue
        }
        return defaultValue
    }
    
    private func typingIndicatorKey(for conversationId: String) -> String {
        "chat_typing_indicator_enabled_\(conversationId)"
    }
    
    func loadConversationData(conversation: Conversation) {
        currentConversation = conversation
        loadPrivacySettings()
        guard let conversationId = conversation.id else { return }
        
        // Cargar mensajes para obtener estadísticas (one-shot para no competir con el listener del chat principal)
        chatService.fetchRecentMessages(conversationId: conversationId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    self?.processMessages(messages)
                case .failure(_):
                    break
                }
            }
        }
        
        // Formatear fecha de creación
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        conversationCreatedDate = formatter.string(from: conversation.timestamp)
    }
    
    private func processMessages(_ messages: [EnhancedMessage]) {
        totalMessages = messages.count
        
        // Filtrar solo contenido multimedia no efímero y no view-once
        let mediaMessages = messages.filter { message in
            (message.type == .image || message.type == .video) && 
            !message.isViewOnce && 
            message.type != .ephemeral &&
            message.storyReplyData == nil &&
            message.mediaUrl != nil
        }
        
        // Contar fotos y videos
        sharedPhotos = mediaMessages.filter { $0.type == .image }.count
        sharedVideos = mediaMessages.filter { $0.type == .video }.count
        
        // Crear array de contenido multimedia compartido
        sharedMedia = mediaMessages.compactMap { message in
            guard let mediaUrl = message.mediaUrl else { return nil }
            
            return SharedMedia(
                id: message.id,
                type: message.type == .image ? .image : .video,
                thumbnailUrl: message.thumbnailUrl ?? mediaUrl,
                originalUrl: mediaUrl
            )
        }
    }
    
    // MARK: - Privacy Settings Functions
    func toggleNotifications() {
        UserDefaults.standard.set(notificationsEnabled, forKey: "chat_notifications_enabled")
        
        // Conectar con el sistema real de notificaciones
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Crear preferencias actualizadas
        var preferences: [String: Bool] = [:]
        preferences["chat_messages"] = notificationsEnabled
        
        firestoreService.updateNotificationPreferences(
            userId: currentUserId,
            preferences: preferences
        ) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.notificationAlertMessage = "❌ Error al actualizar las notificaciones"
                } else {
                    if self.notificationsEnabled {
                        self.notificationAlertMessage = "✅ Las notificaciones están habilitadas. Recibirás alertas cuando lleguen nuevos mensajes."
                    } else {
                        self.notificationAlertMessage = "🔇 Las notificaciones están deshabilitadas. No recibirás alertas de nuevos mensajes en esta conversación."
                    }
                }
                self.showNotificationAlert = true
            }
        }
    }
    
    func toggleReadReceipts() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }
        
        let db = Firestore.firestore()
        let conversationRef = db.collection("conversations").document(conversationId)
        
        // Guardar la preferencia explícita para este chat
        conversationRef.updateData([
            "readReceiptPreferences.\(currentUserId)": readReceiptsEnabled
        ])
        
        UserDefaults.standard.set(readReceiptsEnabled, forKey: "chat_read_receipts_enabled_\(conversationId)")
    }
    
    func toggleTypingIndicator() {
        guard let conversationId = currentConversation?.id else { return }
        
        let perChatKey = typingIndicatorKey(for: conversationId)
        UserDefaults.standard.set(typingIndicatorEnabled, forKey: perChatKey)
    }
    
    private func loadPrivacySettings() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }
        
        // Cargar desde UserDefaults como fallback instantáneo
        notificationsEnabled = boolFromDefaults(key: "chat_notifications_enabled", defaultValue: true)
        readReceiptsEnabled = boolFromDefaults(key: "chat_read_receipts_enabled_\(conversationId)", defaultValue: true)
        
        let typingKey = typingIndicatorKey(for: conversationId)
        if let perChatTyping = UserDefaults.standard.object(forKey: typingKey) as? Bool {
            typingIndicatorEnabled = perChatTyping
        } else {
            typingIndicatorEnabled = boolFromDefaults(key: typingIndicatorLegacyKey, defaultValue: true)
        }
        
        let db = Firestore.firestore()
        
        // 1. Cargar el usuario para el ajuste global
        firestoreService.fetchUser(userId: currentUserId) { [weak self] userResult in
            // 2. Cargar la conversación para el ajuste específico
            db.collection("conversations").document(conversationId).getDocument { [weak self] convSnapshot, convError in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    // Procesar ajuste GLOBAL
                    var globalEnabled = true
                    if case .success(let user) = userResult {
                        globalEnabled = user.showReadReceipts
                        if let notificationPrefs = user.notificationPreferences {
                            self.notificationsEnabled = notificationPrefs["chat_messages"] ?? true
                        }
                    }
                    
                    // Procesar ajuste ESPECÍFICO
                    if let convData = convSnapshot?.data(),
                       let prefs = convData["readReceiptPreferences"] as? [String: Bool],
                       let chatPreference = prefs[currentUserId] {
                        // Prioridad 1: Ajuste del chat
                        self.readReceiptsEnabled = chatPreference
                    } else {
                        // Prioridad 2: Ajuste global
                        self.readReceiptsEnabled = globalEnabled
                    }
                }
            }
        }
    }
    
    func clearConversation() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }
        
        // Obtener el ID del otro participante
        let otherParticipantId = currentConversation?.otherParticipantId ?? ""
        
        // Eliminar conversación usando ChatService
        chatService.deleteConversationsBetweenUsers(user1Id: currentUserId, user2Id: otherParticipantId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                } else {
                    // Aquí podrías cerrar la vista o navegar de vuelta
                }
            }
        }
    }
    
    func blockUser() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }
        
        // Obtener el ID del otro participante
        let otherParticipantId = currentConversation?.otherParticipantId ?? ""
        
        // Bloquear usuario usando FirestoreService
        firestoreService.blockUser(currentUserId: currentUserId, targetUserId: otherParticipantId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                } else {
                    // Aquí podrías cerrar la vista o mostrar una confirmación
                }
            }
        }
    }
}

// MARK: - Models
struct SharedMedia: Identifiable {
    let id: String
    let type: MediaType
    let thumbnailUrl: String
    let originalUrl: String
    
    enum MediaType {
        case image
        case video
    }
} 

// MARK: - Extensión específica para ConversationSettingsView
extension AdaptiveColors {
    var border: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
    }
} 

// MARK: - All Shared Media View
struct AllSharedMediaView: View {
    let sharedMedia: [SharedMedia]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedMedia: SharedMedia?
    @State private var showFullScreenMedia = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // background
                LinearGradient(
                    gradient: Gradient(colors: adaptiveColors.chatBackground),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Animated floating gradients
                GeometryReader { _ in
                    Circle()
                        .fill(adaptiveColors.accent.opacity(0.12))
                        .frame(width: 250, height: 250)
                        .blur(radius: 70)
                        .offset(x: -50, y: 100)
                }
                .ignoresSafeArea()
                
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(sharedMedia, id: \.id) { media in
                            SharedMediaThumbnail(media: media) {
                                HapticManager.shared.lightImpact()
                                selectedMedia = media
                                showFullScreenMedia = true
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(NSLocalizedString("conversationSettings.sharedMedia", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 17))
                        .foregroundColor(adaptiveColors.primary)
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .sheet(isPresented: $showFullScreenMedia) {
            if let selectedMedia = selectedMedia {
                FullScreenMediaView(media: selectedMedia)
            }
        }
    }
}

// MARK: - Full Screen Media View
struct FullScreenMediaView: View {
    let media: SharedMedia
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            // Media content
            VStack {
                Spacer()
                
                if media.type == .image {
                    KFImage(URL(string: media.originalUrl))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    // Video player
                    if let url = URL(string: media.originalUrl) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    } else {
                        Text("conversationSettings.videoLoadError")
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onTapGesture {
            dismiss()
        }
    }
} 
