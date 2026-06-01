import SwiftUI
import GoogleMobileAds
import UIKit

private func activeWindowSafeAreaInsets() -> UIEdgeInsets {
    let scenes = UIApplication.shared.connectedScenes
    let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
    let keyWindow = windowScene?.windows.first(where: \.isKeyWindow)
    return keyWindow?.safeAreaInsets ?? .zero
}

private func storyNativeVideoLoaderOptions() -> VideoOptions {
    let videoOptions = VideoOptions()
    videoOptions.shouldStartMuted = false
    videoOptions.areCustomControlsRequested = true
    return videoOptions
}

@MainActor
final class StoryAdVideoPlayback: ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var isMuted = false
    @Published private(set) var hasVideo = false
    @Published private(set) var canUseCustomControls = false

    private weak var videoController: VideoController?

    func attach(nativeAd: NativeAd, delegate: VideoControllerDelegate) {
        let hasVideoContent = nativeAd.mediaContent.hasVideoContent
        guard hasVideoContent else {
            publishState(hasVideo: false, canUseCustomControls: false, isMuted: false, isPaused: false)
            return
        }

        let controller = nativeAd.mediaContent.videoController
        videoController = controller
        controller.delegate = delegate

        let customControls = controller.areCustomControlsEnabled
        let muted = controller.isMuted

        if customControls {
            controller.isMuted = false
            controller.play()
        }

        publishState(
            hasVideo: true,
            canUseCustomControls: customControls,
            isMuted: customControls ? false : muted,
            isPaused: false
        )
    }

    func detach() {
        videoController?.delegate = nil
        videoController = nil
        publishState(hasVideo: false, canUseCustomControls: false, isMuted: false, isPaused: false)
    }

    func togglePause() {
        guard let controller = videoController else { return }

        if canUseCustomControls {
            if isPaused {
                controller.play()
            } else {
                controller.pause()
            }
            return
        }

        // Sin controles custom el SDK renderiza los suyos; sincronizamos estado local.
        isPaused.toggle()
    }

    func toggleMute() {
        guard let controller = videoController else { return }
        isMuted.toggle()
        controller.isMuted = isMuted
    }

    func syncPaused(_ paused: Bool) {
        publishState(isPaused: paused)
    }

    func syncMuted(_ muted: Bool) {
        publishState(isMuted: muted)
    }

    private func publishState(
        hasVideo: Bool? = nil,
        canUseCustomControls: Bool? = nil,
        isMuted: Bool? = nil,
        isPaused: Bool? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let hasVideo { self.hasVideo = hasVideo }
            if let canUseCustomControls { self.canUseCustomControls = canUseCustomControls }
            if let isMuted { self.isMuted = isMuted }
            if let isPaused { self.isPaused = isPaused }
        }
    }
}

private struct StoryAdVideoControlsOverlay: View {
    @ObservedObject var playback: StoryAdVideoPlayback
    let bottomPanelReservedHeight: CGFloat

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: playback.togglePause) {
                    Image(systemName: playback.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    playback.isPaused
                    ? NSLocalizedString("feed.video.play", comment: "Play video")
                    : NSLocalizedString("feed.video.pause", comment: "Pause video")
                )

                Button(action: playback.toggleMute) {
                    Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    playback.isMuted
                    ? NSLocalizedString("feed.video.unmute", comment: "Unmute video")
                    : NSLocalizedString("feed.video.mute", comment: "Mute video")
                )

                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.bottom, bottomPanelReservedHeight + 12)
        }
        .allowsHitTesting(true)
    }
}

private struct StoryAdTopChrome: View {
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let title: String
    let subtitle: String
    let iconImage: UIImage?
    let onClose: () -> Void
    let trailingAccessory: AnyView?

