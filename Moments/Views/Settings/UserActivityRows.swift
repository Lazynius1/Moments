import SwiftUI
import Kingfisher
import AVFoundation

struct ActivityCommentItemRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityCommentItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onOpenMoment: () -> Void
    let onOpenAuthorAvatar: (Bool) -> Void
    let onOpenAuthorProfile: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isSelectionMode {
                    ActivityCommentMomentPreview(moment: item.moment, canView: item.canView, size: 84)
                } else {
                    Button(action: onOpenMoment) {
                        ActivityCommentMomentPreview(moment: item.moment, canView: item.canView, size: 84)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isSelectionMode {
                        Text(item.moment?.username ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                    } else {
                        Button(action: onOpenAuthorProfile) {
                            Text(item.moment?.username ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                                .font(.custom("Poppins-SemiBold", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }

                    if !item.canView {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if isSelectionMode {
                        StoryRingAvatarView(
                            userId: item.authorId,
                            size: 30,
                            lineWidth: 2.2
                        )
                    } else {
                        StoryRingAvatarView(
                            userId: item.authorId,
                            size: 30,
                            lineWidth: 2.2,
                            onTap: { hasStory in
                                onOpenAuthorAvatar(hasStory)
                            }
                        )
                    }
                }

                Text(item.moment?.content.isEmpty == false
                     ? (item.moment?.content ?? "")
                     : NSLocalizedString("userActivity.simple.comments.momentNoContent", comment: "Moment without content"))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(2)

                Text(NSLocalizedString("userActivity.simple.comments.yourComment", comment: "Your comment label"))
                    .font(.custom("Poppins-SemiBold", size: 11))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.82))

                Text(item.commentText.isEmpty
                     ? NSLocalizedString("userActivity.simple.comments.emptyComment", comment: "Empty comment fallback")
                     : item.commentText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(3)

                Text(item.commentedAt.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray.opacity(0.85))
            }

            Spacer(minLength: 0)

            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color(hex: "2563EB") : Color.clear, lineWidth: 1.6)
                )
        )
    }
}

struct ActivityCommentMomentPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let moment: Moment?
    let canView: Bool
    let size: CGFloat
    @State private var generatedVideoThumbnail: UIImage?
    @State private var isGeneratingThumbnail = false

    var body: some View {
        ScreenshotProtectedView(isProtected: isProtectedMoment(moment)) {
            ZStack {
                if let moment {
                    preview(for: moment)
                } else {
                    placeholder
                }

                if !canView {
                    restrictedOverlay
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func isProtectedMoment(_ moment: Moment?) -> Bool {
        guard let audience = moment?.audience?.lowercased() else { return false }
        return audience != "everyone"
    }

    @ViewBuilder
    private func preview(for moment: Moment) -> some View {
        if let media = moment.primaryVisibleMediaItem {
            if media.type == .image {
                mediaImage(urlString: media.url)
            } else {
                mediaVideoPreview(videoURL: media.url, thumbnailURL: media.thumbnailUrl ?? moment.thumbnailUrl)
            }
        } else if let imagePath = moment.previewImageURLString, !imagePath.isEmpty {
            mediaImage(urlString: imagePath)
        } else if let video = moment.previewVideoURLString, !video.isEmpty {
            mediaVideoPreview(videoURL: video, thumbnailURL: moment.previewImageURLString ?? moment.thumbnailUrl)
        } else {
            placeholder
        }
    }

    private func mediaImage(urlString: String) -> some View {
        KFImage(URL(string: urlString))
            .placeholder { placeholder }
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }

    private func mediaVideoPreview(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, !thumb.isEmpty {
                KFImage(URL(string: thumb))
                    .placeholder { placeholder }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else if let generatedVideoThumbnail {
                Image(uiImage: generatedVideoThumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                placeholder
                    .onAppear {
                        generateThumbnail(for: videoURL)
                    }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .shadow(radius: 3)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.gray)
        }
    }

    private var restrictedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                )

            VStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(NSLocalizedString("savedMoments.restricted.title", comment: "Saved moment restricted title"))
                    .font(.custom("Poppins-SemiBold", size: 8))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("savedMoments.restricted.subtitle", comment: "Saved moment restricted subtitle"))
                    .font(.custom("Poppins-Regular", size: 7))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
        }
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil, let videoURL = URL(string: videoPath) else { return }
        isGeneratingThumbnail = true

        Task {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 500, height: 500)

            do {
                let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600))
                let thumbnail = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.generatedVideoThumbnail = thumbnail
                    self.isGeneratingThumbnail = false
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingThumbnail = false
                }
            }
        }
    }
}

