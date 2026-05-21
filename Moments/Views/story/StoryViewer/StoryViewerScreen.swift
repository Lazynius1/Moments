import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - Story Viewer Screen
struct StoryViewerScreen: View {
    let story: Story
    let storyCount: Int
    let storyIndex: Int
    let screenSize: CGSize
    let storyViewModel: StoryViewModel
    @Binding var showingReportSheet: Bool
    @Binding var showingBlockConfirmation: Bool
    let onReportStory: () -> Void
    let onBlockUser: () -> Void
    let onNext: () -> Void
    let onStoryDeleted: (() -> Void)?
    let onPrevious: () -> Void
    let onClose: () -> Void
    let onProfileTap: () -> Void

    init(
        story: Story,
        storyCount: Int,
        storyIndex: Int,
        screenSize: CGSize,
        storyViewModel: StoryViewModel,
        showingReportSheet: Binding<Bool>,
        showingBlockConfirmation: Binding<Bool>,
        onReportStory: @escaping () -> Void,
        onBlockUser: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onStoryDeleted: (() -> Void)? = nil,
        onPrevious: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onProfileTap: @escaping () -> Void
    ) {
        self.story = story
        self.storyCount = storyCount
        self.storyIndex = storyIndex
        self.screenSize = screenSize
        self.storyViewModel = storyViewModel
        self._showingReportSheet = showingReportSheet
        self._showingBlockConfirmation = showingBlockConfirmation
        self.onReportStory = onReportStory
        self.onBlockUser = onBlockUser
        self.onNext = onNext
        self.onStoryDeleted = onStoryDeleted
        self.onPrevious = onPrevious
        self.onClose = onClose
        self.onProfileTap = onProfileTap
    }

    @State private var showMomentDetail: Bool = false
    @State private var targetMomentId: String? = nil
    @State private var targetMomentUserId: String? = nil
    @State private var messageText: String = ""
    @State private var showReactions: Bool = false
    @State private var showEphemeralPicker: Bool = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showQuickActions: Bool = false
    @State private var showViewers: Bool = false
    @State private var showBestFriendsOptOutConfirmation: Bool = false
    @State private var showUnfollowConfirmation: Bool = false
    @State private var showMuteConfirmation: Bool = false
    @State private var isMenuInteractionActive: Bool = false
    @State private var menuAutoResumeWorkItem: DispatchWorkItem? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var showSuccessMessage: Bool = false
    @State private var canContinueChain: Bool = false
    @State private var successMessageText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyboardHeight: CGFloat = 0 // Track keyboard height
    @State private var isKeyboardVisible: Bool = false // Track keyboard state
    @State private var authorAllowsMessages: Bool = true
    @State private var authorAllowsReactions: Bool = true
    @State private var authorAllowsEphemeralPhotos: Bool = true
    @State private var storyStickers: [StickerItem] = [] // Cache de stickers
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""
    @State private var floatingHearts: [FloatingHeart] = [] // ✅ FLOATING HEARTS ANIMATION
    @State private var isUIHidden: Bool = false // ✅ IMMERSIVE MODE STATE
    @State private var gestureActionTriggered: Bool = false // ✅ UNIFIED GESTURE STATE
    @State private var isHoldingStory: Bool = false
    @State private var holdPauseWorkItem: DispatchWorkItem? = nil
    @State private var holdStartLocation: CGPoint? = nil
    @State private var suppressNavigationTapUntil: Date? = nil
    // ✅ SOLO ZOOM - Estados para pinch to zoom
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    // 🔗 STORY CHAINS - Variables para cadenas de historias
    @State private var showChainView: Bool = false
    @State private var selectedChainId: String = ""
    @State private var selectedChainTitle: String = ""
    @State private var selectedChainStoryId: String = ""
    @State private var selectedChainStoryPosition: Int = 1
    @State private var chainStories: [Story] = [] // Todas las historias de la cadena
    @State private var currentChainIndex: Int = 0 // Índice actual en la cadena
    @State private var isLoadingChainStories: Bool = false
    @StateObject private var playbackCoordinator = StoryPlaybackCoordinator()

    private let reactions: [String] = ["✌🏻", "🔥", "✅", "😊", "✨", "❤️", "💕", "😮", "😂", "😢", "🙏🏻", "⚡", "🧠", "🎨", "😌", "🎉"]

    private let firestoreService = FirestoreService()
    private let bestFriendsService = BestFriendsService()

    private var canOptOutFromAuthorBestFriends: Bool {
        guard story.authorId != Auth.auth().currentUser?.uid else { return false }
        let normalizedAudience = story.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? ""
        return normalizedAudience == "bestfriends"
    }

    private enum StoryConfirmationKind {
        case unfollow
        case mute
        case leaveBestFriends
    }

    private var activeStoryConfirmation: StoryConfirmationKind? {
        if showUnfollowConfirmation { return .unfollow }
        if showMuteConfirmation { return .mute }
        if showBestFriendsOptOutConfirmation { return .leaveBestFriends }
        return nil
    }

