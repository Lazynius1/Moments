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

private enum ChatScrollTarget: Equatable {
    case bottom(messageId: String)
    case firstUnread(messageId: String)

    var isFirstUnread: Bool {
        if case .firstUnread = self { return true }
        return false
    }
}

// MARK: - Glassmorphic Chat View
// Actualizar GlassmorphicChatView para incluir navegación
struct GlassmorphicChatView: View {
    @StateObject private var viewModel: MomentsChatViewModel
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var messageText: String = ""
    @State private var showEnhancedCamera = false
    @State private var activeAttachmentSheet: ChatAttachmentSheetKind?
    @State private var plusButtonAnchorFrame: CGRect = .zero
    @ObservedObject private var liveLocationService = LiveLocationSharingService.shared
    @State private var replyingTo: EnhancedMessage?
    @State private var clusterForReply: [EnhancedMessage]? = nil // ✅ New: Selection grid for clusters
    @State private var editingMessage: EnhancedMessage?
    @State private var messageMenuSelection: ChatMessageMenuSelection? = nil
    @State private var messageRowFrames: [String: CGRect] = [:]
    @State private var showingReactionEmojiPicker = false
    @State private var reactionPickerMessage: EnhancedMessage?
    @State private var forwardingMessage: EnhancedMessage?
    @State private var showCameraSheet = false
    @State private var isRecordingVoice = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var showingConversationSettings = false
    @State private var showingReportSheet = false
    @State private var highlightedMessageId: String? = nil // ✅ New: Jump to message highlight
    @State private var isPinnedToBottom = true
    @State private var pendingIncomingMessages = 0
    @State private var unreadDividerMessageId: String? = nil
    @State private var unreadDividerInitialized = false
    @State private var hasCompletedInitialScroll = false
    @State private var initialScrollTask: Task<Void, Never>? = nil
    @State private var frozenInitialScrollTarget: ChatScrollTarget? = nil
    @State private var isSearchVisible = false
    @State private var searchQuery: String = ""
    @State private var searchMatchIds: [String] = []
    @State private var currentSearchMatchIndex: Int = 0
    @State private var pendingSearchTargetId: String? = nil
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
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

    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: MomentsChatViewModel(conversation: conversation))
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
        chatViewWithSettingsAndStories
        .fullScreenCover(isPresented: $showingUserProfile) {
            UserProfileView(userId: viewModel.conversation.otherParticipantId)
                .userProfileZoomDestination(
                    userId: viewModel.conversation.otherParticipantId,
                    namespace: profileZoomNamespace
                )
        }
        // ✅ NUEVO: Pantalla de selección de medios para respuestas a clusters
        .sheet(item: Binding(
            get: { clusterForReply.map { ClusterWrapper(messages: $0) } },
            set: { clusterForReply = $0?.messages }
        )) { wrapper in
            GlassmorphicMediaSelectionSheet(
                messages: wrapper.messages,
                onSelect: { selectedMessage in
                    self.replyingTo = selectedMessage
                    self.clusterForReply = nil
                },
                onCancel: {
                    self.clusterForReply = nil
                }
            )
            .presentationDetents([.medium, .large])
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        .onAppear {
            onAppearActions()
            initializeUnreadDividerIfNeeded()
        }
        .onDisappear {
            onDisappearActions()
        }
        .onChange(of: viewModel.messages.map(\.id)) { _, _ in
            initializeUnreadDividerIfNeeded()
            if isSearchVisible && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateSearchMatches()
            }
        }
        .onChange(of: searchQuery) { _, _ in
            updateSearchMatches()
        }
        .onChange(of: messageMenuSelection) { _, newValue in
            if let message = newValue?.message {
                highlightedMessageId = message.id
            } else {
                withAnimation { reactionMessageOverlay = nil }
                highlightedMessageId = nil
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: activeAttachmentSheet)
        .overlay {
            if activeAttachmentSheet == .menu {
                ChatAttachmentMenuPopover(
                    isPresented: $activeAttachmentSheet,
                    anchorFrame: plusButtonAnchorFrame,
                    onOpenCamera: {
                        showEnhancedCamera = true
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

            ChatGiphyPickerSheetOverlay(
                activeSheet: $activeAttachmentSheet,
                accentColor: adaptiveColors.userAccentColor,
                onSelect: { asset in
                    viewModel.sendGif(from: asset)
                }
            )

            ChatStickerPickerSheetOverlay(
                activeSheet: $activeAttachmentSheet,
                accentColor: adaptiveColors.userAccentColor,
                onSelect: { asset in
                    viewModel.sendSticker(from: asset)
                }
            )

            ChatLocationSheetOverlay(
                activeSheet: $activeAttachmentSheet,
                accentColor: adaptiveColors.userAccentColor,
                onSendStatic: { coordinate, name, address in
                    viewModel.sendStaticLocation(coordinate: coordinate, name: name, address: address)
                },
                onStartLive: { duration in
                    viewModel.startLiveLocation(duration: duration)
                }
            )

            liveLocationBanner
        }
        .overlay(
            Group {
                if let selectedChatMedia {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    self.selectedChatMedia = nil
                                }
                            }

                        FullScreenMediaView(
                            media: selectedChatMedia,
                            mediaItems: selectedChatMediaItems,
                            currentUserId: viewModel.currentUserId,
                            otherParticipantName: otherParticipantDisplayName,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    self.selectedChatMedia = nil
                                    self.selectedChatMediaItems = []
                                }
                            },
                            onSendReply: { media, text, completion in
                                sendReplyToSharedMedia(media, text: text, completion: completion)
                            }
                        )
                    }
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        )
    }
    
    // MARK: - Banner de ubicación en vivo activa

    @ViewBuilder
    private var liveLocationBanner: some View {
        if let session = liveLocationService.activeSession,
           session.conversationId == viewModel.conversation.id {
            VStack {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundColor(.green)
                    Text("chat.location.liveSharing")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        viewModel.stopLiveLocation(messageId: session.messageId)
                    } label: {
                        Text("chat.location.stopSharing")
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(46)
        }
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
        } else if otherUserStatus != .invisible {
            HStack(spacing: 4) {
                Image(systemName: otherUserStatus.icon)
                    .foregroundStyle(otherUserStatus.color)
                    .font(.system(size: 7))

                Text(otherUserStatus.displayName)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(adaptiveColors.secondary)
                    .lineLimit(1)

                if otherUserStatus != .online, let lastSeen = otherUserLastSeen {
                    Text("• \(onlineStatusService.formatLastSeen(lastSeen))")
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
                    .font(.custom("Poppins-Regular", size: 14))
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
                    .font(.custom("Poppins-Medium", size: 11))
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
    
    // ✅ REFACTORIZADO: Sección de lista de mensajes
    private var messagesListSection: some View {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // ✅ TRIGGER DE PAGINACIÓN
                    if viewModel.canLoadMore {
                        Color.clear
                            .frame(height: 20)
                            .onAppear {
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
                        case .message(let item):
                            if shouldShowUnreadDivider(before: item) {
                                GlassmorphicUnreadDivider()
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 6)
                            }
                            renderMessageItem(item, in: viewModel.messages, proxy: proxy)
                        }
                    }
                    
                    if !viewModel.typingUsers.isEmpty {
                        GlassmorphicTypingIndicator()
                            .padding(.horizontal)
                            .id("typing")
                    }
                    
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom-anchor")
                        .onAppear {
                            guard hasCompletedInitialScroll else { return }
                            isPinnedToBottom = true
                            pendingIncomingMessages = 0
                        }
                        .onDisappear {
                            guard hasCompletedInitialScroll else { return }
                            isPinnedToBottom = false
                        }
                }
                .padding(.vertical, 10)
                .onPreferenceChange(ChatMessageRowFrameKey.self) { frames in
                    messageRowFrames.merge(frames, uniquingKeysWith: { $1 })
                }
            }
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: "chatScroll")
            .chatScrollEdgeEffect()
            .onAppear {
                guard !viewModel.messages.isEmpty else { return }
                scheduleInitialScroll(proxy: proxy)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        if messageMenuSelection != nil {
                            messageMenuSelection = nil
                        }
                        guard hasCompletedInitialScroll else { return }
                        let vertical = value.translation.height
                        let horizontal = abs(value.translation.width)
                        guard abs(vertical) > horizontal * 1.25, vertical > 28 else { return }
                        isPinnedToBottom = false
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                if !isPinnedToBottom || pendingIncomingMessages > 0 {
                    Button {
                        scrollToBottom(proxy: proxy, animated: true)
                        pendingIncomingMessages = 0
                        isPinnedToBottom = true
                        unreadDividerMessageId = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            if pendingIncomingMessages > 0 {
                                Text(pendingIncomingMessages > 99 ? "99+" : "\(pendingIncomingMessages)")
                                    .font(.custom("Poppins-SemiBold", size: 12))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onChange(of: viewModel.messages.isEmpty) { _, isEmpty in
                guard !isEmpty else { return }
                scheduleInitialScroll(proxy: proxy)
            }
            .onChange(of: viewModel.messages.count) { _, newCount in
                guard newCount > 0 else { return }
                scheduleInitialScroll(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.id) { _, lastMessageId in
                guard let lastMessageId, hasCompletedInitialScroll else { return }
                let isLastMessageMine = viewModel.messages.last?.senderId == viewModel.currentUserId
                
                if isLastMessageMine {
                    scrollToBottom(proxy: proxy, animated: true)
                    pendingIncomingMessages = 0
                    isPinnedToBottom = true
                    unreadDividerMessageId = nil
                } else if !viewModel.isLoadingMore {
                    if isPinnedToBottom {
                        scrollToBottom(proxy: proxy, animated: true)
                    } else {
                        if unreadDividerMessageId == nil {
                            unreadDividerMessageId = lastMessageId
                        }
                        pendingIncomingMessages += 1
                    }
                }
            }
            .onChange(of: chatMediaLayoutSignature) { _, _ in
                guard hasCompletedInitialScroll, isPinnedToBottom, !viewModel.isLoadingMore else { return }
                scrollToBottom(proxy: proxy, animated: false)
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
            .onChange(of: isTextFieldFocused) { _, focused in
                guard focused, hasCompletedInitialScroll else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
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
                        .font(.custom("Poppins-Medium", size: 14))
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

            GeometryReader { proxy in
                ChatMessageContextMenuOverlay(
                    selection: $messageMenuSelection,
                    containerSize: proxy.size,
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
                        replyingTo = message
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
                    },
                    onMoreReactions: { message in
                        reactionPickerMessage = message
                        showingReactionEmojiPicker = true
                    }
                )
            }
            .ignoresSafeArea()
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
        VStack(spacing: 0) {
            messagesListSection
            replyBarSection
            inputBarSection
        }
    }

    private func sharedMedia(from message: EnhancedMessage) -> SharedMedia? {
        guard let mediaUrl = message.mediaUrl else { return nil }
        guard message.type == .image || message.type == .video else { return nil }

        return SharedMedia(
            id: message.id,
            type: message.type == .image ? .image : .video,
            thumbnailUrl: message.thumbnailUrl ?? mediaUrl,
            originalUrl: mediaUrl,
            senderId: message.senderId,
            timestamp: message.timestamp
        )
    }

    private func sharedMediaItemsForOverlay(selecting message: EnhancedMessage) -> [SharedMedia] {
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
                    isTyping: $viewModel.isTyping,
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
                    .font(.custom("Poppins-Medium", size: 14))
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
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.58))
                    .lineLimit(2)

                Spacer(minLength: 6)

                Button(action: onUnblock) {
                    Text("chat.blockedByMe.unblock")
                        .font(.custom("Poppins-SemiBold", size: 13))
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

        Group {
            switch item {
            case .single(let message):
                let liveMessage = viewModel.messages.first(where: { $0.id == message.id }) ?? message
                GlassmorphicMessageRow(
                message: liveMessage,
                isCurrentUser: liveMessage.senderId == viewModel.currentUserId,
                showAvatar: shouldShowAvatar(for: liveMessage, in: messages),
                otherUserId: viewModel.conversation.otherParticipantId,
                isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                otherParticipantName: otherParticipantDisplayName,
                repliedMessage: liveMessage.replyTo != nil ? viewModel.messages.first(where: { $0.id == liveMessage.replyTo }) : nil,
                onReply: { replyingTo = liveMessage },
                onReaction: { emoji in
                    viewModel.addReaction(to: liveMessage, emoji: emoji)
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
                progress: viewModel.uploadProgress[liveMessage.id],
                showSeenLabel: shouldShowSeenLabel(for: liveMessage.id, status: liveMessage.status)
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlightedMessageId == liveMessage.id && messageMenuSelection == nil ? Color.white.opacity(0.15) : Color.clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .chatMessageLongPress {
                presentMessageOptions(liveMessage, rowId: rowId, cluster: nil)
            }

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
                onOpenMedia: { message in
                    viewModel.prepareMediaForViewing(message) { resolved in
                        selectedChatMediaItems = sharedMediaItemsForOverlay(selecting: resolved)
                        selectedChatMedia = sharedMedia(from: resolved)
                    }
                },
                onLongPress: { message in
                    presentMessageOptions(message, rowId: rowId, cluster: liveCluster.count > 1 ? liveCluster : nil)
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
                uploadProgress: viewModel.uploadProgress,
                showSeenLabel: {
                    let status = ClusterMessageStatusAggregator.aggregate(liveCluster)
                    guard let anchorId = liveCluster.last?.id else { return false }
                    return shouldShowSeenLabel(for: anchorId, status: status)
                }()
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(liveCluster.contains(where: { $0.id == highlightedMessageId }) && messageMenuSelection == nil ? Color.white.opacity(0.15) : Color.clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .scaleEffect(liveCluster.contains(where: { $0.id == highlightedMessageId }) && messageMenuSelection == nil ? 1.03 : 1.0)
            .chatMessageLongPress {
                if let anchor = liveCluster.last {
                    presentMessageOptions(anchor, rowId: rowId, cluster: liveCluster.count > 1 ? liveCluster : nil)
                }
            }

            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ChatMessageRowFrameKey.self,
                    value: [rowId: geo.frame(in: .global)]
                )
            }
        }
        .modifier(ConversationRowMenuHighlight(
            isSelected: isMenuSelected,
            colorScheme: colorScheme
        ))
        .scaleEffect(isMenuSelected ? 0.92 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isMenuSelected)
        .zIndex(isMenuSelected ? 2 : 0)
        .id(item.id)
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

    private func presentMessageOptions(_ message: EnhancedMessage, rowId: String, cluster: [EnhancedMessage]?) {
        guard let frame = messageRowFrames[rowId], frame.width > 0, frame.height > 0 else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            messageMenuSelection = ChatMessageMenuSelection(
                rowId: rowId,
                message: message,
                rowFrame: frame,
                clusterMessages: cluster
            )
            highlightedMessageId = message.id
        }
    }

    private func onAppearActions() {
        initialScrollTask?.cancel()
        initialScrollTask = nil
        frozenInitialScrollTarget = nil
        hasCompletedInitialScroll = false
        isPinnedToBottom = true
        pendingIncomingMessages = 0
        unreadDividerInitialized = false
        unreadDividerMessageId = nil
        viewModel.isChatVisible = true
        viewModel.startListening()
        Task {
            if let conversationId = viewModel.conversation.id {
                await EncryptionService.shared.preloadConversationKeys(for: [conversationId])
            }
        }
        setupOnlineStatusObserver()
        refreshOtherParticipantUsername()
        refreshOtherParticipantAvailability()
        checkUserStories()
    }

    // ✅ REFACTORIZADO: Acciones al desaparecer
    private func onDisappearActions() {
        initialScrollTask?.cancel()
        initialScrollTask = nil
        viewModel.isChatVisible = false  // ✅ Marcar chat como no visible
        
        viewModel.stopListening()
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
        
        // ✅ AGREGAR ESTA LÍNEA DE DEBUG:
        
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
    private func resolveInitialScrollTarget() -> ChatScrollTarget? {
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

    private func scrollToTarget(_ target: ChatScrollTarget, proxy: ScrollViewProxy, animated: Bool) {
        let performScroll = {
            switch target {
            case .bottom(let messageId):
                proxy.scrollTo(messageId, anchor: .bottom)
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
            case .firstUnread(let messageId):
                proxy.scrollTo(messageId, anchor: .top)
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
        guard let lastId = viewModel.messages.last?.id else {
            if animated {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
            }
            return
        }
        scrollToTarget(.bottom(messageId: lastId), proxy: proxy, animated: animated)
    }

    private func scheduleInitialScroll(proxy: ScrollViewProxy) {
        guard !hasCompletedInitialScroll else { return }
        guard !viewModel.messages.isEmpty else { return }
        guard initialScrollTask == nil else { return }

        initializeUnreadDividerIfNeeded()

        if frozenInitialScrollTarget == nil {
            frozenInitialScrollTarget = resolveInitialScrollTarget()
        }
        guard let target = frozenInitialScrollTarget else { return }

        if target.isFirstUnread {
            isPinnedToBottom = false
        }

        initialScrollTask = Task { @MainActor in
            defer { initialScrollTask = nil }
            let delays: [UInt64] = [0, 80_000_000, 200_000_000, 450_000_000, 700_000_000]
            for delay in delays {
                if Task.isCancelled { return }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !hasCompletedInitialScroll else { return }
                guard !viewModel.messages.isEmpty else { continue }
                scrollToTarget(target, proxy: proxy, animated: false)
            }
            guard !Task.isCancelled else { return }
            hasCompletedInitialScroll = true
            isPinnedToBottom = !target.isFirstUnread
            viewModel.prefetchUnresolvedMediaIfNeeded()
        }
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            proxy.scrollTo(messageId, anchor: .center)
        }
        
        // Efecto visual temporal
        highlightedMessageId = messageId
        
        // Haptic feedback
        HapticManager.shared.mediumImpact()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if highlightedMessageId == messageId {
                    highlightedMessageId = nil
                }
            }
        }
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
        for group in groupedMessages {
            rows.append(.header(group.0))
            for item in ClusterMessageGrouper.group(group.1) {
                rows.append(.message(item))
            }
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
