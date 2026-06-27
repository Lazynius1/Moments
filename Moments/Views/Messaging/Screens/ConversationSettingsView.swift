import SwiftUI
import Kingfisher
import FirebaseAuth
import FirebaseFirestore
import AVKit
import Photos

struct ConversationSettingsView: View {
    let conversation: Conversation
    var onJumpToMessage: ((String) -> Void)? = nil
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
        ScrollView {
            VStack(spacing: 24) {
                conversationHeader

                VStack(spacing: 24) {
                    conversationInfoSection
                    sharedMediaSection
                    starredMessagesSection
                    privacySettingsSection
                    actionsSection
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
        .background {
            Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6")
                .ignoresSafeArea()
        }
        .navigationTitle("conversationSettings.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $viewModel.showAllMedia) {
            sharedMediaGalleryDestination
                .toolbar(.hidden, for: .tabBar)
        }
        .onAppear {
            viewModel.loadConversationData(conversation: conversation)
            setupOnlineStatusObserver()
            refreshOtherParticipantUsername()
        }
        .onDisappear {
            statusListener?.remove()
        }
        .sheet(isPresented: $viewModel.showStarredMessages) {
            ConversationStarredMessagesView(
                messages: viewModel.starredMessages,
                currentUserId: viewModel.currentUserId,
                otherParticipantName: otherParticipantDisplayName,
                onSelect: { messageId in
                    viewModel.showStarredMessages = false
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onJumpToMessage?(messageId)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $viewModel.showFullScreenMedia) {
            if let selectedMedia = viewModel.selectedMedia {
                FullScreenMediaView(
                    media: selectedMedia,
                    mediaItems: viewModel.sharedMedia,
                    currentUserId: viewModel.currentUserId,
                    otherParticipantName: otherParticipantDisplayName,
                    onClose: {
                        viewModel.showFullScreenMedia = false
                        viewModel.selectedMedia = nil
                    },
                    onSendReply: { media, text, completion in
                        viewModel.sendReplyToMedia(media, text: text, completion: completion)
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

    @ViewBuilder
    private var sharedMediaGalleryDestination: some View {
        ClusterGalleryView(
            messages: viewModel.sharedMediaMessages.filter { !$0.isDeleted },
            currentUserId: viewModel.currentUserId,
            presentation: .pushed,
            onClose: {
                viewModel.showAllMedia = false
            },
            onHydrateMedia: { message in
                viewModel.hydrateMediaIfNeeded(for: message)
            },
            onOpenMedia: { message, completion in
                viewModel.openMediaForViewing(message, completion: completion)
            },
            isDownloadingMedia: { viewModel.isDownloadingMedia($0) },
            downloadProgress: { viewModel.downloadProgress[$0] },
            onDeleteForMe: { messages in
                messages.forEach { viewModel.deleteMessageForMe($0) }
            },
            onDeleteForEveryone: { messages in
                messages.forEach { viewModel.deleteMessageForEveryone($0) }
            },
            detail: { selectedMessage, dismissDetail in
                if let media = viewModel.sharedMedia(from: selectedMessage) {
                    FullScreenMediaView(
                        media: media,
                        mediaItems: viewModel.sharedMediaItemsForOverlay(selecting: selectedMessage),
                        currentUserId: viewModel.currentUserId,
                        otherParticipantName: otherParticipantDisplayName,
                        onClose: {
                            dismissDetail()
                        },
                        onSendReply: { media, text, completion in
                            viewModel.sendReplyToMedia(media, text: text, completion: completion)
                        }
                    )
                }
            }
        )
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
                    .background(Color.clear.momentsChromeGlass(in: Circle()))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 34))
                            .foregroundColor(adaptiveColors.primary)
                    )
            }

            Text(otherParticipantDisplayName)
                .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                .foregroundColor(adaptiveColors.primary)

            if let presence = onlineStatusService.presenceDisplay(
                for: otherUserStatus,
                lastSeen: otherUserLastSeen
            ) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(presence.status.color)
                        .frame(width: 8, height: 8)

                    Text(presence.statusText)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(adaptiveColors.secondary)

                    if let lastSeenText = presence.supplementalText {
                        Text("• \(lastSeenText)")
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.clear.momentsChromeGlass(in: Capsule()))
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(adaptiveColors.primary)

                Spacer()

                if !viewModel.sharedMedia.isEmpty {
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        viewModel.showAllMedia = true
                    }) {
                        Text(NSLocalizedString("common.viewAll", comment: "View all"))
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.clear.momentsChromeGlass(in: Capsule()))
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
                            .font(.system(size: legacyPoppinsSize(14)))
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

    // MARK: - Starred Messages Section
    private var starredMessagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                HapticManager.shared.lightImpact()
                viewModel.showStarredMessages = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "FFD60A"))

                    Text(NSLocalizedString("conversationSettings.starredMessages", comment: ""))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundColor(adaptiveColors.primary)

                    Spacer()

                    Text(starredMessagesCountLabel)
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundColor(adaptiveColors.tertiary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(adaptiveColors.tertiary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var starredMessagesCountLabel: String {
        let count = viewModel.starredMessages.count
        if count == 0 {
            return NSLocalizedString("conversationSettings.starredMessages.none", comment: "")
        }
        return "\(count)"
    }



    // MARK: - Privacy Settings Section
    private var privacySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("conversationSettings.privacy", comment: ""))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(adaptiveColors.primary)
            }

            VStack(spacing: 16) {
                Toggle(isOn: $viewModel.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.notifications", comment: "Notifications"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.notifications.desc", comment: "Receive alerts for new messages"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .tint(SettingsProfileColors.toggleTint)
                .onChange(of: viewModel.notificationsEnabled) { _, _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleNotifications()
                }

                dividerLine

                Toggle(isOn: $viewModel.messagePreviewEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.privacy.messagePreview.title", comment: "Show message preview"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.privacy.messagePreview.description", comment: "Show message text in notifications and the conversation list"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .tint(SettingsProfileColors.toggleTint)
                .onChange(of: viewModel.messagePreviewEnabled) { _, _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleMessagePreview()
                }

                dividerLine

                Toggle(isOn: $viewModel.buzzEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.privacy.buzz.title", comment: "Buzz notifications"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.privacy.buzz.description", comment: "Receive buzz alerts in this chat"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .tint(SettingsProfileColors.toggleTint)
                .onChange(of: viewModel.buzzEnabled) { _, _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleBuzzNotifications()
                }

                dividerLine

                Toggle(isOn: $viewModel.readReceiptsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.privacy.readReceipts.title", comment: ""))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.privacy.readReceipts.description", comment: ""))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .tint(SettingsProfileColors.toggleTint)
                .onChange(of: viewModel.readReceiptsEnabled) { _, _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleReadReceipts()
                }

                dividerLine

                Toggle(isOn: $viewModel.forwardingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.privacy.forwarding.title", comment: ""))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.privacy.forwarding.description", comment: ""))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .tint(SettingsProfileColors.toggleTint)
                .onChange(of: viewModel.forwardingEnabled) { _, _ in
                    HapticManager.shared.lightImpact()
                    viewModel.toggleForwarding()
                }

                dividerLine

                Toggle(isOn: $viewModel.typingIndicatorEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.typingIndicator", comment: "Typing indicator"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundColor(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.typingIndicator.desc", comment: "Show when you are typing"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }
                }
                .tint(SettingsProfileColors.toggleTint)
                .onChange(of: viewModel.typingIndicatorEnabled) { _, _ in
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
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
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
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
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
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundColor(adaptiveColors.secondary)

            Spacer()

            Text(value)
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundColor(adaptiveColors.primary)
        }
    }
}

struct SharedMediaThumbnail: View {
    let media: SharedMedia
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var resolvedThumbnailUrl: String?

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var displayThumbnailUrl: String? {
        if let resolvedThumbnailUrl { return resolvedThumbnailUrl }
        // Para vídeos no usamos la URL del vídeo como imagen (no renderiza portada).
        if media.type == .video { return nil }
        return media.thumbnailUrl
    }

    var body: some View {
        KFImage(displayThumbnailUrl.flatMap { URL(string: $0) })
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
            .task { await resolveVideoThumbnailIfNeeded() }
            .overlay(alignment: .bottomLeading) {
                if media.type == .video {
                    ChatVideoPlayBadge(size: 16, padding: 8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .onTapGesture {
                onTap()
            }
    }

    private func resolveVideoThumbnailIfNeeded() async {
        guard media.type == .video, resolvedThumbnailUrl == nil else { return }

        guard let message = media.sourceMessage else {
            if media.thumbnailUrl != media.originalUrl {
                resolvedThumbnailUrl = media.thumbnailUrl
            }
            return
        }

        if let thumb = message.thumbnailUrl, !thumb.isEmpty {
            resolvedThumbnailUrl = thumb
            return
        }

        if let resolved = await ChatService.shared.resolveVideoThumbnail(for: message) {
            resolvedThumbnailUrl = resolved
            return
        }

        if let mediaUrl = message.mediaUrl,
           let url = URL(string: mediaUrl),
           let poster = await ChatVideoPosterGenerator.poster(for: url, messageId: message.id) {
            resolvedThumbnailUrl = poster
        }
    }
}

// MARK: - View Model
@MainActor
class ConversationSettingsViewModel: ObservableObject {
    @Published var currentUserId = Auth.auth().currentUser?.uid ?? ""
    @Published var conversationCreatedDate = "Desconocida"
    @Published var totalMessages = 0
    @Published var sharedPhotos = 0
    @Published var sharedVideos = 0
    @Published var sharedMedia: [SharedMedia] = []
    @Published var sharedMediaMessages: [EnhancedMessage] = []
    @Published var starredMessages: [EnhancedMessage] = []
    @Published var showAllMedia = false
    @Published var showStarredMessages = false
    @Published var selectedMedia: SharedMedia?
    @Published var showFullScreenMedia = false
    @Published private(set) var downloadProgress: [String: Double] = [:]

    private var downloadingMediaIds = Set<String>()
    private var hydratingMediaIds = Set<String>()
    private var refreshingMetadataIds = Set<String>()

    @Published var notificationsEnabled = true
    @Published var readReceiptsEnabled = true
    @Published var forwardingEnabled = true
    @Published var typingIndicatorEnabled = true
    @Published var messagePreviewEnabled = true
    @Published var buzzEnabled = true
    @Published var showNotificationAlert = false
    @Published var notificationAlertMessage = ""

    private let chatService = ChatService.shared
    private let firestoreService = FirestoreService()
    private var currentConversation: Conversation?
    private let typingIndicatorLegacyKey = "chat_typing_indicator_enabled"

    // Clave POR CONVERSACIÓN (App Group) leída por el Notification Service Extension
    // y la lista de conversaciones. Permite activar la vista previa en unos chats y
    // ocultarla en otros. Por defecto: ON.
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: "group.com.glowsyapp") }
    private func messagePreviewKey(for conversationId: String) -> String {
        "chat_show_message_preview_\(conversationId)"
    }

    private func boolFromDefaults(key: String, defaultValue: Bool) -> Bool {
        if let storedValue = UserDefaults.standard.object(forKey: key) as? Bool {
            return storedValue
        }
        return defaultValue
    }

    private func typingIndicatorKey(for conversationId: String) -> String {
        "chat_typing_indicator_enabled_\(conversationId)"
    }

    private func forwardingPreferenceKey(for conversationId: String) -> String {
        "chat_forwarding_enabled_\(conversationId)"
    }

    private func buzzPreferenceKey(for conversationId: String) -> String {
        "chat_buzz_enabled_\(conversationId)"
    }

    func loadConversationData(conversation: Conversation) {
        currentConversation = conversation
        forwardingEnabled = conversation.forwardingPreferences?[currentUserId] ?? true
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
        conversationCreatedDate = MomentsFormat.smartDate(from: conversation.timestamp, context: .mediumDate)
    }

    private func processMessages(_ messages: [EnhancedMessage]) {
        totalMessages = messages.count

        let mediaMessages = messages
            .filter(isSharedGalleryEligible)
            .sorted { $0.timestamp > $1.timestamp }

        sharedMediaMessages = mediaMessages
        sharedPhotos = mediaMessages.filter { $0.type == .image }.count
        sharedVideos = mediaMessages.filter { $0.type == .video }.count
        sharedMedia = mediaMessages.compactMap(makeSharedMedia)

        starredMessages = messages
            .filter { !$0.isDeleted && $0.isStarred(by: currentUserId) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func isSharedGalleryEligible(_ message: EnhancedMessage) -> Bool {
        guard !message.isDeleted else { return false }
        guard message.type == .image || message.type == .video else { return false }
        guard !message.isViewOnce && message.type != .ephemeral && message.storyReplyData == nil else { return false }
        if message.mediaUrl != nil { return true }
        if message.mediaObjectPath != nil, message.mediaEncryption != nil { return true }
        return message.thumbnailUrl != nil && message.thumbnailObjectPath != nil
    }

    func makeSharedMedia(from message: EnhancedMessage) -> SharedMedia? {
        let mediaUrl = message.mediaUrl ?? message.thumbnailUrl
        guard let mediaUrl else { return nil }

        return SharedMedia(
            id: message.id,
            type: message.type == .image ? .image : .video,
            thumbnailUrl: message.thumbnailUrl ?? mediaUrl,
            originalUrl: mediaUrl,
            senderId: message.senderId,
            timestamp: message.timestamp,
            sourceMessage: message
        )
    }

    func sharedMedia(from message: EnhancedMessage) -> SharedMedia? {
        guard message.hasLocalMediaReadyForViewer || message.mediaUrl != nil else { return nil }
        return makeSharedMedia(from: message)
    }

    func sharedMediaItemsForOverlay(selecting message: EnhancedMessage) -> [SharedMedia] {
        let items = sharedMediaMessages.compactMap(sharedMedia(from:))
        guard let selected = sharedMedia(from: message) else { return items }
        if items.contains(where: { $0.id == selected.id }) {
            return items
        }
        return items + [selected]
    }

    func isDownloadingMedia(_ messageId: String) -> Bool {
        downloadingMediaIds.contains(messageId) || hydratingMediaIds.contains(messageId)
    }

    func hydrateMediaIfNeeded(for message: EnhancedMessage) {
        if message.isMediaAwaitingManualDownload {
            hydrateThumbnailPreviewIfNeeded(for: message)
            return
        }

        guard ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return }

        if message.type == .video {
            hydrateVideoThumbnailIfNeeded(for: message)
            return
        }

        guard message.isMediaPendingResolution else {
            if message.type == .image,
               message.mediaUrl == nil,
               message.mediaObjectPath == nil || message.mediaEncryption == nil {
                refreshMediaMetadataIfNeeded(for: message)
            }
            return
        }

        guard !hydratingMediaIds.contains(message.id) else { return }
        hydratingMediaIds.insert(message.id)
        setDownloadProgress(0.03, for: message.id)
        prepareMediaForViewing(message, forceDownload: false) { [weak self] _ in
            self?.hydratingMediaIds.remove(message.id)
            self?.clearDownloadProgress(for: message.id)
        }
    }

    func openMediaForViewing(_ message: EnhancedMessage, completion: @escaping (EnhancedMessage) -> Void) {
        guard message.needsDownloadForPlayback else {
            completion(message)
            return
        }

        guard !downloadingMediaIds.contains(message.id) else { return }
        downloadingMediaIds.insert(message.id)
        setDownloadProgress(0.03, for: message.id)
        prepareMediaForViewing(message, forceDownload: true) { [weak self] updated in
            self?.downloadingMediaIds.remove(message.id)
            self?.clearDownloadProgress(for: message.id)
            completion(updated)
        }
    }

    func deleteMessageForMe(_ message: EnhancedMessage) {
        guard let conversationId = currentConversation?.id, !conversationId.isEmpty else { return }

        sharedMediaMessages.removeAll { $0.id == message.id }
        sharedMedia.removeAll { $0.id == message.id }
        recomputeSharedMediaCounts()

        chatService.deleteMessageForMe(
            conversationId: conversationId,
            messageId: message.id,
            userId: currentUserId
        ) { _ in }
    }

    func deleteMessageForEveryone(_ message: EnhancedMessage) {
        guard let conversationId = currentConversation?.id, !conversationId.isEmpty else { return }
        guard message.senderId == currentUserId else { return }

        sharedMediaMessages.removeAll { $0.id == message.id }
        sharedMedia.removeAll { $0.id == message.id }
        recomputeSharedMediaCounts()

        chatService.deleteMessageWithCleanup(
            conversationId: conversationId,
            messageId: message.id
        ) { _ in }
    }

    private func recomputeSharedMediaCounts() {
        sharedPhotos = sharedMediaMessages.filter { $0.type == .image }.count
        sharedVideos = sharedMediaMessages.filter { $0.type == .video }.count
    }

    private func updateGalleryMessage(_ updated: EnhancedMessage) {
        guard let index = sharedMediaMessages.firstIndex(where: { $0.id == updated.id }) else { return }
        sharedMediaMessages[index] = updated
        if let media = makeSharedMedia(from: updated),
           let mediaIndex = sharedMedia.firstIndex(where: { $0.id == updated.id }) {
            sharedMedia[mediaIndex] = media
        }
    }

    private func setDownloadProgress(_ progress: Double, for messageId: String) {
        downloadProgress[messageId] = progress
    }

    private func clearDownloadProgress(for messageId: String) {
        downloadProgress.removeValue(forKey: messageId)
    }

    private func refreshMediaMetadataIfNeeded(for message: EnhancedMessage) {
        guard message.type == .image || message.type == .video else { return }
        guard let conversationId = currentConversation?.id, !conversationId.isEmpty else { return }

        let missingMain = message.mediaObjectPath == nil || message.mediaEncryption == nil
        let needsThumb = message.type == .video && message.needsVideoThumbnailForDisplay
        let missingThumbMeta = message.thumbnailObjectPath == nil || message.thumbnailEncryption == nil

        if message.type == .image {
            guard missingMain else { return }
        } else if missingMain {
        } else if needsThumb && missingThumbMeta {
        } else {
            if needsThumb { hydrateVideoThumbnailIfNeeded(for: message) }
            return
        }

        let messageId = message.id
        guard refreshingMetadataIds.insert(messageId).inserted else { return }

        chatService.fetchMessage(conversationId: conversationId, messageId: messageId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshingMetadataIds.remove(messageId)
                guard case .success(let fresh?) = result else { return }
                self.updateGalleryMessage(fresh)
                if fresh.type == .video {
                    self.hydrateVideoThumbnailIfNeeded(for: fresh)
                } else {
                    self.hydrateMediaIfNeeded(for: fresh)
                }
            }
        }
    }

    private func hydrateVideoThumbnailIfNeeded(for message: EnhancedMessage) {
        guard message.type == .video else { return }
        guard message.needsVideoThumbnailForDisplay else { return }
        guard ChatMediaDownloadPolicy.shouldDownloadAutomatically() else { return }

        if message.thumbnailObjectPath != nil, message.thumbnailEncryption != nil {
            let thumbnailKey = "thumb_\(message.id)"
            guard !hydratingMediaIds.contains(thumbnailKey) else { return }
            hydratingMediaIds.insert(thumbnailKey)
            Task { [weak self] in
                guard let self else { return }
                let resolvedThumb = await self.chatService.resolveVideoThumbnail(for: message, forceDownload: false)
                await MainActor.run {
                    self.hydratingMediaIds.remove(thumbnailKey)
                    guard let resolvedThumb,
                          var updated = self.sharedMediaMessages.first(where: { $0.id == message.id }) else {
                        return
                    }
                    updated.thumbnailUrl = resolvedThumb
                    self.updateGalleryMessage(updated)
                }
            }
            return
        }

        if let mediaUrl = message.mediaUrl, URL(string: mediaUrl) != nil {
            generateVideoPosterIfPossible(for: message)
            return
        }

        if message.mediaObjectPath != nil, message.mediaEncryption != nil {
            guard !hydratingMediaIds.contains(message.id) else { return }
            hydratingMediaIds.insert(message.id)
            setDownloadProgress(0.03, for: message.id)
            prepareMediaForViewing(message, forceDownload: false) { [weak self] updated in
                self?.hydratingMediaIds.remove(message.id)
                self?.clearDownloadProgress(for: message.id)
                self?.generateVideoPosterIfPossible(for: updated)
            }
            return
        }

        refreshMediaMetadataIfNeeded(for: message)
    }

    private func hydrateThumbnailPreviewIfNeeded(for message: EnhancedMessage) {
        guard message.thumbnailObjectPath != nil, message.thumbnailEncryption != nil else { return }
        if let urlString = message.thumbnailUrl,
           let url = URL(string: urlString),
           message.localMediaFileIsReachable(url) {
            return
        }

        let previewKey = "thumb_preview_\(message.id)"
        guard !hydratingMediaIds.contains(previewKey) else { return }
        hydratingMediaIds.insert(previewKey)

        Task { [weak self] in
            guard let self else { return }
            let resolvedThumb = await self.chatService.resolveVideoThumbnail(for: message, forceDownload: false)
            await MainActor.run {
                self.hydratingMediaIds.remove(previewKey)
                guard let resolvedThumb,
                      var updated = self.sharedMediaMessages.first(where: { $0.id == message.id }) else {
                    return
                }
                updated.thumbnailUrl = resolvedThumb
                self.updateGalleryMessage(updated)
            }
        }
    }

    private func generateVideoPosterIfPossible(for message: EnhancedMessage) {
        guard message.needsVideoThumbnailForDisplay,
              let mediaUrl = message.mediaUrl,
              let url = URL(string: mediaUrl) else { return }
        let posterKey = "poster_\(message.id)"
        guard !hydratingMediaIds.contains(posterKey) else { return }
        hydratingMediaIds.insert(posterKey)
        Task { [weak self] in
            let poster = await ChatVideoPosterGenerator.poster(for: url, messageId: message.id)
            await MainActor.run {
                guard let self else { return }
                self.hydratingMediaIds.remove(posterKey)
                guard let poster,
                      var updated = self.sharedMediaMessages.first(where: { $0.id == message.id }) else {
                    return
                }
                updated.thumbnailUrl = poster
                self.updateGalleryMessage(updated)
            }
        }
    }

    private func prepareMediaForViewing(
        _ message: EnhancedMessage,
        forceDownload: Bool,
        completion: @escaping (EnhancedMessage) -> Void
    ) {
        if message.hasLocalMediaReadyForViewer, !message.hasMissingLocalMedia {
            completion(message)
            return
        }

        guard message.mediaObjectPath != nil, message.mediaEncryption != nil else {
            completion(message)
            return
        }

        Task {
            defer {
                Task { @MainActor in
                    clearDownloadProgress(for: message.id)
                }
            }

            guard let (mediaUrl, thumbnailUrl) = await chatService.resolveEncryptedMediaForMessage(message, forceDownload: forceDownload) else {
                await MainActor.run { completion(message) }
                return
            }
            await MainActor.run {
                var updated = self.sharedMediaMessages.first(where: { $0.id == message.id }) ?? message
                updated.mediaUrl = mediaUrl
                if let thumbnailUrl {
                    updated.thumbnailUrl = thumbnailUrl
                }
                self.updateGalleryMessage(updated)
                if let conversationId = self.currentConversation?.id {
                    LocalPersistenceService.shared.saveMessages([updated], conversationId: conversationId, sync: false)
                }
                completion(updated)
            }
        }
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
                if error != nil {
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

    func toggleForwarding() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }

        let db = Firestore.firestore()
        db.collection("conversations").document(conversationId).updateData([
            "forwardingPreferences.\(currentUserId)": forwardingEnabled
        ])

        UserDefaults.standard.set(forwardingEnabled, forKey: forwardingPreferenceKey(for: conversationId))

        NotificationCenter.default.post(
            name: NSNotification.Name("ConversationForwardingPreferenceChanged"),
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "userId": currentUserId,
                "allowsForwarding": forwardingEnabled
            ]
        )
    }

    func toggleTypingIndicator() {
        guard let conversationId = currentConversation?.id else { return }

        let perChatKey = typingIndicatorKey(for: conversationId)
        UserDefaults.standard.set(typingIndicatorEnabled, forKey: perChatKey)
    }

    func toggleMessagePreview() {
        guard let conversationId = currentConversation?.id else { return }
        sharedDefaults?.set(messagePreviewEnabled, forKey: messagePreviewKey(for: conversationId))
    }

    func toggleBuzzNotifications() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }

        let db = Firestore.firestore()
        db.collection("conversations").document(conversationId).updateData([
            "buzzPreferences.\(currentUserId)": buzzEnabled
        ])

        UserDefaults.standard.set(buzzEnabled, forKey: buzzPreferenceKey(for: conversationId))

        NotificationCenter.default.post(
            name: NSNotification.Name("ConversationBuzzPreferenceChanged"),
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "userId": currentUserId,
                "allowsBuzz": buzzEnabled
            ]
        )
    }

