import SwiftUI
import Kingfisher
import FirebaseAuth
import FirebaseFirestore
import AVKit
import Photos

struct ConversationSettingsView: View {
    let conversation: Conversation
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ConversationSettingsViewModel()
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    @State private var liveOtherParticipantUsername: String = ""

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var otherParticipantDisplayName: String {
        let fallback = conversation.otherParticipantUsername ?? "Usuario"
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    var body: some View {
        ZStack {
            Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6")
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    sheetHeader
                    conversationHeader

                    VStack(spacing: 24) {
                        conversationInfoSection
                        sharedMediaSection
                        privacySettingsSection
                        actionsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            viewModel.loadConversationData(conversation: conversation)
            setupOnlineStatusObserver()
            refreshOtherParticipantUsername()
        }
        .onDisappear {
            statusListener?.remove()
        }
        .sheet(isPresented: $viewModel.showAllMedia) {
            AllSharedMediaView(
                sharedMedia: viewModel.sharedMedia,
                currentUserId: viewModel.currentUserId,
                otherParticipantName: otherParticipantDisplayName,
                onSendReply: viewModel.sendReplyToMedia
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $viewModel.showFullScreenMedia) {
            if let selectedMedia = viewModel.selectedMedia {
                FullScreenMediaView(
                    media: selectedMedia,
                    currentUserId: viewModel.currentUserId,
                    otherParticipantName: otherParticipantDisplayName,
                    onClose: {
                        viewModel.showFullScreenMedia = false
                        viewModel.selectedMedia = nil
                    },
                    onSendReply: { text, completion in
                        viewModel.sendReplyToMedia(selectedMedia, text: text, completion: completion)
                    }
                )
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

    private var sheetHeader: some View {
        HStack {
            Button(action: {
                HapticManager.shared.lightImpact()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.clear.liquidGlass(in: Circle(), interactive: true))
            }

            Spacer()

            Text("conversationSettings.title")
                .font(.custom("Poppins-SemiBold", size: 22))
                .foregroundColor(adaptiveColors.primary)

            Spacer()

            Color.clear
                .frame(width: 38, height: 38)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Header
    private var conversationHeader: some View {
        VStack(spacing: 14) {
            if let avatarUrl = conversation.otherParticipantProfileImagePath {
                KFImage(URL(string: avatarUrl))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
            } else {
                Color.clear
                    .frame(width: 92, height: 92)
                    .background(Color.clear.liquidGlass(in: Circle()))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 34))
                            .foregroundColor(adaptiveColors.primary)
                    )
            }

            Text(otherParticipantDisplayName)
                .font(.custom("Poppins-Bold", size: 24))
                .foregroundColor(adaptiveColors.primary)

            if otherUserStatus != .invisible {
                HStack(spacing: 6) {
                    Circle()
                        .fill(otherUserStatus == .online ? Color.green : adaptiveColors.tertiary.opacity(0.7))
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
                .padding(.vertical, 6)
                .background(Color.clear.liquidGlass(in: Capsule()))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func refreshOtherParticipantUsername() {
        let otherUserId = conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty else {
            liveOtherParticipantUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: otherUserId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                self.liveOtherParticipantUsername = fetchedUsername
            }
        }
    }

    // MARK: - Conversation Info Section
    private var conversationInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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

                dividerLine

                ChatInfoRow(
                    icon: "message.fill",
                    title: NSLocalizedString("conversationSettings.messages", comment: "Messages"),
                    value: "\(viewModel.totalMessages)"
                )

                dividerLine

                ChatInfoRow(
                    icon: "photo.fill",
                    title: NSLocalizedString("conversationSettings.sharedPhotos", comment: "Shared photos"),
                    value: "\(viewModel.sharedPhotos)"
                )

                dividerLine

                ChatInfoRow(
                    icon: "video.fill",
                    title: NSLocalizedString("conversationSettings.sharedVideos", comment: "Shared videos"),
                    value: "\(viewModel.sharedVideos)"
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shared Media Section
    private var sharedMediaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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
                            .foregroundColor(adaptiveColors.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.clear.liquidGlass(in: Capsule()))
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
        .padding(.vertical, 4)
    }



    // MARK: - Privacy Settings Section
    private var privacySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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
                .toggleStyle(SwitchToggleStyle(tint: .green))
                .onChange(of: viewModel.notificationsEnabled) { _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleNotifications()
                }

                dividerLine

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
                .toggleStyle(SwitchToggleStyle(tint: .green))
                .onChange(of: viewModel.readReceiptsEnabled) { _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleReadReceipts()
                }

                dividerLine

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
                .toggleStyle(SwitchToggleStyle(tint: .green))
                .onChange(of: viewModel.typingIndicatorEnabled) { _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleTypingIndicator()
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticManager.shared.mediumImpact()
                viewModel.clearConversation()
            }) {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)

                    Text(NSLocalizedString("conversationSettings.clearConversation", comment: "Clear conversation"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.red)

                    Spacer()
                }
                .padding(.vertical, 10)
            }

            Button(action: {
                HapticManager.shared.mediumImpact()
                viewModel.blockUser()
            }) {
                HStack {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)

                    Text(NSLocalizedString("conversationSettings.blockUser", comment: "Block user"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.red)

                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.top, 4)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(adaptiveColors.tertiary.opacity(colorScheme == .dark ? 0.16 : 0.12))
            .frame(height: 0.5)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(adaptiveColors.secondary)

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
    @Published var currentUserId = Auth.auth().currentUser?.uid ?? ""
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
                originalUrl: mediaUrl,
                senderId: message.senderId,
                timestamp: message.timestamp
            )
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    func sendReplyToMedia(_ media: SharedMedia, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard let conversationId = currentConversation?.id,
              !conversationId.isEmpty,
              !currentUserId.isEmpty else {
            completion(.failure(NSError(domain: "ConversationSettingsReply", code: 1)))
            return
        }

        chatService.sendTextMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            content: trimmedText,
            replyTo: media.id
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Privacy Settings Functions
    func toggleNotifications() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }

        let completion: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.notificationAlertMessage = NSLocalizedString("conversationSettings.notificationConfig.error", comment: "")
                } else {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ConversationMuteStateChanged"),
                        object: nil,
                        userInfo: [
                            "conversationId": conversationId,
                            "isMuted": !self.notificationsEnabled
                        ]
                    )

                    if self.notificationsEnabled {
                        self.notificationAlertMessage = NSLocalizedString("conversationSettings.notificationConfig.enabled", comment: "")
                    } else {
                        self.notificationAlertMessage = NSLocalizedString("conversationSettings.notificationConfig.disabled", comment: "")
                    }
                }
                self.showNotificationAlert = true
            }
        }

        if notificationsEnabled {
            chatService.unmuteConversation(conversationId, for: currentUserId, completion: completion)
        } else {
            chatService.muteConversation(conversationId, for: currentUserId, completion: completion)
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
                    }

                    // Procesar ajuste ESPECÍFICO
                    if let convData = convSnapshot?.data() {
                        let mutedByUserIds = convData["mutedByUserIds"] as? [String] ?? []
                        let legacyIsMuted = convData["isMuted"] as? Bool ?? false
                        let legacyMutedBy = convData["mutedBy"] as? String
                        let isMutedForCurrentUser = mutedByUserIds.contains(currentUserId) || (legacyIsMuted && legacyMutedBy == currentUserId)
                        self.notificationsEnabled = !isMutedForCurrentUser

                        if let prefs = convData["readReceiptPreferences"] as? [String: Bool],
                           let chatPreference = prefs[currentUserId] {
                            // Prioridad 1: Ajuste del chat
                            self.readReceiptsEnabled = chatPreference
                        } else {
                            // Prioridad 2: Ajuste global
                            self.readReceiptsEnabled = globalEnabled
                        }
                    } else {
                        self.notificationsEnabled = true
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
    let senderId: String
    let timestamp: Date

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
    let currentUserId: String
    let otherParticipantName: String
    let onSendReply: (SharedMedia, String, @escaping (Result<Void, Error>) -> Void) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedMedia: SharedMedia?

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        dismiss()
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 38, height: 38)
                            .background(Color.clear.liquidGlass(in: Circle(), interactive: true))
                    }

                    Spacer()

                    Text(NSLocalizedString("conversationSettings.sharedMedia", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 22))
                        .foregroundColor(adaptiveColors.primary)

                    Spacer()

                    Color.clear
                        .frame(width: 38, height: 38)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 16)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(sharedMedia, id: \.id) { media in
                            SharedMediaThumbnail(media: media) {
                                HapticManager.shared.lightImpact()
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedMedia = media
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)
                }
            }

            if let selectedMedia {
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                self.selectedMedia = nil
                            }
                        }

                    FullScreenMediaView(
                        media: selectedMedia,
                        currentUserId: currentUserId,
                        otherParticipantName: otherParticipantName,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                self.selectedMedia = nil
                            }
                        },
                        onSendReply: { text, completion in
                            onSendReply(selectedMedia, text, completion)
                        }
                    )
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}

