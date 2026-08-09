import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import CoreLocation
import MapKit

struct ChatStoryRoute: Identifiable {
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

struct ViewOnceViewerPresentation: Identifiable {
    let id = UUID()
    let message: EnhancedMessage
    let authorName: String
    let isReplaySession: Bool

    var zoomSourceID: String {
        "view-once-\(message.id)"
    }
}

// MARK: - Glassmorphic Chat View
// Actualizar GlassmorphicChatView para incluir navegación
struct GlassmorphicChatView: View {
    @ObservedObject var session: ConversationChatSession
    @StateObject var onlineStatusService = OnlineStatusService()
    @StateObject var keyboardScrollCoordinator = ChatKeyboardScrollCoordinator()
    @StateObject var pendingMessageRequestService = MessageRequestService()
    @State var messageText: String = ""
    @State var pendingChatContext: PendingChatContext?
    @State var conversationIntroContext: PendingChatContext?
    @State var showEnhancedCamera = false
    @StateObject var micGate = PermissionPrimerGate(.microphone)
    @State var pendingCameraReplyToMessageId: String?
    @State var viewOnceViewerPresentation: ViewOnceViewerPresentation?
    @State var activeAttachmentSheet: ChatAttachmentSheetKind?
    @State var plusButtonAnchorFrame: CGRect = .zero
    @State var replyingTo: EnhancedMessage?
    @State var clusterForReply: [EnhancedMessage]? = nil // ✅ New: Selection grid for clusters
    @State var clusterGallerySelection: ClusterGallerySelection? = nil
    @State var editingMessage: EnhancedMessage?
    @State var messageMenuSelection: ChatMessageMenuSelection? = nil
    @State var showingReactionEmojiPicker = false
    @State var reactionPickerMessage: EnhancedMessage?
    @State var forwardingMessage: EnhancedMessage?
    @State var showCameraSheet = false
    @State var isRecordingVoice = false
    @State var isVoiceRecordingLocked = false
    @State var isPreparingVoiceRecordingPreview = false
    @State var voiceRecordingInteractionId: UUID?
    @State var voiceRecordingDraft: VoiceRecordingDraft?
    @StateObject var voiceRecordingGestureState = VoiceRecordingGestureState()
    @State var recordingTime: TimeInterval = 0
    @State var recordingTimer: Timer?
    @State var showingConversationSettings = false
    @State var showingReportSheet = false
    @State var flashingMessageIds: Set<String> = []
    @State var pendingReactionHighlightIds: Set<String> = []
    @State var notificationOpenIntent: ChatNavigationIntentStore.OpenIntent?
    @State var isPinnedToBottom = true
    @State var listIsAtBottom = true
    @StateObject var chatListController = ChatMessageListController()
    @State var pendingIncomingMessages = 0
    @State var unreadDividerMessageId: String? = nil
    @State var unreadDividerCount = 0
    @State var unreadDividerInitialized = false
    @State var hasCompletedInitialScroll = false
    @State var didReapplyFrozenScrollPosition = false
    @State var didHydrateScrollStateOnce = false
    @State var initialScrollTask: Task<Void, Never>? = nil
    @State var highlightScrollTask: Task<Void, Never>? = nil
    @State var frozenInitialScrollTarget: ChatScrollTarget? = nil
    @State var listBottomSnapTask: Task<Void, Never>? = nil
    @State var pendingInitialScrollRoute = false
    @State var scrollContentExceedsViewport = false
    @State var lastComposerHeight: CGFloat = ChatComposerChromeMetrics.estimatedComposerChromeHeight
    @State var composerSnapTask: Task<Void, Never>?
    @State var pendingPinnedBottomSnap = false
    @State var pendingReplyScrollMessageId: String?
    let bottomScrollAnchorID = "chat-bottom-anchor"
    @State var isSearchVisible = false
    @State var searchQuery: String = ""
    @State var searchMatchIds: [String] = []
    @State var currentSearchMatchIndex: Int = 0
    @State var pendingSearchTargetId: String? = nil
    @State var pendingSearchHighlightId: String? = nil
    @State var deferredJumpToMessageId: String? = nil
    @State var searchHighlightScrollTask: Task<Void, Never>? = nil
    @State var pendingScrollMessageId: String? = nil
    @State var buzzShakeProgress: CGFloat = 1
    @State var buzzShakeAmplitude: CGFloat = 18
    @State var buzzToastText: String?
    @State var buzzToastDismissTask: Task<Void, Never>?
    @State var lastBuzzSentAt: Date?
    @State var showVanishTimerSheet = false
    @State var didRunConsumedViewOnceCleanup = false

