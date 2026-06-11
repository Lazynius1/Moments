import SwiftUI
import FirebaseAuth

// MARK: - StoriesView
struct StoriesView: View {
    private enum StoryLoadingMode: Equatable {
        case initial
        case author(String)
    }

    enum StoryLoadingOverlayState: Equatable {
        case loading
        case error(String)
    }

    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @StateObject private var storyViewModel = StoryViewModel()
    @State private var currentUserIndex: Int = 0
    @State private var currentStoryIndex: Int = 0
    @State private var userIds: [String] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false
    @State private var currentStory: Story?
    @State private var showAd: Bool = false
    @StateObject private var deckGestureGate = StoryDeckGestureGate()

    // Variables para controlar anuncios
    @State private var otherUsersStoryCount: Int = 0
    @State private var adStoryCount: Int = 1
    @State private var adStoryIndex: Int = 0
    @State private var totalStoriesViewed: Int = 0

    // 🔗 STORY CHAINS: Variables para navegación entre partes
    @State private var chainStories: [Story] = []
    @State private var currentChainIndex: Int = 0
    @State private var isInChainMode: Bool = false
    @State private var highlightTitle: String?
    private let chainModeUserId = "__chain__"

    @Binding var startWithUserId: String?
    let shouldIncludeConnections: Bool
    @State private var initialTargetUserId: String = ""
    @State private var hasResolvedInitialViewerPosition = false
    /// Orden fijado del anillo del feed (yo → …). No usar afinidad ni lista de following del VM.
    @State private var lockedRingNavigationUserIds: [String] = []
    @State private var pendingUnseenResolveUserId: String?
    @State private var loadingTimeoutWorkItem: DispatchWorkItem?
    @State private var loadingOverlayState: StoryLoadingOverlayState = .loading
    private let loadingTimeout: TimeInterval = 3.0

    init(ringNavigationUserIds: [String] = []) {
        self._startWithUserId = .constant(nil)
        self.shouldIncludeConnections = true
        self._lockedRingNavigationUserIds = State(initialValue: ringNavigationUserIds.filter { !$0.isEmpty })
    }

    init(startWithUserId: Binding<String>) {
        self._startWithUserId = Binding(
            get: { startWithUserId.wrappedValue.isEmpty ? nil : startWithUserId.wrappedValue },
            set: { _ in }
        )
        self.shouldIncludeConnections = false
    }

    // 🔗 STORY CHAINS: Inicializador para cadenas de historias
    init(chainStories: [Story], startAtIndex: Int = 0, highlightTitle: String? = nil) {
        self._startWithUserId = .constant(nil)
        self.shouldIncludeConnections = false
        self._chainStories = State(initialValue: chainStories)
        self._currentChainIndex = State(initialValue: startAtIndex)
        self._isInChainMode = State(initialValue: true)
        self._highlightTitle = State(initialValue: highlightTitle)
    }

