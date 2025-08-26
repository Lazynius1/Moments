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
                // ✅ NUEVO: Usar anuncio integrado
                if let nativeAd = AdMobConfiguration.shared.getPreloadedNativeAd() {
                    IntegratedStoryAdView(
                        nativeAd: nativeAd,
                        storyCount: adStoryCount,
                        storyIndex: adStoryIndex,
                        progress: 0.0,
                        screenSize: UIScreen.main.bounds.size,
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
                        }
                    )
                } else {
                    // Fallback al anuncio original si no hay preloaded
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
                }
                
            } else if currentUserIndex < userIds.count,
                      let userId = userIds[safe: currentUserIndex],
                      let stories = storyViewModel.stories[userId],
                      !stories.isEmpty,
                      currentStoryIndex < stories.count,
                      let story = stories[safe: currentStoryIndex] {
                
                GlassmorphicStoryViewer(
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
                                      viewedUserId: userId)
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
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
        .onAppear {
            loadStories()
            preloadAdOnAppear()
        }
        .onReceive(storyViewModel.$stories) { stories in
            updateUserIds(from: stories)
        }
        .onChange(of: startWithUserId) { newUserId in
            if let userId = newUserId, !userId.isEmpty {
                loadStories()
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
            // ✅ AGREGAR DELAY PARA ASEGURAR CLEANUP DEL VIDEO ANTERIOR
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.moveToNextStoryOrUser()
            }
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
        
        // ✅ AGREGAR DELAY PARA ASEGURAR CLEANUP DEL VIDEO ANTERIOR
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.moveToNextStoryOrUser()
        }
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
        let shouldShow = (otherUsersStoryCount % 4 == 0) && // ANUNCIO CADA 4 HISTORIAS
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
                
                // ✅ CORREGIDO: Si es otro usuario, empezar en la última historia no vista (más reciente)
                if let userStories = stories[specificUserId] {
                    self.currentStoryIndex = self.getLastUnseenStoryIndex(for: userStories)
                }
            } else {
                let newUserIds = stories.keys.sorted()
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
        
        // ✅ AGREGAR DELAY PARA TRANSICIÓN SUAVE
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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
    
    // ✅ CORREGIDO: Obtener índice de la última historia no vista (más reciente)
    private func getLastUnseenStoryIndex(for stories: [Story]) -> Int {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return 0 }
        
        // Buscar desde el final (más reciente) hacia el principio
        for index in stride(from: stories.count - 1, through: 0, by: -1) {
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
}

// MARK: - Array Extension for Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}
