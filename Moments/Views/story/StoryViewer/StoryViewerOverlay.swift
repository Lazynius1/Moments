import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVKit
import PhotosUI
import FirebaseStorage
import Kingfisher
import Photos
import MapKit
import AVFoundation
import SwiftData

// MARK: - Supporting Glassmorphic Views

struct GlassmorphicProgressBar: View {
    let progress: Double
    let isActive: Bool
    let audience: String?

    private var normalizedAudience: String {
        audience?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var progressGradient: LinearGradient {
        switch normalizedAudience {
        case "bestfriends", "best_friends", "best-friends":
            // Best Friends green
            return LinearGradient(
                colors: [Color(hex: "24C26A"), Color(hex: "5BE584")],
                startPoint: .leading,
                endPoint: .trailing
            )
        case "connections", "mutuals", "mutual":
            // Mutuals accent (different from default)
            return LinearGradient(
                colors: [Color(hex: "00B4D8"), Color(hex: "4CC9F0")],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var shadowColor: Color {
        switch normalizedAudience {
        case "bestfriends", "best_friends", "best-friends":
            return Color(hex: "24C26A").opacity(0.65)
        case "connections", "mutuals", "mutual":
            return Color(hex: "00B4D8").opacity(0.55)
        default:
            return Color.purple.opacity(0.6)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 2.5)
                    .cornerRadius(1.25)

                // Progress with clamped value
                Rectangle()
                    .fill(progressGradient)
                    .frame(
                        width: geometry.size.width * min(max(progress, 0.0), 1.0),
                        height: 2.5
                    )
                    .cornerRadius(1.25)
                    .shadow(color: shadowColor, radius: 3, x: 0, y: 0)
                    .animation(
                        isActive ? .linear(duration: 0.1) : .none,
                        value: progress
                    )
            }
        }
        .frame(height: 2.5)
    }
}
struct GlassmorphicActionButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isDestructive ? .red : .white)
                    .font(.system(size: 18))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(isDestructive ? .red : .white)
                        .font(.custom("Poppins-Medium", size: 14))

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .foregroundColor(Color.white.opacity(0.7))
                            .font(.custom("Poppins-Regular", size: 11))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .storyGlassmorphic()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct GlassmorphicSuccessMessage: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "007AFF"))
                .font(.system(size: 20))

            Text(text)
                .foregroundColor(.white)
                .font(.custom("Poppins-Medium", size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .storyGlassmorphic()
        .clipShape(Capsule())
    }
}

struct GlassmorphicStoryConfirmationDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    var isDestructive: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.62)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.20)
    }

    var body: some View {
        ZStack {
            scrimColor
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(title)
                        .foregroundColor(primaryTextColor)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .multilineTextAlignment(.center)

                    if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message)
                            .foregroundColor(secondaryTextColor)
                            .font(.custom("Poppins-Regular", size: 14))
                            .multilineTextAlignment(.center)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text(cancelTitle)
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(primaryTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(isDestructive ? .red : primaryTextColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .padding(.horizontal, 24)
        }
    }
}

struct GlassmorphicViewersSheet: View {
    let story: Story
    let viewers: [StoryViewer]
    let reactions: [StoryReaction]
    var initialTab: Int = 0
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    @State private var viewerSearchText = ""
    @State private var reactionSearchText = ""
    @State private var audienceUsers: [AppUser] = []
    @State private var audienceListName: String?
    @State private var isLoadingAudience = false
    @State private var didLoadAudience = false
    @State private var showAudienceList = false
    @State private var reactionUsersById: [String: AppUser] = [:]
    private let firestoreService = FirestoreService()

    private var normalizedAudience: String {
        story.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "everyone"
    }

    private var isEveryoneAudience: Bool {
        normalizedAudience == "everyone"
    }

    private var audienceTitle: String {
        switch normalizedAudience {
        case "connections", "mutuals", "mutual":
            return NSLocalizedString("audience.type.connections", comment: "Mutuals")
        case "bestfriends", "best_friends", "best-friends":
            return NSLocalizedString("audience.type.bestFriends", comment: "Best friends")
        case "customlist":
            return audienceListName ?? NSLocalizedString("audience.type.customList", comment: "Custom list")
        case "custom":
            return NSLocalizedString("audience.type.custom", comment: "Custom")
        case "onlyme", "only_me", "only-me":
            return NSLocalizedString("audience.type.onlyMe", comment: "Only me")
        default:
            return NSLocalizedString("audience.type.everyone", comment: "Everyone")
        }
    }

