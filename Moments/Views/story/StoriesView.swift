import SwiftUI
import FirebaseAuth

// MARK: - StoriesView
struct StoriesView: View {
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

    // Variables para controlar anuncios
    @State private var otherUsersStoryCount: Int = 0
    @State private var adStoryCount: Int = 1
    @State private var adStoryIndex: Int = 0
    @State private var totalStoriesViewed: Int = 0

    // 🔗 STORY CHAINS: Variables para navegación entre partes
    @State private var chainStories: [Story] = []
    @State private var currentChainIndex: Int = 0
    @State private var isInChainMode: Bool = false
    private let chainModeUserId = "__chain__"


    @Binding var startWithUserId: String?
    let shouldIncludeConnections: Bool

    init() {
        self._startWithUserId = .constant(nil)
        self.shouldIncludeConnections = true
    }

    init(startWithUserId: Binding<String>) {
        self._startWithUserId = Binding(
            get: { startWithUserId.wrappedValue.isEmpty ? nil : startWithUserId.wrappedValue },
            set: { _ in }
        )
        self.shouldIncludeConnections = false
    }

    // 🔗 STORY CHAINS: Inicializador para cadenas de historias
    init(chainStories: [Story], startAtIndex: Int = 0) {
        self._startWithUserId = .constant(nil)
        self.shouldIncludeConnections = false
        self._chainStories = State(initialValue: chainStories)
        self._currentChainIndex = State(initialValue: startAtIndex)
        self._isInChainMode = State(initialValue: true)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if let error = errorMessage {
                GlassmorphicEmptyState(
                    icon: "exclamationmark.triangle",
                    message: error,
                    showCloseButton: true,
                    onClose: { dismiss() }
                )
            } else if userIds.isEmpty || storyViewModel.stories.isEmpty {
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

            } else if currentUserIndex < userIds.count,
                      let userId = userIds[safe: currentUserIndex],
                      let stories = storyViewModel.stories[userId],
                      !stories.isEmpty,
                      currentStoryIndex < stories.count,
                      let story = stories[safe: currentStoryIndex] {

                StoryViewerScreen(
                    story: story,
                    storyCount: stories.count,
                    storyIndex: currentStoryIndex,
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
                        handleStoryNext(currentUserId: Auth.auth().currentUser?.uid,
                                      viewedUserId: isInChainMode ? story.authorId : userId)
                    },
                    onStoryDeleted: {
                        handleStoryDeleted(story, fallbackUserId: userId)
                    },
                    onPrevious: {
                        if currentStoryIndex > 0 {
                            currentStoryIndex -= 1
                        } else {
                            moveToPreviousUser()
                        }
                    },
                    onClose: {
                        dismiss()
                    },
                    onProfileTap: {
                        // Handle profile tap
                    }
                )
            } else {
                GlassmorphicEmptyState(
                    icon: "exclamationmark.triangle",
                    message: NSLocalizedString("stories.errorLoadingStory", comment: "Error loading story"),
                    showCloseButton: true,
                    onClose: { dismiss() }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .all) // ✅ Ignorar keyboard en StoriesView
        .ignoresSafeArea(.container, edges: .all) // ✅ Por si acaso
        .statusBar(hidden: false)
        .onAppear {
            loadStories()
            preloadAdOnAppear()
        }
        .onReceive(storyViewModel.$stories) { stories in
            // 🔗 STORY CHAINS: Solo actualizar si NO estamos en modo cadena
            if !isInChainMode {
                updateUserIds(from: stories)
            }
        }
        .onChange(of: startWithUserId) { _, newUserId in
            // 🔗 STORY CHAINS: Solo cargar si NO estamos en modo cadena
            if !isInChainMode, let userId = newUserId, !userId.isEmpty {
                loadStories()
            }
        }
        // 🔗 STORY CHAINS: Listener para navegación entre partes
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToChainStory"))) { notification in
            if let userInfo = notification.userInfo,
               let storyId = userInfo["storyId"] as? String,
               let chainIndex = userInfo["chainIndex"] as? Int {
                navigateToChainStory(storyId: storyId, chainIndex: chainIndex)
            }
        }
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

