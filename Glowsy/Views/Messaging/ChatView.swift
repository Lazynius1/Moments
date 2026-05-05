import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import PhotosUI
import AVKit
import AVFoundation
import CoreLocation
import MapKit

// MARK: - Glassmorphic Chat View
// Actualizar GlassmorphicChatView para incluir navegación
struct GlassmorphicChatView: View {
    @StateObject private var viewModel: MomentsChatViewModel
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var messageText: String = ""
    @State private var showMediaPicker: Bool = false
    @State private var showEnhancedCamera = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var replyingTo: EnhancedMessage?
    @State private var clusterForReply: [EnhancedMessage]? = nil // ✅ New: Selection grid for clusters
    @State private var editingMessage: EnhancedMessage?
    @State private var showingMessageOptions: EnhancedMessage?
    @State private var scrollToBottom = false
    @State private var showCameraSheet = false
    @State private var isRecordingVoice = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var showingConversationSettings = false
    @State private var highlightedMessageId: String? = nil // ✅ New: Jump to message highlight
    @State private var isDetachedFromBottom = false
    @State private var pendingIncomingMessages = 0
    @State private var unreadDividerMessageId: String? = nil
    @State private var unreadDividerInitialized = false
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
    @State private var navigateToProfile = false
    
    // ✅ NUEVO: Estados para navegación al momento
    @State private var showingMomentDetail = false
    @State private var selectedMoment: Moment?
    @State private var showingMomentError = false
    
    // ✅ NUEVO: Estado para mostrar historias
    @State private var showingStories = false
    
    // ✅ NUEVO: Estado para el userId de las historias
    @State private var storiesUserId: String = ""
    
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
    
    var body: some View {
        GeometryReader { geometry in
            chatRootContent(safeAreaTop: geometry.safeAreaInsets.top)
        }
        .navigationBarHidden(true)
        .photosPicker(isPresented: $showMediaPicker, selection: $selectedItems, maxSelectionCount: 10)
        .sheet(isPresented: $showEnhancedCamera) {
            EnhancedCameraPickerView { data, mediaType, isEphemeral in
                handleCameraCapture(data: data, mediaType: mediaType, isEphemeral: isEphemeral)
            }
        }
        .onChange(of: selectedItems) { items in
            let mediaBatchId = items.count > 1 ? UUID().uuidString : nil
            for item in items {
                viewModel.handlePhotoPickerItem(item, mediaBatchId: mediaBatchId)
            }
            selectedItems = []
        }
        .fullScreenCover(isPresented: $showingConversationSettings, onDismiss: {
            viewModel.refreshTypingIndicatorPreference()
        }) {
            ConversationSettingsView(conversation: viewModel.conversation)
        }
        // ✅ NUEVO: Sheet para mostrar historias del usuario
        .sheet(isPresented: $showingStories) {
            StoriesView(startWithUserId: .constant(storiesUserId))
        }
        // ✅ NUEVO: Sheet para navegación al detalle del momento
        .sheet(isPresented: $showingMomentDetail) {
            if let moment = selectedMoment {
                MomentDetailView(moment: moment)
            }
        }
        // ✅ NUEVO: Alert para error al cargar momento
        .alert("common.error", isPresented: $showingMomentError) {
            Button("common.ok") { }
        } message: {
            Text("chat.moment.loadError")
        }
// ✅ NUEVO: Navegación al perfil del usuario
        .background(
            NavigationLink(
                destination: viewModel.conversation.otherParticipantId != nil ?
                    UserProfileView(userId: viewModel.conversation.otherParticipantId) : nil,
                isActive: $showingUserProfile
            ) { EmptyView() }
        )
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
        .onAppear {
            onAppearActions()
            initializeUnreadDividerIfNeeded()
        }
        .onDisappear {
            onDisappearActions()
        }
        .onChange(of: viewModel.messages.map(\.id)) { _ in
            initializeUnreadDividerIfNeeded()
            if isSearchVisible && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateSearchMatches()
            }
        }
        .onChange(of: searchQuery) { _ in
            updateSearchMatches()
        }
        .onChange(of: showingMessageOptions) { newValue in
            if newValue == nil {
                withAnimation { reactionMessageOverlay = nil }
            }
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
        // ✅ REACCIONES Y OPCIONES: Overlay global premium
        .overlay(
            Group {
                if let message = showingMessageOptions {
                    GlassmorphicMessageOptionsMenu(
                        message: message,
                        isCurrentUser: message.senderId == viewModel.currentUserId,
                        onDeleteForEveryone: {
                            viewModel.deleteMessageForEveryone(message)
                            showingMessageOptions = nil
                        },
                        onDeleteForMe: {
                            viewModel.deleteMessageForMe(message)
                            showingMessageOptions = nil
                        },
                        onEdit: {
                            editingMessage = message
                            messageText = message.content ?? ""
                            showingMessageOptions = nil
                        },
                        onReply: {
                            replyingTo = message
                            showingMessageOptions = nil
                        },
                        onCopy: {
                            UIPasteboard.general.string = message.content
                            showingMessageOptions = nil
                        },
                        onReaction: { emoji in
                            viewModel.addReaction(to: message, emoji: emoji)
                            showingMessageOptions = nil
                        },
                        onDismiss: {
                            showingMessageOptions = nil
                        }
                    )
                }
            }
        )
    }
    
