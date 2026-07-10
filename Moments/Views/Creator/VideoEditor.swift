import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct SocialVideoEditorView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) var colorScheme

    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 60
    @State private var isPlaying: Bool = false

    // Controles principales
    @State private var trimStartTime: Double = 0
    @State private var trimEndTime: Double = 0
    @State private var selectedClipIndex = 0
    @State private var playbackSpeed: PlaybackSpeed = .normal
    @State private var selectedFormat: VideoFormat = .reels
    @State private var volume: Float = 1.0

    // Estados de UI
    @State private var showingSpeedPicker = false
    @State private var showingFormatPicker = false
    @State private var isDraggingTrimHandle = false
    @State private var trimHandleType: TrimHandleType = .start
    @State private var showingVolumeSlider = false
    @State private var draggingHandle: TrimHandleType? = nil
    @State private var lastDragLocation: CGPoint = .zero

    // Drag/scrubbing states for timeline
    @State private var isScrubbingPlayhead: Bool = false
    @State private var dragStartTrimStart: Double?
    @State private var dragStartTrimDuration: Double?

    // Estados para compresión y procesamiento
    @State private var isProcessing = false
    @State private var processingMessage = "Procesando..."
    @State private var processingProgress: Double = 0
    @State private var showingError = false
    @State private var errorMessage = ""

    // Estados para thumbnails del timeline
    @State private var timelineThumbnails: [UIImage] = []
    @State private var isGeneratingThumbnails = false

    // Estados para thumbnail picker
    @State private var showingThumbnailPicker = false
    @State private var selectedThumbnailTime: Double = 0
    @State private var customThumbnailImage: UIImage? = nil
    private let minClipDuration: Double = 1.0
    @State private var lastHapticTick: Double = 0

    enum PlaybackSpeed: String, CaseIterable {
        case slow = "0.3x"
        case normal = "1x"
        case fast = "2x"
        case veryFast = "3x"

        var multiplier: Float {
            switch self {
            case .slow: return 0.3
            case .normal: return 1.0
            case .fast: return 2.0
            case .veryFast: return 3.0
            }
        }

        var icon: String {
            switch self {
            case .slow: return "tortoise"
            case .normal: return "play"
            case .fast: return "hare"
            case .veryFast: return "hare.fill"
            }
        }
    }

    enum VideoFormat: String, CaseIterable {
        case reels = "9:16"
        case square = "1:1"
        case landscape = "16:9"

        var ratio: CGFloat {
            switch self {
            case .reels: return 9.0/16.0
            case .square: return 1.0
            case .landscape: return 16.0/9.0
            }
        }

        var targetSize: CGSize {
            switch self {
            case .reels: return CGSize(width: 1080, height: 1920)
            case .square: return CGSize(width: 1080, height: 1080)
            case .landscape: return CGSize(width: 1920, height: 1080)
            }
        }

        var targetBitrate: Int {
            switch self {
            case .reels: return 6000000 // 6 Mbps
            case .square: return 5000000 // 5 Mbps
            case .landscape: return 8000000 // 8 Mbps
            }
        }

        var toProcessedMediaAspectRatio: CreatorMedia.AspectRatio {
            switch self {
            case .reels: return .nineBySixteen
            case .square: return .square
            case .landscape: return .landscape
            }
        }

        var displayName: String {
            switch self {
            case .reels: return "Reels"
            case .square: return "Cuadrado"
            case .landscape: return "Horizontal"
            }
        }

        var icon: String {
            switch self {
            case .reels: return "rectangle.portrait.fill"
            case .square: return "square.fill"
            case .landscape: return "rectangle.fill"
            }
        }
    }

    enum TrimHandleType {
        case start, end
    }

    struct ProcessedVideoData {
        let compressedVideoURL: URL
        let thumbnailURL: URL
        let duration: Double
        let fileSize: Int64
        let resolution: CGSize
        let thumbnailImage: UIImage
    }

    var currentVideo: CreatorMedia? {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        return videoItems.indices.contains(selectedClipIndex) ? videoItems[selectedClipIndex] : nil
    }

    // MARK: - Nitidez & Liquid Glass Aesthetics
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

    private var videoPreviewHeight: CGFloat {
        switch selectedFormat {
        case .reels:
            return 600
        case .square:
            return 420
        case .landscape:
            return 320
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedPreviewHeight = resolvedVideoPreviewHeight(in: proxy.size)

            VStack(spacing: 0) {
                headerView

                Spacer(minLength: 8)

                // Video Preview Canvas
                ZStack {
                    workspaceBg

                    videoPreviewSection(
                        maxWidth: proxy.size.width,
                        maxHeight: resolvedPreviewHeight
                    )
                }
                .frame(height: resolvedPreviewHeight)
                .clipped()

                Spacer(minLength: 8)

                // Solid Bottom Panel (unboxed, flat controls & trim)
                VStack(spacing: 0) {
                    controlsSection
                        .padding(.top, 8)

                    if let _ = currentVideo {
                        trimTimelineSection
                            .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? proxy.safeAreaInsets.bottom + 14 : 24)
                    }
                }
                .background(workspaceBg)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(
            ZStack(alignment: .bottom) {
                // Background Tap-to-Dismiss Dim Overlay
                if showingSpeedPicker || showingFormatPicker {
                    Color.black.opacity(colorScheme == .dark ? 0.6 : 0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingSpeedPicker = false
                                showingFormatPicker = false
                            }
                        }
                        .transition(.opacity)
                }

                // Real Liquid Glass floating popovers
                if showingSpeedPicker {
                    speedPickerOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                } else if showingFormatPicker {
                    formatPickerOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                }
            }
        )
        .overlay(
            ZStack(alignment: .top) {
                workspaceBg
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .top)

                if isProcessing {
                    processingOverlay
                }
            }
        )
        .statusBar(hidden: false)
        .navigationBarHidden(true)
        .background(workspaceBg.ignoresSafeArea())
        .onAppear {
            setupVideoPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .alert(NSLocalizedString("videoEditor.error.title", comment: "Error"), isPresented: $showingError) {
            Button(NSLocalizedString("videoEditor.ok", comment: "OK")) { }
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showingThumbnailPicker) {
            ThumbnailPickerView(
                videoURL: currentVideo?.videoURL,
                selectedTime: $selectedThumbnailTime,
                selectedImage: $customThumbnailImage,
                onDismiss: {
                    showingThumbnailPicker = false
                }
            )
        }
    }

    private func resolvedVideoPreviewHeight(in availableSize: CGSize) -> CGFloat {
        let videoCount = selectedMediaItems.filter { $0.type == .video }.count
        let headerHeight: CGFloat = 74
        let spacerHeight: CGFloat = 16
        let controlsHeight: CGFloat = videoCount > 1 ? 190 : 102
        let timelineHeight: CGFloat = currentVideo == nil ? 0 : 104
        let reservedHeight = headerHeight + spacerHeight + controlsHeight + timelineHeight
        let availablePreviewHeight = availableSize.height - reservedHeight
        let fallbackMinimumHeight: CGFloat = selectedFormat == .landscape ? 150 : 180

        return max(fallbackMinimumHeight, min(videoPreviewHeight, availablePreviewHeight))
    }

    // MARK: - Processing Overlay
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: processingProgress)
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: processingProgress), value: processingProgress)

                    Text("\(Int(processingProgress * 100))%")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text(processingMessage)
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundColor(.white)

                    Text("videoEditor.optimizing")
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .background(
                Color.clear
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 40)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: true)
                    }
                    .overlay(
                        Circle()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
            .disabled(isProcessing)

            Spacer()

            Text(NSLocalizedString("videoEditor.edit", comment: "Edit Video"))
                .font(.system(size: legacyPoppinsSize(17), weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()

            if !isProcessing {
                GlowSharePill(
                    title: "creator.next",
                    icon: "chevron.right",
                    isSmall: true
                ) {
                    processAndContinue()
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(workspaceBg.ignoresSafeArea(edges: .top))
        .zIndex(10)
    }

    // MARK: - Video Preview
    private func videoPreviewSection(maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        ZStack {
            if let _ = currentVideo {
                // Video Container with proper Aspect Ratio
                VideoPlayerWrapper(player: player)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.15), radius: 12, x: 0, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .aspectRatio(selectedFormat.ratio, contentMode: .fit)
                    .frame(maxWidth: maxWidth)
                    .frame(maxHeight: maxHeight)
                    .padding(.vertical, 8)

                videoOverlayControls
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        .onTapGesture {
            if !isProcessing {
                togglePlayback()
            }
        }
    }

    private var videoOverlayControls: some View {
        ZStack {
            // Speed indicator badge inside player
            if playbackSpeed != .normal {
                VStack {
                    HStack {
                        VStack(spacing: 4) {
                            Image(systemName: playbackSpeed.icon)
                                .font(.system(size: 16, weight: .bold))
                            Text(playbackSpeed.rawValue)
                                .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(10)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: false)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }

            // Glassmorphic interactive Play Button
            if !isPlaying && !isProcessing {
                Button(action: togglePlayback) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 68, height: 68)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .overlay(
                            Circle()
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                }
            }

            // Volume overlay text
            if showingVolumeSlider {
                 Text("\(Int(volume * 100))%")
                    .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                    .foregroundColor(.white)
                    .padding(20)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
                    }
                    .transition(.opacity)
            }

            // Aspect ratio dashed guides
            if showingFormatPicker {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(.white.opacity(0.4))
                    .aspectRatio(selectedFormat.ratio, contentMode: .fit)
                    .padding(20)
            }
        }
    }

    // MARK: - Trim Timeline Area
    private var trimTimelineSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text(formatTime(max(trimStartTime, currentTime)))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                Text("\(formatTime(trimEndTime - trimStartTime)) de \(formatTime(duration))")
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundColor(.gray)

                Spacer()

                Text(formatTime(trimEndTime))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }

            timelineView
        }
        .frame(height: 84)
        .padding(.horizontal, 16)
        .opacity(isProcessing ? 0.5 : 1.0)
    }

    private var timelineView: some View {
        GeometryReader { timelineGeo in
            let width = timelineGeo.size.width
            let startX = width * (trimStartTime / max(duration, 0.1))
            let windowWidth = max(44, width * ((trimEndTime - trimStartTime) / max(duration, 0.1)))
            let clampedStartX = min(startX, max(width - windowWidth, 0))

            ZStack(alignment: .center) {
                // 1. Thumbnail strip (44pt high, centered vertically in the 52pt parent ZStack, rounded corners clip to remove spikes)
                thumbnailStrip(width: width)
                    .frame(width: width, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // 2. Inactive dimming overlays (clipped to a centered 44pt frame so outer corners clip perfectly, inner borders remain straight)
                ZStack(alignment: .leading) {
                    // Left Inactive range dimming
                    Rectangle()
                        .fill(dimmingColor.opacity(0.65))
                        .frame(width: max(0, clampedStartX), height: 44)

                    // Right Inactive range dimming
                    Rectangle()
                        .fill(dimmingColor.opacity(0.65))
                        .frame(width: max(0, width - clampedStartX - windowWidth), height: 44)
                        .offset(x: clampedStartX + windowWidth)
                }
                .frame(width: width, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Outer outline frame of the timeline strip
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                    .frame(width: width, height: 44)

                // 3. Selection border window & handles (Centered vertically in the 52pt parent ZStack)
                ZStack(alignment: .leading) {
                    // Outer selection outline frame (48pt high, centered at offset y: 2, perfectly overlapping by 2pt top/bottom)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(selectionColor, lineWidth: 4)
                        .frame(width: windowWidth, height: 48)
                        .offset(x: clampedStartX, y: 2)
                        .gesture(selectionDragGesture(totalWidth: width))

                    // Playback progress playhead needle cursor (Centered at offset y: 3, wrapped in a 32pt grab hitbox!)
                    if !isDraggingTrimHandle || isScrubbingPlayhead {
                        let needleX = width * (currentTime / max(duration, 0.1))
                        let clampedNeedleX = min(max(clampedStartX, needleX), clampedStartX + windowWidth - 3)

                        Rectangle()
                            .fill(selectionColor)
                            .frame(width: 3, height: 46)
                            .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                            .frame(width: 32, height: 52)
                            .contentShape(Rectangle())
                            .offset(x: clampedNeedleX - 14.5, y: 0)
                            .gesture(needleDragGesture(totalWidth: width, clampedStartX: clampedStartX, windowWidth: windowWidth))
                    }

                    // Tall grab handle Left (52pt high, offset y: 0, bounded to stay inside timeline)
                    trimHandle(isLeading: true)
                        .offset(x: max(0, clampedStartX - 7), y: 0)
                        .gesture(leadingHandleGesture(totalWidth: width))

                    // Tall grab handle Right (52pt high, offset y: 0, bounded to stay inside timeline)
                    trimHandle(isLeading: false)
                        .offset(x: min(width - 14, clampedStartX + windowWidth - 7), y: 0)
                        .gesture(trailingHandleGesture(totalWidth: width))
                }
                .frame(width: width, height: 52)
            }
            .frame(width: width, height: 52)
        }
        .frame(height: 52)
        .allowsHitTesting(!isProcessing)
    }

    private func trimHandle(isLeading: Bool) -> some View {
        let isDragging = draggingHandle == (isLeading ? .start : .end)

        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selectionColor)
            .frame(width: 14, height: 52)
            .shadow(color: Color.black.opacity(0.2), radius: 3, x: isLeading ? -1 : 1, y: 1)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .overlay(
                VStack(spacing: 3) {
                    Circle().fill(gripColor.opacity(0.65)).frame(width: 3, height: 3)
                    Circle().fill(gripColor.opacity(0.65)).frame(width: 3, height: 3)
                    Circle().fill(gripColor.opacity(0.65)).frame(width: 3, height: 3)
                }
            )
    }

    private func thumbnailStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if timelineThumbnails.isEmpty {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(textPrimaryColor.opacity(0.08))
                }
            } else {
                let thumbnailWidth = width / CGFloat(max(1, timelineThumbnails.count))
                ForEach(Array(timelineThumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumbnailWidth, height: 44)
                        .clipped()
                }
            }
        }
    }

    // MARK: - Controles Inferiores
    private var controlsSection: some View {
        VStack(spacing: 20) {
            let videoItems = selectedMediaItems.filter { $0.type == .video }
            if videoItems.count > 1 {
                clipSelectorView
            }

            // Unboxed spacious control buttons
            HStack(spacing: 12) {
                // Velocidad
                controlButton(
                    icon: playbackSpeed.icon,
                    title: "Velocidad",
                    subtitle: playbackSpeed.rawValue,
                    action: {
                        if !isProcessing {
                            showingSpeedPicker = true
                        }
                    }
                )

                // Formato
                controlButton(
                    icon: selectedFormat.icon,
                    title: "Formato",
                    subtitle: selectedFormat.displayName,
                    action: {
                        if !isProcessing {
                            showingFormatPicker = true
                        }
                    }
                )

                // Portada
                controlButton(
                    icon: "photo.on.rectangle",
                    title: "Portada",
                    subtitle: customThumbnailImage == nil ? "Auto" : "Manual",
                    action: {
                        if !isProcessing {
                            showingThumbnailPicker = true
                        }
                    }
                )

                // Volumen (Unboxed elegant slider control)
                VStack(spacing: 4) {
                    Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 42, height: 42)
                        .background {
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        }
                        .onTapGesture {
                            toggleVolume()
                        }

                    Slider(value: $volume, in: 0...1.0)
                        .tint(selectionColor)
                        .frame(width: 46)
                        .scaleEffect(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .opacity(isProcessing ? 0.5 : 1.0)
        }
        .padding(.vertical, 8)
    }

    private var clipSelectorView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                let videoItems = selectedMediaItems.filter { $0.type == .video }
                ForEach(0..<videoItems.count, id: \.self) { index in
                    Button(action: {
                        if !isProcessing {
                            switchToClip(index: index)
                        }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 60, height: 80)

                            VStack(spacing: 4) {
                                Image(systemName: "play.rectangle")
                                    .font(.title3)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Text("\(index + 1)")
                                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }

                            if index == selectedClipIndex {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectionColor, lineWidth: 2)
                                    .frame(width: 60, height: 80)
                            }
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            .padding(.horizontal)
        }
    }

    private func controlButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                    }

                Text(title)
                    .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text(subtitle)
                    .font(.system(size: legacyPoppinsSize(9)))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isProcessing)
    }

    // MARK: - Liquid Glass Overlay Sheets
    private var speedPickerOverlay: some View {
        VStack(spacing: 0) {
            // Pill indicator on top
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack {
                Button(NSLocalizedString("videoEditor.cancel", comment: "Cancel")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingSpeedPicker = false
                    }
                }
                .font(.system(size: legacyPoppinsSize(15)))
                .foregroundColor(.gray)

                Spacer()

                Text("videoEditor.speed")
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(textPrimaryColor)

                Spacer()

                Button(NSLocalizedString("videoEditor.done", comment: "Done")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingSpeedPicker = false
                        applyPlaybackSpeed()
                    }
                }
                .font(.system(size: legacyPoppinsSize(15), weight: .bold))
                .foregroundColor(textPrimaryColor)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 20) {
                ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        playbackSpeed = speed
                    }) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(playbackSpeed == speed ? selectionColor : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)))
                                    .frame(width: 80, height: 80)

                                Image(systemName: speed.icon)
                                    .font(.title2)
                                    .foregroundColor(playbackSpeed == speed ? gripColor : .gray)
                            }

                            Text(speed.rawValue)
                                .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                                .foregroundColor(playbackSpeed == speed ? textPrimaryColor : .gray)
                        }
                    }
                }
            }
            .padding(.top, 24)
            .padding(.horizontal)
            .padding(.bottom, 34) // Account for safe area
        }
        .background {
            Color.clear
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous), interactive: false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1.5)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var formatPickerOverlay: some View {
        VStack(spacing: 0) {
            // Pill indicator on top
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack {
                Button(NSLocalizedString("videoEditor.cancel", comment: "Cancel")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingFormatPicker = false
                    }
                }
                .font(.system(size: legacyPoppinsSize(15)))
                .foregroundColor(.gray)

                Spacer()

                Text("videoEditor.format")
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(textPrimaryColor)

                Spacer()

                Button(NSLocalizedString("videoEditor.done", comment: "Done")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showingFormatPicker = false
                    }
                }
                .font(.system(size: legacyPoppinsSize(15), weight: .bold))
                .foregroundColor(textPrimaryColor)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))

            VStack(spacing: 14) {
                ForEach(VideoFormat.allCases, id: \.self) { format in
                    Button(action: {
                        HapticManager.shared.lightImpact()
                        selectedFormat = format
                    }) {
                        HStack {
                            Image(systemName: format.icon)
                                .font(.title3)
                                .foregroundColor(selectedFormat == format ? textPrimaryColor : .gray)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName)
                                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                                    .foregroundColor(textPrimaryColor)

                                HStack {
                                    Text(format.rawValue)
                                        .font(.system(size: legacyPoppinsSize(11)))
                                        .foregroundColor(.gray)

                                    Text("• \(Int(format.targetSize.width))x\(Int(format.targetSize.height))")
                                        .font(.system(size: legacyPoppinsSize(11)))
                                        .foregroundColor(.gray)
                                }
                            }

                            Spacer()

                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(textPrimaryColor)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(selectedFormat == format ? selectionColor.opacity(0.12) : Color.clear)
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
            .padding(.bottom, 20) // Account for safe area
        }
        .background {
            Color.clear
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous), interactive: false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1.5)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Funciones Principales
    private func setupVideoPlayer() {
        guard let video = currentVideo, let videoURL = video.videoURL else { return }

        player = AVPlayer(url: videoURL)
        generateTimelineThumbnails()

        let asset = AVURLAsset(url: videoURL)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = min(CMTimeGetSeconds(duration), 60)
                    self.trimEndTime = self.duration
                }
            } catch {
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            // Guard progress updates when manual scrubbing is active
            if !isDraggingTrimHandle && !isScrubbingPlayhead {
                self.currentTime = CMTimeGetSeconds(time)

                if self.currentTime >= self.trimEndTime {
                    self.seekTo(time: self.trimStartTime)
                }
            }
        }

        player?.volume = volume

        Task {
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = naturalSize.applying(transform)
                let ratio = abs(size.width / size.height)

                await MainActor.run {
                    if ratio > 1.2 {
                        self.selectedFormat = .landscape
                    } else if ratio < 0.85 {
                        self.selectedFormat = .reels
                    } else {
                        self.selectedFormat = .square
                    }
                }
            } catch {
                print("Error detectando aspect ratio: \(error)")
            }
        }
    }

    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }

    // MARK: - Generación de Thumbnails del Timeline
    private func generateTimelineThumbnails() {
        guard let video = currentVideo, let videoURL = video.videoURL else { return }

        isGeneratingThumbnails = true
        timelineThumbnails.removeAll()

        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 80)

        let thumbnailCount = 20
        let timeInterval = duration / Double(thumbnailCount)

        Task {
            for i in 0..<thumbnailCount {
                let time = CMTime(seconds: Double(i) * timeInterval, preferredTimescale: 600)

                do {
                    let cgImage = try await imageGenerator.image(at: time).image
                    let uiImage = UIImage(cgImage: cgImage)

                    await MainActor.run {
                        timelineThumbnails.append(uiImage)
                    }
                } catch {
                    await MainActor.run {
                        timelineThumbnails.append(createDefaultThumbnail())
                    }
                }
            }

            await MainActor.run {
                isGeneratingThumbnails = false
            }
        }
    }

    private func createDefaultThumbnail() -> UIImage {
        let size = CGSize(width: 120, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.systemBlue.cgColor,
                    UIColor.systemPurple.cgColor
                ] as CFArray,
                locations: [0, 1]
            )!

            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let iconSize: CGFloat = 30
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )

            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: iconRect)

            let trianglePath = UIBezierPath()
            trianglePath.move(to: CGPoint(x: iconRect.midX + 5, y: iconRect.midY - 8))
            trianglePath.addLine(to: CGPoint(x: iconRect.midX + 5, y: iconRect.midY + 8))
            trianglePath.addLine(to: CGPoint(x: iconRect.midX + 13, y: iconRect.midY))
            trianglePath.close()

            UIColor.systemBlue.setFill()
            trianglePath.fill()
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= trimEndTime {
                seekTo(time: trimStartTime)
            }
            player.play()
            isPlaying = true
        }
    }

    private func seekTo(time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func triggerTickHaptic(for time: Double) {
        let rounded = time.rounded()
        if abs(rounded - lastHapticTick) >= 1.0 {
            lastHapticTick = rounded
            HapticManager.shared.lightImpact()
        }
    }

    private func secondsDelta(for translationWidth: CGFloat, totalWidth: CGFloat) -> Double {
        guard totalWidth > 0 else { return 0 }
        return Double(translationWidth / totalWidth) * duration
    }

    // MARK: - High-fidelity Drag Gestures for Timeline Trimming & Scrubbing
    private func leadingHandleGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTrimStart == nil {
                    isDraggingTrimHandle = true
                    HapticManager.shared.lightImpact()
                    player?.pause()
                    isPlaying = false
                    dragStartTrimStart = trimStartTime
                    dragStartTrimDuration = trimEndTime - trimStartTime
                    draggingHandle = .start
                }

                let originalStart = dragStartTrimStart ?? trimStartTime
                let originalDuration = dragStartTrimDuration ?? (trimEndTime - trimStartTime)
                let originalEnd = originalStart + originalDuration
                let delta = secondsDelta(for: value.translation.width, totalWidth: totalWidth)
                let newStart = min(
                    max(0, originalStart + delta),
                    originalEnd - minClipDuration
                )

                trimStartTime = newStart
                currentTime = newStart
                seekTo(time: newStart)
                triggerTickHaptic(for: newStart)
            }
            .onEnded { _ in
                isDraggingTrimHandle = false
                dragStartTrimStart = nil
                dragStartTrimDuration = nil
                draggingHandle = nil
            }
    }

    private func trailingHandleGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTrimDuration == nil {
                    isDraggingTrimHandle = true
                    HapticManager.shared.lightImpact()
                    player?.pause()
                    isPlaying = false
                    dragStartTrimDuration = trimEndTime - trimStartTime
                    draggingHandle = .end
                }

                let originalDuration = dragStartTrimDuration ?? (trimEndTime - trimStartTime)
                let delta = secondsDelta(for: value.translation.width, totalWidth: totalWidth)
                let newDuration = min(
                    duration - trimStartTime,
                    max(minClipDuration, originalDuration + delta)
                )

                let targetEnd = trimStartTime + newDuration
                trimEndTime = targetEnd
                currentTime = targetEnd
                seekTo(time: targetEnd)
                triggerTickHaptic(for: targetEnd)
            }
            .onEnded { _ in
                isDraggingTrimHandle = false
                dragStartTrimDuration = nil
                draggingHandle = nil
            }
    }

    private func selectionDragGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartTrimStart == nil {
                    isDraggingTrimHandle = true
                    HapticManager.shared.lightImpact()
                    player?.pause()
                    isPlaying = false
                    dragStartTrimStart = trimStartTime
                    dragStartTrimDuration = trimEndTime - trimStartTime
                }
                let delta = secondsDelta(for: value.translation.width, totalWidth: totalWidth)
                let newStart = (dragStartTrimStart ?? trimStartTime) + delta
                let windowDuration = dragStartTrimDuration ?? (trimEndTime - trimStartTime)
                let clampedStart = min(max(newStart, 0), max(duration - windowDuration, 0))

                trimStartTime = clampedStart
                currentTime = clampedStart
                trimEndTime = clampedStart + windowDuration
                seekTo(time: clampedStart)
                triggerTickHaptic(for: clampedStart)
            }
            .onEnded { _ in
                isDraggingTrimHandle = false
                dragStartTrimStart = nil
                dragStartTrimDuration = nil
            }
    }

    private func needleDragGesture(totalWidth: CGFloat, clampedStartX: CGFloat, windowWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isScrubbingPlayhead {
                    isScrubbingPlayhead = true
                    HapticManager.shared.lightImpact()
                    player?.pause()
                    isPlaying = false
                }

                let dragX = value.location.x
                let fraction = dragX / max(totalWidth, 0.1)
                let targetTime = fraction * duration

                let clampedTime = min(max(targetTime, trimStartTime), trimEndTime)

                currentTime = clampedTime
                seekTo(time: clampedTime)
                triggerTickHaptic(for: clampedTime)
            }
            .onEnded { _ in
                isScrubbingPlayhead = false
                player?.play()
                isPlaying = true
            }
    }

    private func switchToClip(index: Int) {
        selectedClipIndex = index
        cleanupPlayer()
        setupVideoPlayer()
    }

    private func applyPlaybackSpeed() {
        player?.rate = playbackSpeed.multiplier
    }

    private func toggleVolume() {
        if volume > 0 {
            volume = 0
            player?.volume = 0
        } else {
            volume = 1.0
            player?.volume = 1.0
        }
    }

    private func calculateVideoSize(for containerSize: CGSize) -> CGSize {
        let targetRatio = selectedFormat.ratio
        let containerRatio = containerSize.width / containerSize.height

        if containerRatio > targetRatio {
            let height = containerSize.height
            let width = height * targetRatio
            return CGSize(width: width, height: height)
        } else {
            let width = containerSize.width
            let height = width / targetRatio
            return CGSize(width: width, height: height)
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func goBack() {
        currentFlow = .mediaSelection
    }

    // MARK: - Procesamiento Principal
    private func processAndContinue() {
        isProcessing = true
        processingProgress = 0
        processingMessage = "Iniciando procesamiento..."

        processAllVideos { success in
            DispatchQueue.main.async {
                self.isProcessing = false

                if success {
                    self.updateSelectedMedia()
                    self.currentFlow = .captionAndDetails
                } else {
                    self.showError("Error procesando videos. Inténtalo de nuevo.")
                }
            }
        }
    }

    // MARK: - Procesamiento de Videos
    private func processAllVideos(completion: @escaping (Bool) -> Void) {
        let videoItems = selectedMediaItems.filter { $0.type == .video }

        guard !videoItems.isEmpty else {
            completion(true)
            return
        }

        let group = DispatchGroup()
        var allSuccess = true
        var processedCount = 0

        for (index, mediaItem) in videoItems.enumerated() {
            guard let videoURL = mediaItem.videoURL else { continue }

            group.enter()

            DispatchQueue.main.async {
                self.processingMessage = "Procesando video \(index + 1)/\(videoItems.count)"
                self.processingProgress = Double(index) / Double(videoItems.count)
            }

            processVideoWithThumbnail(videoURL: videoURL, format: selectedFormat) { result in
                defer { group.leave() }

                switch result {
                case .success(let processedData):
                    DispatchQueue.main.async {
                        if let originalIndex = self.selectedMediaItems.firstIndex(where: { $0.id == mediaItem.id }) {
                            var updatedMedia = self.selectedMediaItems[originalIndex]

                            updatedMedia.videoURL = processedData.compressedVideoURL
                            updatedMedia.image = processedData.thumbnailImage
                            updatedMedia.videoDuration = processedData.duration
                            updatedMedia.videoFileSize = processedData.fileSize
                            updatedMedia.videoResolution = "\(Int(processedData.resolution.width))x\(Int(processedData.resolution.height))"

                            self.selectedMediaItems[originalIndex] = updatedMedia
                        }

                        processedCount += 1
                        self.processingProgress = Double(processedCount) / Double(videoItems.count)
                    }

                case .failure:
                    allSuccess = false
                }
            }
        }

        group.notify(queue: .main) {
            self.processingProgress = 1.0
            self.processingMessage = "Finalizando..."

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion(allSuccess)
            }
        }
    }

    // MARK: - Procesamiento Individual de Video
    private func processVideoWithThumbnail(videoURL: URL, format: VideoFormat, completion: @escaping (Result<ProcessedVideoData, Error>) -> Void) {
        Task {
            do {
                let asset = AVURLAsset(url: videoURL)
                let videoTracks = try await asset.loadTracks(withMediaType: .video)

                guard let videoTrack = videoTracks.first else {
                    throw ProcessingError.noVideoTrack
                }

                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let duration = try await asset.load(.duration)

                let transformedSize = naturalSize.applying(transform)
                let currentSize = CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )

                let targetSize = calculateOptimalSize(currentSize: currentSize, targetFormat: format)
                let needsCompression = shouldCompress(currentSize: currentSize, targetSize: targetSize)

                let thumbnailURL: URL
                let thumbnailImage: UIImage

                if let customImg = customThumbnailImage {
                    thumbnailImage = customImg

                    let tempDir = FileManager.default.temporaryDirectory
                    let customURL = tempDir.appendingPathComponent("thumbnail_custom_\(UUID().uuidString).jpg")

                    guard let jpegData = customImg.jpegData(compressionQuality: 0.8) else {
                        throw ProcessingError.thumbnailGenerationFailed
                    }

                    try jpegData.write(to: customURL)
                    thumbnailURL = customURL
                } else {
                    let result = try await generateThumbnail(from: asset, targetSize: targetSize)
                    thumbnailURL = result.0
                    thumbnailImage = result.1
                }

                let finalVideoURL: URL
                if needsCompression {
                    finalVideoURL = try await compressVideo(
                        inputURL: videoURL,
                        targetSize: targetSize,
                        targetBitrate: format.targetBitrate
                    )
                } else {
                    finalVideoURL = videoURL
                }

                let finalFileSize = try getFileSize(url: finalVideoURL)
                let finalDuration = CMTimeGetSeconds(duration)

                let processedData = ProcessedVideoData(
                    compressedVideoURL: finalVideoURL,
                    thumbnailURL: thumbnailURL,
                    duration: finalDuration,
                    fileSize: finalFileSize,
                    resolution: targetSize,
                    thumbnailImage: thumbnailImage
                )

                await MainActor.run {
                    completion(.success(processedData))
                }

            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Generación de Thumbnail
    private func generateThumbnail(from asset: AVAsset, targetSize: CGSize) async throws -> (URL, UIImage) {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let thumbnailSize = calculateThumbnailSize(for: selectedFormat)
        imageGenerator.maximumSize = thumbnailSize

        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: min(1.0, CMTimeGetSeconds(duration) / 2), preferredTimescale: 600)

        let cgImage = try await imageGenerator.image(at: time).image
        let uiImage = UIImage(cgImage: cgImage)

        let tempDir = FileManager.default.temporaryDirectory
        let thumbnailURL = tempDir.appendingPathComponent("thumbnail_\(UUID().uuidString).jpg")

        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw ProcessingError.thumbnailGenerationFailed
        }

        try jpegData.write(to: thumbnailURL)

        return (thumbnailURL, uiImage)
    }

    // MARK: - Cálculo de Tamaño de Thumbnail
    private func calculateThumbnailSize(for format: VideoFormat) -> CGSize {
        switch format {
        case .reels:
            return CGSize(width: 720, height: 1280)
        case .square:
            return CGSize(width: 1080, height: 1080)
        case .landscape:
            return CGSize(width: 1280, height: 720)
        }
    }

    // MARK: - Compresión de Video
    private func compressVideo(inputURL: URL, targetSize: CGSize, targetBitrate: Int) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("compressed_\(UUID().uuidString).mp4")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.noVideoTrack
        }

        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))

        try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let actualSize = CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))

        let needsRescaling = abs(actualSize.width - targetSize.width) > 10 || abs(actualSize.height - targetSize.height) > 10

        if needsRescaling {
            let scaleX = targetSize.width / actualSize.width
            let scaleY = targetSize.height / actualSize.height
            let scale = min(scaleX, scaleY)

            let scaledSize = CGSize(width: actualSize.width * scale, height: actualSize.height * scale)
            let translateX = (targetSize.width - scaledSize.width) / 2
            let translateY = (targetSize.height - scaledSize.height) / 2

            let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
            let translateTransform = CGAffineTransform(translationX: translateX, y: translateY)
            let finalTransform = preferredTransform.concatenating(scaleTransform).concatenating(translateTransform)

            transformer.setTransform(finalTransform, at: .zero)
        } else {
            transformer.setTransform(preferredTransform, at: .zero)
        }

        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProcessingError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        let progressTask = Task {
            for try await _ in exportSession.states(updateInterval: 0.1) {
                await MainActor.run {
                    self.processingProgress = Double(exportSession.progress) * 0.8 + 0.2
                }
            }
        }
        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            progressTask.cancel()
            await MainActor.run {
                self.processingProgress = 1.0
            }
            return outputURL
        } catch {
            progressTask.cancel()
            throw error
        }
    }

    // MARK: - Funciones de Utilidad
    private func calculateOptimalSize(currentSize: CGSize, targetFormat: VideoFormat) -> CGSize {
        let targetSize = targetFormat.targetSize
        let currentAspectRatio = currentSize.width / currentSize.height
        let targetAspectRatio = targetSize.width / targetSize.height
        let tolerance: CGFloat = 0.1

        if abs(currentAspectRatio - targetAspectRatio) < tolerance {
            let maxDimension: CGFloat = targetFormat == .landscape ? 1920 : 1080

            if max(currentSize.width, currentSize.height) > maxDimension * 1.2 {
                return calculateOptimalSizePreservingRatio(currentSize: currentSize, maxDimension: maxDimension)
            } else {
                return currentSize
            }
        }

        if abs(currentAspectRatio - targetAspectRatio) > 0.3 {
            let maxDimension: CGFloat = 1080
            return calculateOptimalSizePreservingRatio(currentSize: currentSize, maxDimension: maxDimension)
        }

        return targetSize
    }

    private func calculateOptimalSizePreservingRatio(currentSize: CGSize, maxDimension: CGFloat) -> CGSize {
        let currentRatio = currentSize.width / currentSize.height

        if currentSize.width > currentSize.height {
            let width = min(currentSize.width, maxDimension)
            let height = width / currentRatio
            return CGSize(width: width, height: height)
        } else {
            let height = min(currentSize.height, maxDimension)
            let width = height * currentRatio
            return CGSize(width: width, height: height)
        }
    }

    private func shouldCompress(currentSize: CGSize, targetSize: CGSize) -> Bool {
        if currentSize == targetSize {
            return false
        }

        let currentPixels = currentSize.width * currentSize.height
        let targetPixels = targetSize.width * targetSize.height
        let pixelRatio = currentPixels / targetPixels

        return pixelRatio > 1.2
    }

    private func getFileSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    private func updateSelectedMedia() {
        for index in selectedMediaItems.indices {
            if selectedMediaItems[index].type == .video {
                selectedMediaItems[index] = selectedMediaItems[index].with(
                    aspectRatio: selectedFormat.toProcessedMediaAspectRatio,
                    hasEdits: true
                )
            }
        }
    }

    func getThumbnailImage(for videoIndex: Int) -> UIImage? {
        let videoItems = selectedMediaItems.filter { $0.type == .video }
        if videoItems.indices.contains(videoIndex) {
            return videoItems[videoIndex].image
        }
        return nil
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Errores de Procesamiento
enum ProcessingError: LocalizedError {
    case noVideoTrack
    case thumbnailGenerationFailed
    case exportSessionCreationFailed
    case compressionFailed
    case compressionCancelled
    case unexpectedState

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No se encontró pista de video"
        case .thumbnailGenerationFailed:
            return "Error generando thumbnail"
        case .exportSessionCreationFailed:
            return "Error creando sesión de exportación"
        case .compressionFailed:
            return "Error comprimiendo video"
        case .compressionCancelled:
            return "Compresión cancelada"
        case .unexpectedState:
            return "Estado inesperado durante el procesamiento"
        }
    }
}

