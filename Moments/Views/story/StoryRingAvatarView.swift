import SwiftUI
import FirebaseAuth

struct StoryRingAvatarView: View {
    let userId: String
    let size: CGFloat
    var lineWidth: CGFloat = 2.5
    var isOwnStory: Bool? = nil
    var allowOwnStories: Bool = true
    var hapticsEnabled: Bool = false
    var showBaseStroke: Bool = false
    var baseStrokeColor: Color = Color.white.opacity(0.2)
    var baseStrokeWidth: CGFloat = 1
    var profileZoomNamespace: Namespace.ID? = nil
    var onTap: ((Bool) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot = StoryRingSnapshot(
        hasStory: false,
        hasUnseenStory: false,
        storyCount: 0,
        storyViewedStatus: [],
        storyAudiences: []
    )

    private let privacyService = PrivacyService()

    private var resolvedIsOwnStory: Bool {
        if let isOwnStory {
            return isOwnStory
        }
        return userId == Auth.auth().currentUser?.uid
    }

    private var avatarContent: some View {
        AsyncProfileImageView(userId: userId)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                StorySegmentedRing(
                    storyCount: snapshot.storyCount,
                    hasStory: snapshot.hasStory,
                    hasUnseenStory: snapshot.hasUnseenStory,
                    storyViewedStatus: snapshot.storyViewedStatus,
                    storyAudiences: snapshot.storyAudiences,
                    isOwnStory: resolvedIsOwnStory,
                    colorScheme: colorScheme,
                    ringSize: size,
                    lineWidth: lineWidth,
                    hapticsEnabled: hapticsEnabled
                )
            )
            .overlay(
                Circle()
                    .stroke(showBaseStroke ? baseStrokeColor : .clear, lineWidth: baseStrokeWidth)
            )
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: { onTap(snapshot.hasStory) }) {
                    avatarContent
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                avatarContent
            }
        }
        .userProfileZoomSource(
            userId: userId,
            namespace: profileZoomNamespace,
            cornerRadius: size / 2
        )
        .onAppear {
            resolveSnapshot()
        }
        .onChange(of: userId) { _, _ in
            resolveSnapshot()
        }
    }

    private func resolveSnapshot() {
        guard !userId.isEmpty else {
            snapshot = StoryRingSnapshot(
                hasStory: false,
                hasUnseenStory: false,
                storyCount: 0,
                storyViewedStatus: [],
                storyAudiences: []
            )
            return
        }

        guard let viewerId = Auth.auth().currentUser?.uid, !viewerId.isEmpty else {
            snapshot = StoryRingSnapshot(
                hasStory: false,
                hasUnseenStory: false,
                storyCount: 0,
                storyViewedStatus: [],
                storyAudiences: []
            )
            return
        }

        if !allowOwnStories, viewerId == userId {
            snapshot = StoryRingSnapshot(
                hasStory: false,
                hasUnseenStory: false,
                storyCount: 0,
                storyViewedStatus: [],
                storyAudiences: []
            )
            return
        }

        StoryRingResolverService.shared.resolve(
            viewerId: viewerId,
            authorId: userId,
            privacyService: privacyService
        ) { resolvedSnapshot in
            self.snapshot = resolvedSnapshot
        }
    }
}