    // ✅ ACTUALIZADO: Navigation bar con navegación al perfil
    private var glassmorphicNavigationBar: some View {
        HStack(spacing: 16) {
            // Back button
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 40, height: 40)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            
            // ✅ ACTUALIZADO: User info con navegación al perfil
            HStack(spacing: 10) {
                // ✅ SEPARADO: Botón solo para la foto (historias o perfil)
                Button(action: {
                    if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
                        showingUserProfile = true
                    } else if hasStory && !isOtherParticipantBlockedByCurrentUser {
                        // ✅ SI TIENE HISTORIAS: Establecer userId y abrir StoriesView
                        storiesUserId = viewModel.conversation.otherParticipantId
                        showingStories = true
                    } else {
                        // ✅ SI NO TIENE HISTORIAS: Ir al perfil
                        showingUserProfile = true
                    }
                }) {
                    if isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser {
                        ProfileUnavailableAvatar(size: 40)
                    } else {
                        // ✅ ACTUALIZADO: Usar el componente asíncrono centralizado para tiempo real
                        AsyncProfileImageView(userId: viewModel.conversation.otherParticipantId)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
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
                                    lineWidth: 2.5
                                )
                            )
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // ✅ SEPARADO: Botón solo para el nombre (siempre al perfil)
                Button(action: {
                    showingUserProfile = true
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(otherParticipantDisplayName)
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .strikethrough(isOtherParticipantUnavailable && !isOtherParticipantBlockedByCurrentUser, color: adaptiveColors.secondary)
                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(isOtherParticipantUnavailable ? 0.72 : 1.0))
                            
                            // ✅ INSIGNIA DE VERIFICADO
                            if !isOtherParticipantUnavailable {
                                VerifiedBadgeView(userId: viewModel.conversation.otherParticipantId, size: 14)
                            }
                        }
                        
                        if isOtherParticipantBlockedByCurrentUser {
                            Text("chat.blockedByMe.subtitle")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.secondary)
                        } else if isOtherParticipantUnavailable {
                            Text("chat.profileUnavailable")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.secondary)
                        } else if !viewModel.typingUsers.isEmpty {
                            Text("chat.typing")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(adaptiveColors.secondary)
                        } else if otherUserStatus != .invisible {
                            HStack(spacing: 4) {
                                Image(systemName: otherUserStatus.icon)
                                    .foregroundColor(otherUserStatus.color)
                                    .font(.system(size: 8))
                                
                                Text(otherUserStatus.displayName)
                                    .font(.custom("Poppins-Regular", size: 12))
                                    .foregroundColor(adaptiveColors.secondary)
                                
                                if otherUserStatus != .online, let lastSeen = otherUserLastSeen {
                                    Text("• \(onlineStatusService.formatLastSeen(lastSeen))")
                                        .font(.custom("Poppins-Regular", size: 10))
                                        .foregroundColor(adaptiveColors.secondary.opacity(0.7))
                                }
                            }
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlass(in: Capsule(), interactive: true)
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSearchVisible.toggle()
                }
                if isSearchVisible {
                    searchQuery = ""
                    searchMatchIds = []
                    currentSearchMatchIndex = 0
                    pendingSearchTargetId = nil
                }
            }) {
                Image(systemName: isSearchVisible ? "xmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 40, height: 40)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            
            // Settings button
            Button(action: {
                showingConversationSettings = true
            }) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 40, height: 40)
                    .liquidGlass(in: Circle(), interactive: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            checkUserStories()
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
            .liquidGlass(in: Capsule(), interactive: true)
            
            HStack(spacing: 6) {
                Text(searchCounterText)
                    .font(.custom("Poppins-Medium", size: 11))
                    .foregroundColor(adaptiveColors.secondary)
                    .frame(minWidth: 38)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .liquidGlass(in: Capsule(), interactive: true)
                
                Button {
                    moveSearchSelection(by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(searchMatchIds.isEmpty ? adaptiveColors.secondary.opacity(0.35) : adaptiveColors.primary)
                        .frame(width: 30, height: 30)
                        .liquidGlass(in: Circle(), interactive: true)
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
                        .liquidGlass(in: Circle(), interactive: true)
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
                    
                    ForEach(viewModel.groupedMessages, id: \.0) { date, messages in
                        GlassmorphicDateHeader(date: date)
                            .padding(.vertical, 10)
                        
                        let clusteredItems = self.clusterMessages(messages)
                        ForEach(clusteredItems) { item in
                            if shouldShowUnreadDivider(before: item) {
                                GlassmorphicUnreadDivider()
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 6)
                            }
                            renderMessageItem(item, in: messages, proxy: proxy)
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
                            if isDetachedFromBottom || pendingIncomingMessages > 0 {
                                isDetachedFromBottom = false
                                pendingIncomingMessages = 0
                            }
                        }
                }
                .padding(.vertical, 10)
                .padding(.top, headerOverlayHeight)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if value.translation.height > 10 {
                            isDetachedFromBottom = true
                        }
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                if isDetachedFromBottom || pendingIncomingMessages > 0 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                        }
                        pendingIncomingMessages = 0
                        isDetachedFromBottom = false
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
            .onAppear {
                guard !viewModel.messages.isEmpty else { return }
                // Si los mensajes ya están cargados (caché), scroll inmediato
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.isEmpty) { isEmpty in
                // Detecta cuando los mensajes cargan de Firestore por primera vez (vacío → poblado)
                guard !isEmpty else { return }
                proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.last?.id) { lastMessageId in
                guard let lastMessageId else { return }
                let isLastMessageMine = viewModel.messages.last?.senderId == viewModel.currentUserId
                
                if isLastMessageMine {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                    }
                    pendingIncomingMessages = 0
                    isDetachedFromBottom = false
                    unreadDividerMessageId = nil
                } else {
                    if !viewModel.isLoadingMore && !isDetachedFromBottom {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                        }
                    } else if !viewModel.isLoadingMore {
                        if unreadDividerMessageId == nil {
                            unreadDividerMessageId = lastMessageId
                        }
                        pendingIncomingMessages += 1
                    }
                }
            }
            .onChange(of: pendingSearchTargetId) { targetId in
                guard let targetId else { return }
                jumpToMessage(targetId, proxy: proxy)
                pendingSearchTargetId = nil
            }
            .onChange(of: isTextFieldFocused) { focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
                        }
                    }
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
            
            if let editingMessage = editingMessage {
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

    private var headerOverlayHeight: CGFloat {
        isSearchVisible ? 132 : 76
    }

    @ViewBuilder
    private func chatRootContent(safeAreaTop: CGFloat) -> some View {
        let fadeBase = Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6")

        ZStack(alignment: .top) {
            ChatGlassmorphicBackground(adaptiveColors: adaptiveColors)
            mainChatStack
            topChromeSection
            topFadeOverlay(safeAreaTop: safeAreaTop, fadeBase: fadeBase)
        }
    }

    private var mainChatStack: some View {
        VStack(spacing: 0) {
            messagesListSection
            replyBarSection
            inputBarSection
        }
    }

    private var topChromeSection: some View {
        VStack(spacing: 0) {
            glassmorphicNavigationBar

            if isSearchVisible {
                chatSearchBarSection
            }
        }
    }

    @ViewBuilder
    private func topFadeOverlay(safeAreaTop: CGFloat, fadeBase: Color) -> some View {
        VStack {
            LinearGradient(
                stops: [
                    .init(color: fadeBase.opacity(0.98), location: 0.0),
                    .init(color: fadeBase.opacity(0.88), location: 0.28),
                    .init(color: fadeBase.opacity(0.4), location: 0.64),
                    .init(color: fadeBase.opacity(0.08), location: 0.88),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaTop + 42)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
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
                    onCamera: {
                        showEnhancedCamera = true
                    },
                    onMedia: {
                        showMediaPicker = true
                    },
                    onStartVoiceRecording: {
                        startVoiceRecording()
                    },
                    onStopVoiceRecording: { shouldSend in
                        stopVoiceRecording(shouldSend: shouldSend)
                    }
                )
                .focused($isTextFieldFocused)
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
            .liquidGlass(in: Capsule(), interactive: false)
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
                        .liquidGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .liquidGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
    
    // ✅ REFACTORIZADO: Acciones al aparecer
    
    // ✅ REFACTORIZADO: Renderizar cada item del chat por separado para evitar errores del compilador
    @ViewBuilder
    private func renderMessageItem(_ item: MessageItem, in messages: [EnhancedMessage], proxy: ScrollViewProxy) -> some View {
        switch item {
        case .single(let message):
            GlassmorphicMessageRow(
                message: message,
                isCurrentUser: message.senderId == viewModel.currentUserId,
                showAvatar: shouldShowAvatar(for: message, in: messages),
                otherUserId: viewModel.conversation.otherParticipantId,
                isOtherParticipantUnavailable: isOtherParticipantUnavailable,
                otherParticipantName: otherParticipantDisplayName,
                repliedMessage: message.replyTo != nil ? viewModel.messages.first(where: { $0.id == message.replyTo }) : nil,
                onReply: { replyingTo = message },
                onReaction: { emoji in
                    viewModel.addReaction(to: message, emoji: emoji)
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
                onOpenMedia: { message in
                    selectedChatMediaItems = sharedMediaItemsForOverlay(selecting: message)
                    selectedChatMedia = sharedMedia(from: message)
                },
                progress: viewModel.uploadProgress[message.id]
            )
            .id(message.id)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlightedMessageId == message.id ? Color.white.opacity(0.15) : Color.clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .onLongPressGesture(minimumDuration: 0.3) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showingMessageOptions = message
                }
            }
            
        case .mediaCluster(let clusterMessages):
            GlassmorphicClusterRow(
                messages: clusterMessages,
                isCurrentUser: clusterMessages.first?.senderId == viewModel.currentUserId,
                showAvatar: shouldShowAvatar(for: clusterMessages.first!, in: messages),
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
                    selectedChatMediaItems = sharedMediaItemsForOverlay(selecting: message)
                    selectedChatMedia = sharedMedia(from: message)
                },
                onLongPress: { message in
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showingMessageOptions = message
                    }
                },
                onReply: { messages in
                    self.clusterForReply = messages
                },
                onReplyTap: { id in
                    jumpToMessage(id, proxy: proxy)
                },
                uploadProgress: viewModel.uploadProgress
            )
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(clusterMessages.contains(where: { $0.id == highlightedMessageId }) ? Color.white.opacity(0.15) : Color.clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .scaleEffect(clusterMessages.contains(where: { $0.id == highlightedMessageId }) ? 1.03 : 1.0)
        }
    }

    private func onAppearActions() {
        if let conversationId = viewModel.conversation.id {
            Task {
                await EncryptionService.shared.preloadConversationKeys(for: [conversationId])
            }
        }
        viewModel.isChatVisible = true  // ✅ Marcar chat como visible
        viewModel.startListening()
        setupOnlineStatusObserver()
        refreshOtherParticipantUsername()
        refreshOtherParticipantAvailability()
    }
    
    // ✅ REFACTORIZADO: Acciones al desaparecer
    private func onDisappearActions() {
        viewModel.isChatVisible = false  // ✅ Marcar chat como no visible
        
        viewModel.stopListening()
        statusListener?.remove()
    }
    
    // ✅ ACTUALIZADO: Función para verificar historias del usuario (con filtrado de privacidad como en reels)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId ?? ""
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

        guard let conversationId = viewModel.conversation.id else {
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
        isRecordingVoice = true
        recordingTime = 0
        
        // ✅ Track voice recording start
        
        // Iniciar timer para mostrar duración
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
            
            // Límite máximo de 60 segundos
            if recordingTime >= 60.0 {
                stopVoiceRecording(shouldSend: true)
            }
        }
        
        // Aquí integrarías la lógica real de grabación de audio
        AudioRecordingManager.shared.startRecording()
    }
    
    private func stopVoiceRecording(shouldSend: Bool) {
        isRecordingVoice = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // ✅ Track voice recording completion
        
        // Aquí obtendrías los datos del audio grabado
        AudioRecordingManager.shared.stopRecording { audioData in
            if shouldSend, let audioData = audioData {
                viewModel.sendAudioMessage(audioData, duration: recordingTime)
            }
        }
        
        recordingTime = 0
    }
}