    // Precargar anuncio
    private func preloadAdOnAppear() {
        if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AdMobConfiguration.shared.preloadNativeAd()
            }
        }
    }

    // Manejar navegación de historias
    private func handleStoryNext(currentUserId: String?, viewedUserId: String) {
        guard let currentUserId = currentUserId else {
            moveToNextStoryOrUser()
            return
        }

        totalStoriesViewed += 1

        // Solo contar si NO es historia propia
        if viewedUserId != currentUserId {
            otherUsersStoryCount += 1

            // Verificar si debe mostrar anuncio
            if shouldShowStoryAd() {
                activateAdWithLoading()
                return
            }
        }

        // 🔗 STORY CHAINS: En modo cadena, navegar por índice global de la cadena
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

    // Activar anuncio con loading inmediato
    private func activateAdWithLoading() {
        adStoryCount = 1
        adStoryIndex = 0

        DispatchQueue.main.async {
            self.showAd = true
        }
    }

    // Verificar si debe mostrar anuncio
    private func shouldShowStoryAd() -> Bool {
        let shouldShow = (otherUsersStoryCount % 4 == 0) &&
                        otherUsersStoryCount > 0 &&
                        PlusStatusHelper.shouldShowAds(for: authService.currentUser)

        return shouldShow
    }

    // Bloquear usuario confirmado
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

    // Cargar historias
    private func loadStories() {
        // 🔗 STORY CHAINS: Si estamos en modo cadena, usar las historias de la cadena
        if isInChainMode && !chainStories.isEmpty {
            // Modo cadena: un único carrusel ordenado por chainPosition (no por autor).
            // Evita desalineaciones de índice al tocar "parte 1/2/3..." en el sheet.
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

        if let specificUserId = startWithUserId, !specificUserId.isEmpty {
            storyViewModel.fetchStoriesForSpecificUser(userId: specificUserId, viewerId: currentUserId)
        } else {
            storyViewModel.fetchStories(for: currentUserId, includeConnections: shouldIncludeConnections)
        }
    }

    // Actualizar IDs de usuarios
    private func updateUserIds(from stories: [String: [Story]]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        DispatchQueue.main.async {
            if let specificUserId = self.startWithUserId, !specificUserId.isEmpty {
                self.userIds = stories.keys.contains(specificUserId) ? [specificUserId] : []
                self.currentUserIndex = 0

                // ✅ CORREGIDO: Si es otro usuario, empezar en la primera historia no vista
                // Necesitamos verificar los viewers directamente desde Firestore
                if let userStories = stories[specificUserId] {
                    self.getFirstUnseenStoryIndexAsync(for: userStories, userId: specificUserId) { index in
                        DispatchQueue.main.async {
                            self.currentStoryIndex = index
                            self.isLoading = false
                        }
                    }
                    return // Salir temprano, isLoading se establecerá en el callback
                }
            } else {
                // ✅ EXPERIMENTAL AFFINITY SORTING FOR STORIES UI
                // Use the affinity-sorted IDs from the view model if available
                var newUserIds: [String] = []
                if !self.storyViewModel.sortedStoryUserIds.isEmpty {
                    // Make sure we only use IDs that actually have stories in the current dict
                    newUserIds = self.storyViewModel.sortedStoryUserIds.filter { stories.keys.contains($0) }
                } else {
                    newUserIds = stories.keys.sorted()
                }

                self.userIds = newUserIds

                if !newUserIds.isEmpty {
                    if let index = newUserIds.firstIndex(of: currentUserId) {
                        self.currentUserIndex = index
                    } else {
                        self.currentUserIndex = 0
                    }
                }
            }

            // ✅ CORREGIDO: Solo resetear currentStoryIndex si NO es usuario específico
            if self.startWithUserId == nil || self.startWithUserId?.isEmpty == true {
                self.currentStoryIndex = 0
            }

            self.isLoading = false

            // Reset contadores al cargar nuevas historias
            self.otherUsersStoryCount = 0
            self.totalStoriesViewed = 0
        }
    }

    // Mover a siguiente historia o usuario
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

        let remainingUserIds = userIds.filter { userId in
            !(storyViewModel.stories[userId]?.isEmpty ?? true)
        }

        guard !remainingUserIds.isEmpty else {
            dismiss()
            return
        }

        userIds = remainingUserIds
        currentUserIndex = min(currentUserIndex, remainingUserIds.count - 1)
        currentStoryIndex = 0
    }

    // Mover a siguiente usuario
    private func moveToNextUser() {
        if let _ = startWithUserId {
            dismiss()
        } else {
            if currentUserIndex < userIds.count - 1 {
                currentUserIndex += 1
                currentStoryIndex = 0
            } else {
                dismiss()
            }
        }
    }

    // Mover a usuario anterior
    private func moveToPreviousUser() {
        if let _ = startWithUserId {
            currentStoryIndex = 0
        } else {
            if currentUserIndex > 0 {
                currentUserIndex -= 1
                currentStoryIndex = 0
            } else {
                currentStoryIndex = 0
            }
        }
    }

    // ✅ CORREGIDO: Obtener índice de la primera historia no vista (versión asíncrona que verifica desde Firestore)
    private func getFirstUnseenStoryIndexAsync(for stories: [Story], userId: String, completion: @escaping (Int) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(0)
            return
        }

        // Si no hay historias, empezar desde 0
        guard !stories.isEmpty else {
            completion(0)
            return
        }

        // Verificar viewers para cada historia en orden
        let group = DispatchGroup()
        var firstUnseenIndex: Int? = nil
        let syncQueue = DispatchQueue(label: "story.viewers.check")

        for (index, story) in stories.enumerated() {
            guard let storyId = story.id else { continue }

            group.enter()

            // Verificar directamente desde Firestore si el usuario ha visto esta historia
            firestoreService.db.collection("users").document(userId)
                .collection("stories").document(storyId)
                .collection("viewers").document(currentUserId)
                .getDocument { document, error in
                    let wasViewed = document?.exists == true

                    syncQueue.async {
                        // Si encontramos la primera no vista y aún no hemos encontrado ninguna, guardar este índice
                        if !wasViewed && firstUnseenIndex == nil {
                            firstUnseenIndex = index
                        }
                    }

                    group.leave()
                }
        }

        group.notify(queue: .main) {
            // Si encontramos una historia no vista, empezar ahí
            // Si todas están vistas, empezar desde el principio
            completion(firstUnseenIndex ?? 0)
        }
    }

    // ✅ Versión síncrona para cuando los viewers ya están cargados
    private func getFirstUnseenStoryIndex(for stories: [Story]) -> Int {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return 0 }

        // Buscar desde el principio hacia el final (primera no vista)
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

        // Si todas están vistas, empezar desde el principio
        return 0
    }

    // 🔗 STORY CHAINS: Navegar a una historia específica de la cadena
    private func navigateToChainStory(storyId: String, chainIndex: Int) {
        // Buscar la historia en todas las historias cargadas
        for (userId, stories) in storyViewModel.stories {
            if let storyIndex = stories.firstIndex(where: { $0.id == storyId }) {
                // Encontrar el usuario y actualizar índices
                if let userIndex = userIds.firstIndex(of: userId) {
                    currentUserIndex = userIndex
                    currentStoryIndex = storyIndex
                    currentChainIndex = chainIndex
                    isInChainMode = true

                    // Cargar todas las historias de la cadena si no están cargadas
                    if chainStories.isEmpty {
                        loadChainStories(for: stories[storyIndex])
                    }
                    return
                }
            }
        }
    }

    // 🔗 STORY CHAINS: Cargar todas las historias de una cadena
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

// MARK: - Array Extension for Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}
