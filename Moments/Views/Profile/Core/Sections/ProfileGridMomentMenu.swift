import SwiftUI
import Kingfisher
import AVFoundation
import FirebaseAuth

// MARK: - Selection

struct ProfileGridMomentMenuSelection: Equatable {
    let moment: Moment
    let index: Int
}

enum ProfileGridHeroMenuKind: Equatable {
    case owner
    case visitor
}

// MARK: - Tap / long-press (UIKit — tap.require(toFail: longPress))

struct ProfileMomentThumbnailGestureOverlay: UIViewRepresentable {
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    let onPressingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onLongPress: onLongPress,
            onPressingChanged: onPressingChanged
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = GestureHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.coordinator = context.coordinator
        view.installGestures()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let host = uiView as? GestureHostView else { return }
        host.coordinator = context.coordinator
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onPressingChanged = onPressingChanged
    }

    final class GestureHostView: UIView {
        weak var coordinator: Coordinator?
        private var installed = false

        func installGestures() {
            guard !installed, let coordinator else { return }
            installed = true
            gestureRecognizers?.forEach { removeGestureRecognizer($0) }

            let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))

            if coordinator.onLongPress != nil {
                let longPress = UILongPressGestureRecognizer(
                    target: coordinator,
                    action: #selector(Coordinator.handleLongPress(_:))
                )
                longPress.minimumPressDuration = 0.42
                longPress.allowableMovement = 10
                tap.require(toFail: longPress)
                addGestureRecognizer(longPress)
            }

            addGestureRecognizer(tap)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installGestures()
        }
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onLongPress: (() -> Void)?
        var onPressingChanged: (Bool) -> Void
        private var didTriggerLongPress = false

        init(
            onTap: @escaping () -> Void,
            onLongPress: (() -> Void)?,
            onPressingChanged: @escaping (Bool) -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onPressingChanged = onPressingChanged
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onPressingChanged(true)
                guard !didTriggerLongPress else { return }
                didTriggerLongPress = true
                HapticManager.shared.mediumImpact()
                onLongPress?()
            case .ended, .cancelled, .failed:
                onPressingChanged(false)
                didTriggerLongPress = false
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onPressingChanged(false)
            onTap()
        }
    }
}

// MARK: - Hero sizing

private let profileGridHeroFooterAvatarSize: CGFloat = 36
private let profileGridHeroFooterHorizontalPadding: CGFloat = 12

// MARK: - Hero card

