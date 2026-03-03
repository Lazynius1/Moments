import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

// ✅ VISTA DE COMENTARIOS MODERNA MEJORADA CON ANIDACIÓN
struct ModernCommentsView: View {
    let moment: Moment
    @State private var comments: [Comment] = []
    @State private var newComment: String = ""
    @State private var editingCommentId: String? = nil
    @State private var editingCommentContent: String = ""
    @State private var replyToComment: Comment? = nil
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment? = nil
    @State private var expandedComments: Set<String> = []
    @State private var sortOption: CommentSortOption = .newest
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId: String = ""
    @State private var isLoading = true
    @State private var commentsListener: ListenerRegistration?
    @EnvironmentObject private var firestoreService: FirestoreService
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // ✅ NUEVO: Init personalizado para asegurar estado inicial correcto
    init(moment: Moment) {
        self.moment = moment
        // El estado se inicializa automáticamente por SwiftUI
    }
    
    // Computed properties para mejor organización
    private var rootComments: [Comment] {
        comments.filter { $0.parentCommentId == nil }
            .sorted { comment1, comment2 in
                switch sortOption {
                case .newest:
                    return comment1.timestamp > comment2.timestamp
                case .oldest:
                    return comment1.timestamp < comment2.timestamp
                case .mostLiked:
                    let likes1 = comment1.reactions["like"]?.count ?? 0
                    let likes2 = comment2.reactions["like"]?.count ?? 0
                    return likes1 > likes2
                }
            }
    }
    
    private var totalCommentsCount: Int {
        comments.count
    }
    
