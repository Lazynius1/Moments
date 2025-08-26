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
    @State private var isLoading = true
    @State private var commentsListener: ListenerRegistration?
    @EnvironmentObject private var firestoreService: FirestoreService
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
                    enhancedCommentsListView
                    if let replyComment = replyToComment {
                        replyIndicatorView(replyComment)
                    }
                    commentInputView
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
    }
    
    // ✅ Fondo moderno unificado con el resto de la app
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                // Negro más intenso y elegante - igual que FeedView
                Color(hex: "0A0A0A")
                    .ignoresSafeArea()
                
                // Overlay sutil para profundidad
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.1),
                        Color.clear,
                        Color.black.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                // Fondo claro elegante - igual que FeedView
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white,
                        Color(hex: "f8f9fa"),
                        Color(hex: "e9ecef"),
                        Color.white
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Overlay sutil para profundidad
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.3),
                        Color.clear,
                        Color(hex: "f8f9fa").opacity(0.2)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
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
                                            colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.1),
                                            Color(hex: "00A896").opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white : Color.black,
                                    Color(hex: "00A896").opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("modernComments.title")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    // ✅ NUEVO: Indicador de carga en el header
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
                            .scaleEffect(0.8)
                    } else if !comments.isEmpty {
                        Text("(\(totalCommentsCount))")
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(Color(hex: "00A896"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(hex: "00A896").opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 3) {
                    Text(String(format: NSLocalizedString("modernComments.postOf", comment: "Post of user"), moment.username))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .gray.opacity(0.8) : .gray.opacity(0.6))
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: moment.authorId, size: 10)
                }
            }
            
            Spacer()
            
            // Menú de ordenación
            Menu {
                Button(action: { sortOption = .newest }) {
                    Label(NSLocalizedString("modernComments.sort.newest", comment: "Most recent"), systemImage: "clock.arrow.circlepath")
                }
                Button(action: { sortOption = .oldest }) {
                    Label(NSLocalizedString("modernComments.sort.oldest", comment: "Oldest"), systemImage: "clock")
                }
                Button(action: { sortOption = .mostLiked }) {
                    Label(NSLocalizedString("modernComments.sort.mostLiked", comment: "Most liked"), systemImage: "heart.fill")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                                            Color(hex: "00A896").opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .gray.opacity(0.7) : .gray.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.1 : 0.05)
        )
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color(hex: "00A896").opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 0.5),
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
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
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
                .foregroundColor(Color(hex: "00A896"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: NSLocalizedString("modernComments.replyingTo", comment: "Replying to user"), replyComment.username))
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(.white.opacity(0.8))
                
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
                .fill(Color(hex: "00A896").opacity(0.3))
                .frame(height: 2),
            alignment: .top
        )
    }
    
    // ✅ Input de comentario moderno (mejorado)
    private var commentInputView: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color(hex: "00A896").opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 0.5)
            
            HStack(spacing: 12) {
                if editingCommentId != nil {
                    // Modo edición mejorado
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "00A896"))
                                
                                Text("modernComments.editing")
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(Color(hex: "00A896"))
                                
                                Spacer()
                            }
                            
                            TextField("Editar comentario...", text: $editingCommentContent, axis: .vertical)
                                .font(.custom("Poppins-Regular", size: 15))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1...4)
                                .disabled(isLoading) // ✅ NUEVO: Deshabilitar mientras carga
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                if let commentId = editingCommentId, !editingCommentContent.isEmpty {
                                    updateComment(commentId: commentId, content: editingCommentContent)
                                    editingCommentId = nil
                                    editingCommentContent = ""
                                }
                            }) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.gray.opacity(0.5)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 36, height: 36)
                                        .background(
                                            LinearGradient(
                                                colors: editingCommentContent.isEmpty ?
                                                [Color.gray.opacity(0.5)] :
                                                [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(Circle())
                                }
                            }
                            .disabled(editingCommentContent.isEmpty || isLoading) // ✅ NUEVO: Deshabilitar mientras carga
                            
                            Button(action: {
                                editingCommentId = nil
                                editingCommentContent = ""
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.6))
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .disabled(isLoading) // ✅ NUEVO: Deshabilitar mientras carga
                        }
                    }
                } else {
                    // Modo comentario normal mejorado
                    HStack(spacing: 12) {
                        TextField(replyToComment != nil ? "Responder..." : "Añade un comentario...", text: $newComment, axis: .vertical)
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .lineLimit(1...4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .disabled(isLoading) // ✅ NUEVO: Deshabilitar mientras carga
                        
                        Button(action: {
                            if !newComment.isEmpty {
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
                                            [Color.gray.opacity(0.5)] :
                                            [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .rotationEffect(.degrees(newComment.isEmpty ? 0 : 45))
                                }
                            }
                        }
                        .disabled(newComment.isEmpty || isLoading) // ✅ NUEVO: Deshabilitar mientras carga
                        .scaleEffect(newComment.isEmpty || isLoading ? 0.9 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: newComment.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
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
                DispatchQueue.main.async {
                    self.fetchComments()
                }
                
                // 🔥 Moderación silenciosa en segundo plano
                self.moderateCommentInBackground(
                    content: content,
                    momentId: momentId,
                    userId: userId,
                    parentCommentId: parentCommentId
                )
                
            case .failure(_):
                break
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
                // ✅ Línea de conexión visual (como X/Twitter)
                if shouldShowConnectorLine {
                    VStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 2)
                            .padding(.leading, indentationWidth - 10)
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
                            .foregroundColor(Color(hex: "00A896"))
                        
                        Text(String(format: NSLocalizedString("modernComments.viewMoreReplies", comment: "View more replies"), nestedComments.count))
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(Color(hex: "00A896"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "00A896").opacity(0.1))
                    .clipShape(Capsule())
                }
                .padding(.leading, indentationWidth + 50)
                .padding(.top, 8)
            }
        }
    }
    
    // ✅ Contenido principal del comentario
    private var commentContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // ✅ Avatar con tamaño variable según nivel
            AsyncProfileImageView(userId: comment.authorId)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: nestingLevel == 0 ? 1.5 : 1
                        )
                )
                .shadow(
                    color: Color(hex: "00A896").opacity(nestingLevel == 0 ? 0.3 : 0.1),
                    radius: nestingLevel == 0 ? 4 : 2,
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
        .shadow(
            color: Color.black.opacity(nestingLevel == 0 ? 0.3 : 0.1),
            radius: nestingLevel == 0 ? 8 : 4,
            x: 0,
            y: nestingLevel == 0 ? 4 : 2
        )
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
                // ✅ Opción 1: Background sólido con efecto similar
                Color.black.opacity(0.3)
                    .overlay(Color.white.opacity(0.1))
                    .background(.ultraThinMaterial)
            } else {
                Color.black.opacity(0.1)
                    .overlay(Color.white.opacity(0.05))
            }
        }
    }
    
    // ✅ Borde del comentario según nivel
    private var commentBorder: LinearGradient {
        LinearGradient(
            colors: nestingLevel == 0 ?
                [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)] :
                [Color.white.opacity(0.1), Color.gray.opacity(0.2)],
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
                        .foregroundColor(Color(hex: "00A896"))
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
            Text(timeAgo(from: comment.timestamp))
                .font(.custom("Poppins-Regular", size: nestingLevel == 0 ? 12 : 11))
                .foregroundColor(.gray.opacity(0.6))
            
            Spacer()
            
            // ✅ Menú de opciones (solo para comentarios principales o propios)
            if (comment.authorId == Auth.auth().currentUser?.uid || moment.authorId == Auth.auth().currentUser?.uid) && nestingLevel <= 1 {
                commentOptionsMenu
            }
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
                        .foregroundColor(Color(hex: "00A896"))
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
                    .foregroundColor(Color(hex: "00A896"))
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
    
    // ✅ Menú de opciones del comentario
    private var commentOptionsMenu: some View {
        Menu {
            if comment.authorId == Auth.auth().currentUser?.uid {
                Button(action: { onEdit(comment) }) {
                    Label("Editar", systemImage: "pencil")
                }
            }
            Button(action: { onDelete(comment) }) {
                Label("Eliminar", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundColor(.gray.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
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
                    activeColor: Color(hex: "00A896")
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
                    activeColor: Color(hex: "00A896")
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
                                    colors: [Color(hex: "00A896").opacity(0.4), Color.white.opacity(0.2)],
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
                            colors: [Color(hex: "00A896"), Color.white.opacity(0.7)],
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
                    .foregroundColor(isActive ? activeColor : .gray.opacity(0.6))
                
                if !text.isEmpty {
                    Text(text)
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(isActive ? activeColor : .gray.opacity(0.6))
                }
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isActive {
                        activeColor.opacity(0.1)
                    } else {
                        Color.black.opacity(0.3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
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
