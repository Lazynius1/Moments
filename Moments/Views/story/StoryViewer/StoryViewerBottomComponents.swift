import SwiftUI
import Kingfisher

private enum StoryAudienceBottomInfo {
    static func normalizedAudience(_ audience: String?) -> String {
        audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "everyone"
    }

    static func icon(for audience: String?) -> String {
        ContentAudience.fromAudienceValue(audience).assetName
    }

    static func title(for audience: String?, listName: String?) -> String {
        switch normalizedAudience(audience) {
        case "mutuals", "mutual":
            return NSLocalizedString("audience.type.mutuals", comment: "Mutuals")
        case "bestfriends", "best_friends", "best-friends":
            return NSLocalizedString("audience.type.bestFriends", comment: "Best friends")
        case "customlist":
            return listName ?? NSLocalizedString("audience.type.customList", comment: "Custom list")
        case "custom":
            return NSLocalizedString("audience.type.custom", comment: "Custom")
        case "onlyme", "only_me", "only-me":
            return NSLocalizedString("audience.type.onlyMe", comment: "Only me")
        default:
            return NSLocalizedString("audience.type.everyone", comment: "Everyone")
        }
    }
}

// Barra inferior para historias propias (Actividad + audiencia + acciones).
struct StoryOwnStoryBottomBar: View {
    let viewers: [StoryViewer]
    let reactions: [StoryReaction]
    let audience: String?
    let customListId: String?
    let expirationHours: Int?
    let authorId: String
    let onViewActivity: () -> Void
    let onReactionsActivity: () -> Void
    var showsShare: Bool = false
    let onShare: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var audienceListName: String?

