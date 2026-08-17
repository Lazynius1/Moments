import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

struct FeedStoryRingPreviewSelection: Equatable {
    let userId: String
    let anchorFrame: CGRect
}

struct FeedStoryRingPreviewOverlay: View {
    @Binding var selection: FeedStoryRingPreviewSelection?

    let colorScheme: ColorScheme
    let onOpenStory: (String, String?, TimeInterval) -> Void
    let onOpenProfile: (String) -> Void
    let onMuted: (String) -> Void

    private let previewWidth: CGFloat = 196
    private let previewCornerRadius: CGFloat = 26
    private let menuRowHeight: CGFloat = 44
    private let stackGap: CGFloat = 10
    private let horizontalInset: CGFloat = 16
    private let ringGap: CGFloat = 10

    private let photoPreviewDuration: TimeInterval = 4.0
    private let videoPreviewFraction: Double = 0.40
    private let videoPreviewMinimumDuration: TimeInterval = 2.0

    @State private var isPresented = false
    @State private var dismissGeneration = 0
    @State private var advanceGeneration = 0
    @State private var loadGeneration = 0
    @State private var previewStories: [Story] = []
    @State private var previewIndex = 0
    @State private var previewCycle = 0
    @State private var previewStory: Story?
    @State private var previewStickers: [StickerItem] = []
    @State private var resolvedVideoDuration: TimeInterval?
    @State private var isPreviewVideoReady = false
    @State private var showMuteConfirmation = false
    @State private var successMessage: String?
    @State private var resolvedUsername = ""
    @State private var soundEnabledInSession = GlobalVideoManager.shared.userHasEnabledSoundInSession
    @State private var previewSegmentStartedAt: Date?
    @State private var previewElapsedBeforePause: TimeInterval = 0

    @Environment(\.displayScale) private var displayScale

    private var primaryTextColor: Color {
        MomentsChromeGlass.contentColor(for: colorScheme)
    }