// ✅ NUEVO: Función para manejar navegación al momento desde el chat
extension GlassmorphicChatView {
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
        var result: [MessageItem] = []
        var currentCluster: [EnhancedMessage] = []
        
        for message in input {
            // Only cluster images/videos
            let isClusterable = message.type == .image || message.type == .video
            
            if isClusterable {
                if let last = currentCluster.last {
                    let sameSender = message.senderId == last.senderId
                    let sameBatch = {
                        guard let batchId = message.mediaBatchId, !batchId.isEmpty else { return false }
                        return last.mediaBatchId == batchId
                    }()

                    if sameSender && sameBatch {
                        currentCluster.append(message)
                    } else {
                        if !currentCluster.isEmpty {
                            result.append(currentCluster.count > 1 ? .mediaCluster(currentCluster) : .single(currentCluster[0]))
                            currentCluster = []
                        }
                        currentCluster.append(message)
                    }
                } else {
                    currentCluster.append(message)
                }
            } else {
                if !currentCluster.isEmpty {
                    result.append(currentCluster.count > 1 ? .mediaCluster(currentCluster) : .single(currentCluster[0]))
                    currentCluster = []
                }
                result.append(.single(message))
            }
        }
        
        if !currentCluster.isEmpty {
            result.append(currentCluster.count > 1 ? .mediaCluster(currentCluster) : .single(currentCluster[0]))
        }
        
        return result
    }
    
    // ✅ JUMP TO MESSAGE: Scrollear hacia un mensaje específico con efecto visual
    private func jumpToMessage(_ messageId: String, proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            proxy.scrollTo(messageId, anchor: .center)
        }
        
        // Efecto visual temporal
        highlightedMessageId = messageId
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
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
           let momentId = sharedMomentData["momentId"] as? String {
            
            
            // ✅ CORREGIDO: Obtener el authorId del momento compartido o usar el senderId como fallback
            let authorId = sharedMomentData["momentAuthorId"] as? String ?? message.senderId
            
            // ✅ CORREGIDO: Usar la estructura correcta de Firestore (users/{userId}/moments/{momentId})
            let db = Firestore.firestore()
            db.collection("users").document(authorId).collection("moments").document(momentId).getDocument { document, error in
                DispatchQueue.main.async {
                    if let document = document, document.exists {
                        do {
                            var moment = try document.data(as: Moment.self)
                            guard moment.isArchived != true else {
                                self.showingMomentError = true
                                return
                            }
                            moment.id = document.documentID
                            
                            self.selectedMoment = moment
                            self.showingMomentDetail = true
                            
                        } catch {
                            self.showingMomentError = true
                        }
                    } else {
                        self.showingMomentError = true
                    }
                }
            }
        }
    }
}

// MARK: - Chat Background
struct ChatGlassmorphicBackground: View {
    let adaptiveColors: AdaptiveColors
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                adaptiveColors.chatBackground[0]
                    .ignoresSafeArea()
            } else {
                adaptiveColors.chatBackground[0]
                    .ignoresSafeArea()
            }
        }
    }
}

extension View {
    func glassmorphicChat() -> some View {
        modifier(GlassmorphicModifier())
    }

    func glassmorphicChatCircle() -> some View {
        modifier(GlassmorphicCircleModifier())
    }
}

struct GlassmorphicModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Material effect base
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.3 : 0.6)
                    
                    // Fondo base adaptativo encima del material
                    Rectangle()
                        .fill(
                            colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.white.opacity(0.7)
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        colorScheme == .dark ?
                        Color.white.opacity(0.2) :
                        Color.black.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
    }
}

struct GlassmorphicCircleModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.3 : 0.6)

                    Circle()
                        .fill(
                            colorScheme == .dark
                            ? Color.white.opacity(0.1)
                            : Color.white.opacity(0.7)
                        )
                }
            )
            .overlay(
                Circle()
                    .stroke(
                        colorScheme == .dark
                        ? Color.white.opacity(0.2)
                        : Color.black.opacity(0.1),
                        lineWidth: 0.5
                    )
            )
    }
}