    private func loadPrivacySettings() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let conversationId = currentConversation?.id else { return }

        // Cargar desde UserDefaults como fallback instantáneo
        readReceiptsEnabled = boolFromDefaults(key: "chat_read_receipts_enabled_\(conversationId)", defaultValue: true)
        forwardingEnabled = boolFromDefaults(key: forwardingPreferenceKey(for: conversationId), defaultValue: true)
        buzzEnabled = boolFromDefaults(key: buzzPreferenceKey(for: conversationId), defaultValue: true)

        let typingKey = typingIndicatorKey(for: conversationId)
        if let perChatTyping = UserDefaults.standard.object(forKey: typingKey) as? Bool {
            typingIndicatorEnabled = perChatTyping
        } else {
            typingIndicatorEnabled = boolFromDefaults(key: typingIndicatorLegacyKey, defaultValue: true)
        }

        // Vista previa por conversación (App Group, default ON).
        messagePreviewEnabled = sharedDefaults?.object(forKey: messagePreviewKey(for: conversationId)) as? Bool ?? true

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

                        if let forwardingPrefs = convData["forwardingPreferences"] as? [String: Bool],
                           let myForwardingPreference = forwardingPrefs[currentUserId] {
                            self.forwardingEnabled = myForwardingPreference
                            UserDefaults.standard.set(myForwardingPreference, forKey: self.forwardingPreferenceKey(for: conversationId))
                        }

