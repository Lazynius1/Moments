import SwiftUI
import FirebaseAuth
import FirebaseCore
import Kingfisher

private enum SharedActivityDirection: String {
    case viewerOnOther = "viewer_on_other"
    case otherOnViewer = "other_on_viewer"
}

@MainActor
final class SharedActivityDetailViewModel: ObservableObject {
    let category: SharedActivityCategory
    let currentUser: AppUser?
    let otherUser: AppUser

    @Published var selectedTab = 0 {
        didSet { reload() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reactionItems: [ActivityReactionItem] = []
    @Published var commentItems: [ActivityCommentItem] = []
    @Published var hasMore = true

    private var didLoadOnce = false
    private var reactionsNextCursor: BackendReactionsCursor?
    private var commentsNextCursor: BackendCommentsCursor?
    private var tagsNextCursor: BackendTagsCursor?

    init(category: SharedActivityCategory, currentUser: AppUser?, otherUser: AppUser) {
        self.category = category
        self.currentUser = currentUser
        self.otherUser = otherUser
    }

    func loadIfNeeded() {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        reload()
    }

    func reload() {
        reactionItems.removeAll()
        commentItems.removeAll()
        reactionsNextCursor = nil
        commentsNextCursor = nil
        tagsNextCursor = nil
        hasMore = true
        errorMessage = nil
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading && hasMore else { return }
        guard currentUser?.id != nil else {
            errorMessage = NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")
            hasMore = false
            return
        }

        isLoading = true

        Task { [weak self] in
            guard let self else { return }
            do {
                switch category {
                case .reactions:
                    try await fetchSharedReactions()
                case .comments:
                    try await fetchSharedComments()
                case .tags:
                    try await fetchSharedTags()
                }
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.hasMore = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private var currentDirection: SharedActivityDirection {
        selectedTab == 0 ? .viewerOnOther : .otherOnViewer
    }

    func tabTitle(for index: Int) -> String {
        if index == 0 {
            switch category {
            case .reactions:
                return NSLocalizedString("sharedActivity.tab.yourReactions", value: "Tus reacciones", comment: "")
            case .comments:
                return NSLocalizedString("sharedActivity.tab.yourComments", value: "Tus comentarios", comment: "")
            case .tags:
                return NSLocalizedString("sharedActivity.tab.yourTags", value: "Tus etiquetas", comment: "")
            }
        } else {
            switch category {
            case .reactions:
                return String(format: NSLocalizedString("sharedActivity.tab.fromUser", value: "De %@", comment: ""), otherUser.username)
            case .comments:
                return String(format: NSLocalizedString("sharedActivity.tab.fromUser", value: "De %@", comment: ""), otherUser.username)
            case .tags:
                return String(format: NSLocalizedString("sharedActivity.tab.fromUser", value: "De %@", comment: ""), otherUser.username)
            }
        }
    }

    func removeReactions(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }

        let targets = reactionItems
            .filter { ids.contains($0.id) }
            .map { ["authorId": $0.authorId, "momentId": $0.momentId] }
        guard !targets.isEmpty else { return .success(()) }

        do {
            try await postVoid(
                functionName: "removeSharedReactionsBatch",
                payload: [
                    "otherUserId": otherUser.id,
                    "direction": currentDirection.rawValue,
                    "reactions": targets
                ]
            )
            reactionItems.removeAll { ids.contains($0.id) }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeComments(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }

        let targets = commentItems
            .filter { ids.contains($0.id) }
            .map { ["authorId": $0.authorId, "momentId": $0.momentId, "commentId": $0.commentId] }
        guard !targets.isEmpty else { return .success(()) }

        do {
            try await postVoid(
                functionName: "deleteSharedCommentsBatch",
                payload: [
                    "otherUserId": otherUser.id,
                    "direction": currentDirection.rawValue,
                    "comments": targets
                ]
            )
            commentItems.removeAll { ids.contains($0.id) }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeTags(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }

        let targets = reactionItems
            .filter { ids.contains($0.id) }
            .map { ["authorId": $0.authorId, "momentId": $0.momentId] }
        guard !targets.isEmpty else { return .success(()) }

        do {
            try await postVoid(
                functionName: "removeSharedTagsBatch",
                payload: [
                    "otherUserId": otherUser.id,
                    "direction": currentDirection.rawValue,
                    "moments": targets
                ]
            )
            reactionItems.removeAll { ids.contains($0.id) }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func fetchSharedReactions() async throws {
        let response: BackendReactionsResponse = try await post(
            functionName: "getSharedReactedMomentsPage",
            payload: sharedPayload(cursor: reactionsNextCursor)
        )

        let mapped = response.items.compactMap { item -> ActivityReactionItem? in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty else { return nil }

            return ActivityReactionItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)_\(item.reactedAt ?? 0)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                reactionType: item.reactionType,
                reactedAt: item.reactedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? moment.timestamp,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        reactionsNextCursor = response.nextCursor
        reactionItems.append(contentsOf: mapped)
        hasMore = response.nextCursor != nil
    }

    private func fetchSharedComments() async throws {
        let response: BackendCommentsResponse = try await post(
            functionName: "getSharedCommentedMomentsPage",
            payload: sharedPayload(cursor: commentsNextCursor)
        )

        let mapped = response.items.compactMap { item -> ActivityCommentItem? in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            let resolvedCommentId = item.commentId ?? item.comment?.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty,
                  let resolvedCommentId, !resolvedCommentId.isEmpty else { return nil }

            let commentedAt = item.commentedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? item.comment?.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? moment.timestamp

            return ActivityCommentItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)_\(resolvedCommentId)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                commentId: resolvedCommentId,
                commentText: item.comment?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                commentedAt: commentedAt,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        commentsNextCursor = response.nextCursor
        commentItems.append(contentsOf: mapped)
        hasMore = response.nextCursor != nil
    }

    private func fetchSharedTags() async throws {
        let response: BackendTagsResponse = try await post(
            functionName: "getSharedTaggedMomentsPage",
            payload: sharedPayload(cursor: tagsNextCursor)
        )

        let mapped = response.items.compactMap { item -> ActivityReactionItem? in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty else { return nil }

            return ActivityReactionItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                reactionType: "tagged",
                reactedAt: item.taggedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? moment.timestamp,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        tagsNextCursor = response.nextCursor
        reactionItems.append(contentsOf: mapped)
        hasMore = response.nextCursor != nil
    }

    private func sharedPayload(cursor: BackendReactionsCursor?) -> [String: Any] {
        var payload: [String: Any] = [
            "otherUserId": otherUser.id,
            "direction": currentDirection.rawValue,
            "limit": 36
        ]
        if let cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }
        return payload
    }

    private func sharedPayload(cursor: BackendCommentsCursor?) -> [String: Any] {
        var payload: [String: Any] = [
            "otherUserId": otherUser.id,
            "direction": currentDirection.rawValue,
            "limit": 36
        ]
        if let cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }
        return payload
    }

    private func sharedPayload(cursor: BackendTagsCursor?) -> [String: Any] {
        var payload: [String: Any] = [
            "otherUserId": otherUser.id,
            "direction": currentDirection.rawValue,
            "limit": 36
        ]
        if let cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }
        return payload
    }

    private func post<Response: Decodable>(functionName: String, payload: [String: Any]) async throws -> Response {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }
        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/\(functionName)") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func postVoid(functionName: String, payload: [String: Any]) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }
        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/\(functionName)") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }
    }
}

struct SharedActivityDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SharedActivityDetailViewModel

    @State private var sortOption: ReactionsSortOption = .newest
    @State private var dateFilter: ReactionsDateFilter = .all
    @State private var customDateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customDateTo: Date = Date()
    @Namespace private var zoomNamespace
    @State private var zoomDestination: MomentZoomDestination?
    @State private var zoomMomentsPool: [Moment] = []
    @State private var selectedProfileUserId: String?
    @State private var isSelectionMode = false
    @State private var selectedReactionIds: Set<String> = []
    @State private var selectedCommentIds: Set<String> = []
    @State private var isDeletingSelectedReactions = false
    @State private var isDeletingSelectedComments = false
    @State private var isRemovingSelectedTags = false
    @State private var selectionSuccessBannerKey: String?
    @State private var pendingSelectionConfirmation: SharedActivitySelectionConfirmationAction?

    init(category: SharedActivityCategory, currentUser: AppUser?, otherUser: AppUser) {
        _viewModel = StateObject(wrappedValue: SharedActivityDetailViewModel(
            category: category,
            currentUser: currentUser,
            otherUser: otherUser
        ))
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)
    }

    private var selectionToolbarButtonTitle: String {
        isSelectionMode
            ? NSLocalizedString("savedMoments.cancel", comment: "Cancel")
            : NSLocalizedString("savedMoments.select", comment: "Select")
    }

    var body: some View {
        VStack(spacing: 0) {
            SharedActivityUnderlineTabBar(
                tabTitles: [
                    viewModel.tabTitle(for: 0),
                    viewModel.tabTitle(for: 1)
                ],
                selectedIndex: $viewModel.selectedTab
            )

            filtersBar

            if dateFilter == .custom {
                customDateRangeControls
            }

            contentArea
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(viewModel.category.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(selectionToolbarButtonTitle) {
                    handleSelectionToolbarTap()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelectionMode ? .red : primaryTextColor)
            }
        }
        .safeAreaInset(edge: .bottom) {
            selectionBottomInset
        }
        .overlay(alignment: .bottom) {
            selectionToastOverlay
        }
        .navigationDestination(item: $zoomDestination) { destination in
            MomentZoomDetailDestination(
                destination: destination,
                moments: MomentZoomOpener.resolvedMoments(for: destination, in: zoomMomentsPool),
                namespace: zoomNamespace
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedProfileUserId != nil },
            set: { if !$0 { selectedProfileUserId = nil } }
        )) {
            if let selectedProfileUserId {
                UserProfileView(userId: selectedProfileUserId)
            }
        }
        .alert(item: $pendingSelectionConfirmation) { action in
            selectionConfirmationAlert(for: action)
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            resetSelectionState()
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
    }

    private var contentArea: some View {
        Group {
            if viewModel.isLoading && filteredReactionItems.isEmpty && filteredCommentItems.isEmpty {
                ProgressView(NSLocalizedString("userActivity.loading", comment: "Loading activity"))
                    .tint(primaryTextColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage,
                      filteredReactionItems.isEmpty && filteredCommentItems.isEmpty {
                errorStateView(errorMessage: errorMessage)
            } else {
                switch viewModel.category {
                case .comments:
                    commentsList
                case .reactions, .tags:
                    reactionsGrid
                }
            }
        }
    }

    private var reactionsGrid: some View {
        GeometryReader { geometry in
            if filteredReactionItems.isEmpty {
                emptyStateView
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
                let side = floor((geometry.size.width - 2) / 3)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(filteredReactionItems) { item in
                            Button {
                                if isSelectionMode {
                                    toggleReactionSelection(for: item.id)
                                    return
                                }
                                guard let moment = item.moment, item.canView else { return }
                                openMomentZoom(moment: moment)
                            } label: {
                                sharedMomentThumbnail(
                                    moment: item.moment,
                                    size: side,
                                    reactionType: viewModel.category == .reactions ? item.reactionType : nil,
                                    canView: item.canView,
                                    isSelected: selectedReactionIds.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                    guard !isSelectionMode else { return }
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                        isSelectionMode = true
                                        selectedReactionIds.insert(item.id)
                                    }
                                }
                            )
                        }

                        if viewModel.hasMore {
                            Color.clear
                                .frame(height: 50)
                                .onAppear {
                                    viewModel.loadNextPage()
                                }
                        }
                    }
                }
            }
        }
    }

    private var commentsList: some View {
        Group {
            if filteredCommentItems.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredCommentItems) { item in
                            SharedActivityCommentRow(
                                item: item,
                                commentLabelText: commentLabelText,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedCommentIds.contains(item.id),
                                onOpenMoment: {
                                    if isSelectionMode {
                                        toggleCommentSelection(for: item.id)
                                        return
                                    }
                                    guard item.canView, let moment = item.moment else { return }
                                    openMomentZoom(moment: moment)
                                },
                                onOpenAuthor: {
                                    if isSelectionMode {
                                        toggleCommentSelection(for: item.id)
                                        return
                                    }
                                    openProfile(userId: item.authorId)
                                },
                                onToggleSelection: {
                                    toggleCommentSelection(for: item.id)
                                }
                            )
                            .onLongPressGesture(minimumDuration: 0.35) {
                                guard !isSelectionMode else { return }
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                    isSelectionMode = true
                                    selectedCommentIds.insert(item.id)
                                }
                            }
                        }

                        if viewModel.hasMore {
                            ProgressView()
                                .padding(.vertical, 12)
                                .onAppear {
                                    viewModel.loadNextPage()
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var selectionBottomInset: some View {
        Group {
            if isSelectionMode {
                switch viewModel.category {
                case .comments:
                    commentsSelectionBar
                case .reactions, .tags:
                    reactionsSelectionBar
                }
            }
        }
    }

    private var selectionToastOverlay: some View {
        VStack(spacing: 10) {
            if let bannerKey = selectionSuccessBannerKey {
                selectionSuccessBanner(textKey: bannerKey)
            } else if isProcessingSelectionAction {
                processingBanner(
                    titleKey: processingTitleKey,
                    subtitleKey: "userActivity.simple.recentlyDeleted.processing.subtitle"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, isSelectionMode ? 84 : 20)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: selectionSuccessBannerKey), value: selectionSuccessBannerKey)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isProcessingSelectionAction), value: isProcessingSelectionAction)
    }

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ReactionsSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Text(NSLocalizedString(option.titleKey, comment: "Sort option"))
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.sort", comment: "Sort filter title"),
                        value: NSLocalizedString(sortOption.titleKey, comment: "Selected sort option")
                    )
                }