// MARK: - Glassmorphic Message Row
struct GlassmorphicMessageRow: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let showAvatar: Bool
    let otherUserId: String?
    let isOtherParticipantUnavailable: Bool
    let otherParticipantName: String
    let repliedMessage: EnhancedMessage?
    let onReply: () -> Void
    let onReaction: (String) -> Void
    let onAvatarTap: () -> Void // ✅ NUEVO: Callback para tap en avatar
    let onReplyTap: ((String) -> Void)? // ✅ New: Jump to message
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)? // ✅ NUEVO: Callback para navegación al momento
    let onOpenMedia: (EnhancedMessage) -> Void
    let progress: Double? // ✅ New: Real-time progress
    
    @Environment(\.colorScheme) var colorScheme
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false

    var body: some View {
        ZStack(alignment: .leading) {
            // Background Reply Icon (appears when swiping)
            if dragOffset > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(adaptiveColors.userAccentColor)
                    .opacity(Double(min(dragOffset / 60, 1.0)))
                    .offset(x: min(dragOffset - 30, 0))
                    .padding(.leading, 12)
            }
            
            HStack(alignment: .bottom, spacing: 8) {
                if !isCurrentUser {
                    if showAvatar {
                        // ✅ ACTUALIZADO: Avatar con navegación al perfil
                        Button(action: onAvatarTap) {
                            if isOtherParticipantUnavailable {
                                ProfileUnavailableAvatar(size: 32)
                            } else {
                                GlassmorphicAvatar(userId: otherUserId ?? "")
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }
                
                if isCurrentUser { Spacer(minLength: 50) }
                
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if let originalMessage = repliedMessage {
                        GlassmorphicReplyPreview(
                            message: originalMessage,
                            isParentMessageFromCurrentUser: isCurrentUser,
                            otherParticipantName: otherParticipantName,
                            onTap: { onReplyTap?(originalMessage.id) } // ✅ New: Trigger jump
                        )
                        .padding(.bottom, -8) // Superponer ligeramente con la burbuja
                        .zIndex(1)
                    }
                    
                    GlassmorphicMessageBubble(
                        message: message,
                        repliedMessage: repliedMessage,
                        otherParticipantName: otherParticipantName,
                        isCurrentUser: isCurrentUser,
                        progress: progress, // ✅ Pass progress
                        onReplyTap: onReplyTap, // ✅ Pass jump callback
                        onMessageViewed: onMessageViewed,
                        onMomentNavigation: onMomentNavigation,
                        onOpenMedia: onOpenMedia
                    )
                    
                    if let reactions = message.reactions, !reactions.isEmpty {
                        GlassmorphicReactionsView(reactions: reactions, onTap: onReaction)
                    }
                    
                    MessageTimestamp(message: message, status: message.status, isCurrentUser: isCurrentUser)
                }
                
                if !isCurrentUser { Spacer(minLength: 50) }
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle()) // Asegurar que todo el área es gesture-able
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // ✅ SOLUCIÓN: Solo detectar si el movimiento es predominantemente horizontal
                        let horizontalMove = value.translation.width
                        let verticalMove = value.translation.height
                        
                        if horizontalMove > 0 && abs(horizontalMove) > abs(verticalMove) {
                            dragOffset = horizontalMove
                            
                            // Haptic Feedback
                            if dragOffset > 60 && !hasTriggeredHaptic {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                hasTriggeredHaptic = true
                            } else if dragOffset < 60 && hasTriggeredHaptic {
                                hasTriggeredHaptic = false
                            }
                        }
                    }
                    .onEnded { value in
                        if dragOffset > 70 {
                            onReply()
                        }
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                            hasTriggeredHaptic = false
                        }
                    }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - Componente para Mensajes Eliminados
struct DeletedMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: getDeletedIcon())
                .font(.system(size: 16))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5)) // ✅ CAMBIO AQUÍ
            
            Text(getDeletedText())
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6)) // ✅ CAMBIO AQUÍ
                .italic()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(adaptiveColors.messageBubbleBackground.opacity(0.5)) // ✅ CAMBIO AQUÍ
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                )
        )
    }
    
    private func getDeletedIcon() -> String {
        switch message.type {
        case .audio:
            return "mic.slash"
        case .image:
            return "photo"
        case .video:
            return "video.slash"
        case .text:
            return "text.quote"
        case .file:
            return "doc.slash"
        case .location:
            return "location.slash"
        default:
            return "trash"
        }
    }
    
    private func getDeletedText() -> String {
        switch message.type {
        case .audio:
            return NSLocalizedString("chat.deleted.audio", comment: "Deleted audio message")
        case .image:
            return NSLocalizedString("chat.deleted.image", comment: "Deleted image message")
        case .video:
            return NSLocalizedString("chat.deleted.video", comment: "Deleted video message")
        case .text:
            return NSLocalizedString("chat.deleted.text", comment: "Deleted text message")
        case .file:
            return NSLocalizedString("chat.deleted.file", comment: "Deleted file message")
        case .location:
            return NSLocalizedString("chat.deleted.location", comment: "Deleted location message")
        case .ephemeral:
            return NSLocalizedString("chat.deleted.ephemeral", comment: "Deleted ephemeral moment")
        default:
            return NSLocalizedString("chat.deleted.text", comment: "Deleted text message")
        }
    }
}

