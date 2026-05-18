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
    
    // ✅ REFACTOR: Dividido en variables separadas para evitar el error del compilador (timeout AST)
    private var baseChatView: some View {
        GeometryReader { geometry in
            chatRootContent(safeAreaTop: geometry.safeAreaInsets.top)
        }
        .navigationBarHidden(true)
        .photosPicker(isPresented: $showMediaPicker, selection: $selectedItems, maxSelectionCount: 10)
        .fullScreenCover(isPresented: $showEnhancedCamera) {
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
    }
    
    private var chatViewWithSettingsAndStories: some View {
        baseChatView
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
    }
    
    var body: some View {
        chatViewWithSettingsAndStories
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

// MARK: - Enhanced MomentsChatViewModel with Better Audio Deletion
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
