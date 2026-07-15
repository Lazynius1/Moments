import SwiftUI

enum RecentlyDeletedContentKind: Hashable {
    case moments
    case stories
}

enum ArchivedContentKind: Hashable {
    case moments
    case stories
}

enum RecentlyDeletedConfirmationAction: Identifiable {
    case restore
    case permanentlyDelete

    var id: String {
        switch self {
        case .restore: return "restore"
        case .permanentlyDelete: return "permanentlyDelete"
        }
    }
}

enum ActivitySelectionConfirmationAction: Identifiable {
    case archivedRestore(ids: Set<String>)
    case reactionsDelete
    case tagsRemove
    case commentsDelete
    case stickerRepliesDelete
    case recentlyDeletedRestore
    case recentlyDeletedDelete

    var id: String {
        switch self {
        case .archivedRestore(let ids): return "archivedRestore-\(ids.sorted().joined(separator: ","))"
        case .reactionsDelete: return "reactionsDelete"
        case .tagsRemove: return "tagsRemove"
        case .commentsDelete: return "commentsDelete"
        case .stickerRepliesDelete: return "stickerRepliesDelete"
        case .recentlyDeletedRestore: return "recentlyDeletedRestore"
        case .recentlyDeletedDelete: return "recentlyDeletedDelete"
        }
    }
}

enum RecentlyDeletedAutoScrollDirection {
    case up
    case down
}

enum SelectionDragMode {
    case selecting
    case deselecting
}

enum ActivityInteractionCategory: String, CaseIterable, Identifiable {
    case reactions
    case comments
    case tags
    case stickerReplies
    case archived
    case storiesArchive
    case recentlyDeleted
    case echoes
    case followers
    case visits
    case moments
    case reels
    case timeSpent
    case searches
    case accountHistory

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .reactions: return "userActivity.simple.item.reactions.title"
        case .comments: return "userActivity.simple.item.comments.title"
        case .tags: return "userActivity.simple.item.tags.title"
        case .stickerReplies: return "userActivity.simple.item.stickers.title"
        case .archived: return "userActivity.simple.item.archived.title"
        case .storiesArchive: return "settings.sections.archivedStories"
        case .recentlyDeleted: return "userActivity.simple.item.recentlyDeleted.title"
        case .echoes: return "userActivity.simple.item.echoes.title"
        case .followers: return "userActivity.simple.item.followers.title"
        case .visits: return "userActivity.simple.item.visits.title"
        case .moments: return "userActivity.simple.item.moments"
        case .reels: return "userActivity.simple.item.reels"
        case .timeSpent: return "userActivity.timeSpent.rowTitle"
        case .searches: return "userActivity.recentSearches.title"
        case .accountHistory: return "userActivity.accountHistory.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .reactions: return "userActivity.simple.item.reactions.subtitle"
        case .comments: return "userActivity.simple.item.comments.subtitle"
        case .tags: return "userActivity.simple.item.tags.subtitle"
        case .stickerReplies: return "userActivity.simple.item.stickers.subtitle"
        case .archived: return "userActivity.simple.item.archived.subtitle"
        case .storiesArchive: return "settings.sections.archivedStories.subtitle"
        case .recentlyDeleted: return "userActivity.simple.item.recentlyDeleted.subtitle"
        case .echoes: return "userActivity.simple.item.echoes.subtitle"
        case .followers: return "userActivity.simple.item.followers.subtitle"
        case .visits: return "userActivity.simple.item.visits.subtitle"
        case .moments: return "userActivity.simple.item.moments.subtitle"
        case .reels: return "userActivity.simple.item.reels.subtitle"
        case .timeSpent: return "userActivity.timeSpent.rowSubtitle"
        case .searches: return "userActivity.recentSearches.subtitle"
        case .accountHistory: return "userActivity.accountHistory.subtitle"
        }
    }

    var icon: String {
        switch self {
        case .reactions: return "sparkles"
        case .comments: return "bubble.right.fill"
        case .tags: return AttachmentIcon.tagged.rawValue
        case .stickerReplies: return "face.smiling"
        case .archived: return "archivebox.fill"
        case .storiesArchive: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .recentlyDeleted: return "trash.fill"
        case .echoes: return "EchoesIcon"
        case .followers: return "person.badge.plus"
        case .visits: return "eye.fill"
        case .moments: return "square.grid.2x2.fill"
        case .reels: return "play.square.stack.fill"
        case .timeSpent: return "clock.fill"
        case .searches: return "magnifyingglass"
        case .accountHistory: return "calendar.badge.clock"
        }
    }

    var emptyKey: String {
        switch self {
        case .reactions: return "userActivity.simple.empty.reactions"
        case .comments: return "userActivity.simple.empty.comments"
        case .tags: return "userActivity.simple.empty.tags"
        case .stickerReplies: return "userActivity.simple.empty.stickers"
        case .archived: return "userActivity.simple.empty.archived"
        case .storiesArchive: return "archivedStories.empty.title"
        case .recentlyDeleted: return "userActivity.simple.empty.recentlyDeleted"
        case .echoes: return "userActivity.simple.empty.echoes"
        case .followers: return "userActivity.simple.empty.followers"
        case .visits: return "userActivity.simple.empty.visits"
        case .moments: return "userActivity.simple.empty.moments"
        case .reels: return "userActivity.simple.empty.reels"
        case .searches: return "userActivity.recentSearches.empty"
        case .timeSpent, .accountHistory: return ""
        }
    }

    var accentColor: Color {
        switch self {
        case .reactions: return Color(hex: "F97316")
        case .comments: return Color(hex: "3B82F6")
        case .tags: return Color(hex: "EC4899")
        case .stickerReplies: return Color(hex: "EC4899")
        case .archived: return Color(hex: "64748B")
        case .storiesArchive: return Color(hex: "0EA5E9")
        case .recentlyDeleted: return Color(hex: "EF4444")
        case .echoes: return Color(hex: "3B82F6")
        case .followers: return Color(hex: "10B981")
        case .visits: return Color(hex: "F59E0B")
        case .moments: return Color(hex: "0EA5E9")
        case .reels: return Color(hex: "0EA5E9")
        case .timeSpent: return Color(hex: "64748B")
        case .searches: return Color(hex: "3B82F6")
        case .accountHistory: return Color(hex: "3B82F6")
        }
    }
}

