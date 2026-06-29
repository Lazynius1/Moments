import SwiftUI
import FirebaseAuth

/// Placeholder del anillo del feed con las mismas medidas que `RealStoryCircle` / `YourStoryCircleWithProgress`.
struct StoryRingTraySkeletonCell: View {
    let isOwnStory: Bool
    let colorScheme: ColorScheme
    /// Si hay `userId`, muestra el avatar real atenuado bajo el shimmer (refresh con caché).
    var userId: String? = nil

    @State private var isAnimating = false

    private let avatarSize = StoryRingLayout.feedHeaderAvatarSize
    private let ringLineWidth = StoryRingLayout.feedHeaderLineWidth
    private let cellWidth: CGFloat = 64

    private var outerSize: CGFloat {
        StoryRingLayout.outerFrameSize(avatarSize: avatarSize, lineWidth: ringLineWidth)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                ringOverlay

                avatarPlaceholder
                    .shimmer(isAnimating: isAnimating)
            }
            .frame(width: outerSize, height: outerSize)

            labelPlaceholder
                .shimmer(isAnimating: isAnimating)
        }
        .frame(width: cellWidth)
        .accessibilityLabel(
            Text(NSLocalizedString("feed.storyRing.loading", value: "Cargando historias", comment: "Story ring loading accessibility"))
        )
        .onAppear { isAnimating = true }
    }

    @ViewBuilder
    private var avatarPlaceholder: some View {
        if let userId, !userId.isEmpty {
            AsyncProfileImageView(userId: userId)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .opacity(0.4)
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: avatarSize, height: avatarSize)
        }
    }

    private var ringOverlay: some View {
        StorySegmentedRing(
            storyCount: isOwnStory ? 0 : 1,
            hasStory: !isOwnStory,
            hasUnseenStory: !isOwnStory,
            storyViewedStatus: isOwnStory ? [] : [false],
            storyAudiences: [],
            isOwnStory: isOwnStory,
            colorScheme: colorScheme,
            ringSize: StoryRingLayout.ringStrokeDiameter(
                avatarSize: avatarSize,
                lineWidth: ringLineWidth
            ),
            lineWidth: ringLineWidth,
            hapticsEnabled: false
        )
        .mask(StoryRingLayout.ringGapMask(avatarSize: avatarSize))
        .opacity(isOwnStory ? 1 : 0.55)
        .allowsHitTesting(false)
    }

    private var labelPlaceholder: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: isOwnStory ? 52 : 44, height: 10)
    }
}

/// Fila inicial de carga del tray (tu círculo + N vecinos).
struct StoryRingTraySkeletonRow: View {
    let colorScheme: ColorScheme
    var placeholderCount: Int = 6

    var body: some View {
        HStack(spacing: 10) {
            StoryRingTraySkeletonCell(
                isOwnStory: true,
                colorScheme: colorScheme,
                userId: Auth.auth().currentUser?.uid
            )

            ForEach(0..<max(placeholderCount - 1, 0), id: \.self) { _ in
                StoryRingTraySkeletonCell(isOwnStory: false, colorScheme: colorScheme)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
    }
}

/// Cola del scroll mientras llega la siguiente página del anillo.
struct StoryRingTrayLoadingTail: View {
    let colorScheme: ColorScheme
    var count: Int = 3

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            StoryRingTraySkeletonCell(isOwnStory: false, colorScheme: colorScheme)
        }
    }
}
