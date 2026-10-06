import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Combine

/// Avatares: uno grande o dos solapados en horizontal (atrás izquierda, delante derecha).
struct NotificationLeadingAvatarView: View {
    let senderIds: [String]
    let colorScheme: ColorScheme
    let onPrimaryTap: () -> Void
    let onSecondaryTap: (() -> Void)?

    private var ringStrokeColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    var body: some View {
        Group {
             if senderIds.count > 1,
                let frontId = senderIds.first,
                let backId = senderIds.dropFirst().first {
                HStack(spacing: -NotificationRowMetrics.stackedOverlap) {
                    AsyncProfileImageView(userId: backId)
                        .frame(width: NotificationRowMetrics.stackedAvatarSize, height: NotificationRowMetrics.stackedAvatarSize)
                        .clipShape(Circle())
                        .zIndex(0)
                        .reversedMask(alignment: .center) {
                            Circle()
                                .frame(width: NotificationRowMetrics.stackedAvatarSize + 3, height: NotificationRowMetrics.stackedAvatarSize + 3)
                                .offset(x: NotificationRowMetrics.stackedAvatarSize - NotificationRowMetrics.stackedOverlap)
                        }
                        .onTapGesture { onSecondaryTap?() }

                    AsyncProfileImageView(userId: frontId)
                        .frame(width: NotificationRowMetrics.stackedAvatarSize, height: NotificationRowMetrics.stackedAvatarSize)
                        .clipShape(Circle())
                        .zIndex(1)
                        .onTapGesture { onPrimaryTap() }
                }
                .frame(width: NotificationRowMetrics.stackedRowWidth, height: NotificationRowMetrics.stackedAvatarSize)
            } else if let userId = senderIds.first {
                Button(action: onPrimaryTap) {
                    avatarCircle(userId: userId, size: NotificationRowMetrics.avatarSize)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func avatarCircle(userId: String, size: CGFloat = NotificationRowMetrics.stackedAvatarSize) -> some View {
        AsyncProfileImageView(userId: userId)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(ringStrokeColor, lineWidth: 2))
    }
}

/// Miniatura vertical de historia.
struct NotificationStoryThumbnailView: View {
    let imagePath: String?
    var story: Story? = nil
    let reaction: String?
    let colorScheme: ColorScheme
    let loadFailed: Bool
    var isChain = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let story {
                    StoryStaticPreviewSurface(story: story)
                } else if let path = imagePath, let url = URL(string: path), !loadFailed {
                    KFImage(url)
                        .placeholder { thumbnailPlaceholder }
                        .resizable()
                        .scaledToFill()
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(
                width: NotificationRowMetrics.storyThumbnailWidth,
                height: NotificationRowMetrics.storyThumbnailHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: NotificationRowMetrics.storyThumbnailCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NotificationRowMetrics.storyThumbnailCornerRadius, style: .continuous)
                    .stroke(thumbnailBorder, lineWidth: isChain ? 2 : 0.5)
            )
            .reversedMask(alignment: .bottomTrailing) {
                if isChain {
                    Circle()
                        .frame(width: 22, height: 22)
                        .offset(x: 4, y: 4)
                }
            }

            if isChain {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }

            if let reaction, !reaction.isEmpty {
                Text(reaction)
                    .font(.system(size: 15))
                    .padding(3)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var thumbnailBorder: AnyShapeStyle {
        if isChain {
            AnyShapeStyle(LinearGradient(
                colors: [Color.blue.opacity(0.85), Color.purple.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        } else {
            AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: NotificationRowMetrics.storyThumbnailCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
            )
    }
}