    @Environment(\.colorScheme) var colorScheme
    @State var screenshotObserver: NSObjectProtocol?
    @State var screenshotTakenObserver: NSObjectProtocol?
    @State var otherUserStatus: OnlineStatus = .offline
    @State var otherUserLastSeen: Date?
    @State var statusListener: ListenerRegistration?
    @FocusState var isTextFieldFocused: Bool
    @FocusState var isSearchFieldFocused: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Namespace var viewOnceZoomNamespace
    let privacyService = PrivacyService()
    let firestoreService = FirestoreService()
    let onPendingChatAccepted: ((String) -> Void)?
    let onPendingChatDismissed: (() -> Void)?

    // ✅ NUEVO: Estados para navegación al perfil
    @State var showingUserProfile = false
    @Namespace var profileZoomNamespace
    @State var navigateToProfile = false

    // ✅ NUEVO: Estados para navegación al momento
    @State var showingMomentDetail = false
    @State var selectedMoment: Moment?
    @State var showingMomentError = false
    @State var showingStoryUnavailable = false
    @State var storyUnavailableReason: SharedStoryAccessDenialReason?

    // ✅ Ruta estable para presentar historias (header del chat o historia compartida en mensaje)
    @State var storyRoute: ChatStoryRoute?

    // ✅ HISTORIAS: Estados para anillo de historias
    @State var hasStory: Bool = false
    @State var hasUnseenStory: Bool = false
    @State var storyCount: Int = 0
    @State var storyViewedStatus: [Bool] = []
    @State var storyAudiences: [String?] = []
    @State var liveOtherParticipantUsername: String = ""
    @State var isOtherParticipantUnavailable: Bool = false
    @State var isOtherParticipantBlockedByCurrentUser: Bool = false

    // ✅ REACCIONES: Nuevo estado para Overlay
    @State var reactionMessageOverlay: EnhancedMessage? = nil
    @State var selectedChatMedia: SharedMedia?
    @State var selectedChatMediaItems: [SharedMedia] = []

    var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var otherParticipantDisplayName: String {
        let fallback = viewModel.conversation.otherParticipantUsername ?? "Usuario"
        let live = liveOtherParticipantUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return live.isEmpty ? fallback : live
    }

    var searchCounterText: String {
        guard !searchMatchIds.isEmpty else {
            return String(format: NSLocalizedString("chat.search.results", comment: "Search match counter"), 0, 0)
        }
        let current = min(max(currentSearchMatchIndex + 1, 1), searchMatchIds.count)
        return String(
            format: NSLocalizedString("chat.search.results", comment: "Search match counter"),
            current,
            searchMatchIds.count
        )
    }

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var floatingNavigationState: ChatFloatingNavigationState {
        ChatFloatingNavigationState.resolve(
            hasCompletedInitialScroll: hasCompletedInitialScroll,
            isSearchVisible: isSearchVisible,
            isSearchingHistory: viewModel.isSearchingHistory,
            hasSearchQuery: !trimmedSearchQuery.isEmpty,
            isPinnedToBottom: isPinnedToBottom
        )
    }

    var canSearchGoUp: Bool {
        !searchMatchIds.isEmpty && currentSearchMatchIndex > 0
    }

    var floatingNavigationBottomInset: CGFloat {
        ChatComposerChromeMetrics.floatingControlBottomInset(composerChromeHeight: lastComposerHeight)
    }

    var canSearchGoDown: Bool {
        guard isSearchVisible, !trimmedSearchQuery.isEmpty else { return false }
        if !searchMatchIds.isEmpty {
            let isLastMatch = currentSearchMatchIndex >= searchMatchIds.count - 1
            if isLastMatch {
                return !isPinnedToBottom || chatListController.distanceFromBottom > 16
            }
            return true
        }
        return !isPinnedToBottom || chatListController.distanceFromBottom > 16
    }