    /// Carga todo el ring y empieza en `userId` (feed). Permite Deck Pass entre usuarios.
    init(startAtUserId: String, ringNavigationUserIds: [String] = []) {
        self._startWithUserId = .constant(nil)
        self.shouldIncludeConnections = true
        self._initialTargetUserId = State(initialValue: startAtUserId)
        self._lockedRingNavigationUserIds = State(initialValue: ringNavigationUserIds.filter { !$0.isEmpty })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                StoryViewerLoadingState(
                    state: loadingOverlayState,
                    onClose: { dismiss() }
                )
            } else if currentLoadingMode != nil {
                StoryViewerLoadingState(
                    state: loadingOverlayState,
                    onClose: { dismiss() }
                )
            } else if let error = errorMessage {
                GlassmorphicEmptyState(
                    icon: "exclamationmark.triangle",
                    message: error,
                    showCloseButton: true,
                    onClose: { dismiss() }
                )
            } else if userIds.isEmpty || (!shouldUseDeckPass && storyViewModel.stories.isEmpty) {
                GlassmorphicEmptyState(
                    icon: "photo.on.rectangle",
                    message: NSLocalizedString("stories.noStoriesAvailable", comment: "No stories available"),
                    showCloseButton: true,
                    onClose: { dismiss() }
                )
            } else if showAd {
                StoryNativeAdView(
                    onNext: {
                        showAd = false
                        moveToNextStoryOrUser()
                    },
                    onPrevious: {
                        showAd = false
                        if currentStoryIndex > 0 {
                            currentStoryIndex -= 1
                        } else {
                            moveToPreviousUser()
                        }
                    },
                    onClose: {
                        dismiss()
                    },
                    storyCount: adStoryCount,
                    storyIndex: adStoryIndex,
                    screenSize: UIScreen.main.bounds.size
                )
                .environmentObject(authService)

            } else if shouldUseDeckPass {
                StoryUserDeckPager(
                    userIds: userIds,
                    currentUserIndex: $currentUserIndex,
                    isDeckGestureEnabled: !deckGestureGate.suppressDeckNavigation,
                    onUserChanged: { newIndex in
                        applyStoryIndexForUser(at: newIndex)
                    },
                    content: { userId, role, isDraggingDeck in
                        storyViewerContent(
                            userId: userId,
                            isDeckPageActive: role == .center && !isDraggingDeck
                        )
                    }
                )
            } else if canRenderStoryViewer, let userId = userIds[safe: currentUserIndex] {
                storyViewerContent(userId: userId, isDeckPageActive: true)
            } else {
                GlassmorphicEmptyState(
                    icon: "exclamationmark.triangle",
                    message: NSLocalizedString("stories.errorLoadingStory", comment: "Error loading story"),
                    showCloseButton: true,
                    onClose: { dismiss() }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .all)
        .ignoresSafeArea(.container, edges: .all)
        .statusBar(hidden: false)
        .onAppear {
            loadStories()
            preloadAdOnAppear()
            updateLoadingTimeout(for: currentLoadingMode)
        }
        .onDisappear {
            loadingTimeoutWorkItem?.cancel()
            loadingTimeoutWorkItem = nil
        }
        .onReceive(storyViewModel.$stories) { stories in
            if !isInChainMode {
                updateUserIds(from: stories)
                resolvePendingUnseenIndexIfNeeded(using: stories)
            }
        }
        .onChange(of: currentUserIndex) { _, newIndex in
            prefetchNeighborStories(around: newIndex)
        }
        .onChange(of: currentLoadingMode) { _, newMode in
            updateLoadingTimeout(for: newMode)
        }
        .onChange(of: startWithUserId) { _, newUserId in
            if !isInChainMode, let userId = newUserId, !userId.isEmpty {
                loadStories()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToChainStory"))) { notification in
            if let userInfo = notification.userInfo,
               let storyId = userInfo["storyId"] as? String,
               let chainIndex = userInfo["chainIndex"] as? Int {
                navigateToChainStory(storyId: storyId, chainIndex: chainIndex)
            }
        }
        .environment(\.storyDeckGestureGate, deckGestureGate)
        .sheet(isPresented: $showingReportSheet) {
            if let story = currentStory {
                ReportBottomSheet(story: story)
            }
        }
        .alert(NSLocalizedString("stories.blockUser.title", comment: "Block user"), isPresented: $showingBlockConfirmation) {
            Button(NSLocalizedString("stories.blockUser.cancel", comment: "Cancel"), role: .cancel) { }
            Button(NSLocalizedString("stories.blockUser.confirm", comment: "Block"), role: .destructive) {
                blockUserConfirmed()
            }
        } message: {
            Text(NSLocalizedString("stories.blockUser.confirm", comment: "Block user confirmation message"))
        }
    }

    private var currentLoadingMode: StoryLoadingMode? {
        guard !isInChainMode, errorMessage == nil, !showAd else { return nil }

        if isLoading {
            return .initial
        }

        guard let currentUserId = userIds[safe: currentUserIndex],
              shouldShowLoadingState(for: currentUserId) else {
            return nil
        }

        return .author(currentUserId)
    }

    private var canRenderStoryViewer: Bool {
        guard let userId = userIds[safe: currentUserIndex],
              let stories = storyViewModel.stories[userId],
              !stories.isEmpty,
              currentStoryIndex < stories.count,
              stories[safe: currentStoryIndex] != nil else {
            return false
        }
        return true
    }

    private func shouldShowLoadingState(for userId: String) -> Bool {
        guard errorMessage == nil else { return false }
        if let stories = storyViewModel.stories[userId] {
            return stories.isEmpty
        }
        return true
    }

    /// Deck Pass cuando hay varios usuarios y no estamos en modo usuario único (chat, perfil, etc.).
    private var shouldUseDeckPass: Bool {
        !isInChainMode && isMultiUserRingMode && userIds.count > 1
    }

    private var isMultiUserRingMode: Bool {
        startWithUserId == nil || startWithUserId?.isEmpty == true
    }

    @ViewBuilder
    private func storyViewerContent(userId: String, isDeckPageActive: Bool) -> some View {
        if let stories = storyViewModel.stories[userId],
           !stories.isEmpty {
            let storyIndex = userId == userIds[safe: currentUserIndex]
                ? min(currentStoryIndex, stories.count - 1)
                : 0

            if let story = stories[safe: storyIndex] {
                StoryViewerScreen(
                    story: story,
                    storyCount: stories.count,
                    storyIndex: storyIndex,
                    screenSize: UIScreen.main.bounds.size,
                    storyViewModel: storyViewModel,
                    showingReportSheet: $showingReportSheet,
                    showingBlockConfirmation: $showingBlockConfirmation,
                    onReportStory: {
                        currentStory = story
                        showingReportSheet = true
                    },
                    onBlockUser: {
                        currentStory = story
                        showingBlockConfirmation = true
                    },
                    onNext: {
                        handleStoryNext(
                            currentUserId: Auth.auth().currentUser?.uid,
                            viewedUserId: isInChainMode ? story.authorId : userId
                        )
                    },
                    onStoryDeleted: {
                        handleStoryDeleted(story, fallbackUserId: userId)
                    },
                    onPrevious: {
                        if userId == userIds[safe: currentUserIndex], currentStoryIndex > 0 {
                            currentStoryIndex -= 1
                        } else if userId == userIds[safe: currentUserIndex] {
                            moveToPreviousUser()
                        }
                    },
                    onClose: {
                        dismiss()
                    },
                    onProfileTap: {},
                    isDeckPageActive: isDeckPageActive,
                    highlightTitle: highlightTitle
                )
            } else {
                Color.clear
            }
        } else {
            StoryViewerLoadingState(
                state: loadingOverlayState,
                onClose: { dismiss() }
            )
        }
    }

    private func updateLoadingTimeout(for mode: StoryLoadingMode?) {
        loadingTimeoutWorkItem?.cancel()
        loadingTimeoutWorkItem = nil
        loadingOverlayState = .loading

        guard let mode else { return }

        let workItem = DispatchWorkItem { [mode] in
            handleLoadingTimeout(for: mode)
        }
        loadingTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + loadingTimeout, execute: workItem)
    }

