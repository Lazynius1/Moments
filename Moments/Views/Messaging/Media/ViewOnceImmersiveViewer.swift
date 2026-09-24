import SwiftUI
import Kingfisher
import AVFoundation
import FirebaseAuth

/// Immersive story-style viewer for view-once media in chat.
struct ViewOnceImmersiveViewer: View {
    let message: EnhancedMessage
    let authorName: String
    let onViewed: () -> Void
    var isReplaySession: Bool = false
    var onReplayConsumed: (() -> Void)? = nil
    var onSendReply: ((String) -> Void)? = nil
    var onSendReaction: ((String) -> Void)? = nil
    var onOpenCameraReply: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.momentsToolbarVerticalEdge) private var toolbarVerticalEdge
    @Environment(\.momentsDivisionRegions) private var divisionRegions
    /// `.unknown` es iPhone. En el Duo la toolbar nativa decide si el carril es vertical.
    @State private var hingePose: ViewOnceHingePose = .unknown

    @State private var progress: Double = 0.0
    @State private var duration: Double = 5.0
    @State private var isPaused = false
    @State private var hasMarkedAsViewed = false
    @State private var imageAspectRatio: CGFloat = 9.0 / 16.0
    @State private var videoAspectRatio: CGFloat?
    @State private var dragOffset: CGFloat = 0
    @State private var isClosing = false
    @State private var replyText = ""
    @State private var showReplyComposer = false
    @State private var showReactions = false
    @State private var showReactionEmojiPicker = false
    @State private var showSentConfirmation = false
    @State private var floatingHearts: [FloatingHeart] = []
    @State private var reactionViewport: CGSize = .zero
    @State private var keyboardHeight: CGFloat = 0
    @State private var isKeyboardVisible = false
    @State private var overlayTextOverlays: [StoryTextOverlayMetadata] = []
    @State private var overlayStickerItems: [StickerItem] = []
    @State private var overlayDrawingData: Data?
    @StateObject private var emojiUsageTracker = EmojiUsageTracker()
    @FocusState private var isReplyFieldFocused: Bool

    private var reactionEmojis: [String] {
        emojiUsageTracker.orderedEmojis(from: EmojiReactionDefaults.story)
    }

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var mediaURL: URL? {
        guard let mediaUrl = message.mediaUrl else { return nil }
        return URL(string: mediaUrl)
    }

    private var relativeTime: String {
        MomentsFormat.relativeTime(from: message.timestamp, style: .conversational(unitsStyle: .full))
    }

    private var currentMediaAspectRatio: CGFloat {
        if message.type == .viewOnceVideo {
            return videoAspectRatio ?? 9.0 / 16.0
        }
        return imageAspectRatio
    }

    private var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, progress / duration))
    }

    private var protectedMediaUpdateToken: AnyHashable {
        let overlayToken = [
            overlayTextOverlays.map(\.id).joined(separator: ","),
            overlayStickerItems.map { "\($0.id):\($0.gifURL?.absoluteString ?? ""):\($0.videoURL?.absoluteString ?? "")" }.joined(separator: ","),
            "\(overlayDrawingData?.count ?? 0)"
        ].joined(separator: "|")

        return [
            message.id,
            String(describing: message.type),
            mediaURL?.absoluteString ?? "",
            String(format: "%.4f", currentMediaAspectRatio),
            message.type == .viewOnceVideo ? "\(isPaused)" : "image",
            overlayToken
        ].joined(separator: "#")
    }

    var body: some View {
        viewOnceRoot
            .modifier(ViewOnceHingeObserver(pose: $hingePose))
    }

    /// Duo. En iPhone (`.unknown` y sin carril) se queda la barra de abajo.
    private var usesViewOnceSystemToolbar: Bool {
        hingePose != .unknown || toolbarVerticalEdge != nil || !divisionRegions.isEmpty
    }

    /// Igual que `StoryViewerScreen`: el carril o una división reservan el canvas.
    private var adaptsForDuoChrome: Bool {
        toolbarVerticalEdge != nil || !divisionRegions.isEmpty
    }

    /// Libro vertical: la barra nativa queda arriba, no al lateral.
    private var usesDuoOpenVerticalChrome: Bool {
        toolbarVerticalEdge == nil && !divisionRegions.isEmpty
    }

    @ViewBuilder
    private var viewOnceRoot: some View {
        if usesViewOnceSystemToolbar {
            NavigationStack {
                viewerBody
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar { viewOnceSystemToolbar }
            }
        } else {
            viewerBody
        }
    }

    private var viewerBody: some View {
        GeometryReader { proxy in
            let windowInsets = keyWindowSafeAreaInsets()
            let viewportSize = stableViewportSize(for: proxy)
            let resolvedTopInset = windowInsets.top
            let resolvedBottomInset = windowInsets.bottom
            let horizontalSafeInsets = adaptsForDuoChrome
                ? (proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing)
                : 0
            let canvasViewportSize = CGSize(
                width: max(viewportSize.width - horizontalSafeInsets, 1),
                height: viewportSize.height
            )
            let baseCanvasRect = creatorMomentsCaptureRect(
                in: canvasViewportSize,
                topInset: resolvedTopInset,
                bottomInset: resolvedBottomInset
            )
            let canvasRect: CGRect = {
                let originX = baseCanvasRect.origin.x
                    + (adaptsForDuoChrome ? proxy.safeAreaInsets.leading : 0)
                if usesDuoOpenVerticalChrome {
                    let topY = creatorMomentsCaptureTopOffset + 14
                    let maxHeight = max(viewportSize.height - resolvedBottomInset - 20 - topY, 1)
                    var height = min(baseCanvasRect.height, maxHeight)
                    var width = height * creatorMomentsCaptureAspectRatio
                    if width > canvasViewportSize.width {
                        width = canvasViewportSize.width
                        height = width / creatorMomentsCaptureAspectRatio
                    }
                    return CGRect(x: originX, y: topY, width: width, height: height)
                }
                return CGRect(
                    x: originX,
                    y: baseCanvasRect.origin.y + (adaptsForDuoChrome ? 0 : resolvedTopInset),
                    width: baseCanvasRect.width,
                    height: baseCanvasRect.height
                )
            }()
            let progressY = usesDuoOpenVerticalChrome
                ? creatorMomentsCaptureTopOffset + 4
                : max(resolvedTopInset + 1, canvasRect.minY - 26)

            ZStack {
                Color(hex: "0B1215")
                    .ignoresSafeArea()
                    .onAppear { reactionViewport = viewportSize }
                    .onChange(of: viewportSize) { _, size in
                        reactionViewport = size
                    }

                mediaCanvas(size: canvasRect.size)
                    .frame(width: canvasRect.width, height: canvasRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                    .position(x: canvasRect.midX, y: canvasRect.midY)
                    .onLongPressGesture(
                        minimumDuration: .infinity,
                        maximumDistance: .infinity,
                        pressing: { pressing in
                            isPaused = pressing
                        },
                        perform: {}
                    )

                StoryMediaOverlayRendererView(
                    containerSize: canvasRect.size,
                    textOverlays: overlayTextOverlays,
                    stickerItems: overlayStickerItems,
                    drawingData: overlayDrawingData,
                    storyId: message.id,
                    userId: message.senderId,
                    replayToken: 0,
                    reportsDeckInteractionExclusion: false,
                    allowsStickerHitTesting: true,
                    onPauseStory: { isPaused = true },
                    onResumeStory: { isPaused = false }
                )
                .frame(width: canvasRect.width, height: canvasRect.height)
                .position(x: canvasRect.midX, y: canvasRect.midY)

                if let revealSticker = overlayStickerItems.first(where: { $0.type == .reveal }) {
                    InteractiveRevealSticker(
                        storyId: message.id,
                        onPauseStory: { isPaused = true },
                        onResumeStory: { isPaused = false },
                        reportsDeckInteractionExclusion: false,
                        revealType: revealSticker.interactionData?.revealType,
                        revealPattern: revealSticker.interactionData?.revealPattern,
                        revealPrimaryColor: revealSticker.interactionData?.revealPrimaryColor,
                        revealSecondaryColor: revealSticker.interactionData?.revealSecondaryColor,
                        revealEffectColor: revealSticker.interactionData?.revealEffectColor
                    )
                    .frame(width: canvasRect.width, height: canvasRect.height)
                    .position(x: canvasRect.midX, y: canvasRect.midY)
                }

                StoryFloatingReactionLayer(
                    hearts: floatingHearts,
                    frameSize: viewportSize,
                    midX: viewportSize.width / 2,
                    midY: viewportSize.height / 2
                )
                .allowsHitTesting(false)

                viewerChrome(
                    canvasRect: canvasRect,
                    progressY: progressY,
                    screenWidth: proxy.size.width
                )
                .zIndex(1)

                if showSentConfirmation {
                    sentConfirmationToast
                        .position(x: canvasRect.midX, y: canvasRect.midY)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .simultaneousGesture(viewerDismissDrag(screenHeight: proxy.size.height))
            .simultaneousGesture(viewerSwipeUpGesture())
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if isReplyFieldFocused {
                            isReplyFieldFocused = false
                        }
                    }
            )
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: adaptsForDuoChrome ? [] : .all)
        .ignoresSafeArea(.keyboard, edges: .all)
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .onReceive(timer) { _ in
            guard !isPaused && !isClosing else { return }
            let nextProgress = progress + 0.1
            progress = nextProgress >= duration ? 0 : nextProgress
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height - keyWindowSafeAreaInsets().bottom
                isKeyboardVisible = true
                isPaused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            isKeyboardVisible = false
            if !isReplyFieldFocused && !showReactions {
                isPaused = false
            }
        }
        .onAppear {
            GlobalVideoManager.shared.pauseAllVideos()
            hydrateOverlayState()
            markAsStarted()
            refreshVideoAspectRatio()
        }
        .onDisappear {
            handleDeletionOnClose()
        }
        .sheet(isPresented: $showReactionEmojiPicker) {
            EmojiPickerView(isPresented: $showReactionEmojiPicker) { emoji in
                showReactionEmojiPicker = false
                sendReaction(emoji)
            }
            .chatPickerSheetPresentation()
        }
    }

    private var shouldMuteVideoForReveal: Bool {
        guard message.type == .viewOnceVideo,
              overlayStickerItems.contains(where: { $0.type == .reveal }),
              !message.id.isEmpty else {
            return false
        }
        return !UserDefaults.standard.bool(forKey: "reveal_revealed_\(message.id)")
    }

    @ViewBuilder
    private func mediaCanvas(size: CGSize) -> some View {
        let presentationMode = StoryMediaLayoutRules.presentationMode(
            for: currentMediaAspectRatio,
            canvasAspectRatio: size.width / max(size.height, 1)
        )

        ScreenshotProtectedView(
            isProtected: true,
            fillsContainer: true,
            cornerRadius: storyViewerCanvasCornerRadius,
            updateToken: protectedMediaUpdateToken
        ) {
            ZStack {
                if presentationMode == .fitWithBlur {
                    blurredMediaBackground(size: size)
                }

                if message.type == .viewOnceImage {
                    viewOnceImage(contentMode: presentationMode.swiftUIContentMode)
                        .frame(width: size.width, height: size.height)
                } else if message.type == .viewOnceVideo {
                    viewOnceVideo(
                        videoGravity: presentationMode.videoGravity,
                        isMuted: shouldMuteVideoForReveal
                    )
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .clipped()
        }
    }

    @ViewBuilder
    private func blurredMediaBackground(size: CGSize) -> some View {
        Group {
            if message.type == .viewOnceImage {
                viewOnceImage(contentMode: .fill)
            } else if message.type == .viewOnceVideo {
                viewOnceVideo(videoGravity: .resizeAspectFill, isMuted: true, tracksProgress: false)
            }
        }
        .frame(width: size.width, height: size.height)
        .blur(radius: 36)
        .overlay(Color.black.opacity(0.35))
        .clipped()
    }

    @ViewBuilder
    private func viewOnceImage(contentMode: SwiftUI.ContentMode) -> some View {
        if let mediaURL {
            KFImage(mediaURL)
                .onSuccess { result in
                    let size = result.image.size
                    guard size.width > 0, size.height > 0 else { return }
                    imageAspectRatio = size.width / size.height
                }
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private func viewOnceVideo(
        videoGravity: AVLayerVideoGravity,
        isMuted: Bool = false,
        tracksProgress: Bool = true
    ) -> some View {
        if let mediaURL {
            MomentsVideoPlayer(
                url: mediaURL,
                isLooping: true,
                isPaused: isPaused,
                isMuted: isMuted,
                videoGravity: videoGravity,
                onDurationReceived: { dur in
                    guard tracksProgress else { return }
                    duration = max(dur, 0.1)
                },
                onProgressUpdate: { current in
                    if tracksProgress && current < 0.2 && progress > duration - 0.4 {
                        progress = 0
                    }
                }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "video.slash")
                    .font(.system(size: 40))
                Text("chat.video.unavailable")
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    @ToolbarContentBuilder
    private var viewOnceSystemToolbar: some ToolbarContent {
        if #available(iOS 27.1, *) {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: closeViewer) {
                    Label("stories.close", systemImage: "xmark")
                }
            }
            .axisBehavior(.verticalPreferred)

            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                        showReplyComposer.toggle()
                    }
                    isReplyFieldFocused = showReplyComposer
                    isPaused = showReplyComposer || showReactions
                } label: {
                    Label(
                        "chat.viewOnce.replyPlaceholder",
                        systemImage: showReplyComposer ? "text.bubble.fill" : "text.bubble"
                    )
                }

                Button {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                        showReactions.toggle()
                    }
                    isPaused = showReactions || showReplyComposer
                } label: {
                    Label("Reacción", systemImage: showReactions ? "heart.fill" : "heart")
                }

                if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        onOpenCameraReply?()
                        closeViewer()
                    } label: {
                        Label("Cámara", systemImage: "camera.fill")
                    }
                } else {
                    Button(action: sendReplyText) {
                        Label("Enviar", systemImage: "paperplane.fill")
                    }
                }
            }
            .axisBehavior(.verticalPreferred)
        }
    }

    @ViewBuilder
    private func viewerChrome(canvasRect: CGRect, progressY: CGFloat, screenWidth: CGFloat) -> some View {
        ZStack {
            StoryProgressBar(progress: progressFraction)
                .padding(.horizontal, 12)
                .frame(width: canvasRect.width)
                .position(x: canvasRect.midX, y: progressY)

            headerView
                .padding(.horizontal, 16)
                .frame(width: canvasRect.width)
                .position(x: canvasRect.midX, y: canvasRect.minY + 26)

            if !usesViewOnceSystemToolbar && isKeyboardVisible {
                Color.black.opacity(0.32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                StoryQuickReactionsGrid(
                    reactions: Array(EmojiReactionDefaults.story.prefix(8))
                ) { reaction in
                    isReplyFieldFocused = false
                    sendReaction(reaction)
                }
                .position(
                    x: canvasRect.midX,
                    y: canvasRect.minY + max(140, (canvasRect.height - keyboardHeight) * 0.62)
                )
            }

            VStack {
                Spacer()

                VStack(spacing: 12) {
                    if showReactions && !isKeyboardVisible {
                        StoryReactionsStrip(
                            reactions: reactionEmojis,
                            showReactions: showReactions,
                            onReaction: { emoji in sendReaction(emoji) },
                            onMoreReactions: { showReactionEmojiPicker = true }
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }

                    if !usesViewOnceSystemToolbar {
                        replyBar()
                    } else if showReplyComposer {
                        replyBar(showsActions: false)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, bottomBarPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: keyboardHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private func stableViewportSize(for proxy: GeometryProxy) -> CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let bounds = scene?.windows.first(where: { $0.isKeyWindow })?.bounds else {
            return proxy.size
        }
        return CGSize(
            width: max(proxy.size.width, bounds.width),
            height: max(proxy.size.height, bounds.height)
        )
    }

    private var bottomBarPadding: CGFloat {
        if isKeyboardVisible {
            return keyboardHeight + 8
        }
        // Justo debajo del canvas; el visor ocupa toda la pantalla (ignora safe area).
        return max(keyWindowSafeAreaInsets().bottom, 16) + 8
    }

    // Mismo patrón que la barra de respuesta de historias: texto + reacción rápida
    // + cámara, con el botón de enviar sustituyendo a la cámara en cuanto escribes.
    private func replyBar(showsActions: Bool = true) -> some View {
        HStack(spacing: 8) {
            TextField(
                NSLocalizedString("chat.viewOnce.replyPlaceholder", comment: "Reply to view-once placeholder"),
                text: $replyText,
                axis: .vertical
            )
            .foregroundStyle(.white)
            .font(.system(size: legacyPoppinsSize(14)))
            .padding(.leading, 4)
            .lineLimit(1...3)
            .focused($isReplyFieldFocused)
            .submitLabel(.send)
            .onSubmit(sendReplyText)
            .onChange(of: isReplyFieldFocused) { _, focused in
                isPaused = focused
            }
            .padding(.horizontal, 16)
            .padding(.vertical, showsActions ? 14 : 10)
            .frame(maxWidth: showsActions ? .infinity : nil)
            .background(Color.white.opacity(0.001))
            .momentsChromeGlass(in: Capsule(), interactive: true)

            if showsActions {
                let replyIsEmpty = replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let keepsReplyActions = !isKeyboardVisible && !isReplyFieldFocused
                HStack(spacing: 2) {
                    if keepsReplyActions && replyIsEmpty {
                        replyChromeIcon(systemImage: showReactions ? "heart.fill" : "heart") {
                            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                                showReactions.toggle()
                            }
                            isPaused = showReactions
                        }
                        replyChromeIcon(systemImage: "camera.fill") {
                            onOpenCameraReply?()
                            closeViewer()
                        }
                    } else if !replyIsEmpty {
                        replyChromeIcon(systemImage: "paperplane.fill", action: sendReplyText)
                            .transition(MotionPolicy.Transition.enterPop)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: replyText.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
        .animation(.easeInOut(duration: 0.2), value: isReplyFieldFocused)
    }

    private func replyChromeIcon(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 34, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func viewerSwipeUpGesture() -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !usesViewOnceSystemToolbar else { return }
                guard !isReplyFieldFocused, !isKeyboardVisible, !showReactions else { return }
                guard value.translation.height < -60, abs(value.translation.width) < 50 else { return }
                isReplyFieldFocused = true
                isPaused = true
            }
    }

    private func viewerDismissDrag(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard shouldHandleDismissDrag(value, screenHeight: screenHeight) else {
                    dragOffset = 0
                    return
                }
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                guard shouldHandleDismissDrag(value, screenHeight: screenHeight) else {
                    dragOffset = 0
                    return
                }
                if value.translation.height > 100 {
                    closeViewer()
                } else {
                    dragOffset = 0
                }
            }
    }

    private func shouldHandleDismissDrag(_ value: DragGesture.Value, screenHeight: CGFloat) -> Bool {
        guard usesViewOnceSystemToolbar else { return false }
        guard !isReplyFieldFocused, !isKeyboardVisible, !showReactions else { return false }
        guard value.translation.height > 0 else { return false }

        // Same protection idea as StoryViewer's bottomProtectedInset: the reply
        // composer owns this area, so viewer dismiss drag must not start there.
        let bottomChromeHeight: CGFloat = 170
        return value.startLocation.y < screenHeight - bottomChromeHeight
    }

    // El texto y la reacción no cierran el visor (como en historias): se envían en
    // segundo plano y se muestra un "enviado" fugaz. Solo la cámara lo cierra,
    // porque necesita presentar otra pantalla a pantalla completa.
    private func sendReplyText() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSendReply?(trimmed)
        replyText = ""
        isReplyFieldFocused = false
        flashSentConfirmation()
    }

    private func sendReaction(_ emoji: String) {
        emojiUsageTracker.increment(emoji)
        onSendReaction?(emoji)
        isReplyFieldFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            showReactions = false
        }
        StoryReactionBurst.emit(
            &floatingHearts,
            emoji: emoji,
            in: reactionViewport
        ) { heartId in
            floatingHearts.removeAll { $0.id == heartId }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !showReactions && !isReplyFieldFocused {
                isPaused = false
            }
        }
    }

    private func flashSentConfirmation() {
        HapticManager.shared.lightImpact()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            showSentConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.25)) {
                showSentConfirmation = false
            }
        }
    }

    private var sentConfirmationToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
            Text("chat.viewOnce.replySent")
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .momentsChromeGlass(in: Capsule(), interactive: false)
    }

    private var headerView: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                avatarView

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(relativeTime)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 6)

            Spacer()

            if !usesViewOnceSystemToolbar {
                Button(action: { closeViewer() }) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(Text("Close"))
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if !message.senderId.isEmpty {
            StoryRingAvatarView(
                userId: message.senderId,
                size: 42,
                lineWidth: 2.1,
                showBaseStroke: true,
                baseStrokeColor: Color.white.opacity(0.16),
                baseStrokeWidth: 1
            )
        } else {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                )
        }
    }

    struct StoryProgressBar: View {
        var progress: Double

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))

                    Capsule()
                        .fill(Color(hex: "FFCC33"))
                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, progress))))
                        .shadow(color: Color(hex: "FFCC33").opacity(0.55), radius: 3, x: 0, y: 0)
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
            .frame(height: 2.5)
        }
    }

    private func refreshVideoAspectRatio() {
        guard message.type == .viewOnceVideo, let mediaURL else { return }

        Task {
            let detected = await Self.detectVideoAspectRatio(from: mediaURL)
            await MainActor.run {
                videoAspectRatio = detected
            }
        }
    }

    private func hydrateOverlayState() {
        overlayTextOverlays = message.resolvedTextOverlays
        overlayStickerItems = message.resolvedStickerItems(traitCollection: UITraitCollection(displayScale: displayScale))
        overlayDrawingData = message.drawingData
    }

    private static func detectVideoAspectRatio(from url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await videoTrack.load(.naturalSize),
              let preferredTransform = try? await videoTrack.load(.preferredTransform) else {
            return nil
        }

        let resolvedSize = StoryViewerScreen.resolvedVideoPresentationSize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        guard resolvedSize.width > 0, resolvedSize.height > 0 else { return nil }
        return resolvedSize.width / resolvedSize.height
    }

    private func markAsStarted() {
        guard !hasMarkedAsViewed else {
            return
        }
        hasMarkedAsViewed = true
        onViewed()
    }

    private func closeViewer() {
        isClosing = true
        dismiss()
    }

    private func handleDeletionOnClose() {
        if message.allowReplay == true, !isReplaySession {
            return
        }

        if isReplaySession, let viewerId = Auth.auth().currentUser?.uid {
            ViewOnceReplaySessionStore.shared.markConsumed(message: message, viewerId: viewerId)
            if message.replayedBy?.contains(viewerId) != true {
                message.replayedBy = (message.replayedBy ?? []) + [viewerId]
            }
            onReplayConsumed?()
        }

        ViewOnceConsumptionService.shared.consume(
            conversationId: message.conversationId,
            messageId: message.id,
            reason: isReplaySession ? .replay : .viewOnce
        ) { error in
            if let error = error {
                LogConfig.log("View-once consume failed: \(error.localizedDescription)", category: "Chat")
            }
        }
    }
}

private enum ViewOnceHingePose {
    case unknown
    case closed
    case partiallyOpen
    case fullyOpen
}

private struct ViewOnceHingeObserver: ViewModifier {
    @Binding var pose: ViewOnceHingePose

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                switch context.hinge?.status {
                case .partiallyOpen:
                    pose = .partiallyOpen
                case .fullyOpen:
                    pose = .fullyOpen
                case .closed:
                    pose = .closed
                default:
                    pose = .unknown
                }
            }
        } else {
            content
        }
    }
}