    var attachmentPickerSheetBinding: Binding<ChatAttachmentSheetKind?> {
        Binding(
            get: {
                guard let sheet = activeAttachmentSheet, sheet.isPickerSheet else { return nil }
                return sheet
            },
            set: { activeAttachmentSheet = $0 }
        )
    }

    var viewModel: ConversationChatSession { session }

    var conversationId: String {
        viewModel.conversation.id ?? ""
    }

    var draftStorageKey: String {
        viewModel.conversation.id ?? "pending:\(viewModel.conversation.otherParticipantId)"
    }

    var quickReactionEmoji: String { "❤️" }

    init(
        conversation: Conversation,
        session: ConversationChatSession? = nil,
        pendingChatContext: PendingChatContext? = nil,
        onPendingChatAccepted: ((String) -> Void)? = nil,
        onPendingChatDismissed: (() -> Void)? = nil
    ) {
        let resolved = session ?? ChatSessionEngine.shared.session(for: conversation)
        let draftKey = conversation.id ?? "pending:\(conversation.otherParticipantId)"
        _session = ObservedObject(wrappedValue: resolved)
        _messageText = State(initialValue: ChatDraftStore.shared.draft(for: draftKey))
        _pendingChatContext = State(initialValue: pendingChatContext)
        // Cada apertura arranca fresca y va al fondo (no se restaura posición).
        _hasCompletedInitialScroll = State(initialValue: false)
        _isPinnedToBottom = State(initialValue: true)
        _didReapplyFrozenScrollPosition = State(initialValue: false)
        self.onPendingChatAccepted = onPendingChatAccepted
        self.onPendingChatDismissed = onPendingChatDismissed
    }

    // ✅ REFACTOR: Dividido en variables separadas para evitar el error del compilador (timeout AST)
    var baseChatView: some View {
        chatRootContent
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(isSearchVisible ? .hidden : .visible, for: .navigationBar)
            .toolbar { chatToolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isSearchVisible {
                    chatSearchNavigationHeader
                }
            }
            .chatInteractivePopEnabled()
        .permissionPrimerGate(micGate)
        .fullScreenCover(isPresented: $showEnhancedCamera) {
            ChatCameraView(
                otherUserId: viewModel.conversation.otherParticipantId,
                otherUsername: otherParticipantDisplayName
            ) { data, mediaType, mode, overlayPayload in
                handleCameraCapture(data: data, mediaType: mediaType, mode: mode, overlayPayload: overlayPayload)
            }
        }
        .fullScreenCover(item: $viewOnceViewerPresentation) { presentation in
            ViewOnceImmersiveViewer(
                message: presentation.message,
                authorName: presentation.authorName,
                onViewed: {
                    handleViewOnceViewerViewed(presentation)
                },
                isReplaySession: presentation.isReplaySession,
                onReplayConsumed: {
                    handleViewOnceReplayConsumed(presentation)
                },
                onSendReply: { text in
                    viewModel.sendTextMessage(text, replyTo: presentation.message.id)
                },
                onSendReaction: { emoji in
                    viewModel.sendTextMessage(emoji, replyTo: presentation.message.id)
                },
                onOpenCameraReply: {
                    openCameraForReply(to: presentation.message.id)
                }
            )
            .interactiveDismissDisabled(true)
            .navigationTransition(.zoom(sourceID: presentation.zoomSourceID, in: viewOnceZoomNamespace))
        }
        .onChange(of: activeAttachmentSheet) { _, newValue in
            guard newValue != nil else { return }
            isTextFieldFocused = false
        }
        .onChange(of: messageText) { _, newValue in
            guard editingMessage == nil else { return }
            ChatDraftStore.shared.setDraft(newValue, for: draftStorageKey)
        }
        .task {
            await enrichPendingChatContextIfNeeded()
            await loadConversationIntroContextIfNeeded()
        }
    }

    /// Completa el contexto pendiente con stats y relación social (como hace el emisor)
    /// cuando el chat se abrió con datos mínimos cacheados de la solicitud.
    func enrichPendingChatContextIfNeeded() async {
        guard let context = pendingChatContext,
              context.direction == .incoming,
              context.viewerFollowsOther == nil,
              let request = context.request,
              let viewerId = Auth.auth().currentUser?.uid else { return }

        let enriched = await PendingChatContextFactory.incoming(request: request, viewerId: viewerId)
        guard pendingChatContext?.request?.id == request.id,
              pendingChatContext?.status == .incomingRequestPending else { return }
        pendingChatContext = enriched
    }

