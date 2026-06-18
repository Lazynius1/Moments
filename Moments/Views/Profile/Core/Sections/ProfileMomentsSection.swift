import SwiftUI
import Kingfisher
import AVFoundation
import FirebaseAuth

enum ProfileMomentsGridMetrics {
    static let spacing: CGFloat = 1
    static let columns = 3

    static func columnWidth(for availableWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
        let totalSpacing = spacing * CGFloat(columns - 1)
        return (availableWidth - totalSpacing) / CGFloat(columns)
    }

    static func tileSize(kind: BentoTileKind, unitWidth: CGFloat, spacing: CGFloat = spacing) -> CGSize {
        switch kind {
        case .unit:
            return CGSize(width: unitWidth, height: unitWidth)
        case .tall:
            return CGSize(width: unitWidth, height: unitWidth * 2 + spacing)
        case .hero:
            let side = unitWidth * 2 + spacing
            return CGSize(width: side, height: side)
        }
    }

    static func bentoHeight(tileKinds: [BentoTileKind], availableWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
        guard !tileKinds.isEmpty else { return 0 }
        let unitWidth = columnWidth(for: availableWidth)
        let columnCount = columns
        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)

        for kind in tileKinds {
            let tileSize = tileSize(kind: kind, unitWidth: unitWidth)
            let colSpan = kind.colSpan
            var bestColumn = 0
            var bestY = CGFloat.greatestFiniteMagnitude

            for startColumn in 0...(columnCount - colSpan) {
                let y = columnHeights[startColumn..<(startColumn + colSpan)].map { height in
                    height > 0 ? height + spacing : 0
                }.max() ?? 0
                if y < bestY || (y == bestY && startColumn < bestColumn) {
                    bestY = y
                    bestColumn = startColumn
                }
            }

            let newBottom = bestY + tileSize.height
            for column in bestColumn..<(bestColumn + colSpan) {
                columnHeights[column] = newBottom
            }
        }

        return columnHeights.max() ?? 0
    }
}

struct ModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let customListNamesById: [String: String]
    var zoomNamespace: Namespace.ID? = nil
    var zoomSourceID: String? = nil
    let onTap: (() -> Void)?
    var onLongPress: (() -> Void)? = nil
    var isInteractionEnabled: Bool = true
    var usesDiscreetAudienceIcon: Bool = false
    var showsAudienceBadge: Bool = true
    var gridIndex: Int = 0
    let descriptor: ProfileGridTileDescriptor
    @State private var isPressed = false
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    private var cellWidth: CGFloat {
        ProfileMomentsGridMetrics.tileSize(kind: descriptor.layoutKind, unitWidth: size).width
    }

    private var cellHeight: CGFloat {
        ProfileMomentsGridMetrics.tileSize(kind: descriptor.layoutKind, unitWidth: size).height
    }

    init(
        moment: Moment,
        size: CGFloat,
        customListNamesById: [String: String] = [:],
        zoomNamespace: Namespace.ID? = nil,
        zoomSourceID: String? = nil,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        isInteractionEnabled: Bool = true,
        usesDiscreetAudienceIcon: Bool = false,
        showsAudienceBadge: Bool = true,
        gridIndex: Int = 0,
        descriptor: ProfileGridTileDescriptor? = nil
    ) {
        self.moment = moment
        self.size = size
        self.customListNamesById = customListNamesById
        self.zoomNamespace = zoomNamespace
        self.zoomSourceID = zoomSourceID
        self.onTap = onTap
        self.onLongPress = onLongPress
        self.isInteractionEnabled = isInteractionEnabled
        self.usesDiscreetAudienceIcon = usesDiscreetAudienceIcon
        self.showsAudienceBadge = showsAudienceBadge
        self.gridIndex = gridIndex
        self.descriptor = descriptor ?? ProfileGridTileDescriptor.standard(for: moment)
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
            if isInteractionEnabled, onTap != nil || onLongPress != nil {
                ProfileMomentThumbnailGestureOverlay(
                    onTap: { onTap?() },
                    onLongPress: onLongPress,
                    onPressingChanged: { isPressed = $0 }
                )
            }
        }
    }

    private var resolvedContentAudience: ContentAudience {
        let audience = ContentAudience.fromAudienceValue(moment.audience)
        if moment.customListId != nil, audience == .custom {
            return .customList
        }
        return audience
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
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .foregroundColor(.gray.opacity(0.6))
                            )
                            .overlay(ProgressView().tint(Color(hex: "007AFF")))
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
                if showsAudienceBadge && usesDiscreetAudienceIcon {
                    ActivityGridAudienceIcon(audience: resolvedContentAudience)
                        .padding(6)
                        .accessibilityLabel(resolvedContentAudience.title)
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
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)

                if descriptor.showsDuration, let duration = moment.videoDuration {
                    Text(Self.formatVideoDuration(duration))
                        .font(.custom("Poppins-SemiBold", size: 8))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.34))
            .clipShape(Capsule())
            .padding(6)
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
                    Rectangle().fill(.ultraThinMaterial)
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
    private var pinnedBadgeView: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(5)
            .background(Color.black.opacity(0.56))
            .clipShape(Circle())
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
                    .fill(.ultraThinMaterial)
                    .frame(width: cellWidth, height: cellHeight)
                    .overlay(
                        Group {
                            if isLoadingVideoThumbnail {
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(Color(hex: "007AFF"))
                                        .scaleEffect(0.8)
                                    Text("profile.video.uploading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray.opacity(0.6))
                                    Text("profile.video")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
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
                            .fill(.ultraThinMaterial)
                            .overlay(
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(Color(hex: "007AFF"))
                                        .scaleEffect(0.8)
                                    Text("profile.image.uploading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
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
            .fill(.ultraThinMaterial)
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(.gray.opacity(0.6))

                    Text(moment.content.isEmpty ? NSLocalizedString("profile.content.empty", comment: "No content text") : String(moment.content.prefix(12)))
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(.white.opacity(0.8))
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

struct ProfileSectionEmptyState: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(ProfileColors.textPrimary.opacity(0.05))
                    .frame(width: 54, height: 54)

                if icon == "bookmark" {
                    AttachmentIconView(icon: .bookmark, preset: .profileEmptyState, tintColor: ProfileColors.textSecondary.opacity(0.7))
                } else if icon == "person.crop.rectangle" {
                    AttachmentIconView(icon: .tagged, preset: .profileEmptyState, tintColor: ProfileColors.textSecondary.opacity(0.7))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(ProfileColors.textSecondary.opacity(0.7))
                }
            }

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.custom("Poppins-SemiBold", size: 17))
                    .foregroundColor(ProfileColors.textPrimary)

                Text(subtitleKey)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

struct ModernEmptyMomentsView: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "camera",
            titleKey: "profile.moments.empty.title",
            subtitleKey: "profile.moments.empty.subtitle"
        )
    }
}

struct ProfileSavedPlaceholder: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "bookmark",
            titleKey: LocalizedStringKey("profile.saved.empty.title"),
            subtitleKey: LocalizedStringKey("profile.saved.empty.subtitle")
        )
    }
}

struct MomentCarouselIndicatorIcon: View {
    var size: CGFloat = 18

    var body: some View {
        Image("CarouselPostIcon")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