// MARK: - Updated Glassmorphic Message Bubble
struct GlassmorphicMessageBubble: View {
    let message: EnhancedMessage
    let repliedMessage: EnhancedMessage?
    let otherParticipantName: String
    let isCurrentUser: Bool
    let progress: Double? // ✅ New
    let onReplyTap: ((String) -> Void)? // ✅ New: Jump to message
    let onMessageViewed: ((String) -> Void)? // ✅ NUEVO callback
    let onMomentNavigation: ((EnhancedMessage) -> Void)? // ✅ NUEVO callback para navegación al momento
    let onOpenMedia: (EnhancedMessage) -> Void
    @State private var showEphemeralImage: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Group {
            // ✅ PRIMERO: Verificar si el mensaje está eliminado
            if message.isDeleted {
                DeletedMessageBubble(message: message, isCurrentUser: isCurrentUser)
            } else {
                // ✅ SEGUNDO: Verificar si es view-once
                if message.type == .viewOnceImage || message.type == .viewOnceVideo {
                    ViewOnceMessageBubble(
                        message: message,
                        isCurrentUser: isCurrentUser,
                        otherParticipantName: otherParticipantName,
                        progress: progress, // ✅ Pass progress
                        onViewed: {
                            markViewOnceAsViewed()
                        }
                    )
                    .onAppear {
                    }
                } else {
                // ✅ TERCERO: Mostrar contenido normal según el tipo
                switch message.type {
                case .text:
                    // Check if this is a story reply text message
                    if message.storyReplyData != nil {
                        StoryReplyMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser
                        )
                    } else if let content = message.content {
                        // Regular text message con colores adaptativos
                        HStack(alignment: .bottom, spacing: 12) {
                            if isCurrentUser {
                                // SENT Message: Content + Accent Line
                                Text(content)
                                    .font(.custom("Poppins-Regular", size: 15))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundColor(adaptiveColors.messageTextColor)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial.opacity(0.3)) // Barely there background
                                    )
                                
                                // User Accent Line (Dynamic)
                                Capsule()
                                    .fill(adaptiveColors.userAccentColor)
                                    .frame(width: 3, height: 20)
                                    .padding(.bottom, 6)
                                    
                            } else {
                                // RECEIVED Message: Accent Line + Content
                                Capsule()
                                    .fill(adaptiveColors.receivedAccentColor)
                                    .frame(width: 3, height: 20)
                                    .padding(.bottom, 6)
                                
                                Text(content)
                                    .font(.custom("Poppins-Regular", size: 15))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundColor(adaptiveColors.messageTextColor)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.ultraThinMaterial.opacity(0.3)) // Barely there background
                                    )
                            }
                        }
                    }
                    
                case .image:
                    GlassmorphicImageMessage(
                        imageUrl: message.mediaUrl,
                        isSending: message.status == .sending,
                        progress: progress,
                        onTap: {
                            onOpenMedia(message)
                        }
                    )
                    .frame(width: 208, height: 272)
                        .onAppear {
                        }
                    
                case .audio:
                    GlassmorphicAudioMessage(
                        audioUrl: message.mediaUrl,
                        duration: message.duration ?? 0,
                        isCurrentUser: isCurrentUser,
                        isSending: message.status == .sending,
                        progress: progress,
                        adaptiveColors: adaptiveColors
                    )
                    .onAppear {
                    }
                    
                case .video:
                    GlassmorphicVideoMessage(
                        videoUrl: message.mediaUrl,
                        thumbnailUrl: message.thumbnailUrl,
                        isSending: message.status == .sending,
                        progress: progress,
                        onTap: {
                            onOpenMedia(message)
                        }
                    )
                    .frame(width: 208, height: 272)
                        .onAppear {
                        }
                    
                case .ephemeral:
                    // Check if this is a story reply (always ephemeral for media)
                    if message.storyReplyData != nil {
                        StoryReplyMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser
                        )
                    } else {
                        // Regular ephemeral message (not story reply)
                        if let mediaUrl = message.mediaUrl, !message.isViewed, isEphemeralValid() {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(adaptiveColors.messageBubbleBackground) // ✅ CAMBIO AQUÍ
                                    .frame(maxWidth: 250, maxHeight: 300)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "camera.circle.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7)) // ✅ CAMBIO AQUÍ
                                            
                                            Text("chat.tapToView")
                                                .font(.custom("Poppins-Medium", size: 14))
                                                .foregroundColor(adaptiveColors.messageTextColor) // ✅ CAMBIO AQUÍ
                                            
                                            Text("chat.ephemeral.title")
                                                .font(.custom("Poppins-Regular", size: 12))
                                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7)) // ✅ CAMBIO AQUÍ
                                        }
                                    )
                                
                                if showEphemeralImage {
                                    GlassmorphicImageMessage(
                                        imageUrl: mediaUrl,
                                        isSending: false,
                                        progress: nil,
                                        onTap: {}
                                    )
                                }
                            }
                            .onTapGesture {
                                showEphemeralImage = true
                                markAsViewed()
                            }
                        } else if let content = message.content {
                            Text(content)
                                .font(.custom("Poppins-Regular", size: 15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6)) // ✅ CAMBIO AQUÍ
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(adaptiveColors.messageBubbleBackground) // ✅ CAMBIO AQUÍ
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                                        )
                                )
                        } else {
                            Text("chat.message.expired")
                                .font(.custom("Poppins-Regular", size: 15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6)) // ✅ CAMBIO AQUÍ
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(adaptiveColors.messageBubbleBackground) // ✅ CAMBIO AQUÍ
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                case .sharedMoment:
                    HStack(alignment: .bottom, spacing: 12) {
                        if isCurrentUser {
                            // SENT: Content + Accent
                            SharedMomentMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                onTap: {
                                    onMomentNavigation?(message)
                                }
                            )
                            
                            // User Accent Line
                            Capsule()
                                .fill(adaptiveColors.userAccentColor)
                                .frame(width: 3, height: 20)
                                .padding(.bottom, 6)
                        } else {
                            // RECEIVED: Accent + Content
                            Capsule()
                                .fill(adaptiveColors.receivedAccentColor)
                                .frame(width: 3, height: 20)
                                .padding(.bottom, 6)
                            
                            SharedMomentMessageBubble(
                                message: message,
                                isCurrentUser: isCurrentUser,
                                onTap: {
                                    onMomentNavigation?(message)
                                }
                            )
                        }
                    }
                    .onAppear {
                    }
                    
                default:
                    Text("chat.message.unsupported")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6)) // ✅ CAMBIO AQUÍ
                        .glassmorphicChat()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                }
            }
        }
        .onAppear {
            // ✅ Track message view
            if !isCurrentUser && !message.isDeleted {
            }
        }
    }
    
    private func isEphemeralValid() -> Bool {
        guard let expirationDate = message.expirationDate else { return true }
        return Date() < expirationDate
    }
    
    private func markAsViewed() {
        ChatService().markEphemeralAsViewed(conversationId: message.conversationId, messageId: message.id) { error in
            if let error = error {
            } else {
            }
        }
    }
    
    // ✅ FUNCIÓN ACTUALIZADA para marcar view-once como visto
    private func markViewOnceAsViewed() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // ✅ CAPTURAR VALORES LOCALMENTE
        let messageId = message.id
        let conversationId = message.conversationId
        let callback = onMessageViewed
        
        ChatService().markViewOnceAsViewed(
            conversationId: conversationId,
            messageId: messageId,
            viewerId: currentUserId
        ) { error in
            if let error = error {
            } else {
                
                // ✅ ACTUALIZAR EL ESTADO LOCAL INMEDIATAMENTE
                DispatchQueue.main.async {
                    callback?(messageId)
                }
            }
        }
    }
}

// MARK: - Glassmorphic Media Messages
struct GlassmorphicImageMessage: View {
    let imageUrl: String?
    let isSending: Bool // ✅ New
    let progress: Double? // ✅ New
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            if let url = imageUrl, let imageURL = URL(string: url) {
                KFImage(imageURL)
                    .resizable()
                    .scaledToFill()
                    .onTapGesture {
                        onTap()
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "photo.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
            
            if isSending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color.black.opacity(0.4)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 60, lineWidth: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct GlassmorphicVideoMessage: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    let isSending: Bool // ✅ New
    let progress: Double? // ✅ New
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            
            // Play button with glass effect
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                )
            
            // ✅ Progress Overlay (Mejorado)
            if isSending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color.black.opacity(0.4)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 60, lineWidth: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onTapGesture {
            onTap()
        }
    }
}

struct NormalVideoPlayerView: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isPaused = false
    @State private var isMuted = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    
    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let videoUrl = videoUrl, let url = URL(string: videoUrl) {
                MomentsVideoPlayer(
                    url: url,
                    isLooping: true,
                    isPaused: isPaused,
                    isMuted: isMuted,
                    prioritizeSmoothPlayback: true,
                    videoGravity: .resizeAspectFill,
                    onDurationReceived: { value in
                        duration = max(value, 0)
                    },
                    onProgressUpdate: { value in
                        if !isPaused {
                            currentTime = max(value, 0)
                        }
                    },
                    onVideoFinished: {}
                )
                .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                            
                            Capsule()
                                .fill(Color(hex: "FFCC33"))
                                .frame(width: geo.size.width * progressFraction)
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 30)
                .padding(.top, 4)
                
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 14))
                        Text("common.video")
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .textCase(.uppercase)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    )
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    Button(action: { isMuted.toggle() }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPaused = pressing
        }, perform: {})
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        dragOffset = 0
                    }
                }
        )
    }
}