    private var chromeColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var labelShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.clear
    }

    private var isEveryoneAudience: Bool {
        StoryAudienceBottomInfo.normalizedAudience(audience) == "everyone"
    }

    private let firestoreService = FirestoreService()

    private var recentViewers: [StoryViewer] {
        Array(viewers.sorted { $0.timestamp > $1.timestamp }.prefix(3))
    }

    private var audienceTitle: String {
        StoryAudienceBottomInfo.title(for: audience, listName: audienceListName)
    }

    private var storyDurationHours: Int {
        expirationHours == 48 ? 48 : 24
    }

    private var storyDurationLabel: String {
        String(
            format: NSLocalizedString("storyEditor.expiration.option", comment: "Story duration option"),
            storyDurationHours
        )
    }

    private var displayAudience: ContentAudience {
        ContentAudience.fromAudienceValue(audience)
    }

    private var uniqueReactions: [StoryReaction] {
        reactions.latestPerUser()
    }

    private var reactionCount: Int {
        uniqueReactions.count
    }

    /// Hasta 3 emojis distintos de personas distintas, los más recientes primero.
    private var distinctReactionEmojis: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for item in uniqueReactions {
            let emoji = item.reaction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !emoji.isEmpty, seen.insert(emoji).inserted else { continue }
            result.append(emoji)
            if result.count >= 3 { break }
        }
        return result
    }

    private var activityAccessibilityLabel: String {
        let count = viewers.count
        if count == 0 {
            return NSLocalizedString("stories.ownBottom.noViews", comment: "No story views yet")
        }
        if count == 1 {
            return NSLocalizedString("stories.ownBottom.viewsOne", comment: "One story view")
        }
        return String(
            format: NSLocalizedString("stories.ownBottom.viewsMany", comment: "Story view count"),
            count
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            activityColumn
                .frame(maxWidth: .infinity)

            audienceColumn
                .frame(maxWidth: .infinity)

            if showsShare && isEveryoneAudience {
                shareColumn
                    .frame(maxWidth: .infinity)
            }

            if reactionCount > 0 {
                reactionsColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .task(id: customListId) {
            await loadAudienceListNameIfNeeded()
        }
    }

    private var shareColumn: some View {
        Button(action: onShare) {
            VStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(chromeColors.messageTextColor)
                    .frame(height: 32)
                Text(NSLocalizedString("stories.ownBottom.share", comment: "Share story"))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundColor(chromeColors.messageTextColor)
                    .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(NSLocalizedString("stories.ownBottom.share", comment: "Share story"))
    }

    private var reactionsColumn: some View {
        Button(action: onReactionsActivity) {
            VStack(spacing: 6) {
                reactionEmojisStack
                    .frame(height: 32)

                Text(MomentsFormat.count(reactionCount, style: .socialMetric))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundColor(chromeColors.messageTextColor)
                    .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(
            String(
                format: NSLocalizedString("stories.ownBottom.reactionsCount", comment: "Story reactions count"),
                reactionCount
            )
        )
    }

    @ViewBuilder
    private var reactionEmojisStack: some View {
        let emojis = distinctReactionEmojis
        if emojis.isEmpty {
            Text("❤️")
                .font(.system(size: 22))
        } else if emojis.count == 1 {
            Text(emojis[0])
                .font(.system(size: 22))
        } else {
            HStack(spacing: -6) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                    Text(emoji)
                        .font(.system(size: index == 0 ? 22 : 18))
                        .shadow(color: labelShadowColor, radius: 3, x: 0, y: 1)
                }
            }
        }
    }

    private var activityColumn: some View {
        Button(action: onViewActivity) {
            VStack(spacing: 6) {
                if !recentViewers.isEmpty {
                     HStack(spacing: -8) {
                         ForEach(Array(recentViewers.enumerated()), id: \.element.id) { index, viewer in
                             viewerAvatar(viewer)
                                 .reversedMask(alignment: .center) {
                                     if index < recentViewers.count - 1 {
                                         Circle()
                                             .frame(width: 31, height: 31)
                                             .offset(x: 20)
                                     }
                                 }
                         }
                     }
                     .frame(height: 32)
                } else {
                    Image("StoryActivityEmptyIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(chromeColors.messageTextColor)
                        .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)
                        .frame(width:36, height: 36)
                }

                Text(NSLocalizedString("stories.ownBottom.activity", comment: "Activity label under avatars"))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundColor(chromeColors.messageTextColor)
                    .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(activityAccessibilityLabel)
    }

    private var audienceColumn: some View {
        VStack(spacing: 6) {
            AudienceIconView(
                audience: displayAudience,
                size: AudienceIconMetrics.storyBottomBar,
                tintColor: chromeColors.messageTextColor
            )
            .frame(width: 36, height: 36)
            .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)

            Text(audienceTitle)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundColor(chromeColors.messageTextColor)
                .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: 88)

            Text(storyDurationLabel)
                .font(.system(size: legacyPoppinsSize(11)))
                .foregroundColor(chromeColors.messageTextColor.opacity(0.92))
                .shadow(color: labelShadowColor, radius: 4, x: 0, y: 1)
                .lineLimit(1)
        }
        .frame(minWidth: 56)
        .accessibilityLabel(
            String(
                format: NSLocalizedString("stories.ownBottom.audienceDurationAccessibility", comment: "Story audience and duration"),
                audienceTitle,
                storyDurationLabel
            )
        )
    }

    @MainActor
    private func loadAudienceListNameIfNeeded() async {
        let normalized = StoryAudienceBottomInfo.normalizedAudience(audience)
        guard normalized == "customlist",
              let listId = customListId,
              !listId.isEmpty else {
            audienceListName = nil
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            firestoreService.fetchCustomListDetails(listId: listId, ownerId: authorId) { result in
                Task { @MainActor in
                    if case .success(let list) = result {
                        audienceListName = list.name
                    }
                    continuation.resume()
                }
            }
        }
    }

    @ViewBuilder
    private func viewerAvatar(_ viewer: StoryViewer) -> some View {
        Group {
            if let path = viewer.profileImagePath,
               let url = URL(string: path) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .foregroundColor(chromeColors.replyBarSecondaryText)
                    .background(chromeColors.messageBubbleBackground)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(
                colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.12),
                lineWidth: 1.5
            )
        )
    }
}

struct StoryReactionsStrip: View {
    let reactions: [String]
    let showReactions: Bool
    let onReaction: (String) -> Void
    let onMoreReactions: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text(NSLocalizedString("storyContextMenu.scrollReactions", comment: "Scroll for more reactions"))
                    .font(.system(size: legacyPoppinsSize(10)))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(reactions, id: \.self) { reaction in
                        Button(action: {
                            onReaction(reaction)
                        }) {
                            Text(reaction)
                                .font(.system(size: 30))
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(showReactions ? 1.0 : 0.5)
                        .animation(
                            .spring(response: 0.3)
                                .delay(Double(reactions.firstIndex(of: reaction) ?? 0) * 0.03),
                            value: showReactions
                        )
                    }

                    Button {
                        HapticManager.shared.lightImpact()
                        onMoreReactions()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .frame(width: 36, height: 36)
                            .background {
                                Color.clear
                                    .momentsChromeGlass(in: Circle(), interactive: true)
                            }
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .momentsChromeGlass(in: Capsule(), interactive: true)
            .clipShape(Capsule())
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                radius: 24,
                x: 0,
                y: 12
            )
            .padding(.horizontal, 20)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

struct StoryNoInteractionsNotice: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("stories.noInteractions")
            .font(.system(size: legacyPoppinsSize(14)))
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.68) : Color.black.opacity(0.68))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }
}

/// Zonas laterales de navegación alineadas al rect del canvas.
struct StoryNavigationTouchAreas: View {
    let canvasSize: CGSize
    var sideWidthFraction: CGFloat = StoryGestureCoordinator.navigationSideWidthFraction
    let shouldSuppressNavigationTapAt: (CGPoint) -> Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let sideWidth = max(geometry.size.width * sideWidthFraction, 1)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: sideWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let point = value.location
                                guard !shouldSuppressNavigationTapAt(point) else { return }
                                onPrevious()
                            }
                    )
                    .position(x: sideWidth / 2, y: geometry.size.height / 2)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: sideWidth)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let point = CGPoint(
                                    x: geometry.size.width - sideWidth + value.location.x,
                                    y: value.location.y
                                )
                                guard !shouldSuppressNavigationTapAt(point) else { return }
                                onNext()
                            }
                    )
                    .position(x: geometry.size.width - (sideWidth / 2), y: geometry.size.height / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