    private func handleLoadingTimeout(for mode: StoryLoadingMode) {
        guard currentLoadingMode == mode else { return }

        switch mode {
        case .initial:
            if attemptAdvanceToNextUserFromTimeout() {
                return
            }
            isLoading = false
            loadingOverlayState = .error(
                NSLocalizedString("stories.errorLoadingStory", comment: "Error loading story")
            )
        case .author(let userId):
            guard userIds[safe: currentUserIndex] == userId else { return }
            if attemptAdvanceToNextUserFromTimeout() {
                return
            }
            loadingOverlayState = .error(
                NSLocalizedString("stories.errorLoadingStory", comment: "Error loading story")
            )
        }
    }

    private func attemptAdvanceToNextUserFromTimeout() -> Bool {
        guard shouldUseDeckPass || isMultiUserRingMode else { return false }
        guard let nextIndex = nextTimeoutFallbackIndex(after: currentUserIndex) else { return false }

        errorMessage = nil
        loadingOverlayState = .loading
        isLoading = false
        currentUserIndex = nextIndex
        currentStoryIndex = 0
        applyStoryIndexForUser(at: nextIndex)
        return true
    }

    private func nextTimeoutFallbackIndex(after index: Int) -> Int? {
        guard userIds.count > 1 else { return nil }

        for candidateIndex in (index + 1)..<userIds.count {
            guard let userId = userIds[safe: candidateIndex] else { continue }
            if let stories = storyViewModel.stories[userId], !stories.isEmpty {
                return candidateIndex
            }
        }

        for candidateIndex in (index + 1)..<userIds.count {
            if userIds[safe: candidateIndex] != nil {
                return candidateIndex
            }
        }

        return nil
    }