struct ActivityEventRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityEventItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onOpenTargetProfile: () -> Void
    let onRowTap: (() -> Void)?

    private var kindLowercased: String {
        item.kind?.lowercased() ?? ""
    }

    private var shouldShowTrailingThumbnail: Bool {
        guard let thumbUrl = item.thumbnailUrl, !thumbUrl.isEmpty else { return false }
        // En visitas/followers no mostramos bloque derecho para evitar hueco visual.
        if kindLowercased == "visit" || kindLowercased == "follower" {
            return false
        }
        return true
    }

    private var hasTrailingAccessory: Bool {
        shouldShowTrailingThumbnail || isSelectionMode
    }

    private var shouldUseSplitHeaderLayout: Bool {
        kindLowercased == "visit" || kindLowercased == "follower"
    }

    var body: some View {
        Group {
            if item.kind?.lowercased() == "echo" {
                echoCardContent
            } else if kindLowercased == "visit" || kindLowercased == "follower" {
                visitFollowerCardContent
            } else {
                HStack(alignment: .top, spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        if let actionText = item.actionText, !actionText.isEmpty {
                            if shouldUseSplitHeaderLayout {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(item.title)
                                        .font(.custom("Poppins-SemiBold", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    Text(actionText)
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(item.title)
                                        .font(.custom("Poppins-SemiBold", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                    Text(actionText)
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(item.title)
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        HStack(spacing: 6) {
                            Text(item.timestamp.timeAgoDisplay())
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(.gray.opacity(0.85))

                            if hasContext {
                                Text("•")
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.gray.opacity(0.7))

                                if let username = item.targetUsername,
                                   !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(contextPrefix)
                                        .font(.custom("Poppins-Regular", size: 11))
                                        .foregroundColor(.gray.opacity(0.85))

                                    Button {
                                        onOpenTargetProfile()
                                    } label: {
                                        Text(username)
                                            .font(.custom("Poppins-SemiBold", size: 11))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                } else if let context = item.contextText, !context.isEmpty {
                                    Text(context)
                                        .font(.custom("Poppins-Regular", size: 11))
                                        .foregroundColor(.gray.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if hasTrailingAccessory {
                        Spacer(minLength: 0)
                    }

                    if shouldShowTrailingThumbnail, let thumbUrl = item.thumbnailUrl, !thumbUrl.isEmpty {
                        KFImage(URL(string: thumbUrl))
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.trailing, 4)
                    }

                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onRowTap?()
            } else {
                onRowTap?()
            }
        }
    }

    private var echoCardContent: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumbUrl = item.thumbnailUrl,
                   !thumbUrl.isEmpty,
                   let url = URL(string: thumbUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    EchoesIconView(
                        size: EchoesIconMetrics.rowThumbnail,
                        gradient: EchoesIconView.echoesBrandGradientHorizontal
                    )
                }
            }
            .frame(width: 56, height: 56)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(participantsText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(expiresLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.14), Color.white.opacity(0.06)]
                            : [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .padding(.vertical, 1)
    }

    private var statusColor: Color {
        switch item.echoStatusRaw?.lowercased() {
        case EchoStatus.pending.rawValue:
            return .orange
        case EchoStatus.active.rawValue:
            return .green
        case EchoStatus.completed.rawValue:
            return .purple
        default:
            return .gray
        }
    }

    private var statusText: String {
        switch item.echoStatusRaw?.lowercased() {
        case EchoStatus.pending.rawValue:
            return NSLocalizedString("echo.status.pending", comment: "")
        case EchoStatus.active.rawValue:
            return NSLocalizedString("echo.status.active", comment: "")
        case EchoStatus.completed.rawValue:
            return NSLocalizedString("echo.status.completed", comment: "")
        default:
            return NSLocalizedString("echo.status.expired", comment: "")
        }
    }

    private var participantsText: String {
        let count = max(item.echoParticipantsCount ?? 0, 0)
        let format = count == 1 ? "echo.participants.singular" : "echo.participants.plural"
        return String(format: NSLocalizedString(format, comment: ""), count)
    }

    private var expiresLabel: String {
        guard let expiresAt = item.echoExpiresAt else {
            return item.timestamp.timeAgoDisplay()
        }

        if expiresAt <= Date() {
            return NSLocalizedString("echo.status.expired", comment: "")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: expiresAt, relativeTo: Date())
    }

    private var hasContext: Bool {
        if let username = item.targetUsername, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let context = item.contextText, !context.isEmpty {
            return true
        }
        return false
    }

    private var contextPrefix: String {
        switch item.kind?.lowercased() {
        case "poll":
            return NSLocalizedString("userActivity.simple.stickers.poll.contextPrefix", comment: "Poll context prefix")
        case "question":
            return NSLocalizedString("userActivity.simple.stickers.question.contextPrefix", comment: "Question context prefix")
        default:
            return ""
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let path = item.actorProfileImagePath,
           !path.isEmpty,
           let url = URL(string: path) {
            KFImage(url)
                .placeholder {
                    fallbackAvatar
                }
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else if let userId = item.actorId, !userId.isEmpty {
            AsyncProfileImageView(userId: userId)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "4F46E5").opacity(0.13))
                .frame(width: 34, height: 34)

            if item.icon == "EchoesIcon" || item.icon == "camera.aperture" {
                EchoesIconView(
                    size: EchoesIconMetrics.rowAvatar,
                    tintColor: Color(hex: "4F46E5")
                )
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "4F46E5"))
            }
        }
    }

    private var cleanDescriptionText: String {
        if kindLowercased == "visit" {
            return NSLocalizedString("userActivity.event.visit.clean", value: "Visited your profile", comment: "")
        } else if kindLowercased == "follower" {
            return NSLocalizedString("userActivity.event.follow.clean", value: "Started following you", comment: "")
        }
        return item.subtitle
    }

    private var visitFollowerCardContent: some View {
        HStack(alignment: .center, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    Text(item.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.secondary)
                }
                
                Text(cleanDescriptionText)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let actionText = item.actionText, !actionText.isEmpty {
                Button {
                    onOpenTargetProfile()
                } label: {
                    Text(actionText)
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.12), Color.white.opacity(0.06)]
                                            : [Color.black.opacity(0.08), Color.black.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.14), Color.white.opacity(0.06)]
                                            : [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActivityReactionMomentCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityReactionItem
    let size: CGFloat
    let isSelectionMode: Bool
    let isSelected: Bool
    @State private var generatedVideoThumbnail: UIImage?
    @State private var isGeneratingThumbnail = false

    var body: some View {
        ScreenshotProtectedView(isProtected: isProtectedMoment(item.moment)) {
            ZStack(alignment: .topLeading) {
                cardPreview
                    .frame(width: size, height: size)
                    .blur(radius: item.canView ? 0 : 16)
                    .clipped()

                if !item.canView {
                    restrictedOverlay
                }

                if item.reactionType == "moment" || item.reactionType == "reel" || item.reactionType == "archived" || item.reactionType == "recentlyDeleted" {
                    audienceBadge
                        .padding(6)
                } else {
                    reactionBadge
                        .padding(6)
                }

                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(isSelected ? Color(hex: "2563EB") : .white.opacity(0.92))
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func isProtectedMoment(_ moment: Moment?) -> Bool {
        guard let audience = moment?.audience?.lowercased() else { return false }
        return audience != "everyone"
    }

    @ViewBuilder
    private var cardPreview: some View {
        if let moment = item.moment {
            preview(for: moment)
        } else {
            ZStack {
                Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.gray)
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func preview(for moment: Moment) -> some View {
        if let media = moment.primaryVisibleMediaItem {
            if media.type == .image {
                mediaImage(urlString: media.url)
            } else {
                mediaVideoPreview(videoURL: media.url, thumbnailURL: media.thumbnailUrl ?? moment.thumbnailUrl)
            }
        } else if let imagePath = moment.previewImageURLString, !imagePath.isEmpty {
            mediaImage(urlString: imagePath)
        } else if let video = moment.previewVideoURLString, !video.isEmpty {
            mediaVideoPreview(videoURL: video, thumbnailURL: moment.previewImageURLString ?? moment.thumbnailUrl)
        } else {
            videoPlaceholder
        }
    }

    private func mediaImage(urlString: String) -> some View {
        KFImage(URL(string: urlString))
            .placeholder {
                Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            }
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }

    private func mediaVideoPreview(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, !thumb.isEmpty {
                KFImage(URL(string: thumb))
                    .placeholder {
                        Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else if let generatedVideoThumbnail {
                Image(uiImage: generatedVideoThumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                videoPlaceholder
                    .onAppear {
                        generateThumbnail(for: videoURL)
                    }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 3)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "video")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.gray)
        }
        .frame(width: size, height: size)
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil, let videoURL = URL(string: videoPath) else { return }
        isGeneratingThumbnail = true

        Task {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 700, height: 700)

            do {
                let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600))
                let thumbnail = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.generatedVideoThumbnail = thumbnail
                    self.isGeneratingThumbnail = false
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingThumbnail = false
                }
            }
        }
    }

    private var reactionBadge: some View {
        let style = reactionStyle(from: item.reactionType)

        return HStack(spacing: 4) {
            Text(style.icon)
                .font(.system(size: 13))

            Text(style.label)
                .font(.custom("Poppins-SemiBold", size: 10))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(style.color.opacity(0.88))
        )
    }

    private var restrictedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                )

            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(NSLocalizedString("savedMoments.restricted.title", comment: "Saved moment restricted title"))
                    .font(.custom("Poppins-SemiBold", size: 10))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("savedMoments.restricted.subtitle", comment: "Saved moment restricted subtitle"))
                    .font(.custom("Poppins-Regular", size: 9))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var audienceBadge: some View {
        guard let moment = item.moment else { return AnyView(EmptyView()) }

        let normalizedAudience = moment.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? "everyone"

        let icon: String
        let title: String
        let background: Color

        switch normalizedAudience {
        case "bestfriends", "bestfriend":
            icon = "heart.fill"
            title = NSLocalizedString("audience.type.bestFriends", comment: "")
            background = Color(hex: "24C26A").opacity(0.92)
        case "connections", "connection", "mutuals", "mutual":
            icon = "person.2.fill"
            title = NSLocalizedString("audience.type.connections", comment: "")
            background = Color(hex: "00B4D8").opacity(0.92)
        case "onlyme":
            icon = "lock.fill"
            title = NSLocalizedString("audience.type.onlyMe", comment: "")
            background = Color.black.opacity(0.78)
        default:
            icon = "globe"
            title = NSLocalizedString("audience.type.everyone", comment: "")
            background = Color(hex: "0EA5A3").opacity(0.9)
        }

        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 8))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
        )
    }

    private func reactionStyle(from rawValue: String) -> (icon: String, label: String, color: Color) {
        if rawValue.lowercased() == "tagged" {
            return ("🏷️", NSLocalizedString("profile.tab.tagged", comment: "Tagged tab"), Color(hex: "F59E0B"))
        }
        if let type = ReactionType(rawValue: rawValue) {
            return (type.icon, type.displayName, type.color)
        }

        let fallback = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            return ("✨", NSLocalizedString("userActivity.simple.reaction.unknown", comment: "Unknown reaction"), Color(hex: "4F46E5"))
        }

        return ("✨", fallback.capitalized, Color(hex: "4F46E5"))
    }
}

struct ActivityDeletedStoryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityDeletedStoryItem
    let size: CGFloat
    let isSelectionMode: Bool
    let isSelected: Bool

    private var previewURLString: String? {
        if item.story.mediaItem.type == .video,
           let thumbnail = item.story.mediaItem.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !thumbnail.isEmpty {
            return thumbnail
        }

        let url = item.story.mediaItem.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                .overlay {
                    if let previewURLString, let url = URL(string: previewURLString) {
                        KFImage(url)
                            .placeholder {
                                placeholder
                            }
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 4) {
                Image(systemName: item.story.mediaItem.type == .video ? "play.fill" : "circle.dashed")
                    .font(.system(size: 10, weight: .bold))
                Text(NSLocalizedString("notifications.tab.stories", comment: "Stories"))
                    .font(.custom("Poppins-SemiBold", size: 10))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .padding(6)

            if isSelectionMode {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? Color(hex: "2563EB") : .white.opacity(0.92))
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: item.story.mediaItem.type == .video ? "play.rectangle.fill" : "photo")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}
