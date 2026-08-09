import SwiftUI
import Kingfisher
import FirebaseAuth
import FirebaseFirestore
import AVKit
import Photos

struct ConversationSettingsView: View {
    let conversation: Conversation
    var onJumpToMessage: ((String) -> Void)? = nil
    var onSearchRequested: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ConversationSettingsViewModel()
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    @State private var liveOtherParticipantUsername: String = ""
    @State private var pendingJumpMessageId: String? = nil
    @State private var conversationMediaBytes: Int64 = 0
    @State private var showClearMediaConfirmation = false
    @State private var sharedTab: SharedContentTab = .media
    @State private var showChatPreferences = false
    @State private var showVanishPreferences = false
    @State private var showingUserProfile = false
    @State private var showBlockConfirmationFromHeader = false
    @State private var showReportSheetFromHeader = false
    @State private var isLargeHeader = false
    @State private var headerTopInset: CGFloat = 0
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var safeAreaTopValue: CGFloat = 0
    @State private var lastHeaderScrollOffset: CGFloat = 0

    private enum SharedContentTab: Hashable {
        case media
        case links
    }

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var otherParticipantDisplayName: String {
        let fallback = conversation.otherParticipantUsername ?? "Usuario"
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    private var headerPresence: PresenceDisplay? {
        onlineStatusService.presenceDisplay(
            for: otherUserStatus,
            lastSeen: otherUserLastSeen
        )
    }

    private var toolbarForeground: Color {
        isLargeHeader ? .white : adaptiveColors.primary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                settingsListSection
                    .padding(.horizontal, 16)

                settingsFooter
                    .padding(.horizontal, 16)

                sharedContentTabsSection
                    .padding(.top, 8)
            }
            .padding(.bottom, 32)
            .safeAreaInset(edge: .top, spacing: 0) {
                ConversationSettingsHeroHeader(
                    isLargeHeader: $isLargeHeader,
                    topInset: $headerTopInset,
                    avatarURL: conversation.otherParticipantProfileImagePath,
                    displayName: otherParticipantDisplayName,
                    presence: headerPresence,
                    notificationsEnabled: viewModel.notificationsEnabled,
                    onProfile: {
                        HapticManager.shared.lightImpact()
                        showingUserProfile = true
                    },
                    onSearch: {
                        HapticManager.shared.lightImpact()
                        onSearchRequested?()
                    },
                    onMuteToggle: {
                        HapticManager.shared.lightImpact()
                        viewModel.notificationsEnabled.toggle()
                        viewModel.toggleNotifications()
                    }
                )
            }
        }
        .background {
            Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6")
                .ignoresSafeArea()
        }
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentInsets.top
        } action: { _, newValue in
            headerTopInset = newValue
        }
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, newValue in
            lastHeaderScrollOffset = newValue
            // Expandir/colapsar también en decelerating (el rubber-band a veces no es solo .interacting).
            guard scrollPhase == .interacting || scrollPhase == .decelerating else { return }
            let shouldExpand = newValue < -22
            let shouldCollapse = newValue > 28
            let next: Bool
            if isLargeHeader {
                next = shouldCollapse ? false : true
            } else {
                next = shouldExpand ? true : false
            }
            guard next != isLargeHeader else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                isLargeHeader = next
            }
        }
        .onScrollPhaseChange { _, newPhase in
            scrollPhase = newPhase
            guard newPhase == .idle else { return }
            // No colapsar por el rebote del rubber-band tras expandir.
            if isLargeHeader {
                guard lastHeaderScrollOffset > 28 else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    isLargeHeader = false
                }
            } else if lastHeaderScrollOffset < -18 {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                    isLargeHeader = true
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.top
        } action: { newValue in
            safeAreaTopValue = newValue
        }
        // Solo en hero grande: extender bajo status bar. Compacto = layout original bajo la nav.
        .safeAreaPadding(.top, isLargeHeader ? safeAreaTopValue : 0)
        .ignoresSafeArea(.container, edges: isLargeHeader ? .top : [])
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .chatInteractivePopEnabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .modifier(ConversationSettingsScrollEdgeModifier(isLargeHeader: isLargeHeader))
        .modifier(ConversationSettingsCompactChromeModifier(isLargeHeader: isLargeHeader))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ProfileChromeIconButton(
                    systemName: "chevron.left",
                    foregroundColor: toolbarForeground,
                    preset: .navigationBack,
                    standaloneGlass: false,
                    action: { dismiss() }
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showBlockConfirmationFromHeader = true
                    } label: {
                        Label(NSLocalizedString("conversationSettings.blockUser", comment: ""), systemImage: "slash.circle")
                    }

                    Button(role: .destructive) {
                        showReportSheetFromHeader = true
                    } label: {
                        Label(NSLocalizedString("report.action.user", comment: "Report user"), systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(toolbarForeground)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .momentsFloatingTabBarHidden()
        .chatInteractivePopEnabled()
        .navigationDestination(isPresented: $viewModel.showSharedGallery) {
            sharedMediaGalleryDestination
                .toolbar(.hidden, for: .tabBar)
                .chatInteractivePopEnabled()
        }
        .navigationDestination(isPresented: $showChatPreferences) {
            ConversationChatPreferencesView(viewModel: viewModel)
                .toolbar(.hidden, for: .tabBar)
                .chatInteractivePopEnabled()
        }
        .navigationDestination(isPresented: $showVanishPreferences) {
            ConversationVanishModeView(viewModel: viewModel)
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $showingUserProfile) {
            UserProfileView(userId: conversation.otherParticipantId)
        }
        .sheet(isPresented: $showReportSheetFromHeader) {
            ReportBottomSheet(
                userId: conversation.otherParticipantId,
                username: otherParticipantDisplayName
            )
        }
        .confirmationDialog(
            NSLocalizedString("conversationSettings.blockUser", comment: ""),
            isPresented: $showBlockConfirmationFromHeader,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("conversationSettings.blockUser", comment: ""), role: .destructive) {
                HapticManager.shared.mediumImpact()
                viewModel.blockUser()
                dismiss()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        }
        .onAppear {
            viewModel.loadConversationData(conversation: conversation)
            setupOnlineStatusObserver()
            refreshOtherParticipantUsername()
            refreshMediaUsage()
        }
        .onDisappear {
            statusListener?.remove()
        }
        .sheet(isPresented: $viewModel.showStarredMessages, onDismiss: {
            // Pop diferido: si se hace dismiss() con el sheet aún animando, SwiftUI ignora el pop
            // y el salto al mensaje nunca llega al chat.
            guard let messageId = pendingJumpMessageId else { return }
            pendingJumpMessageId = nil
            onJumpToMessage?(messageId)
            dismiss()
        }) {
            ConversationStarredMessagesView(
                messages: viewModel.starredMessages,
                currentUserId: viewModel.currentUserId,
                otherParticipantName: otherParticipantDisplayName,
                onSelect: { messageId in
                    pendingJumpMessageId = messageId
                    viewModel.showStarredMessages = false
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
            messages: viewModel.sharedGalleryMessages.filter { !$0.isDeleted },
            currentUserId: viewModel.currentUserId,
            scope: .conversationShared,
            presentation: .pushed,
            initialTab: viewModel.sharedGalleryInitialTab,
            onClose: {
                viewModel.showSharedGallery = false
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

    // MARK: - Header (ver ConversationSettingsHeroHeader)

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

    // MARK: - Starred Messages Count Helper
    private var starredMessagesCountLabel: String {
        let count = viewModel.starredMessages.count
        if count == 0 {
            return NSLocalizedString("conversationSettings.starredMessages.none", comment: "")
        }
        return "\(count)"
    }

    private var vanishModeDetailLabel: String {
        if !viewModel.vanishModeActive {
            return NSLocalizedString("conversationSettings.vanish.no", value: "No", comment: "")
        }
        return NSLocalizedString(viewModel.vanishMessageTimer.localizationKey, comment: "")
    }

    // MARK: - Settings List
    private var settingsListSection: some View {
        VStack(spacing: 0) {
            // Starred messages row
            Button {
                HapticManager.shared.lightImpact()
                viewModel.showStarredMessages = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "star")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary)
                        .frame(width: 24)

                    Text(NSLocalizedString("conversationSettings.starredMessages", comment: ""))
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundStyle(adaptiveColors.primary)

                    Spacer()

                    Text(starredMessagesCountLabel)
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(adaptiveColors.tertiary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(adaptiveColors.tertiary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPressSubtle)

            dividerLine.padding(.leading, 38)

            // Mensajes temporales row
            Button {
                HapticManager.shared.lightImpact()
                showVanishPreferences = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary)
                        .frame(width: 24)

                    Text(NSLocalizedString("conversationSettings.vanish.title", value: "Mensajes temporales", comment: ""))
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundStyle(adaptiveColors.primary)

                    Spacer()

                    Text(vanishModeDetailLabel)
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(adaptiveColors.tertiary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(adaptiveColors.tertiary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPressSubtle)

            dividerLine.padding(.leading, 38)

            // Chat preferences row
            Button {
                HapticManager.shared.lightImpact()
                showChatPreferences = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.preferences", comment: "Chat preferences"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                            .foregroundStyle(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.preferences.desc", comment: "Notifications, previews, privacy"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(adaptiveColors.tertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(adaptiveColors.tertiary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPressSubtle)

            dividerLine.padding(.leading, 38)

            // Media storage usage row
            Button {
                HapticManager.shared.lightImpact()
                viewModel.openSharedGallery(tab: .media)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "folder")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("conversationSettings.storage.mediaUsage", comment: "Media in this chat"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                            .foregroundStyle(adaptiveColors.primary)
                        Text(NSLocalizedString("conversationSettings.storage.mediaUsage.desc", comment: "Cached photos and videos on this device"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(adaptiveColors.tertiary)
                    }

                    Spacer()

                    Text(formatBytes(conversationMediaBytes))
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(adaptiveColors.secondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(adaptiveColors.tertiary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPressSubtle)

            if conversationMediaBytes > 0 {
                dividerLine.padding(.leading, 38)

                // Clear storage cache row
                Button {
                    showClearMediaConfirmation = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.red)
                            .frame(width: 24)

                        Text(NSLocalizedString("conversationSettings.storage.clearMedia", comment: "Clear cached media"))
                            .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                            .foregroundStyle(.red)

                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.momentsPressSubtle)
            }
        }
        .confirmationDialog(
            NSLocalizedString("conversationSettings.storage.clearMedia.title", comment: "Clear media confirmation"),
            isPresented: $showClearMediaConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("conversationSettings.storage.clearMedia", comment: "Clear cached media"), role: .destructive) {
                clearConversationMedia()
            }
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("conversationSettings.storage.clearMedia.message", comment: "Media will re-download when needed"))
        }
    }

    // MARK: - Footer
    private var settingsFooter: some View {
        VStack(spacing: 4) {
            let sentCount = viewModel.sentMessagesCount
            let receivedCount = viewModel.receivedMessagesCount
            let sentText = NSLocalizedString("conversationSettings.messages.sent", value: "enviados", comment: "")
            let receivedText = NSLocalizedString("conversationSettings.messages.received", value: "recibidos", comment: "")
            
            Text("\(NSLocalizedString("conversationSettings.created", comment: "")): \(viewModel.conversationCreatedDate)  •  \(NSLocalizedString("conversationSettings.messages", comment: "")): \(viewModel.totalMessages) (\(sentCount) \(sentText), \(receivedCount) \(receivedText))")
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(adaptiveColors.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared Content Tabs (Media / Links) — segmented control nativo
    private var sharedContentTabsSection: some View {
        VStack(spacing: 16) {
            Picker("", selection: $sharedTab) {
                Text(NSLocalizedString("chat.gallery.tab.media", comment: "Media"))
                    .tag(SharedContentTab.media)
                Text(NSLocalizedString("chat.gallery.tab.links", comment: "Links"))
                    .tag(SharedContentTab.links)
            }
            .pickerStyle(.segmented)
            .tint(ProfilePillTabPalette.selectedThumbTint(for: colorScheme))
            .frame(width: 200, height: 32)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onChange(of: sharedTab) { _, _ in
                HapticManager.shared.selection()
            }

            Group {
                switch sharedTab {
                case .media: sharedMediaGrid
                case .links: sharedLinksList
                }
            }
        }
    }

    @ViewBuilder
    private var sharedMediaGrid: some View {
        if viewModel.sharedMedia.isEmpty {
            sharedEmptyState(icon: "photo.on.rectangle.angled", textKey: "conversationSettings.sharedContent.empty.media")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(viewModel.sharedMedia, id: \.id) { media in
                    SharedMediaThumbnail(media: media, fillsGrid: true) {
                        HapticManager.shared.lightImpact()
                        viewModel.selectedMedia = media
                        viewModel.showFullScreenMedia = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sharedLinksList: some View {
        if viewModel.sharedLinkMessages.isEmpty {
            sharedEmptyState(icon: "link", textKey: "conversationSettings.sharedContent.empty.links")
        } else {
            VStack(spacing: 12) {
                ForEach(viewModel.sharedLinkMessages, id: \.id) { message in
                    if let url = ChatLinkOpener.firstURL(in: message.content ?? "") {
                        LinkPreviewCard(url: url, embedded: true)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(adaptiveColors.tertiary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func sharedEmptyState(icon: String, textKey: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(adaptiveColors.tertiary.opacity(0.6))
            Text(NSLocalizedString(textKey, comment: ""))
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(adaptiveColors.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 36)
        .momentsEmptyStateAppear()
    }

    private func refreshMediaUsage() {
        guard let conversationId = conversation.id else { return }
        conversationMediaBytes = ChatCacheStore.bytes(for: conversationId)
    }

    private func clearConversationMedia() {
        guard let conversationId = conversation.id else { return }
        HapticManager.shared.mediumImpact()
        ChatCacheStore.deleteConversation(conversationId, messageIds: [])
        refreshMediaUsage()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
            .foregroundStyle(adaptiveColors.primary)
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
struct ConversationSettingsNavigationRow: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let detail: String
    let adaptiveColors: AdaptiveColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(adaptiveColors.secondary)
                    .frame(width: 22)

                Text(titleKey)
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(adaptiveColors.primary)

                Spacer()

                Text(detail)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(adaptiveColors.tertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(adaptiveColors.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPressSubtle)
    }
}

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
                .foregroundStyle(adaptiveColors.secondary)

            Text(title)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(adaptiveColors.secondary)

            Spacer()

            Text(value)
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)
        }
    }
}

struct SharedMediaThumbnail: View {
    let media: SharedMedia
    /// `true` → celda cuadrada que rellena la columna del grid, sin esquinas ni sombra (estilo perfil).
    var fillsGrid: Bool = false
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
        if fillsGrid {
            gridCell
        } else {
            roundedThumbnail
        }
    }

    /// Celda edge-to-edge para el grid tipo perfil.
    private var gridCell: some View {
        Color(colorScheme == .dark ? .white : .black).opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                KFImage(displayThumbnailUrl.flatMap { URL(string: $0) })
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
            .task { await resolveVideoThumbnailIfNeeded() }
            .overlay(alignment: .bottomLeading) {
                if media.type == .video {
                    ChatVideoPlayBadge(size: 16, padding: 6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(NSLocalizedString(
                media.type == .video ? "chat.a11y.video" : "chat.a11y.photo",
                comment: "Media type"
            )))
            .accessibilityHint(Text(NSLocalizedString("chat.a11y.openMedia", comment: "Open media")))
            .accessibilityAddTraits(.isButton)
    }

    private var roundedThumbnail: some View {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(NSLocalizedString(
                media.type == .video ? "chat.a11y.video" : "chat.a11y.photo",
                comment: "Media type"
            )))
            .accessibilityHint(Text(NSLocalizedString("chat.a11y.openMedia", comment: "Open media")))
            .accessibilityAddTraits(.isButton)
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
    @Published var sentMessagesCount = 0
    @Published var receivedMessagesCount = 0
    @Published var vanishModeActive = false
    @Published var vanishMessageTimer: VanishMessageTimer = .hours24
    @Published var sharedMedia: [SharedMedia] = []
    @Published var sharedGalleryMessages: [EnhancedMessage] = []
    @Published var sharedLinksCount = 0

    /// Mensajes de texto que contienen un enlace (para la pestaña de enlaces).
    var sharedLinkMessages: [EnhancedMessage] {
        sharedGalleryMessages.filter {
            $0.type == .text && ChatLinkOpener.containsLink(in: $0.content ?? "")
        }
    }
    @Published var starredMessages: [EnhancedMessage] = []
    @Published var showSharedGallery = false
    @Published var sharedGalleryInitialTab: ClusterGalleryTab = .media
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

    var sharedMediaCountLabel: String {
        let count = sharedMedia.count
        return count == 0
            ? NSLocalizedString("conversationSettings.count.none", comment: "")
            : "\(count)"
    }

    var sharedLinksCountLabel: String {
        sharedLinksCount == 0
            ? NSLocalizedString("conversationSettings.count.none", comment: "")
            : "\(sharedLinksCount)"
    }

    func openSharedGallery(tab: ClusterGalleryTab) {
        sharedGalleryInitialTab = tab
        showSharedGallery = true
    }

    private var isLoaded = false

    func loadConversationData(conversation: Conversation) {
        guard !isLoaded else { return }
        isLoaded = true
        currentConversation = conversation
        forwardingEnabled = conversation.forwardingPreferences?[currentUserId] ?? true
        vanishModeActive = conversation.vanishModeActive ?? false
        vanishMessageTimer = VanishMessageTimer(storedValue: conversation.vanishMessageTimer)
        loadPrivacySettings()
        guard let conversationId = conversation.id else { return }

        // Local-first: pintar al instante con lo que ya hay sincronizado en disco,
        // igual que el chat principal. Sin esto, la pantalla siempre esperaba un
        // round-trip a Firestore aunque los mensajes ya estuvieran cacheados.
        let cachedMessages = LocalPersistenceService.shared.loadMessagesFast(conversationId: conversationId)
        if !cachedMessages.isEmpty {
            processMessages(cachedMessages)
        }

        // Refresco en segundo plano: delta por cursor en vez de re-pedir 300 mensajes
        // (con su hidratación y descifrado) cada vez que se abre la pantalla. El
        // catch-up trae solo lo que falte al cache y aquí se recuenta desde disco.
        Task { [weak self] in
            await MessageCatchUpService.shared.sync(conversationId: conversationId)
            guard let self else { return }
            let refreshed = LocalPersistenceService.shared.loadMessagesFast(conversationId: conversationId)
            if !refreshed.isEmpty {
                self.processMessages(refreshed)
            }
        }

        // Formatear fecha de creación
        conversationCreatedDate = MomentsFormat.smartDate(from: conversation.timestamp, context: .mediumDate)
    }

    private func processMessages(_ messages: [EnhancedMessage]) {
        totalMessages = messages.count

        let activeMessages = messages.filter { !$0.isDeleted }
        sentMessagesCount = activeMessages.filter { $0.senderId == currentUserId }.count
        receivedMessagesCount = activeMessages.filter { $0.senderId != currentUserId }.count

        let galleryMessages = messages
            .filter(isSharedGalleryEligible)
            .sorted { $0.timestamp > $1.timestamp }

        sharedGalleryMessages = galleryMessages
        sharedLinksCount = galleryMessages.filter {
            $0.type == .text && ChatLinkOpener.containsLink(in: $0.content ?? "")
        }.count

        let mediaMessages = galleryMessages.filter(isSharedMediaItem)
        sharedMedia = mediaMessages.compactMap(makeSharedMedia)

        starredMessages = messages
            .filter { !$0.isDeleted && $0.isStarred(by: currentUserId) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func isSharedGalleryEligible(_ message: EnhancedMessage) -> Bool {
        guard !message.isDeleted else { return false }
        if message.type == .text, let content = message.content, ChatLinkOpener.containsLink(in: content) { return true }
        return isSharedMediaItem(message)
    }

    private func isSharedMediaItem(_ message: EnhancedMessage) -> Bool {
        guard message.type == .image || message.type == .video else { return false }
        guard !message.isViewOnce && message.type != .ephemeral && message.storyReplyData == nil else { return false }
        guard message.isVanishModeMessage != true else { return false }
        if message.mediaUrl != nil { return true }
        if message.mediaObjectPath != nil, message.mediaEncryption != nil { return true }
        return message.thumbnailUrl != nil && message.thumbnailObjectPath != nil
    }

    func makeSharedMedia(from message: EnhancedMessage) -> SharedMedia? {
        // Si el archivo descifrado ya vive en disco (prefetch o visto antes en el chat),
        // usar esa ruta local en vez de esperar a que el mensaje traiga una URL remota.
        let cached = ChatCacheStore.localURLsIfPresent(for: message)
        let mediaUrl = cached.mediaUrl ?? message.mediaUrl ?? cached.thumbnailUrl ?? message.thumbnailUrl
        guard let mediaUrl else { return nil }

        return SharedMedia(
            id: message.id,
            type: message.type == .image ? .image : .video,
            thumbnailUrl: cached.thumbnailUrl ?? message.thumbnailUrl ?? mediaUrl,
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
        let items = sharedGalleryMessages.compactMap(sharedMedia(from:))
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

        sharedGalleryMessages.removeAll { $0.id == message.id }
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

        sharedGalleryMessages.removeAll { $0.id == message.id }
        sharedMedia.removeAll { $0.id == message.id }
        recomputeSharedMediaCounts()

        chatService.deleteMessageWithCleanup(
            conversationId: conversationId,
            messageId: message.id
        ) { _ in }
    }

    private func recomputeSharedMediaCounts() {
        sharedLinksCount = sharedGalleryMessages.filter {
            $0.type == .text && ChatLinkOpener.containsLink(in: $0.content ?? "")
        }.count
        sharedMedia = sharedGalleryMessages.filter(isSharedMediaItem).compactMap(makeSharedMedia)
    }

    private func updateGalleryMessage(_ updated: EnhancedMessage) {
        guard let index = sharedGalleryMessages.firstIndex(where: { $0.id == updated.id }) else { return }
        sharedGalleryMessages[index] = updated
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
                          var updated = self.sharedGalleryMessages.first(where: { $0.id == message.id }) else {
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
                      var updated = self.sharedGalleryMessages.first(where: { $0.id == message.id }) else {
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
                      var updated = self.sharedGalleryMessages.first(where: { $0.id == message.id }) else {
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
                var updated = self.sharedGalleryMessages.first(where: { $0.id == message.id }) ?? message
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

    func updateVanishSettings(active: Bool, timer: VanishMessageTimer) {
        guard let conversationId = currentConversation?.id else { return }
        
        chatService.setVanishMode(
            conversationId: conversationId,
            active: active,
            userId: currentUserId,
            timer: active ? timer : nil
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil {
                    self.vanishModeActive = active
                    self.vanishMessageTimer = timer
                    self.currentConversation?.vanishModeActive = active
                    self.currentConversation?.vanishMessageTimer = timer.rawValue
                    
                    NotificationCenter.default.post(
                        name: .conversationVanishModeDidChange,
                        object: nil,
                        userInfo: [
                            "conversationId": conversationId,
                            "vanishModeActive": active
                        ]
                    )
                    
                    if active {
                        if let disabledNoticeId = self.currentConversation?.vanishDisabledNoticeMessageId {
                            self.currentConversation?.vanishDisabledNoticeMessageId = nil
                            self.chatService.clearVanishDisabledNoticeMessageId(conversationId: conversationId)
                            self.chatService.deleteMessage(conversationId: conversationId, messageId: disabledNoticeId) { _ in }
                        }
                        
                        if let enabledNoticeId = self.currentConversation?.vanishSettingsNoticeMessageId {
                            self.chatService.updateChatNotice(
                                conversationId: conversationId,
                                messageId: enabledNoticeId,
                                noticeKey: timer.enabledNoticeToken
                            )
                        } else {
                            self.chatService.sendChatNotice(
                                conversationId: conversationId,
                                senderId: self.currentUserId,
                                noticeKey: timer.enabledNoticeToken
                            ) { messageId, _ in
                                if let messageId {
                                    self.currentConversation?.vanishSettingsNoticeMessageId = messageId
                                    self.chatService.setVanishSettingsNoticeMessageId(
                                        conversationId: conversationId,
                                        messageId: messageId
                                    )
                                }
                            }
                        }
                    } else {
                        if let enabledNoticeId = self.currentConversation?.vanishSettingsNoticeMessageId {
                            self.currentConversation?.vanishSettingsNoticeMessageId = nil
                            self.chatService.clearVanishSettingsNoticeMessageId(conversationId: conversationId)
                            self.chatService.deleteMessage(conversationId: conversationId, messageId: enabledNoticeId) { _ in }
                        }
                        
                        self.chatService.sendChatNotice(
                            conversationId: conversationId,
                            senderId: self.currentUserId,
                            noticeKey: VanishMessageTimer.disabledNoticeToken
                        ) { messageId, _ in
                            if let messageId {
                                self.currentConversation?.vanishDisabledNoticeMessageId = messageId
                                self.chatService.setVanishDisabledNoticeMessageId(
                                    conversationId: conversationId,
                                    messageId: messageId
                                )
                            }
                        }
                    }
                }
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
                        .foregroundStyle(adaptiveColors.primary)
                        .frame(width: 38, height: 38)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }

                Spacer()

                Text(NSLocalizedString("conversationSettings.starredMessages", comment: ""))
                    .font(.system(size: legacyPoppinsSize(22), weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)

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
                        .foregroundStyle(adaptiveColors.tertiary)
                    Text(NSLocalizedString("conversationSettings.starredMessages.empty", comment: ""))
                        .font(.system(size: legacyPoppinsSize(15)))
                        .foregroundStyle(adaptiveColors.tertiary)
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
                            .foregroundStyle(adaptiveColors.primary)
                        Spacer()
                        Text(relativeDate)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(adaptiveColors.tertiary)
                    }

                    Text(previewText)
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(adaptiveColors.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPressSubtle)
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
                    .foregroundStyle(color)
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
    @StateObject private var photosSaveGate = PermissionPrimerGate(.photosSave)
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

    private func isScreenshotProtectedMedia(_ item: SharedMedia) -> Bool {
        item.sourceMessage?.isVanishModeMessage == true
            || item.sourceMessage?.type == .ephemeral
            || !item.allowsSaving
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
        .alert("conversationSettings.mediaSave.title", isPresented: $showSaveResult) {
            Button("common.ok") { }
        } message: {
            Text(saveResultMessage)
        }
        .permissionPrimerGate(photosSaveGate)
        .onChange(of: selectedIndex) { _, _ in
            videoCurrentTime = 0
            videoDuration = 0
            isVideoPaused = false
            showingReactionBarForMessageId = nil
            restartEphemeralCountdownIfNeeded()
        }
        .onAppear {
            GlobalVideoManager.shared.pauseAllVideos()
            restartEphemeralCountdownIfNeeded()
        }
        .onDisappear {
            stopEphemeralCountdown()
        }
        .onChange(of: showExpandedVideo) { _, isShown in
            if !isShown {
                expandedVideoURL = nil
            } else if isScreenshotProtectedMedia(currentMedia) {
                // No permitir modal nativo fuera del entorno protegido.
                showExpandedVideo = false
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

        let mediaBody = Group {
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
                        .foregroundStyle(primaryOverlayColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }

        Group {
            if isScreenshotProtectedMedia(item) {
                ScreenshotProtectedView(isProtected: true, fillsContainer: true) {
                    mediaBody
                }
            } else {
                mediaBody
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
                    .foregroundStyle(primaryOverlayColor)
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
                    .foregroundStyle(ephemeralAccentColor)
                    .lineLimit(1)
                } else {
                    Text(relativeTime)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(secondaryOverlayColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if currentMedia.allowsSaving {
                ProfileChromeIconButton(
                    systemName: "arrow.down",
                    foregroundColor: primaryOverlayColor,
                    preset: .toolbarAction,
                    action: { photosSaveGate.requestAccess { saveMedia() } }
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
                .foregroundStyle(primaryOverlayColor)
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
                        .foregroundStyle(canSendReply ? primaryOverlayColor : primaryOverlayColor.opacity(0.32))
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
                    .foregroundStyle(primaryOverlayColor)
                    .frame(width: 64, height: 64)
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                    .padding(60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.momentsPressSubtle)

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
                                .foregroundStyle(primaryOverlayColor)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.momentsPressSubtle)

                        // Expand nativo (AVPlayerViewController) sale de ScreenshotProtectedView.
                        // Solo media normal; protegida (vanish/ephemeral/no-save) se queda en el overlay seguro.
                        if !isScreenshotProtectedMedia(currentMedia) {
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
                                    .foregroundStyle(primaryOverlayColor)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.momentsPressSubtle)
                        }
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
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
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
            // Defensa: no presentar modal nativo si el media actual es protegido.
            // El botón expand ya se oculta; esto cubre races / estados residuales.
            let playerController = ModalVideoPlayerController()
            
            playerController.player = player
            playerController.showsPlaybackControls = true
            // Deployment target ≥ iOS 18.6.
            playerController.allowsPictureInPicturePlayback = false
            playerController.canStartPictureInPictureAutomaticallyFromInline = false
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

// MARK: - Chat Preferences (pantalla dedicada con los toggles)
struct ConversationChatPreferencesView: View {
    @ObservedObject var viewModel: ConversationSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showClearConfirm = false

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("conversationSettings.preferences.group.notifications")

                    toggleRow(
                        title: "conversationSettings.privacy.buzz.title",
                        desc: "conversationSettings.privacy.buzz.description",
                        isOn: $viewModel.buzzEnabled
                    ) { viewModel.toggleBuzzNotifications() }

                    dividerLine

                    toggleRow(
                        title: "conversationSettings.privacy.messagePreview.title",
                        desc: "conversationSettings.privacy.messagePreview.description",
                        isOn: $viewModel.messagePreviewEnabled
                    ) { viewModel.toggleMessagePreview() }
                }

                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("conversationSettings.preferences.group.privacy")

                    toggleRow(
                        title: "conversationSettings.privacy.readReceipts.title",
                        desc: "conversationSettings.privacy.readReceipts.description",
                        isOn: $viewModel.readReceiptsEnabled
                    ) { viewModel.toggleReadReceipts() }

                    dividerLine

                    toggleRow(
                        title: "conversationSettings.typingIndicator",
                        desc: "conversationSettings.typingIndicator.desc",
                        isOn: $viewModel.typingIndicatorEnabled
                    ) { viewModel.toggleTypingIndicator() }

                    dividerLine

                    toggleRow(
                        title: "conversationSettings.privacy.forwarding.title",
                        desc: "conversationSettings.privacy.forwarding.description",
                        isOn: $viewModel.forwardingEnabled
                    ) { viewModel.toggleForwarding() }
                }

                destructiveRow(
                    icon: "trash",
                    title: "conversationSettings.clearConversation"
                ) { showClearConfirm = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background {
            Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6").ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .chatInteractivePopEnabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .momentsScrollEdgeChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("conversationSettings.preferences", comment: "Chat preferences"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
            }
        }
        .confirmationDialog(
            NSLocalizedString("conversationSettings.clearConversation", comment: ""),
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("conversationSettings.clearConversation", comment: ""), role: .destructive) {
                HapticManager.shared.mediumImpact()
                viewModel.clearConversation()
                dismiss()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        }
        .chatInteractivePopEnabled()
    }

    private func destructiveRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 28)

                Text(NSLocalizedString(title, comment: ""))
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundStyle(.red)

                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPressSubtle)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
            .foregroundStyle(adaptiveColors.secondary)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(adaptiveColors.tertiary.opacity(colorScheme == .dark ? 0.16 : 0.12))
            .frame(height: 0.5)
    }

    private func toggleRow(
        title: String,
        desc: String,
        isOn: Binding<Bool>,
        onToggle: @escaping () -> Void
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(title, comment: ""))
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(adaptiveColors.primary)
                Text(NSLocalizedString(desc, comment: ""))
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(adaptiveColors.tertiary)
            }
        }
        .tint(SettingsProfileColors.toggleTint)
        .onChange(of: isOn.wrappedValue) { _, _ in
            HapticManager.shared.lightImpact()
            onToggle()
        }
    }

}

// MARK: - Conversation Vanish Mode View
struct ConversationVanishModeView: View {
    @ObservedObject var viewModel: ConversationSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 0) {
                    timerOptionRow(
                        title: NSLocalizedString("conversationSettings.vanish.no", value: "No", comment: ""),
                        isSelected: !viewModel.vanishModeActive
                    ) {
                        viewModel.updateVanishSettings(active: false, timer: viewModel.vanishMessageTimer)
                    }

                    dividerLine

                    timerOptionRow(
                        title: NSLocalizedString("chat.vanish.timer.onceSeen", comment: ""),
                        isSelected: viewModel.vanishModeActive && viewModel.vanishMessageTimer == .onceSeen
                    ) {
                        viewModel.updateVanishSettings(active: true, timer: .onceSeen)
                    }

                    dividerLine

                    timerOptionRow(
                        title: NSLocalizedString("chat.vanish.timer.24h", comment: ""),
                        isSelected: viewModel.vanishModeActive && viewModel.vanishMessageTimer == .hours24
                    ) {
                        viewModel.updateVanishSettings(active: true, timer: .hours24)
                    }

                    dividerLine

                    timerOptionRow(
                        title: NSLocalizedString("chat.vanish.timer.7d", comment: ""),
                        isSelected: viewModel.vanishModeActive && viewModel.vanishMessageTimer == .days7
                    ) {
                        viewModel.updateVanishSettings(active: true, timer: .days7)
                    }
                }

                let descriptionText = NSLocalizedString("conversationSettings.vanish.description", value: "Elige cuánto tiempo permanecen visibles tus mensajes y reacciones en el chat. Puedes hacer que desaparezcan justo después de leerse y cerrar la conversación, o conservarlos hasta 7 días. Por tu privacidad, se enviará una notificación al chat si alguien hace una captura o graba la pantalla.", comment: "")
                
                Text(descriptionText)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(adaptiveColors.tertiary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 16)
        }
        .background {
            Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6").ignoresSafeArea()
        }
        .navigationTitle(NSLocalizedString("conversationSettings.vanish.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .momentsScrollEdgeChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
        .chatInteractivePopEnabled()
    }

    private func timerOptionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            HStack {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(16), weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? adaptiveColors.primary : adaptiveColors.secondary)
                
                Spacer()
                
                Circle()
                    .strokeBorder(isSelected ? adaptiveColors.primary : adaptiveColors.tertiary.opacity(0.5), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(isSelected ? adaptiveColors.primary : Color.clear)
                            .padding(4)
                    )
                    .frame(width: 22, height: 22)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPressSubtle)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(adaptiveColors.tertiary.opacity(colorScheme == .dark ? 0.16 : 0.12))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}

/// Oculta el scroll edge effect superior solo en hero grande.
private struct ConversationSettingsScrollEdgeModifier: ViewModifier {
    let isLargeHeader: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), isLargeHeader {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

/// Chrome de scroll edge Moments solo en estado compacto (layout original).
private struct ConversationSettingsCompactChromeModifier: ViewModifier {
    let isLargeHeader: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isLargeHeader {
            content
        } else {
            content.momentsScrollEdgeChrome()
        }
    }
}