    /// Replica el bloque social del intro de requests en conversaciones normales,
    /// pero con caché TTL para no rehacer lecturas cada vez que se abre el chat.
    func loadConversationIntroContextIfNeeded() async {
        guard pendingChatContext == nil,
              conversationIntroContext == nil,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        let context = await PendingChatContextFactory.conversationIntro(
            for: viewModel.conversation,
            currentUserId: currentUserId
        )
        guard pendingChatContext == nil else { return }
        conversationIntroContext = context
    }

    var chatViewWithSettingsAndStories: some View {
        baseChatView
            .sheet(isPresented: $showingReportSheet) {
                ReportBottomSheet(
                    userId: viewModel.conversation.otherParticipantId,
                    username: otherParticipantDisplayName
                )
            }

            // ✅ NUEVO: Sheet para mostrar historias del usuario
            .fullScreenCover(item: $storyRoute) { route in
                // ≡ FeedPresentationModifier / MessagingView: inyectar FirestoreService o el fullScreenCover crashea.
                Group {
                    switch route.presentation {
                    case .userStories(let userId):
                        StoriesView(startWithUserId: .constant(userId))
                    case .sharedStory(let story):
                        StoriesView(chainStories: [story], startAtIndex: 0)
                    }
                }
                .environmentObject(FirestoreService.shared)
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
            .toolbar(isSearchVisible ? .hidden : .visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .momentsFloatingTabBarHidden()
            .background(adaptiveColors.chatBackground[0].ignoresSafeArea())
    }

    var clusterForReplyBinding: Binding<ClusterWrapper?> {
        Binding(
            get: { clusterForReply.map { ClusterWrapper(messages: $0) } },
            set: { clusterForReply = $0?.messages }
        )
    }

    var forwardingMessageBinding: Binding<ForwardMessageWrapper?> {
        Binding(
            get: { forwardingMessage.map { ForwardMessageWrapper(message: $0) } },
            set: { forwardingMessage = $0?.message }
        )
    }

    var chatViewWithNavigationDestinations: some View {
        chatViewWithSettingsAndStories
            .navigationDestination(isPresented: $showingConversationSettings) {
                ConversationSettingsView(
                    conversation: viewModel.conversation,
                    onJumpToMessage: { messageId in
                        deferredJumpToMessageId = messageId
                    },
                    onSearchRequested: {
                        showingConversationSettings = false
                        toggleChatSearch()
                    }
                )
                .toolbar(.hidden, for: .tabBar)
            }
            .onChange(of: showingConversationSettings) { _, isShowing in
                if !isShowing {
                    viewModel.refreshTypingIndicatorPreference()
                    viewModel.refreshForwardingPreference()
                    consumeDeferredJumpToMessageIfNeeded()
                }
            }
            .navigationDestination(isPresented: $showingUserProfile) {
                UserProfileView(userId: viewModel.conversation.otherParticipantId)
                    .userProfileZoomDestination(
                        userId: viewModel.conversation.otherParticipantId,
                        namespace: profileZoomNamespace
                    )
            }
            .navigationDestination(item: $clusterGallerySelection) { selection in
                clusterGalleryDestination(messageIds: selection.messageIds)
                    .toolbar(.hidden, for: .tabBar)
            }
    }

    var chatViewWithClusterSheets: some View {
        chatViewWithNavigationDestinations
            .sheet(item: clusterForReplyBinding) { wrapper in
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
    }

    var chatViewWithInteractionSheets: some View {
        chatViewWithClusterSheets
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
            .sheet(isPresented: $showVanishTimerSheet) {
                ChatVanishTimerSheet(
                    isPresented: $showVanishTimerSheet,
                    selectedTimer: viewModel.vanishMessageTimer,
                    onSelect: { timer in
                        viewModel.setVanishMessageTimer(timer)
                    }
                )
            }
            .sheet(item: forwardingMessageBinding) { wrapper in
                forwardMessageSheet(for: wrapper.message)
            }
    }

    @ViewBuilder
    func forwardMessageSheet(for message: EnhancedMessage) -> some View {
        ChatMessageForwardSheet(
            message: message,
            onDismiss: { forwardingMessage = nil },
            onForward: { userIds in
                viewModel.forwardTextMessage(message, toUserIds: userIds)
            }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    var chatViewWithLifecycleObservers: some View {
        chatViewWithInteractionSheets
            .onAppear {
                onAppearActions()
                initializeUnreadDividerIfNeeded()
            }
            .onDisappear {
                resetVoiceRecordingInteraction()
                onDisappearActions()
            }
            .onChange(of: isSearchVisible) { wasVisible, isVisible in
                guard wasVisible, !isVisible else { return }
                restoreLayoutAfterClosingSearch()
            }
            .onChange(of: viewModel.messages.map(\.id)) { _, _ in
                initializeUnreadDividerIfNeeded()
                if isSearchVisible && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    syncSearchMatchesFromViewModel()
                }
            }
            .onChange(of: searchQuery) { _, newValue in
                viewModel.performSearch(query: newValue)
            }
            .onChange(of: viewModel.searchResults) { _, _ in
                syncSearchMatchesFromViewModel()
            }
            .onChange(of: viewModel.latestBuzzEvent?.id) { _, _ in
                handleIncomingBuzzToastIfNeeded()
            }
            .onChange(of: messageMenuSelection) { _, newValue in
                if newValue == nil {
                    withAnimation { reactionMessageOverlay = nil }
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                guard viewModel.vanishModeActive, viewModel.vanishMessageTimer != .onceSeen else { return }
                viewModel.refreshVanishExpiryPresentation()
            }
    }

    var chatViewWithOverlays: some View {
        chatViewWithLifecycleObservers
            .fullScreenCover(item: $selectedChatMedia) { media in
                selectedChatMediaCover(media: media)
            }
            .animation(MotionPolicy.animation(MotionPolicy.Spring.sheet, value: activeAttachmentSheet), value: activeAttachmentSheet)
            .overlay {
                chatAttachmentOverlayContent
            }
    }

    func liveClusterGalleryMessages(messageIds: [String]) -> [EnhancedMessage] {
        messageIds.compactMap { id in
            viewModel.messages.first(where: { $0.id == id })
        }.filter { !$0.isDeleted }
    }

    @ViewBuilder
    func clusterGalleryDetailView(
        for selectedMessage: EnhancedMessage,
        dismissDetail: @escaping () -> Void
    ) -> some View {
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
                onClose: dismissDetail,
                onSendReply: { media, text, completion in
                    sendReplyToSharedMedia(media, text: text, completion: completion)
                }
            )
        }
    }

    @ViewBuilder
    func clusterGalleryDestination(messageIds: [String]) -> some View {
        ClusterGalleryView(
            messages: liveClusterGalleryMessages(messageIds: messageIds),
            currentUserId: viewModel.currentUserId,
            scope: .cluster,
            presentation: .pushed,
            onClose: {
                self.clusterGallerySelection = nil
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
            detail: clusterGalleryDetailView
        )
        .onAppear {
            let cluster = liveClusterGalleryMessages(messageIds: messageIds)
            if !cluster.isEmpty {
                viewModel.prefetchClusterGalleryMedia(cluster)
            }
        }
    }

    @ViewBuilder
    func selectedChatMediaCover(media: SharedMedia) -> some View {
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
    var chatAttachmentOverlayContent: some View {
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

    func handleIncomingBuzzToastIfNeeded() {
        guard let event = viewModel.latestBuzzEvent,
              event.senderId != viewModel.currentUserId else { return }
        let message = String(
            format: NSLocalizedString("chat.buzz.received", comment: "Incoming buzz toast"),
            otherParticipantDisplayName
        )
        triggerBuzzEffect(text: message, isLocal: false, showsToast: true)
        markBuzzEventProcessed(event)
    }

    func markBuzzEventProcessed(_ event: ChatBuzzEvent) {
        guard let conversationId = viewModel.conversation.id else { return }
        ChatBuzzProcessedStore.markProcessed(eventId: event.id, conversationId: conversationId)
    }

}
