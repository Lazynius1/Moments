import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

// ✅ VISTA DE COMENTARIOS MODERNA MEJORADA CON ANIDACIÓN
struct ModernCommentsView: View {
    private struct CommentFilterResult {
        let visible: [Comment]
        let mutedWordMaskedIds: Set<String>
    }

    private struct MentionDraftToken {
        let query: String
        let fullRange: Range<String.Index>
    }

    private enum MentionInputTarget {
        case newComment
        case editing
    }

    let moment: Moment
    @State private var comments: [Comment] = []
    @State private var mutedUserIds: Set<String> = []
    @State private var mutedWordsNormalized: [String] = []
    @State private var temporarilyRevealedCommentIds: Set<String> = []
    @State private var newComment: String = ""
    @State private var newCommentMentions: [CommentMentionEntity] = []
    @State private var activeNewCommentMention: MentionDraftToken?
    @State private var editingCommentId: String? = nil
    @State private var editingCommentContent: String = ""
    @State private var editingCommentMentions: [CommentMentionEntity] = []
    @State private var activeEditingCommentMention: MentionDraftToken?
    @State private var replyToComment: Comment? = nil
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment? = nil
    /// nestingLevel 0…max; no se puede responder desde el nivel máximo.
    private let maxCommentNestingLevel = 4
    @State private var expandedComments: Set<String> = []
    @State private var sortOption: CommentSortOption = .newest
    @State private var storyRoute: StoryUserPresentationRoute?
    @State private var isLoading = true
    @State private var commentsListener: ListenerRegistration?
    @State private var muteSettingsListener: ListenerRegistration?
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
    private var commentFilterResult: CommentFilterResult {
        applyCommentMuteFilters(to: comments)
    }

    private var filteredComments: [Comment] {
        commentFilterResult.visible
    }

    private var mutedWordMaskedCommentIds: Set<String> {
        commentFilterResult.mutedWordMaskedIds
    }