                        if let buzzPrefs = convData["buzzPreferences"] as? [String: Bool],
                           let myBuzzPreference = buzzPrefs[currentUserId] {
                            self.buzzEnabled = myBuzzPreference
                            UserDefaults.standard.set(myBuzzPreference, forKey: self.buzzPreferenceKey(for: conversationId))
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
              currentConversation?.id != nil else { return }

        // Obtener el ID del otro participante
        let otherParticipantId = currentConversation?.otherParticipantId ?? ""

        // Eliminar conversación usando ChatService
        chatService.deleteConversationsBetweenUsers(user1Id: currentUserId, user2Id: otherParticipantId) { _ in
        }
    }

    func blockUser() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentConversation?.id != nil else { return }

        // Obtener el ID del otro participante
        let otherParticipantId = currentConversation?.otherParticipantId ?? ""

        // Bloquear usuario usando FirestoreService
        firestoreService.blockUser(currentUserId: currentUserId, targetUserId: otherParticipantId) { _ in
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
    var sourceMessage: EnhancedMessage? = nil
    var allowsSaving: Bool = true

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

// MARK: - Starred Messages List
struct ConversationStarredMessagesView: View {
    let messages: [EnhancedMessage]
    let currentUserId: String
    let otherParticipantName: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
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
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }

                Spacer()

                Text(NSLocalizedString("conversationSettings.starredMessages", comment: ""))
                    .font(.system(size: legacyPoppinsSize(22), weight: .semibold))
                    .foregroundColor(adaptiveColors.primary)

                Spacer()

                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 16)

