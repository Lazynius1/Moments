import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

private struct ChatStoryRoute: Identifiable {
    enum Presentation {
        case userStories(userId: String)
        case sharedStory(story: Story)
    }

    let id: String
    let presentation: Presentation

    init(userId: String) {
        self.id = userId
        self.presentation = .userStories(userId: userId)
    }

    init(story: Story) {
        self.id = story.id ?? UUID().uuidString
        self.presentation = .sharedStory(story: story)
    }
}

// MARK: - Glassmorphic Chat View
// Actualizar GlassmorphicChatView para incluir navegación
struct GlassmorphicChatView: View {
    @ObservedObject private var session: ConversationChatSession
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var messageText: String = ""
    @State private var showEnhancedCamera = false
    @State private var activeAttachmentSheet: ChatAttachmentSheetKind?
    @State private var plusButtonAnchorFrame: CGRect = .zero
    @State private var replyingTo: EnhancedMessage?
    @State private var clusterForReply: [EnhancedMessage]? = nil // ✅ New: Selection grid for clusters
    @State private var clusterForGallery: [EnhancedMessage]? = nil // Galería de selección al abrir un álbum
    @State private var editingMessage: EnhancedMessage?
    @State private var messageMenuSelection: ChatMessageMenuSelection? = nil
    @State private var showingReactionEmojiPicker = false
    @State private var reactionPickerMessage: EnhancedMessage?
    @State private var forwardingMessage: EnhancedMessage?
    @State private var showCameraSheet = false
    @State private var isRecordingVoice = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var showingConversationSettings = false
    @State private var showingReportSheet = false
    @State private var flashingMessageIds: Set<String> = []
    @State private var pendingReactionHighlightIds: Set<String> = []
    @State private var notificationOpenIntent: ChatNavigationIntentStore.OpenIntent?
    @State private var didProcessNotificationBuzz = false
    @State private var isPinnedToBottom = true
    @State private var pendingIncomingMessages = 0
    @State private var unreadDividerMessageId: String? = nil
    @State private var unreadDividerInitialized = false
    @State private var hasCompletedInitialScroll = false
    @State private var suppressPinnedMetricsUpdates = false
    @State private var didReapplyFrozenScrollPosition = false
    @State private var didHydrateScrollStateOnce = false
    @State private var missingFrozenAnchorLayoutPasses = 0
    @State private var initialScrollTask: Task<Void, Never>? = nil
    @State private var highlightScrollTask: Task<Void, Never>? = nil
    @State private var frozenInitialScrollTarget: ChatScrollTarget? = nil
    @State private var scrollContentOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var scrollMetricsBuffer = ChatScrollMetricsBuffer()
    @State private var messageRowFrames: [String: CGRect] = [:]
    @State private var liveScrollAnchorRowId: String?
    @State private var bottomSnapTask: Task<Void, Never>? = nil
    private let bottomScrollAnchorID = "chat-bottom-anchor"
    @State private var isSearchVisible = false
    @State private var searchQuery: String = ""
    @State private var searchMatchIds: [String] = []
    @State private var currentSearchMatchIndex: Int = 0
    @State private var pendingSearchTargetId: String? = nil
    @State private var buzzShakeProgress: CGFloat = 1
    @State private var buzzShakeAmplitude: CGFloat = 18
    @State private var buzzToastText: String?
    @State private var buzzToastDismissTask: Task<Void, Never>?
    @State private var lastBuzzSentAt: Date?
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let privacyService = PrivacyService()
    private let firestoreService = FirestoreService()

    // ✅ NUEVO: Estados para navegación al perfil
    @State private var showingUserProfile = false
    @Namespace private var profileZoomNamespace
    @State private var navigateToProfile = false

    // ✅ NUEVO: Estados para navegación al momento
    @State private var showingMomentDetail = false
    @State private var selectedMoment: Moment?
    @State private var showingMomentError = false
    @State private var showingStoryUnavailable = false
    @State private var storyUnavailableReason: SharedStoryAccessDenialReason?

    // ✅ Ruta estable para presentar historias (header del chat o historia compartida en mensaje)
    @State private var storyRoute: ChatStoryRoute?

    // ✅ HISTORIAS: Estados para anillo de historias
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    @State private var storyCount: Int = 0
    @State private var storyViewedStatus: [Bool] = []
    @State private var storyAudiences: [String?] = []
    @State private var liveOtherParticipantUsername: String = ""
    @State private var isOtherParticipantUnavailable: Bool = false
    @State private var isOtherParticipantBlockedByCurrentUser: Bool = false

