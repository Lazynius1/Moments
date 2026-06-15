import SwiftUI
import FirebaseAuth

private enum StoryRingAvatarMetrics {
    /// Referencia visual del carrusel de historias del feed.
    static let feedHeaderAvatarSize: CGFloat = 50
    static let feedHeaderLineWidth: CGFloat = 3.0

    static func defaultLineWidth(for size: CGFloat) -> CGFloat {
        max(2.8, size * (feedHeaderLineWidth / feedHeaderAvatarSize))
    }

    static func outerFrameSize(avatarSize: CGFloat, lineWidth: CGFloat) -> CGFloat {
        avatarSize + lineWidth + 4
    }
}

struct StoryRingAvatarView: View {
    let userId: String
    let size: CGFloat
    /// `nil` → grosor proporcional al header del feed (50pt / 3pt).
    var lineWidth: CGFloat? = nil
    var refreshTrigger: Int = 0
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

    private var resolvedLineWidth: CGFloat {
        lineWidth ?? StoryRingAvatarMetrics.defaultLineWidth(for: size)
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
                    lineWidth: resolvedLineWidth,
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
        .frame(
            width: StoryRingAvatarMetrics.outerFrameSize(avatarSize: size, lineWidth: resolvedLineWidth),
            height: StoryRingAvatarMetrics.outerFrameSize(avatarSize: size, lineWidth: resolvedLineWidth)
        )
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
        .onChange(of: refreshTrigger) { _, _ in
            resolveSnapshot(forceRefresh: true)
        }
    }

    private func resolveSnapshot(forceRefresh: Bool = false) {
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

        let resolve = {
            StoryRingResolverService.shared.resolve(
                viewerId: viewerId,
                authorId: userId,
                privacyService: privacyService,
                useCache: !forceRefresh
            ) { resolvedSnapshot in
                self.snapshot = resolvedSnapshot
            }
        }

        guard forceRefresh else {
            resolve()
            return
        }

        Task {
            await StoryRingCacheService.shared.invalidate(viewerId: viewerId, authorId: userId)
            await MainActor.run {
                resolve()
            }
        }
    }
}