// MARK: - Full Screen Media View
struct FullScreenMediaView: View {
    let media: SharedMedia
    let currentUserId: String
    let otherParticipantName: String
    let onClose: () -> Void
    let onSendReply: (String, @escaping (Result<Void, Error>) -> Void) -> Void
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isReplyFocused: Bool
    @State private var replyText = ""
    @State private var isSendingReply = false
    @State private var showSaveResult = false
    @State private var saveResultMessage = ""

    private var isOwnMedia: Bool {
        media.senderId == currentUserId
    }

    private var authorName: String {
        isOwnMedia ? NSLocalizedString("chat.reply.you", comment: "You") : otherParticipantName
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: media.timestamp, relativeTo: Date())
    }

    private var canSendReply: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingReply
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 22
            let maxCardWidth = max(geometry.size.width - (horizontalInset * 2), 0)
            let maxCardHeight = max(geometry.size.height * 0.82, 0)
            let primaryOverlayColor = colorScheme == .dark ? Color.white : Color.black

            ZStack {
                Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6")
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(primaryOverlayColor)
                                .frame(width: 42, height: 42)
                        }

                        HStack(spacing: 10) {
                            avatarView

                            VStack(alignment: .leading, spacing: 2) {
                                Text(authorName)
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(primaryOverlayColor)

                                Text(relativeTime)
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(primaryOverlayColor.opacity(0.58))
                            }
                        }
                        .padding(.leading, 6)

                        Spacer()

                        Button(action: {
                            saveMedia()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("conversationSettings.mediaSave.action")
                                    .font(.custom("Poppins-SemiBold", size: 17))
                            }
                            .foregroundColor(primaryOverlayColor)
                            .frame(height: 42)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                    Spacer(minLength: 6)

                    Group {
                        if media.type == .image {
                            KFImage(URL(string: media.originalUrl))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: maxCardWidth)
                                .frame(maxHeight: maxCardHeight)
                        } else if let url = URL(string: media.originalUrl) {
                            VideoPlayer(player: AVPlayer(url: url))
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: maxCardWidth)
                                .frame(maxHeight: maxCardHeight)
                        } else {
                            Text("conversationSettings.videoLoadError")
                                .foregroundColor(primaryOverlayColor)
                                .frame(maxWidth: maxCardWidth)
                                .frame(maxHeight: maxCardHeight)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    HStack(spacing: 12) {
                        TextField(NSLocalizedString("conversationSettings.replyPlaceholder", comment: "Reply placeholder"), text: $replyText)
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(primaryOverlayColor)
                            .focused($isReplyFocused)
                            .submitLabel(.send)
                            .onSubmit {
                                sendReply()
                            }

                        Button(action: sendReply) {
                            if isSendingReply {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(primaryOverlayColor)
                                    .frame(width: 30, height: 30)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(canSendReply ? primaryOverlayColor : primaryOverlayColor.opacity(0.32))
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .disabled(!canSendReply)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(isPresented: $showSaveResult) {
            Alert(
                title: Text("conversationSettings.mediaSave.title"),
                message: Text(saveResultMessage),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if !media.senderId.isEmpty {
            StoryRingAvatarView(
                userId: media.senderId,
                size: 42,
                lineWidth: 2.1,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12),
                baseStrokeWidth: 1
            )
        } else {
            Circle()
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.1))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
                )
        }
    }

    private func sendReply() {
        let trimmedText = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSendingReply else { return }

        isSendingReply = true
        onSendReply(trimmedText) { result in
            isSendingReply = false
            switch result {
            case .success:
                replyText = ""
                isReplyFocused = false
                HapticManager.shared.notification(.success)
            case .failure:
                saveResultMessage = NSLocalizedString("conversationSettings.replySend.error", comment: "")
                showSaveResult = true
            }
        }
    }

    private func saveMedia() {
        guard let url = URL(string: media.originalUrl) else {
            saveResultMessage = NSLocalizedString("conversationSettings.mediaSave.error", comment: "")
            showSaveResult = true
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                switch media.type {
                case .image:
                    guard let image = UIImage(data: data) else {
                        throw NSError(domain: "ConversationSettingsMedia", code: 1)
                    }
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                case .video:
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString).mp4")
                    try data.write(to: tempURL)
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                }

                await MainActor.run {
                    saveResultMessage = NSLocalizedString("conversationSettings.mediaSave.success", comment: "")
                    showSaveResult = true
                }
            } catch {
                await MainActor.run {
                    saveResultMessage = NSLocalizedString("conversationSettings.mediaSave.error", comment: "")
                    showSaveResult = true
                }
            }
        }
    }
}