    // ✅ REACCIONES: Nuevo estado para Overlay
    @State private var reactionMessageOverlay: EnhancedMessage? = nil
    @State private var selectedChatMedia: SharedMedia?
    @State private var selectedChatMediaItems: [SharedMedia] = []

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var otherParticipantDisplayName: String {
        let fallback = viewModel.conversation.otherParticipantUsername ?? "Usuario"
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    private var searchCounterText: String {
        guard !searchMatchIds.isEmpty else { return "0/0" }
        let current = min(max(currentSearchMatchIndex + 1, 1), searchMatchIds.count)
        return "\(current)/\(searchMatchIds.count)"
    }

    private var attachmentPickerSheetBinding: Binding<ChatAttachmentSheetKind?> {
        Binding(
            get: {
                guard let sheet = activeAttachmentSheet, sheet.isPickerSheet else { return nil }
                return sheet
            },
            set: { activeAttachmentSheet = $0 }
        )
    }

    private var viewModel: ConversationChatSession { session }

    private var conversationId: String {
        viewModel.conversation.id ?? ""
    }

    private var quickReactionEmoji: String { "❤️" }

    init(conversation: Conversation, session: ConversationChatSession? = nil) {
        let resolved = session ?? ChatSessionEngine.shared.session(for: conversation)
        let conversationId = conversation.id ?? ""
        let stored = ChatScrollStateStore.state(for: conversationId)
        _session = ObservedObject(wrappedValue: resolved)
        _messageText = State(initialValue: ChatDraftStore.shared.draft(for: conversationId))
        _hasCompletedInitialScroll = State(initialValue: stored.hasCompletedInitialScroll)
        _isPinnedToBottom = State(initialValue: stored.isPinnedToBottom)
        if let anchor = stored.scrollAnchorId, anchor != "chat-bottom-anchor" {
            _liveScrollAnchorRowId = State(initialValue: anchor)
        }
        _suppressPinnedMetricsUpdates = State(
            initialValue: stored.hasCompletedInitialScroll && !stored.isPinnedToBottom
        )
        _didReapplyFrozenScrollPosition = State(initialValue: false)
    }

    // ✅ REFACTOR: Dividido en variables separadas para evitar el error del compilador (timeout AST)
    private var baseChatView: some View {
        chatRootContent
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar { chatToolbarContent }
        .fullScreenCover(isPresented: $showEnhancedCamera) {
            EnhancedCameraPickerView { data, mediaType, isEphemeral in
                handleCameraCapture(data: data, mediaType: mediaType, isEphemeral: isEphemeral)
            }
        }
        .onChange(of: activeAttachmentSheet) { _, newValue in
            guard newValue != nil else { return }
            isTextFieldFocused = false
        }
        .onChange(of: messageText) { _, newValue in
            guard editingMessage == nil else { return }
            ChatDraftStore.shared.setDraft(newValue, for: conversationId)
        }
    }

    private var chatViewWithSettingsAndStories: some View {
        baseChatView
            .fullScreenCover(isPresented: $showingConversationSettings, onDismiss: {
                viewModel.refreshTypingIndicatorPreference()
                viewModel.refreshForwardingPreference()
            }) {
                ConversationSettingsView(
                    conversation: viewModel.conversation,
                    onJumpToMessage: { messageId in
                        pendingSearchTargetId = messageId
                    }
                )
            }
            .sheet(isPresented: $showingReportSheet) {
                ReportBottomSheet(
                    userId: viewModel.conversation.otherParticipantId,
                    username: otherParticipantDisplayName
                )
            }
            // ✅ NUEVO: Sheet para mostrar historias del usuario
            .fullScreenCover(item: $storyRoute) { route in
                switch route.presentation {
                case .userStories(let userId):
                    StoriesView(startWithUserId: .constant(userId))
                case .sharedStory(let story):
                    StoriesView(chainStories: [story], startAtIndex: 0)
                }
            }
            // ✅ NUEVO: Sheet para navegación al detalle del momento
            .sheet(isPresented: $showingMomentDetail) {
                if let moment = selectedMoment {
                    MomentDetailContainerView(context: .single(moment))
                }
            }
            // ✅ NUEVO: Alert para error al cargar momento
            .alert("common.error", isPresented: $showingMomentError) {
                Button("common.ok") { }
            } message: {
                Text("chat.moment.loadError")
            }
            .alert("common.error", isPresented: $showingStoryUnavailable) {
                Button("common.ok") { }
            } message: {
                if let reason = storyUnavailableReason {
                    Text(LocalizedStringKey(reason.messageKey))
                } else {
                    Text("share.storyUnavailable")
                }
            }
    }

    var body: some View {
        chatViewWithOverlays
            .toolbar(.visible, for: .navigationBar)
            .navigationBarHidden(false)
            .toolbar(.hidden, for: .tabBar)
    }

    private var chatViewWithInteractionSheets: some View {
        chatViewWithSettingsAndStories
            .navigationDestination(isPresented: $showingUserProfile) {
                UserProfileView(userId: viewModel.conversation.otherParticipantId)
                    .userProfileZoomDestination(
                        userId: viewModel.conversation.otherParticipantId,
                        namespace: profileZoomNamespace
                    )
            }
            .sheet(item: Binding(
                get: { clusterForReply.map { ClusterWrapper(messages: $0) } },
                set: { clusterForReply = $0?.messages }
            )) { wrapper in
                GlassmorphicMediaSelectionSheet(
                    messages: wrapper.messages,
                    onSelect: { selectedMessage in
                        self.activateReply(to: selectedMessage)
                        self.clusterForReply = nil
                    },
                    onCancel: {
                        self.clusterForReply = nil
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: Binding(
                get: { clusterForGallery.map { ClusterWrapper(messages: $0) } },
                set: { clusterForGallery = $0?.messages }
            )) { wrapper in
                clusterGalleryCover(for: wrapper)
            }
            .sheet(isPresented: $showingReactionEmojiPicker, onDismiss: {
                reactionPickerMessage = nil
            }) {
                EmojiPickerView(isPresented: $showingReactionEmojiPicker, onSelect: { emoji in
                    if let message = reactionPickerMessage {
                        viewModel.addReaction(to: message, emoji: emoji)
                    }
                    showingReactionEmojiPicker = false
                })
                .chatPickerSheetPresentation()
            }
            .sheet(item: attachmentPickerSheetBinding) { kind in
                ChatAttachmentPickerSheet(
                    kind: kind,
                    accentColor: adaptiveColors.userAccentColor,
                    onDismiss: { activeAttachmentSheet = nil },
                    onSelectGif: { asset in
                        viewModel.sendGif(from: asset)
                    },
                    onSelectSticker: { asset in
                        viewModel.sendSticker(from: asset)
                    },
                    onSendStaticLocation: { coordinate, name, address in
                        viewModel.sendStaticLocation(coordinate: coordinate, name: name, address: address)
                    },
                    onStartLive: { duration in
                        viewModel.startLiveLocation(duration: duration)
                    }
                )
                .chatPickerSheetPresentation()
            }
            .sheet(item: Binding(
                get: { forwardingMessage.map { ForwardMessageWrapper(message: $0) } },
                set: { forwardingMessage = $0?.message }
            )) { wrapper in
                ChatMessageForwardSheet(
                    message: wrapper.message,
                    onDismiss: { forwardingMessage = nil },
                    onForward: { userIds in
                        viewModel.forwardTextMessage(wrapper.message, toUserIds: userIds)
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    private var chatViewWithLifecycleObservers: some View {
        chatViewWithInteractionSheets
            .onAppear {
                onAppearActions()
                initializeUnreadDividerIfNeeded()
            }
            .onDisappear {
                onDisappearActions()
            }
            .onChange(of: viewModel.messages.map(\.id)) { _, _ in
                initializeUnreadDividerIfNeeded()
                if !hasUnreadIncomingMessages() {
                    unreadDividerMessageId = nil
                }
                if isSearchVisible && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updateSearchMatches()
                }
            }
            .onChange(of: searchQuery) { _, _ in
                updateSearchMatches()
            }
            .onChange(of: viewModel.latestBuzzEvent?.id) { _, _ in
                handleIncomingBuzzToastIfNeeded()
            }
            .onChange(of: messageMenuSelection) { _, newValue in
                if newValue == nil {
                    withAnimation { reactionMessageOverlay = nil }
                }
            }
    }

    private var chatViewWithOverlays: some View {
        chatViewWithLifecycleObservers
            .fullScreenCover(item: $selectedChatMedia) { media in
                selectedChatMediaCover(media: media)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: activeAttachmentSheet)
            .overlay {
                chatAttachmentOverlayContent
            }
    }

    @ViewBuilder
    private func clusterGalleryCover(for wrapper: ClusterWrapper) -> some View {
        ClusterGalleryView(
            messages: wrapper.messages,
            onClose: {
                self.clusterForGallery = nil
            },
            onHydrateMedia: { message in
                viewModel.hydrateMediaIfNeeded(for: message)
            },
            detail: { selectedMessage, dismissDetail in
                if let media = sharedMedia(from: selectedMessage) {
                    FullScreenMediaView(
                        media: media,
                        mediaItems: sharedMediaItemsForOverlay(selecting: selectedMessage),
                        currentUserId: viewModel.currentUserId,
                        otherParticipantName: otherParticipantDisplayName,
                        displayReactions: { messageId in
                            viewModel.displayReactions(for: messageId)
                        },
                        onReaction: { messageId, emoji in
                            guard let message = viewModel.messages.first(where: { $0.id == messageId }) else { return }
                            viewModel.addReaction(to: message, emoji: emoji)
                        },
                        onMoreReactions: { messageId in
                            guard let message = viewModel.messages.first(where: { $0.id == messageId }) else { return }
                            reactionPickerMessage = message
                            showingReactionEmojiPicker = true
                        },
                        onClose: {
                            dismissDetail()
                        },
                        onSendReply: { media, text, completion in
                            sendReplyToSharedMedia(media, text: text, completion: completion)
                        }
                    )
                }
            }
        )
    }

    @ViewBuilder
    private func selectedChatMediaCover(media: SharedMedia) -> some View {
        FullScreenMediaView(
            media: media,
            mediaItems: selectedChatMediaItems,
            currentUserId: viewModel.currentUserId,
            otherParticipantName: otherParticipantDisplayName,
            displayReactions: { messageId in
                viewModel.displayReactions(for: messageId)
            },
            onReaction: { messageId, emoji in
                guard let message = viewModel.messages.first(where: { $0.id == messageId }) else { return }
                viewModel.addReaction(to: message, emoji: emoji)
            },
            onMoreReactions: { messageId in
                guard let message = viewModel.messages.first(where: { $0.id == messageId }) else { return }
                reactionPickerMessage = message
                showingReactionEmojiPicker = true
            },
            onClose: {
                selectedChatMedia = nil
                selectedChatMediaItems = []
            },
            onSendReply: { media, text, completion in
                sendReplyToSharedMedia(media, text: text, completion: completion)
            }
        )
    }

    @ViewBuilder
    private var chatAttachmentOverlayContent: some View {
        if activeAttachmentSheet == .menu {
            ChatAttachmentMenuPopover(
                isPresented: $activeAttachmentSheet,
                anchorFrame: plusButtonAnchorFrame,
                canSendBuzz: viewModel.canSendBuzz,
                onOpenCamera: {
                    showEnhancedCamera = true
                },
                onSendBuzz: {
                    sendBuzzFromAttachmentMenu()
                }
            )
            .transition(.opacity)
            .zIndex(44)
        }

        ChatAttachmentMediaSheetOverlay(
            activeSheet: $activeAttachmentSheet,
            accentColor: adaptiveColors.userAccentColor,
            onPickerItems: { items in
                viewModel.handlePhotoPickerItems(items)
                activeAttachmentSheet = nil
            },
            onConfirmAssets: { assets in
                viewModel.sendSelectedPHAssets(assets) {
                    activeAttachmentSheet = nil
                }
            }
        )
    }

    private func handleIncomingBuzzToastIfNeeded() {
        guard let event = viewModel.latestBuzzEvent,
              event.senderId != viewModel.currentUserId else { return }
        let message = String(
            format: NSLocalizedString("chat.buzz.received", comment: "Incoming buzz toast"),
            otherParticipantDisplayName
        )
        triggerBuzzEffect(text: message, isLocal: false, showsToast: false)
    }

    // MARK: - Toolbar nativo (scroll edge blur del sistema en iOS 26)

    @ToolbarContentBuilder
    private var chatToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            chatToolbarBackButton
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .topBarLeading) {
            Button(action: openProfileOrStoryFromHeader) {
                chatToolbarAvatar
            }
            .buttonStyle(.plain)
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .principal) {
            chatToolbarTitleStack
                .contentShape(Rectangle())
                .onTapGesture {
                    showingUserProfile = true
                }
        }

        ToolbarItem(placement: .topBarTrailing) {
            chatToolbarSearchButton
        }
        .chatHideSharedBackgroundIfAvailable()

        ToolbarItem(placement: .topBarTrailing) {
            chatToolbarMenu
        }
        .chatHideSharedBackgroundIfAvailable()
    }

    private var chatToolbarBackButton: some View {
        ProfileChromeIconButton(
            systemName: "chevron.left",
            foregroundColor: adaptiveColors.primary,
            preset: .navigationBack,
            action: { dismiss() }
        )
    }

    @ViewBuilder
    private var chatToolbarAvatar: some View {
        if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
            ProfileUnavailableAvatar(size: 40)
                .userProfileZoomSource(
                    userId: viewModel.conversation.otherParticipantId,
                    namespace: profileZoomNamespace,
                    cornerRadius: 20
                )
        } else {
            AsyncProfileImageView(userId: viewModel.conversation.otherParticipantId)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .userProfileZoomSource(
                    userId: viewModel.conversation.otherParticipantId,
                    namespace: profileZoomNamespace,
                    cornerRadius: 20
                )
                .overlay(
                    StorySegmentedRing(
                        storyCount: storyCount,
                        hasStory: hasStory,
                        hasUnseenStory: hasUnseenStory,
                        storyViewedStatus: storyViewedStatus,
                        storyAudiences: storyAudiences,
                        isOwnStory: false,
                        colorScheme: colorScheme,
                        ringSize: 40,
                        lineWidth: 2.7
                    )
                )
        }
    }

    private var chatToolbarTitleStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(otherParticipantDisplayName)
                    .font(.system(size: 17, weight: .semibold))
                    .strikethrough(isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser, color: adaptiveColors.secondary)
                    .foregroundStyle(adaptiveColors.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if !isOtherParticipantUnavailable {
                    VerifiedBadgeView(userId: viewModel.conversation.otherParticipantId, size: 14)
                }
            }

            chatToolbarSubtitle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var chatToolbarSubtitle: some View {
        if isOtherParticipantBlockedByCurrentUser {
            Text("chat.blockedByMe.subtitle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        } else if isOtherParticipantUnavailable {
            Text("chat.profileUnavailable")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        } else if !viewModel.typingUsers.isEmpty {
            Text("chat.typing")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        } else if let presence = onlineStatusService.presenceDisplay(
            for: otherUserStatus,
            lastSeen: otherUserLastSeen
        ) {
            HStack(spacing: 4) {
                Image(systemName: presence.status.icon)
                    .foregroundStyle(presence.status.color)
                    .font(.system(size: 7))

                Text(presence.statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(adaptiveColors.secondary)
                    .lineLimit(1)

                if let lastSeenText = presence.supplementalText {
                    Text("• \(lastSeenText)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(adaptiveColors.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
    }

    private var chatToolbarSearchButton: some View {
        ProfileChromeIconButton(
            systemName: isSearchVisible ? "xmark.circle.fill" : "magnifyingglass",
            foregroundColor: adaptiveColors.primary,
            size: MomentsGlassControlMetrics.toolbarControlSize,
            iconSize: 16,
            action: toggleChatSearch
        )
    }

    private var chatToolbarMenu: some View {
        Menu {
            Button(action: { showingConversationSettings = true }) {
                Label(
                    NSLocalizedString("chat.menu.details", comment: "Conversation details"),
                    systemImage: "info.circle"
                )
            }

            Button(role: .destructive, action: { showingReportSheet = true }) {
                Label(
                    NSLocalizedString("report.action.user", comment: "Report user"),
                    systemImage: "flag"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(adaptiveColors.primary)
                .frame(width: 38, height: 38)
                .momentsChromeGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func openProfileOrStoryFromHeader() {
        if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
            showingUserProfile = true
        } else if hasStory && !isOtherParticipantBlockedByCurrentUser {
            storyRoute = ChatStoryRoute(userId: viewModel.conversation.otherParticipantId)
        } else {
            showingUserProfile = true
        }
    }

    private func toggleChatSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSearchVisible.toggle()
        }
        if isSearchVisible {
            searchQuery = ""
            searchMatchIds = []
            currentSearchMatchIndex = 0
            pendingSearchTargetId = nil
        }
    }

    private var chatSearchBarSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(adaptiveColors.secondary.opacity(0.8))
                    .font(.system(size: 14, weight: .medium))

                TextField(LocalizedStringKey("messaging.search.placeholder"), text: $searchQuery)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundColor(adaptiveColors.primary)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchMatchIds = []
                        currentSearchMatchIndex = 0
                        pendingSearchTargetId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(adaptiveColors.secondary.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .momentsChromeGlass(in: Capsule(), interactive: true)

            HStack(spacing: 6) {
                Text(searchCounterText)
                    .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                    .foregroundColor(adaptiveColors.secondary)
                    .frame(minWidth: 38)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .momentsChromeGlass(in: Capsule(), interactive: true)

                Button {
                    moveSearchSelection(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(searchMatchIds.isEmpty ? adaptiveColors.secondary.opacity(0.35) : adaptiveColors.primary)
                        .frame(width: 30, height: 30)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(searchMatchIds.isEmpty)

                Button {
                    moveSearchSelection(by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(searchMatchIds.isEmpty ? adaptiveColors.secondary.opacity(0.35) : adaptiveColors.primary)
                        .frame(width: 30, height: 30)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(searchMatchIds.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // ✅ Lista de mensajes — orden cronológico + anclaje inferior nativo (sin invertir LazyVStack)
    private var messagesListSection: some View {
        ScrollViewReader { proxy in
            applyChatScrollReceivers(
                to: applyChatScrollMessageChanges(
                    to: applyChatScrollInitialHandlers(
                        to: chatMessagesScrollView(proxy: proxy),
                        proxy: proxy
                    ),
                    proxy: proxy
                ),
                proxy: proxy
            )
        }
    }

    @ViewBuilder
    private func chatMessagesLazyStack(proxy: ScrollViewProxy) -> some View {
        LazyVStack(spacing: 2) {
            chatMessagesStackContent(proxy: proxy)
        }
        .padding(.vertical, 10)
        .scrollTargetLayout()
    }

    @ViewBuilder
    private func chatMessagesStackContent(proxy: ScrollViewProxy) -> some View {
            if viewModel.canLoadMore {
                Color.clear
                    .frame(height: 20)
                    .onAppear {
                        guard hasCompletedInitialScroll else { return }
                        viewModel.loadMoreMessages()
                    }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: adaptiveColors.primary))
                    .scaleEffect(0.8)
                    .padding(.vertical, 10)
            }

            ForEach(viewModel.chatRenderRows) { row in
                switch row {
                case .header(let date):
                    GlassmorphicDateHeader(date: date)
                        .padding(.vertical, 10)
                        .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                case .message(let item):
                    if shouldShowUnreadDivider(before: item) {
                        GlassmorphicUnreadDivider()
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                    }
                    renderMessageItem(item, in: viewModel.messages, proxy: proxy)
                        .id(item.id)
                case .buzz(let event):
                    ChatBuzzTimelineEventRow(
                        text: buzzTimelineText(for: event),
                        isOutgoing: event.senderId == viewModel.currentUserId
                    )
                    .id("buzz-\(event.id)")
                    .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                }
            }

            if !viewModel.typingUsers.isEmpty {
                GlassmorphicTypingIndicator()
                    .padding(.horizontal)
                    .id("typing")
                    .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
            }

            Color.clear
                .frame(height: 0)
                .id(bottomScrollAnchorID)
                .onAppear {
                    guard hasCompletedInitialScroll else { return }
                    markBottomAnchorVisible()
                }
                .onChange(of: hasCompletedInitialScroll) { _, completed in
                    guard completed else { return }
                    markBottomAnchorVisible()
                }
    }

    /// Scroll interactivo solo cuando el contenido supera el viewport (métricas reales del ScrollView).
    private var allowsVerticalScrolling: Bool {
        guard scrollViewportHeight > 1, scrollContentHeight > 1 else { return false }
        return scrollContentHeight > scrollViewportHeight + 32
    }

    private func chatMessagesScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            chatMessagesLazyStack(proxy: proxy)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .scrollContentBackground(.hidden)
        .coordinateSpace(name: "chatScroll")
        .chatScrollEdgeEffect()
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: ChatScrollMetrics.self, of: { geometry in
            ChatScrollMetrics(
                offsetY: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                viewportHeight: geometry.containerSize.height
            )
        }) { _, metrics in
            scrollMetricsBuffer.ingest(metrics)
            syncScrollLayoutMetrics(from: metrics)
        }
        .onScrollPhaseChange { _, phase in
            if phase == .idle || phase == .decelerating {
                flushScrollMetricsToUI()
            }
            guard allowsVerticalScrolling else { return }
            guard phase == .idle, hasCompletedInitialScroll else { return }
            if suppressPinnedMetricsUpdates {
                suppressPinnedMetricsUpdates = false
            }
            updateLiveScrollAnchor()
            commitScrollStateToStore()
        }
    }

    private func chatScrollToBottomOverlay(proxy: ScrollViewProxy) -> some View {
        Group {
            if shouldShowScrollToBottomControl {
                Button {
                    scheduleBottomSnap(using: proxy, reason: .userRequested)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 30, weight: .bold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(scrollToBottomAccentColor)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16), radius: 8, x: 0, y: 3)

                        if pendingIncomingMessages > 0, isScrollContentScrollable {
                            Text(pendingIncomingMessages > 99 ? "99+" : "\(pendingIncomingMessages)")
                                .font(.system(size: legacyPoppinsSize(10), weight: .semibold))
                                .foregroundStyle(scrollToBottomBadgeTextColor)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(scrollToBottomAccentColor)
                                .clipShape(Capsule())
                                .offset(x: 7, y: -5)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .padding(.trailing, 14)
                .padding(.bottom, 12)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var shouldShowScrollToBottomControl: Bool {
        pendingIncomingMessages > 0 || (!isPinnedToBottom && isScrollContentScrollable)
    }

    private func markBottomAnchorVisible() {
        pendingIncomingMessages = 0
        guard !isPinnedToBottom else {
            clearUnreadDividerAndMarkReadIfNeeded()
            return
        }
        isPinnedToBottom = true
        clearUnreadDividerAndMarkReadIfNeeded()
    }

    private var scrollToBottomAccentColor: Color {
        colorScheme == .dark ? Color(hex: "8EB6CE") : Color(hex: "3F6F8F")
    }

    private var scrollToBottomBadgeTextColor: Color {
        colorScheme == .dark ? Color(hex: "071015") : .white
    }

    private func applyChatScrollInitialHandlers<V: View>(to content: V, proxy: ScrollViewProxy) -> some View {
        applyUnpinnedDragGestureIfNeeded(
            to: content
            .onAppear {
                routeInitialScroll(using: proxy)
                scheduleSingleHighlightScrollIfNeeded(using: proxy)
            }
        )
            .overlay(alignment: .bottomTrailing) {
                chatScrollToBottomOverlay(proxy: proxy)
            }
            .onChange(of: viewModel.messages.isEmpty) { _, isEmpty in
                guard !isEmpty else { return }
                routeInitialScroll(using: proxy)
            }
            .onChange(of: viewModel.liveReactionOverlays.count) { _, _ in
                guard !hasCompletedInitialScroll else { return }
                guard preferredReactionHighlightMessageId() != nil else { return }
                frozenInitialScrollTarget = nil
                initialScrollTask?.cancel()
                initialScrollTask = nil
                scheduleInitialScroll(proxy: proxy)
            }
            .onChange(of: viewModel.chatRenderRows.map(\.id)) { _, rowIds in
                reapplyFrozenScrollPositionIfNeeded(in: rowIds, using: proxy)
                scheduleSingleHighlightScrollIfNeeded(using: proxy)
                guard !hasCompletedInitialScroll else { return }
                if shouldOpenAtBottom(), isPinnedToBottom {
                    scheduleInitialBottomSnap(using: proxy)
                    return
                }
                guard case .highlightedMessage(let messageId) = frozenInitialScrollTarget,
                      messageIsReadyForScroll(messageId) else { return }
                guard initialScrollTask == nil else { return }
                scheduleInitialScroll(proxy: proxy)
            }
    }

    private func applyChatScrollMessageChanges<V: View>(to content: V, proxy: ScrollViewProxy) -> some View {
        content
            .onChange(of: viewModel.messages.last?.id) { oldValue, lastMessageId in
                handleLastMessageScrollChange(
                    oldValue: oldValue,
                    lastMessageId: lastMessageId,
                    proxy: proxy
                )
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard hasCompletedInitialScroll, !isPinnedToBottom else { return }
                pendingIncomingMessages = unreadIncomingMessageCount()
            }
            .onChange(of: viewModel.latestBuzzEvent?.id) { _, buzzId in
                guard let buzzId, hasCompletedInitialScroll else { return }
                let isMine = viewModel.latestBuzzEvent?.senderId == viewModel.currentUserId

                if isMine || isPinnedToBottom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            proxy.scrollTo("buzz-\(buzzId)", anchor: .center)
                        }
                    }
                    pendingIncomingMessages = 0
                    isPinnedToBottom = true
                } else {
                    pendingIncomingMessages += 1
                }
            }
            .onChange(of: viewModel.typingUsers.isEmpty) { _, isEmpty in
                guard hasCompletedInitialScroll, isPinnedToBottom, !isEmpty else { return }
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: pendingSearchTargetId) { _, targetId in
                guard let targetId else { return }
                jumpToMessage(targetId, proxy: proxy)
                pendingSearchTargetId = nil
            }
            .onChange(of: pendingReactionHighlightIds) { _, ids in
                guard hasCompletedInitialScroll, !ids.isEmpty else { return }
                let shouldScroll = hasExplicitReactionHighlightIntent()
                highlightMessages(ids, proxy: shouldScroll ? proxy : nil, scroll: shouldScroll)
                pendingReactionHighlightIds.removeAll()
            }
            .onChange(of: viewModel.buzzEvents.map(\.id)) { _, _ in
                guard hasCompletedInitialScroll else { return }
                processPendingBuzz(using: proxy)
            }
    }

    private func applyChatScrollReceivers<V: View>(to content: V, proxy: ScrollViewProxy) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .chatMessageReactionHighlight)) { notification in
                guard
                    let conversationId = notification.userInfo?["conversationId"] as? String,
                    conversationId == viewModel.conversation.id,
                    let messageId = notification.userInfo?["messageId"] as? String
                else { return }
                reloadNotificationOpenIntent()
                let shouldScroll = notificationOpenIntent?.highlightMessageIds.contains(messageId) == true
                if shouldScroll {
                    scheduleSingleHighlightScrollIfNeeded(using: proxy)
                } else {
                    highlightMessages([messageId], proxy: nil, scroll: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chatBuzzHighlight)) { notification in
                guard
                    let conversationId = notification.userInfo?["conversationId"] as? String,
                    conversationId == viewModel.conversation.id
                else { return }

                reloadNotificationOpenIntent()
                if hasCompletedInitialScroll {
                    processPendingBuzz(using: proxy)
                }
            }
            .onChange(of: isTextFieldFocused) { _, focused in
                guard focused, hasCompletedInitialScroll else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
    }

    private func handleLastMessageScrollChange(
        oldValue: String?,
        lastMessageId: String?,
        proxy: ScrollViewProxy
    ) {
        guard let lastMessageId, hasCompletedInitialScroll else { return }
        guard oldValue != nil else { return }
        let isLastMessageMine = viewModel.messages.last?.senderId == viewModel.currentUserId

        if isLastMessageMine {
            scheduleBottomSnap(using: proxy, reason: .incomingWhilePinned)
        } else if !viewModel.isLoadingMore {
            if isPinnedToBottom {
                scheduleBottomSnap(using: proxy, reason: .incomingWhilePinned)
            } else {
                if unreadDividerMessageId == nil {
                    unreadDividerMessageId = lastMessageId
                }
                pendingIncomingMessages += 1
            }
        }
    }

    private func isOutgoingItem(_ item: MessageItem) -> Bool {
        switch item {
        case .single(let message):
            return message.senderId == viewModel.currentUserId
        case .mediaCluster(let messages):
            return messages.first?.senderId == viewModel.currentUserId
        }
    }

    // ✅ REFACTORIZADO: Sección de barra de respuesta o edición
    private var replyBarSection: some View {
        VStack(spacing: 0) {
            if let replyingTo = replyingTo {
                GlassmorphicReplyBar(
                    message: replyingTo,
                    otherParticipantName: otherParticipantDisplayName
                ) {
                    self.replyingTo = nil
                }
            }

            if editingMessage != nil {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundColor(adaptiveColors.primary)
                    Text("chat.editing.title")
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(adaptiveColors.primary)
                    Spacer()
                    Button(action: {
                        self.editingMessage = nil
                        self.messageText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(adaptiveColors.primary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.5))
            }
        }
    }

    private var chatRootContent: some View {
        ZStack {
            ChatGlassmorphicBackground(adaptiveColors: adaptiveColors)
            mainChatStack
                .modifier(ChatBuzzShakeEffect(
                    progress: buzzShakeProgress,
                    amplitude: reduceMotion ? 0 : buzzShakeAmplitude
                ))

            if let buzzToastText {
                VStack {
                    ChatBuzzToast(text: buzzToastText)
                        .padding(.top, 10)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(45)
            }

            GeometryReader { proxy in
                ChatMessageContextMenuOverlay(
                    selection: $messageMenuSelection,
                    containerSize: proxy.size,
                    containerFrameInGlobal: proxy.frame(in: .global),
                    safeAreaInsets: proxy.safeAreaInsets,
                    colorScheme: colorScheme,
                    currentUserId: viewModel.currentUserId,
                    forwardingPreferences: viewModel.forwardingPreferences,
                    onDeleteForEveryone: { message in
                        viewModel.deleteMessageForEveryone(message)
                    },
                    onDeleteForMe: { message in
                        viewModel.deleteMessageForMe(message)
                    },
                    onEdit: { message in
                        editingMessage = message
                        messageText = message.content ?? ""
                    },
                    onReply: { message in
                        activateReply(to: message)
                    },
                    onCopy: { message in
                        UIPasteboard.general.string = message.content
                    },
                    onForward: { message in
                        forwardingMessage = message
                    },
                    onToggleStar: { message in
                        viewModel.toggleStar(for: message)
                    },
                    onReaction: { message, emoji in
                        viewModel.addReaction(to: message, emoji: emoji)
                        pulseBubbleHighlight(message.id)
                    },
                    onMoreReactions: { message in
                        reactionPickerMessage = message
                        showingReactionEmojiPicker = true
                    }
                )
            }
            .allowsHitTesting(messageMenuSelection != nil)
            .zIndex(50)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isSearchVisible {
                chatSearchBarSection
            }
        }
    }

    private var mainChatStack: some View {
        messagesListSection
            .chatBottomBarInset {
                VStack(spacing: 0) {
                    replyBarSection
                        .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                    inputBarSection
                        .chatMenuDimmedWhenOpen(messageMenuSelection != nil)
                }
                .background(Color.clear)
            }
    }

    private func sharedMedia(from message: EnhancedMessage) -> SharedMedia? {
        guard let mediaUrl = message.mediaUrl else { return nil }
        guard message.type == .image || message.type == .video || message.type == .ephemeral else { return nil }

        return SharedMedia(
            id: message.id,
            type: message.type == .video ? .video : .image,
            thumbnailUrl: message.thumbnailUrl ?? mediaUrl,
            originalUrl: mediaUrl,
            senderId: message.senderId,
            timestamp: message.timestamp,
            sourceMessage: message,
            allowsSaving: message.type != .ephemeral
        )
    }

    private func sharedMediaItemsForOverlay(selecting message: EnhancedMessage) -> [SharedMedia] {
        if message.type == .ephemeral {
            guard let selected = sharedMedia(from: message) else { return [] }
            return [selected]
        }

        let items = viewModel.messages.compactMap(sharedMedia(from:))
        guard let selected = sharedMedia(from: message) else { return items }

        if items.contains(where: { $0.id == selected.id }) {
            return items
        }

        return items + [selected]
    }

    private func sendReplyToSharedMedia(_ media: SharedMedia, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        viewModel.sendTextMessage(trimmedText, replyTo: media.id)
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }

    private func sendBuzzFromAttachmentMenu() {
        let now = Date()
        if let lastBuzzSentAt, now.timeIntervalSince(lastBuzzSentAt) < 45 {
            showBuzzToast(NSLocalizedString("chat.buzz.cooldown", comment: "Buzz cooldown"))
            return
        }

        lastBuzzSentAt = now
        viewModel.sendBuzz { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    HapticManager.shared.playBuzzSentSound()
                    triggerBuzzEffect(
                        text: NSLocalizedString("chat.buzz.sent", comment: "Sent buzz toast"),
                        isLocal: true,
                        showsToast: false
                    )
                case .failure(let error):
                    lastBuzzSentAt = nil
                    showBuzzToast(error.localizedDescription)
                }
            }
        }
    }

    private func buzzTimelineText(for event: ChatBuzzEvent) -> String {
        if event.senderId == viewModel.currentUserId {
            return NSLocalizedString("chat.buzz.sent", comment: "Sent buzz timeline event")
        }

        return String(
            format: NSLocalizedString("chat.buzz.received", comment: "Incoming buzz timeline event"),
            otherParticipantDisplayName
        )
    }

    private func triggerBuzzEffect(text: String, isLocal: Bool, showsToast: Bool = true) {
        if showsToast {
            showBuzzToast(text)
        }
        guard !isLocal else { return }

        buzzShakeAmplitude = 24
        HapticManager.shared.chatBuzzReceived(reduceMotion: reduceMotion)
        HapticManager.shared.playBuzzReceivedSound()
        guard !reduceMotion else { return }
        buzzShakeProgress = 0
        withAnimation(.linear(duration: 1.12)) {
            buzzShakeProgress = 1
        }
    }

    private func showBuzzToast(_ text: String) {
        buzzToastDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            buzzToastText = text
        }

        buzzToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                buzzToastText = nil
            }
        }
    }

    // ✅ REFACTORIZADO: Sección de barra de entrada
    private var inputBarSection: some View {
        Group {
            if isOtherParticipantBlockedByCurrentUser {
                BlockedByMeChatInputBar(onUnblock: unblockOtherParticipantFromChat)
            } else if isOtherParticipantUnavailable {
                UnavailableChatInputBar()
            } else {
                GlassmorphicInputBar(
                    text: $messageText,
                    isTyping: $session.isTyping,
                    isRecordingVoice: $isRecordingVoice,
                    activeAttachmentSheet: $activeAttachmentSheet,
                    recordingTime: recordingTime,
                    onSend: {
                        let messageToSend = messageText

                        guard !messageToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return
                        }

                        if let editingMessage = editingMessage {
                            // Save edit
                            viewModel.editMessage(editingMessage, newContent: messageToSend)
                            self.editingMessage = nil
                        } else {
                            // Send new message
                            let replyToMessageId = replyingTo?.id
                            viewModel.sendTextMessage(messageToSend, replyTo: replyToMessageId)
                            replyingTo = nil
                            ChatDraftStore.shared.clearDraft(for: conversationId)
                        }

                        messageText = ""
                    },
                    onStartVoiceRecording: {
                        startVoiceRecording()
                    },
                    onStopVoiceRecording: { shouldSend in
                        stopVoiceRecording(shouldSend: shouldSend)
                    }
                )
                .focused($isTextFieldFocused)
                .onPreferenceChange(ChatPlusButtonAnchorKey.self) { frame in
                    plusButtonAnchorFrame = frame
                }
            }
        }
    }

    private struct UnavailableChatInputBar: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "person.slash")
                    .font(.system(size: 15, weight: .semibold))

                Text("chat.input.unavailable")
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .momentsChromeGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private struct BlockedByMeChatInputBar: View {
        let onUnblock: () -> Void
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 10) {
                Text("chat.blockedByMe.input")
                    .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.58))
                    .lineLimit(2)

                Spacer(minLength: 6)

                Button(action: onUnblock) {
                    Text("chat.blockedByMe.unblock")
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .momentsChromeGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // ✅ REFACTORIZADO: Acciones al aparecer

    // ✅ REFACTORIZADO: Renderizar cada item del chat por separado para evitar errores del compilador
    @ViewBuilder
    private func renderMessageItem(_ item: MessageItem, in messages: [EnhancedMessage], proxy: ScrollViewProxy) -> some View {
        let rowId = item.id
        let isMenuSelected = messageMenuSelection?.rowId == rowId
        let isBubbleHighlighted = isMessageItemHighlighted(item)

        ChatMessageRowChrome(
            isOutgoing: isOutgoingItem(item),
            colorScheme: colorScheme
        ) {
            Group {
                switch item {
                case .single(let message):
                    let liveMessage = viewModel.messages.first(where: { $0.id == message.id }) ?? message
                    let displayReactions = shouldRenderReactionChrome(rowId: rowId, messageIds: [liveMessage.id])
                        ? viewModel.displayReactions(for: liveMessage.id)
                        : nil
                    GlassmorphicMessageRow(
                    message: liveMessage,
                    displayReactions: displayReactions,
                    isCurrentUser: liveMessage.senderId == viewModel.currentUserId,
                    showAvatar: shouldShowAvatar(for: liveMessage, in: messages),
                    groupPosition: messageGroupPosition(for: liveMessage, in: messages),
                    otherUserId: viewModel.conversation.otherParticipantId,
                    isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                    otherParticipantName: otherParticipantDisplayName,
                    repliedMessage: liveMessage.replyTo != nil ? viewModel.messages.first(where: { $0.id == liveMessage.replyTo }) : nil,
                    isMenuSelected: isMenuSelected,
                    isBubbleFlashing: isBubbleFlashing(liveMessage.id),
                    onReply: { activateReply(to: liveMessage) },
                    onReaction: { emoji in
                        viewModel.addReaction(to: liveMessage, emoji: emoji)
                        pulseBubbleHighlight(liveMessage.id)
                    },
                    onAvatarTap: {
                        showingUserProfile = true
                    },
                    onReplyTap: { targetId in
                        jumpToMessage(targetId, proxy: proxy)
                    },
                    onMessageViewed: { messageId in
                        if let index = viewModel.messages.firstIndex(where: { $0.id == messageId }) {
                            viewModel.messages[index].isViewed = true
                        }
                    },
                    onMomentNavigation: { message in
                        handleMomentNavigationFromChat(message: message)
                    },
                    onStoryNavigation: { message in
                        handleStoryNavigationFromChat(message: message)
                    },
                    onOpenMedia: { message in
                        viewModel.prepareMediaForViewing(message) { resolved in
                            selectedChatMediaItems = sharedMediaItemsForOverlay(selecting: resolved)
                            selectedChatMedia = sharedMedia(from: resolved)
                        }
                    },
                    onStopLiveLocation: { messageId in
                        viewModel.stopLiveLocation(messageId: messageId)
                    },
                    onHydrateMedia: { message in
                        viewModel.hydrateMediaIfNeeded(for: message)
                    },
                    onLongPress: { frame, cornerRadius in
                        presentMessageOptions(
                            liveMessage,
                            rowId: rowId,
                            cluster: nil,
                            anchorFrame: frame,
                            anchorCornerRadius: cornerRadius
                        )
                    },
                    progress: viewModel.uploadProgress[liveMessage.id],
                    showSeenLabel: shouldShowSeenLabel(for: liveMessage.id, status: liveMessage.status)
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        addQuickReaction(to: liveMessage)
                    }
                )

                case .mediaCluster(let clusterMessages):
                    let liveCluster = clusterMessages.compactMap { clusterMessage in
                        viewModel.messages.first(where: { $0.id == clusterMessage.id }) ?? clusterMessage
                    }
                    GlassmorphicClusterRow(
                    messages: liveCluster,
                    isCurrentUser: liveCluster.first?.senderId == viewModel.currentUserId,
                    showAvatar: shouldShowAvatar(for: liveCluster.first!, in: messages),
                    otherUserId: viewModel.conversation.otherParticipantId,
                    isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                    onAvatarTap: { showingUserProfile = true },
                    onMessageViewed: { messageId in
                        if let index = viewModel.messages.firstIndex(where: { $0.id == messageId }) {
                            viewModel.messages[index].isViewed = true
                        }
                    },
                    onMomentNavigation: { message in
                        handleMomentNavigationFromChat(message: message)
                    },
                    onOpenCluster: { clusterMessages in
                        viewModel.prefetchClusterGalleryMedia(clusterMessages)
                        self.clusterForGallery = clusterMessages
                    },
                    onLongPress: { message, frame, cornerRadius in
                        presentMessageOptions(
                            message,
                            rowId: rowId,
                            cluster: liveCluster.count > 1 ? liveCluster : nil,
                            anchorFrame: frame,
                            anchorCornerRadius: cornerRadius
                        )
                    },
                    onHydrateMedia: { message in
                        viewModel.hydrateMediaIfNeeded(for: message)
                    },
                    onReply: { messages in
                        self.clusterForReply = messages
                    },
                    onReplyTap: { id in
                        jumpToMessage(id, proxy: proxy)
                    },
                    displayReactions: { messageId in
                        shouldRenderReactionChrome(rowId: rowId, messageIds: liveCluster.map(\.id))
                            ? viewModel.displayReactions(for: messageId)
                            : nil
                    },
                    onReaction: { message, emoji in
                        viewModel.addReaction(to: message, emoji: emoji)
                        pulseBubbleHighlight(message.id)
                    },
                    uploadProgress: viewModel.uploadProgress,
                    showSeenLabel: {
                        let status = ClusterMessageStatusAggregator.aggregate(liveCluster)
                        guard let anchorId = liveCluster.last?.id else { return false }
                        return shouldShowSeenLabel(for: anchorId, status: status)
                    }(),
                    isMenuSelected: isMenuSelected,
                    isBubbleFlashing: liveCluster.contains { isBubbleFlashing($0.id) }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if let frontMessage = liveCluster.first {
                            addQuickReaction(to: frontMessage)
                        }
                    }
                )

                }
            }
        }
        .chatMenuDimmedUnlessSelected(isSelected: isMenuSelected, menuOpen: messageMenuSelection != nil)
        .zIndex(isMenuSelected || isBubbleHighlighted ? 100 : 0)
        .id(item.id)
    }

    private func isMessageItemHighlighted(_ item: MessageItem) -> Bool {
        switch item {
        case .single(let message):
            return flashingMessageIds.contains(message.id)
        case .mediaCluster(let messages):
            return messages.contains { flashingMessageIds.contains($0.id) }
        }
    }

    private var chatMediaLayoutSignature: String {
        viewModel.messages.suffix(6).map { message in
            "\(message.id)|\(message.mediaUrl ?? "")|\(message.thumbnailUrl ?? "")|\(message.type.rawValue)"
        }.joined(separator: ";")
    }

    private var lastOutgoingMessageId: String? {
        viewModel.messages.last(where: { $0.senderId == viewModel.currentUserId })?.id
    }

    private func shouldShowSeenLabel(for messageId: String, status: MessageStatus) -> Bool {
        status == .read && messageId == lastOutgoingMessageId
    }

    private func reactionIdentitySuffix(for item: MessageItem) -> String {
        switch item {
        case .single(let message):
            return reactionToken(for: message.id)
        case .mediaCluster(let clusterMessages):
            return clusterMessages.map { reactionToken(for: $0.id) }.joined(separator: "|")
        }
    }

    private func reactionToken(for messageId: String) -> String {
        guard let reactions = viewModel.displayReactions(for: messageId), !reactions.isEmpty else { return "" }
        return reactions
            .map { "\($0.key):\($0.value.count)" }
            .sorted()
            .joined(separator: ",")
    }

    private func shouldRenderReactionChrome(rowId: String, messageIds: [String]) -> Bool {
        messageMenuSelection?.rowId != rowId
    }

    private func isBubbleFlashing(_ messageId: String) -> Bool {
        flashingMessageIds.contains(messageId)
    }

    private func activateReply(to message: EnhancedMessage) {
        replyingTo = message
        pulseBubbleHighlight(message.id)
    }

    private func pulseBubbleHighlight(_ messageId: String, duration: TimeInterval = ChatBubbleAnchorMetrics.highlightDuration) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            flashingMessageIds.insert(messageId)
        }
        let id = messageId
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                _ = flashingMessageIds.remove(id)
            }
        }
    }

    private func addQuickReaction(to message: EnhancedMessage) {
        viewModel.addReaction(to: message, emoji: quickReactionEmoji)
        pulseBubbleHighlight(message.id)
        HapticManager.shared.lightImpact()
    }

    private func presentMessageOptions(
        _ message: EnhancedMessage,
        rowId: String,
        cluster: [EnhancedMessage]?,
        anchorFrame: CGRect,
        anchorCornerRadius: CGFloat
    ) {
        guard anchorFrame.width > 0, anchorFrame.height > 0 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            messageMenuSelection = ChatMessageMenuSelection(
                rowId: rowId,
                message: message,
                anchorFrame: anchorFrame,
                anchorCornerRadius: anchorCornerRadius,
                isOutgoing: message.senderId == viewModel.currentUserId,
                clusterMessages: cluster
            )
        }
    }