// MARK: - Wrapper para VideoPlayer
struct VideoPlayerWrapper: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

// MARK: - Thumbnail Picker View
struct ThumbnailPickerView: View {
    let videoURL: URL?
    @Binding var selectedTime: Double
    @Binding var selectedImage: UIImage?
    var onDismiss: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var previewImage: UIImage?
    @State private var isGenerating = false
    @State private var imageGenerator: AVAssetImageGenerator?

    @State private var timelineThumbnails: [UIImage] = []

    private var workspaceBg: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var selectionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.1))
                        .aspectRatio(9/16, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                        )

                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    } else if isGenerating {
                        ProgressView()
                            .tint(selectionColor)
                    }
                }
                .padding()
                .frame(maxHeight: 500)

                Spacer()

                VStack(spacing: 12) {
                    Text("videoEditor.coverPicker.instructions")
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(.secondary)

                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            if timelineThumbnails.isEmpty {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 60)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(0..<timelineThumbnails.count, id: \.self) { index in
                                    Image(uiImage: timelineThumbnails[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 60)
                                        .clipped()
                                }
                            }
                        }
                        .frame(height: 60)
                        .cornerRadius(10)
                        .opacity(0.6)

                        Slider(value: $currentTime, in: 0...max(duration, 0.1))
                            .tint(selectionColor)
                            .onChange(of: currentTime) { _, newValue in
                                generateFrame(at: newValue)
                            }
                    }
                    .padding(.horizontal)

                    Text(formatTime(currentTime))
                        .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                        .foregroundColor(selectionColor)
                }
                .padding(.bottom, 40)
            }
            .background(workspaceBg.ignoresSafeArea())
            .navigationTitle("videoEditor.coverPicker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.cancel") {
                        onDismiss()
                    }
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundColor(.gray)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done") {
                        selectedTime = currentTime
                        selectedImage = previewImage
                        onDismiss()
                    }
                    .font(.system(size: legacyPoppinsSize(15), weight: .bold))
                    .foregroundColor(selectionColor)
                }
            }
            .onAppear {
                setupGenerator()
                loadDurationAndGenerateTimeline()
            }
        }
    }

    private func setupGenerator() {
        guard let url = videoURL else { return }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.imageGenerator = generator
    }

    private func loadDurationAndGenerateTimeline() {
        guard let url = videoURL else { return }
        let asset = AVURLAsset(url: url)

        Task {
            do {
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)

                await MainActor.run {
                    self.duration = durationSeconds
                    generateTimelineThumbnails(for: asset, duration: durationSeconds)
                    generateFrame(at: 0)
                }
            } catch {
                print("Error loading asset duration: \(error)")
            }
        }
    }

    private func generateFrame(at time: Double) {
        guard let generator = imageGenerator else { return }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        Task {
            do {
                let (cgImage, _) = try await generator.image(at: cmTime)
                let image = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.previewImage = image
                    self.isGenerating = false
                }
            } catch {
                print("Error generating frame: \(error)")
            }
        }
    }

    private func generateTimelineThumbnails(for asset: AVAsset, duration: Double) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 150, height: 150)

        let count = 10
        var times: [NSValue] = []
        let step = duration / Double(count)

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
            times.append(NSValue(time: time))
        }

        generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, _, _ in
            if let cgImage = cgImage {
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.timelineThumbnails.append(image)
                }
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
