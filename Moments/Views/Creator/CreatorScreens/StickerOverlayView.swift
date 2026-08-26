import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct StickerOverlayView: View {
    @Binding var sticker: StickerItem // ✅ USAR BINDING PARA ACTUALIZACIÓN DIRECTA
    let canvasSize: CGSize
    let isSelected: Bool
    let isDragging: Bool
    let isContentEditing: Bool
    @Binding var activeEditingStickerId: String?
    let onUpdate: (StickerItem) -> Void
    let onDelete: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    let onStickerTapped: (StickerItem) -> Void

    @State private var currentPosition: CGPoint
    @State private var scale: CGFloat
    @State private var rotation: Angle
    @State private var showInteractionFeedback = false
    @State private var selfieCaptureTrigger = false
    @State private var selfieSwitchCameraTrigger = false
    @State private var lastSelfieSwitchAt: Date = .distantPast
    @State private var dragOffset: CGSize = .zero // ✅ Offset para evitar el salto al centro al tocar
    @State private var contentDragStartOffset: CGSize?
    @State private var contentPinchStartScale: CGFloat?
    @State private var stickerPinchStartScale: CGFloat?

    private var isEditingInline: Bool {
        activeEditingStickerId == sticker.id
    }

    init(sticker: Binding<StickerItem>, canvasSize: CGSize, isSelected: Bool, isDragging: Bool,
         isContentEditing: Bool,
         activeEditingStickerId: Binding<String?>,
         onUpdate: @escaping (StickerItem) -> Void,
         onDelete: @escaping () -> Void,
         onDragChanged: @escaping (CGPoint) -> Void,
         onDragEnded: @escaping (CGPoint) -> Void,
         onStickerTapped: @escaping (StickerItem) -> Void) {
        self._sticker = sticker
        self.canvasSize = canvasSize
        self.isSelected = isSelected
        self.isDragging = isDragging
        self.isContentEditing = isContentEditing
        self._activeEditingStickerId = activeEditingStickerId
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onStickerTapped = onStickerTapped
        _currentPosition = State(initialValue: sticker.wrappedValue.position)
        _scale = State(initialValue: sticker.wrappedValue.scale)
        _rotation = State(initialValue: sticker.wrappedValue.rotation)
    }

    private var stickerSize: CGSize {
        switch sticker.type {
        case .frame: return CGSize(width: 200, height: 240)
        case .poll: return CGSize(width: 300, height: 172)
        case .question: return CGSize(width: 300, height: 132)
        case .questionResponse: return questionResponseStickerRenderSize
        case .quiz: return CGSize(width: 280, height: 220)
        case .weather: return CGSize(width: 140, height: 50)
        case .time: return CGSize(width: 180, height: 80)
        case .emojiSlider:
            return emojiSliderBaseSize
        default: return sticker.image.size
        }
    }

    private var emojiSliderBaseSize: CGSize {
        let prompt = sticker.interactionData?.sliderPrompt ?? ""
        return emojiSliderRenderingSize(prompt: prompt)
    }

    private var minimumStickerScale: CGFloat {
        switch sticker.type {
        case .poll, .question, .quiz:
            return 0.42
        case .time, .weather, .location, .mention, .hashtag, .link, .countdown, .emojiSlider:
            return 0.35
        case .frame, .selfie:
            return 0.3
        default:
            return 0.28
        }
    }

    private var maximumStickerScale: CGFloat {
        let screenBounds = CGRect(origin: .zero, size: canvasSize)
        let hardMaxDimension: CGFloat = 2048
        let hardMaxScaleWidth = hardMaxDimension / max(stickerSize.width, 1)
        let hardMaxScaleHeight = hardMaxDimension / max(stickerSize.height, 1)
        let hardSafeMaxScale = min(hardMaxScaleWidth, hardMaxScaleHeight)

        if sticker.type == .shareMoment,
           sticker.videoURL != nil,
           (sticker.interactionData?.mediaCount ?? 1) == 1,
           (sticker.interactionData?.cardLayoutVariant ?? 0) % 2 == 1 {
            let fillScale = max(
                screenBounds.width / max(stickerSize.width, 1),
                screenBounds.height / max(stickerSize.height, 1)
            )
            return min(hardSafeMaxScale, max(fillScale, minimumStickerScale))
        }

        let widthPadding: CGFloat
        let heightRatio: CGFloat
        let typeCap: CGFloat

        switch sticker.type {
        case .poll, .question, .quiz, .emojiSlider:
            widthPadding = 34
            heightRatio = 0.42
            typeCap = 1.45
        case .countdown:
            widthPadding = 40
            heightRatio = 0.34
            typeCap = 1.35
        case .time, .weather, .location, .mention, .hashtag, .link:
            widthPadding = 44
            heightRatio = 0.28
            typeCap = 1.85
        case .frame:
            widthPadding = 28
            heightRatio = 0.68
            typeCap = 2.4
        case .selfie:
            widthPadding = 28
            heightRatio = 0.42
            typeCap = 2.0
        default:
            widthPadding = 24
            heightRatio = 0.78
            typeCap = 4.0
        }

        let maxVisualWidth = max(screenBounds.width - widthPadding, 120)
        let maxVisualHeight = max(screenBounds.height * heightRatio, 120)
        let visualMaxScaleWidth = maxVisualWidth / max(stickerSize.width, 1)
        let visualMaxScaleHeight = maxVisualHeight / max(stickerSize.height, 1)
        let visualSafeMaxScale = min(visualMaxScaleWidth, visualMaxScaleHeight)

        return min(typeCap, hardSafeMaxScale, visualSafeMaxScale)
    }

    private func dampedMagnification(_ value: CGFloat) -> CGFloat {
        let damping: CGFloat = 0.55
        if value >= 1 {
            return 1 + ((value - 1) * damping)
        }
        return 1 - ((1 - value) * damping)
    }

    private var interactiveBoundsSize: CGSize {
        // La tarjeta compartida ya se escala como una sola unidad. Mantener su
        // caja natural estable evita que el layout cambie durante el pellizco.
        if sticker.type == .shareMoment {
            return stickerSize
        }

        return CGSize(
            width: stickerSize.width * max(scale, 1),
            height: stickerSize.height * max(scale, 1)
        )
    }

    private var clampedCurrentPosition: CGPoint {
        clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: interactiveBoundsSize.width, height: interactiveBoundsSize.height)


            // Los Moments compartidos con vídeo también son animados, pero
            // necesitan su renderer contextual (paleta, avatar y fullscreen).
            if sticker.isAnimated && sticker.type != .shareMoment {
                if let videoURL = sticker.videoURL {
                    // ✅ VIDEO STICKER (Loop)
                    ZStack(alignment: .top) {
                        StoryVideoPlayerView(videoURL: videoURL, videoGravity: .resizeAspectFill)
                            .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                            .allowsHitTesting(false)

                        // Header Overlay (Username)
                        if let interactionData = sticker.interactionData, let username = interactionData.username {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))

                                Text(username)
                                    .font(.system(size: legacyPoppinsSize(10), weight: .bold))
                                    .foregroundStyle(.white)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .mask(
                                        LinearGradient(
                                            colors: [.black, .black, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                        }

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.system(size: legacyPoppinsSize(9), weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius))
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                else if sticker.gifURL != nil {
                    AnimatedStickerView(
                        sticker: sticker,
                        size: CGSize(width: sticker.image.size.width, height: sticker.image.size.height)
                    )
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .allowsHitTesting(false)
                }
            } else if isLiveSelfieSticker {
                ZStack {
                    SelfieStickerLiveCameraView(
                        captureTrigger: $selfieCaptureTrigger,
                        switchCameraTrigger: $selfieSwitchCameraTrigger
                    ) { capturedImage in
                        let targetSize = max(sticker.image.size.width, 100)
                        let stickerImage = makeCapturedSelfieStickerImage(from: capturedImage, size: targetSize)
                        let capturedSticker = StickerItem(
                            id: sticker.id,
                            image: stickerImage,
                            position: currentPosition,
                            scale: scale,
                            rotation: rotation,
                            gifURL: nil,
                            videoURL: nil,
                            isAnimated: false,
                            type: .selfie,
                            interactionData: nil
                        )
                        sticker = capturedSticker
                        onUpdate(capturedSticker)
                    }
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                    .clipShape(Circle())

                    Circle()
                        .stroke(Color.black.opacity(0.04), lineWidth: max(0.5, sticker.image.size.width * 0.005))
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                                .padding(8)
                        }
                    }
                }
                .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                .allowsHitTesting(false)
            } else if sticker.type == .poll, sticker.interactionData?.pollData != nil {
                // POLL INTERACTIVO
                InteractivePollSticker(
                    pollData: Binding(
                        get: { sticker.interactionData?.pollData ?? [] },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.pollData = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    selectedOption: .constant(nil),
                    hasVoted: .constant(false),
                    voteCounts: .constant([:]),
                    totalVotes: .constant(0),
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    isEditingInline: isEditingInline,
                    onVote: { _ in }
                )
                .frame(width: 300, height: 172)
                .allowsHitTesting(isEditingInline)
            } else if sticker.type == .question, sticker.interactionData?.questionText != nil {
                // QUESTION INTERACTIVO
                InteractiveQuestionSticker(
                    questionText: Binding(
                        get: { sticker.interactionData?.questionText ?? "" },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.questionText = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    isEditingInline: isEditingInline,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .frame(width: 300, height: 132)
                .allowsHitTesting(isEditingInline)
            } else if sticker.type == .questionResponse,
                      let responseText = sticker.interactionData?.questionText {
                QuestionResponseStoryStickerCardView(
                    questionText: responseText,
                    styleVariant: sticker.interactionData?.styleVariant ?? 0
                )
                .frame(
                    width: questionResponseStickerRenderSize.width,
                    height: questionResponseStickerRenderSize.height
                )
                .allowsHitTesting(false)
            } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
                // LOCATION INTERACTIVO
                InteractiveLocationSticker(
                    locationName: locationName,
                    coordinate: sticker.interactionData?.locationCoordinate,
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .hashtag, sticker.interactionData?.hashtag != nil {
                StickerHashtagCardView(
                    hashtag: Binding(
                        get: { sticker.interactionData?.hashtag ?? "" },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.hashtag = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    isEditingInline: isEditingInline
                )
                .allowsHitTesting(isEditingInline)
            } else if sticker.type == .mention, let username = sticker.interactionData?.username {
                // MENTION INTERACTIVO
                InteractiveMentionSticker(
                    username: username,
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    onTap: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .link, let linkURL = sticker.interactionData?.linkURL {
                StickerLinkCardView(
                    title: sticker.interactionData?.linkTitle ?? stickerHostLabel(from: linkURL),
                    styleVariant: sticker.interactionData?.styleVariant ?? 0
                )
                .allowsHitTesting(false)
            } else if sticker.type == .countdown,
                      sticker.interactionData?.countdownTitle != nil,
                      sticker.interactionData?.countdownTargetAtMs != nil {
                StickerCountdownCardView(
                    title: Binding(
                        get: { sticker.interactionData?.countdownTitle ?? "" },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.countdownTitle = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    targetAtMs: Binding(
                        get: { sticker.interactionData?.countdownTargetAtMs ?? (Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000) },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.countdownTargetAtMs = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    isEditingInline: isEditingInline
                )
                .allowsHitTesting(isEditingInline)
            } else if sticker.type == .emojiSlider,
                      sticker.interactionData?.sliderPrompt != nil,
                      let sliderEmoji = sticker.interactionData?.sliderEmoji {
                StickerEmojiSliderCardView(
                    prompt: Binding(
                        get: { sticker.interactionData?.sliderPrompt ?? "" },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.sliderPrompt = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    emoji: sliderEmoji,
                    value: 0.5,
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    isEditingInline: isEditingInline
                )
                .allowsHitTesting(isEditingInline)
            } else if sticker.type == .shareMoment {
                SharedMomentStoryCardView(
                    image: sticker.image,
                    videoURL: sticker.videoURL,
                    username: sticker.interactionData?.username
                        ?? NSLocalizedString("storyEditor.mention.userFallback", comment: "Fallback username for shared Moment"),
                    userId: sticker.interactionData?.userId,
                    profileImagePath: sticker.interactionData?.profileImagePath,
                    sharedMediaPath: sticker.interactionData?.sharedMediaPath,
                    caption: sticker.interactionData?.caption,
                    mediaCount: sticker.interactionData?.mediaCount ?? 1,
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    cardLayoutVariant: sticker.interactionData?.cardLayoutVariant ?? 0
                )
                .allowsHitTesting(false)

            } else if sticker.type == .weather, let weatherSymbol = sticker.interactionData?.weatherSymbol {

                // WEATHER ANIMADO
                AnimatedWeatherSticker(
                    weatherSymbol: weatherSymbol,
                    temperature: sticker.interactionData?.questionText ?? "🌤️"
                )
                .frame(width: 140, height: 50)
                .allowsHitTesting(false)
            } else if sticker.type == .time {
                StickerTimeCardView(
                    timeText: sticker.interactionData?.questionText ?? MomentsFormat.smartDate(from: .now, context: .timeOnly),
                    dateText: sticker.interactionData?.caption ?? MomentsFormat.smartDate(from: .now, context: .numericDate),
                    styleVariant: sticker.interactionData?.styleVariant ?? 0
                )
                .allowsHitTesting(false)
            } else if sticker.type == .frame {
                InteractiveFrameSticker(
                    image: sticker.image,
                    caption: sticker.interactionData?.caption,
                    frameStyle: StoryPolaroidFrameStyle(rawValueOrDefault: sticker.interactionData?.frameStyle),
                    contentScale: sticker.interactionData?.contentScale ?? 1.0,
                    contentOffset: CGSize(
                        width: sticker.interactionData?.contentOffsetX ?? 0,
                        height: sticker.interactionData?.contentOffsetY ?? 0
                    ),
                    isEditing: true
                )
                .frame(width: 200, height: 240)
                .allowsHitTesting(false)
            } else if sticker.type == .quiz,
                      sticker.interactionData?.quizQuestion != nil,
                      sticker.interactionData?.quizOptions != nil {
                StickerQuizCardView(
                    question: Binding(
                        get: { sticker.interactionData?.quizQuestion ?? "" },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.quizQuestion = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    options: Binding(
                        get: { sticker.interactionData?.quizOptions ?? [] },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.quizOptions = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    selectedIndex: nil,
                    correctIndex: Binding(
                        get: { sticker.interactionData?.quizCorrectIndex },
                        set: { newValue in
                            var data = sticker.interactionData ?? StickerItem.StickerInteractionData()
                            data.quizCorrectIndex = newValue
                            sticker.interactionData = data
                            onUpdate(sticker)
                        }
                    ),
                    styleVariant: sticker.interactionData?.styleVariant ?? 0,
                    isEditingInline: isEditingInline,
                    onSelect: { _ in }
                )
                .frame(width: 300)
                .allowsHitTesting(isEditingInline)
            } else if sticker.type == .audio {
                InteractiveAudioStickerView(
                    audioURL: sticker.interactionData?.audioURL ?? "",
                    duration: sticker.interactionData?.audioDuration ?? 15.0
                )
                .allowsHitTesting(false)
            } else {
                // STICKER ESTÁTICO / IMAGEN (Emoji, Generic, etc.)
                // ✅ FIX: Usar tamaño natural de la imagen
                if sticker.type == .selfie {
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                } else {
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit) // Asegurar aspecto correcto
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius))
                        .allowsHitTesting(false)
                }
            }
        }
        .rotationEffect(rotation)
        .scaleEffect(showInteractionFeedback ? 1.05 : 1.0)
        .scaleEffect(scale)
        .opacity(1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingInline {
                handleStickerTap()
            }
        }
        // ✅ SINCRONIZAR CON EL PADRE PARA EL "VUELO HERO"
        .onChange(of: sticker.position) { _, newPos in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentPosition = clampedStickerPosition(newPos, scale: scale, rotation: rotation)
            }
        }
        .onChange(of: sticker.scale) { _, newScale in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
                let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
                currentPosition = clampedPosition
                sticker.position = clampedPosition
            }
        }
        .onChange(of: sticker.rotation) { _, newRot in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                rotation = newRot
                let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: newRot)
                currentPosition = clampedPosition
                sticker.position = clampedPosition
            }
        }
        .onChange(of: canvasSize) { _, _ in
            let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
            currentPosition = clampedPosition
            sticker.position = clampedPosition
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    if isEditingInline { return }
                    guard isLiveSelfieSticker else { return }
                    lastSelfieSwitchAt = Date()
                    selfieSwitchCameraTrigger.toggle()
                    HapticManager.shared.mediumImpact()
                }
        )
        .gesture(
            DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Usar el canvas global para estabilidad absoluta
                .onChanged { value in
                    if isEditingInline { return }
                    if isContentEditing, sticker.type == .frame {
                        let baseOffset = contentDragStartOffset ?? frameContentOffset
                        if contentDragStartOffset == nil {
                            contentDragStartOffset = baseOffset
                        }

                        let stickerScale = max(scale, 0.0001)
                        let proposedOffset = CGSize(
                            width: baseOffset.width + (value.translation.width / stickerScale),
                            height: baseOffset.height + (value.translation.height / stickerScale)
                        )

                        updateFrameContentOffset(proposedOffset)
                        return
                    }

                    if dragOffset == .zero {
                        // Calcular la distancia desde el centro del sticker hasta donde pusimos el dedo
                        dragOffset = CGSize(
                            width: value.startLocation.x - currentPosition.x,
                            height: value.startLocation.y - currentPosition.y
                        )
                    }

                    let newPos = CGPoint(
                        x: value.location.x - dragOffset.width,
                        y: value.location.y - dragOffset.height
                    )

                    let clampedPosition = clampedStickerPosition(newPos, scale: scale, rotation: rotation)
                    currentPosition = clampedPosition
                    onDragChanged(clampedPosition)
                    sticker.position = clampedPosition
                }
                .onEnded { _ in
                    if isEditingInline { return }
                    if isContentEditing, sticker.type == .frame {
                        contentDragStartOffset = nil
                        return
                    }

                    dragOffset = .zero // Resetear para el próximo arrastre
                    let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
                    currentPosition = clampedPosition
                    sticker.position = clampedPosition
                    onDragEnded(clampedPosition)
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if isEditingInline { return }
                    if isContentEditing, sticker.type == .frame {
                        let baseScale = contentPinchStartScale ?? max(sticker.interactionData?.contentScale ?? 1.0, 1.0)
                        if contentPinchStartScale == nil {
                            contentPinchStartScale = baseScale
                        }

                        updateFrameContentScale(baseScale * value.magnification)
                        return
                    }

                    let baseScale = stickerPinchStartScale ?? sticker.scale
                    if stickerPinchStartScale == nil {
                        stickerPinchStartScale = sticker.scale
                    }

                    let newScale = baseScale * dampedMagnification(value.magnification)
                    scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
                    let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
                    currentPosition = clampedPosition
                    sticker.position = clampedPosition
                }
                .onEnded { _ in
                    if isEditingInline { return }
                    if isContentEditing, sticker.type == .frame {
                        contentPinchStartScale = nil
                        return
                    }

                    sticker.scale = scale
                    let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
                    currentPosition = clampedPosition
                    sticker.position = clampedPosition
                    stickerPinchStartScale = nil
                }
        )
        .simultaneousGesture(
            RotateGesture()
                .onChanged { value in
                    if isEditingInline { return }
                    guard !(isContentEditing && sticker.type == .frame) else { return }
                    rotation = sticker.rotation + value.rotation
                    let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
                    currentPosition = clampedPosition
                    sticker.position = clampedPosition
                }
                .onEnded { value in
                    if isEditingInline { return }
                    guard !(isContentEditing && sticker.type == .frame) else { return }
                    sticker.rotation = rotation
                    let clampedPosition = clampedStickerPosition(currentPosition, scale: scale, rotation: rotation)
                    currentPosition = clampedPosition
                    sticker.position = clampedPosition
                }
        )
        .position(clampedCurrentPosition) // ✅ Posicionar en el lienzo global al final
        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: showInteractionFeedback), value: showInteractionFeedback)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: rotation)
    }

    private func handleStickerTap() {
        if isEditingInline { return }
        if isLiveSelfieSticker {
            // Evita capturar justo después de long-press para cambiar cámara.
            if Date().timeIntervalSince(lastSelfieSwitchAt) < 0.35 { return }
            selfieCaptureTrigger.toggle()
            HapticManager.shared.mediumImpact()
            return
        }

        // ✅ Feedback visual MUY sutil
        withAnimation(.spring(response: 0.15, dampingFraction: 0.9)) {
            showInteractionFeedback = true
        }

        // ✅ Feedback háptico ligero
        HapticManager.shared.lightImpact()

        // ✅ Llamar al handler
        onStickerTapped(sticker)

        // Reset feedback visual rápido
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.15)) {
                showInteractionFeedback = false
            }
        }
    }

    @ViewBuilder
    private func emojiSliderEditorView(prompt: String, emoji: String) -> some View {
        Image(uiImage: sticker.image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: sticker.image.size.width, height: sticker.image.size.height)
        .allowsHitTesting(false)
    }

    private var isLiveSelfieSticker: Bool {
        sticker.type == .selfie && sticker.interactionData?.caption == "selfie_live"
    }

    private var frameContentOffset: CGSize {
        CGSize(
            width: sticker.interactionData?.contentOffsetX ?? 0,
            height: sticker.interactionData?.contentOffsetY ?? 0
        )
    }

    private func updateFrameContentOffset(_ proposedOffset: CGSize) {
        let clamped = clampedFrameContentOffset(
            proposedOffset,
            imageSize: sticker.image.size,
            contentScale: sticker.interactionData?.contentScale ?? 1.0
        )

        var interaction = sticker.interactionData ?? StickerItem.StickerInteractionData()
        interaction.contentOffsetX = clamped.width
        interaction.contentOffsetY = clamped.height
        sticker.interactionData = interaction
    }

    private func updateFrameContentScale(_ proposedScale: CGFloat) {
        let clampedScale = min(max(proposedScale, 1.0), 4.0)
        var interaction = sticker.interactionData ?? StickerItem.StickerInteractionData()
        interaction.contentScale = clampedScale

        let currentOffset = CGSize(
            width: interaction.contentOffsetX ?? 0,
            height: interaction.contentOffsetY ?? 0
        )
        let clampedOffset = clampedFrameContentOffset(
            currentOffset,
            imageSize: sticker.image.size,
            contentScale: clampedScale
        )
        interaction.contentOffsetX = clampedOffset.width
        interaction.contentOffsetY = clampedOffset.height
        sticker.interactionData = interaction
    }

    private func clampedFrameContentOffset(_ offset: CGSize, imageSize: CGSize, contentScale: CGFloat) -> CGSize {
        let viewportSize = CGSize(width: 180, height: 180)
        let imageRatio = imageSize.width / max(imageSize.height, 0.0001)
        let viewportRatio = viewportSize.width / max(viewportSize.height, 0.0001)

        let baseSize: CGSize
        if imageRatio > viewportRatio {
            let height = viewportSize.height
            baseSize = CGSize(width: height * imageRatio, height: height)
        } else {
            let width = viewportSize.width
            baseSize = CGSize(width: width, height: width / max(imageRatio, 0.0001))
        }

        let safeScale = max(contentScale, 1.0)
        let drawSize = CGSize(width: baseSize.width * safeScale, height: baseSize.height * safeScale)
        let maxOffsetX = max(0, (drawSize.width - viewportSize.width) / 2)
        let maxOffsetY = max(0, (drawSize.height - viewportSize.height) / 2)

        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    private func clampedStickerPosition(
        _ proposedPosition: CGPoint,
        scale proposedScale: CGFloat,
        rotation proposedRotation: Angle
    ) -> CGPoint {
        let bounds = rotatedStickerBoundingSize(
            scale: max(proposedScale, minimumStickerScale),
            rotation: proposedRotation
        )
        let visualWidth = min(bounds.width, canvasSize.width)
        let visualHeight = min(bounds.height, canvasSize.height)
        let halfWidth = visualWidth / 2
        let halfHeight = visualHeight / 2

        return CGPoint(
            x: min(max(proposedPosition.x, halfWidth), canvasSize.width - halfWidth),
            y: min(max(proposedPosition.y, halfHeight), canvasSize.height - halfHeight)
        )
    }

    private func rotatedStickerBoundingSize(scale: CGFloat, rotation: Angle) -> CGSize {
        let scaledWidth = stickerSize.width * scale
        let scaledHeight = stickerSize.height * scale
        let radians = rotation.radians
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))

        let rotatedWidth = (scaledWidth * cosine) + (scaledHeight * sine)
        let rotatedHeight = (scaledWidth * sine) + (scaledHeight * cosine)

        return CGSize(width: rotatedWidth, height: rotatedHeight)
    }

    private func makeCapturedSelfieStickerImage(from originalImage: UIImage, size: CGFloat) -> UIImage {
        let selfieImage = downscaleSelfieImageIfNeeded(originalImage)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let circlePath = UIBezierPath(ovalIn: rect)

            context.cgContext.saveGState()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: UIColor.black.withAlphaComponent(0.12).cgColor)
            UIColor.white.setFill()
            circlePath.fill()
            context.cgContext.restoreGState()

            let imageRect = rect.insetBy(dx: size * 0.012, dy: size * 0.012)
            let imageCirclePath = UIBezierPath(ovalIn: imageRect)
            context.cgContext.saveGState()
            imageCirclePath.addClip()

            let aspectRatio = selfieImage.size.width / max(selfieImage.size.height, 1)
            let drawRect: CGRect
            if aspectRatio > 1 {
                let drawHeight = imageRect.height
                let drawWidth = drawHeight * aspectRatio
                let drawX = imageRect.midX - drawWidth / 2
                drawRect = CGRect(x: drawX, y: imageRect.minY, width: drawWidth, height: drawHeight)
            } else {
                let drawWidth = imageRect.width
                let drawHeight = drawWidth / max(aspectRatio, 0.0001)
                let drawY = imageRect.midY - drawHeight / 2
                drawRect = CGRect(x: imageRect.minX, y: drawY, width: drawWidth, height: drawHeight)
            }

            selfieImage.draw(in: drawRect)
            context.cgContext.restoreGState()

            UIColor.black.withAlphaComponent(0.04).setStroke()
            circlePath.lineWidth = max(0.5, size * 0.005)
            circlePath.stroke()
        }
    }

    private func downscaleSelfieImageIfNeeded(_ image: UIImage, maxDimension: CGFloat = 900) -> UIImage {
        if image.size.width <= maxDimension && image.size.height <= maxDimension {
            return image
        }

        let aspectRatio = image.size.width / max(image.size.height, 1)
        let newSize: CGSize
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
struct SelfieStickerLiveCameraView: UIViewRepresentable {
    @Binding var captureTrigger: Bool
    @Binding var switchCameraTrigger: Bool
    let onPhotoCaptured: (UIImage) -> Void

    func makeUIView(context: Context) -> SelfieStickerCameraPreviewView {
        let view = SelfieStickerCameraPreviewView()
        view.onPhotoCaptured = onPhotoCaptured
        return view
    }

    func updateUIView(_ uiView: SelfieStickerCameraPreviewView, context: Context) {
        if captureTrigger != context.coordinator.lastCaptureState {
            context.coordinator.lastCaptureState = captureTrigger
            uiView.capturePhoto()
        }
        if switchCameraTrigger != context.coordinator.lastSwitchCameraState {
            context.coordinator.lastSwitchCameraState = switchCameraTrigger
            uiView.toggleCamera()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCaptureState = false
        var lastSwitchCameraState = false
    }
}

final class SelfieStickerCameraPreviewView: UIView, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "moments.selfieSticker.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var captureEventInteraction: AVCaptureEventInteraction?
    /// Calcula el ángulo de rotación correcto por dispositivo (frontal y trasera pueden montar
    /// el sensor con orientación física distinta; un ángulo fijo para ambas produce fotos giradas).
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    var onPhotoCaptured: ((UIImage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.cornerRadius = 18
        clipsToBounds = true
        configureHardwareCaptureInteraction()
        configureCamera()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        layer.cornerRadius = 18
        clipsToBounds = true
        configureHardwareCaptureInteraction()
        configureCamera()
    }

    deinit {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
    }

    private func configureHardwareCaptureInteraction() {
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.capturePhoto()
        }
        addInteraction(interaction)
        captureEventInteraction = interaction
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            if let connection = self.photoOutput.connection(with: .video) {
                let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = (self.currentCameraPosition == .front)
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleCamera() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let newPosition: AVCaptureDevice.Position = self.currentCameraPosition == .front ? .back : .front
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.session.beginConfiguration()
            if let existing = self.currentInput {
                self.session.removeInput(existing)
            }

            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.currentCameraPosition = newPosition
            } else if let oldInput = self.currentInput, self.session.canAddInput(oldInput) {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.applyPreviewConnectionConfiguration()
            }
        }
    }

    private func configureCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.setupSession()
                }
            }
        default:
            break
        }
    }

    private func setupSession() {
        sessionQueue.async {
            guard !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentCameraPosition),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.currentInput = input

            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                return
            }

            self.session.addOutput(self.photoOutput)
            self.session.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async {
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = self.bounds
                self.layer.insertSublayer(previewLayer, at: 0)
                self.previewLayer = previewLayer
                self.applyPreviewConnectionConfiguration()
            }

            self.session.startRunning()
        }
    }

    private func applyPreviewConnectionConfiguration() {
        if let device = currentInput?.device, let previewLayer {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        }

        guard let previewConnection = previewLayer?.connection else { return }
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? 90
        if previewConnection.isVideoRotationAngleSupported(angle) {
            previewConnection.videoRotationAngle = angle
        }
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = (currentCameraPosition == .front)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let normalized = image.creatorNormalizedUp()
        DispatchQueue.main.async {
            self.onPhotoCaptured?(normalized)
        }
    }
}