            if messages.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 36))
                        .foregroundColor(adaptiveColors.tertiary)
                    Text(NSLocalizedString("conversationSettings.starredMessages.empty", comment: ""))
                        .font(.system(size: legacyPoppinsSize(15)))
                        .foregroundColor(adaptiveColors.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages, id: \.id) { message in
                            StarredMessageRow(
                                message: message,
                                currentUserId: currentUserId,
                                otherParticipantName: otherParticipantName,
                                adaptiveColors: adaptiveColors,
                                colorScheme: colorScheme
                            ) {
                                HapticManager.shared.lightImpact()
                                onSelect(message.id)
                            }

                            if message.id != messages.last?.id {
                                Rectangle()
                                    .fill(adaptiveColors.tertiary.opacity(colorScheme == .dark ? 0.16 : 0.12))
                                    .frame(height: 0.5)
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

private struct StarredMessageRow: View {
    let message: EnhancedMessage
    let currentUserId: String
    let otherParticipantName: String
    let adaptiveColors: AdaptiveColors
    let colorScheme: ColorScheme
    let onTap: () -> Void

    private var senderLabel: String {
        message.senderId == currentUserId
            ? NSLocalizedString("chat.reply.you", comment: "")
            : otherParticipantName
    }

    private var previewText: String {
        StarredMessagePreview.text(for: message)
    }

    private var relativeDate: String {
        MomentsFormat.relativeTime(from: message.timestamp)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                StarredMessagePreview.iconView(for: message, adaptiveColors: adaptiveColors)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(senderLabel)
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                        Spacer()
                        Text(relativeDate)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundColor(adaptiveColors.tertiary)
                    }

                    Text(previewText)
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundColor(adaptiveColors.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private enum StarredMessagePreview {
    static func text(for message: EnhancedMessage) -> String {
        if message.isDeleted {
            return NSLocalizedString("chat.message.deleted", comment: "")
        }

        if message.type == .text {
            let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return content.isEmpty ? message.type.displayName : content
        }

        return message.type.displayName
    }

    @ViewBuilder
    static func iconView(for message: EnhancedMessage, adaptiveColors: AdaptiveColors) -> some View {
        switch message.type {
        case .image, .viewOnceImage:
            if let url = message.thumbnailUrl ?? message.mediaUrl, let imageURL = URL(string: url) {
                KFImage(imageURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                iconBadge(systemName: "photo.fill", color: .blue, adaptiveColors: adaptiveColors)
            }
        case .video, .viewOnceVideo:
            if let url = message.thumbnailUrl ?? message.mediaUrl, let imageURL = URL(string: url) {
                KFImage(imageURL)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        ChatVideoPlayBadge(size: 12, padding: 6)
                    }
            } else {
                iconBadge(systemName: "video.fill", color: .purple, adaptiveColors: adaptiveColors)
            }
        default:
            let (icon, color) = iconSpec(for: message.type)
            iconBadge(systemName: icon, color: color, adaptiveColors: adaptiveColors)
        }
    }

    private static func iconSpec(for type: MessageType) -> (String, Color) {
        switch type {
        case .audio: return ("mic.fill", .orange)
        case .location: return ("location.fill", .green)
        case .file: return ("doc.fill", .gray)
        case .ephemeral: return ("sparkles", .pink)
        case .text: return ("text.quote", .secondary)
        case .sharedMoment: return ("sparkles.rectangle.stack", .pink)
        case .sharedStory: return ("circle.dashed", .purple)
        case .gif: return ("photo.on.rectangle.angled", .blue)
        case .sticker: return ("face.smiling", .yellow)
        default: return ("ellipsis.bubble.fill", .secondary)
        }
    }

    private static func iconBadge(systemName: String, color: Color, adaptiveColors: AdaptiveColors) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.15))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            )
    }
}

