import SwiftUI
import Kingfisher

func sharedMomentStoryCardSize(aspectRatio: String?, image: UIImage?) -> CGSize {
    let width: CGFloat = 260
    let ratio: CGFloat = {
        if let aspectRatio {
            let components = aspectRatio.split(separator: ":")
            if components.count == 2,
               let sourceWidth = Double(components[0]),
               let sourceHeight = Double(components[1]),
               sourceWidth > 0 {
                return CGFloat(sourceHeight / sourceWidth)
            }
        }
        if let image, image.size.width > 0 {
            return image.size.height / image.size.width
        }
        return 340 / width
    }()
    return CGSize(width: width, height: width * min(max(ratio, 0.5), 1.8))
}

struct SharedMomentStorySnapshotView: View {
    let image: UIImage?
    let size: CGSize

    var body: some View {
        ZStack {
            Color(white: 0.1)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Fuente visual única para un Moment compartido dentro de una historia.
/// El editor y el visor deben escalar esta vista completa; sus métricas internas
/// siempre permanecen en el tamaño natural de la imagen base.
struct SharedMomentStoryCardView: View {
    let image: UIImage
    let videoURL: URL?
    let username: String
    let userId: String?
    let profileImagePath: String?
    let sharedMediaPath: String?
    let caption: String?
    let mediaCount: Int
    let styleVariant: Int
    let cardLayoutVariant: Int

    var body: some View {
        ZStack(alignment: .top) {
            SharedMomentStoryMediaView(
                image: image,
                videoURL: videoURL,
                sharedMediaPath: sharedMediaPath
            )
                .clipShape(cardShape)

            if layoutVariant == 0 {
                SharedMomentStoryExpandedChrome(
                    username: username,
                    userId: userId,
                    profileImagePath: profileImagePath,
                    caption: caption,
                    paletteVariant: paletteVariant
                )
                .clipShape(cardShape)
            } else if isReelFullScreen {
                SharedMomentStoryReelFullscreenChrome(
                    username: username,
                    caption: caption,
                    paletteVariant: paletteVariant
                )
            } else {
                SharedMomentStoryPostByline(
                    username: username,
                    paletteVariant: paletteVariant
                )
            }

            if mediaCount > 1 {
                VStack {
                    HStack {
                        Spacer()
                        MomentCarouselIndicatorIcon(size: 18)
                            .padding(5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.trailing, 12)
                            .padding(.top, layoutVariant == 0 ? 52 : 12)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: image.size.width, height: image.size.height)
        .background {
            cardShape.fill(Color(white: 0.1))
        }
        .overlay {
            cardShape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0.4), .white.opacity(0.05), .white.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isReelFullScreen ? 0 : 1.2
            )
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isReelFullScreen ? 0 : FeedMomentCardLayout.mediaCornerRadius,
            style: .continuous
        )
    }

    private var layoutVariant: Int { cardLayoutVariant % 2 }
    private var paletteVariant: Int { styleVariant % 6 }
    private var isReelFullScreen: Bool {
        videoURL != nil && mediaCount == 1 && layoutVariant == 1
    }
}

private struct SharedMomentStoryExpandedChrome: View {
    let username: String
    let userId: String?
    let profileImagePath: String?
    let caption: String?
    let paletteVariant: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            SharedMomentStoryHeaderView(
                username: username,
                userId: userId,
                profileImagePath: profileImagePath,
                paletteVariant: paletteVariant
            )

            Spacer(minLength: 0)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(
                        momentsCardStickerTextColor(
                            styleVariant: paletteVariant,
                            colorScheme: colorScheme
                        )
                    )
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        momentsCardStickerBackgroundGradient(
                            styleVariant: paletteVariant,
                            colorScheme: colorScheme
                        )
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct SharedMomentStoryReelFullscreenChrome: View {
    let username: String
    let caption: String?
    let paletteVariant: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.62)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    AnimatedMomentsCardStickerSurface(
                        styleVariant: paletteVariant,
                        colorScheme: colorScheme
                    )
                    .opacity(paletteVariant == 0 ? 0.08 : 0.18)
                }
                .frame(height: 112)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }

            VStack(spacing: 7) {
                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)
                    SharedMomentStoryFullscreenUsernameText(username: username)
                }

                if let caption,
                   !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SharedMomentStoryFullscreenCaptionPill(
                        caption: caption,
                        paletteVariant: paletteVariant
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SharedMomentStoryFullscreenUsernameText: View {
    let username: String

    var body: some View {
        Text(username.hasPrefix("@") ? username : "@\(username)")
            .font(.system(size: legacyPoppinsSize(11), weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
    }
}

private struct SharedMomentStoryFullscreenCaptionPill: View {
    let caption: String
    let paletteVariant: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(caption)
            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
            .foregroundStyle(
                momentsCardStickerTextColor(
                    styleVariant: paletteVariant,
                    colorScheme: colorScheme
                )
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                AnimatedMomentsCardStickerSurface(
                    styleVariant: paletteVariant,
                    colorScheme: colorScheme
                )
                .clipShape(Capsule())
            }
            .overlay {
                Capsule().stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .frame(maxWidth: 220)
            .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
    }
}

private struct SharedMomentStoryPostByline: View {
    let username: String
    let paletteVariant: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(displayUsername)
            .font(.system(size: legacyPoppinsSize(12), weight: .bold))
            .foregroundStyle(
                momentsCardStickerTextColor(
                    styleVariant: paletteVariant,
                    colorScheme: colorScheme
                )
            )
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                AnimatedMomentsCardStickerSurface(
                    styleVariant: paletteVariant,
                    colorScheme: colorScheme
                )
                .clipShape(Capsule())
            }
            .overlay {
                Capsule().stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
            .offset(y: -17)
    }

    private var displayUsername: String {
        username.hasPrefix("@") ? username : "@\(username)"
    }
}

private struct SharedMomentStoryMediaView: View {
    let image: UIImage
    let videoURL: URL?
    let sharedMediaPath: String?

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: image.size.width, height: image.size.height)
                .clipped()

            if videoURL == nil,
               let sharedMediaPath,
               !sharedMediaPath.isEmpty,
               let mediaURL = URL(string: sharedMediaPath) {
                KFImage(mediaURL)
                    .placeholder {
                        Color.clear
                    }
                    .cancelOnDisappear(true)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: image.size.width, height: image.size.height)
                    .clipped()
            }

            if let videoURL {
                StickerVideoPlayer(url: videoURL, isMuted: false)
                    .frame(width: image.size.width, height: image.size.height)
                    .clipped()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct SharedMomentStoryHeaderView: View {
    let username: String
    let userId: String?
    let profileImagePath: String?
    let paletteVariant: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            SharedMomentStoryAvatarView(
                userId: userId,
                profileImagePath: profileImagePath
            )
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }

            Text(username)
                .font(.system(size: legacyPoppinsSize(13), weight: .bold))
                .foregroundStyle(
                    momentsCardStickerTextColor(
                        styleVariant: paletteVariant,
                        colorScheme: colorScheme
                    )
                )
                .lineLimit(1)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            AnimatedMomentsCardStickerSurface(
                styleVariant: paletteVariant,
                colorScheme: colorScheme
            )
                .opacity(paletteVariant == 0 ? 0.82 : 0.92)
                .mask {
                    LinearGradient(
                        colors: [.black, .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
    }
}

private struct SharedMomentStoryAvatarView: View {
    let userId: String?
    let profileImagePath: String?

    var body: some View {
        if let userId, !userId.isEmpty {
            AsyncProfileImageView(userId: userId)
        } else if let profileImagePath,
           !profileImagePath.isEmpty,
           let url = URL(string: profileImagePath) {
            KFImage(url)
                .placeholder { avatarPlaceholder }
                .cancelOnDisappear(true)
                .resizable()
                .scaledToFill()
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.white.opacity(0.14))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
}