    var body: some View {
        ZStack {
            modernBackgroundView.ignoresSafeArea()
            
            // ✅ VERIFICAR SI LOS COMENTARIOS ESTÁN DESHABILITADOS
            if moment.disableComments {
                VStack(spacing: 20) {
                    modernHeaderView
                    
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text("modernComments.disabled.title")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("modernComments.disabled.description")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                }
            } else {
                // UI normal de comentarios (código existente)
                VStack(spacing: 0) {
                    modernHeaderView
                    
                    ZStack(alignment: .bottom) {
                        enhancedCommentsListView
                            .padding(.bottom, 80) // Espacio para el input flotante
                        
                        // Input flotante
                        VStack(spacing: 0) {
                            if let replyComment = replyToComment {
                                replyIndicatorView(replyComment)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            commentInputView
                        }
                    }
                }
            }
        }
        .onAppear {
            
            // ✅ NUEVO: Resetear estado antes de configurar listener
            DispatchQueue.main.async {
                self.isLoading = true
                self.comments = []
                self.commentsListener?.remove() // Remover listener anterior si existe
            }
            
            // ✅ NUEVO: Pequeño delay para asegurar que el estado se resetee
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupCommentsListener()
            }
        }
        .task {
            // ✅ NUEVO: Task adicional para asegurar inicialización
            await initializeCommentsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // ✅ NUEVO: Re-inicializar cuando la app vuelve a estar activa
            Task {
                await initializeCommentsView()
            }
        }
        .onChange(of: moment.id) { newMomentId in
            
            // ✅ NUEVO: Resetear estado cuando cambia el momento
            DispatchQueue.main.async {
                self.isLoading = true
                self.comments = []
                self.commentsListener?.remove()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupCommentsListener()
            }
        }
        .onDisappear {
            commentsListener?.remove()
            
            // ✅ NUEVO: Limpiar estado al desaparecer
            DispatchQueue.main.async {
                self.isLoading = false
                self.comments = []
                self.commentsListener = nil
            }
        }
        .alert(NSLocalizedString("modernComments.delete.title", comment: "Delete comment"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("modernComments.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("modernComments.delete.confirm", comment: "Delete"), role: .destructive) {
                if let comment = commentToDelete {
                    deleteComment(comment)
                }
            }
        } message: {
                            Text("modernComments.delete.message")
        }
        .fullScreenCover(isPresented: $showSpecificUserStories) {
            StoriesView(
                startWithUserId: Binding(
                    get: { selectedStoryUserId },
                    set: { selectedStoryUserId = $0 }
                )
            )
            .environmentObject(firestoreService)
            .ignoresSafeArea(.keyboard)
        }
    }
    
    // ✅ Fondo moderno unificado con el resto de la app
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                // Negro más intenso y elegante
                Color(hex: "050505")
                    .ignoresSafeArea()
                
                // Efecto de luz ambiental sutil (Blue/Purple glow)
                Circle()
                    .fill(Color.blue.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: -100, y: -200)
                
                Circle()
                    .fill(Color.purple.opacity(0.05))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: 100, y: 200)
                
            } else {
                // Fondo claro elegante
                Color(hex: "f8f9fa")
                    .ignoresSafeArea()
                
                // Efecto de luz ambiental sutil
                Circle()
                    .fill(Color.blue.opacity(0.03))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -100, y: -200)
            }
            
            // Material sutil encima
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
                .ignoresSafeArea()
        }
    }
    
    // ✅ Header moderno mejorado
    private var modernHeaderView: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("modernComments.title")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    // ✅ Indicador de carga
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                            .scaleEffect(0.7)
                    } else if !comments.isEmpty {
                        Text("\(totalCommentsCount)")
                            .font(.custom("Poppins-Bold", size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 4) {
                    LiveUsernameContent(userId: moment.authorId, fallbackUsername: moment.username) { username in
                        Text(String(format: NSLocalizedString("modernComments.postOf", comment: "Post of user"), username))
                    }
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
                    
                    VerifiedBadgeView(userId: moment.authorId, size: 10)
                }
            }
            
            Spacer()
            
            // Menú de ordenación
            Menu {
                Button(action: { sortOption = .newest }) {
                    Label(NSLocalizedString("modernComments.sort.newest", comment: "Latest"), systemImage: "arrow.up.circle")
                }
                Button(action: { sortOption = .oldest }) {
                    Label(NSLocalizedString("modernComments.sort.oldest", comment: "Oldest"), systemImage: "arrow.down.circle")
                }
                Button(action: { sortOption = .mostLiked }) {
                    Label(NSLocalizedString("modernComments.sort.mostLiked", comment: "Top"), systemImage: "heart")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // ✅ Lista de comentarios mejorada con nueva estructura anidada
    private var enhancedCommentsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // ✅ NUEVO: Indicador de carga cuando isLoading es true
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                            .scaleEffect(1.2)
                        
                        Text("modernComments.loading")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(rootComments) { comment in
                        EnhancedModernCommentRow(
                            comment: comment,
                            moment: moment,
                            onEdit: { comment in
                                editingCommentId = comment.id
                                editingCommentContent = comment.content
                            },
                            onDelete: { comment in
                                commentToDelete = comment
                                showDeleteAlert = true
                            },
                            onLike: { comment in
                                toggleLike(comment)
                            },
                            onReply: { comment in
                                replyToComment = comment
                            },
                            nestedComments: getNestedComments(for: comment.id ?? ""),
                            isExpanded: expandedComments.contains(comment.id ?? ""),
                            onToggleExpand: { commentId in
                                if expandedComments.contains(commentId) {
                                    expandedComments.remove(commentId)
                                } else {
                                    expandedComments.insert(commentId)
                                }
                            },
                            onAvatarTap: { userId, hasStory in
                                guard !userId.isEmpty else { return }
                                if hasStory {
                                    selectedStoryUserId = userId
                                    showSpecificUserStories = true
                                } else {
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("NavigateToProfile"),
                                        object: userId
                                    )
                                }
                            },
                            nestingLevel: 0 // ✅ Comenzar en nivel 0
                        )
                        .environmentObject(firestoreService)
                    }
                    
                    if comments.isEmpty {
                        ModernEmptyCommentsView()
                            .padding(.vertical, 60)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
    }
    
    // ✅ Indicador de respuesta mejorado
    private func replyIndicatorView(_ replyComment: Comment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: NSLocalizedString("modernComments.replyingTo", comment: "Replying to user"), replyComment.username))
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                
                Text(String(replyComment.content.prefix(50)) + (replyComment.content.count > 50 ? "..." : ""))
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: { replyToComment = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 2),
            alignment: .top
        )
    }
    
    // ✅ Input de comentario moderno (Diseño Floating Glass)
    private var commentInputView: some View {
        VStack(spacing: 0) {
            
            HStack(spacing: 12) {
                if editingCommentId != nil {
                    // Modo edición mejorado
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("modernComments.editing")
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                            }
                            
                            TextField("Editar comentario...", text: $editingCommentContent, axis: .vertical)
                                .font(.custom("Poppins-Regular", size: 15))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1...4)
                                .disabled(isLoading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                if let commentId = editingCommentId, !editingCommentContent.isEmpty {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    updateComment(commentId: commentId, content: editingCommentContent)
                                    editingCommentId = nil
                                    editingCommentContent = ""
                                }
                            }) {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.blue, Color.purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(Circle())
                                }
                            }
                            .disabled(editingCommentContent.isEmpty || isLoading)
                            
                            Button(action: {
                                editingCommentId = nil
                                editingCommentContent = ""
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .disabled(isLoading)
                        }
                    }
                } else {
                    // Modo comentario normal mejorado (Floating)
                    HStack(spacing: 8) {
                        // ✅ Avatar del usuario actual
                        if let currentUserId = Auth.auth().currentUser?.uid {
                            StoryRingAvatarView(
                                userId: currentUserId,
                                size: 36,
                                lineWidth: 2.2,
                                showBaseStroke: true,
                                baseStrokeColor: Color.white.opacity(0.2),
                                baseStrokeWidth: 1,
                                onTap: { hasStory in
                                    if hasStory {
                                        selectedStoryUserId = currentUserId
                                        showSpecificUserStories = true
                                    } else {
                                        NotificationCenter.default.post(
                                            name: NSNotification.Name("NavigateToProfile"),
                                            object: currentUserId
                                        )
                                    }
                                }
                            )
                        }
                        
                        TextField(replyToComment != nil ? "Responder a \(replyToComment?.username ?? "")..." : "Añade un comentario...", text: $newComment, axis: .vertical)
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .lineLimit(1...4)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 25)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .disabled(isLoading)
                        
                        Button(action: {
                            if !newComment.isEmpty {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                addComment(content: newComment, parentCommentId: replyToComment?.id)
                                newComment = ""
                                replyToComment = nil
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: newComment.isEmpty || isLoading ?
                                            [Color.gray.opacity(0.3), Color.gray.opacity(0.3)] :
                                            [Color.blue, Color.purple, Color.pink], // ✅ Degradado correcto
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .shadow(color: newComment.isEmpty ? .clear : Color.purple.opacity(0.4), radius: 5, x: 0, y: 3)
                                
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                        .offset(x: -1, y: 1) // Ajuste visual
                                }
                            }
                        }
                        .disabled(newComment.isEmpty || isLoading)
                        .scaleEffect(newComment.isEmpty || isLoading ? 0.95 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: newComment.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 8) // Espacio extra abajo
        }
    }
    
    // ✅ Función auxiliar para obtener comentarios anidados
    private func getNestedComments(for parentId: String) -> [Comment] {
        return comments
            .filter { $0.parentCommentId == parentId }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    private func setupCommentsListener() {
        guard let momentId = moment.id else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        
        // ✅ NUEVO: Asegurar que isLoading esté en true
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        // ✅ NUEVO: Timeout más corto para mejor UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isLoading {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
        
        // ✅ NUEVO: Remover listener anterior si existe
        commentsListener?.remove()
        
        commentsListener = firestoreService.db
            .collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self.comments = []
                        self.isLoading = false
                    }
                    return
                }
                
                
                let loadedComments = documents.compactMap { doc -> Comment? in
                    do {
                        var comment = try doc.data(as: Comment.self)
                        comment.id = doc.documentID
                        return comment
                    } catch {
                        return nil
                    }
                }
                
                DispatchQueue.main.async {
                    self.comments = loadedComments
                    self.isLoading = false
                }
            }
    }
    
    // ✅ FUNCIONES DE COMENTARIOS (manteniendo los nombres originales)
    private func fetchComments() {
        setupCommentsListener()
    }
    
    // ✅ NUEVO: Método de inicialización robusto
    private func initializeCommentsView() async {
        
        // Asegurar que el estado esté correcto
        await MainActor.run {
            self.isLoading = true
            self.comments = []
            self.commentsListener?.remove()
        }
        
        // Pequeño delay para asegurar que la vista esté lista
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 segundos
        
        await MainActor.run {
            self.setupCommentsListener()
        }
    }
    
    // MARK: - Tu función addComment corregida
    private func addComment(content: String, parentCommentId: String?) {
        guard let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        
        // ✅ OPTIMISTIC UPDATE: Add a temporary pending comment
        let currentUser = authService.currentUser
        let pendingComment = Comment(
            id: UUID().uuidString,
            authorId: userId,
            username: currentUser?.username ?? NSLocalizedString("common.me", comment: "Me"),
            content: content,
            timestamp: Date(),
            profileImagePath: currentUser?.profileImagePath,
            reactions: [:],
            parentCommentId: parentCommentId,
            isPending: true
        )
        
        withAnimation {
            self.comments.append(pendingComment)
        }
        
        AnalyticsService.shared.trackInteraction("comment_created", details: [
            "momentId": momentId,
            "isReply": parentCommentId != nil,
            "contentLength": content.count
        ])
        
        firestoreService.addComment(
            to: momentId,
            userId: moment.authorId,
            authorId: userId,
            content: content,
            parentCommentId: parentCommentId
        ) { result in
            switch result {
            case .success:
                Task { @MainActor in
                    AffinityTracker.shared.trackInteraction(type: .momentComment, with: self.moment.authorId)
                }
                // Si estamos online, el listener actualizará la lista.
                // Si estamos offline, el comentario se queda como "pending" hasta que se sincronice.
                if NetworkMonitor.shared.isConnected {
                    DispatchQueue.main.async {
                        self.fetchComments()
                    }
                }
                
                // 🔥 Moderación silenciosa en segundo plano
                self.moderateCommentInBackground(
                    content: content,
                    momentId: momentId,
                    userId: userId,
                    parentCommentId: parentCommentId
                )
                
            case .failure(_):
                // En caso de error, remover el optimista
                DispatchQueue.main.async {
                    self.comments.removeAll { $0.id == pendingComment.id }
                }
            }
        }
    }

    // MARK: - 🥷 Función de moderación silenciosa ACTUALIZADA
    private func moderateCommentInBackground(
        content: String,
        momentId: String,
        userId: String,
        parentCommentId: String?
    ) {
        // Moderar en background después de 2 segundos
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            
            CommentModerationService.shared.moderateAndHandle(
                content: content,
                onApproved: {
                    // ✅ Todo bien, silencio total
                    
                    // 📊 Log opcional para estadísticas (comentarios limpios)
                    CommentModerationService.shared.logModerationEvent(
                        userId: userId,
                        content: content,
                        action: "approved",
                        reason: "Contenido apropiado",
                        category: "clean",
                        momentId: momentId
                    )
                },
                onWarning: { reason, category in
                    // ⚠️ Marcar para revisión manual pero dejarlo publicado
                    
                    // 📊 Log para tu panel de admin - AHORA SÍ SE GUARDA EN FIRESTORE
                    CommentModerationService.shared.logModerationEvent(
                        userId: userId,
                        content: content,
                        action: "flagged_for_review",
                        reason: reason,
                        category: category,
                        momentId: momentId
                    )
                },
                onRejected: { reason, category in
                    // ❌ Borrar el comentario silenciosamente
                    
                    // Buscar y eliminar sin avisar al usuario
                    self.deleteCommentByContent(content: content, momentId: momentId, userId: userId)
                    
                    // 📊 Log para estadísticas - AHORA SÍ SE GUARDA EN FIRESTORE
                    CommentModerationService.shared.logModerationEvent(
                        userId: userId,
                        content: content,
                        action: "auto_deleted_silent",
                        reason: reason,
                        category: category,
                        momentId: momentId
                    )
                },
                onError: { error in
                    // 🔍 Error en moderación, marcar para revisión manual
                    
                    // 📊 Log del error - AHORA SÍ SE GUARDA EN FIRESTORE
                    CommentModerationService.shared.logModerationEvent(
                        userId: userId,
                        content: content,
                        action: "moderation_error",
                        reason: "API error: \(error.localizedDescription)",
                        category: "system_error",
                        momentId: momentId
                    )
                }
            )
        }
    }

    // MARK: - 🗑️ Función para eliminar comentario silenciosamente (FUERA de addComment)
    private func deleteCommentByContent(content: String, momentId: String, userId: String) {
        // Buscar el comentario que acabamos de crear por su contenido
        firestoreService.fetchComments(for: momentId, userId: moment.authorId) { result in
            switch result {
            case .success(let (fetchedComments, _)):
                // Buscar el comentario más reciente con este contenido y autor
                if let commentToDelete = fetchedComments
                    .filter({ $0.content == content && $0.authorId == userId })
                    .sorted(by: { $0.timestamp > $1.timestamp })
                    .first,
                   let commentId = commentToDelete.id {
                    
                    // Eliminar el comentario silenciosamente
                    self.firestoreService.deleteComment(
                        to: momentId,
                        commentId: commentId,
                        userId: self.moment.authorId,
                        authorId: userId
                    ) { result in
                        switch result {
                        case .success:
                            DispatchQueue.main.async {
                                self.fetchComments() // Refrescar lista silenciosamente
                            }
                        case .failure(_):
                            break
                        }
                    }
                }
                
            case .failure(_):
                break
            }
        }
    }
    
    private func updateComment(commentId: String, content: String) {
        guard let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        firestoreService.updateComment(momentId: momentId, userId: moment.authorId, commentId: commentId, content: content) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.fetchComments()
                }
            case .failure(_):
                break
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        guard let commentId = comment.id, let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        firestoreService.deleteComment(to: momentId, commentId: commentId, userId: moment.authorId, authorId: userId) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    // ✅ Optimistic update
                    withAnimation {
                        self.comments.removeAll { $0.id == commentId }
                        self.comments.removeAll { $0.parentCommentId == commentId }
                    }
                    self.fetchComments()
                }
            case .failure(_):
                break
            }
        }
    }
    
    private func toggleLike(_ comment: Comment) {
        guard let commentId = comment.id,
              let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        AnalyticsService.shared.trackInteraction("comment_liked", details: [
            "commentId": commentId,
            "momentId": momentId
        ])
        
        firestoreService.addCommentReaction(
            to: momentId,
            commentId: commentId,
            reaction: "like",
            userId: moment.authorId,  // ✅ CAMBIO: usar moment.authorId en lugar de currentUserId
            authorId: comment.authorId
        ) { error in
            if let error = error {
            } else {
                DispatchQueue.main.async {
                    self.fetchComments()
                }
            }
        }
    }
}

