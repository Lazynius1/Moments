import SwiftUI
import FirebaseAuth

/// Medidas compartidas del aro de historias (feed header, inbox, perfil, etc.).
enum StoryRingLayout {
    static let feedHeaderAvatarSize: CGFloat = 50
    static let feedHeaderLineWidth: CGFloat = 3.0
    /// Espacio visible entre la foto y el aro (estilo Instagram).
    static let ringGap: CGFloat = 1.5

    static func defaultLineWidth(for size: CGFloat) -> CGFloat {
        max(2.8, size * (feedHeaderLineWidth / feedHeaderAvatarSize))
    }

    static func ringStrokeDiameter(avatarSize: CGFloat, lineWidth: CGFloat) -> CGFloat {
        avatarSize + ringGap * 2 + lineWidth
    }

    static func outerFrameSize(avatarSize: CGFloat, lineWidth: CGFloat) -> CGFloat {
        ringStrokeDiameter(avatarSize: avatarSize, lineWidth: lineWidth) + lineWidth + 2
    }

    static func gapSeparatorColor(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.06) : .white
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
        lineWidth ?? StoryRingLayout.defaultLineWidth(for: size)
    }

    private var ringStrokeDiameter: CGFloat {
        StoryRingLayout.ringStrokeDiameter(avatarSize: size, lineWidth: resolvedLineWidth)
    }

    private var avatarContent: some View {
        ZStack {
            StorySegmentedRing(
                storyCount: snapshot.storyCount,
                hasStory: snapshot.hasStory,
                hasUnseenStory: snapshot.hasUnseenStory,
                storyViewedStatus: snapshot.storyViewedStatus,
                storyAudiences: snapshot.storyAudiences,
                isOwnStory: resolvedIsOwnStory,
                colorScheme: colorScheme,
                ringSize: ringStrokeDiameter,
                lineWidth: resolvedLineWidth,
                hapticsEnabled: hapticsEnabled
            )

            AsyncProfileImageView(userId: userId)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            StoryRingLayout.gapSeparatorColor(colorScheme),
                            lineWidth: StoryRingLayout.ringGap * 2
                        )
                )
                .overlay(
                    Circle()
                        .stroke(showBaseStroke ? baseStrokeColor : .clear, lineWidth: baseStrokeWidth)
                )
        }
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
            width: StoryRingLayout.outerFrameSize(avatarSize: size, lineWidth: resolvedLineWidth),
            height: StoryRingLayout.outerFrameSize(avatarSize: size, lineWidth: resolvedLineWidth)
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