    private func restoreScrollUIState() {
        // Apertura fresca por instancia: solo se establece la línea base una vez para que un
        // segundo `onAppear` (p. ej. al cerrar un sheet) no fuerce un salto al fondo a media lectura.
        guard !didHydrateScrollStateOnce else { return }
        didHydrateScrollStateOnce = true

        let stored = ChatScrollStateStore.state(for: conversationId)
        hasCompletedInitialScroll = stored.hasCompletedInitialScroll
        frozenInitialScrollTarget = stored.frozenInitialScrollTarget
        isPinnedToBottom = stored.isPinnedToBottom
        didProcessNotificationBuzz = stored.didProcessNotificationBuzz
        if let anchor = stored.scrollAnchorId, anchor != bottomScrollAnchorID {
            liveScrollAnchorRowId = anchor
        }
    }

    private func commitScrollStateToStore(includeFullState: Bool = false) {
        guard !conversationId.isEmpty else { return }
        if !isPinnedToBottom {
            updateLiveScrollAnchor()
        }
        let savedAnchor = isPinnedToBottom ? bottomScrollAnchorID : liveScrollAnchorRowId
        let savedOffset = isPinnedToBottom ? nil : scrollContentOffset
        ChatScrollStateStore.update(for: conversationId) { state in
            if includeFullState {
                state.hasCompletedInitialScroll = hasCompletedInitialScroll
                state.frozenInitialScrollTarget = frozenInitialScrollTarget
                state.didProcessNotificationBuzz = didProcessNotificationBuzz
            }
            state.isPinnedToBottom = isPinnedToBottom
            state.scrollAnchorId = savedAnchor
            state.scrollOffsetY = savedOffset.map { Double($0) }
        }
    }

