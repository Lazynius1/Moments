import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import Combine

/// Avatares estilo Instagram: uno grande o dos solapados en horizontal (atrás izquierda, delante derecha).
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
                    avatarCircle(userId: backId)
                        .zIndex(0)
                        .onTapGesture { onSecondaryTap?() }

                    avatarCircle(userId: frontId)
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

/// Miniatura vertical de historia (estilo Instagram).
struct NotificationStoryThumbnailView: View {
    let imagePath: String?
    let reaction: String?
    let colorScheme: ColorScheme
    let loadFailed: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let path = imagePath, let url = URL(string: path), !loadFailed {
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
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1), lineWidth: 0.5)
            )

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

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: NotificationRowMetrics.storyThumbnailCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
            )
    }
}
