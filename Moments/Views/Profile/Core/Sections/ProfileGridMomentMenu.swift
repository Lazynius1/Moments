import SwiftUI
import Kingfisher
import AVFoundation

// MARK: - Selection

struct ProfileGridMomentMenuSelection: Equatable {
    let moment: Moment
    let index: Int
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

private let profileGridHeroTopBleed: CGFloat = 22
private let profileGridHeroCapsuleHeight: CGFloat = 60
private let profileGridHeroCapsuleLeadingPadding: CGFloat = 6
private let profileGridHeroCapsuleTrailingPadding: CGFloat = 12
private let profileGridHeroAvatarSize: CGFloat = 34
private let profileGridHeroCapsuleContentYOffset: CGFloat = 4

// MARK: - Hero card

struct ProfileGridHeroCard: View {
    let moment: Moment
    let width: CGFloat
    let onOpenMoment: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.profileHeroShowsChrome) private var showsChrome

    private var mediaHeight: CGFloat {
        ProfileGridHeroLayout.mediaHeight(width: width, aspectRatio: moment.aspectRatio)
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
        ZStack(alignment: .top) {
            heroMedia
                .frame(width: width, height: mediaHeight + profileGridHeroTopBleed)
                .offset(y: -profileGridHeroTopBleed * 0.72)

            if showsChrome {
                LinearGradient(
                    colors: [
                        .black.opacity(colorScheme == .dark ? 0.38 : 0.24),
                        .black.opacity(0.1),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.42)
                )

                heroTopGlassExtension
            }
        }
        .frame(width: width, height: mediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: ProfileGridHeroLayout.peekCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ProfileGridHeroLayout.peekCornerRadius, style: .continuous))
        .onTapGesture(perform: onOpenMoment)
        .overlay(alignment: .topTrailing) {
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
                .padding(.top, profileGridHeroCapsuleHeight + 6)
                .padding(.trailing, profileGridHeroCapsuleTrailingPadding)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 16, x: 0, y: 8)
    }

    private var heroCapsuleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: ProfileGridHeroLayout.peekCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: ProfileGridHeroLayout.peekCornerRadius,
            style: .continuous
        )
    }

    private var heroTopGlassExtension: some View {
        HStack(alignment: .center, spacing: 10) {
            AsyncProfileImageView(userId: moment.authorId)
                .frame(width: profileGridHeroAvatarSize, height: profileGridHeroAvatarSize)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                    Text(moment.username)
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                        .lineLimit(1)

                if let locationText {
                    Text(locationText)
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.82))
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            ActivityGridAudienceIcon(audience: resolvedAudience)
                .scaleEffect(1.14)
                .accessibilityLabel(resolvedAudience.title)
        }
        .padding(.leading, profileGridHeroCapsuleLeadingPadding)
        .padding(.trailing, profileGridHeroCapsuleTrailingPadding)
        .offset(y: profileGridHeroCapsuleContentYOffset)
        .frame(height: profileGridHeroCapsuleHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            heroCapsuleShape
                .fill(Color.black.opacity(0.22))
        }
        .liquidGlass(in: heroCapsuleShape)
    }

    private var heroVideoAspectRatio: CGFloat {
        let ratio = ProfileGridHeroLayout.parsedAspectRatio(moment.aspectRatio)
        return max(ratio, 0.55)
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
                .font(.custom("Poppins-Regular", size: 14))
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