    private func clearUnreadDividerAndMarkReadIfNeeded() {
        unreadDividerMessageId = nil
        unreadDividerInitialized = true
        pendingIncomingMessages = 0
        viewModel.markVisibleConversationAsRead()
    }

    /// Actualiza altura de contenido/viewport en cuanto el ScrollView las conoce (no esperar al idle).
    private func syncScrollLayoutMetrics(from metrics: ChatScrollMetrics) {
        let contentDelta = abs(metrics.contentHeight - scrollContentHeight)
        let viewportDelta = abs(metrics.viewportHeight - scrollViewportHeight)
        guard contentDelta > 1 || viewportDelta > 1 else { return }

        if contentDelta > 1 { scrollContentHeight = metrics.contentHeight }
        if viewportDelta > 1 { scrollViewportHeight = metrics.viewportHeight }

        if !hasCompletedInitialScroll {
            completeInitialScrollIfContentFits(using: nil)
        }
    }

    /// Sincroniza métricas de scroll a @State al parar o desacelerar.
    private func flushScrollMetricsToUI() {
        let metrics = scrollMetricsBuffer.metrics
        let offsetDelta = abs(metrics.offsetY - scrollContentOffset)
        let contentDelta = abs(metrics.contentHeight - scrollContentHeight)
        let viewportDelta = abs(metrics.viewportHeight - scrollViewportHeight)
        guard offsetDelta > 1 || contentDelta > 1 || viewportDelta > 1 else { return }

        let oldViewportHeight = scrollViewportHeight
        let oldContentHeight = scrollContentHeight
        if offsetDelta > 1 { scrollContentOffset = metrics.offsetY }
        if contentDelta > 1 { scrollContentHeight = metrics.contentHeight }
        if viewportDelta > 1 { scrollViewportHeight = metrics.viewportHeight }

        guard hasCompletedInitialScroll else {
            completeInitialScrollIfContentFits(using: nil)
            return
        }

        guard allowsVerticalScrolling else {
            if !isPinnedToBottom {
                isPinnedToBottom = true
                clearUnreadDividerAndMarkReadIfNeeded()
            }
            return
        }

        guard !suppressPinnedMetricsUpdates else { return }

        let bottomGap = bottomGap(for: metrics)
        var pinned = !isScrollable(metrics) || bottomGap < 48

        if isPinnedToBottom
            && (metrics.viewportHeight != oldViewportHeight || metrics.contentHeight != oldContentHeight) {
            pinned = true
        }

        if pinned != isPinnedToBottom {
            isPinnedToBottom = pinned
            if pinned {
                clearUnreadDividerAndMarkReadIfNeeded()
            }
        }

        if !isPinnedToBottom {
            updateLiveScrollAnchor()
        }
    }