    init(
        storyCount: Int,
        storyIndex: Int,
        progress: Double,
        title: String,
        subtitle: String,
        iconImage: UIImage?,
        onClose: @escaping () -> Void,
        trailingAccessory: AnyView? = nil
    ) {
        self.storyCount = storyCount
        self.storyIndex = storyIndex
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.iconImage = iconImage
        self.onClose = onClose
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<storyCount, id: \.self) { index in
                    GlassmorphicProgressBar(
                        progress: progressForSegment(index),
                        isActive: index == storyIndex,
                        audience: nil
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        if let iconImage {
                            Image(uiImage: iconImage)
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

                            Image(systemName: "megaphone.fill")
                                .foregroundColor(.white.opacity(0.82))
                                .font(.system(size: 16, weight: .medium))
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundColor(.white)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .lineLimit(1)
                            .shadow(color: Color.black.opacity(0.60), radius: 5, x: 0, y: 2)

                        HStack(spacing: 6) {
                            Text("Ad")
                                .foregroundColor(.white)
                                .font(.custom("Poppins-SemiBold", size: 9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())

                            Text(subtitle)
                                .foregroundColor(.white.opacity(0.7))
                                .font(.custom("Poppins-Regular", size: 11))
                                .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 2)
                        }
                    }
                }

                Spacer()

                if let trailingAccessory {
                    trailingAccessory
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .storyGlassmorphic()
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private func progressForSegment(_ index: Int) -> Double {
        if index < storyIndex { return 1.0 }
        if index == storyIndex { return progress }
        return 0.0
    }
}

// MARK: - Story Native Ad View
struct StoryNativeAdView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var storyAdManager = StoryNativeAdManager()
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    let storyCount: Int
    let storyIndex: Int
    let screenSize: CGSize
    
    @State private var progress: Double = 0.0
    @State private var adTimer: Timer?
    @State private var debugTimer: Timer?
    @State private var hasAppeared = false
    @State private var currentAdDuration: Double = 8.0
    @State private var isAdTimerPaused = false

    var body: some View {
        Group {
            if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
                if storyAdManager.isLoading && hasAppeared {
                    StoryAdLoadingView(
                        storyCount: storyCount,
                        storyIndex: storyIndex,
                        progress: progress,
                        onNext: cleanupAndNext,
                        onPrevious: onPrevious,
                        onClose: onClose
                    )
                    
                } else if let nativeAd = storyAdManager.nativeAd, hasAppeared {
                    StoryAdContentViewWithMediaView(
                        nativeAd: nativeAd,
                        storyCount: storyCount,
                        storyIndex: storyIndex,
                        progress: progress,
                        screenSize: screenSize,
                        isTimerPaused: $isAdTimerPaused,
                        onNext: cleanupAndNext,
                        onPrevious: onPrevious,
                        onClose: onClose
                    )
                    .onAppear {
                        currentAdDuration = nativeAd.mediaContent.hasVideoContent ? 20.0 : 8.0
                        startAdTimer()
                    }
                    
                } else if storyAdManager.hasError && hasAppeared {
                    ZStack {
                        Color.red.opacity(0.3)
                        
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            
                            Text("ad.story.errorLoading")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("ad.story.skippingSoon")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            cleanupAndNext()
                        }
                    }
                    
                } else {
                    if hasAppeared {
                        StoryAdLoadingView(
                            storyCount: storyCount,
                            storyIndex: storyIndex,
                            progress: progress,
                            onNext: cleanupAndNext,
                            onPrevious: onPrevious,
                            onClose: onClose
                        )
                        .onAppear {
                            if !storyAdManager.isLoading && storyAdManager.nativeAd == nil && !storyAdManager.hasError {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    self.storyAdManager.loadStoryAd()
                                }
                            }
                        }
                    } else {
                        Color.black
                    }
                }
            } else {
                Color.clear.onAppear {
                    onNext()
                }
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            
            hasAppeared = true
            
            if PlusStatusHelper.shouldShowAds(for: authService.currentUser) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.storyAdManager.loadStoryAd()
                }
                
                debugTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    Task { @MainActor in
                        if self.storyAdManager.isLoading {
                            self.cleanupAndNext()
                        }
                    }
                }
            }
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func cleanupAndNext() {
        cleanup()
        onNext()
    }
    
    private func cleanup() {
        adTimer?.invalidate()
        adTimer = nil
        debugTimer?.invalidate()
        debugTimer = nil
        storyAdManager.cleanup()
    }
    
    private func startAdTimer() {
        guard adTimer == nil else { return }
        
        progress = 0.0
        adTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard !isAdTimerPaused else { return }
            progress += 0.05 / currentAdDuration
            if progress >= 1.0 {
                cleanupAndNext()
            }
        }
    }
}

// MARK: - Story Ad Content View with MediaView
struct StoryAdContentViewWithMediaView: View {
    let nativeAd: NativeAd
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let screenSize: CGSize
    @Binding var isTimerPaused: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var mediaViewKey = UUID()
    @StateObject private var videoPlayback = StoryAdVideoPlayback()