// MARK: - Glassmorphic Input Bar
struct GlassmorphicInputBar: View {
    @Binding var text: String
    @Binding var isTyping: Bool
    @Binding var isRecordingVoice: Bool
    let recordingTime: TimeInterval
    let onSend: () -> Void
    let onCamera: () -> Void
    let onMedia: () -> Void
    let onStartVoiceRecording: () -> Void
    let onStopVoiceRecording: (Bool) -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if !isRecordingVoice {
                HStack(spacing: 8) {
                    Button(action: {
                        onCamera()
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(adaptiveColors.primary)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(
                                        colorScheme == .dark ?
                                        Color.white.opacity(0.12) :
                                        Color.black.opacity(0.06)
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    TextField(LocalizedStringKey("chat.input.placeholder"), text: $text, axis: .vertical)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(adaptiveColors.primary)
                        .accentColor(adaptiveColors.primary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.leading, 2)
                        .padding(.vertical, 10)
                        .onChange(of: text) { newValue in
                            isTyping = !newValue.isEmpty
                            
                            // ✅ Track typing start
                            if newValue.count == 1 {
                            }
                        }
                    
                    if text.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: {
                                // ✅ Track media picker
                                onMedia()
                            }) {
                                Image(systemName: "photo")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(adaptiveColors.mediaIconColor)
                            }
                            
                            Button(action: {
                                // ✅ Track voice message attempt
                                onStartVoiceRecording()
                            }) {
                                Image(systemName: "mic")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(adaptiveColors.mediaIconColor)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .liquidGlass(in: Capsule(), interactive: true)
                .overlay(
                    Capsule()
                        .stroke(
                            colorScheme == .dark ?
                            Color.white.opacity(0.08) :
                            Color.black.opacity(0.05),
                            lineWidth: 0.8
                        )
                )
            } else {
                // Voice recording UI
                VoiceRecordingBar(
                    recordingTime: recordingTime,
                    adaptiveColors: adaptiveColors,
                    onCancel: {
                        onStopVoiceRecording(false)
                    },
                    onSend: {
                        onStopVoiceRecording(true)
                    }
                )
            }
            
            // Send button
            if !text.isEmpty && !isRecordingVoice {
                Button(action: {
                    // ✅ Track message send
                    onSend()
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(adaptiveColors.userAccentColor)
                        .clipShape(Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Supporting Views
struct GlassmorphicDateHeader: View {
    let date: Date
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Text(formatDate(date))
            .font(.custom("Poppins-Regular", size: 12))
            .foregroundColor(adaptiveColors.dateHeaderColor) // ✅ CAMBIO AQUÍ
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .glassmorphicChat()
            .clipShape(Capsule())
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return NSLocalizedString("chat.date.today", comment: "Today")
        } else if calendar.isDateInYesterday(date) {
            return NSLocalizedString("chat.date.yesterday", comment: "Yesterday")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.locale = Locale.current
            return formatter.string(from: date)
        }
    }
}

struct GlassmorphicUnreadDivider: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(adaptiveColors.secondary.opacity(0.25))
                .frame(height: 1)
            
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                Text("chat.newMessages")
                    .font(.custom("Poppins-SemiBold", size: 11))
            }
            .foregroundColor(adaptiveColors.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(adaptiveColors.chatInputBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(adaptiveColors.messageBubbleStroke.opacity(0.7), lineWidth: 0.5)
            )
            
            Rectangle()
                .fill(adaptiveColors.secondary.opacity(0.25))
                .frame(height: 1)
        }
    }
}

struct GlassmorphicAvatar: View {
    let userId: String
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        AsyncProfileImageView(userId: userId)
            .shadow(color: adaptiveColors.primary.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct GlassmorphicTypingIndicator: View {
    @State private var animationAmounts = [0.0, 0.0, 0.0]
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(adaptiveColors.typingIndicatorColor) // ✅ CAMBIO AQUÍ
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmounts[index])
                    .opacity(animationAmounts[index])
                    .onAppear {
                        withAnimation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2)
                        ) {
                            animationAmounts[index] = 1.0
                        }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassmorphicChat()
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct GlassmorphicReplyBar: View {
    let message: EnhancedMessage
    let otherParticipantName: String
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)
                .frame(width: 3.5)
                .padding(.vertical, 8)
                .padding(.leading, 1)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.senderId == currentUserId ? LocalizedStringKey("chat.reply.you") : LocalizedStringKey(otherParticipantName))
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)
                    
                    Text(message.preview)
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(adaptiveColors.replyBarText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let mediaUrl = message.thumbnailUrl ?? message.mediaUrl, let url = URL(string: mediaUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 8)
                }
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(adaptiveColors.replyBarSecondaryText)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(adaptiveColors.replyBarBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

struct GlassmorphicReplyPreview: View {
    let message: EnhancedMessage
    let isParentMessageFromCurrentUser: Bool
    let otherParticipantName: String
    let onTap: (() -> Void)? // ✅ New: Tap callback
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 0) {
                Capsule()
                    .fill(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)
                    .frame(width: 2.5)
                    .padding(.vertical, 6)
                    .padding(.leading, 1)
                
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.senderId == currentUserId ? LocalizedStringKey("chat.reply.you") : LocalizedStringKey(otherParticipantName))
                            .font(.custom("Poppins-SemiBold", size: 11))
                            .foregroundColor(message.senderId == currentUserId ? adaptiveColors.userAccentColor : adaptiveColors.receivedAccentColor)
                        
                        Text(message.preview)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(adaptiveColors.messageTextColor.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if let mediaUrl = message.thumbnailUrl ?? message.mediaUrl, let url = URL(string: mediaUrl) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(adaptiveColors.messageBubbleBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(minWidth: 120, maxWidth: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(adaptiveColors.messageBubbleStroke.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GlassmorphicReactionsView: View {
    let reactions: [String: [String]]
    let onTap: (String) -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(reactions.keys), id: \.self) { emoji in
                Button(action: { onTap(emoji) }) {
                    HStack(spacing: 2) {
                        Text(emoji)
                            .font(.caption)
                        if let count = reactions[emoji]?.count, count > 1 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(adaptiveColors.messageBubbleBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct MessageTimestamp: View {
    let message: EnhancedMessage
    let status: MessageStatus  // ✅ Parámetro explícito para forzar re-render
    let isCurrentUser: Bool
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(formatTime(message.timestamp))
                .font(.custom("Poppins-Regular", size: 11))
                .foregroundColor(adaptiveColors.timestampColor) // ✅ CAMBIO AQUÍ
            
            if message.editedAt != nil {
                Text("chat.edited")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(adaptiveColors.timestampColor) // ✅ CAMBIO AQUÍ
            }
            
            if isCurrentUser {
                MessageStatusIcon(status: status)  // ✅ Usar parámetro explícito
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct MessageStatusIcon: View {
    let status: MessageStatus
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(adaptiveColors.timestampColor.opacity(0.8))
        case .sending:
            HStack(spacing: 2) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(adaptiveColors.timestampColor)
                
                Text("chat.sending")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(adaptiveColors.timestampColor.opacity(0.8))
            }
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(adaptiveColors.timestampColor)
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(adaptiveColors.timestampColor)
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(adaptiveColors.userAccentColor)
        case .failed:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.red)
                
                Text("chat.error")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Full Screen Image View
struct FullScreenImageView: View {
    let imageUrl: URL
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var progress: Double = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            KFImage(imageUrl)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Constant space to keep header position consistent since there's no progress bar
                Color.clear.frame(height: 7)

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 14))
                        Text("common.photo")
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .textCase(.uppercase)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .statusBar(hidden: false)
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onReceive(timer) { _ in
            if progress < 5.0 {
                progress += 0.1
            }
        }
    }
}

// MARK: - Enhanced MomentsChatViewModel with Better Audio Deletion
// MARK: - Glassmorphic Reactions Overlay
struct GlassmorphicReactionsOverlay: View {
    let emojis = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    let onReaction: (String) -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(emojis, id: \.self) { emoji in
                Button(action: {
                    onReaction(emoji)
                }) {
                    Text(emoji)
                        .font(.system(size: 26))
                        .scaleEffect(1.0)
                        .padding(8)
                        .background(.ultraThinMaterial.opacity(0.8))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.7)),
            removal: .scale.combined(with: .opacity).animation(.easeOut(duration: 0.2))
        ))
    }
}

class MomentsChatViewModel: EnhancedChatViewModel {
    @Published var groupedMessages: [(Date, [EnhancedMessage])] = []
    @Published var messagesSentThisSession: Int = 0
    private let chatService = ChatService.shared // ✅ Cambiar a Shared
    
    override init(conversation: Conversation) {
        super.init(conversation: conversation)
        setupMessageGrouping()
    }
    
    private func setupMessageGrouping() {
        $messages
            .map { messages in
                let calendar = Calendar.current
                let grouped = Dictionary(grouping: messages) { message in
                    calendar.startOfDay(for: message.timestamp)
                }
                return grouped.sorted { $0.key < $1.key }
            }
            .assign(to: &$groupedMessages)
    }
    
    // ✅ Función para forzar actualización de groupedMessages
    func updateGroupedMessages() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        groupedMessages = grouped.sorted { $0.key < $1.key }
        
        // ✅ FORZAR SwiftUI a re-renderizar (porque EnhancedMessage es clase, no struct)
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
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
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
            self.updateGroupedMessages()
            self.objectWillChange.send()
        }
        
        chatService.sendMediaMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            type: .image,
            mediaData: imageData,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sentMessage):
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
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
        
        // ✅ Crear mensaje local inmediatamente para feedback visual
        let messageId = UUID().uuidString
        let tempMessage = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            type: .audio,
            content: nil,
            mediaUrl: nil,
            thumbnailUrl: nil,
            duration: duration,
            status: .sending
        )
        
        // Agregar mensaje temporal a la lista local
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
            self.updateGroupedMessages()
            self.objectWillChange.send()
        }
        
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
                    self?.updateMessageInArray(messageId: messageId, newStatus: sentMessage.status)
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
        
        // Agregar mensaje temporal a la lista local
        DispatchQueue.main.async {
            self.messages.append(tempMessage)
            self.updateGroupedMessages()
            self.objectWillChange.send()
        }
        
        let trackingType = mediaType == .image ? "view_once_image" : "view_once_video"
        
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
}

// MARK: - Voice Recording Bar
struct VoiceRecordingBar: View {
    let recordingTime: TimeInterval
    let adaptiveColors: AdaptiveColors
    let onCancel: () -> Void
    let onSend: () -> Void
    
    private var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
            }
            
            // Recording indicator and time
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                        value: recordingTime
                    )
                
                Text("chat.recording")
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(adaptiveColors.recordingIndicator)
                
                LiveWaveformView(color: adaptiveColors.primary)
                    .frame(width: 100, height: 25)
                
                Spacer()
                
                Text(formattedTime)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(adaptiveColors.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassmorphicChat()
            .clipShape(Capsule())
            
            // Send button
            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(adaptiveColors.accent)
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Colores adaptativos mejorados para ChatView
extension AdaptiveColors {
    // MARK: - Colores específicos para chat mejorados
    var chatInputBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215").opacity(0.78) : Color(hex: "FAF9F6").opacity(0.94)
    }
    
    var chatNavigationBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215").opacity(0.78) : Color(hex: "FAF9F6").opacity(0.94)
    }
    
    var searchBarStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)
    }
    
    var mediaIconColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }
    
    var recordingIndicator: Color {
        colorScheme == .dark ? .white : .black
    }
    
    // MARK: - Colores para mensajes mejorados
    var messageBubbleBackground: Color {
        colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.14) : Color(hex: "0B1215").opacity(0.07)
    }
    
    var messageBubbleStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
    }
    
    var messageTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var timestampColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }
    
    var dateHeaderColor: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)
    }
    
    var typingIndicatorColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6)
    }
    
    var replyBarBackground: Color {
        colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.1) : Color(hex: "0B1215").opacity(0.05)
    }
    
    var replyBarText: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var replyBarSecondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6)
    }
    
    // MARK: - Accent Colors
    var userAccentColor: Color {
        // Light mode: System Blue
        // Dark mode: Purple/Indigo
        colorScheme == .dark ? Color.purple : Color.blue
    }
    
    var receivedAccentColor: Color {
        // Light mode: Concrete Gray (Distinct but subtle)
        // Dark mode: White with opacity (Glass effect)
        colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2)
    }
    


    // MARK: - Gradientes específicos para chat actualizados
    var chatBackground: [Color] {
        colorScheme == .dark ? [
            Color(hex: "0B1215"),
            Color(hex: "0B1215"),
            Color(hex: "0B1215")
        ] : [
            Color(hex: "FAF9F6"),
            Color(hex: "FAF9F6"),
            Color(hex: "FAF9F6")
        ]
    }
    
    var messagingBackground: [Color] {
        colorScheme == .dark ? [
            userAccentColor.opacity(0.3),
            Color.blue.opacity(0.2),
            Color(hex: "0B1215")
        ] : [
            userAccentColor.opacity(0.1),
            Color(hex: "FAF9F6"),
            Color(hex: "FAF9F6")
        ]
    }

}

