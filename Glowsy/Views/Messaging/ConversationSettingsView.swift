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
                // Background
                LinearGradient(
                    gradient: Gradient(colors: adaptiveColors.chatBackground),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        conversationHeader
                        
                        // Settings sections
                        VStack(spacing: 16) {
                            // Conversation Info
                            conversationInfoSection
                            
                            // Shared Media
                            sharedMediaSection
                            
                            // Privacy Settings
                            privacySettingsSection
                            
                            // Actions
                            actionsSection
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Ajustes de conversación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("conversationSettings.close", comment: "Close")) {
                        dismiss()
                    }
                    .foregroundColor(adaptiveColors.primary)
                }
            }
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
        VStack(spacing: 16) {
            // Avatar
            if let avatarUrl = conversation.otherParticipantProfileImagePath {
                KFImage(URL(string: avatarUrl))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(adaptiveColors.primary, lineWidth: 2)
                    )
            } else {
                Circle()
                    .fill(adaptiveColors.primary.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundColor(adaptiveColors.primary)
                    )
            }
            
            // Name
            Text(conversation.otherParticipantUsername ?? "Usuario")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(adaptiveColors.messageTextColor)
            
            // Status (no mostrar si es invisible)
            if otherUserStatus != .invisible {
                HStack(spacing: 8) {
                    Image(systemName: otherUserStatus.icon)
                        .foregroundColor(otherUserStatus.color)
                        .font(.system(size: 12))
                    
                    Text(otherUserStatus.displayName)
                        .font(.subheadline)
                        .foregroundColor(adaptiveColors.timestampColor)
                    
                    if otherUserStatus != .online, let lastSeen = otherUserLastSeen {
                        Text("• \(onlineStatusService.formatLastSeen(lastSeen))")
                            .font(.caption)
                            .foregroundColor(adaptiveColors.timestampColor.opacity(0.7))
                    }
                }
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Conversation Info Section
    private var conversationInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("conversationSettings.conversationInfo")
                .font(.headline)
                .foregroundColor(adaptiveColors.messageTextColor)
            
            VStack(spacing: 8) {
                ChatInfoRow(
                    icon: "calendar",
                    title: "Creada",
                    value: viewModel.conversationCreatedDate
                )
                
                ChatInfoRow(
                    icon: "message",
                    title: "Mensajes",
                    value: "\(viewModel.totalMessages)"
                )
                
                ChatInfoRow(
                    icon: "photo",
                    title: "Fotos compartidas",
                    value: "\(viewModel.sharedPhotos)"
                )
                
                ChatInfoRow(
                    icon: "video",
                    title: "Videos compartidos",
                    value: "\(viewModel.sharedVideos)"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(adaptiveColors.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Shared Media Section
    private var sharedMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
                            Text("conversationSettings.sharedMedia")
                .font(.headline)
                .foregroundColor(adaptiveColors.messageTextColor)
            
            if viewModel.sharedMedia.isEmpty {
                Text("conversationSettings.noSharedMedia")
                    .font(.subheadline)
                    .foregroundColor(adaptiveColors.timestampColor)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(viewModel.sharedMedia.prefix(9), id: \.id) { media in
                        SharedMediaThumbnail(media: media) {
                            viewModel.selectedMedia = media
                            viewModel.showFullScreenMedia = true
                        }
                    }
                }
                
                if viewModel.sharedMedia.count > 9 {
                    Button(String(format: NSLocalizedString("conversationSettings.viewAllMedia", comment: "View all media"), viewModel.sharedMedia.count)) {
                        viewModel.showAllMedia = true
                    }
                    .font(.subheadline)
                    .foregroundColor(adaptiveColors.primary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(adaptiveColors.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    

    
    // MARK: - Privacy Settings Section
    private var privacySettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("conversationSettings.privacy")
                .font(.headline)
                .foregroundColor(adaptiveColors.messageTextColor)
            
            VStack(spacing: 8) {
                Toggle("Notificaciones", isOn: $viewModel.notificationsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: adaptiveColors.primary))
                    .onChange(of: viewModel.notificationsEnabled) { _ in
                        viewModel.toggleNotifications()
                    }
                
                Toggle("Confirmación de lectura", isOn: $viewModel.readReceiptsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: adaptiveColors.primary))
                    .onChange(of: viewModel.readReceiptsEnabled) { _ in
                        viewModel.toggleReadReceipts()
                    }
                
                Toggle("Indicador de escritura", isOn: $viewModel.typingIndicatorEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: adaptiveColors.primary))
                    .onChange(of: viewModel.typingIndicatorEnabled) { _ in
                        viewModel.toggleTypingIndicator()
                    }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(adaptiveColors.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button(action: {
                viewModel.clearConversation()
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                    Text(NSLocalizedString("conversationSettings.clearConversation", comment: "Clear conversation"))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                )
            }
            
            Button(action: {
                viewModel.blockUser()
            }) {
                HStack {
                    Image(systemName: "slash.circle")
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("conversationSettings.blockUser", comment: "Block user"))
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
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
            Image(systemName: icon)
                .foregroundColor(adaptiveColors.primary)
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(adaptiveColors.messageTextColor)
            
            Spacer()
            
            Text(value)
                .foregroundColor(adaptiveColors.timestampColor)
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
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(adaptiveColors.border, lineWidth: 1)
            )
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
    
    private let chatService = ChatService()
    private let firestoreService = FirestoreService()
    private var currentConversation: Conversation?
    
    func loadConversationData(conversation: Conversation) {
        currentConversation = conversation
        loadPrivacySettings()
        guard let conversationId = conversation.id else { return }
        
        // Cargar mensajes para obtener estadísticas
        chatService.listenToMessages(conversationId: conversationId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let messages):
                    self?.processMessages(messages)
                case .failure(let error):
                    print("Error loading conversation data: \(error)")
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
                    print("Error updating notification preference: \(error)")
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
        UserDefaults.standard.set(readReceiptsEnabled, forKey: "chat_read_receipts_enabled")
        print("Read receipts toggled: \(readReceiptsEnabled)")
    }
    
    func toggleTypingIndicator() {
        UserDefaults.standard.set(typingIndicatorEnabled, forKey: "chat_typing_indicator_enabled")
        print("Typing indicator toggled: \(typingIndicatorEnabled)")
    }
    
    private func loadPrivacySettings() {
        // Cargar desde UserDefaults como fallback
        notificationsEnabled = UserDefaults.standard.bool(forKey: "chat_notifications_enabled")
        readReceiptsEnabled = UserDefaults.standard.bool(forKey: "chat_read_receipts_enabled")
        typingIndicatorEnabled = UserDefaults.standard.bool(forKey: "chat_typing_indicator_enabled")
        
        // Cargar preferencias reales desde Firestore
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        firestoreService.fetchUser(userId: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    // Usar preferencias de Firestore si existen
                    if let notificationPrefs = user.notificationPreferences {
                        self?.notificationsEnabled = notificationPrefs["chat_messages"] ?? true
                    }
                    
                    // Si no hay valores guardados, usar valores por defecto
                    if UserDefaults.standard.object(forKey: "chat_notifications_enabled") == nil {
                        self?.notificationsEnabled = true
                    }
                    if UserDefaults.standard.object(forKey: "chat_read_receipts_enabled") == nil {
                        self?.readReceiptsEnabled = true
                    }
                    if UserDefaults.standard.object(forKey: "chat_typing_indicator_enabled") == nil {
                        self?.typingIndicatorEnabled = true
                    }
                    
                case .failure(let error):
                    print("Error loading notification preferences: \(error)")
                    // Mantener valores de UserDefaults como fallback
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
                    print("Error clearing conversation: \(error)")
                } else {
                    print("Conversación eliminada exitosamente")
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
                    print("Error blocking user: \(error)")
                } else {
                    print("Usuario bloqueado exitosamente")
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
                // Background
                LinearGradient(
                    gradient: Gradient(colors: adaptiveColors.chatBackground),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(sharedMedia, id: \.id) { media in
                            SharedMediaThumbnail(media: media) {
                                selectedMedia = media
                                showFullScreenMedia = true
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Contenido compartido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("conversationSettings.close", comment: "Close")) {
                        dismiss()
                    }
                    .foregroundColor(adaptiveColors.primary)
                }
            }
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