                Menu {
                    ForEach(ReactionsDateFilter.allCases) { option in
                        Button {
                            dateFilter = option
                        } label: {
                            HStack {
                                Text(NSLocalizedString(option.titleKey, comment: "Date filter option"))
                                if dateFilter == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.date", comment: "Date filter title"),
                        value: NSLocalizedString(dateFilter.titleKey, comment: "Selected date filter")
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    private func filterChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(secondaryTextColor)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(primaryTextColor)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(primaryTextColor.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.06))
        )
        .overlay(
            Capsule()
                .stroke(Color(colorScheme == .dark ? .white : .black).opacity(0.08), lineWidth: 0.8)
        )
    }

    private var reactionsSelectionBar: some View {
        let selectedCount = selectedReactionIds.count
        let isTagsCategory = viewModel.category == .tags

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack {
                Spacer()
                Button {
                    pendingSelectionConfirmation = isTagsCategory ? .tagsRemove : .reactionsDelete
                } label: {
                    HStack(spacing: 6) {
                        if isTagsCategory ? isRemovingSelectedTags : isDeletingSelectedReactions {
                            ProgressView()
                                .tint(.red)
                                .scaleEffect(0.8)
                        }
                        Text(reactionsSelectionButtonTitle(selectedCount: selectedCount, isTagsCategory: isTagsCategory))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(selectedCount > 0 ? 0.95 : 0.45))
                }
                .disabled(selectedCount == 0 || (isTagsCategory ? isRemovingSelectedTags : isDeletingSelectedReactions))
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var commentsSelectionBar: some View {
        let selectedCount = selectedCommentIds.count

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack {
                Spacer()
                Button {
                    pendingSelectionConfirmation = .commentsDelete
                } label: {
                    HStack(spacing: 6) {
                        if isDeletingSelectedComments {
                            ProgressView()
                                .tint(.red)
                                .scaleEffect(0.8)
                        }

                        Text(commentsSelectionButtonTitle(selectedCount: selectedCount))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(selectedCount > 0 ? 0.95 : 0.45))
                }
                .disabled(selectedCount == 0 || isDeletingSelectedComments)
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var customDateRangeControls: some View {
        HStack(spacing: 10) {
            DatePicker("", selection: $customDateFrom, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            DatePicker("", selection: $customDateTo, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var filteredReactionItems: [ActivityReactionItem] {
        let filteredByDate = viewModel.reactionItems.filter { item in
            matches(date: item.reactedAt)
        }
        switch sortOption {
        case .newest:
            return filteredByDate.sorted { $0.reactedAt > $1.reactedAt }
        case .oldest:
            return filteredByDate.sorted { $0.reactedAt < $1.reactedAt }
        }
    }

    private var filteredCommentItems: [ActivityCommentItem] {
        let filteredByDate = viewModel.commentItems.filter { item in
            matches(date: item.commentedAt)
        }
        switch sortOption {
        case .newest:
            return filteredByDate.sorted { $0.commentedAt > $1.commentedAt }
        case .oldest:
            return filteredByDate.sorted { $0.commentedAt < $1.commentedAt }
        }
    }

    private func matches(date: Date) -> Bool {
        switch dateFilter {
        case .all:
            return true
        case .week:
            let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            return date >= from
        case .month:
            let from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? .distantPast
            return date >= from
        case .year:
            let from = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
            return date >= from
        case .custom:
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
            let endBase = max(customDateFrom, customDateTo)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase
            return date >= start && date <= end
        }
    }

    private var commentLabelText: String {
        if viewModel.selectedTab == 0 {
            return NSLocalizedString("sharedActivity.comment.yours", value: "Tu comentario", comment: "")
        }
        return String(format: NSLocalizedString("sharedActivity.comment.fromUser", value: "Comentario de %@", comment: ""), viewModel.otherUser.username)
    }

    @ViewBuilder
    private func sharedMomentThumbnail(moment: Moment?, size: CGFloat, reactionType: String?, canView: Bool, isSelected: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ActivityCommentMomentPreview(moment: moment, canView: canView, size: size)

            if let moment, moment.isCarouselMoment, canView {
                VStack {
                    HStack {
                        MomentCarouselIndicatorIcon(size: 16)
                            .padding(6)
                        Spacer()
                    }
                    Spacer()
                }
            }

            if let reactionType, !reactionType.isEmpty, canView {
                Text(reactionIcon(for: reactionType))
                    .font(.system(size: 16))
                    .padding(6)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }

            if isSelectionMode {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(isSelected ? Color(hex: "2563EB") : .white.opacity(0.95))
                            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                            .padding(8)
                    }
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(isSelected ? Color.black.opacity(0.16) : Color.clear)
                )
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private func reactionIcon(for type: String) -> String {
        let normalized = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "heart" || normalized == "like" {
            return "❤️"
        }
        if let reactionType = ReactionType(rawValue: normalized) {
            return reactionType.icon
        }
        switch normalized {
        case "vibe": return "✌🏻"
        case "fire": return "🔥"
        case "real": return "✅"
        case "mood": return "😊"
        case "glow": return "✨"
        case "feel": return "❤️"
        case "love": return "💕"
        case "wow": return "😮"
        case "laugh": return "😂"
        case "cry": return "😢"
        case "respect": return "🙏🏻"
        case "power": return "⚡"
        case "genius": return "🧠"
        case "creative": return "🧠"
        case "chill": return "😎"
        case "hype": return "🚀"
        default: return "✨"
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Group {
                if viewModel.category == .reactions {
                    AnimatedReactionIcon()
                        .scaleEffect(1.35)
                } else if viewModel.category == .comments {
                    AttachmentIconView(icon: .comments, preset: .activityEmptyState, tintColor: viewModel.category.accentColor)
                        .scaleEffect(1.35)
                } else {
                    AttachmentIconView(icon: .tagged, preset: .activityEmptyState, tintColor: viewModel.category.accentColor)
                        .scaleEffect(1.35)
                }
            }
            .frame(height: 50)

            Text(NSLocalizedString("savedMoments.noResults.title", value: "No hay resultados", comment: ""))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(primaryTextColor)

            Text(emptyStateDescription)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(0.75)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    private var emptyStateDescription: String {
        let username = viewModel.otherUser.username
        if viewModel.selectedTab == 0 {
            switch viewModel.category {
            case .reactions:
                return String(format: NSLocalizedString("sharedActivity.empty.yourReactions", value: "Las reacciones que dejes en los momentos de %@ aparecerán aquí.", comment: ""), username)
            case .comments:
                return String(format: NSLocalizedString("sharedActivity.empty.yourComments", value: "Los comentarios que dejes en los momentos de %@ aparecerán aquí.", comment: ""), username)
            case .tags:
                return String(format: NSLocalizedString("sharedActivity.empty.yourTags", value: "Los momentos que publiques donde etiquetes a %@ aparecerán aquí.", comment: ""), username)
            }
        } else {
            switch viewModel.category {
            case .reactions:
                return String(format: NSLocalizedString("sharedActivity.empty.theirReactions", value: "Las reacciones de %@ en tus momentos aparecerán aquí.", comment: ""), username)
            case .comments:
                return String(format: NSLocalizedString("sharedActivity.empty.theirComments", value: "Los comentarios de %@ en tus momentos aparecerán aquí.", comment: ""), username)
            case .tags:
                return String(format: NSLocalizedString("sharedActivity.empty.theirTags", value: "Los momentos publicados por %@ donde estés etiquetado aparecerán aquí.", comment: ""), username)
            }
        }
    }

    @ViewBuilder
    private func errorStateView(errorMessage: String) -> some View {
        VStack(spacing: 12) {
            Text("⚠️")
                .font(.system(size: 42))

            Text(NSLocalizedString("userActivity.error.generic.title", comment: "Error title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(primaryTextColor)

            Text(errorMessage)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: { viewModel.reload() }) {
                Text(NSLocalizedString("userActivity.simple.retry", comment: "Retry activity load"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: "007AFF")))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openMomentZoom(moment: Moment) {
        zoomMomentsPool = [moment]
        MomentZoomOpener.open(
            moment: moment,
            moments: [moment],
            initialIndex: 0,
            presentation: .single,
            destination: &zoomDestination,
            zoomIDPrefix: "shared-activity",
            chromeTitle: viewModel.category.title
        )
    }

    private func openProfile(userId: String) {
        selectedProfileUserId = userId
    }

    private var isProcessingSelectionAction: Bool {
        isDeletingSelectedReactions || isDeletingSelectedComments || isRemovingSelectedTags
    }

    private var processingTitleKey: String {
        switch viewModel.category {
        case .reactions:
            return "userActivity.simple.reactions.delete.multiple"
        case .comments:
            return "userActivity.simple.comments.delete.multiple"
        case .tags:
            return "userActivity.simple.tags.remove.multiple"
        }
    }

    private func handleSelectionToolbarTap() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            isSelectionMode.toggle()
            if !isSelectionMode {
                resetSelectionState()
            }
        }
    }

    private func resetSelectionState() {
        isSelectionMode = false
        selectedReactionIds.removeAll()
        selectedCommentIds.removeAll()
    }

    private func toggleReactionSelection(for reactionId: String) {
        if selectedReactionIds.contains(reactionId) {
            selectedReactionIds.remove(reactionId)
        } else {
            selectedReactionIds.insert(reactionId)
        }
    }

    private func toggleCommentSelection(for commentId: String) {
        if selectedCommentIds.contains(commentId) {
            selectedCommentIds.remove(commentId)
        } else {
            selectedCommentIds.insert(commentId)
        }
    }

    private func reactionsSelectionButtonTitle(selectedCount: Int, isTagsCategory: Bool) -> String {
        if isTagsCategory {
            if selectedCount > 0 {
                return String(format: NSLocalizedString("sharedActivity.selection.tags.suppress.count", value: "Suprimir (%d)", comment: "Suppress selected tags"), selectedCount)
            }
            return NSLocalizedString("sharedActivity.selection.tags.suppress", value: "Suprimir", comment: "Suppress tags")
        }

        if selectedCount == 1 {
            return NSLocalizedString("sharedActivity.selection.reactions.delete.single", value: "Eliminar reacción", comment: "Delete one reaction")
        }
        if selectedCount > 1 {
            return String(format: NSLocalizedString("sharedActivity.selection.reactions.delete.multiple", value: "Eliminar reacciones (%d)", comment: "Delete multiple reactions"), selectedCount)
        }
        return NSLocalizedString("sharedActivity.selection.reactions.delete.base", value: "Eliminar reacción", comment: "Delete reaction")
    }

    private func commentsSelectionButtonTitle(selectedCount: Int) -> String {
        if selectedCount > 0 {
            return String(format: NSLocalizedString("sharedActivity.selection.comments.delete.count", value: "Eliminar (%d)", comment: "Delete selected comments"), selectedCount)
        }
        return NSLocalizedString("sharedActivity.selection.comments.delete.base", value: "Eliminar", comment: "Delete comments")
    }

    private func selectionSuccessBanner(textKey: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "22C55E"))

            Text(NSLocalizedString(textKey, comment: "Selection success banner"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 16, y: 6)
    }

    private func processingBanner(titleKey: String, subtitleKey: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(primaryTextColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(titleKey, comment: "Processing title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryTextColor)

                Text(NSLocalizedString(subtitleKey, comment: "Processing subtitle"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.gray)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 16, y: 6)
    }

    private func showSelectionSuccessBanner(_ textKey: String) {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
            selectionSuccessBannerKey = textKey
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard selectionSuccessBannerKey == textKey else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    selectionSuccessBannerKey = nil
                }
            }
        }
    }

    private func selectionConfirmationAlert(for action: SharedActivitySelectionConfirmationAction) -> Alert {
        switch action {
        case .reactionsDelete:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.reactions.confirm.delete.title", comment: "Reactions delete confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.reactions.confirm.delete.message", comment: "Reactions delete confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.reactions.delete.single", comment: "Delete reaction")),
                    action: { Task { await deleteSelectedReactions() } }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .commentsDelete:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.comments.confirm.delete.title", comment: "Comments delete confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.comments.confirm.delete.message", comment: "Comments delete confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.comments.delete.single", comment: "Delete comment")),
                    action: { Task { await deleteSelectedComments() } }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .tagsRemove:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.tags.confirm.remove.title", comment: "Tags remove confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.tags.confirm.remove.message", comment: "Tags remove confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.tags.remove.single", comment: "Remove tag")),
                    action: { Task { await removeSelectedTags() } }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        }
    }

    private func deleteSelectedReactions() async {
        guard !selectedReactionIds.isEmpty else { return }
        isDeletingSelectedReactions = true
        let idsToDelete = selectedReactionIds
        let result = await viewModel.removeReactions(withIds: idsToDelete)

        await MainActor.run {
            isDeletingSelectedReactions = false
            switch result {
            case .success:
                selectedReactionIds.removeAll()
                isSelectionMode = false
                showSelectionSuccessBanner("userActivity.simple.reactions.success.delete")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelectedComments() async {
        guard !selectedCommentIds.isEmpty else { return }
        isDeletingSelectedComments = true
        let idsToDelete = selectedCommentIds
        let result = await viewModel.removeComments(withIds: idsToDelete)

        await MainActor.run {
            isDeletingSelectedComments = false
            switch result {
            case .success:
                selectedCommentIds.removeAll()
                isSelectionMode = false
                showSelectionSuccessBanner("userActivity.simple.comments.success.delete")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func removeSelectedTags() async {
        guard !selectedReactionIds.isEmpty else { return }
        isRemovingSelectedTags = true
        let idsToDelete = selectedReactionIds
        let result = await viewModel.removeTags(withIds: idsToDelete)

        await MainActor.run {
            isRemovingSelectedTags = false
            switch result {
            case .success:
                selectedReactionIds.removeAll()
                isSelectionMode = false
                showSelectionSuccessBanner("userActivity.simple.tags.success.remove")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

private enum SharedActivitySelectionConfirmationAction: Identifiable {
    case reactionsDelete
    case commentsDelete
    case tagsRemove

    var id: Int {
        switch self {
        case .reactionsDelete: return 1
        case .commentsDelete: return 2
        case .tagsRemove: return 3
        }
    }
}

private struct SharedActivityCommentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityCommentItem
    let commentLabelText: String
    let isSelectionMode: Bool
    let isSelected: Bool
    let onOpenMoment: () -> Void
    let onOpenAuthor: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpenMoment) {
                ActivityCommentMomentPreview(moment: item.moment, canView: item.canView, size: 84)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onOpenAuthor) {
                    Text(item.moment?.username ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Text(item.moment?.content.isEmpty == false
                     ? (item.moment?.content ?? "")
                     : NSLocalizedString("userActivity.simple.comments.momentNoContent", comment: "Moment without content"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
                    .lineLimit(2)

                Text(commentLabelText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.82))

                Text(item.commentText.isEmpty
                     ? NSLocalizedString("userActivity.simple.comments.emptyComment", comment: "Empty comment fallback")
                     : item.commentText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(3)

                Text(item.commentedAt.timeAgoDisplay())
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.gray.opacity(0.85))
            }

            Spacer(minLength: 0)

            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            } else {
                StoryRingAvatarView(
                    userId: item.authorId,
                    size: 30,
                    lineWidth: 2.2,
                    onTap: { _ in
                        onOpenAuthor()
                    }
                )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color(hex: "2563EB") : Color.clear, lineWidth: 1.6)
                )
        )
    }
}

struct SharedActivityUnderlineTabBar: View {
    let tabTitles: [String]
    @Binding var selectedIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<tabTitles.count, id: \.self) { index in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex = index
                        }
                    }) {
                        Text(tabTitles[index])
                            .font(.system(size: 14, weight: selectedIndex == index ? .semibold : .regular))
                            .foregroundStyle(selectedIndex == index ? primaryTextColor : secondaryTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(dividerColor)
                    .frame(maxWidth: .infinity, maxHeight: 0.5)

                GeometryReader { geometry in
                    let tabCount = CGFloat(tabTitles.count)
                    let tabWidth = geometry.size.width / tabCount

                    Rectangle()
                        .fill(primaryTextColor)
                        .frame(width: tabWidth, height: 1.5)
                        .offset(x: tabWidth * CGFloat(selectedIndex))
                        .animation(.easeInOut(duration: 0.2), value: selectedIndex)
                }
                .frame(height: 1.5)
            }
            .frame(height: 1.5)
        }
    }
}

enum SharedActivityCategory: String, CaseIterable, Identifiable {
    case reactions
    case comments
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reactions:
            return NSLocalizedString("userActivity.simple.item.reactions.title", comment: "")
        case .comments:
            return NSLocalizedString("comments.title", comment: "")
        case .tags:
            return NSLocalizedString("editMoment.tags.title", comment: "")
        }
    }

    var accentColor: Color {
        switch self {
        case .reactions: return Color(hex: "F97316")
        case .comments: return Color(hex: "3B82F6")
        case .tags: return Color(hex: "EC4899")
        }
    }
}
