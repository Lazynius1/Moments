import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

/// Renderiza foto + StorySegmentedRing a UIImage para el segmento Perfil.
enum FloatingTabProfileSegmentRenderer {
    static let canvasSize: CGFloat = 42
    static let avatarSize: CGFloat = 30
    static let lineWidth: CGFloat = 2.2

    @MainActor
    static func render(
        userId: String,
        colorScheme: ColorScheme,
        forceRefresh: Bool = false
    ) async -> UIImage {
        guard !userId.isEmpty else {
            return personPlaceholder(colorScheme: colorScheme)
        }

        async let avatarTask = loadAvatar(userId: userId)
        async let snapshotTask = loadSnapshot(userId: userId, forceRefresh: forceRefresh)
        let (avatar, snapshot) = await (avatarTask, snapshotTask)

        return compose(avatar: avatar, snapshot: snapshot, colorScheme: colorScheme)
    }

    private static func loadAvatar(userId: String) async -> UIImage? {
        let path: String? = await withCheckedContinuation { cont in
            Firestore.firestore().collection("users").document(userId).getDocument { doc, _ in
                let value = doc?.data()?["profileImagePath"] as? String
                cont.resume(returning: value)
            }
        }
        guard let path, !path.isEmpty, let url = URL(string: path) else { return nil }

        return await withCheckedContinuation { cont in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let value):
                    cont.resume(returning: value.image)
                case .failure:
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private static func loadSnapshot(userId: String, forceRefresh: Bool) async -> StoryRingSnapshot {
        if forceRefresh {
            await StoryRingCacheService.shared.invalidate(viewerId: userId, authorId: userId)
        }
        let privacy = PrivacyService()
        return await withCheckedContinuation { cont in
            StoryRingResolverService.shared.resolve(
                viewerId: userId,
                authorId: userId,
                privacyService: privacy,
                useCache: !forceRefresh
            ) { snapshot in
                cont.resume(returning: snapshot)
            }
        }
    }

    @MainActor
    private static func compose(
        avatar: UIImage?,
        snapshot: StoryRingSnapshot,
        colorScheme: ColorScheme
    ) -> UIImage {
        let content = FloatingTabProfileSegmentIcon(
            avatar: avatar,
            snapshot: snapshot,
            colorScheme: colorScheme
        )
        .frame(width: canvasSize, height: canvasSize)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        let rendered = renderer.uiImage ?? personPlaceholder(colorScheme: colorScheme)
        return rendered.withRenderingMode(.alwaysOriginal)
    }

    static func personPlaceholder(colorScheme: ColorScheme) -> UIImage {
        let config = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 23, weight: .medium))
        let base = UIImage(systemName: "person.fill", withConfiguration: config) ?? UIImage()
        let color = colorScheme == .dark ? UIColor.white : UIColor(Color(hex: "0B1215"))
        return base.withTintColor(color, renderingMode: .alwaysOriginal)
    }
}

private struct FloatingTabProfileSegmentIcon: View {
    let avatar: UIImage?
    let snapshot: StoryRingSnapshot
    let colorScheme: ColorScheme

    private var ringStrokeDiameter: CGFloat {
        StoryRingLayout.ringStrokeDiameter(
            avatarSize: FloatingTabProfileSegmentRenderer.avatarSize,
            lineWidth: FloatingTabProfileSegmentRenderer.lineWidth
        )
    }

    var body: some View {
        ZStack {
            StorySegmentedRing(
                storyCount: snapshot.storyCount,
                hasStory: snapshot.hasStory,
                hasUnseenStory: snapshot.hasUnseenStory,
                storyViewedStatus: snapshot.storyViewedStatus,
                storyAudiences: snapshot.storyAudiences,
                isOwnStory: true,
                colorScheme: colorScheme,
                ringSize: ringStrokeDiameter,
                lineWidth: FloatingTabProfileSegmentRenderer.lineWidth,
                hapticsEnabled: false
            )
            .mask(
                StoryRingLayout.ringGapMask(
                    avatarSize: FloatingTabProfileSegmentRenderer.avatarSize
                )
            )

            Group {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.25))
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(
                                colorScheme == .dark ? Color.white : Color(hex: "0B1215")
                            )
                    }
                }
            }
            .frame(
                width: FloatingTabProfileSegmentRenderer.avatarSize,
                height: FloatingTabProfileSegmentRenderer.avatarSize
            )
            .clipShape(Circle())
        }
        .frame(
            width: StoryRingLayout.outerFrameSize(
                avatarSize: FloatingTabProfileSegmentRenderer.avatarSize,
                lineWidth: FloatingTabProfileSegmentRenderer.lineWidth
            ),
            height: StoryRingLayout.outerFrameSize(
                avatarSize: FloatingTabProfileSegmentRenderer.avatarSize,
                lineWidth: FloatingTabProfileSegmentRenderer.lineWidth
            )
        )
    }
}