    private var menuCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
    }

    private var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: previewCornerRadius, style: .continuous)
    }

    private var presentationAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.42, dampingFraction: 0.84)
    }

    private var dismissalAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.26)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let selection {
                    let layout = previewLayout(for: selection, in: proxy)

                    Color.black.opacity(isPresented ? 0.28 : 0)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissOverlay() }
                        .accessibilityHidden(true)

                    VStack(spacing: stackGap) {
                        previewCard(size: CGSize(width: layout.previewWidth, height: layout.previewHeight), userId: selection.userId)
                            .shadow(
                                color: .black.opacity(isPresented ? 0.28 : 0),
                                radius: isPresented ? 28 : 0,
                                x: 0,
                                y: isPresented ? 14 : 0
                            )

                        actionsMenu(for: selection)
                            .frame(width: layout.previewWidth)
                    }
                    .frame(width: layout.previewWidth, height: layout.stackHeight)
                    .scaleEffect(isPresented ? 1 : 0.92, anchor: .top)
                    .opacity(isPresented ? 1 : 0)
                    .position(x: layout.center.x, y: layout.center.y)

                    LiveUsernameContent(userId: selection.userId, fallbackUsername: "") { username in
                        Color.clear
                            .onAppear { resolvedUsername = username }
                            .onChange(of: username) { _, newValue in
                                resolvedUsername = newValue
                            }
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)

                    if showMuteConfirmation {
                        GlassmorphicStoryConfirmationDialog(
                            title: String(
                                format: NSLocalizedString("storyContextMenu.mute.confirm.title", comment: "Mute confirmation title"),
                                resolvedUsername
                            ),
                            message: NSLocalizedString("storyContextMenu.mute.confirm.message", comment: "Mute confirmation message"),
                            confirmTitle: NSLocalizedString("storyContextMenu.mute.confirm.action", comment: "Mute action"),
                            cancelTitle: NSLocalizedString("storyContextMenu.mute.confirm.cancel", comment: "Mute cancel"),
                            isDestructive: true,
                            onConfirm: {
                                showMuteConfirmation = false
                                muteAuthor(selection.userId)
                            },
                            onCancel: {
                                showMuteConfirmation = false
                            }
                        )
                        .zIndex(20)
                    }

                    if let successMessage {
                        VStack {
                            GlassmorphicSuccessMessage(text: successMessage)
                                .padding(.top, 12)
                            Spacer()
                        }
                        .zIndex(30)
                    }
                }
            }
            .onChange(of: selection?.userId) { _, userId in
                guard let userId else {
                    GlobalVideoManager.shared.endPlaybackHold()
                    isPresented = false
                    resetPreviewPlayback()
                    showMuteConfirmation = false
                    successMessage = nil
                    return
                }
                GlobalVideoManager.shared.beginPlaybackHold()
                dismissGeneration += 1
                isPresented = false
                showMuteConfirmation = false
                successMessage = nil
                resetPreviewPlayback()
                loadPreview(for: userId)
                preparePreviewAudioIfNeeded()
                DispatchQueue.main.async {
                    withAnimation(presentationAnimation) {
                        isPresented = true
                    }
                }
            }
            .onChange(of: showMuteConfirmation) { _, isShowing in
                if isShowing {
                    pausePreviewSegmentClock()
                    advanceGeneration += 1
                } else if selection != nil, isPresented {
                    resumePreviewSegmentClock()
                    scheduleAdvance()
                }
            }
            .onReceive(GlobalVideoManager.shared.$userHasEnabledSoundInSession) { enabled in
                soundEnabledInSession = enabled
                if enabled, previewStory?.mediaItem.type == .video {
                    preparePreviewAudioIfNeeded()
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(selection != nil)
        .accessibilityHidden(selection == nil)
    }

    @ViewBuilder
    private func previewCard(size: CGSize, userId: String) -> some View {
        Button {
            openCurrentPreviewStory(userId: userId)
        } label: {
            ZStack {
                if previewStory == nil {
                    ProgressView()
                        .tint(.white)
                }

                if let previewStory {
                    if previewStory.mediaItem.type == .image,
                       let url = URL(string: previewStory.mediaItem.url) {
                        KFImage(url)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size.width, height: size.height)
                    }

                    if previewStory.mediaItem.type == .video {
                        VideoPosterOverlay(
                            posterURLString: previewStory.mediaItem.thumbnailUrl,
                            isReadyToPlay: isPreviewVideoReady,
                            contentMode: .fit
                        )
                        .frame(width: size.width, height: size.height)

                        if let videoURL = URL(string: previewStory.mediaItem.url) {
                            StickerVideoPlayer(
                                url: videoURL,
                                isMuted: !soundEnabledInSession,
                                onDuration: { seconds in
                                    DispatchQueue.main.async {
                                        isPreviewVideoReady = true
                                        resolvedVideoDuration = seconds
                                        markPreviewSegmentStart()
                                        scheduleAdvance(videoDuration: seconds)
                                    }
                                }
                            )
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                            .onAppear {
                                preparePreviewAudioIfNeeded()
                            }
                        }
                    }

                    let stickers = previewStickers
                    StoryMediaOverlayRendererView(
                        containerSize: size,
                        textOverlays: previewStory.resolvedTextOverlays,
                        stickerItems: stickers,
                        drawingData: nil,
                        storyId: previewStory.id ?? "",
                        userId: previewStory.authorId,
                        reportsDeckInteractionExclusion: false,
                        allowsStickerHitTesting: false
                    )
                    .allowsHitTesting(false)

                    if let revealSticker = stickers.first(where: { $0.type == .reveal }) {
                        InteractiveRevealSticker(
                            storyId: previewStory.id ?? "",
                            onPauseStory: {},
                            onResumeStory: {},
                            reportsDeckInteractionExclusion: false,
                            revealType: revealSticker.interactionData?.revealType,
                            revealPattern: revealSticker.interactionData?.revealPattern,
                            revealPrimaryColor: revealSticker.interactionData?.revealPrimaryColor,
                            revealSecondaryColor: revealSticker.interactionData?.revealSecondaryColor,
                            revealEffectColor: revealSticker.interactionData?.revealEffectColor
                        )
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                    }
                }
            }
            .id("\(previewStory?.id ?? "empty")-\(previewCycle)")
            .frame(width: size.width, height: size.height)
            .clipped()
            .clipShape(previewShape)
            .contentShape(previewShape)
        }
        .buttonStyle(.plain)
        .frame(width: size.width, height: size.height)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func actionsMenu(for selection: FeedStoryRingPreviewSelection) -> some View {
        VStack(spacing: 0) {
            menuRow(
                title: NSLocalizedString("userActivity.event.action.viewProfile", comment: "View profile"),
                icon: "person.crop.circle",
                isDestructive: false
            ) {
                let userId = selection.userId
                dismissOverlay { onOpenProfile(userId) }
            }

            Divider()
                .opacity(0.35)
                .padding(.horizontal, 14)

            menuRow(
                title: NSLocalizedString("storyContextMenu.mute", comment: "Mute user button"),
                icon: "bell.slash",
                isDestructive: true
            ) {
                showMuteConfirmation = true
            }
        }
        .padding(.vertical, 6)
        .momentsChromeGlass(in: menuCardShape, interactive: true, style: .nativeTinted)
        .clipShape(menuCardShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
    }

    private func menuRow(
        title: String,
        icon: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        MomentRowButton(feedback: .menu, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? Color.red : primaryTextColor)
            .padding(.horizontal, 16)
            .frame(height: menuRowHeight)
            .contentShape(Rectangle())
        }
    }

    private func previewLayout(
        for selection: FeedStoryRingPreviewSelection,
        in proxy: GeometryProxy
    ) -> (
        previewWidth: CGFloat,
        previewHeight: CGFloat,
        stackHeight: CGFloat,
        center: CGPoint
    ) {
        let overlayGlobal = proxy.frame(in: .global)
        let anchor = CGRect(
            x: selection.anchorFrame.minX - overlayGlobal.minX,
            y: selection.anchorFrame.minY - overlayGlobal.minY,
            width: selection.anchorFrame.width,
            height: selection.anchorFrame.height
        )
        let menuHeight = menuRowHeight * 2 + 12
        let previewTop = max(anchor.maxY + ringGap, proxy.safeAreaInsets.top + 8)
        let maxHeight = max(
            220,
            proxy.size.height
                - previewTop
                - stackGap
                - menuHeight
                - proxy.safeAreaInsets.bottom
                - 16
        )
        let availableWidth = max(160, proxy.size.width - horizontalInset * 2)
        var width = min(previewWidth, availableWidth)
        var height = width * 16 / 9
        if height > maxHeight {
            height = maxHeight
            width = height * 9 / 16
        }

        let minX = horizontalInset
        let maxX = max(minX, proxy.size.width - horizontalInset - width)
        let originX = min(max(anchor.midX - width / 2, minX), maxX)
        let stackHeight = height + stackGap + menuHeight
        return (
            width,
            height,
            stackHeight,
            CGPoint(x: originX + width / 2, y: previewTop + stackHeight / 2)
        )
    }

    private func loadPreview(for userId: String) {
        loadGeneration += 1
        let generation = loadGeneration
        guard let viewerId = Auth.auth().currentUser?.uid else {
            applyPreviewStories([])
            return
        }

        Task { @MainActor in
            guard generation == loadGeneration, selection?.userId == userId else { return }

            if let bundle = await StoryTrayService.shared.fetchAuthorStoryBundle(authorId: userId) {
                let visible = bundle.stories.compactMap { StoryRepository.decodeBackendStory($0) }
                if !visible.isEmpty {
                    guard generation == loadGeneration, selection?.userId == userId else { return }
                    applyPreviewStories(visible)
                    return
                }
            }

            guard generation == loadGeneration, selection?.userId == userId else { return }
            loadPreviewLegacy(for: userId, viewerId: viewerId, generation: generation)
        }
    }

    private func loadPreviewLegacy(for userId: String, viewerId: String, generation: Int) {
        StoryRepository().fetchActiveStories(for: userId) { result in
            let stories = (try? result.get()) ?? []
            filterVisibleStories(stories, viewerId: viewerId) { visible in
                guard generation == loadGeneration, selection?.userId == userId else { return }
                applyPreviewStories(visible)
            }
        }
    }

    private func filterVisibleStories(
        _ stories: [Story],
        viewerId: String,
        completion: @escaping ([Story]) -> Void
    ) {
        guard !stories.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var visibleIds: Set<String> = []
        let syncQueue = DispatchQueue(label: "feed.story.ring.preview.visibility")

        for story in stories {
            group.enter()
            PrivacyService.shared.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                if canView, let storyId = story.id {
                    syncQueue.sync {
                        visibleIds.insert(storyId)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let ids = syncQueue.sync { visibleIds }
            let visible = stories
                .filter { story in
                    guard let storyId = story.id else { return false }
                    return ids.contains(storyId)
                }
                .sorted { $0.timestamp < $1.timestamp }
            completion(visible)
        }
    }

    private func applyPreviewStories(_ stories: [Story]) {
        let newIds = stories.compactMap(\.id)
        let oldIds = previewStories.compactMap(\.id)
        if newIds == oldIds, previewStory != nil {
            return
        }

        previewStories = stories
        if previewStories.isEmpty {
            previewStory = nil
            previewStickers = []
            advanceGeneration += 1
            resetPreviewSegmentClock()
            return
        }
        previewIndex = min(previewIndex, previewStories.count - 1)
        previewStory = previewStories[previewIndex]
        previewStickers = resolvedPreviewStickers(for: previewStories[previewIndex])
        resolvedVideoDuration = nil
        isPreviewVideoReady = false
        beginPreviewSegmentClockIfNeeded()
        scheduleAdvance()
    }

    private func resolvedPreviewStickers(for story: Story) -> [StickerItem] {
        story.convertStickersToStickerItems(
            traitCollection: UITraitCollection(displayScale: displayScale)
        )
    }

    private func scheduleAdvance(videoDuration: TimeInterval? = nil) {
        if let videoDuration, videoDuration > 0 {
            resolvedVideoDuration = videoDuration
        }
        advanceGeneration += 1
        let generation = advanceGeneration
        guard let previewStory, !previewStories.isEmpty else { return }
        let duration: TimeInterval
        if previewStory.mediaItem.type == .video {
            guard let videoSeconds = videoDuration ?? resolvedVideoDuration, videoSeconds > 0 else { return }
            duration = max(videoSeconds * videoPreviewFraction, videoPreviewMinimumDuration)
        } else {
            duration = photoPreviewDuration
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard generation == advanceGeneration else { return }
            guard selection != nil, isPresented, !showMuteConfirmation else { return }
            advancePreview()
        }
    }

    private func advancePreview() {
        guard !previewStories.isEmpty else { return }
        previewCycle += 1
        previewIndex = (previewIndex + 1) % previewStories.count
        previewStory = previewStories[previewIndex]
        previewStickers = resolvedPreviewStickers(for: previewStories[previewIndex])
        resolvedVideoDuration = nil
        isPreviewVideoReady = false
        beginPreviewSegmentClockIfNeeded()
        scheduleAdvance()
    }

    private func resetPreviewPlayback() {
        advanceGeneration += 1
        loadGeneration += 1
        previewStories = []
        previewIndex = 0
        previewCycle = 0
        previewStory = nil
        previewStickers = []
        resolvedVideoDuration = nil
        isPreviewVideoReady = false
        resetPreviewSegmentClock()
    }

    private func openCurrentPreviewStory(userId: String) {
        let storyId = previewStory?.id
        let elapsed = currentPreviewElapsed()
        dismissOverlay { onOpenStory(userId, storyId, elapsed) }
    }

    private func beginPreviewSegmentClockIfNeeded() {
        guard previewStory?.mediaItem.type != .video else {
            resetPreviewSegmentClock()
            return
        }
        markPreviewSegmentStart()
    }

    private func markPreviewSegmentStart() {
        previewElapsedBeforePause = 0
        previewSegmentStartedAt = Date()
    }

    private func resetPreviewSegmentClock() {
        previewElapsedBeforePause = 0
        previewSegmentStartedAt = nil
    }

    private func pausePreviewSegmentClock() {
        previewElapsedBeforePause = currentPreviewElapsed()
        previewSegmentStartedAt = nil
    }

    private func resumePreviewSegmentClock() {
        guard previewSegmentStartedAt == nil else { return }
        previewSegmentStartedAt = Date()
    }

    private func currentPreviewElapsed() -> TimeInterval {
        var elapsed = previewElapsedBeforePause
        if let startedAt = previewSegmentStartedAt {
            elapsed += Date().timeIntervalSince(startedAt)
        }
        return max(0, elapsed)
    }

    private func preparePreviewAudioIfNeeded() {
        guard soundEnabledInSession else { return }
        StoryAudioSession.activate()
        Task {
            await MomentsAudioSession.activate(category: .playback, mode: .moviePlayback)
        }
    }

    private func muteAuthor(_ userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != userId else { return }

        FirestoreService.shared.db
            .collection("users")
            .document(currentUserId)
            .updateData([
                "muteSettings.mutedUsers": FieldValue.arrayUnion([userId])
            ]) { error in
                DispatchQueue.main.async {
                    if let error {
                        let fallback = NSLocalizedString("storyContextMenu.actionFailed", comment: "Generic story action failed")
                        successMessage = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
                        return
                    }

                    onMuted(userId)
                    successMessage = NSLocalizedString(
                        "storyContextMenu.mute.successWithHint",
                        comment: "Mute success message with settings hint"
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        dismissOverlay()
                    }
                }
            }
    }

    private func dismissOverlay(then action: (() -> Void)? = nil) {
        dismissGeneration += 1
        advanceGeneration += 1
        let generation = dismissGeneration
        showMuteConfirmation = false
        withAnimation(dismissalAnimation) {
            isPresented = false
        }

        let delay = UIAccessibility.isReduceMotionEnabled ? 0 : 0.26
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == dismissGeneration else { return }
            selection = nil
            action?()
        }
    }
}
