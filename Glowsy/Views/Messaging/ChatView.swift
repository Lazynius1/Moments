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
    @StateObject private var viewModel: InstagramChatViewModel
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var messageText: String = ""
    @State private var showMediaPicker: Bool = false
    @State private var showEnhancedCamera = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var replyingTo: EnhancedMessage?
    @State private var editingMessage: EnhancedMessage?
    @State private var showingMessageOptions: EnhancedMessage?
    @State private var scrollToBottom = false
    @State private var showCameraSheet = false
    @State private var isRecordingVoice = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var showingConversationSettings = false
    @State private var otherUserStatus: OnlineStatus = .offline
    @State private var otherUserLastSeen: Date?
    @State private var statusListener: ListenerRegistration?
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    // ✅ NUEVO: Estados para navegación al perfil
    @State private var showingUserProfile = false
    @State private var navigateToProfile = false
    
    // ✅ NUEVO: Estados para navegación al momento
    @State private var showingMomentDetail = false
    @State private var selectedMoment: Moment?
    @State private var showingMomentError = false
    // ✅ HISTORIAS: Estados para anillo de historias
    @State private var hasStory: Bool = false
    @State private var hasUnseenStory: Bool = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: InstagramChatViewModel(conversation: conversation))
    }
    
    var body: some View {
        ZStack {
            // Glassmorphic background
            ChatGlassmorphicBackground(adaptiveColors: adaptiveColors)
            
            VStack(spacing: 0) {
                // Custom Navigation Bar con navegación al perfil
                glassmorphicNavigationBar
                
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.groupedMessages, id: \.0) { date, messages in
                                GlassmorphicDateHeader(date: date)
                                    .padding(.vertical, 10)
                                
                                ForEach(messages) { message in
                                    GlassmorphicMessageRow(
                                        message: message,
                                        isCurrentUser: message.senderId == viewModel.currentUserId,
                                        showAvatar: shouldShowAvatar(for: message, in: messages),
                                        otherUserAvatar: viewModel.conversation.otherParticipantProfileImagePath,
                                        onReply: { replyingTo = message },
                                        onReaction: { emoji in
                                            viewModel.addReaction(to: message, emoji: emoji)
                                        },
                                        onAvatarTap: {
                                            showingUserProfile = true
                                        },
                                        // ✅ NUEVO: Callback para cuando un mensaje es visto
                                        onMessageViewed: { messageId in
                                            // Actualizar el mensaje localmente
                                            if let index = viewModel.messages.firstIndex(where: { $0.id == messageId }) {
                                                viewModel.messages[index].isViewed = true
                                            }
                                        },
                                        // ✅ NUEVO: Callback para navegación al momento
                                        onMomentNavigation: { message in
                                            handleMomentNavigationFromChat(message: message)
                                        }
                                    )
                                    .id(message.id)
                                    .onLongPressGesture {
                                        showingMessageOptions = message
                                    }
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
                    .onReceive(viewModel.$messages) { _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id ?? "typing", anchor: .bottom)
                        }
                    }
                }
                
                // Reply Bar
                if let replyingTo = replyingTo {
                    GlassmorphicReplyBar(message: replyingTo) {
                        self.replyingTo = nil
                    }
                }
                
                // Input Bar
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
        .onAppear {
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
            viewModel.startListening()
            setupOnlineStatusObserver()
        }
        .onDisappear {
            print("🔍 ChatView disappeared!")
            print("🔍 Conversation ID: \(viewModel.conversation.id ?? "nil")")
            print("🔍 Messages sent this session: \(viewModel.messagesSentThisSession)")
            print("🔍 Current messages count: \(viewModel.messages.count)")
            
            AnalyticsService.shared.trackInteraction("chat_closed", details: [
                "conversationId": viewModel.conversation.id,
                "messagesSent": viewModel.messagesSentThisSession
            ])
            viewModel.stopListening()
            statusListener?.remove()
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
            Button(action: {
                showingUserProfile = true
            }) {
                HStack(spacing: 10) {
                    if let profileImagePath = viewModel.conversation.otherParticipantProfileImagePath,
                       let url = URL(string: profileImagePath) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(storyRingGradient, lineWidth: hasStory ? 2.5 : 0)
                            )
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.white.opacity(0.7))
                            .overlay(
                                Circle()
                                    .stroke(storyRingGradient, lineWidth: hasStory ? 2.5 : 0)
                            )
                    }
                    
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
            }
            .buttonStyle(PlainButtonStyle())
            
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
    
    // ✅ NUEVO: Gradiente para anillo de historias
    private var storyRingGradient: LinearGradient {
        if hasUnseenStory {
            // ✅ HISTORIA NO VISTA: Gradiente azul → morado → rosa
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if hasStory {
            // ✅ HISTORIA YA VISTA: Gris según el tema
            return LinearGradient(
                colors: colorScheme == .dark ?
                [Color.gray.opacity(0.5), Color.gray.opacity(0.7)] :
                [Color.gray.opacity(0.7), Color.gray.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // ✅ SIN HISTORIAS: Sin anillo (transparente)
            return LinearGradient(
                colors: [Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // ✅ NUEVO: Función para verificar historias del usuario
    private func checkUserStories() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let otherUserId = viewModel.conversation.otherParticipantId ?? ""
        guard !otherUserId.isEmpty else { return }
        
        Firestore.firestore().collection("users").document(otherUserId).collection("stories")
            .whereField("expirationDate", isGreaterThan: Date())
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    DispatchQueue.main.async {
                        hasStory = false
                        hasUnseenStory = false
                    }
                    return
                }
                
                let stories = documents.compactMap { doc -> Story? in
                    try? doc.data(as: Story.self)
                }
                
                guard !stories.isEmpty else {
                    DispatchQueue.main.async {
                        hasStory = false
                        hasUnseenStory = false
                    }
                    return
                }
                
                // Verificar si alguna historia no ha sido vista
                var hasUnseen = false
                let group = DispatchGroup()
                
                for story in stories {
                    group.enter()
                    Firestore.firestore().collection("users").document(story.authorId)
                        .collection("stories").document(story.id ?? "")
                        .collection("viewers").document(currentUserId)
                        .getDocument { viewerDoc, _ in
                            let wasViewed = viewerDoc?.exists == true
                            if !wasViewed {
                                hasUnseen = true
                            }
                            group.leave()
                        }
                }
                
                group.notify(queue: .main) {
                    hasStory = true
                    hasUnseenStory = hasUnseen
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
            print("❌ No conversation ID for camera capture")
            return
        }
        
        // ✅ AGREGAR ESTA LÍNEA DE DEBUG:
        print("📸 DEBUG: Camera capture - mediaType: \(mediaType), isEphemeral: \(isEphemeral)")
        
        if isEphemeral {
            // ✅ AGREGAR ESTE PRINT:
            print("📸 Sending VIEW-ONCE message")
            viewModel.sendViewOnceMessage(data: data, mediaType: mediaType)
            
            AnalyticsService.shared.trackInteraction("view_once_message_sent", details: [
                "mediaType": mediaType == .image ? "view_once_image" : "view_once_video", // ✅ CAMBIAR ESTO
                "conversationId": conversationId
            ])
        } else {
            // ✅ AGREGAR ESTE PRINT:
            print("📸 Sending NORMAL message")
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
    private func handleMomentNavigationFromChat(message: EnhancedMessage) {
        if let sharedMomentData = message.sharedMomentData,
           let momentId = sharedMomentData["momentId"] as? String {
            
            print("Navigate to moment: \(momentId)")
            
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
                            
                            print("Momento obtenido: \(momentId)")
                            self.selectedMoment = moment
                            self.showingMomentDetail = true
                            
                        } catch {
                            print("❌ Error decodificando momento: \(error.localizedDescription)")
                            self.showingMomentError = true
                        }
                    } else {
                        print("❌ Error obteniendo momento: \(error?.localizedDescription ?? "Unknown error")")
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
    let otherUserAvatar: String?
    let onReply: () -> Void
    let onReaction: (String) -> Void
    let onAvatarTap: () -> Void // ✅ NUEVO: Callback para tap en avatar
    let onMessageViewed: ((String) -> Void)?
    let onMomentNavigation: ((EnhancedMessage) -> Void)? // ✅ NUEVO: Callback para navegación al momento

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                if showAvatar {
                    // ✅ ACTUALIZADO: Avatar con navegación al perfil
                    Button(action: onAvatarTap) {
                        GlassmorphicAvatar(imageUrl: otherUserAvatar)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }
            
            if isCurrentUser { Spacer(minLength: 50) }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if let replyToId = message.replyTo {
                    GlassmorphicReplyPreview(messageId: replyToId)
                }
                
                GlassmorphicMessageBubble(
                    message: message,
                    isCurrentUser: isCurrentUser,
                    onMessageViewed: onMessageViewed,
                    onMomentNavigation: onMomentNavigation
                )
                
                if let reactions = message.reactions, !reactions.isEmpty {
                    GlassmorphicReactionsView(reactions: reactions, onTap: onReaction)
                }
                
                MessageTimestamp(message: message, isCurrentUser: isCurrentUser)
            }
            
            if !isCurrentUser { Spacer(minLength: 50) }
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
    let isCurrentUser: Bool
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
                            Text(content)
                                .font(.custom("Poppins-Regular", size: 15))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .foregroundColor(adaptiveColors.messageTextColor) // ✅ CAMBIO AQUÍ
                                .background(
                                    Group {
                                        if isCurrentUser {
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color(hex: "00A896").opacity(0.8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                                                )
                                        } else {
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(adaptiveColors.messageBubbleBackground) // ✅ CAMBIO AQUÍ
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                                                )
                                                .background(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(.ultraThinMaterial)
                                                )
                                        }
                                    }
                                )
                        }
                        
                    case .image:
                        GlassmorphicImageMessage(imageUrl: message.mediaUrl)
                            .onAppear {
                                AnalyticsService.shared.trackInteraction("image_message_viewed")
                            }
                        
                    case .audio:
                        GlassmorphicAudioMessage(
                            audioUrl: message.mediaUrl,
                            duration: message.duration ?? 0,
                            isCurrentUser: isCurrentUser
                        )
                        .onAppear {
                            AnalyticsService.shared.trackInteraction("audio_message_viewed")
                        }
                        
                    case .video:
                        GlassmorphicVideoMessage(videoUrl: message.mediaUrl, thumbnailUrl: message.thumbnailUrl)
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
                                        GlassmorphicImageMessage(imageUrl: mediaUrl)
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
                        SharedMomentMessageBubble(
                            message: message,
                            isCurrentUser: isCurrentUser,
                            onTap: {
                                // ✅ NUEVO: Usar el callback de navegación al momento
                                onMomentNavigation?(message)
                            }
                        )
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
                print("Error marking ephemeral as viewed: \(error.localizedDescription)")
            } else {
                print("Marked ephemeral message \(message.id) as viewed in conversation \(message.conversationId)")
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
                print("❌ Error marking view-once as viewed: \(error.localizedDescription)")
            } else {
                print("✅ View-once message marked as viewed")
                
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
    @State private var showFullScreen = false
    
    var body: some View {
        if let url = imageUrl, let imageURL = URL(string: url) {
            KFImage(imageURL)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 250, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
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
    @State private var showPlayer = false
    
    var body: some View {
        ZStack {
            if let thumbnailUrl = thumbnailUrl, let url = URL(string: thumbnailUrl) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 250, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 250, height: 200)
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
            // ✅ VIDEO PLAYER FUNCIONAL PARA MENSAJES NORMALES
            NormalVideoPlayerView(videoUrl: videoUrl)
        }
    }
}

struct NormalVideoPlayerView: View {
    let videoUrl: String?
    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let videoUrl = videoUrl, let url = URL(string: videoUrl) {
                VideoPlayer(player: AVPlayer(url: url))
                    .onAppear {
                        player = AVPlayer(url: url)
                        player?.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("chat.video.unavailable")
                        .font(.custom("Poppins-Regular", size: 18))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // ✅ Controls overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                            Text("chat.close")
                                .font(.custom("Poppins-Medium", size: 16))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // ✅ Track video view
            AnalyticsService.shared.trackInteraction("normal_video_opened", details: [
                "videoUrl": videoUrl ?? "unknown"
            ])
        }
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
                        .background(Color(hex: "00A896"))
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
    let imageUrl: String?
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(adaptiveColors.messageBubbleBackground)
            
            if let imageUrl = imageUrl, let url = URL(string: imageUrl) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(adaptiveColors.messageBubbleBackground)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
                            )
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(adaptiveColors.primary)
                            )
                    }
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
            }
        }
        .overlay(
            Circle()
                .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
        )
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
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color(hex: "00A896"))
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("chat.replying")
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(adaptiveColors.replyBarSecondaryText) // ✅ CAMBIO AQUÍ
                Text(message.content ?? "Mensaje")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(adaptiveColors.replyBarText) // ✅ CAMBIO AQUÍ
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(adaptiveColors.replyBarSecondaryText) // ✅ CAMBIO AQUÍ
            }
        }
        .padding()
        .background(adaptiveColors.replyBarBackground) // ✅ CAMBIO AQUÍ
        .glassmorphicChat()
        .padding(.horizontal, 16)
    }
}

