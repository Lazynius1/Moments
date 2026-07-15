import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CommentsView: View {
    let moment: Moment
    @StateObject private var viewModel = CommentsViewModel()
    @State private var storyRoute: StoryUserPresentationRoute?
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            headerView
            commentsListView
            addCommentView
        }
        .background(
            colorScheme == .dark ? Color.black.opacity(0.95) : Color.white.opacity(0.98)
        )
        .onAppear {
            viewModel.fetchComments(momentId: moment.id, userId: moment.authorId)
        }
        .alert(NSLocalizedString("comments.error.title", comment: "Error title"), isPresented: $viewModel.showError) {
            Button(NSLocalizedString("comments.error.ok", comment: "OK button")) { }
        } message: {
            Text(viewModel.errorMessage ?? NSLocalizedString("comments.error.unknown", comment: "Unknown error"))
        }
        .fullScreenCover(item: $storyRoute) { route in
            StoriesView(startWithUserId: .constant(route.userId))
                .environmentObject(firestoreService)
                .ignoresSafeArea(.keyboard)
        }
    }

    // Encabezado
    private var headerView: some View {
        HStack {
            Text(NSLocalizedString("comments.title", comment: "Comments title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.momentsPressIcon)
            .accessibilityLabel(NSLocalizedString("common.close", comment: "Close"))
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    // Lista de comentarios
    private var commentsListView: some View {
        ScrollView {
            commentsStackView
        }
    }

    // Stack de comentarios
    private var commentsStackView: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.comments) { comment in
                commentRowView(for: comment)
            }
        }
        .padding(.vertical, 8)
    }

    // Vista individual para cada comentario
    @ViewBuilder
    private func commentRowView(for comment: Comment) -> some View {
        if let commentId = comment.id {
            CommentRow(
                comment: comment,
                isEditing: viewModel.editingCommentId == comment.id,
                editedContent: $viewModel.editedCommentContent,
                onEdit: {
                    viewModel.startEditing(comment: comment)
                },
                onSaveEdit: {
                    viewModel.saveEditedComment(
                        momentId: moment.id,
                        userId: moment.authorId,
                        commentId: commentId
                    )
                },
                onCancelEdit: {
                    viewModel.cancelEditing()
                },
                onDelete: {
                    viewModel.deleteComment(
                        momentId: moment.id,
                        userId: moment.authorId,
                        commentId: commentId
                    )
                },
                onLike: {
                    viewModel.addCommentReaction(
                        momentId: moment.id,
                        userId: moment.authorId,
                        commentId: commentId
                    )
                },
                onAvatarTap: { userId, hasStory in
                    guard !userId.isEmpty else { return }
                    if hasStory {
                        storyRoute = StoryUserPresentationRoute(userId: userId)
                    } else {
                        LegacyNavigationBridge.profile(userId: userId)
                    }
                }
            )
            .contextMenu {
                commentContextMenu(for: comment)
            }
        }
    }

    // Menú contextual para cada comentario
    @ViewBuilder
    private func commentContextMenu(for comment: Comment) -> some View {
        if comment.authorId == Auth.auth().currentUser?.uid || moment.authorId == Auth.auth().currentUser?.uid {
            Button(action: { viewModel.startEditing(comment: comment) }) {
                Label(NSLocalizedString("comments.actions.edit", comment: "Edit comment"), systemImage: "pencil")
            }
            .disabled(moment.authorId != comment.authorId && comment.authorId != Auth.auth().currentUser?.uid)
            Button(action: {
                if let commentId = comment.id {
                    viewModel.deleteComment(
                        momentId: moment.id,
                        userId: moment.authorId,
                        commentId: commentId
                    )
                }
            }) {
                Label(NSLocalizedString("comments.actions.delete", comment: "Delete comment"), systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    // Campo para añadir comentario
    private var addCommentView: some View {
        HStack {
            TextField(NSLocalizedString("comments.add.placeholder", comment: "Add comment placeholder"), text: $viewModel.newComment)
                .font(.system(size: 16))
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 8)

            Button(action: {
                if !viewModel.newComment.isEmpty {
                    viewModel.addComment(
                        to: moment.id,
                        userId: moment.authorId,
                        authorId: Auth.auth().currentUser?.uid ?? ""
                    )
                    viewModel.newComment = ""
                }
            }) {
                Text(NSLocalizedString("comments.actions.publish", comment: "Publish comment"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(viewModel.newComment.isEmpty ? .gray : (colorScheme == .dark ? .yellow : .blue))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(viewModel.newComment.isEmpty ? Color.clear : (colorScheme == .dark ? Color.yellow.opacity(0.1) : Color.blue.opacity(0.1)))
                    )
            }
            .disabled(viewModel.newComment.isEmpty)
        }
        .padding()
    }
}

struct CommentRow: View {
    let comment: Comment
    let isEditing: Bool
    @Binding var editedContent: String
    let onEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    let onLike: () -> Void
    let onAvatarTap: (String, Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Foto de perfil
            StoryRingAvatarView(
                userId: comment.authorId,
                size: 36,
                lineWidth: 2.2,
                showBaseStroke: true,
                baseStrokeColor: Color.gray.opacity(0.2),
                baseStrokeWidth: 1,
                onTap: { hasStory in
                    onAvatarTap(comment.authorId, hasStory)
                }
            )

            // Contenido del comentario
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let updatedAt = comment.updatedAt, abs(updatedAt.timeIntervalSince(comment.timestamp)) > 1 {
                        Text(NSLocalizedString("comments.edited", comment: "Edited comment indicator"))
                            .font(.system(size: 12))
                            .foregroundStyle(.gray.opacity(0.6))
                    }
                    Spacer()
                    Text(comment.timestamp.timeAgoDisplay())
                        .font(.system(size: 12))
                        .foregroundStyle(.gray.opacity(0.6))
                }

                if isEditing {
                    TextField(NSLocalizedString("comments.actions.editPlaceholder", comment: "Edit comment placeholder"), text: $editedContent)
                        .font(.system(size: 14))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                    HStack {
                        Button(NSLocalizedString("comments.actions.cancel", comment: "Cancel edit")) {
                            onCancelEdit()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.gray)
                        Spacer()
                        Button(NSLocalizedString("comments.actions.save", comment: "Save edit")) {
                            onSaveEdit()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                        .disabled(editedContent.isEmpty)
                    }
                    .padding(.top, 4)
                } else {
                    Text(comment.content)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary) // Cambiado a .primary para mejor legibilidad
                        .fixedSize(horizontal: false, vertical: true)
                    // Botón de like
                    HStack(spacing: 8) {
                        Button(action: onLike) {
                            HStack(spacing: 4) {
                                Image(systemName: comment.reactions["like"]?.contains(Auth.auth().currentUser?.uid ?? "") ?? false ? "heart.fill" : "heart")
                                    .foregroundStyle(.red)
                                if (comment.reactions["like"]?.count ?? 0) > 0 {
                                    Text("\(comment.reactions["like"]?.count ?? 0)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                        .padding(.top, 4)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var newComment: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var editingCommentId: String?
    @Published var editedCommentContent: String = ""
    @Published var lastDocument: DocumentSnapshot? // Declared missing property
    @Published var hasMoreComments: Bool = true // Declared missing property

    private let firestoreService = FirestoreService()

    func fetchComments(momentId: String?, userId: String) {
        guard let momentId = momentId else {
            errorMessage = "No se pudo cargar los comentarios."
            showError = true
            return
        }

        isLoading = true
        firestoreService.fetchComments(for: momentId, userId: userId, limit: 10) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let (comments, lastDocument)):
                    self?.comments = comments
                    self?.lastDocument = lastDocument
                    self?.hasMoreComments = comments.count >= 10
                case .failure(let error):
                    self?.errorMessage = "Error al cargar comentarios: \(error.localizedDescription)"
                    self?.showError = true
                }
            }
        }
    }

    func addComment(to momentId: String?, userId: String, authorId: String) {
        guard let momentId = momentId, !authorId.isEmpty, !newComment.isEmpty else {
            errorMessage = "No se pudo añadir el comentario."
            showError = true
            return
        }

        firestoreService.addComment(to: momentId, userId: userId, authorId: authorId, content: newComment) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    Task { @MainActor in
                        AffinityTracker.shared.trackInteraction(type: .momentComment, with: userId)
                    }
                    self?.fetchComments(momentId: momentId, userId: userId)
                case .failure(let error):
                    self?.errorMessage = "Error al añadir comentario: \(error.localizedDescription)"
                    self?.showError = true
                }
            }
        }
    }

    func startEditing(comment: Comment) {
        editingCommentId = comment.id
        editedCommentContent = comment.content
    }

    func saveEditedComment(momentId: String?, userId: String, commentId: String) {
        guard let momentId = momentId, !editedCommentContent.isEmpty else {
            errorMessage = "No se pudo guardar el comentario."
            showError = true
            return
        }

        firestoreService.updateComment(
            momentId: momentId,
            userId: userId,
            commentId: commentId,
            content: editedCommentContent
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.editingCommentId = nil
                    self?.editedCommentContent = ""
                    self?.fetchComments(momentId: momentId, userId: userId)
                case .failure(let error):
                    self?.errorMessage = "Error al actualizar comentario: \(error.localizedDescription)"
                    self?.showError = true
                }
            }
        }
    }
    
    func addCommentReaction(momentId: String?, userId: String, commentId: String) {
        guard let momentId = momentId, let authorId = Auth.auth().currentUser?.uid else {
            errorMessage = "No se pudo añadir la reacción."
            showError = true
            return
        }

        firestoreService.addCommentReaction(
            to: momentId,
            commentId: commentId,
            reaction: "like",
            userId: authorId,
            authorId: userId
        ) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Error al añadir reacción: \(error.localizedDescription)"
                    self?.showError = true
                } else {
                    self?.fetchComments(momentId: momentId, userId: userId)
                }
            }
        }
    }

    func cancelEditing() {
        editingCommentId = nil
        editedCommentContent = ""
    }

    func deleteComment(momentId: String?, userId: String, commentId: String) {
        guard let momentId = momentId else {
            errorMessage = "No se pudo eliminar el comentario."
            showError = true
            return
        }

        let authorId = Auth.auth().currentUser?.uid ?? ""
        firestoreService.deleteComment(
            to: momentId,
            commentId: commentId,
            userId: userId,
            authorId: authorId
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.fetchComments(momentId: momentId, userId: userId)
                case .failure(let error):
                    self?.errorMessage = "Error al eliminar comentario: \(error.localizedDescription)"
                    self?.showError = true
                }
            }
        }
    }
}