    private func resolvedNavigationUserIds(from stories: [String: [Story]]) -> [String] {
        if !lockedRingNavigationUserIds.isEmpty {
            return lockedRingNavigationUserIds
        }
        if !storyViewModel.ringOrderedStoryUserIds.isEmpty {
            return storyViewModel.ringOrderedStoryUserIds
        }
        return stories.keys
            .filter { !(stories[$0]?.isEmpty ?? true) }
            .sorted()
    }

    private func applyStoryIndexForUser(at index: Int) {
        guard let userId = userIds[safe: index] else { return }

        prefetchNeighborStories(around: index)

        guard let viewerId = Auth.auth().currentUser?.uid else {
            currentStoryIndex = 0
            return
        }

        storyViewModel.mergeStoriesForUserIfNeeded(userId: userId, viewerId: viewerId)

        if let stories = storyViewModel.stories[userId], !stories.isEmpty {
            pendingUnseenResolveUserId = nil
            getFirstUnseenStoryIndexAsync(for: stories, userId: userId) { storyIndex in
                DispatchQueue.main.async {
                    self.currentStoryIndex = storyIndex
                }
            }
        } else {
            pendingUnseenResolveUserId = userId
            currentStoryIndex = 0
        }
    }

    private func resolvePendingUnseenIndexIfNeeded(using stories: [String: [Story]]) {
        guard let pendingUserId = pendingUnseenResolveUserId,
              pendingUserId == userIds[safe: currentUserIndex],
              let userStories = stories[pendingUserId],
              !userStories.isEmpty else { return }

        pendingUnseenResolveUserId = nil
        getFirstUnseenStoryIndexAsync(for: userStories, userId: pendingUserId) { storyIndex in
            DispatchQueue.main.async {
                self.currentStoryIndex = storyIndex
            }
        }
    }

    private func prefetchNeighborStories(around index: Int) {
        guard isMultiUserRingMode,
              let viewerId = Auth.auth().currentUser?.uid else { return }

        if let userId = userIds[safe: index] {
            storyViewModel.loadAuthorReelIfNeeded(authorId: userId, viewerId: viewerId)
        }

        for offset in [1, -1] {
            guard let userId = userIds[safe: index + offset] else { continue }
            storyViewModel.loadAuthorReelIfNeeded(authorId: userId, viewerId: viewerId)
        }
    }