// ✅ ENUM para opciones de ordenación
enum CommentSortOption {
    case newest, oldest, mostLiked
}

// ✅ NUEVA FILA DE COMENTARIO CON ANIDACIÓN COMO 
struct EnhancedModernCommentRow: View {
    let comment: Comment
    let moment: Moment
    let onEdit: (Comment) -> Void
    let onDelete: (Comment) -> Void
    let onLike: (Comment) -> Void
    let onReply: (Comment) -> Void
    let nestedComments: [Comment]
    let isExpanded: Bool
    let onToggleExpand: (String) -> Void
    let onAvatarTap: (String, Bool) -> Void
    let nestingLevel: Int // ✅ NUEVO: Nivel de anidación
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme
    @State private var showFullContent = false
    
    private var isLongComment: Bool {
        comment.content.count > 100
    }
    
    private var displayContent: String {
        if isLongComment && !showFullContent {
            return String(comment.content.prefix(100)) + "..."
        }
        return comment.content
    }
    
    // ✅ Máximo nivel de anidación (evita anidación infinita)
    private var maxNestingLevel: Int { 4 }
    
    // ✅ Indentación visual basada en nivel
    private var indentationWidth: CGFloat {
        CGFloat(min(nestingLevel, maxNestingLevel)) * 16
    }
    