    private let bottomPanelReservedHeight: CGFloat = 174

    var body: some View {
        GeometryReader { geometry in
            let topInset = max(geometry.safeAreaInsets.top, activeWindowSafeAreaInsets().top)

            ZStack {
                StoryAdMediaViewRepresentable(
                    nativeAd: nativeAd,
                    playback: videoPlayback
                )
                    .id(mediaViewKey)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .clipped()
                
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topInset)
                        .allowsHitTesting(false)

                    StoryAdTopChrome(
                        storyCount: storyCount,
                        storyIndex: storyIndex,
                        progress: progress,
                        title: nativeAd.advertiser ?? NSLocalizedString("ad.common.sponsored", comment: "Sponsored"),
                        subtitle: NSLocalizedString("ad.common.sponsored", comment: "Sponsored"),
                        iconImage: nativeAd.icon?.image,
                        onClose: onClose
                    )

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }

                if nativeAd.mediaContent.hasVideoContent, videoPlayback.canUseCustomControls {
                    StoryAdVideoControlsOverlay(
                        playback: videoPlayback,
                        bottomPanelReservedHeight: bottomPanelReservedHeight
                    )
                }
                
                if !nativeAd.mediaContent.hasVideoContent {
                    storyTouchAreas
                }
            }
        }
        .onChange(of: videoPlayback.isPaused) { _, paused in
            isTimerPaused = paused
        }
        .onDisappear {
            videoPlayback.detach()
        }
    }

    private var storyTouchAreas: some View {
        GeometryReader { geometry in
            let topReserved = max(geometry.safeAreaInsets.top, activeWindowSafeAreaInsets().top) + 92
            let bottomReserved: CGFloat = 188
            let interactiveHeight = max(geometry.size.height - topReserved - bottomReserved, 0)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topReserved)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: geometry.size.width * 0.15)
                        .contentShape(Rectangle())
                        .onTapGesture { onPrevious() }
                    
                    Spacer()
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: geometry.size.width * 0.15)
                        .contentShape(Rectangle())
                        .onTapGesture { onNext() }
                }
                .frame(height: interactiveHeight)

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