// MARK: - Clustering UI Components
struct GlassmorphicClusterRow: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let showAvatar: Bool
    let otherUserId: String?
    let isOtherParticipantUnavailable: Bool
    let onAvatarTap: () -> Void
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)? // ✅ Added missing property
    let onOpenMedia: (EnhancedMessage) -> Void
    let onLongPress: (EnhancedMessage) -> Void
    let onReply: ([EnhancedMessage]) -> Void // ✅ New: Cluster reply callback
    let onReplyTap: ((String) -> Void)? // ✅ New: Jump to message callback
    let uploadProgress: [String: Double]
    
    @State private var dragOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background Reply Icon (appears when swiping)
            if dragOffset > 0 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(adaptiveColors.userAccentColor)
                    .opacity(Double(min(dragOffset / 60, 1.0)))
                    .offset(x: min(dragOffset - 30, 0))
                    .padding(.leading, 12)
            }
            
            HStack(alignment: .bottom, spacing: 8) {
                if !isCurrentUser {
                    if showAvatar {
                        Button(action: onAvatarTap) {
                            if isOtherParticipantUnavailable {
                                ProfileUnavailableAvatar(size: 32)
                            } else {
                                GlassmorphicAvatar(userId: otherUserId ?? "")
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }
                
                if isCurrentUser { Spacer(minLength: 50) }
                
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    MediaGridBubble(
                        messages: messages,
                        isCurrentUser: isCurrentUser,
                        uploadProgress: uploadProgress,
                        onMomentNavigation: onMomentNavigation,
                        onOpenMedia: onOpenMedia,
                        onLongPress: onLongPress
                    )
                }
                
                if !isCurrentUser { Spacer(minLength: 50) }
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle()) // Asegurar que todo el área es gesture-able
            .highPriorityGesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .local)
                    .onChanged { value in
                        let horizontalMove = value.translation.width
                        let verticalMove = value.translation.height
                        
                        if horizontalMove > 0 && abs(horizontalMove) > abs(verticalMove) {
                            dragOffset = horizontalMove
                            
                            // Haptic Feedback
                            if dragOffset > 60 && !hasTriggeredHaptic {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                hasTriggeredHaptic = true
                            } else if dragOffset < 60 && hasTriggeredHaptic {
                                hasTriggeredHaptic = false
                            }
                        }
                    }
                    .onEnded { value in
                        if dragOffset > 70 {
                            onReply(messages)
                        }
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                            hasTriggeredHaptic = false
                        }
                    }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

