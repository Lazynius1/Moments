import SwiftUI
import FirebaseAuth
import Kingfisher

// MARK: - Story share helpers

func storyPreviewURL(for story: Story) -> String {
    if let url = story.backgroundFrameURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
        return url
    }
    if let url = story.backgroundBlurredFrameURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
        return url
    }
    return story.mediaItem.url
}

func storyMediaTypeString(for story: Story) -> String {
    story.mediaItem.type == .video ? "video" : "image"
}

// MARK: - Acceso a historia compartida (privada, bloqueo, audiencia, expiración)

enum SharedStoryAccessDenialReason: Error {
    case expired
    case notFound
    case blocked
    case privateAccount
    case restricted

    var titleKey: String {
        switch self {
        case .privateAccount:
            return "share.storyDenied.private.title"
        case .blocked:
            return "share.storyDenied.blocked.title"
        default:
            return "share.storyUnavailable"
        }
    }

    var messageKey: String {
        switch self {
        case .expired:
            return "share.storyDenied.expired"
        case .notFound:
            return "share.storyDenied.notFound"
        case .blocked:
            return "share.storyDenied.blocked"
        case .privateAccount:
            return "share.storyDenied.private"
        case .restricted:
            return "share.storyDenied.restricted"
        }
    }
}

enum SharedStoryAccessEvaluator {
    static func evaluate(
        authorId: String,
        storyId: String,
        payloadExpiration: TimeInterval?,
        viewerId: String,
        completion: @escaping (Result<Story, SharedStoryAccessDenialReason>) -> Void
    ) {
        if authorId == viewerId {
            StoryRepository().fetchStory(userId: authorId, storyId: storyId) { result in
                switch result {
                case .success(let story):
                    completion(.success(story))
                case .failure:
                    completion(.failure(.notFound))
                }
            }
            return
        }

        if let payloadExpiration, Date() > Date(timeIntervalSince1970: payloadExpiration) {
            completion(.failure(.expired))
            return
        }

        StoryRepository().fetchStory(userId: authorId, storyId: storyId) { result in
            switch result {
            case .failure:
                completion(.failure(.notFound))
            case .success(let story):
                evaluate(story: story, authorId: authorId, viewerId: viewerId, completion: completion)
            }
        }
    }

    static func evaluate(
        story: Story,
        authorId: String,
        viewerId: String,
        completion: @escaping (Result<Story, SharedStoryAccessDenialReason>) -> Void
    ) {
        let resolvedAuthorId = authorId.isEmpty ? story.authorId : authorId

        if resolvedAuthorId == viewerId || story.authorId == viewerId {
            completion(.success(story))
            return
        }

        if story.expirationDate <= Date() {
            completion(.failure(.expired))
            return
        }

        let privacyService = PrivacyService.shared

        privacyService.checkMutualBlocks(viewerId: viewerId, targetUserId: resolvedAuthorId) { isBlocked in
            if isBlocked {
                completion(.failure(.blocked))
                return
            }

            privacyService.fetchPrivacySettings(userId: resolvedAuthorId) { result in
                switch result {
                case .failure:
                    completion(.failure(.restricted))
                case .success(let settings):
                    if settings.isPrivate {
                        FirestoreService.shared.isFollowing(
                            currentUserId: viewerId,
                            targetUserId: resolvedAuthorId
                        ) { isFollowing in
                            if !isFollowing {
                                completion(.failure(.privateAccount))
                                return
                            }
                            finishWithEnhancedCheck(story: story, viewerId: viewerId, completion: completion)
                        }
                    } else {
                        finishWithEnhancedCheck(story: story, viewerId: viewerId, completion: completion)
                    }
                }
            }
        }
    }

    private static func finishWithEnhancedCheck(
        story: Story,
        viewerId: String,
        completion: @escaping (Result<Story, SharedStoryAccessDenialReason>) -> Void
    ) {
        PrivacyService.shared.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
            completion(canView ? .success(story) : .failure(.restricted))
        }
    }
}

// MARK: - Share sheet (solo mensajes)

