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
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                    } else {
                        Button(action: onOpenAuthorProfile) {
                            Text(item.moment?.username ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }

                    if !item.canView {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.gray)
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
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(.gray)
                    .lineLimit(2)

                Text(NSLocalizedString("userActivity.simple.comments.yourComment", comment: "Your comment label"))
                    .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.82))

                Text(item.commentText.isEmpty
                     ? NSLocalizedString("userActivity.simple.comments.emptyComment", comment: "Empty comment fallback")
                     : item.commentText)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(3)

                Text(item.commentedAt.timeAgoDisplay())
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundStyle(.gray.opacity(0.85))
            }

            Spacer(minLength: 0)

            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
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

                if let moment, moment.isCarouselMoment, canView {
                    VStack {
                        HStack {
                            MomentCarouselIndicatorIcon(size: 15)
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
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
                mediaVideoPreview(
                    videoURL: media.url,
                    thumbnailURL: resolvedVideoThumbnailURL(for: moment, preferred: media.thumbnailUrl)
                )
            }
        } else if let imagePath = moment.previewImageURLString, !imagePath.isEmpty {
            mediaImage(urlString: imagePath)
        } else if let video = moment.previewVideoURLString, !video.isEmpty {
            mediaVideoPreview(
                videoURL: video,
                thumbnailURL: resolvedVideoThumbnailURL(for: moment, preferred: moment.previewImageURLString)
            )
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

            VStack {
                Spacer()
                HStack {
                    ChatVideoPlayBadge(size: 14, padding: 8)
                    Spacer()
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private func resolvedVideoThumbnailURL(for moment: Moment, preferred: String?) -> String? {
        let candidates = [
            preferred,
            moment.previewImageURLString,
            moment.thumbnailUrl
        ]

        let normalizedVideoURL = moment.previewVideoURLString?.trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { continue }
            if normalizedVideoURL == nil || trimmed != normalizedVideoURL {
                return trimmed
            }
        }

        return nil
    }

    private var placeholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.gray)
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
                    .foregroundStyle(.white.opacity(0.95))

                Text(NSLocalizedString("savedMoments.restricted.title", comment: "Saved moment restricted title"))
                    .font(.system(size: legacyPoppinsSize(8), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("savedMoments.restricted.subtitle", comment: "Saved moment restricted subtitle"))
                    .font(.system(size: legacyPoppinsSize(7)))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
        }
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil else { return }
        isGeneratingThumbnail = true

        Task {
            let image = await VideoThumbnailCache.shared.thumbnail(for: videoPath)
            await MainActor.run {
                self.generatedVideoThumbnail = image ?? self.generatedVideoThumbnail
                self.isGeneratingThumbnail = false
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
                                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    Text(actionText)
                                        .font(.system(size: legacyPoppinsSize(12)))
                                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                    Text(actionText)
                                        .font(.system(size: legacyPoppinsSize(12)))
                                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(item.title)
                                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.system(size: legacyPoppinsSize(13)))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        HStack(spacing: 6) {
                            Text(item.timestamp.timeAgoDisplay())
                                .font(.system(size: legacyPoppinsSize(11)))
                                .foregroundStyle(.gray.opacity(0.85))

                            if hasContext {
                                Text("•")
                                    .font(.system(size: legacyPoppinsSize(10)))
                                    .foregroundStyle(.gray.opacity(0.7))

                                if let username = item.targetUsername,
                                   !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(contextPrefix)
                                        .font(.system(size: legacyPoppinsSize(11)))
                                        .foregroundStyle(.gray.opacity(0.85))

                                    Button {
                                        onOpenTargetProfile()
                                    } label: {
                                        Text(username)
                                            .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                } else if let context = item.contextText, !context.isEmpty {
                                    Text(context)
                                        .font(.system(size: legacyPoppinsSize(11)))
                                        .foregroundStyle(.gray.opacity(0.85))
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
                            .foregroundStyle(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(participantsText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(expiresLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
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

        return MomentsFormat.relativeTime(
            from: expiresAt,
            style: .conversational(unitsStyle: .short)
        )
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
                .fill(SettingsProfileColors.accentBackground(colorScheme, opacity: 0.13))
                .frame(width: 34, height: 34)

            if item.icon == "EchoesIcon" || item.icon == "camera.aperture" {
                EchoesIconView(
                    size: EchoesIconMetrics.rowAvatar,
                    tintColor: SettingsProfileColors.accent(colorScheme)
                )
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsProfileColors.accent(colorScheme))
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
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))
                    
                    Text(item.timestamp.timeAgoDisplay())
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(.secondary)
                }
                
                Text(cleanDescriptionText)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let actionText = item.actionText, !actionText.isEmpty {
                Button {
                    onOpenTargetProfile()
                } label: {
                    Text(actionText)
                        .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
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
    var overlayBadge: ActivityOverlayBadgeStyle = .none
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

                overlayContent

                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(isSelected ? Color(hex: "2563EB") : .white.opacity(0.92))
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .clipped()
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch overlayBadge {
        case .reactionDiscreet:
            discreetReactionBadge
                .frame(width: size, height: size, alignment: .bottomTrailing)
        case .audience:
            discreetAudienceIcon
                .frame(width: size, height: size, alignment: .topLeading)
        case .none:
            if isVideoMoment, item.canView {
                ActivityThumbnailVideoPlayIndicator()
                    .frame(width: size, height: size)
            }
        }
    }

    private var discreetReactionBadge: some View {
        let style = reactionStyle(from: item.reactionType)

        return Group {
            if item.reactionType.lowercased() == "tagged" {
                AttachmentIconView(icon: .tagged, preset: .activityReactionBadge, tintColor: .white)
            } else {
                Text(style.icon)
                    .font(.system(size: 14))
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        .padding(6)
        .allowsHitTesting(false)
    }

    private var isVideoMoment: Bool {
        guard let moment = item.moment else { return false }
        if let media = moment.primaryVisibleMediaItem {
            return media.type != .image
        }
        if let video = moment.previewVideoURLString, !video.isEmpty {
            return true
        }
        return false
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
                    .foregroundStyle(.gray)
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

            if overlayBadge == .none {
                ActivityThumbnailVideoPlayIndicator()
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "video")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.gray)
        }
        .frame(width: size, height: size)
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil else { return }
        isGeneratingThumbnail = true

        Task {
            let image = await VideoThumbnailCache.shared.thumbnail(for: videoPath)
            await MainActor.run {
                self.generatedVideoThumbnail = image ?? self.generatedVideoThumbnail
                self.isGeneratingThumbnail = false
            }
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

            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Text(NSLocalizedString("savedMoments.restricted.title", comment: "Saved moment restricted title"))
                    .font(.system(size: legacyPoppinsSize(10), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("savedMoments.restricted.subtitle", comment: "Saved moment restricted subtitle"))
                    .font(.system(size: legacyPoppinsSize(9)))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var discreetAudienceIcon: some View {
        if let moment = item.moment {
            let audience = resolvedAudience(for: moment)
            ActivityGridAudienceIcon(audience: audience)
                .padding(6)
                .accessibilityLabel(audience.title)
        }
    }

    private func resolvedAudience(for moment: Moment) -> ContentAudience {
        let audience = ContentAudience.fromAudienceValue(moment.audience)
        if moment.customListId != nil, audience == .custom {
            return .customList
        }
        return audience
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
            return ("✨", NSLocalizedString("userActivity.simple.reaction.unknown", comment: "Unknown reaction"), Color(hex: "64748B"))
        }

        return ("✨", fallback.capitalized, Color(hex: "64748B"))
    }
}

// MARK: - Tarjeta portrait 9:16 para reels en actividad

struct ActivityPortraitMomentCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let moment: Moment
    @State private var generatedVideoThumbnail: UIImage?
    @State private var isGeneratingThumbnail = false

    private var isVideoMoment: Bool {
        if let media = moment.primaryVisibleMediaItem {
            return media.type != .image
        }
        if let video = moment.previewVideoURLString, !video.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        ScreenshotProtectedView(isProtected: (moment.audience?.lowercased() ?? "") != "everyone") {
            GeometryReader { geometry in
                ZStack {
                    cardPreview
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                    if isVideoMoment {
                        ActivityThumbnailVideoPlayIndicator()
                    }
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipped()
        }
    }

    @ViewBuilder
    private var cardPreview: some View {
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
    }

    @ViewBuilder
    private func mediaVideoPreview(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, !thumb.isEmpty {
                KFImage(URL(string: thumb))
                    .placeholder {
                        Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
                    }
                    .resizable()
                    .scaledToFill()
            } else if let generatedVideoThumbnail {
                Image(uiImage: generatedVideoThumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                videoPlaceholder
                    .onAppear {
                        generateThumbnail(for: videoURL)
                    }
            }
        }
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "video")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.gray)
        }
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil else { return }
        isGeneratingThumbnail = true

        Task {
            let image = await VideoThumbnailCache.shared.thumbnail(for: videoPath)
            await MainActor.run {
                self.generatedVideoThumbnail = image ?? self.generatedVideoThumbnail
                self.isGeneratingThumbnail = false
            }
        }
    }
}

struct ActivityDeletedStoryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityDeletedStoryItem
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
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                if let previewURLString, let url = URL(string: previewURLString) {
                    KFImage(url)
                        .placeholder {
                            placeholder
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    placeholder
                }

                VStack {
                    HStack {
                        HighlightStoryDateBadge(date: item.story.timestamp)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)

                if item.story.mediaItem.type == .video, item.story.duration > 0 {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            Text(HighlightArchiveStoryCardVisual.formatVideoDuration(item.story.duration))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        }
                    }
                    .padding(7)
                }

                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: "2563EB") : .white.opacity(0.92))
                        .padding(8)
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: item.story.mediaItem.type == .video ? "play.rectangle.fill" : "photo")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct ActivityThumbnailVideoPlayIndicator: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
        }
        .padding(6)
        .allowsHitTesting(false)
    }
}