struct ProfileGridHeroCard: View {
    let moment: Moment
    let width: CGFloat
    let onOpenMoment: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.profileHeroShowsChrome) private var showsChrome
    @Environment(\.profileHeroChromeOpacity) private var profileHeroChromeOpacity
    @Environment(\.profileHeroShowsAudience) private var showsAudience

    private var mediaHeight: CGFloat {
        ProfileGridHeroLayout.mediaHeight(width: width, aspectRatio: moment.aspectRatio)
    }

    private var totalCardHeight: CGFloat {
        mediaHeight + (showsChrome ? ProfileGridHeroLayout.peekFooterHeight : 0)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var locationText: String? {
        let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let location, !location.isEmpty else { return nil }
        return location
    }

    private var resolvedAudience: ContentAudience {
        let audience = ContentAudience.fromAudienceValue(moment.audience)
        if moment.customListId != nil, audience == .custom {
            return .customList
        }
        return audience
    }

    var body: some View {
        VStack(spacing: 0) {
            heroMediaSection
            if showsChrome {
                heroFooterBar
                    .opacity(profileHeroChromeOpacity)
            }
        }
        .frame(width: width, height: totalCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: ProfileGridHeroLayout.peekCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ProfileGridHeroLayout.peekCornerRadius, style: .continuous))
        .onTapGesture(perform: onOpenMoment)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 16, x: 0, y: 8)
    }

    private var heroMediaSection: some View {
        heroMedia
            .frame(width: width, height: mediaHeight)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(colorScheme == .dark ? 0.18 : 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(mediaHeight * 0.12, 36))
            }
            .overlay(alignment: .topTrailing) {
                videoDurationBadge
            }
    }

    @ViewBuilder
    private var videoDurationBadge: some View {
        if moment.primaryVisibleMediaItem?.type == .video {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                LiveVideoTimeLabel(
                    consumerId: GlobalVideoManager.profileVideoConsumerId(for: moment),
                    totalDuration: moment.primaryVisibleMediaItem?.videoDuration ?? moment.videoDuration,
                    displayMode: .inline
                )
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
    }

    private var heroFooterBar: some View {
        HStack(alignment: .center, spacing: 10) {
            AsyncProfileImageView(userId: moment.authorId)
                .frame(width: profileGridHeroFooterAvatarSize, height: profileGridHeroFooterAvatarSize)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(moment.username)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                if let locationText {
                    Text(locationText)
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if showsAudience {
                AudienceIconView(
                    audience: resolvedAudience,
                    size: AudienceIconMetrics.activityGridThumbnail,
                    colorScheme: colorScheme
                )
                .accessibilityLabel(resolvedAudience.title)
            }
        }
        .padding(.horizontal, profileGridHeroFooterHorizontalPadding)
        .frame(height: ProfileGridHeroLayout.peekFooterHeight)
        .frame(maxWidth: .infinity)
        .background(heroFooterBackground)
    }

    private var heroFooterBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var heroVideoAspectRatio: CGFloat {
        ProfileGridHeroLayout.clampedPeekWidthOverHeight(moment.aspectRatio)
    }

    @ViewBuilder
    private var heroMedia: some View {
        if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
            if mediaItem.type == .video {
                if !mediaItem.url.isEmpty {
                    ModernVideoPlayer(
                        url: mediaItem.url,
                        aspectRatio: heroVideoAspectRatio,
                        videoId: GlobalVideoManager.profileVideoConsumerId(for: moment),
                        hideMuteButton: true,
                        chromeStyle: .socialReels,
                        allowsPauseInteraction: false,
                        posterURLString: moment.videoPosterURLString(for: mediaItem),
                        mediaItem: mediaItem,
                        moment: moment,
                        activationMode: .alwaysWhenVisible,
                        consumesDetailHandoff: false
                    )
                    .allowsHitTesting(false)
                } else if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty, let url = imageURL(thumbnailUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    videoPlaceholder
                }
            } else if let url = imageURL(mediaItem.url) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                textFallback
            }
        } else if let imagePath = moment.imagePath, let url = imageURL(imagePath) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            textFallback
        }
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.08)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private var textFallback: some View {
        ZStack {
            Color.black.opacity(0.06)
            Text(moment.content)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(20)
                .lineLimit(6)
        }
    }

    private func imageURL(_ path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let base = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(base)\(encoded)?alt=media")
    }
}

// MARK: - Visitor action bar (perfil ajeno)

struct ProfileGridVisitorActionBar: View {
    let moment: Moment
    let canShare: Bool
    let onComment: () -> Void
    let onShare: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var firestoreService: FirestoreService
    @StateObject private var usageTracker: UserReactionUsageTracker

    init(
        moment: Moment,
        canShare: Bool,
        onComment: @escaping () -> Void,
        onShare: @escaping () -> Void
    ) {
        self.moment = moment
        self.canShare = canShare
        self.onComment = onComment
        self.onShare = onShare
        let userId = Auth.auth().currentUser?.uid ?? ""
        _usageTracker = StateObject(wrappedValue: UserReactionUsageTracker(userId: userId))
    }

    private var primaryColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var mutedColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.28)
    }

    var body: some View {
        HStack(spacing: 10) {
            reactionRail

            if !moment.disableComments {
                visitorIconButton(
                    systemName: "bubble.left",
                    tint: primaryColor,
                    accessibilityLabel: NSLocalizedString("comments.title", comment: "Comments"),
                    action: onComment
                )
            }

            visitorIconButton(
                systemName: "paperplane",
                tint: canShare ? primaryColor : mutedColor,
                accessibilityLabel: NSLocalizedString("contextMenu.shareMoment", comment: "Share moment"),
                isEnabled: canShare,
                action: onShare
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reactionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(usageTracker.getReactionsOrderedByUsage(), id: \.rawValue) { reaction in
                    Button {
                        HapticManager.shared.lightImpact()
                        usageTracker.incrementUsage(for: reaction)
                        submitReaction(reaction)
                    } label: {
                        Text(reaction.icon)
                            .font(.system(size: 22))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func visitorIconButton(
        systemName: String,
        tint: Color,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPress(scale: 0.9, haptic: .light))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func submitReaction(_ reaction: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }

        firestoreService.addReaction(
            to: momentId,
            reaction: reaction.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { _ in }
    }
}