enum ReactionsSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .newest: return "userActivity.simple.filters.sort.newest"
        case .oldest: return "userActivity.simple.filters.sort.oldest"
        }
    }
}

enum ReactionsDateFilter: String, CaseIterable, Identifiable {
    case all
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "userActivity.simple.filters.date.all"
        case .week: return "userActivity.simple.filters.date.week"
        case .month: return "userActivity.simple.filters.date.month"
        case .year: return "userActivity.simple.filters.date.year"
        case .custom: return "userActivity.simple.filters.date.custom"
        }
    }
}

extension Moment {
    var hasVideoMedia: Bool {
        videoUrl != nil || mediaItems?.first?.type == .video
    }

    var parsedAspectRatioValue: Double? {
        guard let raw = aspectRatio?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        let separators = CharacterSet(charactersIn: ":/xX")
        let parts = raw.components(separatedBy: separators).filter { !$0.isEmpty }
        if parts.count == 2,
           let w = Double(parts[0]),
           let h = Double(parts[1]),
           h > 0 {
            return w / h
        }

        if let direct = Double(raw), direct > 0 {
            return direct
        }

        return nil
    }

    var isVerticalReelAspect: Bool {
        guard let ratio = parsedAspectRatioValue else { return false }
        let target = 9.0 / 16.0
        return abs(ratio - target) <= 0.05
    }

    var isReelCandidate: Bool {
        hasVideoMedia && isVerticalReelAspect
    }
}

struct AnimatedReactionIcon: View {
    private let reactions = ReactionType.allCases.map { $0.icon }
    @State private var currentIndex = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var timer: Timer?

    var body: some View {
        Text(reactions[currentIndex])
            .font(.system(size: 22))
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 36, height: 36)
            .onAppear {
                guard timer == nil else { return }
                timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 0.6
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        currentIndex = (currentIndex + 1) % reactions.count
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            scale = 1.0
                            opacity = 1.0
                        }
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
}

struct AnimatedCommentIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    private let bubbles = [
        "bubble.right",
        "bubble.right.fill",
        "bubble.left",
        "bubble.left.fill",
        "ellipsis.bubble",
        "ellipsis.bubble.fill",
    ]
    @State private var currentIndex = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: bubbles[currentIndex])
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 36, height: 36)
            .onAppear {
                guard timer == nil else { return }
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        scale = 0.7
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        currentIndex = (currentIndex + 1) % bubbles.count
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                            scale = 1.0
                            opacity = 1.0
                        }
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
}
