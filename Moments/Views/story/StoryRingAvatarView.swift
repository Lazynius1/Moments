import SwiftUI
import FirebaseAuth

/// Medidas compartidas del aro de historias (feed header, inbox, perfil, etc.).
enum StoryRingLayout {
    static let feedHeaderAvatarSize: CGFloat = 50
    static let feedHeaderLineWidth: CGFloat = 3.0
    /// Espacio visible entre la foto y el aro (transparente, sin relleno de color).
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

    static func ringGapMask(avatarSize: CGFloat) -> some View {
        StoryRingGapCutoutMask(innerDiameter: avatarSize + ringGap * 2)
            .fill(style: FillStyle(eoFill: true))
    }
}

/// Enmascara el aro para que no pinte dentro del hueco transparente alrededor del avatar.
private struct StoryRingGapCutoutMask: Shape {
    let innerDiameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - innerDiameter / 2,
            y: rect.midY - innerDiameter / 2,
            width: innerDiameter,
            height: innerDiameter
        ))
        return path
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
            .mask(StoryRingLayout.ringGapMask(avatarSize: size))

            AsyncProfileImageView(userId: userId)
                .frame(width: size, height: size)
                .clipShape(Circle())
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

/// Anillo de historias del inbox de grupo: miembros excepto el visor.
/// La privacidad es la de 1:1 (`StoryRingResolverService` / `canUserViewStoryEnhanced`).
struct GroupStoryRingAvatarView: View {
    let memberUserIds: [String]
    let groupName: String
    let groupImage: String
    let size: CGFloat
    var lineWidth: CGFloat? = nil
    var hapticsEnabled: Bool = false
    var onTap: ((_ hasStory: Bool, _ startUserId: String?, _ ringUserIds: [String]) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot = StoryRingSnapshot.empty
    @State private var storyAuthorIds: [String] = []
    @State private var startAuthorId: String?
    @State private var nestedStoryAudiences: [[String?]] = []
    @State private var nestedStoryViewedStatus: [[Bool]] = []
    @State private var resolveGeneration = 0

    private let privacyService = PrivacyService()

    private var resolvedLineWidth: CGFloat {
        lineWidth ?? StoryRingLayout.defaultLineWidth(for: size)
    }

    private var ringStrokeDiameter: CGFloat {
        StoryRingLayout.ringStrokeDiameter(avatarSize: size, lineWidth: resolvedLineWidth)
    }

    private var authorIds: [String] {
        let viewerId = Auth.auth().currentUser?.uid
        return memberUserIds.filter { !$0.isEmpty && $0 != viewerId }
    }

    private var avatarContent: some View {
        ZStack {
            StorySegmentedRing(
                storyCount: snapshot.storyCount,
                hasStory: snapshot.hasStory,
                hasUnseenStory: snapshot.hasUnseenStory,
                storyViewedStatus: snapshot.storyViewedStatus,
                storyAudiences: snapshot.storyAudiences,
                nestedStoryAudiences: nestedStoryAudiences,
                nestedStoryViewedStatus: nestedStoryViewedStatus,
                isOwnStory: false,
                colorScheme: colorScheme,
                ringSize: ringStrokeDiameter,
                lineWidth: resolvedLineWidth,
                hapticsEnabled: hapticsEnabled
            )
            .mask(StoryRingLayout.ringGapMask(avatarSize: size))

            GroupChatAvatar(name: groupName, image: groupImage, size: size)
        }
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: {
                    onTap(snapshot.hasStory, startAuthorId, storyAuthorIds)
                }) {
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
        .onAppear { resolveSnapshots() }
        .onChange(of: memberUserIds) { _, _ in
            resolveSnapshots()
        }
    }

    private func resolveSnapshots() {
        let viewerId = Auth.auth().currentUser?.uid
        let authors = authorIds
        resolveGeneration += 1
        let generation = resolveGeneration

        guard let viewerId, !viewerId.isEmpty, !authors.isEmpty else {
            applyAggregation(authors: [], snapshots: [:])
            return
        }

        var collected: [String: StoryRingSnapshot] = [:]
        let group = DispatchGroup()
        let lock = NSLock()

        for authorId in authors {
            group.enter()
            StoryRingResolverService.shared.resolve(
                viewerId: viewerId,
                authorId: authorId,
                privacyService: privacyService,
                useCache: true
            ) { resolved in
                lock.lock()
                collected[authorId] = resolved
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard generation == resolveGeneration else { return }
            applyAggregation(authors: authors, snapshots: collected)
        }
    }

    private func applyAggregation(authors: [String], snapshots: [String: StoryRingSnapshot]) {
        let withStories = authors.compactMap { id -> (String, StoryRingSnapshot)? in
            guard let snap = snapshots[id], snap.hasStory else { return nil }
            return (id, snap)
        }
        storyAuthorIds = withStories.map(\.0)
        startAuthorId = withStories.first(where: { $0.1.hasUnseenStory })?.0 ?? withStories.first?.0

        snapshot = StoryRingSnapshot(
            hasStory: !withStories.isEmpty,
            hasUnseenStory: withStories.contains { $0.1.hasUnseenStory },
            storyCount: withStories.count,
            storyViewedStatus: withStories.map { !$0.1.hasUnseenStory },
            storyAudiences: withStories.map(\.1.groupRingAudience)
        )
        nestedStoryAudiences = withStories.map(\.1.storyAudiences)
        nestedStoryViewedStatus = withStories.map(\.1.storyViewedStatus)
    }
}