    private var isScrollContentScrollable: Bool {
        allowsVerticalScrolling
    }

    private func isScrollable(_ metrics: ChatScrollMetrics) -> Bool {
        metrics.contentHeight > metrics.viewportHeight + 32
    }

    private func bottomGap(for metrics: ChatScrollMetrics) -> CGFloat {
        max(0, metrics.contentHeight - metrics.offsetY - metrics.viewportHeight)
    }

    private func shouldOpenAtBottom() -> Bool {
        preferredReactionHighlightMessageId() == nil && !hasUnreadIncomingMessages()
    }

    private func storedScrollAnchorRowId() -> String? {
        if let liveScrollAnchorRowId { return liveScrollAnchorRowId }
        let stored = ChatScrollStateStore.state(for: conversationId).scrollAnchorId
        guard let stored, stored != bottomScrollAnchorID else { return nil }
        return stored
    }

    private func isPreferredScrollAnchorRow(_ rowId: String) -> Bool {
        !rowId.hasPrefix("buzz-") && !rowId.hasPrefix("header-")
    }

    /// Solo la primera apertura o intents (no leídos / reacción) necesitan scroll programático.
    private func needsProgrammaticInitialScroll() -> Bool {
        if preferredReactionHighlightMessageId() != nil { return true }
        if hasCompletedInitialScroll && !isPinnedToBottom { return false }
        if hasUnreadIncomingMessages() { return true }
        return !hasCompletedInitialScroll
    }

    private func routeInitialScroll(using proxy: ScrollViewProxy) {
        guard needsProgrammaticInitialScroll() else { return }
        if shouldOpenAtBottom() {
            scheduleInitialBottomSnap(using: proxy)
        } else {
            scheduleInitialScroll(proxy: proxy)
        }
    }

    /// Re-aplica scroll guardado tras recrear la vista (navigationDestination pop/push).
    private func reapplyFrozenScrollPositionIfNeeded(in rowIds: [String], using proxy: ScrollViewProxy) {
        guard hasCompletedInitialScroll, !didReapplyFrozenScrollPosition, !rowIds.isEmpty else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true

        if isPinnedToBottom {
            didReapplyFrozenScrollPosition = true
            withTransaction(transaction) {
                proxy.scrollTo(bottomScrollAnchorID, anchor: .bottom)
            }
            return
        }

        guard let anchorId = storedScrollAnchorRowId(), rowIds.contains(anchorId) else {
            guard !viewModel.isLoadingMore, !viewModel.messages.isEmpty else { return }
            missingFrozenAnchorLayoutPasses += 1
            guard missingFrozenAnchorLayoutPasses >= 3 else { return }
            guard let fallbackId = fallbackFrozenScrollAnchor(in: rowIds) else { return }

            didReapplyFrozenScrollPosition = true
            missingFrozenAnchorLayoutPasses = 0
            withTransaction(transaction) {
                proxy.scrollTo(fallbackId, anchor: .top)
            }
            return
        }

        didReapplyFrozenScrollPosition = true
        missingFrozenAnchorLayoutPasses = 0
        withTransaction(transaction) {
            proxy.scrollTo(anchorId, anchor: .top)
        }
    }

    private func fallbackFrozenScrollAnchor(in rowIds: [String]) -> String? {
        if let unreadDividerMessageId,
           let unreadRowId = messageRowId(containingMessageId: unreadDividerMessageId),
           rowIds.contains(unreadRowId) {
            return unreadRowId
        }

        if let firstPreferred = rowIds.first(where: isPreferredScrollAnchorRow) {
            return firstPreferred
        }

        return rowIds.first
    }

    private func updateLiveScrollAnchor() {
        if isPinnedToBottom {
            if liveScrollAnchorRowId != bottomScrollAnchorID {
                liveScrollAnchorRowId = bottomScrollAnchorID
            }
            return
        }

        guard scrollViewportHeight > 0 else { return }

        guard !messageRowFrames.isEmpty else { return }

        let viewportTop: CGFloat = 8
        let viewportBottom = scrollViewportHeight - 8

        var candidateId: String?
        var candidateMinY: CGFloat = .greatestFiniteMagnitude

        let preferredCandidates = messageRowFrames.keys.filter(isPreferredScrollAnchorRow(_:)).compactMap { rowId -> (String, CGFloat)? in
            guard let frame = messageRowFrames[rowId] else { return nil }
            guard frame.maxY > viewportTop, frame.minY < viewportBottom else { return nil }
            return (rowId, frame.minY)
        }

        if let preferred = preferredCandidates.min(by: {
            abs($0.1 - viewportTop) < abs($1.1 - viewportTop)
        }) {
            candidateId = preferred.0
            candidateMinY = preferred.1
        } else {
            for (rowId, frame) in messageRowFrames {
                guard frame.maxY > viewportTop, frame.minY < viewportBottom else { continue }
                if frame.minY < candidateMinY {
                    candidateMinY = frame.minY
                    candidateId = rowId
                }
            }
        }

        guard let candidateId else { return }

        if liveScrollAnchorRowId != candidateId {
            liveScrollAnchorRowId = candidateId
        }
    }

    private enum BottomSnapReason {
        case initialOpen
        case userRequested
        case incomingWhilePinned
    }

    private func scheduleBottomSnap(using proxy: ScrollViewProxy, reason: BottomSnapReason) {
        bottomSnapTask?.cancel()
        bottomSnapTask = Task { @MainActor in
            defer { bottomSnapTask = nil }
            suppressPinnedMetricsUpdates = true

            let maxPasses = reason == .initialOpen ? 3 : 4
            let delays: [UInt64] = [0, 50_000_000, 120_000_000, 200_000_000]

            for pass in 0..<maxPasses {
                if Task.isCancelled { return }
                if pass > 0, pass < delays.count {
                    try? await Task.sleep(nanoseconds: delays[pass])
                }
                guard !viewModel.chatRenderRows.isEmpty else { continue }

                flushScrollMetricsToUI()
                performBottomScroll(using: proxy)
                flushScrollMetricsToUI()

                let metrics = scrollMetricsBuffer.metrics
                if !allowsVerticalScrolling || bottomGap(for: metrics) < 48 {
                    finalizeBottomSnap(reason: reason, using: proxy)
                    return
                }
            }

            finalizeBottomSnap(reason: reason, using: proxy)
        }
    }