    private func preloadAdOnAppear() {
        if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AdMobConfiguration.shared.preloadNativeAd()
            }
        }
    }

    private func handleStoryNext(currentUserId: String?, viewedUserId: String) {
        guard let currentUserId = currentUserId else {
            moveToNextStoryOrUser()
            return
        }

        totalStoriesViewed += 1

        if viewedUserId != currentUserId {
            otherUsersStoryCount += 1

            if shouldShowStoryAd() {
                activateAdWithLoading()
                return
            }
        }

        if isInChainMode && !chainStories.isEmpty {
            if currentChainIndex < chainStories.count - 1 {
                currentChainIndex += 1
                currentUserIndex = 0
                currentStoryIndex = currentChainIndex
                return
            } else {
                dismiss()
                return
            }
        }

        moveToNextStoryOrUser()
    }

    private func activateAdWithLoading() {
        adStoryCount = 1
        adStoryIndex = 0

        DispatchQueue.main.async {
            self.showAd = true
        }
    }

    private func shouldShowStoryAd() -> Bool {
        (otherUsersStoryCount % 4 == 0) &&
        otherUsersStoryCount > 0 &&
        PlusStatusHelper.shouldShowAds(for: authService.currentUser)
    }

    private func blockUserConfirmed() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let story = currentStory else { return }

        firestoreService.blockUser(
            currentUserId: currentUserId,
            targetUserId: story.authorId
        ) { error in
            if error == nil {
                DispatchQueue.main.async {
                    dismiss()
                }
            }
        }
    }

    private func loadStories() {
        errorMessage = nil
        loadingOverlayState = .loading

        if isInChainMode && !chainStories.isEmpty {
            let orderedChainStories = chainStories.sorted { lhs, rhs in
                let lp = lhs.chainPosition ?? Int.max
                let rp = rhs.chainPosition ?? Int.max
                if lp != rp { return lp < rp }
                return lhs.timestamp < rhs.timestamp
            }

            chainStories = orderedChainStories
            storyViewModel.stories = [chainModeUserId: orderedChainStories]
            userIds = [chainModeUserId]
            currentUserIndex = 0
            currentChainIndex = max(0, min(currentChainIndex, max(orderedChainStories.count - 1, 0)))
            currentStoryIndex = currentChainIndex
            isLoading = false
            return
        }

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            errorMessage = NSLocalizedString("stories.error.notAuthenticated", comment: "User not authenticated error")
            return
        }

        isLoading = true

        if !lockedRingNavigationUserIds.isEmpty {
            storyViewModel.setRingNavigationOrder(lockedRingNavigationUserIds)
        }

        if let specificUserId = startWithUserId, !specificUserId.isEmpty {
            userIds = [specificUserId]
            currentUserIndex = 0
            storyViewModel.loadAuthorReelIfNeeded(authorId: specificUserId, viewerId: currentUserId)
            isLoading = false
            return
        }

        if shouldIncludeConnections, !lockedRingNavigationUserIds.isEmpty {
            userIds = lockedRingNavigationUserIds
            let targetId: String = {
                if !initialTargetUserId.isEmpty { return initialTargetUserId }
                return lockedRingNavigationUserIds.first ?? currentUserId
            }()
            if let targetIndex = userIds.firstIndex(of: targetId) {
                currentUserIndex = targetIndex
            }
            storyViewModel.fetchStories(for: currentUserId, includeConnections: true)
            applyStoryIndexForUser(at: currentUserIndex)
            isLoading = false
            return
        }

        storyViewModel.fetchStories(for: currentUserId, includeConnections: shouldIncludeConnections)
    }

    private func updateUserIds(from stories: [String: [Story]]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        DispatchQueue.main.async {
            self.loadingOverlayState = .loading
            // Modo usuario único (chat, notificaciones, perfil…)
            if let specificUserId = self.startWithUserId, !specificUserId.isEmpty {
                self.userIds = [specificUserId]
                self.currentUserIndex = 0

                if let userStories = stories[specificUserId] {
                    self.getFirstUnseenStoryIndexAsync(for: userStories, userId: specificUserId) { index in
                        DispatchQueue.main.async {
                            self.currentStoryIndex = index
                            self.isLoading = false
                            self.loadingOverlayState = .loading
                        }
                    }
                    return
                }

                self.isLoading = !stories.keys.contains(specificUserId)
                return
            }

            let newUserIds = self.resolvedNavigationUserIds(from: stories)

            let previousActiveUserId = self.userIds[safe: self.currentUserIndex]

            // Feed / ring: esperar a que el usuario tocado tenga historias cargadas.
            if !self.initialTargetUserId.isEmpty {
                let targetUserId = self.initialTargetUserId
                guard let targetIndex = newUserIds.firstIndex(of: targetUserId),
                      let targetStories = stories[targetUserId],
                      !targetStories.isEmpty else {
                    self.userIds = newUserIds
                    self.isLoading = true
                    self.loadingOverlayState = .loading
                    return
                }

                self.initialTargetUserId = ""
                self.userIds = newUserIds
                self.currentUserIndex = targetIndex
                self.hasResolvedInitialViewerPosition = true
                self.prefetchNeighborStories(around: targetIndex)

                self.getFirstUnseenStoryIndexAsync(for: targetStories, userId: targetUserId) { index in
                    DispatchQueue.main.async {
                        self.currentStoryIndex = index
                        self.isLoading = false
                        self.loadingOverlayState = .loading
                        self.otherUsersStoryCount = 0
                        self.totalStoriesViewed = 0
                    }
                }
                return
            }

            self.userIds = newUserIds

            // Recargas mientras se navega: mantener el usuario activo.
            if self.hasResolvedInitialViewerPosition {
                if let previousActiveUserId,
                   let preservedIndex = newUserIds.firstIndex(of: previousActiveUserId) {
                    self.currentUserIndex = preservedIndex
                } else {
                    self.currentUserIndex = min(self.currentUserIndex, max(newUserIds.count - 1, 0))
                }
                return
            }

            // Ring completo sin target (StoriesView()).
            guard !newUserIds.isEmpty else {
                self.isLoading = false
                return
            }

            if let ownIndex = newUserIds.firstIndex(of: currentUserId) {
                self.currentUserIndex = ownIndex
            } else {
                self.currentUserIndex = 0
            }
            self.currentStoryIndex = 0
            self.hasResolvedInitialViewerPosition = true
            self.prefetchNeighborStories(around: self.currentUserIndex)
            self.isLoading = false
            self.loadingOverlayState = .loading
            self.otherUsersStoryCount = 0
            self.totalStoriesViewed = 0
        }
    }

    private func moveToNextStoryOrUser() {
        if let userId = self.userIds[safe: self.currentUserIndex],
           let stories = self.storyViewModel.stories[userId] {
            if self.currentStoryIndex < stories.count - 1 {
                self.currentStoryIndex += 1
            } else {
                self.moveToNextUser()
            }
        } else {
            self.dismiss()
        }
    }

    private func handleStoryDeleted(_ deletedStory: Story, fallbackUserId: String) {
        let activeUserId = isInChainMode ? chainModeUserId : fallbackUserId

        if isInChainMode {
            chainStories.removeAll { $0.id == deletedStory.id }
            storyViewModel.stories[chainModeUserId] = chainStories
            currentChainIndex = min(currentChainIndex, max(chainStories.count - 1, 0))
        }

        if let remainingStories = storyViewModel.stories[activeUserId], !remainingStories.isEmpty {
            currentStoryIndex = min(currentStoryIndex, remainingStories.count - 1)
            return
        }

        if isInChainMode {
            dismiss()
            return
        }

        let navigationOrder = lockedRingNavigationUserIds.isEmpty ? userIds : lockedRingNavigationUserIds
        let remainingUserIds = navigationOrder.filter { userId in
            !(storyViewModel.stories[userId]?.isEmpty ?? true)
        }

        guard !remainingUserIds.isEmpty else {
            dismiss()
            return
        }

        let previousActiveUserId = userIds[safe: currentUserIndex]
        userIds = remainingUserIds
        if let previousActiveUserId,
           let preservedIndex = remainingUserIds.firstIndex(of: previousActiveUserId) {
            currentUserIndex = preservedIndex
        } else {
            currentUserIndex = min(currentUserIndex, remainingUserIds.count - 1)
        }
        currentStoryIndex = 0
    }

    private func moveToNextUser() {
        if startWithUserId != nil {
            dismiss()
        } else if currentUserIndex < userIds.count - 1 {
            currentUserIndex += 1
            applyStoryIndexForUser(at: currentUserIndex)
        } else {
            dismiss()
        }
    }

    private func moveToPreviousUser() {
        if startWithUserId != nil {
            currentStoryIndex = 0
        } else if currentUserIndex > 0 {
            currentUserIndex -= 1
            applyStoryIndexForUser(at: currentUserIndex)
        } else {
            currentStoryIndex = 0
        }
    }

    private func getFirstUnseenStoryIndexAsync(for stories: [Story], userId: String, completion: @escaping (Int) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(0)
            return
        }

        guard !stories.isEmpty else {
            completion(0)
            return
        }

        let group = DispatchGroup()
        var firstUnseenIndex: Int?
        let syncQueue = DispatchQueue(label: "story.viewers.check")

        for (index, story) in stories.enumerated() {
            guard let storyId = story.id else { continue }

            group.enter()

            firestoreService.db.collection("users").document(userId)
                .collection("stories").document(storyId)
                .collection("viewers").document(currentUserId)
                .getDocument { document, _ in
                    let wasViewed = document?.exists == true

                    syncQueue.async {
                        if !wasViewed && firstUnseenIndex == nil {
                            firstUnseenIndex = index
                        }
                    }

                    group.leave()
                }
        }

        group.notify(queue: .main) {
            completion(firstUnseenIndex ?? 0)
        }
    }

    private func getFirstUnseenStoryIndex(for stories: [Story]) -> Int {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return 0 }

        for index in 0..<stories.count {
            let story = stories[index]
            if let storyId = story.id {
                let wasViewed = storyViewModel.storyViewers[storyId]?.contains { viewer in
                    viewer.userId == currentUserId
                } ?? false

                if !wasViewed {
                    return index
                }
            }
        }

        return 0
    }

    private func navigateToChainStory(storyId: String, chainIndex: Int) {
        for (userId, stories) in storyViewModel.stories {
            if let storyIndex = stories.firstIndex(where: { $0.id == storyId }) {
                if let userIndex = userIds.firstIndex(of: userId) {
                    currentUserIndex = userIndex
                    currentStoryIndex = storyIndex
                    currentChainIndex = chainIndex
                    isInChainMode = true

                    if chainStories.isEmpty {
                        loadChainStories(for: stories[storyIndex])
                    }
                    return
                }
            }
        }
    }

    private func loadChainStories(for story: Story) {
        guard let chainId = story.chainId else { return }

        Task {
            do {
                let storiesSnapshot = try await firestoreService.db
                    .collectionGroup("stories")
                    .whereField("chainId", isEqualTo: chainId)
                    .order(by: "chainPosition")
                    .getDocuments()

                let stories = storiesSnapshot.documents.compactMap { doc in
                    try? doc.data(as: Story.self)
                }

                await MainActor.run {
                    chainStories = stories
                }
            } catch {
                // Error loading chain stories
            }
        }
    }
}