// MARK: - Full Screen Media View
struct FullScreenMediaView: View {
    let media: SharedMedia
    let mediaItems: [SharedMedia]
    let currentUserId: String
    let otherParticipantName: String
    var displayReactions: ((String) -> [String: [String]]?)? = nil
    var onReaction: ((String, String) -> Void)? = nil
    var onMoreReactions: ((String) -> Void)? = nil
    let onClose: () -> Void
    let onSendReply: (SharedMedia, String, @escaping (Result<Void, Error>) -> Void) -> Void
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isReplyFocused: Bool
    @State private var replyText = ""
    @State private var isSendingReply = false
    @State private var showSaveResult = false
    @State private var saveResultMessage = ""
    @State private var videoCurrentTime: Double = 0
    @State private var videoDuration: Double = 0
    @State private var seekTarget: Double? = nil
    @State private var sharedPlayer: AVPlayer? = nil
    @State private var isVideoPaused = false
    @State private var isMuted = false
    @State private var expandedVideoURL: URL?
    @State private var showExpandedVideo = false
    @State private var dragOffset: CGFloat = 0
    @State private var selectedIndex: Int
    @State private var showingReactionBarForMessageId: String? = nil
    @State private var ephemeralRemaining: TimeInterval = 0
    @State private var ephemeralTimer: Timer?