    private func performBottomScroll(using proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(bottomScrollAnchorID, anchor: .bottom)
            if let lastId = viewModel.messages.last?.id,
               let rowId = messageRowId(containingMessageId: lastId) {
                proxy.scrollTo(rowId, anchor: .bottom)
            }
        }
    }

    private func finalizeBottomSnap(reason: BottomSnapReason, using proxy: ScrollViewProxy) {
        isPinnedToBottom = true
        suppressPinnedMetricsUpdates = false
        clearUnreadDividerAndMarkReadIfNeeded()

        if reason == .initialOpen, !hasCompletedInitialScroll {
            hasCompletedInitialScroll = true
            frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
            commitScrollStateToStore(includeFullState: true)
            viewModel.prefetchUnresolvedMediaIfNeeded()
            processPendingReactionHighlights(using: proxy)
            processPendingBuzz(using: proxy)
            scheduleNotificationBuzzRetries(using: proxy)
            clearNotificationOpenIntentIfFinished()
            return
        }

        commitScrollStateToStore()
    }

    /// Snap silencioso al fondo cuando no hay pendientes — solo primera apertura.
    private func scheduleInitialBottomSnap(using proxy: ScrollViewProxy) {
        guard shouldOpenAtBottom(), isPinnedToBottom else { return }
        guard !hasCompletedInitialScroll else { return }
        guard bottomSnapTask == nil else { return }
        scheduleBottomSnap(using: proxy, reason: .initialOpen)
    }

    /// Marca la apertura inicial como lista cuando el contenido cabe sin scroll interactivo.
    private func completeInitialScrollIfContentFits(using proxy: ScrollViewProxy?) {
        guard !hasCompletedInitialScroll else { return }
        guard scrollViewportHeight > 1, !viewModel.chatRenderRows.isEmpty else { return }
        guard !allowsVerticalScrolling else { return }

        if let proxy {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(bottomScrollAnchorID, anchor: .bottom)
            }
        }

        hasCompletedInitialScroll = true
        isPinnedToBottom = true
        frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
        clearUnreadDividerAndMarkReadIfNeeded()
        commitScrollStateToStore(includeFullState: true)

        viewModel.prefetchUnresolvedMediaIfNeeded()
        if let proxy {
            processPendingReactionHighlights(using: proxy)
            processPendingBuzz(using: proxy)
            scheduleNotificationBuzzRetries(using: proxy)
        }
        clearNotificationOpenIntentIfFinished()
    }

    @ViewBuilder
    private func applyUnpinnedDragGestureIfNeeded<V: View>(to content: V) -> some View {
        if allowsVerticalScrolling {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        if messageMenuSelection != nil {
                            messageMenuSelection = nil
                        }
                        guard hasCompletedInitialScroll else { return }
                        let vertical = value.translation.height
                        let horizontal = abs(value.translation.width)
                        guard abs(vertical) > horizontal * 1.25, vertical > 28 else { return }
                        if isPinnedToBottom {
                            isPinnedToBottom = false
                        }
                    }
            )
        } else {
            content
        }
    }

    private func onAppearActions() {
        restoreScrollUIState()
        reloadNotificationOpenIntent()
        reconcileScrollStateForCurrentConversation()

        if let intent = notificationOpenIntent, !intent.highlightMessageIds.isEmpty {
            hasCompletedInitialScroll = false
            frozenInitialScrollTarget = nil
            initialScrollTask?.cancel()
            initialScrollTask = nil
            highlightScrollTask?.cancel()
            highlightScrollTask = nil
            bottomSnapTask?.cancel()
            bottomSnapTask = nil
        }

        if !conversationId.isEmpty {
            ChatSessionEngine.shared.activate(conversationId: conversationId)
        }

        pendingIncomingMessages = isPinnedToBottom ? 0 : unreadIncomingMessageCount()
        setupOnlineStatusObserver()
        refreshOtherParticipantUsername()
        refreshOtherParticipantAvailability()
        checkUserStories()
    }

    // ✅ REFACTORIZADO: Acciones al desaparecer
    private func onDisappearActions() {
        flushScrollMetricsToUI()
        updateLiveScrollAnchor()
        if isPinnedToBottom {
            clearUnreadDividerAndMarkReadIfNeeded()
        }
        commitScrollStateToStore(includeFullState: true)
        initialScrollTask?.cancel()
        initialScrollTask = nil
        highlightScrollTask?.cancel()
        highlightScrollTask = nil
        bottomSnapTask?.cancel()
        bottomSnapTask = nil
        buzzToastDismissTask?.cancel()
        buzzToastDismissTask = nil
        buzzToastText = nil

        if !conversationId.isEmpty {
            ChatSessionEngine.shared.deactivate(conversationId: conversationId)
        }

        statusListener?.remove()
    }

    // ✅ ACTUALIZADO: Función para verificar historias del usuario (con filtrado de privacidad como en reels)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId
        guard !otherUserId.isEmpty else { return }

        StoryRingResolverService.shared.resolve(
            viewerId: currentUserId,
            authorId: otherUserId,
            privacyService: privacyService
        ) { snapshot in
            self.hasStory = snapshot.hasStory
            self.hasUnseenStory = snapshot.hasUnseenStory
            self.storyCount = snapshot.storyCount
            self.storyViewedStatus = snapshot.storyViewedStatus
            self.storyAudiences = snapshot.storyAudiences
        }
    }

    // MARK: - Helper Methods
    private func setupOnlineStatusObserver() {
        let otherUserId = viewModel.conversation.otherParticipantId

        statusListener = onlineStatusService.observeUserStatus(userId: otherUserId) { status, lastSeen in
            DispatchQueue.main.async {
                self.otherUserStatus = status
                self.otherUserLastSeen = lastSeen
            }
        }
    }

    private func handleCameraCapture(data: Data, mediaType: EnhancedCameraPickerView.MediaType, isEphemeral: Bool) {
        guard !isOtherParticipantUnavailable else {
            showEnhancedCamera = false
            return
        }

        guard viewModel.conversation.id != nil else {
            return
        }

        if isEphemeral {
            viewModel.sendViewOnceMessage(data: data, mediaType: mediaType)

        } else {
            if mediaType == .image {
                viewModel.sendImageMessage(data)
            } else {
                viewModel.sendVideoMessage(data: data)
            }

        }

        showEnhancedCamera = false
    }

    private func refreshOtherParticipantUsername() {
        let otherUserId = viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty else {
            liveOtherParticipantUsername = ""
            return
        }

        UserCacheService.shared.refreshUser(userId: otherUserId) { user in
            let fetchedUsername = user?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard self.viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                self.liveOtherParticipantUsername = fetchedUsername
            }
        }
    }

    private func refreshOtherParticipantAvailability() {
        let otherUserId = viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty, NetworkMonitor.shared.isConnected else { return }

        firestoreService.checkPublicProfileAvailability(userId: otherUserId) { availability in
            DispatchQueue.main.async {
                guard self.viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == otherUserId else { return }
                if availability == .unavailable {
                    self.markOtherParticipantUnavailable(clearLiveUsername: true)
                } else {
                    self.refreshOtherParticipantBlockAvailability(userId: otherUserId)
                }
            }
        }
    }

    private func refreshOtherParticipantBlockAvailability(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        firestoreService.checkIfBlocked(currentUserId: currentUserId, targetUserId: userId) { isBlockedByCurrentUser, isCurrentUserBlocked, _ in
            DispatchQueue.main.async {
                guard self.viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines) == userId else { return }

                if isBlockedByCurrentUser || isCurrentUserBlocked {
                    self.isOtherParticipantBlockedByCurrentUser = isBlockedByCurrentUser
                    self.markOtherParticipantUnavailable(clearLiveUsername: false)
                } else {
                    self.isOtherParticipantBlockedByCurrentUser = false
                    self.isOtherParticipantUnavailable = false
                    self.refreshOtherParticipantUsername()
                }
            }
        }
    }

    private func markOtherParticipantUnavailable(clearLiveUsername: Bool) {
        isOtherParticipantUnavailable = true
        if clearLiveUsername {
            liveOtherParticipantUsername = ""
            isOtherParticipantBlockedByCurrentUser = false
        }
        disableUnavailableParticipantStories()
    }

    private func unblockOtherParticipantFromChat() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otherUserId.isEmpty else { return }

        firestoreService.unblockUser(currentUserId: currentUserId, targetUserId: otherUserId) { error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                self.isOtherParticipantBlockedByCurrentUser = false
                self.isOtherParticipantUnavailable = false
                self.refreshOtherParticipantUsername()
                self.checkUserStories()
            }
        }
    }

    private func disableUnavailableParticipantStories() {
        storyRoute = nil
        hasStory = false
        hasUnseenStory = false
        storyCount = 0
        storyViewedStatus = []
        storyAudiences = []
    }

    private func shouldShowAvatar(for message: EnhancedMessage, in messages: [EnhancedMessage]) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return true }
        if index == messages.count - 1 { return true }
        let nextMessage = messages[index + 1]
        return nextMessage.senderId != message.senderId
    }

    /// Posición del mensaje en una ráfaga del mismo remitente.
    private func messageGroupPosition(for message: EnhancedMessage, in messages: [EnhancedMessage]) -> ChatMessageGroupPosition {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return .single }
        let prevSameSender = index > 0 && messages[index - 1].senderId == message.senderId
        let nextSameSender = index < messages.count - 1 && messages[index + 1].senderId == message.senderId

        switch (prevSameSender, nextSameSender) {
        case (false, false): return .single
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    // MARK: - Voice Recording Functions
    private func startVoiceRecording() {
        recordingTime = 0

        AudioRecordingManager.shared.startRecording { started in
            guard started else {
                viewModel.error = NSLocalizedString(
                    "chat.error.microphonePermission",
                    comment: "Microphone permission required for voice messages"
                )
                return
            }

            isRecordingVoice = true
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime += 0.1
                if recordingTime >= 60.0 {
                    stopVoiceRecording(shouldSend: true)
                }
            }
        }
    }

    private func stopVoiceRecording(shouldSend: Bool) {
        isRecordingVoice = false
        recordingTimer?.invalidate()
        recordingTimer = nil

        let capturedDuration = max(recordingTime, 0.1)
        recordingTime = 0

        AudioRecordingManager.shared.stopRecording { [weak viewModel] audioData in
            guard shouldSend,
                  let audioData,
                  !audioData.isEmpty,
                  let viewModel else { return }
            viewModel.sendAudioMessage(audioData, duration: capturedDuration)
        }
    }
}

// ✅ NUEVO: Función para manejar navegación al momento desde el chat
extension GlassmorphicChatView {
    private func preferredReactionHighlightMessageId() -> String? {
        reloadNotificationOpenIntent()
        return notificationOpenIntent?.highlightMessageIds.first
    }

    private func hasExplicitReactionHighlightIntent() -> Bool {
        reloadNotificationOpenIntent()
        return notificationOpenIntent?.highlightMessageIds.isEmpty == false
    }

    private func hasUnreadIncomingMessages() -> Bool {
        unreadIncomingMessageCount() > 0
    }

    private func unreadIncomingMessageCount() -> Int {
        viewModel.messages.filter {
            !$0.isRead && $0.senderId != viewModel.currentUserId
        }.count
    }

    private func reconcileScrollStateForCurrentConversation() {
        guard !hasCompletedInitialScroll else { return }
        reloadNotificationOpenIntent()
        let hasHighlightIntent = preferredReactionHighlightMessageId() != nil
        if hasHighlightIntent { return }

        if !hasUnreadIncomingMessages() {
            unreadDividerMessageId = nil
            if case .firstUnread = frozenInitialScrollTarget {
                frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
                isPinnedToBottom = true
            }
            if case .highlightedMessage = frozenInitialScrollTarget {
                frozenInitialScrollTarget = viewModel.messages.last.map { .bottom(messageId: $0.id) }
                isPinnedToBottom = true
            }
        }
    }

    private func refreshFrozenScrollTargetForReactionHighlight() {
        guard let highlightId = preferredReactionHighlightMessageId() else { return }
        frozenInitialScrollTarget = .highlightedMessage(messageId: highlightId)
    }

