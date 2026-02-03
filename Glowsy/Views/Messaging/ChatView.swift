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
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    // ✅ NUEVO: Instancia de PrivacyService para verificar historias
    private let privacyService = PrivacyService()
    
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
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: MomentsChatViewModel(conversation: conversation))
    }
    
    var body: some View {
        ZStack {
            // Glassmorphic background
            ChatGlassmorphicBackground(adaptiveColors: adaptiveColors)
            
            VStack(spacing: 0) {
                // Custom Navigation Bar con navegación al perfil
                glassmorphicNavigationBar
                
                // Messages List
                messagesListSection
                
                // Reply Bar
                replyBarSection
                
                // Input Bar
                inputBarSection
            }
        }
        .navigationBarHidden(true)
        .photosPicker(isPresented: $showMediaPicker, selection: $selectedItems, maxSelectionCount: 10)
        .sheet(isPresented: $showEnhancedCamera) {
            EnhancedCameraPickerView { data, mediaType, isEphemeral in
                handleCameraCapture(data: data, mediaType: mediaType, isEphemeral: isEphemeral)
            }
        }
        .onChange(of: selectedItems) { items in
            for item in items {
                viewModel.handlePhotoPickerItem(item)
            }
            selectedItems = []
        }
        .sheet(item: $showingMessageOptions) { message in
            GlassmorphicMessageOptionsSheet(
                message: message,
                isCurrentUser: message.senderId == viewModel.currentUserId,
                onDelete: {
                    viewModel.deleteMessageWithCleanup(message)
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
                }
            )
        }
        .sheet(isPresented: $showingConversationSettings) {
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
        .alert("Error", isPresented: $showingMomentError) {
            Button("OK") { }
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
        }
        .onDisappear {
            onDisappearActions()
        }
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
                    .glassmorphicChat()
                    .clipShape(Circle())
            }
            
            // ✅ ACTUALIZADO: User info con navegación al perfil
            HStack(spacing: 10) {
                // ✅ SEPARADO: Botón solo para la foto (historias o perfil)
                Button(action: {
                    if hasStory {
                        // ✅ SI TIENE HISTORIAS: Establecer userId y abrir StoriesView
                        storiesUserId = viewModel.conversation.otherParticipantId
                        showingStories = true
                    } else {
                        // ✅ SI NO TIENE HISTORIAS: Ir al perfil
                        showingUserProfile = true
                    }
                }) {
                    // ✅ ACTUALIZADO: Usar el componente asíncrono centralizado para tiempo real
                    AsyncProfileImageView(userId: viewModel.conversation.otherParticipantId ?? "")
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(
                            StorySegmentedRing(
                                storyCount: storyCount,
                                hasStory: hasStory,
                                hasUnseenStory: hasUnseenStory,
                                storyViewedStatus: storyViewedStatus,
                                isOwnStory: false,
                                colorScheme: colorScheme,
                                ringSize: 40,
                                lineWidth: 2.5
                            )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                // ✅ SEPARADO: Botón solo para el nombre (siempre al perfil)
                Button(action: {
                    showingUserProfile = true
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(viewModel.conversation.otherParticipantUsername ?? "Usuario")
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(adaptiveColors.primary)
                            
                            // ✅ INSIGNIA DE VERIFICADO
                            VerifiedBadgeView(userId: viewModel.conversation.otherParticipantId ?? "", size: 14)
                        }
                        
                        if !viewModel.typingUsers.isEmpty {
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
            
            Spacer()
            
            // Settings button
            Button(action: {
                showingConversationSettings = true
            }) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 40, height: 40)
                    .glassmorphicChat()
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            adaptiveColors.chatNavigationBackground
                .blur(radius: 10)
                .ignoresSafeArea()
        )
        .onAppear {
            checkUserStories()
        }
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
                        
                        ForEach(self.clusterMessages(messages)) { item in
                            renderMessageItem(item, in: messages, proxy: proxy)
                        }
                    }
                    
                    if !viewModel.typingUsers.isEmpty {
                        GlassmorphicTypingIndicator()
                            .padding(.horizontal)
                            .id("typing")
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: viewModel.messages.last?.id) { lastMessageId in
                // ✅ Solo hacer scroll si cambia el ÚLTIMO mensaje (nuevo mensaje)
                // Esto evita el scroll al cargar historial (donde cambia el PRIMER mensaje)
                withAnimation {
                    proxy.scrollTo(lastMessageId ?? "typing", anchor: .bottom)
                }
            }
        }
    }
    
    // ✅ REFACTORIZADO: Sección de barra de respuesta
    private var replyBarSection: some View {
        Group {
            if let replyingTo = replyingTo {
                GlassmorphicReplyBar(
                    message: replyingTo,
                    otherParticipantName: viewModel.conversation.otherParticipantUsername ?? "Usuario"
                ) {
                    self.replyingTo = nil
                }
            }
        }
    }
    
    // ✅ REFACTORIZADO: Sección de barra de entrada
    private var inputBarSection: some View {
        GlassmorphicInputBar(
            text: $messageText,
            isTyping: $viewModel.isTyping,
            isRecordingVoice: $isRecordingVoice,
            recordingTime: recordingTime,
            onSend: {
                let messageToSend = messageText
                let replyToMessageId = replyingTo?.id
                
                guard !messageToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                
                messageText = ""
                replyingTo = nil
                
                viewModel.sendTextMessage(messageToSend, replyTo: replyToMessageId)
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
            onStopVoiceRecording: {
                stopVoiceRecording()
            }
        )
        .focused($isTextFieldFocused)
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
                otherParticipantName: viewModel.conversation.otherParticipantUsername ?? "Usuario",
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
                progress: viewModel.uploadProgress[message.id]
            )
            .id(message.id)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(highlightedMessageId == message.id ? Color.white.opacity(0.15) : Color.clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .scaleEffect(highlightedMessageId == message.id ? 1.03 : 1.0)
            .onLongPressGesture {
                showingMessageOptions = message
            }
            
        case .mediaCluster(let clusterMessages):
            GlassmorphicClusterRow(
                messages: clusterMessages,
                isCurrentUser: clusterMessages.first?.senderId == viewModel.currentUserId,
                showAvatar: shouldShowAvatar(for: clusterMessages.first!, in: messages),
                otherUserId: viewModel.conversation.otherParticipantId,
                onAvatarTap: { showingUserProfile = true },
                onMessageViewed: { messageId in
                    if let index = viewModel.messages.firstIndex(where: { $0.id == messageId }) {
                        viewModel.messages[index].isViewed = true
                    }
                },
                onMomentNavigation: { message in
                    handleMomentNavigationFromChat(message: message)
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
        AnalyticsService.shared.trackScreenView("ChatView")
        AnalyticsService.shared.trackFeatureUsage("chat")
        AnalyticsService.shared.trackInteraction("chat_opened", details: [
            "conversationId": viewModel.conversation.id,
            "otherUserId": viewModel.conversation.otherParticipantId ?? "unknown"
        ])
        viewModel.isChatVisible = true  // ✅ Marcar chat como visible
        viewModel.startListening()
        setupOnlineStatusObserver()
    }
    
    // ✅ REFACTORIZADO: Acciones al desaparecer
    private func onDisappearActions() {
        viewModel.isChatVisible = false  // ✅ Marcar chat como no visible
        
        AnalyticsService.shared.trackInteraction("chat_closed", details: [
            "conversationId": viewModel.conversation.id,
            "messagesSent": viewModel.messagesSentThisSession
        ])
        viewModel.stopListening()
        statusListener?.remove()
    }
    
    // ✅ ACTUALIZADO: Función para verificar historias del usuario (con filtrado de privacidad como en reels)
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId ?? ""
        guard !otherUserId.isEmpty else { return }
        
        // ✅ USAR LA MISMA LÓGICA DE REELS: Verificar historias con filtrado de privacidad
        Firestore.firestore().collection("users").document(otherUserId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
                    return
                }
                
                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }
                
                guard !stories.isEmpty else {
                    DispatchQueue.main.async {
                        self.hasStory = false
                        self.hasUnseenStory = false
                    }
                    return
                }
                
                // ✅ FILTRADO DE PRIVACIDAD: Solo contar historias que se pueden ver
                let group = DispatchGroup()
                var visibleStories: [(story: Story, wasViewed: Bool)] = []
                let syncQueue = DispatchQueue(label: "story.visibility.check")
                
                for story in stories {
                    group.enter()
                    // ✅ USAR PRIVACY SERVICE como en reels
                    self.privacyService.canUserViewStoryEnhanced(story, viewerId: currentUserId) { canView in
                        if canView {
                            if let storyId = story.id {
                                group.enter()
                                Firestore.firestore().collection("users").document(story.authorId)
                                    .collection("stories").document(storyId)
                                    .collection("viewers").document(currentUserId)
                                    .getDocument { viewerDoc, _ in
                                        let wasViewed = viewerDoc?.exists == true
                                        syncQueue.async {
                                            visibleStories.append((story: story, wasViewed: wasViewed))
                                        }
                                        group.leave()
                                    }
                            } else {
                                syncQueue.async {
                                    visibleStories.append((story: story, wasViewed: false))
                                }
                            }
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    if !visibleStories.isEmpty {
                        self.hasStory = true
                        let storyCount = visibleStories.count
                        // Ordenar por timestamp y extraer el estado de visto
                        let sortedStories = visibleStories.sorted { story1, story2 in
                            (story1.story.timestamp ?? Date.distantPast) < (story2.story.timestamp ?? Date.distantPast)
                        }
                        let viewedStatus = sortedStories.map { $0.wasViewed }
                        let hasUnseenVisible = viewedStatus.contains(false)
                        
                        self.storyCount = storyCount
                        self.storyViewedStatus = viewedStatus
                        self.hasUnseenStory = hasUnseenVisible
                    } else {
                        self.hasStory = false
                        self.hasUnseenStory = false
                        self.storyCount = 0
                        self.storyViewedStatus = []
                    }
                }
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
        guard let conversationId = viewModel.conversation.id else {
            return
        }
        
        // ✅ AGREGAR ESTA LÍNEA DE DEBUG:
        
        if isEphemeral {
            viewModel.sendViewOnceMessage(data: data, mediaType: mediaType)
            
            AnalyticsService.shared.trackInteraction("view_once_message_sent", details: [
                "mediaType": mediaType == .image ? "view_once_image" : "view_once_video", // ✅ CAMBIAR ESTO
                "conversationId": conversationId
            ])
        } else {
            if mediaType == .image {
                viewModel.sendImageMessage(data)
            } else {
                viewModel.sendVideoMessage(data: data)
            }
            
            AnalyticsService.shared.trackInteraction("normal_camera_message_sent", details: [
                "mediaType": mediaType == .image ? "image" : "video",
                "conversationId": conversationId
            ])
        }
        
        showEnhancedCamera = false
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
        AnalyticsService.shared.trackInteraction("voice_recording_started", details: [
            "conversationId": viewModel.conversation.id
        ])
        
        // Iniciar timer para mostrar duración
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
            
            // Límite máximo de 60 segundos
            if recordingTime >= 60.0 {
                stopVoiceRecording()
            }
        }
        
        // Aquí integrarías la lógica real de grabación de audio
        AudioRecordingManager.shared.startRecording()
    }
    
    private func stopVoiceRecording() {
        isRecordingVoice = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // ✅ Track voice recording completion
        AnalyticsService.shared.trackInteraction("voice_recording_completed", details: [
            "conversationId": viewModel.conversation.id,
            "duration": recordingTime
        ])
        
        // Aquí obtendrías los datos del audio grabado
        AudioRecordingManager.shared.stopRecording { audioData in
            if let audioData = audioData {
                viewModel.sendAudioMessage(audioData, duration: recordingTime)
            }
        }
        
        recordingTime = 0
    }
}

// ✅ NUEVO: Función para manejar navegación al momento desde el chat
extension GlassmorphicChatView {
    // MARK: - Clustering Logic
    private func clusterMessages(_ input: [EnhancedMessage]) -> [MessageItem] {
        var result: [MessageItem] = []
        var currentCluster: [EnhancedMessage] = []
        
        for message in input {
            // Only cluster images/videos
            let isClusterable = message.type == .image || message.type == .video
            
            if isClusterable {
                if let last = currentCluster.last {
                    let timeDiff = abs(message.timestamp.timeIntervalSince(last.timestamp))
                    let sameSender = message.senderId == last.senderId
                    
                    if sameSender && timeDiff < 60 { // WhatsApp grouping threshold
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
            // Gradiente base adaptativo
            LinearGradient(
                gradient: Gradient(colors: adaptiveColors.chatBackground),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Blobs animados adaptativos
            GeometryReader { geometry in
                // Blob 1
                Circle()
                    .fill(
                        colorScheme == .dark ?
                        Color(hex: "00A896").opacity(0.2) :
                        Color(hex: "00A896").opacity(0.08)
                    )
                    .frame(width: 250, height: 250)
                    .blur(radius: colorScheme == .dark ? 80 : 60)
                    .offset(x: geometry.size.width * 0.7, y: geometry.size.height * 0.2)
                
                // Blob 2
                Circle()
                    .fill(
                        colorScheme == .dark ?
                        Color(hex: "02C39A").opacity(0.2) :
                        Color(hex: "02C39A").opacity(0.06)
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: colorScheme == .dark ? 100 : 80)
                    .offset(x: -50, y: geometry.size.height * 0.6)
                
                // Blob 3 adicional para modo claro
                if colorScheme == .light {
                    Circle()
                        .fill(Color(hex: "F0F3BD").opacity(0.04))
                        .frame(width: 200, height: 200)
                        .blur(radius: 60)
                        .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.8)
                }
            }
            
            // Overlay de material adaptativo
            Rectangle()
                .fill(
                    colorScheme == .dark ?
                    Color.black.opacity(0.1) :
                    Color.white.opacity(0.2)
                )
                .ignoresSafeArea()
        }
    }
}

extension View {
    func glassmorphicChat() -> some View {
        modifier(GlassmorphicModifier())
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


// MARK: - Glassmorphic Message Row
struct GlassmorphicMessageRow: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let showAvatar: Bool
    let otherUserId: String?
    let otherParticipantName: String
    let repliedMessage: EnhancedMessage?
    let onReply: () -> Void
    let onReaction: (String) -> Void
    let onAvatarTap: () -> Void // ✅ NUEVO: Callback para tap en avatar
    let onReplyTap: ((String) -> Void)? // ✅ New: Jump to message
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)? // ✅ NUEVO: Callback para navegación al momento
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
                            GlassmorphicAvatar(userId: otherUserId ?? "")
                                .frame(width: 32, height: 32)
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
                        onMomentNavigation: onMomentNavigation
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
        .padding(.vertical, 2)
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
            return "Mensaje de audio eliminado"
        case .image:
            return "Imagen eliminada"
        case .video:
            return "Video eliminado"
        case .text:
            return "Mensaje eliminado"
        case .file:
            return "Archivo eliminado"
        case .location:
            return "Ubicación eliminada"
        case .ephemeral:
            return "Momento efímero eliminado"
        default:
            return "Mensaje eliminado"
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
                        progress: progress, // ✅ Pass progress
                        onViewed: {
                            markViewOnceAsViewed()
                        }
                    )
                    .onAppear {
                        AnalyticsService.shared.trackInteraction("view_once_message_displayed", details: [
                            "messageType": message.type.rawValue,
                            "isCurrentUser": isCurrentUser
                        ])
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
                        progress: progress
                    )
                    .frame(maxWidth: 250, maxHeight: 300)
                        .onAppear {
                            AnalyticsService.shared.trackInteraction("image_message_viewed")
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
                        AnalyticsService.shared.trackInteraction("audio_message_viewed")
                    }
                    
                case .video:
                    GlassmorphicVideoMessage(
                        videoUrl: message.mediaUrl,
                        thumbnailUrl: message.thumbnailUrl,
                        isSending: message.status == .sending,
                        progress: progress
                    )
                    .frame(maxWidth: 250, maxHeight: 300)
                        .onAppear {
                            AnalyticsService.shared.trackInteraction("video_message_viewed")
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
                                        progress: nil
                                    )
                                }
                            }
                            .onTapGesture {
                                AnalyticsService.shared.trackInteraction("ephemeral_message_opened", details: [
                                    "messageId": message.id
                                ])
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
                        AnalyticsService.shared.trackInteraction("shared_moment_viewed")
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
                AnalyticsService.shared.trackInteraction("message_received_viewed", details: [
                    "messageType": message.type.rawValue,
                    "senderId": message.senderId
                ])
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
    @State private var showFullScreen = false
    
    var body: some View {
        if let url = imageUrl, let imageURL = URL(string: url) {
            KFImage(imageURL)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                .overlay(
                    Group {
                        if isSending, let uploadProgress = progress {
                            ZStack {
                                Color.black.opacity(0.4) // Máximo contraste
                                BlurView(style: UIBlurEffect.Style.systemThinMaterialDark) // Desenfoque premium
                                MediaProgressRing(progress: uploadProgress, size: 60, lineWidth: 4)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                )
                .onTapGesture {
                    showFullScreen = true
                }
                .fullScreenCover(isPresented: $showFullScreen) {
                    FullScreenImageView(imageUrl: imageURL)
                }
        }
    }
}

struct GlassmorphicVideoMessage: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    let isSending: Bool // ✅ New
    let progress: Double? // ✅ New
    @State private var showPlayer = false
    
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
            if isSending, let uploadProgress = progress {
                ZStack {
                    Color.black.opacity(0.4)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 60, lineWidth: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onTapGesture {
            showPlayer = true
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NormalVideoPlayerView(videoUrl: videoUrl, thumbnailUrl: thumbnailUrl)
        }
    }
}

struct NormalVideoPlayerView: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isPaused = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let videoUrl = videoUrl, let url = URL(string: videoUrl) {
                MomentsVideoPlayer(
                    url: url,
                    isLooping: true,
                    isPaused: isPaused,
                    videoGravity: .resizeAspectFill,
                    onVideoFinished: {}
                )
                .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Progress Bar (Simple white line for normal media)
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
                
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 14))
                        Text("common.video")
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
    let onStopVoiceRecording: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Camera button
            Button(action: {
                // ✅ Track camera usage in chat
                AnalyticsService.shared.trackInteraction("chat_camera_tapped")
                onCamera()
            }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(adaptiveColors.primary)
                    .frame(width: 40, height: 40)
                    .glassmorphicChat()
                    .clipShape(Circle())
            }
            
            // Text field with glass effect
            if !isRecordingVoice {
                HStack(spacing: 8) {
                    TextField("Mensaje...", text: $text, axis: .vertical)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(adaptiveColors.primary)
                        .accentColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .onChange(of: text) { newValue in
                            isTyping = !newValue.isEmpty
                            
                            // ✅ Track typing start
                            if newValue.count == 1 {
                                AnalyticsService.shared.trackInteraction("chat_typing_started")
                            }
                        }
                    
                    if text.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: {
                                // ✅ Track media picker
                                AnalyticsService.shared.trackInteraction("chat_media_picker_tapped")
                                onMedia()
                            }) {
                                Image(systemName: "photo")
                                    .font(.system(size: 18))
                                    .foregroundColor(adaptiveColors.mediaIconColor)
                            }
                            
                            Button(action: {
                                // ✅ Track voice message attempt
                                AnalyticsService.shared.trackInteraction("chat_voice_message_tapped")
                                onStartVoiceRecording()
                            }) {
                                Image(systemName: "mic")
                                    .font(.system(size: 18))
                                    .foregroundColor(adaptiveColors.mediaIconColor)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                }
                .glassmorphicChat()
                .clipShape(Capsule())
            } else {
                // Voice recording UI
                VoiceRecordingBar(
                    recordingTime: recordingTime,
                    adaptiveColors: adaptiveColors,
                    onCancel: {
                        onStopVoiceRecording()
                    },
                    onSend: {
                        onStopVoiceRecording()
                    }
                )
            }
            
            // Send button
            if !text.isEmpty && !isRecordingVoice {
                Button(action: {
                    // ✅ Track message send
                    AnalyticsService.shared.trackInteraction("message_sent", details: [
                        "messageType": "text",
                        "messageLength": text.count,
                        "hasReply": false // Ajustar según el contexto
                    ])
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
        .background(
            adaptiveColors.chatInputBackground
                .blur(radius: 10)
        )
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
            return "Hoy"
        } else if calendar.isDateInYesterday(date) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.locale = Locale(identifier: "es_ES")
            return formatter.string(from: date)
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

// MARK: - Message Options Sheet
struct GlassmorphicMessageOptionsSheet: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onDelete: () -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onReaction: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    let reactionEmojis = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    
    var body: some View {
        ZStack {
            // Background adaptativo
            (colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            
            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(adaptiveColors.messageTextColor.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                
                // ✅ Solo mostrar reacciones si el mensaje NO está eliminado
                if !message.isDeleted {
                    // Quick reactions
                    HStack(spacing: 16) {
                        ForEach(reactionEmojis, id: \.self) { emoji in
                            Button(action: {
                                AnalyticsService.shared.trackInteraction("message_reaction_added", details: [
                                    "reactionEmoji": emoji,
                                    "messageType": message.type.rawValue
                                ])
                                onReaction(emoji)
                                dismiss()
                            }) {
                                Text(emoji)
                                    .font(.system(size: 35))
                                    .scaleEffect(1.0)
                                    .frame(width: 50, height: 50)
                                    .background(adaptiveColors.messageBubbleBackground)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
                                    )
                                    .shadow(color: adaptiveColors.primary.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                
                // Actions
                VStack(spacing: 8) {
                    // ✅ Solo mostrar responder si NO está eliminado
                    if !message.isDeleted {
                        GlassActionButton(
                            title: "Responder",
                            icon: "arrowshape.turn.up.left",
                            adaptiveColors: adaptiveColors
                        ) {
                            AnalyticsService.shared.trackInteraction("message_reply_tapped")
                            onReply()
                            dismiss()
                        }
                    }
                    
                    // ✅ Solo mostrar copiar para texto y si NO está eliminado
                    if message.type == .text && !message.isDeleted {
                        GlassActionButton(
                            title: "Copiar",
                            icon: "doc.on.doc",
                            adaptiveColors: adaptiveColors
                        ) {
                            AnalyticsService.shared.trackInteraction("message_copied")
                            onCopy()
                            dismiss()
                        }
                    }
                    
                    // ✅ Solo el usuario actual puede eliminar Y solo si NO está ya eliminado
                    if isCurrentUser && !message.isDeleted {
                        GlassActionButton(
                            title: "Eliminar",
                            icon: "trash",
                            isDestructive: true,
                            adaptiveColors: adaptiveColors
                        ) {
                            AnalyticsService.shared.trackInteraction("message_deleted")
                            onDelete()
                            dismiss()
                        }
                    }
                    
                    // ✅ Si está eliminado, mostrar info
                    if message.isDeleted {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 18))
                                .frame(width: 24)
                            Text("chat.message.deleted")
                                .font(.custom("Poppins-Regular", size: 16))
                            Spacer()
                        }
                        .foregroundColor(adaptiveColors.messageTextColor.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(adaptiveColors.messageBubbleBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(
                ZStack {
                    // Fondo base adaptativo
                    Rectangle()
                        .fill(
                            colorScheme == .dark ?
                            Color.black.opacity(0.8) :
                            Color.white.opacity(0.95)
                        )
                    
                    // Material effect
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.3 : 0.7)
                }
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 1)
            )
            .shadow(color: adaptiveColors.primary.opacity(0.1), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 20)
        }
        .onAppear {
            AnalyticsService.shared.trackInteraction("message_options_opened", details: [
                "messageType": message.type.rawValue,
                "isCurrentUser": isCurrentUser,
                "isDeleted": message.isDeleted
            ])
        }
    }
}

struct GlassActionButton: View {
    let title: String
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
                        Text("Foto")
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
class MomentsChatViewModel: EnhancedChatViewModel {
    @Published var groupedMessages: [(Date, [EnhancedMessage])] = []
    @Published var messagesSentThisSession: Int = 0
    private let chatService = ChatService() // ✅ Agregar ChatService
    
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
            error = "No se puede enviar el mensaje: ID de conversación no válido"
            return
        }
        
        // Track antes de enviar
        AnalyticsService.shared.trackInteraction("text_message_sent", details: [
            "messageLength": content.count,
            "hasReply": replyTo != nil,
            "conversationId": conversation.id
        ])
        
        messagesSentThisSession += 1
        
        // ✅ USAR el método de la clase padre que maneja mensajes temporales
        super.sendTextMessage(content, replyTo: replyTo)
    }
    
    func trackMediaMessageSent(type: String) {
        AnalyticsService.shared.trackInteraction("media_message_sent", details: [
            "mediaType": type,
            "conversationId": conversation.id
        ])
        messagesSentThisSession += 1
    }
    
    // MARK: - Enhanced Delete Message with Cleanup
    func deleteMessageWithCleanup(_ message: EnhancedMessage) {
        // Track deletion
        AnalyticsService.shared.trackInteraction("message_deleted", details: [
            "messageType": message.type.rawValue,
            "messageId": message.id,
            "conversationId": conversation.id
        ])
        
        // Use the enhanced delete method from ChatService
        chatService.deleteMessageWithCleanup(conversationId: message.conversationId, messageId: message.id) { error in
            if let error = error {
            } else {
            }
        }
        
        // Force UI update
        objectWillChange.send()
    }
    
    // MARK: - New Media Message Functions
    func sendImageMessage(_ imageData: Data) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar la imagen: ID de conversación no válido"
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
                case .success(_):
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = "Error al enviar imagen: \(error.localizedDescription)"
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    func sendAudioMessage(_ audioData: Data, duration: TimeInterval) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el audio: ID de conversación no válido"
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
                case .success(_):
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = "Error al enviar audio: \(error.localizedDescription)"
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
    }
    
    // ✅ NUEVA función para enviar mensajes view-once
    func sendViewOnceMessage(data: Data, mediaType: EnhancedCameraPickerView.MediaType) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            error = "No se puede enviar el mensaje: ID de conversación no válido"
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
        AnalyticsService.shared.trackInteraction("view_once_message_sent", details: [
            "mediaType": trackingType,
            "conversationId": conversationId
        ])
        
        chatService.sendViewOnceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            mediaData: data,
            mediaType: mediaType,
            messageId: messageId // ✅ Pasar el mismo ID
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // ✅ SOLO cambiar el estado, no reemplazar
                    self?.updateMessageInArray(messageId: messageId, newStatus: .sent)
                case .failure(let error):
                    self?.error = "Error al enviar mensaje: \(error.localizedDescription)"
                    self?.updateMessageInArray(messageId: messageId, newStatus: .failed)
                }
            }
        }
        
        messagesSentThisSession += 1
    }
    
    // ✅ NUEVA función para enviar video normal
    override func sendVideoMessage(data: Data) {
        trackMediaMessageSent(type: "video")
        
        chatService.sendMediaMessage(
            conversationId: conversation.id ?? "",
            senderId: currentUserId,
            type: .video,
            mediaData: data
        ) { result in
            switch result {
            case .success(let message):
                // Video message sent successfully
                break
            case .failure(let error):
                // Handle error if needed
                break
            }
        }
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
                    .background(Color(hex: "00A896"))
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Colores adaptativos mejorados para ChatView
extension AdaptiveColors {
    // MARK: - Colores específicos para chat mejorados
    var chatInputBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.9)
    }
    
    var chatNavigationBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.2) : Color.white.opacity(0.9)
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
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
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
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
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
            Color(hex: "0F172A"), // Slate 900
            Color(hex: "1E293B"), // Slate 800
            Color(hex: "334155")  // Slate 700
        ] : [
            Color(hex: "F1F5F9"), // Slate 100
            Color(hex: "E2E8F0"), // Slate 200
            Color(hex: "CBD5E1")  // Slate 300
        ]
    }
    
    var messagingBackground: [Color] {
        colorScheme == .dark ? [
            userAccentColor.opacity(0.3),
            Color.blue.opacity(0.2),
            Color.black
        ] : [
            userAccentColor.opacity(0.1),
            Color.white,
            Color.white
        ]
    }

}

// MARK: - Clustering UI Components
struct GlassmorphicClusterRow: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let showAvatar: Bool
    let otherUserId: String?
    let onAvatarTap: () -> Void
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)? // ✅ Added missing property
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
                            GlassmorphicAvatar(userId: otherUserId ?? "")
                                .frame(width: 32, height: 32)
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
                        onMomentNavigation: onMomentNavigation
                    )
                }
                
                if !isCurrentUser { Spacer(minLength: 50) }
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle()) // Asegurar que todo el área es gesture-able
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
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
        .padding(.vertical, 4)
    }
}

struct MediaGridBubble: View {
    let messages: [EnhancedMessage]
    let isCurrentUser: Bool
    let uploadProgress: [String: Double]
    let onMomentNavigation: ((EnhancedMessage) -> Void)?
    
    var body: some View {
        let count = messages.count
        let columns = count >= 2 ? 2 : 1
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)
        
        LazyVGrid(columns: gridItems, spacing: 4) {
            ForEach(messages.prefix(4)) { message in
                Group {
                    if message.type == .image {
                        GlassmorphicImageMessage(
                            imageUrl: message.mediaUrl,
                            isSending: message.status == .sending,
                            progress: uploadProgress[message.id]
                        )
                    } else if message.type == .video {
                        GlassmorphicVideoMessage(
                            videoUrl: message.mediaUrl,
                            thumbnailUrl: message.thumbnailUrl,
                            isSending: message.status == .sending,
                            progress: uploadProgress[message.id]
                        )
                    }
                }
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: count > 2 ? 120 : 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(width: 250)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.3))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
