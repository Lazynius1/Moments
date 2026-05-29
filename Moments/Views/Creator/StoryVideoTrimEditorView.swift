import AVFoundation
import SwiftUI

struct StoryVideoTrimEditorView: View {
    let videoURL: URL
    let duration: Double
    let onCancel: () -> Void
    let onComplete: (CreatorMedia) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var trimStart: Double = 0
    @State private var trimDuration: Double
    @State private var thumbnails: [UIImage] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var isMuted = true
    @State private var dragStartTrimStart: Double?
    @State private var dragStartTrimDuration: Double?

    // Playhead tracking & scrubbing state
    @State private var playbackProgress: Double = 0.0
    @State private var previewTime: Double? = nil
    @State private var isDragging: Bool = false
    @State private var isScrubbingPlayhead: Bool = false
    @State private var lastHapticTick: Double = 0.0

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private let minClipDuration: Double = 1.0

    init(
        videoURL: URL,
        duration: Double,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (CreatorMedia) -> Void
    ) {
        self.videoURL = videoURL
        self.duration = duration
        self.onCancel = onCancel
        self.onComplete = onComplete
        _trimDuration = State(initialValue: min(StoryVideoProcessingService.maxStorySegmentDuration, duration))
    }

    private var maxClipDuration: Double {
        min(StoryVideoProcessingService.maxStorySegmentDuration, duration)
    }

    private var trimEnd: Double {
        min(trimStart + trimDuration, duration)
    }