struct GlassmorphicReplyPreview: View {
    let messageId: String
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(adaptiveColors.primary.opacity(0.5))
                .frame(width: 2)
            
                            Text("chat.replyingToMessage")
                .font(.custom("Poppins-Regular", size: 12))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.leading, 8)
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
                MessageStatusIcon(status: message.status)
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
            .foregroundColor(Color(hex: "00A896"))
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
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                KFImage(imageUrl)
                    .resizable()
                    .scaledToFit()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Enhanced InstagramChatViewModel with Better Audio Deletion
class InstagramChatViewModel: EnhancedChatViewModel {
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
    
    // ✅ NUEVA: Función para forzar actualización de groupedMessages
    func updateGroupedMessages() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        groupedMessages = grouped.sorted { $0.key < $1.key }
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
                print("❌ Error deleting message with cleanup: \(error.localizedDescription)")
            } else {
                print("✅ Message deleted successfully with cleanup")
            }
        }
        
        // Force UI update
        objectWillChange.send()
    }
    
    // MARK: - New Media Message Functions
    func sendImageMessage(_ imageData: Data) {
        trackMediaMessageSent(type: "image")
        
        chatService.sendMediaMessage(
            conversationId: conversation.id ?? "",
            senderId: currentUserId,
            type: .image,
            mediaData: imageData
        ) { result in
            switch result {
            case .success(let message):
                print("Image message sent successfully: \(message.id)")
            case .failure(let error):
                print("Error sending image: \(error.localizedDescription)")
            }
        }
    }
    
    func sendAudioMessage(_ audioData: Data, duration: TimeInterval) {
        trackMediaMessageSent(type: "audio")
        
        chatService.sendAudioMessage(
            conversationId: conversation.id ?? "",
            senderId: currentUserId,
            audioData: audioData,
            duration: duration
        ) { result in
            switch result {
            case .success(let message):
                print("Audio message sent successfully: \(message.id)")
            case .failure(let error):
                print("Error sending audio: \(error.localizedDescription)")
            }
        }
    }
    
    // ✅ NUEVA función para enviar mensajes view-once
    func sendViewOnceMessage(data: Data, mediaType: EnhancedCameraPickerView.MediaType) {
        guard let conversationId = conversation.id, !conversationId.isEmpty else {
            print("❌ No valid conversation ID for view-once message")
            error = "No se puede enviar el mensaje: ID de conversación no válido"
            return
        }
        
        print("📸 Sending view-once \(mediaType) message")
        
        let trackingType = mediaType == .image ? "view_once_image" : "view_once_video"
        AnalyticsService.shared.trackInteraction("view_once_message_sent", details: [
            "mediaType": trackingType,
            "conversationId": conversationId
        ])
        
        chatService.sendViewOnceMessage(
            conversationId: conversationId,
            senderId: currentUserId,
            mediaData: data,
            mediaType: mediaType
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    print("✅ View-once message sent successfully")
                case .failure(let error):
                    print("❌ Error sending view-once message: \(error.localizedDescription)")
                    self?.error = "Error al enviar mensaje: \(error.localizedDescription)"
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
                print("Video message sent successfully: \(message.id)")
            case .failure(let error):
                print("Error sending video: \(error.localizedDescription)")
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
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(adaptiveColors.recordingIndicator)
                
                Spacer()
                
                Text(formattedTime)
                    .font(.custom("Poppins-Medium", size: 16))
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
    
    // MARK: - Gradientes específicos para chat actualizados
    var chatBackground: [Color] {
        colorScheme == .dark ? [
            Color(hex: "1a1a2e"),
            Color(hex: "16213e"),
            Color(hex: "0f3460")
        ] : [
            Color(hex: "f8f9fa"),
            Color(hex: "e9ecef"),
            Color(hex: "dee2e6")
        ]
    }
    
    var messagingBackground: [Color] {
        colorScheme == .dark ? [
            Color(hex: "00A896").opacity(0.6),
            Color(hex: "02C39A").opacity(0.4),
            Color(hex: "F0F3BD").opacity(0.3)
        ] : [
            Color(hex: "E8F5E8"),
            Color(hex: "F0F8FF"),
            Color(hex: "FFF8DC")
        ]
    }
}
