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

    @State private var progress: Double = 0.0
    @State private var duration: Double = 5.0
    @State private var isPaused = false
    @State private var hasMarkedAsViewed = false
    @State private var imageAspectRatio: CGFloat = 9.0 / 16.0
    @State private var videoAspectRatio: CGFloat?
    @State private var dragOffset: CGFloat = 0
    @State private var isClosing = false
    @State private var replyText = ""
    @State private var showReactions = false
    @State private var showReactionEmojiPicker = false
    @State private var showSentConfirmation = false
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
        GeometryReader { proxy in
            let resolvedTopInset = max(proxy.safeAreaInsets.top, keyWindowSafeAreaInsets().top)
            let resolvedBottomInset = max(proxy.safeAreaInsets.bottom, keyWindowSafeAreaInsets().bottom)
            let baseCanvasRect = creatorMomentsCaptureRect(
                in: proxy.size,
                topInset: resolvedTopInset,
                bottomInset: resolvedBottomInset
            )
            let canvasRect = CGRect(
                x: baseCanvasRect.origin.x,
                y: baseCanvasRect.origin.y + resolvedTopInset,
                width: baseCanvasRect.width,
                height: baseCanvasRect.height
            )
            let progressY = max(resolvedTopInset + 1, canvasRect.minY - 26)

            ZStack {
                Color(hex: "0B1215").ignoresSafeArea()

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

                viewerChrome(
                    canvasRect: canvasRect,
                    progressY: progressY,
                    screenWidth: proxy.size.width
                )

                if showSentConfirmation {
                    sentConfirmationToast
                        .position(x: canvasRect.midX, y: canvasRect.midY)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .simultaneousGesture(viewerDismissDrag(screenHeight: proxy.size.height))
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.container, edges: .all)
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
                    viewOnceVideo(videoGravity: presentationMode.videoGravity)
                        .frame(width: size.width, height: size.height)
                }

                StoryMediaOverlayRendererView(
                    containerSize: size,
                    textOverlays: overlayTextOverlays,
                    stickerItems: overlayStickerItems,
                    drawingData: overlayDrawingData,
                    storyId: message.id,
                    userId: message.senderId,
                    replayToken: 0,
                    reportsDeckInteractionExclusion: false,
                    allowsStickerHitTesting: false
                )
                .allowsHitTesting(false)
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

    @ViewBuilder
    private func viewerChrome(canvasRect: CGRect, progressY: CGFloat, screenWidth: CGFloat) -> some View {
        ZStack {
            StoryProgressBar(progress: progressFraction)
                .padding(.horizontal, 12)
                .position(x: screenWidth / 2, y: progressY)

            headerView
                .padding(.horizontal, 16)
                .frame(width: canvasRect.width)
                .position(x: canvasRect.midX, y: canvasRect.minY + 26)

            VStack {
                Spacer()

                VStack(spacing: 12) {
                    if showReactions {
                        StoryReactionsStrip(
                            reactions: reactionEmojis,
                            showReactions: showReactions,
                            onReaction: { emoji in sendReaction(emoji) },
                            onMoreReactions: { showReactionEmojiPicker = true }
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }

                    replyBar
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

    private var bottomBarPadding: CGFloat {
        if isKeyboardVisible {
            return keyboardHeight + 8
        }
        // Justo debajo del canvas; el visor ocupa toda la pantalla (ignora safe area).
        return max(keyWindowSafeAreaInsets().bottom, 16) + 8
    }

    // Mismo patrón que la barra de respuesta de historias: texto + reacción rápida
    // + cámara, con el botón de enviar sustituyendo a la cámara en cuanto escribes.
    private var replyBar: some View {
        HStack(spacing: 8) {
            TextField(
                NSLocalizedString("chat.viewOnce.replyPlaceholder", comment: "Reply to view-once placeholder"),
                text: $replyText,
                axis: .vertical
            )
            .foregroundColor(.white)
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
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.001))
            .momentsChromeGlass(in: Capsule(), interactive: true)

            if replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replyBarActionButton(systemImage: showReactions ? "face.smiling.fill" : "face.smiling") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showReactions.toggle()
                    }
                    isPaused = showReactions
                }

                replyBarActionButton(systemImage: "camera.fill") {
                    onOpenCameraReply?()
                    closeViewer()
                }
            } else {
                replyBarActionButton(systemImage: "paperplane.fill", action: sendReplyText)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: replyText.isEmpty)
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
        guard !isReplyFieldFocused, !isKeyboardVisible, !showReactions else { return false }
        guard value.translation.height > 0 else { return false }

        // Same protection idea as StoryViewer's bottomProtectedInset: the reply
        // composer owns this area, so viewer dismiss drag must not start there.
        let bottomChromeHeight: CGFloat = 170
        return value.startLocation.y < screenHeight - bottomChromeHeight
    }

    private func replyBarActionButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.001))
                .momentsChromeGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(PlainButtonStyle())
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            showReactions = false
        }
        flashSentConfirmation()
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
        .foregroundColor(.white)
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

            Button(action: { closeViewer() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.001))
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text("Close"))
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
        overlayStickerItems = message.resolvedStickerItems
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