struct StoryShareBottomSheet: View {
    let story: Story
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isPresented = false
                    }
                }

            VStack {
                Spacer()

                StoryShareRecipientsPanel(
                    story: story,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
                )
                .background(
                    Color.clear
                        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Recipients picker (reutiliza componentes de share.swift)

struct StoryShareRecipientsPanel: View {
    let story: Story
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedUsers: Set<String> = []
    @State private var conversations: [Conversation] = []
    @State private var globalSearchResults: [AppUser] = []
    @State private var isLoading = true
    @State private var activeFilter: FilterType = .none

    enum FilterType {
        case none, favorites, recents
    }

    @StateObject private var chatService = ChatService.shared

    private var filteredConversations: [Conversation] {
        var base = conversations

        switch activeFilter {
        case .favorites:
            base = conversations.filter { $0.isPinned == true }
        case .recents, .none:
            break
        }

        if searchText.isEmpty {
            return base
        }
        return base.filter {
            $0.otherParticipantUsername?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("share.story.title", comment: "Share story sheet title"))
                        .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                        .foregroundStyle(.primary)

                    LiveUsernameContent(userId: story.authorId, fallbackUsername: story.username) { username in
                        Text(String(format: NSLocalizedString("share.story.by", comment: "Story by user"), username))
                    }
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))

                TextField(NSLocalizedString("share.search.placeholder", comment: ""), text: $searchText)
                    .foregroundStyle(.primary)
                    .font(.system(size: legacyPoppinsSize(16)))
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        performGlobalSearch(query: newValue)
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .momentsChromeGlass(in: Capsule(), interactive: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    FilterChip(
                        icon: "star.fill",
                        title: NSLocalizedString("share.favorites", comment: ""),
                        color: Color(hex: "00A896"),
                        isSelected: activeFilter == .favorites
                    ) {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            activeFilter = activeFilter == .favorites ? .none : .favorites
                        }
                    }

                    FilterChip(
                        icon: "clock.fill",
                        title: NSLocalizedString("share.recents", comment: ""),
                        color: .blue,
                        isSelected: activeFilter == .recents
                    ) {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            activeFilter = activeFilter == .recents ? .none : .recents
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        PeopleSkeletonGrid()
                    } else {
                        if !filteredConversations.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                                ForEach(Array(filteredConversations.enumerated()), id: \.element.otherParticipantId) { index, conversation in
                                    PersonCell(
                                        conversation: conversation,
                                        isSelected: selectedUsers.contains(conversation.otherParticipantId),
                                        animationDelay: Double(index) * 0.05,
                                        onTap: { toggleUserSelection(conversation.otherParticipantId) }
                                    )
                                }
                            }
                        }

                        if !globalSearchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("share.search.globalResults")
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                                    ForEach(globalSearchResults) { user in
                                        GlobalUserCell(
                                            user: user,
                                            isSelected: selectedUsers.contains(user.id),
                                            onTap: { toggleUserSelection(user.id) }
                                        )
                                    }
                                }
                            }
                        }

                        if filteredConversations.isEmpty && globalSearchResults.isEmpty && !searchText.isEmpty {
                            EmptySearchState()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .frame(maxHeight: 350)

            SendActionBottomBar(
                selectedCount: selectedUsers.count,
                onSend: sendToSelectedUsers
            )
        }
        .onAppear(perform: loadConversations)
    }

    private func loadConversations() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        chatService.fetchConversations(for: currentUserId) { result in
            DispatchQueue.main.async {
                if case .success(let fetched) = result {
                    withAnimation(.easeInOut) {
                        self.conversations = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func performGlobalSearch(query: String) {
        guard query.count >= 3 else {
            globalSearchResults = []
            return
        }

        FirestoreService.shared.searchUsers(query: query) { result in
            DispatchQueue.main.async {
                if case .success(let users) = result {
                    let localIds = Set(conversations.map(\.otherParticipantId))
                    globalSearchResults = users.filter { !localIds.contains($0.id) }
                }
            }
        }
    }

    private func toggleUserSelection(_ userId: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedUsers.contains(userId) {
                selectedUsers.remove(userId)
            } else {
                selectedUsers.insert(userId)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func sendToSelectedUsers() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              story.id != nil else { return }

        let freshUsername = UserCacheService.shared.getCachedUser(userId: story.authorId)?.username ?? story.username
        let shareText = String(format: NSLocalizedString("share.story.by", comment: ""), freshUsername)

        for userId in selectedUsers {
            let existingConv = conversations.first(where: { $0.otherParticipantId == userId })

            if let conversationId = existingConv?.id, !conversationId.isEmpty {
                chatService.sendSharedStoryMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    story: story,
                    shareText: shareText
                ) { _ in }
            } else {
                chatService.getOrCreateConversation(between: currentUserId, and: userId) { result in
                    if case .success(let conversationId) = result {
                        chatService.sendSharedStoryMessage(
                            conversationId: conversationId,
                            senderId: currentUserId,
                            story: story,
                            shareText: shareText
                        ) { _ in }
                    }
                }
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }
}

// MARK: - Chat bubble (misma huella que momentos compartidos en DM)

struct SharedStoryMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onTap: () -> Void

    @State private var canViewStory: Bool?
    @State private var denialReason: SharedStoryAccessDenialReason?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                SharedDMPreviewCardSkeleton()
                    .frame(
                        maxWidth: 280,
                        alignment: isCurrentUser ? .trailing : .leading
                    )
                    .padding(.vertical, 4)
            } else if canViewStory == true, let sharedStoryData = message.sharedStoryData {
                Button(action: onTap) {
                    StoryBubbleContent(sharedStoryData: sharedStoryData, isCurrentUser: isCurrentUser)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                BlockedStoryBubble(
                    reason: denialReason ?? .restricted,
                    sharedStoryData: message.sharedStoryData
                )
                .frame(
                    maxWidth: 280,
                    alignment: isCurrentUser ? .trailing : .leading
                )
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            validateAccess()
        }
    }

    private func validateAccess() {
        guard let sharedStoryData = message.sharedStoryData,
              let storyId = sharedStoryData["storyId"],
              let currentUserId = Auth.auth().currentUser?.uid else {
            canViewStory = false
            denialReason = .restricted
            isLoading = false
            return
        }

        let authorId = sharedStoryData["storyAuthorId"] ?? message.senderId
        let payloadExpiration = sharedStoryData["storyExpiration"].flatMap { TimeInterval($0) }

        SharedStoryAccessEvaluator.evaluate(
            authorId: authorId,
            storyId: storyId,
            payloadExpiration: payloadExpiration,
            viewerId: currentUserId
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    canViewStory = true
                    denialReason = nil
                case .failure(let reason):
                    canViewStory = false
                    denialReason = reason
                }
                isLoading = false
            }
        }
    }
}

struct BlockedStoryBubble: View {
    let reason: SharedStoryAccessDenialReason
    let sharedStoryData: [String: String]?

    private var iconName: String {
        switch reason {
        case .blocked:
            return "hand.raised.fill"
        case .privateAccount:
            return "lock.fill"
        case .expired:
            return "clock.fill"
        default:
            return "lock.fill"
        }
    }

    var body: some View {
        SharedDMUnavailablePreviewCard(
            titleKey: reason.titleKey,
            messageKey: reason.messageKey,
            iconName: iconName,
            previewImageURL: sharedStoryData?["storyPreviewUrl"],
            authorId: sharedStoryData?["storyAuthorId"],
            authorName: sharedStoryData?["storyAuthor"],
            useStoryRing: true
        )
    }
}

struct StoryBubbleContent: View {
    let sharedStoryData: [String: String]
    let isCurrentUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StoryPreviewCard(sharedStoryData: sharedStoryData)
        }
        .padding(.vertical, 4)
        .frame(alignment: isCurrentUser ? .trailing : .leading)
    }
}