    private var displayAudience: ContentAudience {
        ContentAudience.fromAudienceValue(story.audience)
    }

    private var filteredViewers: [StoryViewer] {
        let query = viewerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewers }
        return viewers.filter { viewer in
            (viewer.username ?? "Usuario").localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredReactions: [StoryReaction] {
        let query = reactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return reactions }
        return reactions.filter { reaction in
            let username = reactionUsersById[reaction.userId]?.username ?? "Usuario"
            return username.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            storyActivityHeader
                .padding(.horizontal, 22)
                .padding(.top, 12)

            audienceSection
                .padding(.horizontal, 22)
                .padding(.top, 18)

            GlassmorphicTabSelector(
                    tabs: [
                        String(format: NSLocalizedString("stories.activity.viewersTab", comment: ""), viewers.count),
                        String(format: NSLocalizedString("stories.activity.reactionsTab", comment: ""), reactions.count)
                    ],
                    selectedIndex: $selectedTab
                )
                .padding(.horizontal, 22)
                .padding(.top, 14)

            TabView(selection: $selectedTab) {
                ZStack {
                    if viewers.isEmpty {
                        GlassmorphicEmptyState(
                            icon: "eye.slash",
                            message: NSLocalizedString("stories.activity.noViewers", comment: "No viewers yet")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                viewersSearchBar

                                if filteredViewers.isEmpty {
                                    GlassmorphicEmptyState(
                                        icon: "magnifyingglass",
                                        message: NSLocalizedString(
                                            "stories.activity.search.empty",
                                            value: "No viewers match your search.",
                                            comment: "No matching viewers for search"
                                        )
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 8)
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(filteredViewers) { viewer in
                                            GlassmorphicViewerRow(viewer: viewer)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 28)
                        }
                    }
                }
                .tag(0)

                ZStack {
                    if reactions.isEmpty {
                        GlassmorphicEmptyState(
                            icon: "heart.slash",
                            message: NSLocalizedString("stories.activity.noReactions", comment: "No reactions yet")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                reactionsSearchBar

                                if filteredReactions.isEmpty {
                                    GlassmorphicEmptyState(
                                        icon: "magnifyingglass",
                                        message: NSLocalizedString(
                                            "stories.activity.search.empty",
                                            value: "No viewers match your search.",
                                            comment: "No matching viewers for search"
                                        )
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 8)
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(filteredReactions) { reaction in
                                            GlassmorphicReactionRow(
                                                reaction: reaction,
                                                user: reactionUsersById[reaction.userId]
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 28)
                        }
                    }
                }
                .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .background(Color.clear.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedTab = min(max(initialTab, 0), 1)
            guard !didLoadAudience else { return }
            didLoadAudience = true
            loadAudienceMembers()
            loadReactionUsersIfNeeded()
        }
        .sheet(isPresented: $showAudienceList) {
            GlassmorphicAudienceMembersSheet(
                title: audienceTitle,
                users: audienceUsers
            )
        }
    }

    private var viewersSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                .font(.system(size: 15, weight: .medium))

            TextField(NSLocalizedString("userListView.search.placeholder", comment: "Search users placeholder"), text: $viewerSearchText)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black.opacity(0.88))
                .textFieldStyle(.plain)

            if !viewerSearchText.isEmpty {
                Button {
                    viewerSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.001))
        .liquidGlass(in: Capsule())
    }

    private var reactionsSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                .font(.system(size: 15, weight: .medium))

            TextField(NSLocalizedString("userListView.search.placeholder", comment: "Search users placeholder"), text: $reactionSearchText)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black.opacity(0.88))
                .textFieldStyle(.plain)

            if !reactionSearchText.isEmpty {
                Button {
                    reactionSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.001))
        .liquidGlass(in: Capsule())
    }

    private func loadReactionUsersIfNeeded() {
        let missingIds = Array(Set(reactions.map(\.userId))).filter { reactionUsersById[$0] == nil }
        guard !missingIds.isEmpty else { return }

        firestoreService.fetchUsers(userIds: missingIds) { result in
            guard case .success(let users) = result else { return }
            DispatchQueue.main.async {
                for user in users {
                    self.reactionUsersById[user.id] = user
                }
            }
        }
    }

    private var storyActivityHeader: some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(activityPrimaryText)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(spacing: 2) {
                Text(NSLocalizedString("stories.activity.title", comment: "Activity Title"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(activityPrimaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 2)
        }
    }

    private var activityPrimaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var activitySecondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.54)
    }

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingAudience {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(activitySecondaryText)
                    Text(NSLocalizedString("stories.activity.audienceLoading", comment: "Loading audience"))
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(activitySecondaryText)
                }
            } else if isEveryoneAudience {
                Text(NSLocalizedString("audience.description.everyone", comment: "Everyone audience description"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(activitySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if canOpenAudienceList {
                Button {
                    showAudienceList = true
                } label: {
                    audienceSummaryRow(showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                audienceSummaryRow(showsChevron: false)
            }
        }
    }

    private var canOpenAudienceList: Bool {
        !isEveryoneAudience && !audienceUsers.isEmpty
    }

    private func audienceSummaryRow(showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(activityPrimaryText.opacity(colorScheme == .dark ? 0.08 : 0.06))

                AudienceIconView(
                    audience: displayAudience,
                    size: AudienceIconMetrics.storyActivity,
                    tintColor: activityPrimaryText.opacity(0.82)
                )
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(audienceTitle)
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(activityPrimaryText)
                    .lineLimit(1)

                Text(audienceSummarySubtitle)
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(activitySecondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(activitySecondaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private var audienceSummarySubtitle: String {
        if audienceUsers.isEmpty {
            return NSLocalizedString("stories.activity.audienceNoMembers", comment: "No users in this audience")
        }

        return String(format: NSLocalizedString("stories.activity.audienceMembersCount", comment: "Members count"), audienceUsers.count)
    }

    private func loadAudienceMembers() {
        isLoadingAudience = true
        audienceUsers = []
        audienceListName = nil

        switch normalizedAudience {
        case "connections", "mutuals", "mutual":
            firestoreService.fetchMutualConnections(userId: story.authorId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let users):
                        self.audienceUsers = users.sorted { $0.username.lowercased() < $1.username.lowercased() }
                    case .failure:
                        self.audienceUsers = []
                    }
                    self.isLoadingAudience = false
                }
            }

        case "bestfriends", "best_friends", "best-friends":
            firestoreService.fetchUser(userId: story.authorId) { result in
                switch result {
                case .success(let user):
                    self.fetchAudienceUsersByIds(user.bestFriends)
                case .failure:
                    DispatchQueue.main.async {
                        self.audienceUsers = []
                        self.isLoadingAudience = false
                    }
                }
            }

        case "customlist":
            guard let listId = story.customListId, !listId.isEmpty else {
                isLoadingAudience = false
                return
            }

            firestoreService.fetchCustomListDetails(listId: listId, ownerId: story.authorId) { result in
                switch result {
                case .success(let list):
                    DispatchQueue.main.async {
                        self.audienceListName = list.name
                    }
                    self.fetchAudienceUsersByIds(list.members)
                case .failure:
                    DispatchQueue.main.async {
                        self.audienceUsers = []
                        self.isLoadingAudience = false
                    }
                }
            }

        case "custom":
            Firestore.firestore()
                .collection("users")
                .document(story.authorId)
                .getDocument { document, _ in
                    let visibilitySettings = document?.data()?["contentVisibilitySettings"] as? [String: Any]
                    let customUsers = visibilitySettings?["storyCustomUsers"] as? [String]
                        ?? visibilitySettings?["customStoryViewers"] as? [String]
                        ?? []
                    self.fetchAudienceUsersByIds(customUsers)
                }

        case "onlyme", "only_me", "only-me":
            fetchAudienceUsersByIds([story.authorId])

        default:
            isLoadingAudience = false
        }
    }

    private func fetchAudienceUsersByIds(_ userIds: [String]) {
        var seen = Set<String>()
        let uniqueIds = userIds.filter { id in
            guard !id.isEmpty else { return false }
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
        guard !uniqueIds.isEmpty else {
            DispatchQueue.main.async {
                self.audienceUsers = []
                self.isLoadingAudience = false
            }
            return
        }

        let chunks: [[String]] = stride(from: 0, to: uniqueIds.count, by: 10).map {
            Array(uniqueIds[$0..<min($0 + 10, uniqueIds.count)])
        }

        let group = DispatchGroup()
        let collectQueue = DispatchQueue(label: "story.audience.collect")
        var mergedUsers: [AppUser] = []

        for chunk in chunks {
            group.enter()
            firestoreService.fetchUsers(userIds: chunk) { result in
                defer { group.leave() }
                if case .success(let users) = result {
                    collectQueue.sync {
                        mergedUsers.append(contentsOf: users)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let order = Dictionary(uniqueIds.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            self.audienceUsers = mergedUsers.sorted { lhs, rhs in
                (order[lhs.id] ?? Int.max) < (order[rhs.id] ?? Int.max)
            }
            self.isLoadingAudience = false
        }
    }
}

private struct GlassmorphicAudienceMembersSheet: View {
    let title: String
    let users: [AppUser]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.001))
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                    .padding(.horizontal, 56)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            if users.isEmpty {
                GlassmorphicEmptyState(
                    icon: "person.2.slash",
                    message: NSLocalizedString("stories.activity.audienceNoMembers", comment: "No users in this audience")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(users) { user in
                            GlassmorphicAudienceMemberRow(user: user)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(Color.clear.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct GlassmorphicAudienceMemberRow: View {
    let user: AppUser
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.86)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let profileImagePath = user.profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(primaryTextColor.opacity(0.10))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(primaryTextColor.opacity(0.7))
                    )
            }

            HStack(spacing: 4) {
                Text(user.username)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                if user.isVerified {
                    VerifiedBadgeView(userId: user.id, size: 12)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct GlassmorphicTabSelector: View {
    let tabs: [String]
    @Binding var selectedIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.46)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                tabButton(for: index)
            }
        }
    }

    private func tabButton(for index: Int) -> some View {
        let isSelected = selectedIndex == index

        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedIndex = index
            }
        }) {
            Text(tabs[index])
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(isSelected ? primaryTextColor : secondaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(isSelected ? primaryTextColor.opacity(0.86) : .clear)
                        .frame(width: 28, height: 2)
                }
                .opacity(isSelected ? 1 : 0.72)
        }
        .buttonStyle(.plain)
    }
}

struct GlassmorphicViewerRow: View {
    let viewer: StoryViewer
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.52)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            if let profileImagePath = viewer.profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            } else {
                ZStack {
                    Circle()
                        .fill(primaryTextColor.opacity(0.10))
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(secondaryTextColor)
                }
                .frame(width: 48, height: 48)
            }

            // User info
            HStack(spacing: 6) {
                Text(viewer.username ?? "Usuario")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(primaryTextColor)

                if let badgeText = viewer.rewatchBadgeText {
                    Text(badgeText)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(primaryTextColor)
                }
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .background(secondaryTextColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
    }
}

struct GlassmorphicReactionRow: View {
    let reaction: StoryReaction
    let user: AppUser?
    @State private var username: String = "Usuario"
    @State private var profileImagePath: String?
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.52)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            if let profileImagePath = profileImagePath,
               let url = URL(string: profileImagePath) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            } else {
                ZStack {
                    Circle()
                        .fill(primaryTextColor.opacity(0.10))
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(secondaryTextColor)
                }
                .frame(width: 48, height: 48)
            }

            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(primaryTextColor)

                Text(timeAgo(from: reaction.timestamp))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            // Reaction
            Text(reaction.reaction)
                .font(.system(size: 32))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
                .background(secondaryTextColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
        }
        .onAppear {
            hydrateUserInfo()
        }
    }

    private func hydrateUserInfo() {
        if let user {
            username = user.username
            profileImagePath = user.profileImagePath
            return
        }

        FirestoreService().fetchUserProfile(userId: reaction.userId) { result in
            switch result {
            case .success(let user):
                self.username = user.username
                self.profileImagePath = user.profileImagePath
            case .failure(_):
                self.username = "Usuario"
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "es")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct GlassmorphicEmptyState: View {
    let icon: String
    let message: String
    let showCloseButton: Bool
    let onClose: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.84)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.48)
    }

    init(icon: String, message: String, showCloseButton: Bool = false, onClose: (() -> Void)? = nil) {
        self.icon = icon
        self.message = message
        self.showCloseButton = showCloseButton
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(secondaryTextColor)

            Text(message)
                .foregroundColor(secondaryTextColor)
                .font(.custom("Poppins-Medium", size: 14))
                .multilineTextAlignment(.center)

            if showCloseButton, let onClose = onClose {
                Button(action: onClose) {
                    Text(NSLocalizedString("stories.close", comment: "Close"))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(primaryTextColor)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.001))
                        .liquidGlass(in: Capsule(), interactive: true)
                }
            }
        }
        .padding()
        .padding(.horizontal, 40)
    }
}
