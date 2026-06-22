import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

struct UserModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    var zoomNamespace: Namespace.ID? = nil
    var zoomSourceID: String? = nil
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    var gridIndex: Int = 0
    let descriptor: ProfileGridTileDescriptor
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    init(
        moment: Moment,
        size: CGFloat,
        zoomNamespace: Namespace.ID? = nil,
        zoomSourceID: String? = nil,
        onTap: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil,
        gridIndex: Int = 0,
        descriptor: ProfileGridTileDescriptor? = nil
    ) {
        self.moment = moment
        self.size = size
        self.zoomNamespace = zoomNamespace
        self.zoomSourceID = zoomSourceID
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.gridIndex = gridIndex
        self.descriptor = descriptor ?? ProfileGridTileDescriptor.standard(for: moment)
    }

    private var cellWidth: CGFloat {
        ProfileMomentsGridMetrics.tileSize(kind: descriptor.layoutKind, unitWidth: size).width
    }

    private var cellHeight: CGFloat {
        ProfileMomentsGridMetrics.tileSize(kind: descriptor.layoutKind, unitWidth: size).height
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mediaBody
            cinematicOverlay
            topChrome
            bottomChrome
        }
        .profileGridLiftedSource(moment: moment, gridIndex: gridIndex)
        .frame(width: cellWidth, height: cellHeight)
        .clipped()
        .modifier(ProfileMomentZoomSourceModifier(namespace: zoomNamespace, sourceID: zoomSourceID))
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isPressed)
        .profileGridThumbnailFrameReporter(
            momentId: moment.id ?? "profile-grid-\(gridIndex)",
            coordinateSpace: .named("profileGridOverlay")
        )
        .overlay {
            ProfileMomentThumbnailGestureOverlay(
                onTap: onTap,
                onLongPress: onLongPress,
                onPressingChanged: { isPressed = $0 }
            )
        }
    }

    @ViewBuilder
    private var mediaBody: some View {
        if descriptor.usesPortraitCrop {
            portraitMedia
        } else if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
            if mediaItem.type == .video {
                if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                    imageView(imageURL: thumbnailUrl)
                } else {
                    videoThumbnailView(videoURL: mediaItem.url)
                }
            } else {
                imageView(imageURL: mediaItem.url)
            }
        } else if let imagePath = moment.imagePath, let url = getImageURL(from: imagePath) {
            GridPreviewThumbnailFrame(size: size, settings: moment.gridPreviewSettings) {
                KFImage(url)
                    .placeholder {
                        Rectangle()
                            .fill(UserProfileColors.cardBackground)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .foregroundColor(UserProfileColors.textTertiary)
                            )
                            .overlay(ProgressView().tint(UserProfileColors.accent))
                    }
                    .resizable()
            }
            .contentShape(Rectangle())
        } else {
            emptyContentView()
        }
    }

    @ViewBuilder
    private var topChrome: some View {
        VStack {
            HStack {
                if moment.isCarouselMoment {
                    MomentCarouselIndicatorIcon()
                        .padding(6)
                }
                if descriptor.showsScheduledCue && moment.authorId == Auth.auth().currentUser?.uid {
                    scheduledBadgeView
                        .padding(6)
                }
                Spacer()
                if descriptor.showsPin {
                    pinnedBadgeView
                        .padding(6)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if descriptor.showsPlayCue {
            HStack(spacing: 4) {
                ChatVideoPlayBadge(size: videoPlayBadgeSize, padding: 8)

                if descriptor.showsDuration, let duration = moment.videoDuration {
                    Text(Self.formatVideoDuration(duration))
                        .font(.custom("Poppins-SemiBold", size: 11))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                }
            }
        }
    }

    private var videoPlayBadgeSize: CGFloat {
        switch descriptor.layoutKind {
        case .hero, .tall:
            return 18
        case .unit:
            return 14
        }
    }

    @ViewBuilder
    private var portraitMedia: some View {
        if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
            if mediaItem.type == .image {
                portraitFillImage(urlString: mediaItem.url)
            } else if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                portraitFillImage(urlString: thumbnailUrl)
            } else {
                videoThumbnailView(videoURL: mediaItem.url)
            }
        } else if let imagePath = moment.previewImageURLString, !imagePath.isEmpty {
            portraitFillImage(urlString: imagePath)
        } else if let video = moment.previewVideoURLString, !video.isEmpty {
            videoThumbnailView(videoURL: video)
        } else {
            emptyContentView()
        }
    }

    @ViewBuilder
    private func portraitFillImage(urlString: String) -> some View {
        if let url = getImageURL(from: urlString) {
            KFImage(url)
                .placeholder {
                    Rectangle().fill(UserProfileColors.cardBackground)
                }
                .resizable()
                .scaledToFill()
                .frame(width: cellWidth, height: cellHeight)
                .clipped()
        } else {
            emptyContentView()
        }
    }

    @ViewBuilder
    private var pinnedBadgeView: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(5)
            .background(Color.black.opacity(colorScheme == .dark ? 0.58 : 0.48))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var scheduledBadgeView: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 7, weight: .bold))
            Text(moment.scheduledRemainingText)
                .font(.custom("Poppins-SemiBold", size: 8))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.52))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var cinematicOverlay: some View {
        if descriptor.showsPlayCue || descriptor.showsPin || descriptor.showsScheduledCue {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.clear,
                    Color.black.opacity(descriptor.usesPortraitCrop ? 0.34 : 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func videoThumbnailView(videoURL: String) -> some View {
        ZStack {
            if let thumbnail = videoThumbnail {
                if descriptor.usesPortraitCrop {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cellWidth, height: cellHeight)
                        .clipped()
                } else {
                    GridPreviewThumbnailFrame(size: size, settings: moment.gridPreviewSettings) {
                        Image(uiImage: thumbnail)
                            .resizable()
                    }
                    .contentShape(Rectangle())
                }
            } else {
                Rectangle()
                    .fill(UserProfileColors.cardBackground)
                    .frame(width: cellWidth, height: cellHeight)
                    .overlay(
                        Group {
                            if isLoadingVideoThumbnail {
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(UserProfileColors.accent)
                                        .scaleEffect(0.8)
                                    Text("userProfile.video.loading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                        .foregroundColor(UserProfileColors.textTertiary)
                                    Text("userProfile.video")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
                                }
                            }
                        }
                    )
            }
        }
        .onAppear {
            loadVideoThumbnail(from: videoURL)
        }
    }

    @ViewBuilder
    private func imageView(imageURL: String) -> some View {
        if let url = getImageURL(from: imageURL) {
            GridPreviewThumbnailFrame(size: size, settings: moment.gridPreviewSettings) {
                KFImage(url)
                    .placeholder {
                        Rectangle()
                            .fill(UserProfileColors.cardBackground)
                            .overlay(
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(UserProfileColors.accent)
                                        .scaleEffect(0.8)
                                    Text("userProfile.image.loading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(UserProfileColors.textSecondary)
                                }
                            )
                    }
                    .resizable()
            }
            .contentShape(Rectangle())
        } else {
            emptyContentView()
        }
    }

    @ViewBuilder
    private func emptyContentView() -> some View {
        Rectangle()
            .fill(UserProfileColors.cardBackground)
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(UserProfileColors.textTertiary)

                    Text(moment.content.isEmpty ? NSLocalizedString("userProfile.noContent", comment: "No content") : String(moment.content.prefix(12)))
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(UserProfileColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 3)
                }
            )
    }

    private func loadVideoThumbnail(from urlString: String) {
        guard let url = URL(string: urlString) else { return }

        isLoadingVideoThumbnail = true

        Task {
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: size * 2, height: size * 2)

            do {
                let (cgImage, _) = try await imageGenerator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
                await MainActor.run {
                    self.videoThumbnail = UIImage(cgImage: cgImage)
                    self.isLoadingVideoThumbnail = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingVideoThumbnail = false
                }
            }
        }
    }

    private func getImageURL(from path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
    }

    private static func formatVideoDuration(_ duration: Double) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

func calculateBentoGridHeight(moments: [Moment]) -> CGFloat {
    let descriptors = ProfileBentoTileAssigner.assign(moments: moments)
    return ProfileMomentsGridMetrics.bentoHeight(tileKinds: descriptors.map(\.layoutKind))
}

func calculateTaggedGridHeight(moments: [Moment]) -> CGFloat {
    let descriptors = ProfileBentoTileAssigner.simple(moments: moments)
    return ProfileMomentsGridMetrics.bentoHeight(tileKinds: descriptors.map(\.layoutKind))
}
