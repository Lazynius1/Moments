import SwiftUI
import UIKit
import Kingfisher

/// Placeholder blur mientras se descifra media o Kingfisher carga la miniatura.
struct ChatMediaResolvingPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.08) : Color(hex: "0B1215").opacity(0.06))
            BlurView(style: .systemThinMaterial)
                .opacity(0.85)
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white.opacity(0.85))
        }
    }
}

/// Overlay centrado: flecha + tamaño del fichero completo.
struct ChatMediaDownloadOverlay: View {
    let sizeLabel: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 46, height: 46)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(sizeLabel ?? NSLocalizedString("chat.media.download", comment: "Download media"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// Placeholder genérico cuando aún no hay miniatura en disco (p. ej. offline).
struct ChatMediaManualDownloadPlaceholder: View {
    let sizeLabel: String?
    var showsVideoBadge: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "4A4A4C"), Color(hex: "2C2C2E"), Color(hex: "1C1C1E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            BlurView(style: .systemUltraThinMaterialDark)
                .opacity(0.28)

            ChatMediaDownloadOverlay(sizeLabel: sizeLabel)
                .background(Color.clear)

            if showsVideoBadge {
                VStack {
                    Spacer()
                    HStack {
                        ChatVideoPlayBadge(size: 14, padding: 6)
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Overlay de progreso de descarga (mismo anillo que la subida).
struct ChatMediaDownloadProgressOverlay: View {
    let progress: Double
    var ringSize: CGFloat = 60
    var lineWidth: CGFloat = 4

    private var clampedProgress: Double {
        min(max(progress, 0.03), 1.0)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
            MediaProgressRing(progress: clampedProgress, size: ringSize, lineWidth: lineWidth)
        }
    }
}

struct GlassmorphicImageMessage: View {
    let imageUrl: String?
    var previewThumbnailUrl: String? = nil
    let isSending: Bool
    var isResolvingMedia: Bool = false
    var isAwaitingManualDownload: Bool = false
    var isDownloadingMedia: Bool = false
    var downloadProgress: Double? = nil
    var downloadSizeLabel: String? = nil
    var downsamplingSize: CGSize? = nil
    let progress: Double?

    private var blurredPreviewURL: URL? {
        if isAwaitingManualDownload,
           let previewThumbnailUrl,
           let url = URL(string: previewThumbnailUrl) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            if isDownloadingMedia {
                ZStack {
                    if let previewURL = blurredPreviewURL {
                        ChatKFImage(url: previewURL, downsamplingSize: downsamplingSize)
                            .blur(radius: 22)
                    } else if let imageUrl, let imageURL = URL(string: imageUrl) {
                        ChatKFImage(url: imageURL, downsamplingSize: downsamplingSize)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    }
                    ChatMediaDownloadProgressOverlay(
                        progress: downloadProgress ?? 0.03,
                        ringSize: 60,
                        lineWidth: 4
                    )
                }
            } else if isAwaitingManualDownload {
                if let previewURL = blurredPreviewURL {
                    ChatKFImage(url: previewURL, downsamplingSize: downsamplingSize)
                        .blur(radius: 22)
                        .overlay { ChatMediaDownloadOverlay(sizeLabel: downloadSizeLabel) }
                } else {
                    ChatMediaManualDownloadPlaceholder(sizeLabel: downloadSizeLabel)
                }
            } else if isResolvingMedia {
                ChatMediaResolvingPlaceholder()
            } else if let imageUrl, let imageURL = URL(string: imageUrl) {
                ChatKFImage(url: imageURL, downsamplingSize: downsamplingSize)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "photo.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }

            if isSending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color.black.opacity(0.4)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 60, lineWidth: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("chat.a11y.photo", comment: "Photo message")))
        .accessibilityHint(Text(NSLocalizedString("chat.a11y.openMedia", comment: "Tap to open media")))
        .accessibilityAddTraits(.isButton)
    }
}

/// Icono de play para miniaturas de vídeo: esquina, sin círculo, con sombra para legibilidad.
struct ChatVideoPlayBadge: View {
    var size: CGFloat = 18
    var padding: CGFloat = 10

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.75), radius: 4, x: 0, y: 1)
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)
            .padding(padding)
    }
}