    private var rootComments: [Comment] {
        filteredComments.filter { $0.parentCommentId == nil }
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
        filteredComments.count
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
                        AttachmentIconView(icon: .comments, preset: .emptyStateHero, tintColor: .gray.opacity(0.6))
                        
                        Text("modernComments.disabled.title")
                            .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        
                        Text("modernComments.disabled.description")
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundStyle(.gray)
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
                self.setupMuteSettingsListener()
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
        .onChange(of: moment.id) { _, newMomentId in
            
            // ✅ NUEVO: Resetear estado cuando cambia el momento
            DispatchQueue.main.async {
                self.isLoading = true
                self.comments = []
                self.commentsListener?.remove()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupMuteSettingsListener()
                self.setupCommentsListener()
            }
        }
        .onDisappear {
            commentsListener?.remove()
            muteSettingsListener?.remove()
            
            // ✅ NUEVO: Limpiar estado al desaparecer
            DispatchQueue.main.async {
                self.isLoading = false
                self.comments = []
                self.commentsListener = nil
                self.muteSettingsListener = nil
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
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.userId))
                .environmentObject(firestoreService)
                .ignoresSafeArea(.keyboard)
        }
    }
    
    // ✅ Fondo moderno unificado con el resto de la app
    private var modernBackgroundView: some View {
        Color.clear
            .ignoresSafeArea()
    }
    
    // ✅ Header moderno mejorado
    private var modernHeaderView: some View {
        ZStack {
            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 8) {
                    Text("modernComments.title")
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                            .scaleEffect(0.7)
                    } else if !filteredComments.isEmpty {
                        Text("\(totalCommentsCount)")
                            .font(.system(size: legacyPoppinsSize(11), weight: .bold))
                            .foregroundStyle(.white)
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
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(.gray)

                    VerifiedBadgeView(userId: moment.authorId, size: 10)
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()

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
                        Color.clear
                            .frame(width: 32, height: 32)
                            .momentsChromeGlass(in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 0.8)
                            )

                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // ✅ Lista de comentarios mejorada con nueva estructura anidada
    private var enhancedCommentsListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // ✅ Skeleton adaptado a la fila real de comentario mientras carga
                if isLoading {
                    CommentRowSkeletonList(rows: 4)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                } else {
                    ForEach(rootComments) { comment in
                        EnhancedModernCommentRow(
                            comment: comment,
                            moment: moment,
                            onEdit: { comment in
                                editingCommentId = comment.id
                                editingCommentContent = comment.content
                                editingCommentMentions = comment.mentions
                                activeEditingCommentMention = detectMentionToken(in: comment.content)
                            },
                            onDelete: { comment in
                                commentToDelete = comment
                                showDeleteAlert = true
                            },
                            onLike: { comment in
                                toggleLike(comment)
                            },
                            onReply: { comment in
                                guard canReply(to: comment) else { return }
                                replyToComment = comment
                            },
                            nestedCommentsProvider: { parentId in
                                getNestedComments(for: parentId)
                            },
                            isCommentExpanded: { expandedComments.contains($0) },
                            onToggleExpand: { commentId in
                                if expandedComments.contains(commentId) {
                                    expandedComments.remove(commentId)
                                } else {
                                    expandedComments.insert(commentId)
                                }
                            },
                            onAvatarTap: { userId, hasStory in
                                guard !userId.isEmpty else { return }
                                if userId == Auth.auth().currentUser?.uid {
                                    LegacyNavigationBridge.ownProfileTab()
                                    return
                                }
                                if hasStory {
                                    storyRoute = StoryUserPresentationRoute(userId: userId)
                                } else {
                                    LegacyNavigationBridge.profile(userId: userId)
                                }
                            },
                            onMentionTap: { identifier in
                                guard !identifier.isEmpty else { return }
                                if identifier.hasPrefix("@") {
                                    let username = String(identifier.dropFirst())
                                    firestoreService.fetchUserByUsername(username) { result in
                                        switch result {
                                        case .success(let user):
                                            DispatchQueue.main.async {
                                                if user.id == Auth.auth().currentUser?.uid {
                                                    LegacyNavigationBridge.ownProfileTab()
                                                } else {
                                                    LegacyNavigationBridge.profile(userId: user.id)
                                                }
                                            }
                                        case .failure(let error):
                                            print("Error resolving username from comment mention: \(error.localizedDescription)")
                                        }
                                    }
                                } else {
                                    if identifier == Auth.auth().currentUser?.uid {
                                        LegacyNavigationBridge.ownProfileTab()
                                    } else {
                                        LegacyNavigationBridge.profile(userId: identifier)
                                    }
                                }
                            },
                            maskedCommentIds: mutedWordMaskedCommentIds,
                            temporarilyRevealedCommentIds: temporarilyRevealedCommentIds,
                            onRevealTemporarily: revealMutedCommentTemporarily,
                            nestingLevel: 0,
                            maxNestingLevel: maxCommentNestingLevel
                        )
                        .environmentObject(firestoreService)
                    }
                    
                    if rootComments.isEmpty {
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
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: NSLocalizedString("modernComments.replyingTo", comment: "Replying to user"), replyComment.username))
                    .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                
                Text(String(replyComment.content.prefix(50)) + (replyComment.content.count > 50 ? "..." : ""))
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: { replyToComment = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.gray.opacity(0.6))
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
            mentionSearchOverlay
            
            HStack(spacing: 12) {
                if editingCommentId != nil {
                    // Modo edición mejorado
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                
                                Text("modernComments.editing")
                                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                            }
                            
                            TextField(NSLocalizedString("comments.edit.placeholder", comment: "Edit comment placeholder"), text: $editingCommentContent, axis: .vertical)
                                .font(.system(size: legacyPoppinsSize(15)))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .textFieldStyle(.plain)
                                .lineLimit(1...4)
                                .lineSpacing(0)
                                .disabled(isLoading)
                                .onChange(of: editingCommentContent) { _, newValue in
                                    activeEditingCommentMention = detectMentionToken(in: newValue)
                                    editingCommentMentions = sanitizedMentionEntities(editingCommentMentions, in: newValue)
                                }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                if let commentId = editingCommentId, !editingCommentContent.isEmpty {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    let mentions = sanitizedMentionEntities(editingCommentMentions, in: editingCommentContent)
                                    updateComment(commentId: commentId, content: editingCommentContent, mentions: mentions)
                                    editingCommentId = nil
                                    editingCommentContent = ""
                                    editingCommentMentions = []
                                    activeEditingCommentMention = nil
                                }
                            }) {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
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
                                editingCommentMentions = []
                                activeEditingCommentMention = nil
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.gray)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .disabled(isLoading)
                        }
                    }
                } else {
                    // Modo comentario normal mejorado (Floating)
                    HStack(alignment: .bottom, spacing: 8) {
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
                                        storyRoute = StoryUserPresentationRoute(userId: currentUserId)
                                    } else {
                                        LegacyNavigationBridge.profile(userId: currentUserId)
                                    }
                                }
                            )
                        }
                        
                        TextField(replyToComment != nil ? "Responder a \(replyToComment?.username ?? "")..." : "Añade un comentario...", text: $newComment, axis: .vertical)
                            .font(.system(size: legacyPoppinsSize(15)))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .lineSpacing(0)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            // ≡ ChatInputViews: misma “gordura” en una línea.
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .disabled(isLoading)
                            .onChange(of: newComment) { _, newValue in
                                activeNewCommentMention = detectMentionToken(in: newValue)
                                newCommentMentions = sanitizedMentionEntities(newCommentMentions, in: newValue)
                            }
                        
                        Button(action: {
                            if !newComment.isEmpty {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                let mentions = sanitizedMentionEntities(newCommentMentions, in: newComment)
                                addComment(content: newComment, parentCommentId: replyToComment?.id, mentions: mentions)
                                newComment = ""
                                newCommentMentions = []
                                activeNewCommentMention = nil
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
                                        .foregroundStyle(.white)
                                        .offset(x: -1, y: 1) // Ajuste visual
                                }
                            }
                        }
                        .disabled(newComment.isEmpty || isLoading)
                        .scaleEffect(newComment.isEmpty || isLoading ? 0.95 : 1.0)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: newComment.isEmpty), value: newComment.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 8) // Espacio extra abajo
        }
    }

    @ViewBuilder
    private var mentionSearchOverlay: some View {
        if let editingMention = activeEditingCommentMention {
            CommentMentionSearchOverlay(
                query: editingMention.query,
                showsSearchField: false,
                onSelect: { user in
                    insertMention(user, into: .editing)
                },
                onCancel: {
                    activeEditingCommentMention = nil
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let newMention = activeNewCommentMention {
            CommentMentionSearchOverlay(
                query: newMention.query,
                showsSearchField: false,
                onSelect: { user in
                    insertMention(user, into: .newComment)
                },
                onCancel: {
                    activeNewCommentMention = nil
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func detectMentionToken(in text: String) -> MentionDraftToken? {
        guard !text.isEmpty else { return nil }

        let tokenStart = text.lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        let tokenRange = tokenStart..<text.endIndex
        let token = String(text[tokenRange])
        guard token.hasPrefix("@"), token.count > 1 else {
            return nil
        }

        let query = String(token.dropFirst())
        guard query.count <= 30,
              query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }

        return MentionDraftToken(
            query: query,
            fullRange: tokenRange
        )
    }

    private func insertMention(_ user: AppUser, into target: MentionInputTarget) {
        switch target {
        case .newComment:
            guard let token = activeNewCommentMention else { return }
            let entity = insertMention(user, token: token, text: &newComment)
            newCommentMentions = replacingMention(entity, in: newCommentMentions)
            activeNewCommentMention = nil
        case .editing:
            guard let token = activeEditingCommentMention else { return }
            let entity = insertMention(user, token: token, text: &editingCommentContent)
            editingCommentMentions = replacingMention(entity, in: editingCommentMentions)
            activeEditingCommentMention = nil
        }

        HapticManager.shared.selection()
    }

    private func insertMention(_ user: AppUser, token: MentionDraftToken, text: inout String) -> CommentMentionEntity {
        let rangeStart = text.distance(from: text.startIndex, to: token.fullRange.lowerBound)
        let replacement = "@\(user.username) "
        text.replaceSubrange(token.fullRange, with: replacement)

        return CommentMentionEntity(
            userId: user.id,
            username: user.username,
            rangeStart: rangeStart,
            rangeLength: replacement.trimmingCharacters(in: .whitespaces).count
        )
    }

    private func replacingMention(_ entity: CommentMentionEntity, in mentions: [CommentMentionEntity]) -> [CommentMentionEntity] {
        var next = mentions.filter { $0.userId != entity.userId }
        next.append(entity)
        return next
    }

    private func sanitizedMentionEntities(_ mentions: [CommentMentionEntity], in text: String) -> [CommentMentionEntity] {
        var seenUserIds = Set<String>()
        var sanitized: [CommentMentionEntity] = []

        for mention in mentions {
            guard !seenUserIds.contains(mention.userId),
                  let range = text.range(of: "@\(mention.username)", options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }

            seenUserIds.insert(mention.userId)
            let rangeStart = text.distance(from: text.startIndex, to: range.lowerBound)
            let rangeLength = text.distance(from: range.lowerBound, to: range.upperBound)
            sanitized.append(
                CommentMentionEntity(
                    userId: mention.userId,
                    username: mention.username,
                    rangeStart: rangeStart,
                    rangeLength: rangeLength
                )
            )
        }

        return sanitized
    }
    
    // ✅ Función auxiliar para obtener comentarios anidados
    private func getNestedComments(for parentId: String) -> [Comment] {
        guard !parentId.isEmpty else { return [] }
        return filteredComments
            .filter { $0.parentCommentId == parentId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Profundidad del comentario en el hilo (0 = raíz).
    private func nestingDepth(of commentId: String) -> Int {
        var depth = 0
        var currentId: String? = commentId
        var visited = Set<String>()
        while let id = currentId, !id.isEmpty, !visited.contains(id) {
            visited.insert(id)
            guard let comment = comments.first(where: { $0.id == id }),
                  let parentId = comment.parentCommentId,
                  !parentId.isEmpty else {
                break
            }
            depth += 1
            currentId = parentId
        }
        return depth
    }

    private func canReply(to comment: Comment) -> Bool {
        guard let id = comment.id, !id.isEmpty else { return false }
        return nestingDepth(of: id) < maxCommentNestingLevel
    }

    private func setupMuteSettingsListener() {
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            DispatchQueue.main.async {
                self.mutedUserIds = []
                self.mutedWordsNormalized = []
            }
            return
        }

        muteSettingsListener?.remove()
        muteSettingsListener = firestoreService.db
            .collection("users")
            .document(currentUserId)
            .addSnapshotListener { snapshot, _ in
                let muteSettings = snapshot?.data()?["muteSettings"] as? [String: Any] ?? [:]
                let mutedUsers = Set((muteSettings["mutedUsers"] as? [String] ?? []).filter { !$0.isEmpty })
                let mutedWords = (muteSettings["mutedWords"] as? [String] ?? [])
                    .map { normalizeMutedText($0) }
                    .filter { !$0.isEmpty }

                DispatchQueue.main.async {
                    self.mutedUserIds = mutedUsers
                    self.mutedWordsNormalized = mutedWords
                }
            }
    }

    private enum CommentMuteFilterReason {
        case mutedAccount
        case mutedWord
    }

    private func applyCommentMuteFilters(to source: [Comment]) -> CommentFilterResult {
        guard !source.isEmpty else { return CommentFilterResult(visible: [], mutedWordMaskedIds: []) }
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return CommentFilterResult(visible: source, mutedWordMaskedIds: [])
        }

        let hasUserMute = !mutedUserIds.isEmpty
        let hasWordMute = !mutedWordsNormalized.isEmpty
        guard hasUserMute || hasWordMute else {
            return CommentFilterResult(visible: source, mutedWordMaskedIds: [])
        }

        var childrenByParent: [String: [String]] = [:]
        for comment in source {
            guard let id = comment.id else { continue }
            if let parentId = comment.parentCommentId {
                childrenByParent[parentId, default: []].append(id)
            }
        }

        var flaggedByReason: [String: CommentMuteFilterReason] = [:]
        for comment in source {
            guard let id = comment.id else { continue }
            if let reason = muteReason(for: comment, currentUserId: currentUserId) {
                flaggedByReason[id] = reason
            }
        }

        guard !flaggedByReason.isEmpty else {
            return CommentFilterResult(visible: source, mutedWordMaskedIds: [])
        }

        var mutedWordMaskedIds = Set<String>()
        var hiddenIds = Set<String>()
        var branchHiddenIds = Set<String>()

        for (id, reason) in flaggedByReason {
            switch reason {
            case .mutedAccount:
                hiddenIds.insert(id)
                branchHiddenIds.insert(id)
            case .mutedWord:
                let hasChildren = !(childrenByParent[id] ?? []).isEmpty
                if hasChildren {
                    mutedWordMaskedIds.insert(id)
                } else {
                    hiddenIds.insert(id)
                    branchHiddenIds.insert(id)
                }
            }
        }

        if !branchHiddenIds.isEmpty {
            var changed = true
            while changed {
                changed = false
                for comment in source {
                    guard let id = comment.id, !hiddenIds.contains(id) else { continue }
                    guard let parentId = comment.parentCommentId, branchHiddenIds.contains(parentId) else { continue }
                    hiddenIds.insert(id)
                    branchHiddenIds.insert(id)
                    changed = true
                }
            }
        }

        mutedWordMaskedIds = Set(mutedWordMaskedIds.filter { !hiddenIds.contains($0) })

        let visible = source.filter { comment in
            guard let id = comment.id else { return true }
            return !hiddenIds.contains(id)
        }

        return CommentFilterResult(visible: visible, mutedWordMaskedIds: mutedWordMaskedIds)
    }

    private func muteReason(for comment: Comment, currentUserId: String) -> CommentMuteFilterReason? {
        if comment.authorId == currentUserId {
            return nil
        }

        if mutedUserIds.contains(comment.authorId) {
            return .mutedAccount
        }

        guard !mutedWordsNormalized.isEmpty else { return nil }
        let normalizedContent = normalizeMutedText(comment.content)
        guard !normalizedContent.isEmpty else { return nil }

        return mutedWordsNormalized.contains { normalizedContent.contains($0) } ? .mutedWord : nil
    }

    private static func normalizeMutedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private func normalizeMutedText(_ text: String) -> String {
        Self.normalizeMutedText(text)
    }

    private func revealMutedCommentTemporarily(_ commentId: String) {
        guard !commentId.isEmpty else { return }
        temporarilyRevealedCommentIds.insert(commentId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = temporarilyRevealedCommentIds.remove(commentId)
            }
        }
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
                
                if error != nil {
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
    private func addComment(content: String, parentCommentId: String?, mentions: [CommentMentionEntity]) {
        guard let userId = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        if let parentCommentId, !parentCommentId.isEmpty,
           nestingDepth(of: parentCommentId) >= maxCommentNestingLevel {
            return
        }
        
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
            mentions: mentions,
            isPending: true
        )
        
        withAnimation {
            self.comments.append(pendingComment)
        }
        
        
        firestoreService.addComment(
            to: momentId,
            userId: moment.authorId,
            authorId: userId,
            content: content,
            parentCommentId: parentCommentId,
            mentions: mentions
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
    
    private func updateComment(commentId: String, content: String, mentions: [CommentMentionEntity]) {
        guard let _ = Auth.auth().currentUser?.uid, let momentId = moment.id else { return }
        firestoreService.updateComment(momentId: momentId, userId: moment.authorId, commentId: commentId, content: content, mentions: mentions) { result in
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
                    HapticManager.shared.notification(.warning)
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
              let _ = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        
        firestoreService.addCommentReaction(
            to: momentId,
            commentId: commentId,
            reaction: "like",
            userId: moment.authorId,  // ✅ CAMBIO: usar moment.authorId en lugar de currentUserId
            authorId: comment.authorId
        ) { error in
            guard error == nil else { return }
            DispatchQueue.main.async {
                self.fetchComments()
            }
        }
    }
}

// ✅ ENUM para opciones de ordenación
enum CommentSortOption {
    case newest, oldest, mostLiked
}

private struct CommentTextSegment: Identifiable {
    let id: Int
    let text: String
    let userId: String?
    let isMention: Bool
}

private struct CommentMentionText: View {
    private static let mentionURLScheme = "moments-mention"

    let segments: [CommentTextSegment]
    let fontSize: CGFloat
    let baseColor: Color
    let mentionColor: Color
    let isBlurred: Bool
    let onMentionTap: (String) -> Void

    var body: some View {
        // Text nativo: wrap, emoji y saltos de línea correctos.
        // El Layout custom anterior partía cada palabra y dejaba el emoji solo en otra línea.
        Text(attributedContent)
            .font(.system(size: legacyPoppinsSize(fontSize)))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: isBlurred ? 8 : 0)
            .allowsHitTesting(!isBlurred)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.mentionURLScheme else { return .systemAction }
                let token = url.host?.removingPercentEncoding
                    ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        .removingPercentEncoding
                    ?? ""
                guard !token.isEmpty else { return .handled }
                onMentionTap(token)
                return .handled
            })
    }

    private var attributedContent: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var chunk = AttributedString(segment.text)
            chunk.font = .system(
                size: legacyPoppinsSize(fontSize),
                weight: segment.isMention ? .semibold : .regular
            )
            chunk.foregroundColor = segment.isMention ? mentionColor : baseColor
            if segment.isMention {
                let token = segment.userId ?? segment.text
                if let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
                   let url = URL(string: "\(Self.mentionURLScheme)://\(encoded)") {
                    chunk.link = url
                }
            }
            result.append(chunk)
        }
        return result
    }
}

// ✅ NUEVA FILA DE COMENTARIO CON ANIDACIÓN COMO 
struct EnhancedModernCommentRow: View {
    let comment: Comment
    let moment: Moment
    let onEdit: (Comment) -> Void
    let onDelete: (Comment) -> Void
    let onLike: (Comment) -> Void
    let onReply: (Comment) -> Void
    let nestedCommentsProvider: (String) -> [Comment]
    let isCommentExpanded: (String) -> Bool
    let onToggleExpand: (String) -> Void
    let onAvatarTap: (String, Bool) -> Void
    let onMentionTap: (String) -> Void
    let maskedCommentIds: Set<String>
    let temporarilyRevealedCommentIds: Set<String>
    let onRevealTemporarily: (String) -> Void
    let nestingLevel: Int
    var maxNestingLevel: Int = 4
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

    private var nestedComments: [Comment] {
        nestedCommentsProvider(comment.id ?? "")
    }

    private var isExpanded: Bool {
        guard let id = comment.id, !id.isEmpty else { return false }
        return isCommentExpanded(id)
    }

    /// Cada nivel expande solo sus hijos directos.
    private var shouldShowNestedComments: Bool {
        !nestedComments.isEmpty && nestingLevel < maxNestingLevel && isExpanded
    }
    
    // ✅ Indentación visual basada en nivel
    private var indentationWidth: CGFloat {
        CGFloat(min(nestingLevel, maxNestingLevel)) * 16
    }
    
    // ✅ Línea vertical para mostrar jerarquía
    private var shouldShowConnectorLine: Bool {
        nestingLevel > 0
    }

    private var isMutedWordMasked: Bool {
        guard let commentId = comment.id else { return false }
        return maskedCommentIds.contains(commentId)
    }

    private var isTemporarilyRevealed: Bool {
        guard let commentId = comment.id else { return false }
        return temporarilyRevealedCommentIds.contains(commentId)
    }

    private var isMaskApplied: Bool {
        isMutedWordMasked && !isTemporarilyRevealed
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
            
            // Hijos directos solo si este nivel está expandido.
            if shouldShowNestedComments {
                LazyVStack(spacing: 8) {
                    ForEach(nestedComments) { nestedComment in
                        EnhancedModernCommentRow(
                            comment: nestedComment,
                            moment: moment,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onLike: onLike,
                            onReply: onReply,
                            nestedCommentsProvider: nestedCommentsProvider,
                            isCommentExpanded: isCommentExpanded,
                            onToggleExpand: onToggleExpand,
                            onAvatarTap: onAvatarTap,
                            onMentionTap: onMentionTap,
                            maskedCommentIds: maskedCommentIds,
                            temporarilyRevealedCommentIds: temporarilyRevealedCommentIds,
                            onRevealTemporarily: onRevealTemporarily,
                            nestingLevel: nestingLevel + 1,
                            maxNestingLevel: maxNestingLevel
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
        }
    }
    

    
    // ✅ Contenido principal del comentario
    private var commentContent: some View {
        HStack(alignment: .top, spacing: 12) {
            StoryRingAvatarView(
                userId: comment.authorId,
                size: avatarSize,
                lineWidth: nestingLevel == 0 ? 2.3 : 2.0,
                onTap: { hasStory in
                    onAvatarTap(comment.authorId, hasStory)
                }
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
        .padding(.horizontal, nestingLevel == 0 ? 10 : 6)
        .padding(.vertical, nestingLevel == 0 ? 12 : 8)
        .contentShape(Rectangle())
        .contextMenu {
            if !isMaskApplied && canEdit {
                Button {
                    onEdit(comment)
                } label: {
                    Label(NSLocalizedString("comments.actions.edit", comment: "Edit comment action"), systemImage: "pencil")
                }
            }

            if !isMaskApplied && canDelete {
                Button(role: .destructive) {
                    onDelete(comment)
                } label: {
                    Label(NSLocalizedString("comments.actions.delete", comment: "Delete comment action"), systemImage: "trash")
                }
            }
        }
        // Animación de entrada "Pop"
        .transition(MotionPolicy.Transition.enterPop)
    }
    
    private var canEdit: Bool {
        comment.authorId == Auth.auth().currentUser?.uid
    }
    
    private var canDelete: Bool {
        comment.authorId == Auth.auth().currentUser?.uid || moment.authorId == Auth.auth().currentUser?.uid
    }
    
    // ✅ Tamaño de avatar variable
    private var avatarSize: CGFloat {
        switch nestingLevel {
        case 0: return 42
        case 1: return 37
        case 2: return 32
        default: return 28
        }
    }
    
    // ✅ Header del comentario mejorado
    private var commentHeader: some View {
        HStack(spacing: 8) {
            // ✅ Username con @ si es respuesta
            HStack(spacing: 4) {
                if nestingLevel > 0 {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 10))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
                
                HStack(spacing: 3) {
                    Text(comment.username)
                        .font(.system(size: legacyPoppinsSize(nestingLevel == 0 ? 14 : 13), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: comment.authorId, size: nestingLevel == 0 ? 12 : 10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onAvatarTap(comment.authorId, false)
            }
            
            // ✅ Indicador de editado
            if comment.isEditedFlag {
                Text("modernComments.edited")
                    .font(.system(size: legacyPoppinsSize(10)))
                    .foregroundStyle(.gray.opacity(0.6))
                    .italic()
            }
            
            Text("•")
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(.gray.opacity(0.6))
            
            // ✅ Timestamp relativo
            HStack(spacing: 4) {
                Text(timeAgo(from: comment.timestamp))
                    .font(.system(size: legacyPoppinsSize(nestingLevel == 0 ? 12 : 11)))
                    .foregroundStyle(.gray.opacity(0.6))
                
                if comment.isPending == true {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray.opacity(0.6))
                }
            }
            
            Spacer()
            

        }
    }
    
    // ✅ Contenido con menciones destacadas
    private var contentWithMentions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                CommentMentionText(
                    segments: commentTextSegments,
                    fontSize: nestingLevel == 0 ? 14 : 13,
                    baseColor: colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9),
                    mentionColor: mentionAccentColor,
                    isBlurred: isMaskApplied,
                    onMentionTap: onMentionTap
                )

                if isMaskApplied {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                            Text(NSLocalizedString("modernComments.mutedWord.placeholder", comment: "Muted word placeholder in comments"))
                                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        if let commentId = comment.id {
                            Button(action: {
                                onRevealTemporarily(commentId)
                            }) {
                                Text(NSLocalizedString("modernComments.mutedWord.reveal", comment: "Temporarily reveal muted word comment"))
                                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if isLongComment && !isMaskApplied {
                Button(action: { showFullContent.toggle() }) {
                    Text(showFullContent ? "Ver menos" : "Ver más")
                        .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }

    private var mentionAccentColor: Color {
        colorScheme == .dark ? Color(red: 0.52, green: 0.78, blue: 1.0) : Color(red: 0.05, green: 0.42, blue: 0.95)
    }

    private var commentTextSegments: [CommentTextSegment] {
        // Solo partir por menciones; el wrap lo hace Text (espacios, emoji, \n).
        var rawSegments: [(text: String, userId: String?, isMention: Bool)] = []
        var currentIndex = displayContent.startIndex

        for mentionRange in mentionRanges(in: displayContent) {
            if currentIndex < mentionRange.range.lowerBound {
                let plain = String(displayContent[currentIndex..<mentionRange.range.lowerBound])
                if !plain.isEmpty {
                    rawSegments.append((text: plain, userId: nil, isMention: false))
                }
            }

            rawSegments.append((
                text: String(displayContent[mentionRange.range]),
                userId: mentionRange.userId,
                isMention: true
            ))
            currentIndex = mentionRange.range.upperBound
        }

        if currentIndex < displayContent.endIndex {
            let plain = String(displayContent[currentIndex...])
            if !plain.isEmpty {
                rawSegments.append((text: plain, userId: nil, isMention: false))
            }
        }

        if rawSegments.isEmpty, !displayContent.isEmpty {
            rawSegments = [(text: displayContent, userId: nil, isMention: false)]
        }

        return rawSegments.enumerated().map { index, segment in
            CommentTextSegment(
                id: index,
                text: segment.text,
                userId: segment.userId,
                isMention: segment.isMention
            )
        }
    }

    private func mentionRanges(in text: String) -> [(range: Range<String.Index>, userId: String?)] {
        if !comment.mentions.isEmpty {
            return comment.mentions.compactMap { mention in
                guard let range = text.range(of: "@\(mention.username)", options: [.caseInsensitive, .diacriticInsensitive]) else {
                    return nil
                }
                return (range, mention.userId)
            }.sorted { first, second in
                first.range.lowerBound < second.range.lowerBound
            }
        }

        let pattern = #"@(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (range, nil)
        }
    }
    

    
    // ✅ Botones de acción mejorados
    private var actionButtons: some View {
        HStack(spacing: 16) {
            if !isMaskApplied {
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
                
                // ✅ Reply button (solo hasta el máximo)
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
            }
            
            // Cada nivel con respuestas directas tiene su propio expand.
            if !nestedComments.isEmpty && nestingLevel < maxNestingLevel {
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
        MomentsFormat.relativeTime(from: date)
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
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text("modernComments.empty.description")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.gray.opacity(0.7))
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
                    .foregroundStyle(isActive ? activeColor : (colorScheme == .dark ? .white : .black))
                
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(isActive ? activeColor : (colorScheme == .dark ? .white : .black))
                }
                
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
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
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isActive), value: isActive)
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