// MARK: - MediaView UIViewRepresentable
struct StoryAdMediaViewRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd
    @ObservedObject var playback: StoryAdVideoPlayback
    
    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        nativeAdView.nativeAd = nativeAd
        
        // MediaView
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.backgroundColor = .black
        mediaView.mediaContent = nativeAd.mediaContent
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.mediaView = mediaView
        
        // Ad Attribution personalizado (REQUERIDO por Google)
        let adAttributionView = UIView()
        adAttributionView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        adAttributionView.layer.cornerRadius = 3
        adAttributionView.translatesAutoresizingMaskIntoConstraints = false
        
        let adAttributionLabel = UILabel()
        adAttributionLabel.text = "Ad"
        adAttributionLabel.font = UIFont(name: "Poppins-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12)
        adAttributionLabel.textColor = .white
        adAttributionLabel.textAlignment = .center
        adAttributionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        adAttributionView.addSubview(adAttributionLabel)
        
        // AdChoices (REQUERIDO por Google)
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.adChoicesView = adChoicesView

        // Headline
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline
        headlineLabel.font = UIFont(name: "Poppins-SemiBold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 1
        headlineLabel.lineBreakMode = .byTruncatingTail
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.headlineView = headlineLabel

        // Body
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body
        bodyLabel.font = UIFont(name: "Poppins-Regular", size: 15) ?? UIFont.systemFont(ofSize: 15)
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        bodyLabel.numberOfLines = 1
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.bodyView = bodyLabel

        let callToActionButton = UIButton(type: .system)
        callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        callToActionButton.titleLabel?.font = UIFont(name: "Poppins-SemiBold", size: 15) ?? UIFont.boldSystemFont(ofSize: 15)
        callToActionButton.setTitleColor(.white, for: .normal)
        callToActionButton.backgroundColor = UIColor(red: 0.09, green: 0.56, blue: 0.96, alpha: 0.95)
        callToActionButton.layer.cornerRadius = 18
        callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.callToActionView = callToActionButton

        let iconView = UIImageView()
        if let iconImage = nativeAd.icon?.image {
            iconView.image = iconImage
        }
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 6
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.iconView = iconView

        let advertiserLabel = UILabel()
        advertiserLabel.text = nativeAd.advertiser ?? "Anunciante"
        advertiserLabel.font = UIFont(name: "Poppins-SemiBold", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
        advertiserLabel.textColor = .white.withAlphaComponent(0.8)
        advertiserLabel.numberOfLines = 1
        advertiserLabel.lineBreakMode = .byTruncatingTail
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.advertiserView = advertiserLabel

        let advertiserRow = UIStackView(arrangedSubviews: [iconView, advertiserLabel])
        advertiserRow.axis = .horizontal
        advertiserRow.alignment = .center
        advertiserRow.spacing = 8
        advertiserRow.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView(arrangedSubviews: [headlineLabel, bodyLabel, advertiserRow, callToActionButton])
        contentStack.axis = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let bottomPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        bottomPanel.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.clipsToBounds = true
        bottomPanel.layer.cornerRadius = 26

        if nativeAd.mediaContent.hasVideoContent {
            context.coordinator.playback = playback
            playback.attach(nativeAd: nativeAd, delegate: context.coordinator)
        }
        
        // Agregar TODOS los elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(bottomPanel)
        bottomPanel.contentView.addSubview(contentStack)
        bottomPanel.contentView.addSubview(adChoicesView)
        bottomPanel.contentView.addSubview(adAttributionView)

        // Constraints - Layout vertical DENTRO del NativeAdView (como FeedNativeAd)
        NSLayoutConstraint.activate([
            // MediaView ocupa la parte superior y deja un panel propio para metadata del anuncio.
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: -12),
            mediaView.heightAnchor.constraint(greaterThanOrEqualTo: nativeAdView.heightAnchor, multiplier: 0.62),

            bottomPanel.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 12),
            bottomPanel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            bottomPanel.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -18),
            bottomPanel.heightAnchor.constraint(equalToConstant: 144),
            
            // Ad Attribution visible dentro del panel nativo.
            adAttributionView.topAnchor.constraint(equalTo: bottomPanel.contentView.topAnchor, constant: 14),
            adAttributionView.leadingAnchor.constraint(equalTo: bottomPanel.contentView.leadingAnchor, constant: 16),
            adAttributionView.widthAnchor.constraint(equalToConstant: 30),
            adAttributionView.heightAnchor.constraint(equalToConstant: 18),
            
            adAttributionLabel.centerXAnchor.constraint(equalTo: adAttributionView.centerXAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: adAttributionView.centerYAnchor),
            
            // AdChoices queda en la misma fila pero sin solapar otros assets.
            adChoicesView.topAnchor.constraint(equalTo: bottomPanel.contentView.topAnchor, constant: 12),
            adChoicesView.trailingAnchor.constraint(equalTo: bottomPanel.contentView.trailingAnchor, constant: -16),
            
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            callToActionButton.heightAnchor.constraint(equalToConstant: 34),

            contentStack.topAnchor.constraint(equalTo: adAttributionView.bottomAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: bottomPanel.contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: bottomPanel.contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: bottomPanel.contentView.bottomAnchor, constant: -16),

            callToActionButton.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            callToActionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 124)
        ])
        
        return nativeAdView
    }
    
    func updateUIView(_ uiView: NativeAdView, context: Context) {
        context.coordinator.playback = playback
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        weak var playback: StoryAdVideoPlayback?

        func videoControllerDidPlayVideo(_ videoController: VideoController) {
            Task { @MainActor in
                playback?.syncPaused(false)
            }
        }

        func videoControllerDidPauseVideo(_ videoController: VideoController) {
            Task { @MainActor in
                playback?.syncPaused(true)
            }
        }

        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {
            Task { @MainActor in
                playback?.syncPaused(true)
            }
        }

        func videoControllerDidMuteVideo(_ videoController: VideoController) {
            Task { @MainActor in
                playback?.syncMuted(true)
            }
        }

        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {
            Task { @MainActor in
                playback?.syncMuted(false)
            }
        }

        func videoController(_ videoController: VideoController, didFailWithError error: Error) {}
    }
}

// MARK: - Story Ad Loading View
struct StoryAdLoadingView: View {
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        let resolvedTopInset = max(CGFloat(48), activeWindowSafeAreaInsets().top)

