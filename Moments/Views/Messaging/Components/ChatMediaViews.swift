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

struct GlassmorphicImageMessage: View {
    let imageUrl: String?
    let isSending: Bool
    var isResolvingMedia: Bool = false
    var downsamplingSize: CGSize? = nil
    let progress: Double?
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if isResolvingMedia {
                ChatMediaResolvingPlaceholder()
            } else if let imageUrl, let imageURL = URL(string: imageUrl) {
                ChatKFImage(url: imageURL, downsamplingSize: downsamplingSize)
                    .onTapGesture(perform: onTap)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "photo.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.5))
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
    }
}

struct GlassmorphicVideoMessage: View {
    let videoUrl: String?
    let thumbnailUrl: String?
    let isSending: Bool
    var isResolvingMedia: Bool = false
    var downsamplingSize: CGSize? = nil
    let progress: Double?
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if isResolvingMedia {
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

            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                )

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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .onTapGesture {
            onTap()
        }
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
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .textCase(.uppercase)
                    }
                    .foregroundColor(.white)
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
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
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
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPaused = pressing
        }, perform: {})
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
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .textCase(.uppercase)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
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