enum StoryShareCardMetrics {
    static let width: CGFloat = 172
    static var height: CGFloat { width * 16 / 9 }
    static let cornerRadius: CGFloat = 12
}

/// Story compartida: NO usa tarjeta, es la propia media
/// vertical (9:16) redondeada, con el autor superpuesto arriba en blanco.
struct StoryPreviewCard: View {
    let sharedStoryData: [String: String]

    private var isVideo: Bool {
        sharedStoryData["storyMediaType"] == "video"
    }

    var body: some View {
        ZStack {
            StoryVisualContent(sharedStoryData: sharedStoryData)
                .frame(width: StoryShareCardMetrics.width, height: StoryShareCardMetrics.height)
                .clipped()

            VStack {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 70)

                    SharedDMPreviewAuthorRow(
                        authorId: sharedStoryData["storyAuthorId"],
                        authorName: sharedStoryData["storyAuthor"],
                        useStoryRing: true
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                }
                Spacer(minLength: 0)
            }

            if isVideo {
                SharedDMCenteredPlayOverlay()
            }
        }
        .frame(width: StoryShareCardMetrics.width, height: StoryShareCardMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: StoryShareCardMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StoryShareCardMetrics.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

struct StoryVisualContent: View {
    let sharedStoryData: [String: String]

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let previewUrl = sharedStoryData["storyPreviewUrl"],
                   let url = URL(string: previewUrl) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            ZStack {
                                Color.white.opacity(0.1)
                                ProgressView().tint(.white)
                            }
                        }
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}