    private func confirmationTitle(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            let format = NSLocalizedString("storyContextMenu.unfollow.confirm.title", comment: "Unfollow confirmation title")
            return String(format: format, story.username)
        case .mute:
            let format = NSLocalizedString("storyContextMenu.mute.confirm.title", comment: "Mute confirmation title")
            return String(format: format, story.username)
        case .leaveBestFriends:
            let format = NSLocalizedString("bestFriends.optOut.confirm.title", comment: "Leave best friends title")
            return String(format: format, story.username)
        }
    }

    private func confirmationMessage(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            return NSLocalizedString("storyContextMenu.unfollow.confirm.message", comment: "Unfollow confirmation message")
        case .mute:
            return NSLocalizedString("storyContextMenu.mute.confirm.message", comment: "Mute confirmation message")
        case .leaveBestFriends:
            return NSLocalizedString("bestFriends.optOut.confirm.message", comment: "Leave best friends message")
        }
    }

    private func confirmationConfirmTitle(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            return NSLocalizedString("storyContextMenu.unfollow.confirm.action", comment: "Unfollow action")
        case .mute:
            return NSLocalizedString("storyContextMenu.mute.confirm.action", comment: "Mute action")
        case .leaveBestFriends:
            return NSLocalizedString("bestFriends.optOut.confirm.action", comment: "Leave best friends action")
        }
    }

    private func confirmationCancelTitle(for kind: StoryConfirmationKind) -> String {
        switch kind {
        case .unfollow:
            return NSLocalizedString("storyContextMenu.unfollow.confirm.cancel", comment: "Unfollow cancel")
        case .mute:
            return NSLocalizedString("storyContextMenu.mute.confirm.cancel", comment: "Mute cancel")
        case .leaveBestFriends:
            return NSLocalizedString("bestFriends.optOut.confirm.cancel", comment: "Leave best friends cancel")
        }
    }

    private var quickActionTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var quickActionDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private func clearAllStoryConfirmations() {
        showUnfollowConfirmation = false
        showMuteConfirmation = false
        showBestFriendsOptOutConfirmation = false
    }

    private func handleStoryConfirmation(_ kind: StoryConfirmationKind) {
        clearAllStoryConfirmations()
        switch kind {
        case .unfollow:
            unfollowStoryAuthor()
        case .mute:
            muteStoryAuthor()
        case .leaveBestFriends:
            optOutFromBestFriends()
        }
    }

    var body: some View {
        profileAndChainBoundView
    }

    @ViewBuilder
    private func geometryStackView(for geometry: GeometryProxy) -> some View {
        let revealSticker = storyStickers.first { $0.type == .reveal }

        ZStack {
            // MARK: - 1. CONTENIDO MULTIMEDIA (Fijo en el centro - NUNCA SE MUEVE)
            contentView
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            // MARK: - 2. STICKERS (Fijos en sus posiciones)
            if !storyStickers.isEmpty {
                ForEach(storyStickers, id: \.id) { sticker in
                StoryStickerView(
                    sticker: stickerForDisplay(sticker, containerSize: screenSize),
                    screenSize: geometry.size,
                    storyId: story.id ?? "",
                    userId: story.authorId,
                    onPauseStory: pauseStory,
                    onResumeStory: resumeStory
                )
                .id((story.id ?? "") + sticker.id) // ✅ Forzar nueva instancia al cambiar de historia
                .position(stickerDisplayPosition(sticker, containerSize: screenSize))
                }
            }

            // MARK: - 3. FLOATING HEARTS (Under UI, Over Content)
            FloatingHeartsView(hearts: floatingHearts)
                .allowsHitTesting(false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            // MARK: - 3.5 REVEAL OVERLAY (sobre contenido, debajo de la UI)
            if let revealSticker = revealSticker {
                InteractiveRevealSticker(
                    storyId: story.id ?? "",
                    onPauseStory: { pauseStory() },
                    onResumeStory: { resumeStory() },
                    revealType: revealSticker.interactionData?.revealType,
                    revealPattern: revealSticker.interactionData?.revealPattern,
                    revealPrimaryColor: revealSticker.interactionData?.revealPrimaryColor,
                    revealSecondaryColor: revealSticker.interactionData?.revealSecondaryColor
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }

            if !isUIHidden {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.70),
                            Color.black.opacity(0.42),
                            Color.black.opacity(0.16),
                            Color.black.opacity(0.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(geometry.safeAreaInsets.top, 47) + 160)
                    .ignoresSafeArea(edges: .top)

                    Spacer()
                }
                .allowsHitTesting(false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }

            // MARK: - 4. UI SUPERIOR (Header + Progress) - FIJA ARRIBA, NUNCA SE MUEVE
            VStack(spacing: 0) {
                if !isUIHidden {
                    Color.clear.frame(height: max(geometry.safeAreaInsets.top, 47) + 8)

                    glassmorphicProgressBar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    glassmorphicHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(1)
                }

                Spacer()

                Color.clear.frame(height: 80)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            if showQuickActions {
                storyQuickActionsOverlay(topInset: max(geometry.safeAreaInsets.top, 47))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                    .zIndex(20)
            }

            // MARK: - 5. ÁREAS DE NAVEGACIÓN (Fijas)
            if !isKeyboardVisible {
                navigationTouchAreas
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(!isStoryInteractionBlocked)
            }

            // MARK: - 6. INPUT AREA - Se mueve manualmente con keyboardHeight
            VStack {
                Spacer()

                if !isUIHidden {
                    glassmorphicBottomArea
                        .padding(.horizontal, 16)
                        .padding(.bottom, isKeyboardVisible ? keyboardHeight + 10 : max(geometry.safeAreaInsets.bottom, 25))
                        .animation(.easeInOut(duration: 0.25), value: keyboardHeight)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            // MARK: - 7. Success message overlay
            if showSuccessMessage {
                GlassmorphicSuccessMessage(text: successMessageText)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }

            if let confirmationKind = activeStoryConfirmation {
                GlassmorphicStoryConfirmationDialog(
                    title: confirmationTitle(for: confirmationKind),
                    message: confirmationMessage(for: confirmationKind),
                    confirmTitle: confirmationConfirmTitle(for: confirmationKind),
                    cancelTitle: confirmationCancelTitle(for: confirmationKind),
                    isDestructive: true,
                    onConfirm: {
                        handleStoryConfirmation(confirmationKind)
                    },
                    onCancel: {
                        clearAllStoryConfirmations()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(30)
            }
        }
        .sheet(isPresented: $showMomentDetail) {
            if let momentId = targetMomentId, let userId = targetMomentUserId {
                MomentDetailFromNotificationView(
                    momentId: momentId,
                    userId: userId,
                    isPresented: $showMomentDetail
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMomentFromStory"))) { notification in
            if let userInfo = notification.userInfo,
               let momentId = userInfo["momentId"] as? String,
               let userId = userInfo["userId"] as? String {
                self.targetMomentId = momentId
                self.targetMomentUserId = userId
                self.showMomentDetail = true
                self.pauseStory()
            }
        }
        .onChange(of: showMomentDetail) { oldValue, newValue in
            if !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.resumeStory()
                }
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .ignoresSafeArea(.all)
    }

    private var interactiveRootView: AnyView {
        let base = GeometryReader { geometry in
            geometryStackView(for: geometry)
        }
        .ignoresSafeArea(.all)
        .background(Color.black)
        .scaleEffect(zoomScale)

        return AnyView(
            base
                .simultaneousGesture(holdToPauseGesture)
                .simultaneousGesture(unifiedDragGesture)
                .simultaneousGesture(pinchGesture)
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            if isTextFieldFocused {
                                isTextFieldFocused = false
                            }
                        }
                )
        )
    }

    private var lifecycleBoundView: AnyView {
        AnyView(
            interactiveRootView
                .onAppear {
                    prepareAndStartStory()
                    setupKeyboardNotifications()
                    if storyStickers.isEmpty {
                        storyStickers = story.convertStickersToStickerItems()
                    }
                    preloadNextStory()
                    if let chainId = story.chainId {
                        checkCanContinueChain(chainId: chainId)
                    }
                    if story.chainId != nil {
                        loadChainStories()
                    }
                }
                .onChange(of: story.id) { newId in
                    if let chainId = story.chainId {
                        checkCanContinueChain(chainId: chainId)
                    }
                }
                .onDisappear {
                    stopAndCleanupStory()
                    removeKeyboardNotifications()
                    cleanupAudioSession()
                }
                .onChange(of: story.id) { oldStoryId, newStoryId in
                    if oldStoryId != newStoryId {
                        handleStoryChange()
                        storyStickers = story.convertStickersToStickerItems()
                    }
                }
                .onChange(of: storyIndex) { oldIndex, newIndex in
                    let newStickers = story.convertStickersToStickerItems()
                    storyStickers = newStickers
                }
        )
    }

    private var overlayBoundView: AnyView {
        AnyView(
            ZStack {
                lifecycleBoundView
                    .sheet(isPresented: $showViewers, onDismiss: {
                        resumeStory()
                    }) {
                        GlassmorphicViewersSheet(
                            story: story,
                            viewers: storyViewModel.storyViewers[story.id ?? ""] ?? [],
                            reactions: storyViewModel.storyReactions[story.id ?? ""] ?? []
                        )
                        .onAppear {
                            pauseStory()
                        }
                    }

            }
            .onChange(of: selectedPhoto) { newPhoto in
                handleEphemeralPhoto(newPhoto)
            }
            .onChange(of: showReactions) { isOpen in
                if isOpen {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showEphemeralPicker) { isOpen in
                if isOpen {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showingReportSheet) { oldValue, newValue in
                if newValue {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showViewers) { oldValue, newValue in
                if newValue {
                    pauseStory()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }
            }
            .onChange(of: showingBlockConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
                .onChange(of: showUnfollowConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
                .onChange(of: showMuteConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
                .onChange(of: showBestFriendsOptOutConfirmation) { oldValue, newValue in
                    if newValue {
                        pauseStory()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            resumeStory()
                        }
                    }
                }
        )
    }

    private var profileAndChainBoundView: AnyView {
        AnyView(
            overlayBoundView
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowUserProfileFromStory"))) { notification in
                    if let userId = notification.object as? String, !userId.isEmpty {
                        selectedUserId = userId
                        showUserProfile = true
                        pauseStory()
                    }
                }
                .sheet(isPresented: $showUserProfile, onDismiss: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }) {
                    if !selectedUserId.isEmpty {
                        UserProfileView(userId: selectedUserId)
                    }
                }
                .sheet(isPresented: $showChainView, onDismiss: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resumeStory()
                    }
                }) {
                    StoryChainView(
                        chainId: selectedChainId,
                        chainTitle: selectedChainTitle,
                        canContinueChain: canContinueChain,
                        initialStoryId: selectedChainStoryId.isEmpty ? nil : selectedChainStoryId,
                        initialChainPosition: selectedChainStoryPosition
                    )
                    .background(Color.clear)
                }
                .onChange(of: showChainView) { isOpen in
                    if isOpen {
                        pauseStory()
                    }
                }
                .onChange(of: showUserProfile) { oldValue, newValue in
                    if !newValue && oldValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            resumeStory()
                        }
                    }
                }
        )
    }

    // MARK: - Glassmorphic Components

    private var glassmorphicProgressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<storyCount, id: \.self) { index in
                GlassmorphicProgressBar(
                    progress: getProgressForSegment(index: index),
                    isActive: index == storyIndex,
                    audience: audienceForSegment(index: index)
                )
            }
        }
    }

    private func audienceForSegment(index: Int) -> String? {
        guard let storiesForAuthor = storyViewModel.stories[story.authorId],
              storiesForAuthor.indices.contains(index) else {
            return nil
        }
        return storiesForAuthor[index].audience
    }

    private var glassmorphicHeader: some View {
        HStack(spacing: 12) {
            Button(action: onProfileTap) {
                HStack(spacing: 10) {
                    ZStack {
                        if let profileImagePath = story.profileImagePath {
                            KFImage(URL(string: profileImagePath))
                                .resizable()
                                .scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.44), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.38), radius: 10, x: 0, y: 5)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.16))
                                .frame(width: 38, height: 38)
                                .liquidGlass(in: Circle())

                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 28))
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(story.username)
                                .foregroundColor(.white)
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .lineLimit(1)
                                .shadow(color: Color.black.opacity(0.60), radius: 5, x: 0, y: 2)

                            // ✅ INSIGNIA DE VERIFICADO
                            if story.authorId == Auth.auth().currentUser?.uid {
                                // Para el usuario actual, verificar si está verificado
                                CurrentUserVerifiedBadge(size: 12)
                            } else {
                                // Para otros usuarios, verificar si están verificados
                                VerifiedBadgeView(userId: story.authorId, size: 12)
                            }
                        }

                        Text(timeAgoString(from: story.timestamp))
                            .foregroundColor(.white.opacity(0.7))
                            .font(.custom("Poppins-Regular", size: 11))
                            .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()


            HStack(alignment: .top, spacing: 8) {
                Button(action: toggleQuickActions) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
        }
    }

    private func storyQuickActionsOverlay(topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissQuickActions()
                }

            storyQuickActionsDropdown
                .padding(.top, topInset + 74)
                .padding(.trailing, 16)
        }
    }

    private var storyQuickActionsDropdown: some View {
        StoryQuickActionsMenu(
            isOwnStory: story.authorId == Auth.auth().currentUser?.uid,
            canLeaveBestFriends: canOptOutFromAuthorBestFriends,
            textColor: quickActionTextColor,
            dividerColor: quickActionDividerColor,
            onViewActivity: {
                dismissQuickActions(resume: false)
                fetchViewersAndShow()
            },
            onSave: {
                dismissQuickActions(resume: false)
                saveStoryToDevice()
            },
            onDelete: {
                dismissQuickActions(resume: false)
                deleteStory()
            },
            onUnfollow: {
                dismissQuickActions(resume: false)
                showUnfollowConfirmation = true
            },
            onMute: {
                dismissQuickActions(resume: false)
                showMuteConfirmation = true
            },
            onReport: {
                dismissQuickActions(resume: false)
                onReportStory()
            },
            onLeaveBestFriends: {
                dismissQuickActions(resume: false)
                showBestFriendsOptOutConfirmation = true
            }
        )
    }


    // MARK: - Bottom Area
    private var glassmorphicBottomArea: some View {
        let hasChainOverlay = story.chainId != nil && story.chainTitle != nil && story.chainPosition != nil
        return VStack(spacing: 12) {
            // ✅ REACCIONES: Solo mostrar si el autor las permite
            if showReactions && authorAllowsReactions {
                StoryReactionsStrip(
                    reactions: reactions,
                    showReactions: showReactions,
                    onReaction: sendReaction
                )
            }

            // ✅ ÁREA DE INTERACCIÓN: Solo para historias de otros usuarios
            if story.authorId != Auth.auth().currentUser?.uid {

                // Si permite alguna interacción, mostrar controles
                if authorAllowsMessages || authorAllowsReactions || authorAllowsEphemeralPhotos {

                    HStack(spacing: 12) {
                        // ✅ ÁREA DE TEXTO/REACCIONES
                        HStack(spacing: 8) {
                            // Campo de texto solo si permite mensajes
                            if authorAllowsMessages {
                                TextField(storyMessagePlaceholder, text: $messageText, axis: .vertical)
                                    .foregroundColor(.white)
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .padding(.leading, 4)
                                    .lineLimit(1...3)
                                    .focused($isTextFieldFocused)
                                    .submitLabel(.send)
                                    .onSubmit {
                                        if !messageText.isEmpty {
                                            sendMessage()
                                        }
                                    }
                                    .onChange(of: isTextFieldFocused) { focused in
                                        if focused {
                                            pauseStory()
                                        } else {
                                            resumeStory()
                                        }
                                    }
                            }

                            // ✅ BOTÓN REACCIONES: Siempre visible si permite reacciones
                            if authorAllowsReactions && (messageText.isEmpty || !authorAllowsMessages) {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        showReactions.toggle()
                                    }
                                }) {
                                    Image(systemName: showReactions ? "face.smiling.fill" : "face.smiling")
                                        .foregroundColor(.white)
                                        .font(.system(size: 18))
                                }
                                .onChange(of: showReactions) { isOpen in
                                    if isOpen {
                                        pauseStory() // ✅ Pausar historia cuando se abren reacciones
                                    } else {
                                        // ✅ Reanudar historia cuando se cierran reacciones
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            resumeStory()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Capsule(), interactive: true)

                        // ✅ BOTÓN CÁMARA: Solo si permite fotos efímeras
                        if authorAllowsEphemeralPhotos {
                            Button(action: {
                                showEphemeralPicker = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.001))
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .photosPicker(isPresented: $showEphemeralPicker, selection: $selectedPhoto, matching: .images)
                            .onChange(of: showEphemeralPicker) { isOpen in
                                if isOpen {
                                    pauseStory() // ✅ Pausar historia cuando se abre selector de fotos
                                } else {
                                    // ✅ Reanudar historia cuando se cierra selector de fotos
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        resumeStory()
                                    }
                                }
                            }
                        }

                        // ✅ BOTÓN ENVIAR: Solo si hay mensaje Y permite mensajes
                        if !messageText.isEmpty && authorAllowsMessages {
                            Button(action: sendMessage) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.001))
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .frame(width: 54, height: 54)
                            .contentShape(Rectangle())
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: keyboardHeight)

                } else {
                    // ✅ MENSAJE: Cuando no permite ninguna interacción
                    StoryNoInteractionsNotice()
                }
            }

            // 🔗 STORY CHAINS: Botones para cadenas de historias
            if let chainId = story.chainId, let chainTitle = story.chainTitle, let chainPosition = story.chainPosition {
                VStack(spacing: 8) {
                    // Banner de información de la cadena
                    HStack {
                        Spacer()

                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .font(.caption)

                            Text(String(format: NSLocalizedString("storyChains.part", comment: "Part"), chainPosition, chainTitle))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Spacer()
                    }

                    // Botones de acción
                    HStack(spacing: 12) {
                        // Botón para ver cadena completa
                        Button(action: {
                            showChainView(
                                chainId: chainId,
                                chainTitle: chainTitle,
                                initialStoryId: story.id,
                                initialChainPosition: chainPosition
                            )
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))

                                Text(NSLocalizedString("storyChains.viewChain", comment: "View Chain"))
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Capsule(), interactive: true)
                        }

                        // Botón principal para continuar (solo si se puede)
                        if canContinueChain {

                            Button(action: {
                                continueStoryChain(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
                            }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))

                                Text(NSLocalizedString("storyChains.continueStory", comment: "Continue Story"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Capsule(), interactive: true)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
                .padding(.vertical, 12)
                .background(
                    Color.white.opacity(0.001)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                )
                .offset(y: 10)
            }
        }
        .padding(.horizontal, 16)
        // ✅ Eliminar padding interno si el teclado está visible
        .padding(.bottom, isKeyboardVisible ? 0 : (hasChainOverlay ? 12 : 25))
    }

    private var contentView: some View {
        let resolvedScreenSize = CGSize(
            width: max(screenSize.width, 1),
            height: max(screenSize.height, 1)
        )
        let mediaAspectRatio = StoryViewerScreen.parseAspectRatio(story.aspectRatio)
            ?? (resolvedScreenSize.width / resolvedScreenSize.height)
        let presentationMode = StoryMediaLayoutRules.presentationMode(
            for: mediaAspectRatio,
            canvasAspectRatio: resolvedScreenSize.width / resolvedScreenSize.height
        )

        return ScreenshotProtectedView(isProtected: (story.audience?.lowercased() ?? "") != "everyone", fillsContainer: true) {
            ZStack {
                // ✅ CONTENIDO PRINCIPAL (imagen/video)
                Group {
                    if story.mediaItem.type == .video, let url = URL(string: story.mediaItem.url) {
                    GlassmorphicStoryVideoPlayer(
                        url: url,
                        isPlaying: Binding(
                            get: { !playbackCoordinator.isPaused },
                            set: { playbackCoordinator.setPausedFromVideoBinding(!$0) }
                        ),
                        isHorizontalVideo: StoryViewerScreen.isHorizontalAspectRatio(story.aspectRatio),
                        videoGravity: presentationMode.videoGravity,
                        shouldLoop: false,
                        onProgressUpdate: { newProgress in
                            playbackCoordinator.updateVideoProgress(newProgress, for: story)
                        },
                        onVideoComplete: {
                            // ✅ VIDEO TERMINÓ, IR A SIGUIENTE (solo si no está pausado)
                            if playbackCoordinator.canAdvanceAfterVideoComplete() {
                                onNext()
                            }
                        }
                    )
                    .frame(width: screenSize.width, height: screenSize.height)
                    .background(
                        Group {
                            if presentationMode == .fitWithBlur,
                               let blurredFrameURL = story.backgroundBlurredFrameURL,
                               let url = URL(string: blurredFrameURL) {
                                KFImage(url)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else if presentationMode == .fitWithBlur,
                                      let backgroundFrameURL = story.backgroundFrameURL,
                                      let url = URL(string: backgroundFrameURL) {
                                KFImage(url)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .blur(radius: 15) // ✅ BLUR SUTIL
                                    .scaleEffect(1.2) // ✅ ESCALADO PARA EVITAR BORDES
                                    .clipped()
                            } else {
                                // ✅ FALLBACK: Degradado elegante
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.85),
                                        Color.black.opacity(0.6),
                                        Color.black.opacity(0.4)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                        }
                    )
                    .id(story.id) // ✅ FORZAR RECREACIÓN CUANDO CAMBIA LA HISTORIA
                } else if story.mediaItem.type == .image, let url = URL(string: story.mediaItem.url) {
                    KFImage(url)
                        .placeholder {
                            ZStack {
                                Color.black
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            }
                        }
                        .resizable()
                        .aspectRatio(contentMode: presentationMode.swiftUIContentMode)
                        .frame(width: screenSize.width, height: screenSize.height)
                        .background(
                            // ✅ FONDO BLUR para imágenes (usando la misma imagen con blur)
                            KFImage(url)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .blur(radius: 20) // ✅ BLUR INTENSO para fondo
                                .scaleEffect(1.3) // ✅ ESCALADO PARA EVITAR BORDES
                                .clipped()
                        )
                        .clipped()
                } else {
                    ZStack {
                        Color.black
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.6))
                            Text("stories.contentUnavailable")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.custom("Poppins-Medium", size: 16))
                        }
                    }
                    .frame(width: screenSize.width, height: screenSize.height)
                }
            }
        }
        .clipped() // Ensure content doesn't overflow
        }
    }

    private var navigationTouchAreas: some View {
        StoryNavigationTouchAreas(
            screenSize: screenSize,
            shouldSuppressNavigationTap: shouldSuppressNavigationTap,
            onPrevious: onPrevious,
            onNext: onNext
        )
    }

    // MARK: - ✅ PRELOADING
    private func preloadNextStory() {
        // ✅ Obtener todas las historias del usuario actual
        let userId = story.authorId
        guard let allStories = storyViewModel.stories[userId],
              let currentStoryId = story.id else {
            return
        }

        // ✅ Precargar la siguiente historia
        storyViewModel.preloadNextStory(currentStoryId: currentStoryId, allStories: allStories)
    }

    // MARK: - Keyboard Handling
    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeInOut(duration: 0.3)) {
                    keyboardHeight = keyboardFrame.height
                    isKeyboardVisible = true
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                keyboardHeight = 0
                isKeyboardVisible = false
            }
        }
    }

    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)

        // Clear focus and resume story smoothly
        if isTextFieldFocused {
            isTextFieldFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                resumeStory()
            }
        }
    }

    // MARK: - Gestures

    private var storyMessagePlaceholder: String {
        let format = NSLocalizedString("stories.sendMessagePlaceholder", comment: "Send story message placeholder")
        return String(format: format, story.username)
    }

    private func isProtectedGestureStart(_ location: CGPoint) -> Bool {
        let topProtectedHeight: CGFloat = 180
        let topRightProtectedX = screenSize.width - 120
        let bottomProtectedHeight = screenSize.height - 170

        if location.y < topProtectedHeight {
            return true
        }

        if location.y < 220 && location.x > topRightProtectedX {
            return true
        }

        if location.y > bottomProtectedHeight {
            return true
        }

        return false
    }

    private var isStoryInteractionBlocked: Bool {
        isMenuInteractionActive
            || showQuickActions
            || showViewers
            || showingReportSheet
            || showingBlockConfirmation
            || showUserProfile
            || showChainView
            || showReactions
            || showEphemeralPicker
            || showBestFriendsOptOutConfirmation
            || showUnfollowConfirmation
            || showMuteConfirmation
    }

    private var holdToPauseGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canStartHoldGesture(from: value.startLocation) else { return }

                if abs(value.translation.width) > 14 || abs(value.translation.height) > 14 {
                    cancelPendingHoldPause()
                    return
                }

                guard holdPauseWorkItem == nil, holdStartLocation == nil else { return }
                holdStartLocation = value.startLocation

                let workItem = DispatchWorkItem {
                    guard self.canStartHoldGesture(from: value.startLocation) else { return }
                    self.isHoldingStory = true
                    self.pauseStory()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.isUIHidden = true
                    }
                }

                holdPauseWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
            }
            .onEnded { _ in
                let shouldResume = isHoldingStory
                cancelPendingHoldPause()
                isHoldingStory = false

                if shouldResume {
                    suppressNavigationTapUntil = Date().addingTimeInterval(0.25)
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isUIHidden = false
                    }
                    resumeStory()
                }
            }
    }

    private func canStartHoldGesture(from location: CGPoint) -> Bool {
        guard !isMenuInteractionActive,
              !isKeyboardVisible,
              !isProtectedGestureStart(location),
              !showQuickActions,
              !showViewers,
              !showingReportSheet,
              !showingBlockConfirmation,
              !showUserProfile,
              !showChainView,
              !showReactions,
              !showEphemeralPicker,
              !showBestFriendsOptOutConfirmation,
              !showUnfollowConfirmation,
              !showMuteConfirmation else {
            return false
        }

        return true
    }

    private var shouldSuppressNavigationTap: Bool {
        guard let suppressNavigationTapUntil else { return false }
        return Date() < suppressNavigationTapUntil
    }

    private func cancelPendingHoldPause() {
        holdPauseWorkItem?.cancel()
        holdPauseWorkItem = nil
        holdStartLocation = nil
    }

    // ✅ UNIFIED GESTURE: Drag, Swipe Up/Down/Horizontal
    private var unifiedDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isStoryInteractionBlocked else { return }

                if isProtectedGestureStart(value.startLocation) {
                    return
                }

                if !playbackCoordinator.isPaused && !isHoldingStory {
                    pauseStory()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isUIHidden = true
                    }
                }

                // Si ya se disparó una acción (nav/reply), ignorar resto del drag
                if gestureActionTriggered { return }

                // SWIPE UP (Quick Reply)
                if value.translation.height < -60 && abs(value.translation.width) < 50 {
                    if authorAllowsMessages {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation {
                            isTextFieldFocused = true
                            isUIHidden = false
                        }
                        gestureActionTriggered = true
                    }
                }

                // HORIZONTAL SWIPE (Navigation) - Solo si es cadena
                else if let chainId = story.chainId, !chainStories.isEmpty {
                    if value.translation.width > 60 {
                         goToPreviousChainPart()
                         gestureActionTriggered = true
                    } else if value.translation.width < -60 {
                         goToNextChainPart()
                         gestureActionTriggered = true
                    }
                }
            }
            .onEnded { value in
                guard !isStoryInteractionBlocked else { return }

                if isProtectedGestureStart(value.startLocation) {
                    return
                }

                isHoldingStory = false
                cancelPendingHoldPause()
                gestureActionTriggered = false

                // Restaurar UI
                if isUIHidden {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isUIHidden = false
                    }
                }

                if !isTextFieldFocused {
                    resumeStory()
                }
            }
    }

    // ✅ ZOOM: Gesto de pinch to zoom
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                guard !isStoryInteractionBlocked else { return }
                let newScale = lastZoomScale * scale
                zoomScale = min(max(newScale, 1.0), 3.0) // Limitar zoom entre 1x y 3x
            }
            .onEnded { _ in
                guard !isStoryInteractionBlocked else { return }
                lastZoomScale = zoomScale

                // Volver a escala normal si es muy pequeña
                if zoomScale < 1.2 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                    }
                }
            }
    }

    // MARK: - Actions

    // 🔗 STORY CHAINS: Navegar a la siguiente parte de la cadena
    private func goToNextChainPart() {
        guard currentChainIndex < chainStories.count - 1 else { return }

        let nextIndex = currentChainIndex + 1
        let nextStory = chainStories[nextIndex]

        // Actualizar el índice actual
        currentChainIndex = nextIndex

        // Notificar al padre para cambiar la historia
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToChainStory"),
            object: nil,
            userInfo: [
                "storyId": nextStory.id ?? "",
                "chainIndex": nextIndex
            ]
        )
    }

    // 🔗 STORY CHAINS: Navegar a la parte anterior de la cadena
    private func goToPreviousChainPart() {
        guard currentChainIndex > 0 else { return }

        let previousIndex = currentChainIndex - 1
        let previousStory = chainStories[previousIndex]

        // Actualizar el índice actual
        currentChainIndex = previousIndex

        // Notificar al padre para cambiar la historia
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToChainStory"),
            object: nil,
            userInfo: [
                "storyId": previousStory.id ?? "",
                "chainIndex": previousIndex
            ]
        )
    }

    // 🔗 STORY CHAINS: Cargar todas las historias de la cadena
    private func loadChainStories() {
        guard let chainId = story.chainId else { return }

        isLoadingChainStories = true

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

                    // Encontrar el índice de la historia actual
                    if let currentStoryId = story.id {
                        currentChainIndex = stories.firstIndex { $0.id == currentStoryId } ?? 0
                    }

                    isLoadingChainStories = false
                }
            } catch {
                await MainActor.run {
                    isLoadingChainStories = false
                }
            }
        }
    }

    private func sendMessage() {
        guard !messageText.isEmpty, let storyId = story.id else { return }

        let messageToSend = messageText
        messageText = "" // Clear immediately for better UX
        isTextFieldFocused = false // Dismiss keyboard

        storyViewModel.sendMessage(
            to: story.authorId,
            storyId: storyId,
            message: messageToSend
        ) { success in
            if success {
                showSuccessAnimation("Mensaje enviado")
            } else {
                // Restore message if failed
                messageText = messageToSend
            }
        }
    }

    private func sendReaction(_ reaction: String) {
        guard let storyId = story.id else { return }

        storyViewModel.sendReaction(
            to: story.authorId,
            storyId: storyId,
            reaction: reaction
        )

        withAnimation(.spring()) {
            showReactions = false
        }

        // ✅ TRIGGER FLOATING VISUAL FEEDBACK
        let randomX = CGFloat.random(in: 50...(screenSize.width - 50))
        let heart = FloatingHeart(emoji: reaction, startX: randomX)
        floatingHearts.append(heart)

        // Remove heart after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if !floatingHearts.isEmpty {
                floatingHearts.removeFirst()
            }
        }

        showSuccessAnimation(NSLocalizedString("stories.reactionSent", comment: "Reaction sent"))

        // ✅ Reanudar historia inmediatamente después de enviar reacción
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            resumeStory()
        }
    }

    private func handleEphemeralPhoto(_ photo: PhotosPickerItem?) {
        guard let photo = photo else { return }

        Task {
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data),
                      let storyId = story.id else {
                    return
                }

                storyViewModel.sendEphemeralMoment(
                    to: story.authorId,
                    storyId: storyId,
                    image: uiImage
                ) { success in
                    if success {
                        showSuccessAnimation("Momento enviado")
                        // ✅ Reanudar historia después de enviar foto efímera
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            resumeStory()
                        }
                    }
                }
            } catch {
                // ✅ Reanudar historia si hay error
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    resumeStory()
                }
            }
        }
    }

    private func deleteStory() {
        guard let storyId = story.id else { return }

        storyViewModel.deleteStory(userId: story.authorId, storyId: storyId) { error in
            if error == nil {
                // Deleting a story changes the source list, so let the presenter
                // reconcile the current index instead of treating it as playback.
                if let onStoryDeleted {
                    onStoryDeleted()
                } else {
                    onNext()
                }
            }
        }
        showQuickActions = false
    }

    private func fetchViewersAndShow() {
        guard let storyId = story.id else { return }

        storyViewModel.fetchViewers(for: story.authorId, storyId: storyId) { _ in
            showViewers = true
            showQuickActions = false
        }
    }

    private func saveStoryToDevice() {
        if let url = URL(string: story.mediaItem.url) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if story.mediaItem.type == .image {
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                        }
                        showSuccessAnimation(NSLocalizedString("stories.savedImage", comment: "Image saved"))
                    } else if story.mediaItem.type == .video {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("story_video.mp4")
                        try data.write(to: tempURL)
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: tempURL, options: nil)
                        }
                        showSuccessAnimation(NSLocalizedString("stories.savedVideo", comment: "Video saved"))
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                } catch {
                }
            }
        }
        showQuickActions = false
    }

    private func showSuccessAnimation(_ message: String) {
        successMessageText = message
        withAnimation(.spring()) {
            showSuccessMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring()) {
                showSuccessMessage = false
            }
        }
    }

    private func pauseForMenuInteraction() {
        pauseStory()
        isMenuInteractionActive = true
        menuAutoResumeWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            let isAnyOverlayVisible = self.showQuickActions
                || self.showViewers
                || self.showingReportSheet
                || self.showingBlockConfirmation
                || self.showUserProfile
                || self.showChainView
                || self.showReactions
                || self.showEphemeralPicker
                || self.showBestFriendsOptOutConfirmation
                || self.showUnfollowConfirmation
                || self.showMuteConfirmation

            if isAnyOverlayVisible {
                self.menuAutoResumeWorkItem = nil
                return
            }

            self.isMenuInteractionActive = false
            self.resumeStory()
            self.menuAutoResumeWorkItem = nil
        }

        menuAutoResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: workItem)
    }

    private func cancelMenuAutoResume() {
        menuAutoResumeWorkItem?.cancel()
        menuAutoResumeWorkItem = nil
        isMenuInteractionActive = false
    }

    private func toggleQuickActions() {
        if showQuickActions {
            dismissQuickActions()
        } else {
            pauseForMenuInteraction()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
                showQuickActions = true
            }
        }
    }

    private func dismissQuickActions(resume: Bool = true) {
        let shouldResume = resume
        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
            showQuickActions = false
        }
        cancelMenuAutoResume()

        guard shouldResume else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.resumeStory()
        }
    }

    private func optOutFromBestFriends() {
        pauseStory()
        bestFriendsService.optOutFromBestFriends(of: story.authorId) { error in
            DispatchQueue.main.async {
                if let error = error {
                    let fallback = NSLocalizedString("bestFriends.optOut.error", comment: "Could not leave best friends")
                    let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                    self.showSuccessAnimation(message)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.resumeStory()
                    }
                    return
                }

                self.showSuccessAnimation(NSLocalizedString("bestFriends.optOut.success", comment: "You left best friends"))
                if let currentUserId = Auth.auth().currentUser?.uid {
                    StorySeenStateService.shared.invalidate(
                        viewerId: currentUserId,
                        authorId: self.story.authorId
                    )
                }

                // Dar tiempo a leer el mensaje y mantener flujo natural de historias.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.onNext()
                }
            }
        }
    }

    private func unfollowStoryAuthor() {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != story.authorId else {
            return
        }

        pauseStory()
        firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: story.authorId) { error in
            DispatchQueue.main.async {
                if let error = error {
                    let fallback = NSLocalizedString("storyContextMenu.actionFailed", comment: "Generic story action failed")
                    let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                    self.showSuccessAnimation(message)
                } else {
                    self.showSuccessAnimation(NSLocalizedString("storyContextMenu.unfollow.success", comment: "Unfollow success message"))
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.resumeStory()
                }
            }
        }
    }

    private func muteStoryAuthor() {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != story.authorId else {
            return
        }

        pauseStory()
        firestoreService.db
            .collection("users")
            .document(currentUserId)
            .updateData([
                "muteSettings.mutedUsers": FieldValue.arrayUnion([story.authorId])
            ]) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        let fallback = NSLocalizedString("storyContextMenu.actionFailed", comment: "Generic story action failed")
                        let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                        self.showSuccessAnimation(message)
                    } else {
                        self.showSuccessAnimation(NSLocalizedString("storyContextMenu.mute.successWithHint", comment: "Mute success message with settings hint"))
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.resumeStory()
                    }
                }
            }
    }

    // MARK: - Story Playback

    private func prepareAndStartStory() {
        playbackCoordinator.prepareStory(story, onImageComplete: onNext)

        loadAuthorInteractionSettings()

        // Mark story as viewed
        if let storyId = story.id {
            storyViewModel.markStoryAsViewed(
                userId: story.authorId,
                storyId: storyId,
                storyTimestamp: story.timestamp,
                audience: story.audience
            )
        }

    }

    private func stopAndCleanupStory() {
        cancelMenuAutoResume()
        cancelPendingHoldPause()
        isHoldingStory = false
        playbackCoordinator.stopStory()

        // ✅ CLEANUP DE AUDIO
        cleanupAudioSession()
    }

    // ✅ NUEVA FUNCIÓN: Limpiar sesión de audio
    private func cleanupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
        }
    }


    // ✅ SIMPLIFICADO: Solo cambiar estado
    private func pauseStory() {
        playbackCoordinator.pauseStory()
    }

    private func resumeStory() {
        // ✅ REFUERZO SEGURO: No reanudar si cualquier overlay está visible o si hay teclado/drag
        let isAnyOverlayVisible = showQuickActions || showViewers || showingReportSheet || showingBlockConfirmation || showUserProfile || showChainView || showReactions || showEphemeralPicker || showBestFriendsOptOutConfirmation || showUnfollowConfirmation || showMuteConfirmation

        let canResume = !isKeyboardVisible && !isDragging && !isMenuInteractionActive && !isAnyOverlayVisible
        playbackCoordinator.resumeStory(story, canResume: canResume, onImageComplete: onNext)
    }

    // MARK: - Helpers

    private func handleStoryChange() {

        // ✅ SIMPLIFICADO: Cleanup inmediato
        stopAndCleanupStory()

        // ✅ SIMPLIFICADO: Sin delay, transición inmediata
        prepareAndStartStory()
    }

    private func getProgressForSegment(index: Int) -> Double {
        playbackCoordinator.progressForSegment(index: index, storyIndex: storyIndex)
    }

    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadAuthorInteractionSettings() {
        FirestoreService().db.collection("users").document(story.authorId).getDocument { document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists,
                   let data = document.data(),
                   let visibilitySettings = data["contentVisibilitySettings"] as? [String: Any] {

                    self.authorAllowsMessages = visibilitySettings["allowStoryMessages"] as? Bool ?? true
                    self.authorAllowsReactions = visibilitySettings["allowStoryReactions"] as? Bool ?? true
                    self.authorAllowsEphemeralPhotos = visibilitySettings["allowStoryEphemeralPhotos"] as? Bool ?? true
                }
            }
        }
    }

    // 🔗 FUNCIÓN: Verificar si el usuario puede continuar la cadena
    private func checkCanContinueChain(chainId: String) {

        guard let currentUserId = Auth.auth().currentUser?.uid else {

            canContinueChain = false
            return
        }


        // 🔥 LÓGICA MEJORADA: 1. Intentar obtener configuración desde la colección global 'storyChains'
        let firestoreService = FirestoreService()
        firestoreService.db.collection("storyChains").document(chainId).getDocument { snapshot, error in
            if let document = snapshot, document.exists, let data = document.data() {

                self.processChainMetadata(data, currentUserId: currentUserId)
                return
            }

            // 2. FALLBACK: Si no existe el documento global, buscar la primera historia (legacy)

            self.fallbackToCheckFirstPart(chainId: chainId, currentUserId: currentUserId)
        }
    }

    // 🔗 AUXILIAR: Procesar metadata de la cadena (desde global o primera parte)
    private func processChainMetadata(_ data: [String: Any], currentUserId: String) {
        // El autor original de la cadena siempre puede continuarla
        let authorId = data["authorId"] as? String ?? ""
        if authorId == currentUserId {

            DispatchQueue.main.async {
                self.canContinueChain = true
            }
            return
        }

        // Verificar si se permite que otros continúen
        let allowOthersToContinue = data["allowOthersToContinue"] as? Bool ?? true


        if !allowOthersToContinue {

            DispatchQueue.main.async {
                self.canContinueChain = false
            }
            return
        }

        // Verificar audiencia de continuación
        let continuationAudience = data["continuationAudience"] as? String ?? "everyone"

        checkContinuationAudience(continuationAudience: continuationAudience, data: data, currentUserId: currentUserId)
    }

    // 🔗 FALLBACK: Buscar la primera parte de la cadena (lógica antigua)
    private func fallbackToCheckFirstPart(chainId: String, currentUserId: String) {
        let authorId = story.authorId
        let firestoreService = FirestoreService()

        firestoreService.db.collection("users").document(authorId).collection("stories")
            .whereField("chainId", isEqualTo: chainId)
            .whereField("chainPosition", isEqualTo: 1) // Primera parte
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let document = snapshot?.documents.first {
                    let data = document.data()

                    self.processChainMetadata(data, currentUserId: currentUserId)
                } else {

                    self.ultimateFallbackSearch(chainId: chainId, currentUserId: currentUserId)
                }
            }
    }

    // 🔗 ÚLTIMO RECURSO: Búsqueda global de la primera parte
    private func ultimateFallbackSearch(chainId: String, currentUserId: String) {
        let firestoreService = FirestoreService()
        firestoreService.db.collectionGroup("stories")
            .whereField("chainId", isEqualTo: chainId)
            .whereField("chainPosition", isEqualTo: 1)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                guard let document = snapshot?.documents.first,
                      let data = document.data() as? [String: Any] else {

                    DispatchQueue.main.async {
                        self.canContinueChain = false
                    }
                    return
                }


                self.processChainMetadata(data, currentUserId: currentUserId)
            }
    }


    // 🔗 FUNCIÓN: Verificar audiencia de continuación
    private func checkContinuationAudience(continuationAudience: String, data: [String: Any], currentUserId: String) {
        let authorId = data["authorId"] as? String ?? ""


        switch continuationAudience {
        case "everyone":

            DispatchQueue.main.async {
                canContinueChain = true

            }

        case "connections":

            // Verificar conexión mutua usando PrivacyService
            let privacyService = PrivacyService()
            privacyService.checkMutualConnection(user1: currentUserId, user2: authorId) { isMutual in
                DispatchQueue.main.async {
                    canContinueChain = isMutual

                }
            }

        case "bestFriends":

            // Verificar si el autor tiene al usuario actual en sus mejores amigos
            let privacyService = PrivacyService()
            privacyService.checkIfBestFriend(userId: authorId, friendId: currentUserId) { isBestFriend in
                DispatchQueue.main.async {
                    canContinueChain = isBestFriend

                }
            }

        case "custom":

            // Verificar usuarios específicos
            let continuationCustomViewers = data["continuationCustomViewers"] as? [String] ?? []
            DispatchQueue.main.async {
                canContinueChain = continuationCustomViewers.contains(currentUserId)

            }

        case "customList":

            // Verificar lista personalizada
            let continuationCustomListId = data["continuationCustomListId"] as? String
            let authorId = data["authorId"] as? String ?? ""

            if let listId = continuationCustomListId {
                // Usar PrivacyService para obtener miembros de la lista
                let privacyService = PrivacyService()
                privacyService.getCustomListViewers(
                    listId: listId,
                    ownerId: authorId
                ) { members in
                    DispatchQueue.main.async {
                        canContinueChain = members.contains(currentUserId)

                    }
                }
            } else {

                DispatchQueue.main.async {
                    canContinueChain = false
                }
            }

        default:

            DispatchQueue.main.async {
                canContinueChain = false
            }
        }
    }

    // 🔗 FUNCIÓN: Continuar cadena de historias
    private func continueStoryChain(chainId: String, chainTitle: String, chainPosition: Int) {
        // Cerrar la vista actual
        dismiss()

        // Notificar al TabBarView para abrir CreatorView
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenCreatorForChain"),
            object: nil,
            userInfo: [
                "chainId": chainId,
                "chainTitle": chainTitle,
                "chainPosition": chainPosition
            ]
        )
    }

    // 🔗 FUNCIÓN: Mostrar vista de cadena completa
    private func showChainView(chainId: String, chainTitle: String, initialStoryId: String? = nil, initialChainPosition: Int? = nil) {
        selectedChainId = chainId
        selectedChainTitle = chainTitle
        selectedChainStoryId = initialStoryId ?? ""
        selectedChainStoryPosition = initialChainPosition ?? 1
        showChainView = true
    }
}