    // ✅ Línea vertical para mostrar jerarquía
    private var shouldShowConnectorLine: Bool {
        nestingLevel > 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // ✅ Línea de conexión visual (Gradient)
                if shouldShowConnectorLine {
                    VStack {
                        // Gradiente que se desvanece
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 2)
                        .padding(.leading, indentationWidth - 10)
                        
                        // Pequeño punto en la conexión (opcional, para detalle premium)
                        if nestingLevel > 0 {
                            Circle()
                                .fill(Color.purple.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.leading, indentationWidth - 11)
                                .offset(y: -4)
                        }
                    }
                    .frame(width: indentationWidth)
                }
                
                // ✅ Contenido principal del comentario
                commentContent
                    .padding(.leading, shouldShowConnectorLine ? 0 : indentationWidth)
            }
            
            // ✅ Comentarios anidados con límite de profundidad
            if !nestedComments.isEmpty && isExpanded && nestingLevel < maxNestingLevel {
                LazyVStack(spacing: 8) {
                    ForEach(nestedComments) { nestedComment in
                        EnhancedModernCommentRow(
                            comment: nestedComment,
                            moment: moment,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onLike: onLike,
                            onReply: onReply,
                            nestedComments: [], // ✅ Evitar anidación infinita
                            isExpanded: false,
                            onToggleExpand: onToggleExpand,
                            onAvatarTap: onAvatarTap,
                            nestingLevel: nestingLevel + 1 // ✅ Incrementar nivel
                        )
                        .environmentObject(firestoreService)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.top, 8)
            }
            
            // ✅ Mostrar indicador si hay más niveles
            if nestingLevel >= maxNestingLevel && !nestedComments.isEmpty {
                Button(action: {
                    // Navegar a vista detallada del hilo
                }) {
                    HStack {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(String(format: NSLocalizedString("modernComments.viewMoreReplies", comment: "View more replies"), nestedComments.count))
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(Capsule())
                }
                .padding(.leading, indentationWidth + 50)
                .padding(.top, 8)
            }
        }
    }
    

    
    // ✅ Contenido principal del comentario CON SWIPE
    private var commentContent: some View {
        ZStack(alignment: .trailing) {
            // Fondo de acciones de deslizar
            if shouldShowSwipeActions {
                HStack(spacing: 0) {
                    Spacer()
                    
                    if canEdit {
                        Button(action: {
                            withAnimation { offset = 0 }
                            onEdit(comment)
                        }) {
                            VStack {
                                Image(systemName: "pencil")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 60, height: nestingLevel == 0 ? 80 : 60) // Ajustar altura
                            .background(Color.blue)
                        }
                    }
                    
                    if canDelete {
                        Button(action: {
                            withAnimation { offset = 0 }
                            onDelete(comment)
                        }) {
                            VStack {
                                Image(systemName: "trash")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 60, height: nestingLevel == 0 ? 80 : 60) // Ajustar altura
                            .background(Color.red)
                            .clipShape(
                                .rect(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: nestingLevel == 0 ? 16 : 12,
                                    topTrailingRadius: nestingLevel == 0 ? 16 : 12
                                )
                            )
                        }
                    }
                }
                .padding(.vertical, nestingLevel == 0 ? 12 : 8) // Coincidir con padding del row
            }
            
            // Contenido visible
            HStack(alignment: .top, spacing: 12) {
                // ✅ Avatar con borde gradiente
                StoryRingAvatarView(
                    userId: comment.authorId,
                    size: avatarSize,
                    lineWidth: nestingLevel == 0 ? 2.3 : 2.0,
                    onTap: { hasStory in
                        onAvatarTap(comment.authorId, hasStory)
                    }
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: nestingLevel == 0 ?
                                [Color.blue.opacity(0.6), Color.purple.opacity(0.6)] :
                                [Color.white.opacity(0.3), Color.white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: nestingLevel == 0 ? 1.5 : 1
                        )
                )
                .shadow(
                    color: nestingLevel == 0 ? Color.purple.opacity(0.2) : .clear,
                    radius: 4,
                    x: 0,
                    y: 2
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    // ✅ Header del comentario
                    commentHeader
                    
                    // ✅ Contenido con @menciones destacadas
                    contentWithMentions
                    
                    // ✅ Botones de acción
                    actionButtons
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, nestingLevel == 0 ? 12 : 8)
            .background(commentBackground)
            .clipShape(RoundedRectangle(cornerRadius: nestingLevel == 0 ? 16 : 12))
            .overlay(
                RoundedRectangle(cornerRadius: nestingLevel == 0 ? 16 : 12)
                    .stroke(commentBorder, lineWidth: nestingLevel == 0 ? 1 : 0.5)
            )
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if shouldShowSwipeActions {
                            // Solo permitir deslizar a la izquierda
                            if gesture.translation.width < 0 {
                                offset = gesture.translation.width
                            }
                        }
                    }
                    .onEnded { _ in
                        if shouldShowSwipeActions {
                            if offset < -50 {
                                withAnimation {
                                    offset = -actionWidth
                                }
                            } else {
                                withAnimation {
                                    offset = 0
                                }
                            }
                        }
                    }
            )
        }
        // Animación de entrada "Pop"
        .transition(.scale.combined(with: .opacity))
    }
    
    // ✅ Propiedades para SWIPE
    @State private var offset: CGFloat = 0
    
    private var canEdit: Bool {
        comment.authorId == Auth.auth().currentUser?.uid
    }
    
    private var canDelete: Bool {
        comment.authorId == Auth.auth().currentUser?.uid || moment.authorId == Auth.auth().currentUser?.uid
    }
    
    private var shouldShowSwipeActions: Bool {
        canEdit || canDelete
    }
    
    private var actionWidth: CGFloat {
        var width: CGFloat = 0
        if canEdit { width += 60 }
        if canDelete { width += 60 }
        return width
    }
    
    // ✅ Tamaño de avatar variable
    private var avatarSize: CGFloat {
        switch nestingLevel {
        case 0: return 36
        case 1: return 32
        case 2: return 28
        default: return 24
        }
    }
    
    private var commentBackground: some View {
        Group {
            if nestingLevel == 0 {
                // Background sólido con efecto glass
                Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05)
                    .background(.ultraThinMaterial)
            } else {
                Color.clear
            }
        }
    }
    
    // ✅ Borde del comentario según nivel
    private var commentBorder: LinearGradient {
        LinearGradient(
            colors: nestingLevel == 0 ?
                [Color.white.opacity(0.15), Color.white.opacity(0.05)] :
                [Color.clear, Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // ✅ Header del comentario mejorado
    private var commentHeader: some View {
        HStack(spacing: 8) {
            // ✅ Username con @ si es respuesta
            HStack(spacing: 4) {
                if nestingLevel > 0 {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 10))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                HStack(spacing: 3) {
                    Text(comment.username)
                        .font(.custom("Poppins-SemiBold", size: nestingLevel == 0 ? 14 : 13))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: comment.authorId, size: nestingLevel == 0 ? 12 : 10)
                }
            }
            
            // ✅ Indicador de editado
            if comment.isEditedFlag {
                Text("modernComments.edited")
                    .font(.custom("Poppins-Regular", size: 10))
                    .foregroundColor(.gray.opacity(0.6))
                    .italic()
            }
            
            Text("•")
                .font(.custom("Poppins-Regular", size: 12))
                .foregroundColor(.gray.opacity(0.6))
            
            // ✅ Timestamp relativo
            HStack(spacing: 4) {
                Text(timeAgo(from: comment.timestamp))
                    .font(.custom("Poppins-Regular", size: nestingLevel == 0 ? 12 : 11))
                    .foregroundColor(.gray.opacity(0.6))
                
                if comment.isPending == true {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            
            Spacer()
            

        }
    }
    
    // ✅ Contenido con menciones destacadas
    private var contentWithMentions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayContent)
                .font(.custom("Poppins-Regular", size: nestingLevel == 0 ? 14 : 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                .multilineTextAlignment(.leading)
                .overlay(
                    // ✅ Destacar @menciones
                    mentionOverlay
                )
            
            if isLongComment {
                Button(action: { showFullContent.toggle() }) {
                    Text(showFullContent ? "Ver menos" : "Ver más")
                        .font(.custom("Poppins-Medium", size: 11))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
    
    // ✅ Overlay para destacar menciones
    private var mentionOverlay: some View {
        Text(displayContent)
            .font(.custom("Poppins-Regular", size: nestingLevel == 0 ? 14 : 13))
            .foregroundColor(.clear)
            .overlay(
                Text(highlightMentions(in: displayContent))
                    .font(.custom("Poppins-SemiBold", size: nestingLevel == 0 ? 14 : 13))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            )
            .allowsHitTesting(false)
    }
    
    // ✅ Función para destacar menciones
    private func highlightMentions(in text: String) -> String {
        let pattern = #"@(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        var result = ""
        var lastEndIndex = text.startIndex
        
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            
            // Agregar texto antes de la mención (invisible)
            let beforeMatch = String(text[lastEndIndex..<matchRange.lowerBound])
            result += String(repeating: " ", count: beforeMatch.count)
            
            // Agregar la mención (visible)
            result += String(text[matchRange])
            
            lastEndIndex = matchRange.upperBound
        }
        
        // Texto restante (invisible)
        let remaining = String(text[lastEndIndex...])
        result += String(repeating: " ", count: remaining.count)
        
        return result
    }
    

    
    // ✅ Botones de acción mejorados
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // ✅ Like button
            CommentActionButton(
                icon: comment.reactions["like"]?.contains(Auth.auth().currentUser?.uid ?? "") ?? false ? "heart.fill" : "heart",
                text: "",
                count: (comment.reactions["like"]?.count ?? 0) > 0 ? comment.reactions["like"]?.count : nil,
                isActive: comment.reactions["like"]?.contains(Auth.auth().currentUser?.uid ?? "") ?? false,
                activeColor: .red
            ) {
                onLike(comment)
            }
            
            // ✅ Reply button (solo para niveles bajos)
            if nestingLevel < maxNestingLevel {
                CommentActionButton(
                    icon: "arrowshape.turn.up.left",
                    text: "Responder",
                    count: nil,
                    isActive: false,
                    activeColor: colorScheme == .dark ? .white : .black
                ) {
                    onReply(comment)
                }
            }
            
            // ✅ Botón de expandir respuestas (solo para comentarios principales)
            if !nestedComments.isEmpty && nestingLevel == 0 {
                CommentActionButton(
                    icon: isExpanded ? "chevron.up" : "chevron.down",
                    text: "\(nestedComments.count) respuesta\(nestedComments.count == 1 ? "" : "s")",
                    count: nil,
                    isActive: isExpanded,
                    activeColor: colorScheme == .dark ? .white : .black
                ) {
                    if let commentId = comment.id {
                        onToggleExpand(commentId)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}


// ✅ ESTADO VACÍO DE COMENTARIOS MEJORADO
struct ModernEmptyCommentsView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "bubble.left")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    // Animación sutil de respiración
                }
            }
            
            VStack(spacing: 8) {
                Text("modernComments.empty.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("modernComments.empty.description")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Text("💭")
                    .font(.system(size: 24))
                    .opacity(0.6)
                    .scaleEffect(1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            // Animación sutil del emoji
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// ✅ VISTA AUXILIAR PARA BOTONES DE ACCIÓN MEJORADOS
struct CommentActionButton: View {
    let icon: String
    let text: String
    let count: Int?
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? activeColor : (colorScheme == .dark ? .white : .black))
                
                if !text.isEmpty {
                    Text(text)
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(isActive ? activeColor : (colorScheme == .dark ? .white : .black))
                }
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isActive {
                        activeColor.opacity(0.1)
                    } else {
                        (colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                }
            )
            .clipShape(Capsule())
        }
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }
}


// ✅ EXTENSIÓN PARA DETECTAR ENLACES Y MENCIONES
extension String {
    func detectURLs() -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return URL(string: String(self[range]))
        }
    }
    
    func containsMention(_ username: String) -> Bool {
        let pattern = "@\(username.lowercased())"
        return self.lowercased().contains(pattern)
    }
}