struct GlassmorphicVideoMessage: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    let isSending: Bool
    var isResolvingMedia: Bool = false
    var isAwaitingManualDownload: Bool = false
    var isDownloadingMedia: Bool = false
    var downloadProgress: Double? = nil
    var downloadSizeLabel: String? = nil
    var downsamplingSize: CGSize? = nil
    let progress: Double?

    private var blurredPreviewURL: URL? {
        if isAwaitingManualDownload,
           let thumbnailUrl,
           let url = URL(string: thumbnailUrl) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            if isDownloadingMedia {
                ZStack {
                    if let previewURL = blurredPreviewURL {
                        ChatKFImage(url: previewURL, downsamplingSize: downsamplingSize)
                            .blur(radius: 22)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    } else if let videoUrl, let url = URL(string: videoUrl) {
                        ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    }
                    ChatMediaDownloadProgressOverlay(
                        progress: downloadProgress ?? 0.03,
                        ringSize: 60,
                        lineWidth: 4
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
            } else if isAwaitingManualDownload {
                if let previewURL = blurredPreviewURL {
                    ChatKFImage(url: previewURL, downsamplingSize: downsamplingSize)
                        .blur(radius: 22)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .overlay { ChatMediaDownloadOverlay(sizeLabel: downloadSizeLabel) }
                } else {
                    ChatMediaManualDownloadPlaceholder(sizeLabel: downloadSizeLabel, showsVideoBadge: true)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }
            } else if isResolvingMedia {
                ChatMediaResolvingPlaceholder()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else if let thumbnailUrl, let url = URL(string: thumbnailUrl) {
                ChatKFImage(url: url, downsamplingSize: downsamplingSize)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }

            if isSending {
                let uploadProgress = max(progress ?? 0.03, 0.03)
                ZStack {
                    Color.black.opacity(0.4)
                    BlurView(style: UIBlurEffect.Style.systemThinMaterialDark)
                    MediaProgressRing(progress: uploadProgress, size: 60, lineWidth: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottomLeading) {
            if !isAwaitingManualDownload && !isDownloadingMedia {
                ChatVideoPlayBadge(size: 22, padding: 12)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isAwaitingManualDownload, blurredPreviewURL != nil {
                ChatVideoPlayBadge(size: 22, padding: 12)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("chat.a11y.video", comment: "Video message")))
        .accessibilityHint(Text(NSLocalizedString("chat.a11y.openMedia", comment: "Tap to open media")))
        .accessibilityAddTraits(.isButton)
    }
}

struct NormalVideoPlayerView: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isPaused = false
    @State private var isMuted = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var externalSeekTime: Double? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let videoUrl = videoUrl, let url = URL(string: videoUrl) {
                MomentsVideoPlayer(
                    url: url,
                    isLooping: true,
                    isPaused: isPaused,
                    isMuted: isMuted,
                    prioritizeSmoothPlayback: true,
                    videoGravity: .resizeAspectFill,
                    onDurationReceived: { value in
                        duration = max(value, 0)
                    },
                    onProgressUpdate: { value in
                        if !isPaused {
                            currentTime = max(value, 0)
                        }
                    },
                    onVideoFinished: {},
                    externalSeekTime: $externalSeekTime
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 14))
                        Text("common.video")
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    )
                    .clipShape(Capsule())

                    Spacer()

                    Button(action: { isMuted.toggle() }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)

                Spacer()

                MomentsVideoPlaybackTimeline(
                    currentTime: currentTime,
                    duration: duration,
                    horizontalPadding: 30,
                    onSeek: { targetTime in
                        currentTime = targetTime
                        externalSeekTime = targetTime
                    }
                )
                .padding(.bottom, 26)
            }
        }
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onAppear {
            GlobalVideoManager.shared.pauseAllVideos()
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            isPaused = pressing
        })
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        dragOffset = 0
                    }
                }
        )
    }
}

struct FullScreenImageView: View {
    let imageUrl: URL
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var progress: Double = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            KFImage(imageUrl)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: 7)

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 14))
                        Text("common.photo")
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)

                Spacer()
            }
        }
        .statusBar(hidden: false)
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onReceive(timer) { _ in
            if progress < 5.0 {
                progress += 0.1
            }
        }
    }
}