    private func messageRowIsLaidOut(_ messageId: String) -> Bool {
        for row in viewModel.chatRenderRows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message) where message.id == messageId:
                return true
            case .mediaCluster(let messages) where messages.contains(where: { $0.id == messageId }):
                return true
            default:
                continue
            }
        }
        return false
    }

    private func messageIsReadyForScroll(_ messageId: String) -> Bool {
        viewModel.messages.contains(where: { $0.id == messageId })
            && messageRowIsLaidOut(messageId)
    }

    private func resolveInitialScrollTarget() -> ChatScrollTarget? {
        reloadNotificationOpenIntent()

        if let highlightId = preferredReactionHighlightMessageId() {
            return .highlightedMessage(messageId: highlightId)
        }

        if let unreadId = viewModel.messages.first(where: {
            !$0.isRead && $0.senderId != viewModel.currentUserId
        })?.id {
            return .firstUnread(messageId: unreadId)
        }

        if let lastId = viewModel.messages.last?.id {
            return .bottom(messageId: lastId)
        }
        return nil
    }

    private func messageRowId(containingMessageId messageId: String) -> String? {
        for row in viewModel.chatRenderRows {
            guard case .message(let item) = row else { continue }
            switch item {
            case .single(let message) where message.id == messageId:
                return item.id
            case .mediaCluster(let messages) where messages.contains(where: { $0.id == messageId }):
                return item.id
            default:
                continue
            }
        }
        return messageId
    }

    private func scrollToTarget(_ target: ChatScrollTarget, proxy: ScrollViewProxy, animated: Bool) {
        if target.pinsToBottom {
            suppressPinnedMetricsUpdates = true
        }
        let performScroll = {
            switch target {
            case .bottom:
                proxy.scrollTo(bottomScrollAnchorID, anchor: .bottom)
            case .firstUnread(let messageId):
                let rowId = messageRowId(containingMessageId: messageId) ?? messageId
                proxy.scrollTo(rowId, anchor: .top)
            case .highlightedMessage(let messageId):
                let rowId = messageRowId(containingMessageId: messageId) ?? messageId
                proxy.scrollTo(rowId, anchor: .center)
            }
        }

        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                performScroll()
            }
        } else {
            performScroll()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        _ = animated
        scheduleBottomSnap(using: proxy, reason: .userRequested)
    }

    private func finishInitialOpen(using proxy: ScrollViewProxy, pinsToBottom: Bool) {
        hasCompletedInitialScroll = true
        isPinnedToBottom = pinsToBottom
        if pinsToBottom {
            clearUnreadDividerAndMarkReadIfNeeded()
        }
        commitScrollStateToStore(includeFullState: true)
        viewModel.prefetchUnresolvedMediaIfNeeded()
        processPendingReactionHighlights(using: proxy)
        processPendingBuzz(using: proxy)
        scheduleNotificationBuzzRetries(using: proxy)
        clearNotificationOpenIntentIfFinished()
    }

    private func scheduleInitialScroll(proxy: ScrollViewProxy) {
        reloadNotificationOpenIntent()
        reconcileScrollStateForCurrentConversation()

        if shouldOpenAtBottom() {
            if isPinnedToBottom {
                scheduleInitialBottomSnap(using: proxy)
            }
            return
        }

        let hasHighlightIntent = preferredReactionHighlightMessageId() != nil

        if hasCompletedInitialScroll,
           !ChatScrollStateStore.shouldRunInitialScroll(for: conversationId, hasHighlightIntent: hasHighlightIntent) {
            return
        }

        refreshFrozenScrollTargetForReactionHighlight()
        if frozenInitialScrollTarget == nil {
            frozenInitialScrollTarget = resolveInitialScrollTarget()
        }

        guard !viewModel.messages.isEmpty else { return }
        guard initialScrollTask == nil else { return }

        initializeUnreadDividerIfNeeded()

        guard let target = frozenInitialScrollTarget else { return }

        if target.pinsToBottom {
            scheduleInitialBottomSnap(using: proxy)
            return
        }

        if target.isFirstUnread || target.isHighlightedMessage {
            isPinnedToBottom = false
        }

        initialScrollTask = Task { @MainActor in
            defer { initialScrollTask = nil }

            let isHighlight: Bool
            var highlightMessageId: String?
            if case .highlightedMessage(let id) = target {
                isHighlight = true
                highlightMessageId = id
            } else {
                isHighlight = false
            }

            let delays: [UInt64] = isHighlight
                ? [0, 150_000_000, 500_000_000, 1_200_000_000]
                : [0, 120_000_000]

            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !hasCompletedInitialScroll else { return }
                guard !viewModel.messages.isEmpty else { continue }

                if isHighlight {
                    refreshFrozenScrollTargetForReactionHighlight()
                    if let updatedId = preferredReactionHighlightMessageId() {
                        highlightMessageId = updatedId
                    }
                    guard let activeId = highlightMessageId else { continue }

                    if !viewModel.messages.contains(where: { $0.id == activeId }) {
                        if viewModel.canLoadMore, !viewModel.isLoadingMore {
                            viewModel.loadMoreMessages()
                        }
                        continue
                    }
                    guard messageIsReadyForScroll(activeId) else { continue }

                    scrollToTarget(.highlightedMessage(messageId: activeId), proxy: proxy, animated: true)
                    finishInitialOpen(using: proxy, pinsToBottom: false)
                    return
                }

                scrollToTarget(target, proxy: proxy, animated: false)
            }

            guard !Task.isCancelled, !hasCompletedInitialScroll else { return }

            if isHighlight, let activeId = highlightMessageId ?? preferredReactionHighlightMessageId() {
                guard messageIsReadyForScroll(activeId) else {
                    scheduleSingleHighlightScrollIfNeeded(using: proxy)
                    return
                }
                scrollToTarget(.highlightedMessage(messageId: activeId), proxy: proxy, animated: false)
                finishInitialOpen(using: proxy, pinsToBottom: false)
            } else {
                finishInitialOpen(using: proxy, pinsToBottom: target.pinsToBottom)
            }
        }
    }

    private func scheduleNotificationBuzzRetries(using proxy: ScrollViewProxy) {
        guard notificationOpenIntent?.playBuzzOnOpen == true, !didProcessNotificationBuzz else { return }

        Task { @MainActor in
            let retryDelays: [UInt64] = [250_000_000, 700_000_000, 1_500_000_000, 2_500_000_000]
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !didProcessNotificationBuzz else { return }
                reloadNotificationOpenIntent()
                processPendingBuzz(using: proxy)
            }
        }
    }

    private func scheduleSingleHighlightScrollIfNeeded(using proxy: ScrollViewProxy) {
        reloadNotificationOpenIntent()
        guard let ids = notificationOpenIntent?.highlightMessageIds, ids.count == 1, let messageId = ids.first else { return }
        guard highlightScrollTask == nil else { return }

        highlightScrollTask = Task { @MainActor in
            defer { highlightScrollTask = nil }

            let delays: [UInt64] = [
                0,
                200_000_000,
                600_000_000,
                1_500_000_000,
                3_000_000_000
            ]

            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                reloadNotificationOpenIntent()
                guard notificationOpenIntent?.highlightMessageIds.contains(messageId) == true else { return }

                if messageIsReadyForScroll(messageId) {
                    hasCompletedInitialScroll = true
                    isPinnedToBottom = false
                    scrollToTarget(.highlightedMessage(messageId: messageId), proxy: proxy, animated: true)
                    highlightMessages([messageId], proxy: nil, duration: ChatBubbleAnchorMetrics.highlightDuration, scroll: false)
                    if let conversationId = viewModel.conversation.id {
                        ChatNavigationIntentStore.clearHighlights(for: conversationId)
                        reloadNotificationOpenIntent()
                        clearNotificationOpenIntentIfFinished()
                    }
                    return
                }

                if !viewModel.messages.contains(where: { $0.id == messageId }),
                   viewModel.canLoadMore,
                   !viewModel.isLoadingMore {
                    viewModel.loadMessageForHighlightIfNeeded(messageId: messageId)
                    viewModel.loadMoreMessages()
                } else if !viewModel.messages.contains(where: { $0.id == messageId }) {
                    viewModel.loadMessageForHighlightIfNeeded(messageId: messageId)
                }
            }
        }
    }

    private func reloadNotificationOpenIntent() {
        guard let conversationId = viewModel.conversation.id else { return }
        notificationOpenIntent = ChatNavigationIntentStore.peek(for: conversationId)
    }

    private func clearNotificationOpenIntentIfFinished() {
        guard let conversationId = viewModel.conversation.id else { return }
        guard let intent = notificationOpenIntent else { return }

        let highlightsPending = !intent.highlightMessageIds.isEmpty
        let buzzPending = intent.playBuzzOnOpen && !didProcessNotificationBuzz
        guard !highlightsPending, !buzzPending else { return }

        ChatNavigationIntentStore.clear(for: conversationId)
        notificationOpenIntent = nil
    }

    private func initializeUnreadDividerIfNeeded() {
        guard !unreadDividerInitialized else { return }
        guard !viewModel.messages.isEmpty else { return }

        unreadDividerMessageId = viewModel.messages.first {
            !$0.isRead && $0.senderId != viewModel.currentUserId
        }?.id
        unreadDividerInitialized = true
    }

    private func shouldShowUnreadDivider(before item: MessageItem) -> Bool {
        guard let dividerId = unreadDividerMessageId else { return false }
        return item.id == dividerId
    }

    private func updateSearchMatches() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchMatchIds = []
            currentSearchMatchIndex = 0
            pendingSearchTargetId = nil
            return
        }

        let normalizedQuery = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let matches = viewModel.messages.filter { message in
            let searchable = [message.content, message.preview]
                .compactMap { $0 }
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return searchable.contains(normalizedQuery)
        }
        .map(\.id)

        searchMatchIds = matches

        guard !matches.isEmpty else {
            currentSearchMatchIndex = 0
            pendingSearchTargetId = nil
            return
        }

        if currentSearchMatchIndex >= matches.count {
            currentSearchMatchIndex = max(matches.count - 1, 0)
        }

        pendingSearchTargetId = matches[currentSearchMatchIndex]
    }

    private func moveSearchSelection(by step: Int) {
        guard !searchMatchIds.isEmpty else { return }
        let count = searchMatchIds.count
        currentSearchMatchIndex = (currentSearchMatchIndex + step + count) % count
        pendingSearchTargetId = searchMatchIds[currentSearchMatchIndex]
    }

    // MARK: - Clustering Logic
    private func clusterMessages(_ input: [EnhancedMessage]) -> [MessageItem] {
        ClusterMessageGrouper.group(input)
    }

    // ✅ JUMP TO MESSAGE: Scrollear hacia un mensaje específico con efecto visual
    private func jumpToMessage(_ messageId: String, proxy: ScrollViewProxy) {
        highlightMessages([messageId], proxy: proxy, duration: ChatBubbleAnchorMetrics.highlightDuration)
    }

    private func highlightMessages(
        _ messageIds: Set<String>,
        proxy: ScrollViewProxy?,
        duration: TimeInterval = ChatBubbleAnchorMetrics.highlightDuration,
        scroll: Bool = true
    ) {
        guard !messageIds.isEmpty else { return }

        if scroll, let proxy, let targetId = messageIds.first {
            let rowId = messageRowId(containingMessageId: targetId) ?? targetId
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(rowId, anchor: .center)
            }
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            flashingMessageIds.formUnion(messageIds)
        }
        HapticManager.shared.mediumImpact()

        let idsToClear = messageIds
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                flashingMessageIds.subtract(idsToClear)
            }
        }
    }

    private func processPendingReactionHighlights(using proxy: ScrollViewProxy) {
        if case .highlightedMessage(let messageId) = frozenInitialScrollTarget {
            var ids = pendingReactionHighlightIds
            ids.insert(messageId)
            if let stored = notificationOpenIntent?.highlightMessageIds {
                ids.formUnion(stored)
            }
            pendingReactionHighlightIds.removeAll()
            if !ids.isEmpty {
                highlightMessages(ids, proxy: nil, duration: 1.2, scroll: false)
            }
            if let conversationId = viewModel.conversation.id {
                ChatNavigationIntentStore.clearHighlights(for: conversationId)
                reloadNotificationOpenIntent()
                clearNotificationOpenIntentIfFinished()
            }
            return
        }

        var ids = pendingReactionHighlightIds
        if let stored = notificationOpenIntent?.highlightMessageIds {
            ids.formUnion(stored)
        }
        guard !ids.isEmpty else { return }
        pendingReactionHighlightIds.removeAll()
        let shouldScroll = hasExplicitReactionHighlightIntent()
        highlightMessages(ids, proxy: shouldScroll ? proxy : nil, scroll: shouldScroll)

        if let conversationId = viewModel.conversation.id {
            ChatNavigationIntentStore.clearHighlights(for: conversationId)
            reloadNotificationOpenIntent()
            clearNotificationOpenIntentIfFinished()
        }
    }

    private func processPendingBuzz(using proxy: ScrollViewProxy) {
        guard !didProcessNotificationBuzz else { return }
        reloadNotificationOpenIntent()
        guard let intent = notificationOpenIntent, intent.playBuzzOnOpen else { return }
        guard let event = resolvePendingBuzzEvent(for: intent) else { return }
        guard event.senderId != viewModel.currentUserId else {
            didProcessNotificationBuzz = true
            clearNotificationOpenIntentIfFinished()
            return
        }

        didProcessNotificationBuzz = true

        let message = String(
            format: NSLocalizedString("chat.buzz.received", comment: "Incoming buzz toast"),
            otherParticipantDisplayName
        )
        triggerBuzzEffect(text: message, isLocal: false, showsToast: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                proxy.scrollTo("buzz-\(event.id)", anchor: .center)
            }
        }

        if let conversationId = viewModel.conversation.id {
            ChatNavigationIntentStore.clear(for: conversationId)
            notificationOpenIntent = nil
        }
    }

    private func resolvePendingBuzzEvent(
        for intent: ChatNavigationIntentStore.OpenIntent
    ) -> ChatBuzzEvent? {
        if let buzzEventId = intent.buzzEventId,
           !buzzEventId.isEmpty,
           let event = viewModel.buzzEvents.first(where: { $0.id == buzzEventId }) {
            return event
        }

        if intent.buzzEventId != nil {
            return nil
        }

        let recentCutoff = Date().addingTimeInterval(-300)
        return viewModel.buzzEvents
            .filter { $0.senderId != viewModel.currentUserId && $0.createdAt >= recentCutoff }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    private func handleMomentNavigationFromChat(message: EnhancedMessage) {
        if let sharedMomentData = message.sharedMomentData,
           let momentId = sharedMomentData["momentId"] {

            // ✅ CORREGIDO: Obtener el authorId del momento compartido o usar el senderId como fallback
            let authorId = sharedMomentData["momentAuthorId"] ?? message.senderId

            firestoreService.fetchMoment(momentId: momentId, userId: authorId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(var moment):
                        if moment.id == nil {
                            moment.id = momentId
                        }
                        self.selectedMoment = moment
                        self.showingMomentDetail = true
                    case .failure:
                        self.showingMomentError = true
                    }
                }
            }
        }
    }

    private func handleStoryNavigationFromChat(message: EnhancedMessage) {
        guard let sharedStoryData = message.sharedStoryData,
              let storyId = sharedStoryData["storyId"],
              let viewerId = Auth.auth().currentUser?.uid else { return }

        let authorId = sharedStoryData["storyAuthorId"] ?? message.senderId
        guard !authorId.isEmpty else {
            storyUnavailableReason = .restricted
            showingStoryUnavailable = true
            return
        }

        let payloadExpiration = sharedStoryData["storyExpiration"].flatMap { TimeInterval($0) }

        SharedStoryAccessEvaluator.evaluate(
            authorId: authorId,
            storyId: storyId,
            payloadExpiration: payloadExpiration,
            viewerId: viewerId
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let story):
                    storyRoute = ChatStoryRoute(story: story)
                case .failure(let reason):
                    storyUnavailableReason = reason
                    showingStoryUnavailable = true
                }
            }
        }
    }
}