        ZStack {
            LinearGradient(
                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Color.clear.frame(height: resolvedTopInset)

                StoryAdTopChrome(
                    storyCount: storyCount,
                    storyIndex: storyIndex,
                    progress: progress,
                    title: NSLocalizedString("ad.common.sponsored", comment: "Sponsored"),
                    subtitle: NSLocalizedString("common.loading", comment: "Loading"),
                    iconImage: nil,
                    onClose: onClose,
                    trailingAccessory: AnyView(
                        Button("ad.common.skip") {
                            onNext()
                        }
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                    )
                )
                
                Spacer()
                
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(isAnimating ? 360 : 0))
                            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isAnimating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("ad.story.preparing")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 5)
                        
                        Text("ad.story.preparingDescription")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 3)
                    }
                    
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 180)
                            .shimmer(isAnimating: isAnimating)
                        
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 20)
                                .shimmer(isAnimating: isAnimating)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 16)
                                .frame(width: 200)
                                .shimmer(isAnimating: isAnimating)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            
            storyTouchAreas
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var storyTouchAreas: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { onPrevious() }
                
                Spacer()
                
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { onNext() }
            }
            .frame(height: geometry.size.height * 0.85)
        }
    }
    
}

// MARK: - Shimmer Effect Extension
extension View {
    func shimmer(isAnimating: Bool) -> some View {
        self.modifier(ShimmerModifier(isAnimating: isAnimating))
    }
}

struct ShimmerModifier: ViewModifier {
    let isAnimating: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(45))
                    .offset(x: phase)
                    .clipped()
            )
            .onAppear {
                if isAnimating {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 300
                    }
                }
            }
    }
}

// MARK: - Helpers para verificar estado Plus
struct PlusStatusHelper {
    static func shouldShowAds(for user: AppUser?) -> Bool {
        guard let user = user else { return true }
        return !(user.isPlusSubscriber && user.hasActivePlusSubscription)
    }

    static func isActivePlus(for user: AppUser?) -> Bool {
        guard let user = user else { return false }
        return user.isPlusSubscriber && user.hasActivePlusSubscription
    }
}

// MARK: - Story Native Ad Manager
@MainActor
class StoryNativeAdManager: NSObject, ObservableObject {
    @Published var nativeAd: NativeAd?
    @Published var isLoading = false
    @Published var hasError = false

    private var adLoader: AdLoader?

    func loadStoryAd() {
        guard !isLoading else { return }
        
        if let preloadedAd = AdMobConfiguration.shared.getPreloadedNativeAd() {
            DispatchQueue.main.async {
                self.nativeAd = preloadedAd
                self.isLoading = false
                self.hasError = false
            }
            AdMobConfiguration.shared.clearPreloadedNativeAd()
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.hasError = false
            self.nativeAd = nil
        }

        let adUnitID = AdMobConfiguration.getNativeAdUnitId()
        let mediaOptions = NativeAdMediaAdLoaderOptions()
        mediaOptions.mediaAspectRatio = .any
        let videoOptions = storyNativeVideoLoaderOptions()
        let rootVC = UIApplication.shared.topViewController()
        
        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [mediaOptions, videoOptions]
        )

        adLoader?.delegate = self
        let request = AdMobConfiguration.shared.createAdRequest()
        adLoader?.load(request)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if self.isLoading {
                self.isLoading = false
                self.hasError = true
            }
        }
    }
    
    func cleanup() {
        adLoader?.delegate = nil
        adLoader = nil
        
        if nativeAd != nil {
            nativeAd = nil
        }
        
        isLoading = false
        hasError = false
    }
    
    var hasReadyAd: Bool {
        return nativeAd != nil && !isLoading && !hasError
    }
    
    func forceReload() {
        DispatchQueue.main.async {
            self.cleanup()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.loadStoryAd()
        }
    }
}

// MARK: - AdLoaderDelegate
extension StoryNativeAdManager: @preconcurrency AdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isLoading = false
            self?.hasError = true
            self?.nativeAd = nil
        }
    }
}

// MARK: - NativeAdLoaderDelegate
extension StoryNativeAdManager: @preconcurrency NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor [weak self] in
            if nativeAd.mediaContent.hasVideoContent {
                nativeAd.mediaContent.videoController.isMuted = false
            }
            
            self?.nativeAd = nativeAd
            self?.isLoading = false
            self?.hasError = false
        }
    }
}