private struct StoryViewerLoadingState: View {
    let state: StoriesView.StoryLoadingOverlayState
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var primaryChrome: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.82)
    }

    private var secondaryChrome: Color {
        colorScheme == .dark ? .white.opacity(0.16) : Color.black.opacity(0.10)
    }

    private var tertiaryChrome: Color {
        colorScheme == .dark ? .white.opacity(0.28) : Color.black.opacity(0.18)
    }

    private var spinnerTint: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.82)
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedTopInset = max(proxy.safeAreaInsets.top, keyWindowSafeAreaInsets().top)
            let resolvedBottomInset = max(proxy.safeAreaInsets.bottom, keyWindowSafeAreaInsets().bottom)
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topChrome
                        .padding(.top, resolvedTopInset + 18)
                        .padding(.horizontal, 12)

                    Spacer()

                    centerContent
                        .offset(y: -18)

                    Spacer()

                    bottomPlaceholder
                        .padding(.horizontal, 16)
                        .padding(.bottom, resolvedBottomInset + 8)
                }
            }
        }
    }

    private func keyWindowSafeAreaInsets() -> UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return keyWindow?.safeAreaInsets ?? .zero
    }

    @ViewBuilder
    private var centerContent: some View {
        switch state {
        case .loading:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: spinnerTint))
                .scaleEffect(1.35)
        case .error(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(primaryChrome.opacity(0.88))

                Text(message)
                    .font(.custom("Poppins-Medium", size: 18))
                    .foregroundColor(primaryChrome.opacity(0.88))
                    .multilineTextAlignment(.center)

                Button(action: onClose) {
                    Text(NSLocalizedString("common.close", comment: "Close"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(primaryChrome)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var topChrome: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index == 0 ? tertiaryChrome : secondaryChrome)
                        .frame(height: 3)
                }
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(secondaryChrome)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(tertiaryChrome)
                        .frame(width: 108, height: 11)

                    Capsule()
                        .fill(secondaryChrome)
                        .frame(width: 58, height: 9)
                }

                Spacer()

                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            .frame(width: 38, height: 38)

                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryChrome)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var bottomPlaceholder: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .frame(height: 46)
                .overlay(
                    HStack {
                        Capsule()
                            .fill(secondaryChrome)
                            .frame(width: 128, height: 11)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                )
        }
    }
}

// MARK: - Array Extension for Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}