// MARK: - Enhanced MomentsChatViewModel with Better Audio Deletion
class MomentsChatViewModel: EnhancedChatViewModel {
    @Published var groupedMessages: [(Date, [EnhancedMessage])] = []
    @Published private(set) var chatRenderRows: [ChatRenderRow] = []
    @Published var messagesSentThisSession: Int = 0
    private let chatService = ChatService.shared // ✅ Cambiar a Shared

    private enum TimelineEntry {
        case message(EnhancedMessage)
        case buzz(ChatBuzzEvent)

        var timestamp: Date {
            switch self {
            case .message(let message): return message.timestamp
            case .buzz(let event): return event.createdAt
            }
        }
    }

    override init(conversation: Conversation) {
        super.init(conversation: conversation)
    }

    /// Sincroniza agrupación por fecha y filas planas de render en un solo paso @Published.
    func syncMessagePresentation() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        groupedMessages = grouped
            .map { ($0.key, $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.0 < $1.0 }

        var rows: [ChatRenderRow] = []
        let dayKeys = Set(messages.map { calendar.startOfDay(for: $0.timestamp) })
            .union(buzzEvents.map { calendar.startOfDay(for: $0.createdAt) })
            .sorted()

        for day in dayKeys {
            rows.append(.header(day))

            let messageEntries = messages
                .filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
                .map(TimelineEntry.message)
            let buzzEntries = buzzEvents
                .filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
                .map(TimelineEntry.buzz)
            let entries = (messageEntries + buzzEntries).sorted { lhs, rhs in
                lhs.timestamp < rhs.timestamp
            }

            var pendingMessages: [EnhancedMessage] = []
            func flushPendingMessages() {
                guard !pendingMessages.isEmpty else { return }
                for item in ClusterMessageGrouper.group(pendingMessages) {
                    rows.append(.message(item))
                }
                pendingMessages.removeAll()
            }

            for entry in entries {
                switch entry {
                case .message(let message):
                    pendingMessages.append(message)
                case .buzz(let event):
                    flushPendingMessages()
                    rows.append(.buzz(event))
                }
            }
            flushPendingMessages()
        }
        chatRenderRows = rows
    }

    func updateGroupedMessages() {
        syncMessagePresentation()
    }

    override func sendTextMessage(_ content: String, replyTo: String? = nil) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.text", comment: "Invalid conversation ID when sending text")
            return
        }

        // Track antes de enviar

        messagesSentThisSession += 1

        // ✅ USAR el método de la clase padre que maneja mensajes temporales
        super.sendTextMessage(content, replyTo: replyTo)
    }

    func trackMediaMessageSent(type: String) {
        messagesSentThisSession += 1
    }

    // MARK: - Enhanced Delete Message Actions
    override func deleteMessageForEveryone(_ message: EnhancedMessage) {

        chatService.deleteMessageWithCleanup(conversationId: message.conversationId, messageId: message.id) { _ in }
        objectWillChange.send()
    }

    override func deleteMessageForMe(_ message: EnhancedMessage) {

        chatService.deleteMessageForMe(conversationId: message.conversationId, messageId: message.id, userId: currentUserId) { [weak self] _ in
            DispatchQueue.main.async {
                self?.messages.removeAll { $0.id == message.id }
                self?.updateGroupedMessages()
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - New Media Message Functions
    func sendImageMessage(_ imageData: Data) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.image", comment: "Invalid conversation ID when sending image")
            return
        }

        trackMediaMessageSent(type: "image")

        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(data: imageData, fileExtension: "jpg")
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaUrl: localPreview,
            status: .sending
        )

        appendOutgoingMessage(tempMessage)

        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaData: imageData,
            messageId: messageId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? localPreview,
                        thumbnailUrl: sentMessage.thumbnailUrl
                    )
                case .failure(let error):
                    self?.error = String(format: NSLocalizedString("chat.error.sendImage", comment: "Image send error"), error.localizedDescription)
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func sendAudioMessage(_ audioData: Data, duration: TimeInterval) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.audio", comment: "Invalid conversation ID when sending audio")
            return
        }

        trackMediaMessageSent(type: "audio")

        // ✅ Crear mensaje local inmediatamente para feedback visual (preview local como imágenes)
        let messageId = UUID().uuidString
        let localPreview = localOutgoingPreviewURL(data: audioData, fileExtension: "m4a")
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .audio,
            content: nil,
            mediaUrl: localPreview,
            thumbnailUrl: nil,
            duration: duration,
            status: .sending
        )

        appendOutgoingMessage(tempMessage)

        chatService.sendAudioMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            audioData: audioData,
            duration: duration,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? localPreview,
                        thumbnailUrl: sentMessage.thumbnailUrl
                    )
                case .failure(let error):
                    self?.error = String(format: NSLocalizedString("chat.error.sendAudio", comment: "Audio send error"), error.localizedDescription)
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // ✅ NUEVA función para enviar mensajes view-once
    func sendViewOnceMessage(data: Data, mediaType: EnhancedCameraPickerView.MediaType) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.viewOnce", comment: "Invalid conversation ID when sending view-once message")
            return
        }

        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let messageType: MessageType = mediaType == .image ? .viewOnceImage : .viewOnceVideo

        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: messageType,
            status: .sending,
            isViewed: false
        )

        appendOutgoingMessage(tempMessage)

        chatService.sendViewOnceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            mediaData: data,
            mediaType: mediaType,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    // ✅ Usar el estado devuelto (puede ser .pending si es offline)
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                case .failure(let error):
                    self?.error = String(format: NSLocalizedString("chat.error.sendMessage", comment: "Message send error"), error.localizedDescription)
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }

        messagesSentThisSession += 1
    }

    // ✅ NUEVA función para enviar video normal
    override func sendVideoMessage(data: Data) {
        trackMediaMessageSent(type: "video")
        // Reutilizar flujo base para mantener estados locales (sending/pending/failed)
        super.sendVideoMessage(data: data)
    }

    // MARK: - GIF / Sticker

    /// Envía un GIF de Giphy por referencia (URL pública, sin cifrado ni re-subida).
    func sendGif(from asset: ChatGiphyAsset) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.image", comment: "")
            return
        }

        trackMediaMessageSent(type: "gif")
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .gif,
            mediaUrl: asset.url,
            mediaWidth: asset.width > 0 ? asset.width : nil,
            mediaHeight: asset.height > 0 ? asset.height : nil,
            status: .sending
        )
        appendOutgoingMessage(tempMessage)

        chatService.sendGiphyReferenceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .gif,
            giphyId: asset.id,
            mediaUrl: asset.url,
            width: asset.width,
            height: asset.height,
            messageId: messageId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? asset.url,
                        thumbnailUrl: nil
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    /// Envía un sticker de Giphy por referencia (URL pública, sin cifrado ni re-subida).
    func sendSticker(from asset: ChatStickerAsset) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.image", comment: "")
            return
        }

        ChatRecentStickersStore.add(asset)
        trackMediaMessageSent(type: "sticker")
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .sticker,
            mediaUrl: asset.url,
            mediaWidth: asset.width > 0 ? asset.width : nil,
            mediaHeight: asset.height > 0 ? asset.height : nil,
            status: .sending
        )
        appendOutgoingMessage(tempMessage)

        chatService.sendGiphyReferenceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .sticker,
            giphyId: asset.id,
            mediaUrl: asset.url,
            width: asset.width,
            height: asset.height,
            messageId: messageId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.applyOutgoingMessageUpdate(
                        messageId: messageId,
                        status: sentMessage.status,
                        mediaUrl: sentMessage.mediaUrl ?? asset.url,
                        thumbnailUrl: nil
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // MARK: - Ubicación fija

    func sendStaticLocation(coordinate: CLLocationCoordinate2D, name: String?, address: String?) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.text", comment: "")
            return
        }
        trackMediaMessageSent(type: "location")

        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .location,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationName: name,
            locationAddress: address,
            isLiveLocation: false,
            status: .sending
        )
        appendOutgoingMessage(tempMessage)

        ChatService.shared.sendStaticLocationMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name,
            address: address,
            messageId: messageId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    // MARK: - Ubicación en vivo

    func startLiveLocation(duration: LiveLocationDuration) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = NSLocalizedString("chat.error.invalidConversation.text", comment: "")
            return
        }
        guard let location = LocationUtilities.shared.currentLocation else {
            // Sin ubicación todavía: solicitar permiso y avisar.
            LocationUtilities.shared.requestLocationPermission()
            error = NSLocalizedString("chat.location.permissionNeeded", comment: "")
            return
        }

        trackMediaMessageSent(type: "liveLocation")

        let coordinate = location.coordinate
        let messageId = UUID().uuidString
        let sessionId = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(duration.timeInterval)

        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .location,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            isLiveLocation: true,
            liveLocationExpiresAt: expiresAt,
            liveLocationDuration: duration.firestoreValue,
            liveLocationSessionId: sessionId,
            locationUpdatedAt: Date(),
            status: .sending
        )
        appendOutgoingMessage(tempMessage)

        ChatService.shared.sendLiveLocationMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: nil,
            address: nil,
            duration: duration,
            sessionId: sessionId,
            expiresAt: expiresAt,
            messageId: messageId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
                    LiveLocationSharingService.shared.startSession(
                        conversationId: conversationId,
                        messageId: messageId,
                        sessionId: sessionId,
                        duration: duration,
                        expiresAt: expiresAt
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }

    func stopLiveLocation(messageId: String) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else { return }
        LiveLocationSharingService.shared.stopSharing(
            messageId: messageId,
            conversationId: conversationId
        )
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].liveLocationStoppedAt = Date()
            updateGroupedMessages()
            objectWillChange.send()
        }
    }
}

private struct ChatScrollMetrics: Equatable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
}

@MainActor
private final class ChatScrollMetricsBuffer {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    func ingest(_ metrics: ChatScrollMetrics) {
        offsetY = metrics.offsetY
        contentHeight = metrics.contentHeight
        viewportHeight = metrics.viewportHeight
    }

    var metrics: ChatScrollMetrics {
        ChatScrollMetrics(offsetY: offsetY, contentHeight: contentHeight, viewportHeight: viewportHeight)
    }
}

private struct ChatScrollRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension View {
    func trackChatScrollRowFrame(id: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ChatScrollRowFrameKey.self,
                    value: [id: geometry.frame(in: .scrollView(axis: .vertical))]
                )
            }
        }
    }
}