// MARK: - ✅ NUEVO: Anuncio integrado para historias
struct IntegratedStoryAdView: View {
    let nativeAd: NativeAd
    let storyCount: Int
    let storyIndex: Int
    let progress: Double
    let screenSize: CGSize
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @State private var adTimer: Timer?
    @State private var timeRemaining: Double = 10.0
    
    // Duración dinámica basada en el tipo de contenido (consistente con historias normales)
    private var adDuration: Double {
        if nativeAd.mediaContent.hasVideoContent {
            return 30.0 // 30 segundos para videos (más razonable para anuncios)
        } else {
            return 10.0 // 10 segundos para fotos (como las historias normales)
        }
    }
    
    var body: some View {
        ZStack {
            // Fondo negro como las historias
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Media del anuncio (Pantalla completa e inmersiva)
                ZStack(alignment: .bottom) {
                    IntegratedStoryMediaView(nativeAd: nativeAd)
                        .frame(width: screenSize.width, height: screenSize.height)
                    
                    // ✅ Gradiente protector cinemático
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 250)
                    .allowsHitTesting(false)
                    
                    // ✅ Contenido del anuncio arriba del gradiente
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nativeAd.headline ?? "")
                                .font(.custom("Poppins-Bold", size: 22))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                            
                            if let body = nativeAd.body {
                                Text(body)
                                    .font(.custom("Poppins-Regular", size: 15))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(3)
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        
                        // ✅ Botón de acción Premium
                        Button(action: {
                            // La interacción se maneja nativamente por AdMob
                        }) {
                            HStack {
                                Text(nativeAd.callToAction ?? "Más información")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                        }
                        .padding(.bottom, 60)
                    }
                }
            }
            .ignoresSafeArea()
            
            // ✅ Capa de Controles superior (Sobre el media)
            VStack(spacing: 0) {
                // Progress Bar estilo Story
                HStack(spacing: 4) {
                    ForEach(0..<storyCount, id: \.self) { index in
                        Capsule()
                            .fill(index == storyIndex ? Color.white : Color.white.opacity(0.3))
                            .frame(height: 3)
                            .overlay(
                                index == storyIndex ?
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * (1 - timeRemaining / adDuration))
                                } : nil
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 60)
                
                // Header Nativo
                HStack(spacing: 12) {
                    // Icono del anunciante
                    if let icon = nativeAd.icon {
                        AsyncImage(url: URL(string: icon.imageURL?.absoluteString ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(.ultraThinMaterial)
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nativeAd.advertiser ?? "Anunciante")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)
                        
                        Text("ad.common.sponsored")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Botón cerrar
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Spacer()
            }
        }
        .onAppear {
            timeRemaining = adDuration
            startAdTimer()
        }
        .onDisappear {
            stopAdTimer()
        }
    }
    
    private func startAdTimer() {
        timeRemaining = adDuration
        
        adTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                stopAdTimer()
                onNext()
            }
        }
    }
    
    private func stopAdTimer() {
        adTimer?.invalidate()
        adTimer = nil
    }
}

// MARK: - ✅ NUEVO: MediaView integrado para historias
struct IntegratedStoryMediaView: UIViewRepresentable {
    let nativeAd: NativeAd
    
    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        nativeAdView.nativeAd = nativeAd
        
        // MediaView - Totalmente inmersivo, sin bordes
        let mediaView = MediaView()
        mediaView.contentMode = .scaleAspectFill
        mediaView.backgroundColor = .black
        mediaView.clipsToBounds = true
        mediaView.mediaContent = nativeAd.mediaContent
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.mediaView = mediaView
        
        // Ad Attribution personalizado (REQUERIDO por Google)
        let adAttributionView = UIView()
        adAttributionView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        adAttributionView.layer.cornerRadius = 3
        adAttributionView.translatesAutoresizingMaskIntoConstraints = false
        
        let adAttributionLabel = UILabel()
        adAttributionLabel.text = "Ad"
        adAttributionLabel.font = UIFont(name: "Poppins-Bold", size: 12) ?? UIFont.boldSystemFont(ofSize: 12)
        adAttributionLabel.textColor = .white
        adAttributionLabel.textAlignment = .center
        adAttributionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        adAttributionView.addSubview(adAttributionLabel)
        