    init(
        media: SharedMedia,
        mediaItems: [SharedMedia] = [],
        currentUserId: String,
        otherParticipantName: String,
        displayReactions: ((String) -> [String: [String]]?)? = nil,
        onReaction: ((String, String) -> Void)? = nil,
        onMoreReactions: ((String) -> Void)? = nil,
        onClose: @escaping () -> Void,
        onSendReply: @escaping (SharedMedia, String, @escaping (Result<Void, Error>) -> Void) -> Void
    ) {
        self.media = media
        self.mediaItems = mediaItems
        self.currentUserId = currentUserId
        self.otherParticipantName = otherParticipantName
        self.displayReactions = displayReactions
        self.onReaction = onReaction
        self.onMoreReactions = onMoreReactions
        self.onClose = onClose
        self.onSendReply = onSendReply

        let source = mediaItems.isEmpty ? [media] : mediaItems
        let index = source.firstIndex(where: { $0.id == media.id }) ?? 0
        _selectedIndex = State(initialValue: index)
    }

    private var pagedMedia: [SharedMedia] {
        mediaItems.isEmpty ? [media] : mediaItems
    }

    private var currentMedia: SharedMedia {
        let safeIndex = min(max(selectedIndex, 0), max(pagedMedia.count - 1, 0))
        return pagedMedia[safeIndex]
    }

