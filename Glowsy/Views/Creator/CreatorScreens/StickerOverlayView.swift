import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct StickerOverlayView: View {
    @Binding var sticker: StickerItem // ✅ USAR BINDING PARA ACTUALIZACIÓN DIRECTA
    let isSelected: Bool
    let isDragging: Bool
    let isContentEditing: Bool
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

    init(sticker: Binding<StickerItem>, isSelected: Bool, isDragging: Bool,
         isContentEditing: Bool,
         onUpdate: @escaping (StickerItem) -> Void,
         onDelete: @escaping () -> Void,
         onDragChanged: @escaping (CGPoint) -> Void,
         onDragEnded: @escaping (CGPoint) -> Void,
         onStickerTapped: @escaping (StickerItem) -> Void) {
        self._sticker = sticker
        self.isSelected = isSelected
        self.isDragging = isDragging
        self.isContentEditing = isContentEditing
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
        case .quiz, .poll, .question: return CGSize(width: 300, height: 320)
        case .weather: return CGSize(width: 140, height: 50)
        case .time: return CGSize(width: 180, height: 80)
        default: return sticker.image.size
        }
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
        let maxDimension: CGFloat = 2048
        let maxScaleWidth = maxDimension / max(stickerSize.width, 1)
        let maxScaleHeight = maxDimension / max(stickerSize.height, 1)
        let safeMaxScale = min(maxScaleWidth, maxScaleHeight)
        return min(4.5, safeMaxScale)
    }

    var body: some View {
        ZStack {
            // ... (resto del contenido del ZStack sin cambios hasta la línea 7405)
            // ✅ SOLUCIÓN DEFINITIVA: Renderizado idéntico al Viewer
            if sticker.isAnimated {
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
                                    .font(.custom("Poppins-Bold", size: 10))
                                    .foregroundColor(.white)

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
                                    .font(.custom("Poppins-Medium", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                else if let gifURL = sticker.gifURL {
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
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                                .padding(8)
                        }
                    }
                }
                .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                .allowsHitTesting(false)
            } else if sticker.type == .poll, let pollData = sticker.interactionData?.pollData {
                // POLL INTERACTIVO
                InteractivePollSticker(
                    pollData: pollData,
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    selectedOption: .constant(nil),
                    hasVoted: .constant(false),
                    voteCounts: .constant([:]),
                    totalVotes: .constant(0),
                    onVote: { _ in }
                )
                .frame(width: 300, height: 172)
                .allowsHitTesting(false)
            } else if sticker.type == .question, let questionText = sticker.interactionData?.questionText {
                // QUESTION INTERACTIVO
                InteractiveQuestionSticker(
                    questionText: questionText,
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .frame(width: 300, height: 132)
                .allowsHitTesting(false)
            } else if sticker.type == .location, let locationName = sticker.interactionData?.location {
                // LOCATION INTERACTIVO
                InteractiveLocationSticker(
                    locationName: locationName,
                    coordinate: sticker.interactionData?.locationCoordinate,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .hashtag, let hashtag = sticker.interactionData?.hashtag {
                // HASHTAG INTERACTIVO
                InteractiveHashtagSticker(
                    hashtag: hashtag,
                    onPauseStory: {},
                    onResumeStory: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .mention, let username = sticker.interactionData?.username {
                // MENTION INTERACTIVO
                InteractiveMentionSticker(
                    username: username,
                    onTap: {}
                )
                .allowsHitTesting(false)
            } else if sticker.type == .link, let linkURL = sticker.interactionData?.linkURL {
                StickerLinkCardView(
                    title: sticker.interactionData?.linkTitle ?? stickerHostLabel(from: linkURL)
                )
                .allowsHitTesting(false)
            } else if sticker.type == .countdown,
                      let countdownTitle = sticker.interactionData?.countdownTitle,
                      let targetAtMs = sticker.interactionData?.countdownTargetAtMs {
                StickerCountdownCardView(title: countdownTitle, targetAtMs: targetAtMs)
                    .allowsHitTesting(false)
            } else if sticker.type == .emojiSlider,
                      let sliderPrompt = sticker.interactionData?.sliderPrompt,
                      let sliderEmoji = sticker.interactionData?.sliderEmoji {
                StickerEmojiSliderCardView(
                    prompt: sliderPrompt,
                    emoji: sliderEmoji,
                    value: 0.5
                )
                .frame(width: emojiSliderRenderingSize(prompt: sliderPrompt).width, height: emojiSliderRenderingSize(prompt: sliderPrompt).height)
                .allowsHitTesting(false)
            } else if sticker.type == .shareMoment {
                // ✅ SHARE MOMENT: Renderizado dinámico de overlays (Header + Caption)
                ZStack(alignment: .top) {
                    // 1. Imagen base (Captura limpia del marco glass + media)
                    Image(uiImage: sticker.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: sticker.image.size.width, height: sticker.image.size.height)

                    // 2. Video Overlay (si existe)
                    if let videoURL = sticker.videoURL {
                        StickerVideoPlayer(url: videoURL)
                           .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                           .allowsHitTesting(false)
                    }

                    // 3. Dynamic Overlays (Mismo diseño que en el Viewer)
                    ZStack(alignment: .top) {
                        Color.clear // Contenedor

                        // Header (Username + Profile)
                        HStack(spacing: 10) {
                            if let interactionData = sticker.interactionData,
                               let userId = interactionData.userId {
                                AsyncProfileImageView(userId: userId)
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 34, height: 34)
                                    .foregroundColor(.white.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                Text(sticker.interactionData?.username ?? "User")
                                    .font(.custom("Poppins-Bold", size: 13))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
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

                        // Caption Overlay (Bottom)
                        if let caption = sticker.interactionData?.caption, !caption.isEmpty {
                            VStack {
                                Spacer()
                                Text(caption)
                                    .font(.custom("Poppins-Medium", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .padding(.bottom, 10)
                            }
                        }

                        // Gallery Indicator (Top Right)
                        if (sticker.interactionData?.mediaCount ?? 0) > 1 {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.on.square.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .padding(12)
                                        .padding(.top, 42) // Below header text
                                }
                                Spacer()
                            }
                        }
                    }
                    .frame(width: sticker.image.size.width, height: sticker.image.size.height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
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
                    timeText: sticker.interactionData?.questionText ?? Date.now.formatted(date: .omitted, time: .shortened),
                    dateText: sticker.interactionData?.caption ?? Date.now.formatted(date: .numeric, time: .omitted)
                )
                .allowsHitTesting(false)
            } else if sticker.type == .frame {
                InteractiveFrameSticker(
                    image: sticker.image,
                    caption: sticker.interactionData?.caption,
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
                      let question = sticker.interactionData?.quizQuestion,
                      let options = sticker.interactionData?.quizOptions {
                InteractiveQuizSticker(
                    storyId: "preview",
                    userId: "preview",
                    stickerId: sticker.id,
                    question: question,
                    options: options,
                    correctIndex: sticker.interactionData?.quizCorrectIndex ?? 0,
                    isEditing: true
                )
                .frame(width: 300)
                .allowsHitTesting(false)
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
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .allowsHitTesting(false)
                }
            }
        }
        .rotationEffect(rotation)
        .scaleEffect(isDragging ? 0.9 : (showInteractionFeedback ? 1.05 : 1.0))
        .scaleEffect(scale)
        .opacity(isDragging ? 0.8 : 1.0)
        .frame(width: stickerSize.width, height: stickerSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            handleStickerTap()
        }
        // ✅ SINCRONIZAR CON EL PADRE PARA EL "VUELO HERO"
        .onChange(of: sticker.position) { _, newPos in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentPosition = newPos
            }
        }
        .onChange(of: sticker.scale) { _, newScale in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
            }
        }
        .onChange(of: sticker.rotation) { _, newRot in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                rotation = newRot
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard isLiveSelfieSticker else { return }
                    lastSelfieSwitchAt = Date()
                    selfieSwitchCameraTrigger.toggle()
                    HapticManager.shared.mediumImpact()
                }
        )
        .gesture(
            DragGesture(coordinateSpace: .named("storyCanvas")) // ✅ Usar el canvas global para estabilidad absoluta
                .onChanged { value in
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

                    currentPosition = newPos
                    onDragChanged(newPos)
                    sticker.position = newPos
                }
                .onEnded { _ in
                    if isContentEditing, sticker.type == .frame {
                        contentDragStartOffset = nil
                        return
                    }

                    dragOffset = .zero // Resetear para el próximo arrastre
                    onDragEnded(currentPosition)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if isContentEditing, sticker.type == .frame {
                        let baseScale = contentPinchStartScale ?? max(sticker.interactionData?.contentScale ?? 1.0, 1.0)
                        if contentPinchStartScale == nil {
                            contentPinchStartScale = baseScale
                        }

                        updateFrameContentScale(baseScale * value)
                        return
                    }

                    let newScale = sticker.scale * value
                    scale = min(max(newScale, minimumStickerScale), maximumStickerScale)
                }
                .onEnded { _ in
                    if isContentEditing, sticker.type == .frame {
                        contentPinchStartScale = nil
                        return
                    }

                    sticker.scale = scale
                }
        )
        .simultaneousGesture(
            RotationGesture()
                .onChanged { value in
                    guard !(isContentEditing && sticker.type == .frame) else { return }
                    rotation = sticker.rotation + value
                }
                .onEnded { value in
                    guard !(isContentEditing && sticker.type == .frame) else { return }
                    sticker.rotation = rotation
                }
        )
        .position(currentPosition) // ✅ Posicionar en el lienzo global al final
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showInteractionFeedback)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: rotation)
    }

    private func handleStickerTap() {
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
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
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
            self.photoOutput.isHighResolutionCaptureEnabled = false
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
        guard let previewConnection = previewLayer?.connection else { return }
        if previewConnection.isVideoOrientationSupported {
            previewConnection.videoOrientation = .portrait
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