        // AdChoices (REQUERIDO por Google)
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.adChoicesView = adChoicesView
        
        // Headline
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.headlineView = headlineLabel
        
        // Body
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.bodyView = bodyLabel
        
        // ✅ QUITADO: CTA Button - No necesario, el tapping general funciona
        // let callToActionButton = UIButton(type: .system)
        // callToActionButton.setTitle(nativeAd.callToAction ?? "Más información", for: .normal)
        // callToActionButton.titleLabel?.font = UIFont(name: "Poppins-SemiBold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        // callToActionButton.setTitleColor(.white, for: .normal)
        // callToActionButton.backgroundColor = UIColor(red: 0, green: 0.66, blue: 0.59, alpha: 1)
        // callToActionButton.layer.cornerRadius = 16
        // callToActionButton.translatesAutoresizingMaskIntoConstraints = false
        // nativeAdView.callToActionView = callToActionButton
        
        // Icon
        let iconView = UIImageView()
        if let iconImage = nativeAd.icon?.image {
            iconView.image = iconImage
        }
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.iconView = iconView
        
        // Advertiser
        let advertiserLabel = UILabel()
        advertiserLabel.text = nativeAd.advertiser ?? "Anunciante"
        advertiserLabel.font = UIFont(name: "Poppins-SemiBold", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
        advertiserLabel.textColor = .white.withAlphaComponent(0.8)
        advertiserLabel.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.advertiserView = advertiserLabel
        
        // Configurar video si existe
        if nativeAd.mediaContent.hasVideoContent {
            let videoController = nativeAd.mediaContent.videoController
            videoController.delegate = context.coordinator
            videoController.isMuted = true
            videoController.play()
        }
        
        // Agregar TODOS los elementos como subvistas de nativeAdView
        nativeAdView.addSubview(mediaView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        // nativeAdView.addSubview(callToActionButton) // ✅ QUITADO: CTA Button
        nativeAdView.addSubview(iconView)
        nativeAdView.addSubview(advertiserLabel)
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.addSubview(adAttributionView)
        
        // Constraints - Layout vertical DENTRO del NativeAdView (como FeedNativeAd)
        NSLayoutConstraint.activate([
            // MediaView - Pantalla completa real
            mediaView.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            mediaView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor),
            mediaView.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor),
            
            // Ad Attribution - Posicionado discretamente arriba
            adAttributionView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 110),
            adAttributionView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 16),
            adAttributionView.widthAnchor.constraint(equalToConstant: 25),
            adAttributionView.heightAnchor.constraint(equalToConstant: 18),
            
            // Ad Attribution Label constraints
            adAttributionLabel.centerXAnchor.constraint(equalTo: adAttributionView.centerXAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: adAttributionView.centerYAnchor),
            
            // AdChoices - Arriba a la derecha
            adChoicesView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 110),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -16),
            
            // Registramos los labels pero los mantenemos fuera de la vista 
            // ya que SwiftUI renderiza el texto cinemático
            headlineLabel.heightAnchor.constraint(equalToConstant: 0),
            bodyLabel.heightAnchor.constraint(equalToConstant: 0),
            iconView.heightAnchor.constraint(equalToConstant: 0),
            advertiserLabel.heightAnchor.constraint(equalToConstant: 0)
            
            // ✅ QUITADO: CTA Button constraints - No necesario, el tapping general funciona
            // callToActionButton.topAnchor.constraint(equalTo: advertiserLabel.bottomAnchor, constant: 16),
            // callToActionButton.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 8),
            // callToActionButton.heightAnchor.constraint(equalToConstant: 44),
            // callToActionButton.widthAnchor.constraint(equalToConstant: 150),
            // callToActionButton.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -8)
        ])
        
        return nativeAdView
    }
    
    func updateUIView(_ uiView: NativeAdView, context: Context) {
        // Actualizar si es necesario
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, VideoControllerDelegate {
        func videoControllerDidPlayVideo(_ videoController: VideoController) {
        }
        
        func videoControllerDidPauseVideo(_ videoController: VideoController) {
        }
        
        func videoControllerDidEndVideoPlayback(_ videoController: VideoController) {
        }
        
        func videoControllerDidMuteVideo(_ videoController: VideoController) {
        }
        
        func videoControllerDidUnmuteVideo(_ videoController: VideoController) {
        }
    }
}