struct MediaGridBubble: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let uploadProgress: [String: Double]
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    let onOpenMedia: (EnhancedMessage) -> Void
    let onLongPress: (EnhancedMessage) -> Void
    
    var body: some View {
        let count = messages.count
        let columns = count >= 2 ? 2 : 1
        let gridSpacing: CGFloat = 6
        let gridWidth: CGFloat = 220
        let horizontalInset: CGFloat = 6
        let availableWidth = gridWidth - (horizontalInset * 2)
        let cellWidth = columns == 2 ? (availableWidth - gridSpacing) / 2 : availableWidth
        let cellHeight: CGFloat = count >= 3 ? 94 : cellWidth
        let gridItems = Array(repeating: GridItem(.fixed(cellWidth), spacing: gridSpacing), count: columns)
        let displayedMessages = Array(messages.prefix(4).enumerated())
        
        LazyVGrid(columns: gridItems, spacing: gridSpacing) {
            ForEach(displayedMessages, id: \.element.id) { index, message in
                MediaGridTileView(
                    message: message,
                    progress: uploadProgress[message.id]
                )
                .frame(width: cellWidth, height: cellHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    Group {
                        if index == 3 && count > 4 {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.5))
                                .overlay(
                                    Text("+\(count - 4)")
                                        .font(.custom("Poppins-SemiBold", size: 20))
                                        .foregroundColor(.white)
                                )
                                .allowsHitTesting(false)
                        }
                    }
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    onOpenMedia(message)
                }
                .onLongPressGesture(minimumDuration: 0.3) {
                    onLongPress(message)
                }
            }
        }
        .frame(width: gridWidth)
        .padding(horizontalInset)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial.opacity(0.3))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct MediaGridTileView: View {
    let message: EnhancedMessage
    let progress: Double?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if message.type == .image {
                if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(icon: "photo.fill")
                }
            } else if message.type == .video {
                if let thumbnailUrl = message.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(icon: "video.fill")
                }
                
                Circle()
                    .fill(Color(hex: "0B1215").opacity(0.42))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
            } else {
                placeholder(icon: "doc.fill")
            }
            
            if message.status == .sending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color(hex: "0B1215").opacity(0.38)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 42, lineWidth: 3)
                }
            }
        }
        .background(Color(hex: "FAF9F6").opacity(colorScheme == .dark ? 0.06 : 0.22))
        .clipped()
    }
    
    @ViewBuilder
    private func placeholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.1) : Color(hex: "0B1215").opacity(0.06))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
}

struct ClusterMediaViewer: View {
    let messages: [EnhancedMessage]
    let startIndex: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int
    
    init(messages: [EnhancedMessage], startIndex: Int) {
        self.messages = messages
        self.startIndex = startIndex
        
        let safeInitialIndex: Int
        if messages.isEmpty {
            safeInitialIndex = 0
        } else {
            safeInitialIndex = min(max(startIndex, 0), messages.count - 1)
        }
        _selectedIndex = State(initialValue: safeInitialIndex)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    ClusterMediaViewerPage(message: message)
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            
            HStack {
                Text("\(min(selectedIndex + 1, max(messages.count, 1)))/\(max(messages.count, 1))")
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .statusBar(hidden: true)
    }
}

struct ClusterMediaViewerPage: View {
    let message: EnhancedMessage
    
    var body: some View {
        Group {
            if message.type == .video, let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                MomentsVideoPlayer(
                    url: url,
                    isLooping: true,
                    isPaused: false,
                    videoGravity: .resizeAspect,
                    onVideoFinished: {}
                )
                .ignoresSafeArea()
            } else if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if let thumbnailUrl = message.thumbnailUrl, let url = URL(string: thumbnailUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.6))
                    )
                    .padding(28)
            }
        }
    }
}

// ✅ Identifiable wrapper for cluster selection sheet
struct ClusterWrapper: Identifiable {
    let messages: [EnhancedMessage]
    var id: String {
        messages.first?.id ?? "empty-cluster"
    }
}

// MARK: - Media Selection Sheet for Clusters
struct GlassmorphicMediaSelectionSheet: View {
    let messages: [EnhancedMessage]
    let onSelect: (EnhancedMessage) -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("chat.reply.select_item")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(adaptiveColors.primary.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            ScrollView {
                let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(messages) { message in
                        Button(action: { onSelect(message) }) {
                            ZStack {
                                // ✅ Simple thumbnails sin gestos propios
                                if message.type == .image, let urlString = message.mediaUrl, let url = URL(string: urlString) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                } else if message.type == .video {
                                    // Video thumbnail
                                    if let thumbUrl = message.thumbnailUrl, let url = URL(string: thumbUrl) {
                                        KFImage(url)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.1))
                                    }
                                    // Play icon overlay
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "play.fill")
                                                .foregroundColor(.white)
                                                .font(.system(size: 16))
                                        )
                                }
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(adaptiveColors.primary.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(
            RoundedCorner(radius: 30, corners: [.topLeft, .topRight])
                .stroke(adaptiveColors.primary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedCorner(radius: 30, corners: [.topLeft, .topRight]))
    }
}

// MARK: - Helper Styles
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}
// MARK: - Premium Unified Message Options Menu
struct GlassmorphicMessageOptionsMenu: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onDeleteForEveryone: () -> Void
    let onDeleteForMe: () -> Void
    let onEdit: () -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onReaction: (String) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var animateIn = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    let reactionEmojis = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    
    var body: some View {
        ZStack {
            // Background Blur & Tint
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(animateIn ? 1 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    handleDismiss()
                }
            
            VStack(spacing: 20) {
                // 1. Reactions Capsule
                HStack(spacing: 15) {
                    ForEach(reactionEmojis, id: \.self) { emoji in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onReaction(emoji)
                        }) {
                            Text(emoji)
                                .font(.system(size: 30))
                                .scaleEffect(animateIn ? 1.0 : 0.5)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(adaptiveColors.messageBubbleBackground)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                )
                .overlay(
                    Capsule()
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
                )
                .scaleEffect(animateIn ? 1.0 : 0.8)
                .opacity(animateIn ? 1 : 0)
                
                // 2. Message Actions Card
                VStack(spacing: 1) {
                    if !message.isDeleted {
                        MenuRow(title: "chat.action.reply", icon: "arrowshape.turn.up.left", adaptiveColors: adaptiveColors) {
                            onReply()
                        }
                        
                        Divider().background(adaptiveColors.messageBubbleStroke)
                        
                        if isCurrentUser && message.type == .text {
                            MenuRow(title: "chat.action.edit", icon: "pencil", adaptiveColors: adaptiveColors) {
                                onEdit()
                            }
                            Divider().background(adaptiveColors.messageBubbleStroke)
                        }
                        
                        if message.type == .text {
                            MenuRow(title: "chat.action.copy", icon: "doc.on.doc", adaptiveColors: adaptiveColors) {
                                onCopy()
                            }
                            Divider().background(adaptiveColors.messageBubbleStroke)
                        }
                        
                        MenuRow(title: "chat.action.deleteForMe", icon: "trash", isDestructive: true, adaptiveColors: adaptiveColors) {
                            onDeleteForMe()
                        }
                        
                        if isCurrentUser && !message.isRead && isWithinDeleteLimit(message.timestamp) {
                            Divider().background(adaptiveColors.messageBubbleStroke)
                            MenuRow(title: "chat.action.deleteForEveryone", icon: "trash.fill", isDestructive: true, adaptiveColors: adaptiveColors) {
                                onDeleteForEveryone()
                            }
                        }
                    }
                }
                .frame(width: 250)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(adaptiveColors.messageBubbleBackground)
                        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
                )
                .offset(y: animateIn ? 0 : 20)
                .opacity(animateIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                animateIn = true
            }
        }
    }
    
    private func handleDismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
    
    private func isWithinDeleteLimit(_ timestamp: Date) -> Bool {
        return Date().timeIntervalSince(timestamp) < 7200
    }
}

struct MenuRow: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool = false
    let adaptiveColors: AdaptiveColors
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack {
                Text(title)
                    .font(.custom("Poppins-Regular", size: 16))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 18))
            }
            .foregroundColor(isDestructive ? .red : adaptiveColors.messageTextColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GlassActionButton: View {
    let title: LocalizedStringKey
    let icon: String
    var isDestructive: Bool = false
    let adaptiveColors: AdaptiveColors
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24)
                Text(title)
                    .font(.custom("Poppins-Regular", size: 16))
                Spacer()
            }
            .foregroundColor(isDestructive ? Color.red : adaptiveColors.messageTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(adaptiveColors.messageBubbleBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