    // MARK: - Adaptive Aesthetics ("Nitidez" Mode)
    private var workspaceBg: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var selectionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var gripColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var dimmingColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var textPrimaryColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black : Color.gray.opacity(0.3)
    }

    var body: some View {
        ZStack {
            workspaceBg.ignoresSafeArea()

            trimCanvas

            if isProcessing {
                processingOverlay
            }
        }
        .task {
            await generateTimeline()
        }
        .alert("videoEditor.error.title", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("videoEditor.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var trimCanvas: some View {
        GeometryReader { proxy in
            let safeAreaInsets = proxy.safeAreaInsets
            let containerWidth = proxy.size.width
            let containerHeight = proxy.size.height

            // Video starts exactly 6pt below the safe area top status bar (leaving a beautiful thin gap)
            let videoTopMargin = max(14, safeAreaInsets.top + 6)

            // Video canvas is fully edge-to-edge horizontally (width = containerWidth)
            let videoWidth = containerWidth
            let videoHeight = videoWidth * 16 / 9

            VStack(spacing: 0) {
                Spacer(minLength: videoTopMargin)

                // 2. Full-bleed edge-to-edge vertical video canvas
                StoryVideoPlayerView(
                    videoURL: videoURL,
                    videoGravity: .resizeAspectFill,
                    isMuted: isMuted,
                    trimStart: trimStart,
                    trimEnd: trimEnd,
                    previewTime: previewTime,
                    onPlayProgress: { progress in
                        // Ignore background updates during manual scrubbing/drags to prevent jumping
                        if !isDragging && !isScrubbingPlayhead {
                            playbackProgress = progress
                        }
                    }
                )
                .frame(width: videoWidth, height: videoHeight)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)) // 28 cornerRadius
                .shadow(color: shadowColor.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 12, x: 0, y: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    // Floating top controls overlayed inside the video player (Clean only buttons)
                    VStack {
                        HStack {
                            // Back button aligned close to the left border
                            Button(action: onCancel) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .white : Color.black.opacity(0.82))
                                    .frame(width: 42, height: 42)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .padding(.leading, 12)

                            Spacer()

                            // Done button aligned close to the right border
                            Button(action: confirmTrim) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .white : Color.black.opacity(0.82))
                                    .frame(width: 42, height: 42)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .disabled(isProcessing)
                            .padding(.trailing, 12)
                        }
                        .padding(.top, 12) // Positioned beautifully below the status bar gap inside the card

                        Spacer()
                    }
                )
                .overlay(
                    // Floating Mute Button in bottom-right corner inside the video player
                    Button(action: toggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color.black.opacity(0.82))
                            .frame(width: 38, height: 38)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .overlay(
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16),
                    alignment: .bottomTrailing
                )
                .overlay(
                    // Selected clip duration badge floating bottom center inside the video player
                    VStack {
                        Spacer()
                        Text(String(format: "%.1fs selected", trimDuration))
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Capsule(), interactive: false)
                            }
                            .overlay(
                                Capsule()
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.bottom, 16)
                    }
                )

                Spacer()

                // 3. Lower bottom timeline trim area container (raised with premium margins)
                timeline
                    .frame(height: 52)
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeAreaInsets.bottom > 0 ? safeAreaInsets.bottom + 14 : 24)
            }
            .frame(width: containerWidth, height: containerHeight)
        }
    }

    private var timeline: some View {
        ZStack(alignment: .center) {
            // 1. Thumbnail strip (44pt high, centered vertically in the 52pt parent ZStack, clipped perfectly to prevent spikes)
            thumbnailStrip
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 2. Inactive dimming overlays (clipped to a centered 44pt frame so outer corners clip perfectly, while inner borders remain perfectly straight!)
            GeometryReader { proxy in
                let width = proxy.size.width
                let startX = width * (trimStart / max(duration, 0.1))
                let rawWindowWidth = width * (trimDuration / max(duration, 0.1))
                let windowWidth = max(44, rawWindowWidth)
                let clampedStartX = min(startX, max(width - windowWidth, 0))

                ZStack(alignment: .leading) {
                    // Left Inactive range dimming (Sharp rectangle, reaches exact beginning)
                    Rectangle()
                        .fill(dimmingColor.opacity(0.65))
                        .frame(width: max(0, clampedStartX), height: 44)

                    // Right Inactive range dimming (Sharp rectangle, reaches exact end)
                    Rectangle()
                        .fill(dimmingColor.opacity(0.65))
                        .frame(width: max(0, width - clampedStartX - windowWidth), height: 44)
                        .offset(x: clampedStartX + windowWidth)
                }
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // Perfect outer clipping, sharp inner alignment!

            // Outer outline frame of the timeline strip
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                .frame(height: 44)

            // 3. Selection border window, draggable playhead & handles (Centered vertically in the 52pt parent ZStack)
            selectionWindow
        }
        .frame(height: 52)
    }

    private var thumbnailStrip: some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(textPrimaryColor.opacity(0.08))
                }
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .clipped()
                }
            }
        }
    }

    private var selectionWindow: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let startX = width * (trimStart / max(duration, 0.1))
            let rawWindowWidth = width * (trimDuration / max(duration, 0.1))
            let windowWidth = max(44, rawWindowWidth)
            let clampedStartX = min(startX, max(width - windowWidth, 0))

            ZStack(alignment: .leading) {
                // Outer selection outline frame (48pt high, centered at offset y: 2, perfectly overlapping by 2pt top/bottom)
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(selectionColor, lineWidth: 4)
                    .frame(width: windowWidth, height: 48)
                    .offset(x: clampedStartX, y: 2)
                    .gesture(selectionDragGesture(totalWidth: width))

                // Playback progress playhead needle cursor (Centered at offset y: 3, wrapped in a 32pt touch hitbox!)
                if !isDragging || isScrubbingPlayhead {
                    let needleX = width * (playbackProgress / max(duration, 0.1))
                    let clampedNeedleX = min(max(clampedStartX, needleX), clampedStartX + windowWidth - 3)

                    Rectangle()
                        .fill(selectionColor)
                        .frame(width: 3, height: 46)
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .frame(width: 32, height: 52) // 32pt target width
                        .contentShape(Rectangle())
                        .offset(x: clampedNeedleX - 14.5, y: 0) // Centered over clampedNeedleX
                        .gesture(needleDragGesture(totalWidth: width, clampedStartX: clampedStartX, windowWidth: windowWidth))
                }

                // Tall grab handle Left (52pt high, offset y: 0, fully covering parent bounds)
                trimHandle(isLeading: true)
                    .offset(x: max(0, clampedStartX - 7), y: 0)
                    .gesture(leadingHandleGesture(totalWidth: width))

                // Tall grab handle Right (52pt high, offset y: 0, fully covering parent bounds)
                trimHandle(isLeading: false)
                    .offset(x: min(width - 14, clampedStartX + windowWidth - 7), y: 0)
                    .gesture(trailingHandleGesture(totalWidth: width))
            }
        }
        .frame(height: 52)
    }

    private func trimHandle(isLeading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selectionColor)
            .frame(width: 14, height: 52)
            .shadow(color: Color.black.opacity(0.2), radius: 3, x: isLeading ? -1 : 1, y: 1)
            .overlay(
                VStack(spacing: 3) {
                    Circle().fill(gripColor.opacity(0.65)).frame(width: 3, height: 3)
                    Circle().fill(gripColor.opacity(0.65)).frame(width: 3, height: 3)
                    Circle().fill(gripColor.opacity(0.65)).frame(width: 3, height: 3)
                }
            )
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                Text("storyVideo.trim.processing")
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        }
    }

    private func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Scrubbing Gestures with boundaries & seconds ticks haptics
    private func triggerTickHaptic(for time: Double) {
        let rounded = time.rounded()
        if abs(rounded - lastHapticTick) >= 1.0 {
            lastHapticTick = rounded
            hapticGenerator.prepare()
            hapticGenerator.impactOccurred()
        }
    }

    private func needleDragGesture(totalWidth: CGFloat, clampedStartX: CGFloat, windowWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isScrubbingPlayhead {
                    isScrubbingPlayhead = true
                    hapticGenerator.prepare()
                    hapticGenerator.impactOccurred()
                }

                // Get absolute coordinate relative to timeline width bounds
                let dragX = value.location.x
                let fraction = dragX / max(totalWidth, 0.1)
                let targetTime = fraction * duration

                // Clamp time strictly inside active [trimStart, trimEnd] trim boundaries!
                let clampedTime = min(max(targetTime, trimStart), trimEnd)

                playbackProgress = clampedTime
                previewTime = clampedTime
                triggerTickHaptic(for: clampedTime)
            }
            .onEnded { _ in
                isScrubbingPlayhead = false
                previewTime = nil // Resume standard looped playback
            }
    }

    private func selectionDragGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTrimStart == nil {
                    isDragging = true
                    hapticGenerator.prepare()
                    hapticGenerator.impactOccurred()
                    dragStartTrimStart = trimStart
                }
                let delta = secondsDelta(for: value.translation.width, totalWidth: totalWidth)
                let newStart = (dragStartTrimStart ?? trimStart) + delta
                let clampedStart = min(max(newStart, 0), max(duration - trimDuration, 0))

                trimStart = clampedStart
                previewTime = clampedStart
                triggerTickHaptic(for: clampedStart)
            }
            .onEnded { _ in
                isDragging = false
                dragStartTrimStart = nil
                previewTime = nil
            }
    }

    private func leadingHandleGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTrimStart == nil {
                    isDragging = true
                    hapticGenerator.prepare()
                    hapticGenerator.impactOccurred()
                    dragStartTrimStart = trimStart
                    dragStartTrimDuration = trimDuration
                }

                let originalStart = dragStartTrimStart ?? trimStart
                let originalDuration = dragStartTrimDuration ?? trimDuration
                let originalEnd = originalStart + originalDuration
                let delta = secondsDelta(for: value.translation.width, totalWidth: totalWidth)
                let newStart = min(
                    max(0, originalStart + delta),
                    originalEnd - minClipDuration
                )

                trimStart = newStart
                trimDuration = min(maxClipDuration, max(minClipDuration, originalEnd - newStart))
                previewTime = newStart
                triggerTickHaptic(for: newStart)
            }
            .onEnded { _ in
                isDragging = false
                dragStartTrimStart = nil
                dragStartTrimDuration = nil
                previewTime = nil
            }
    }

    private func trailingHandleGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTrimDuration == nil {
                    isDragging = true
                    hapticGenerator.prepare()
                    hapticGenerator.impactOccurred()
                    dragStartTrimDuration = trimDuration
                }

                let originalDuration = dragStartTrimDuration ?? trimDuration
                let delta = secondsDelta(for: value.translation.width, totalWidth: totalWidth)
                let newDuration = min(
                    maxClipDuration,
                    max(minClipDuration, originalDuration + delta)
                )
                let finalDuration = min(newDuration, duration - trimStart)

                trimDuration = finalDuration
                let currentEnd = trimStart + finalDuration
                previewTime = currentEnd
                triggerTickHaptic(for: currentEnd)
            }
            .onEnded { _ in
                isDragging = false
                dragStartTrimDuration = nil
                previewTime = nil
            }
    }

    private func secondsDelta(for translationWidth: CGFloat, totalWidth: CGFloat) -> Double {
        guard totalWidth > 0 else { return 0 }
        return Double(translationWidth / totalWidth) * duration
    }

    private func generateTimeline() async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 284)
        let count = 10

        var generated: [UIImage] = []
        for index in 0..<count {
            let seconds = duration * (Double(index) / Double(max(count - 1, 1)))
            do {
                let (cgImage, _) = try await generator.image(
                    at: CMTime(seconds: seconds, preferredTimescale: 600)
                )
                generated.append(UIImage(cgImage: cgImage))
            } catch {
                continue
            }
        }

        await MainActor.run {
            thumbnails = generated
        }
    }

    private func confirmTrim() {
        isProcessing = true
        Task {
            do {
                let media = try await StoryVideoProcessingService.shared.exportStoryClip(
                    videoURL: videoURL,
                    start: trimStart,
                    end: trimEnd
                )
                await MainActor.run {
                    isProcessing = false
                    onComplete(media)
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func formatTime(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