    private var isOwnMedia: Bool {
        currentMedia.senderId == currentUserId
    }

    private var isVideo: Bool {
        currentMedia.type == .video
    }

    private var authorName: String {
        isOwnMedia ? NSLocalizedString("chat.reply.you", comment: "You") : otherParticipantName
    }

    private var relativeTime: String {
        MomentsFormat.relativeTime(from: currentMedia.timestamp, style: .conversational(unitsStyle: .full))
    }

    private var isEphemeralMedia: Bool {
        currentMedia.sourceMessage?.type == .ephemeral || !currentMedia.allowsSaving
    }

    private var ephemeralExpirationDate: Date? {
        currentMedia.sourceMessage?.expirationDate
    }

    private var ephemeralAccentColor: Color {
        Color(hex: "FFCC33")
    }

    private var canSendReply: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingReply
    }

    private var primaryOverlayColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryOverlayColor: Color {
        primaryOverlayColor.opacity(0.58)
    }

    private var mediaClipShape: RoundedRectangle {
        FeedMomentCardLayout.continuousRoundedRect
    }

    private func fullscreenReactionToken(for messageId: String) -> String {
        guard let reactions = displayReactions?(messageId), !reactions.isEmpty else { return "" }
        return reactions
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
    }

    var body: some View {
        ZStack {
            backgroundView

            mediaContentLayer

            if let activeReactionMessageId = showingReactionBarForMessageId,
               activeReactionMessageId == currentMedia.id,
               onReaction != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showingReactionBarForMessageId = nil
                        }
                    }

                GeometryReader { geometry in
                    ChatQuickReactionsBar(
                        onReaction: { emoji in
                            onReaction?(currentMedia.id, emoji)
                            withAnimation(.easeOut(duration: 0.18)) {
                                showingReactionBarForMessageId = nil
                            }
                        },
                        onMore: {
                            onMoreReactions?(currentMedia.id)
                            withAnimation(.easeOut(duration: 0.18)) {
                                showingReactionBarForMessageId = nil
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            headerView
                .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            replyComposer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.84), value: dragOffset)
        .simultaneousGesture(dismissDragGesture)
        .alert(isPresented: $showSaveResult) {
            Alert(
                title: Text("conversationSettings.mediaSave.title"),
                message: Text(saveResultMessage),
                dismissButton: .default(Text("common.ok"))
            )
        }
        .onChange(of: selectedIndex) { _, _ in
            videoCurrentTime = 0
            videoDuration = 0
            isVideoPaused = false
            showingReactionBarForMessageId = nil
            restartEphemeralCountdownIfNeeded()
        }
        .onAppear {
            restartEphemeralCountdownIfNeeded()
        }
        .onDisappear {
            stopEphemeralCountdown()
        }
        .onChange(of: showExpandedVideo) { _, isShown in
            if !isShown {
                expandedVideoURL = nil
            }
        }
        .background(
            NativeVideoPresenter(isPresented: $showExpandedVideo, player: sharedPlayer)
                .frame(width: 0, height: 0)
        )
    }

    @ViewBuilder
    private var backgroundView: some View {
        Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6")
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var mediaContentLayer: some View {
        if pagedMedia.count > 1 {
            TabView(selection: $selectedIndex) {
                ForEach(Array(pagedMedia.enumerated()), id: \.element.id) { index, item in
                    mediaRenderer(for: item, isActive: index == selectedIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, FeedMomentCardLayout.listHorizontalPadding)
                        .id("\(item.id)-\(fullscreenReactionToken(for: item.id))")
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        } else {
            mediaRenderer(for: currentMedia, isActive: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, FeedMomentCardLayout.listHorizontalPadding)
        }
    }

    @ViewBuilder
    private func mediaRenderer(for item: SharedMedia, isActive: Bool) -> some View {
        let isOutgoing = item.senderId == currentUserId
        let reactions = displayReactions?(item.id)

        Group {
            switch item.type {
            case .image:
                KFImage(URL(string: item.originalUrl))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(mediaClipShape)

            case .video:
                if let url = URL(string: item.originalUrl) {
                    ZStack {
                        MomentsVideoPlayer(
                            url: url,
                            isLooping: true,
                            isPaused: !isActive || isVideoPaused,
                            isMuted: isMuted,
                            prioritizeSmoothPlayback: true,
                            showsPlaybackControls: false,
                            respectsExternalPauseState: true,
                            shouldAutoplay: isActive,
                            videoGravity: .resizeAspect,
                            onDurationReceived: { value in
                                if isActive {
                                    videoDuration = value
                                }
                            },
                            onProgressUpdate: { value in
                                if isActive {
                                    videoCurrentTime = value
                                }
                            },
                            onVideoFinished: {},
                            externalSeekTime: $seekTarget,
                            sharedPlayer: $sharedPlayer
                        )
                        .clipShape(mediaClipShape)

                        if isActive {
                            videoControlsOverlay
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .zIndex(2)
                        }
                    }
                    .contentShape(Rectangle())
                } else {
                    Text("conversationSettings.videoLoadError")
                        .foregroundColor(primaryOverlayColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .messageReactionOverlay(
            isOutgoing: isOutgoing,
            reactions: reactions,
            onTap: { emoji in onReaction?(item.id, emoji) }
        )
        .chatMessageLongPress {
            guard onReaction != nil else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showingReactionBarForMessageId = item.id
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            ProfileChromeIconButton(
                systemName: "chevron.left",
                foregroundColor: primaryOverlayColor,
                preset: .navigationBack,
                action: onClose
            )

            avatarView

            VStack(alignment: .leading, spacing: 1) {
                Text(authorName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(primaryOverlayColor)
                    .lineLimit(1)

                if isEphemeralMedia, let expirationDate = ephemeralExpirationDate, ephemeralRemaining > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .semibold))
                        Text(
                            String(
                                format: NSLocalizedString("stories.expiresIn", comment: ""),
                                ChatEphemeralTimeFormatting.shortLabel(for: ephemeralRemaining)
                            )
                        )
                        .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(ephemeralAccentColor)
                    .lineLimit(1)
                } else {
                    Text(relativeTime)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(secondaryOverlayColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if currentMedia.allowsSaving {
                ProfileChromeIconButton(
                    systemName: "arrow.down",
                    foregroundColor: primaryOverlayColor,
                    preset: .toolbarAction,
                    action: saveMedia
                )
                .accessibilityLabel(Text("conversationSettings.mediaSave.action"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var replyComposer: some View {
        HStack(spacing: 10) {
            TextField(NSLocalizedString("conversationSettings.replyPlaceholder", comment: "Reply placeholder"), text: $replyText)
                .font(.system(size: legacyPoppinsSize(15)))
                .foregroundColor(primaryOverlayColor)
                .focused($isReplyFocused)
                .submitLabel(.send)
                .onSubmit {
                    sendReply()
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .padding(.vertical, 10)

            Button(action: sendReply) {
                if isSendingReply {
                    ProgressView()
                        .controlSize(.small)
                        .tint(primaryOverlayColor)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(canSendReply ? primaryOverlayColor : primaryOverlayColor.opacity(0.32))
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.trailing, 10)
            .disabled(!canSendReply)
        }
        .frame(maxWidth: .infinity)
        .background(
            Color.clear.momentsChromeGlass(
                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                interactive: true
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.05),
                    lineWidth: 0.8
                )
        )
    }

    private var videoControlsOverlay: some View {
        ZStack {
            Button {
                HapticManager.shared.lightImpact()
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    isVideoPaused.toggle()
                }
            } label: {
                Image(systemName: isVideoPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(primaryOverlayColor)
                    .frame(width: 64, height: 64)
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                    .padding(60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack {
                HStack {
                    Spacer()
                    
                    HStack(spacing: 0) {
                        Button {
                            HapticManager.shared.lightImpact()
                            isMuted.toggle()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(primaryOverlayColor)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .frame(height: 16)
                            .background(primaryOverlayColor.opacity(0.2))
                        
                        Button {
                            if let url = URL(string: currentMedia.originalUrl) {
                                HapticManager.shared.lightImpact()
                                isVideoPaused = true
                                expandedVideoURL = url
                                showExpandedVideo = true
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(primaryOverlayColor)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                    .padding(12)
                }
                Spacer()
            }

            VStack {
                Spacer()

                MomentsVideoPlaybackTimeline(
                    currentTime: videoCurrentTime,
                    duration: videoDuration,
                    horizontalPadding: 18,
                    onSeek: { targetTime in
                        videoCurrentTime = targetTime
                        seekTarget = targetTime
                    }
                )
                .padding(.bottom, 16)
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    onClose()
                } else {
                    dragOffset = 0
                }
            }
    }

    @ViewBuilder
    private var avatarView: some View {
        if !media.senderId.isEmpty {
            StoryRingAvatarView(
                userId: currentMedia.senderId,
                size: 40,
                lineWidth: 2,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12),
                baseStrokeWidth: 1
            )
        } else {
            Circle()
                .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
                )
        }
    }

    private func sendReply() {
        let trimmedText = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSendingReply else { return }

        isSendingReply = true
        onSendReply(currentMedia, trimmedText) { result in
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
        guard let url = URL(string: currentMedia.originalUrl) else {
            saveResultMessage = NSLocalizedString("conversationSettings.mediaSave.error", comment: "")
            showSaveResult = true
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                switch currentMedia.type {
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

    private func restartEphemeralCountdownIfNeeded() {
        stopEphemeralCountdown()
        guard isEphemeralMedia, let expirationDate = ephemeralExpirationDate else {
            ephemeralRemaining = 0
            return
        }

        ephemeralRemaining = ChatEphemeralTimeFormatting.remainingSeconds(until: expirationDate)
        guard ephemeralRemaining > 0 else {
            onClose()
            return
        }

        ephemeralTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let remaining = ChatEphemeralTimeFormatting.remainingSeconds(until: expirationDate)
            ephemeralRemaining = remaining
            if remaining <= 0 {
                stopEphemeralCountdown()
                onClose()
            }
        }
    }

    private func stopEphemeralCountdown() {
        ephemeralTimer?.invalidate()
        ephemeralTimer = nil
    }
}

private class ModalVideoPlayerController: AVPlayerViewController {
    var onDismiss: (() -> Void)?
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed {
            onDismiss?()
        }
    }
}

private struct NativeVideoPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented, let player = player, context.coordinator.playerController == nil {
            let playerController = ModalVideoPlayerController()
            
            playerController.player = player
            playerController.onDismiss = {
                DispatchQueue.main.async {
                    self.isPresented = false
                }
            }
            context.coordinator.playerController = playerController
            
            DispatchQueue.main.async {
                uiViewController.present(playerController, animated: true) {
                    playerController.player?.play()
                }
            }
        } else if !isPresented, let playerController = context.coordinator.playerController {
            DispatchQueue.main.async {
                playerController.player?.pause()
                if playerController.presentingViewController != nil && !playerController.isBeingDismissed {
                    playerController.dismiss(animated: true)
                }
                context.coordinator.playerController = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var playerController: ModalVideoPlayerController?
    }
}
