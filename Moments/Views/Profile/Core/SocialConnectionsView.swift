import SwiftUI
import FirebaseAuth

// MARK: - Tab & Route

enum SocialConnectionTab: String, CaseIterable, Identifiable, Hashable {
    case visits
    case inCommon
    case followers
    case following
    case mutuals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visits:
            return NSLocalizedString("profile.stats.visits", comment: "Visits")
        case .inCommon:
            return NSLocalizedString("profile.ui.inCommon", comment: "In common")
        case .followers:
            return NSLocalizedString("profile.ui.followers", comment: "Followers")
        case .following:
            return NSLocalizedString("profile.ui.following", comment: "Following")
        case .mutuals:
            return NSLocalizedString("profile.ui.mutuals", comment: "Mutuals")
        }
    }

    static var ownProfileTabs: [SocialConnectionTab] {
        [.visits, .followers, .following, .mutuals]
    }

    static func tabs(for _: VisibleConnectionTypes, includesVisits: Bool) -> [SocialConnectionTab] {
        var tabs: [SocialConnectionTab] = []
        if includesVisits { tabs.append(.visits) }
        if !includesVisits {
            tabs.append(.inCommon)
            tabs.append(.followers)
            tabs.append(.following)
        }
        return tabs
    }
}

struct SocialConnectionsRoute: Hashable, Identifiable {
    let id = UUID()
    let initialTab: SocialConnectionTab

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SocialConnectionsRoute, rhs: SocialConnectionsRoute) -> Bool {
        lhs.id == rhs.id
    }
}

private struct SocialProfileNavigationTarget: Identifiable, Hashable {
    let id: String
}

private struct SharedActivityNavigationTarget: Identifiable, Hashable {
    let user: AppUser

    var id: String { user.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(user.id)
    }

    static func == (lhs: SharedActivityNavigationTarget, rhs: SharedActivityNavigationTarget) -> Bool {
        lhs.user.id == rhs.user.id
    }
}

// MARK: - Main Screen

struct SocialConnectionsScreen<VM: UserListViewModel & ObservableObject>: View {
    let route: SocialConnectionsRoute
    let username: String
    let availableTabs: [SocialConnectionTab]
    let includesVisits: Bool
    let isOwnProfile: Bool
    let currentUser: AppUser?
    let inCommonUsers: [AppUser]
    let followers: [AppUser]
    let following: [AppUser]
    let mutuals: [AppUser]
    let suggestedUsers: [AppUser]
    let viewerInterests: [String]
    let visitTimestamps: [String: [Date]]
    var connectionVisibility: VisibleConnectionTypes?
    @ObservedObject var listViewModel: VM
    var profileZoomNamespace: Namespace.ID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTabIndex = 0
    @State private var searchText = ""
    @State private var sortModes: [SocialConnectionTab: SocialConnectionsSortMode] = [:]
    @State private var followerTimestamps: [String: Date] = [:]
    @State private var followingTimestamps: [String: Date] = [:]
    @State private var recentMomentCounts: [String: Int] = [:]
    @State private var isLoadingFollowerTimestamps = false
    @State private var selectedProfileTarget: SocialProfileNavigationTarget?
    @State private var selectedSharedActivityTarget: SharedActivityNavigationTarget?
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId = ""
    @StateObject private var visitsViewModel = VisitsViewModel()
    @Namespace private var fallbackZoomNamespace
    @EnvironmentObject private var authService: AuthService

    private var zoomNamespace: Namespace.ID {
        profileZoomNamespace ?? fallbackZoomNamespace
    }

    private var activeGroupedVisits: [GroupedVisit] {
        if isOwnProfile, let profileViewModel = listViewModel as? ProfileViewModel {
            return profileViewModel.groupedVisits
        }
        return visitsViewModel.groupedVisits
    }

    private var isVisitsLoading: Bool {
        if isOwnProfile, let profileViewModel = listViewModel as? ProfileViewModel {
            return profileViewModel.isLoadingVisits
        }
        return visitsViewModel.isLoading
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var selectedTab: SocialConnectionTab? {
        guard availableTabs.indices.contains(selectedTabIndex) else { return nil }
        return availableTabs[selectedTabIndex]
    }

    private var tabItems: [SocialConnectionTabItem] {
        availableTabs.map { tab in
            SocialConnectionTabItem(tab: tab, count: count(for: tab))
        }
    }

    private var currentSortMode: SocialConnectionsSortMode {
        guard let selectedTab else { return .default }
        return sortModes[selectedTab] ?? .default
    }

    private var shouldShowSearchBar: Bool {
        guard let selectedTab else { return true }

        if selectedTab == .inCommon {
            return false
        }

        if !canViewList(for: selectedTab) {
            return false
        }

        return selectedTab != .visits || includesVisits
    }

    private var shouldShowSortRow: Bool {
        guard let selectedTab else { return true }
        if selectedTab == .inCommon { return false }
        return canViewList(for: selectedTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            SocialConnectionUnderlineTabBar(
                tabItems: tabItems,
                selectedIndex: $selectedTabIndex
            )
            if shouldShowSearchBar {
                searchBar
            }
            if shouldShowSortRow {
                sortRow
            }
            tabContent
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedProfileTarget) { target in
            UserProfileView(userId: target.id)
                .userProfileZoomDestination(userId: target.id, namespace: zoomNamespace)
        }
        .navigationDestination(item: $selectedSharedActivityTarget) { target in
            SharedActivityView(
                currentUser: currentUser,
                otherUser: target.user,
                viewModel: listViewModel,
                profileZoomNamespace: zoomNamespace
            )
        }
        .fullScreenCover(isPresented: $showSpecificUserStories, onDismiss: {
            selectedStoryUserId = ""
        }) {
            StoriesView(startAtUserId: selectedStoryUserId)
                .environmentObject(FirestoreService.shared)
                .environmentObject(authService)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(stalkerAlertOverlay)
        .onAppear {
            configureInitialTab()
            if includesVisits {
                if isOwnProfile, let profileViewModel = listViewModel as? ProfileViewModel {
                    profileViewModel.refreshVisits()
                } else {
                    visitsViewModel.fetchVisits()
                }
            }
            loadFollowerTimestampsIfNeeded()
            loadFollowingInsightsIfNeeded()
        }
        .onChange(of: selectedTabIndex) { _, _ in
            searchText = ""
            loadFollowerTimestampsIfNeeded()
            loadFollowingInsightsIfNeeded()
        }
        .onChange(of: currentSortMode) { _, newMode in
            if newMode == .newest || newMode == .oldest {
                loadFollowerTimestampsIfNeeded()
                loadFollowingTimestampsIfNeeded()
            }
        }
    }



    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))

            TextField(
                NSLocalizedString("userListView.search.placeholder", comment: "Search users placeholder"),
                text: $searchText
            )
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(primaryTextColor)
            .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.clear.momentsChromeGlass(in: Capsule()))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var sortRow: some View {
        Menu {
            ForEach(SocialConnectionsSortMode.allCases) { mode in
                Button {
                    setSortMode(mode)
                } label: {
                    if mode == currentSortMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(NSLocalizedString("socialConnections.sort.by", comment: ""))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(currentSortMode.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(primaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        if availableTabs.isEmpty {
            Spacer()
        } else {
            TabView(selection: $selectedTabIndex) {
                ForEach(Array(availableTabs.enumerated()), id: \.offset) { index, tab in
                    tabPage(for: tab)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    @ViewBuilder
    private func tabPage(for tab: SocialConnectionTab) -> some View {
        let sortMode = sortModes[tab] ?? .default

        switch tab {
        case .visits:
            VisitsTabContent(
                groupedVisits: activeGroupedVisits,
                isLoading: isVisitsLoading,
                listViewModel: listViewModel,
                searchText: searchText,
                sortMode: sortMode,
                colorScheme: colorScheme,
                profileZoomNamespace: zoomNamespace,
                onUserTap: { userId in
                    selectedProfileTarget = SocialProfileNavigationTarget(id: userId)
                },
                onAvatarTap: handleAvatarTap
            )
        case .inCommon:
            CommonConnectionsTabContent(
                commonUsers: inCommonUsers,
                suggestedUsers: suggestedUsers,
                viewerInterests: viewerInterests,
                viewModel: listViewModel,
                onUserTap: { user in
                    selectedProfileTarget = SocialProfileNavigationTarget(id: user.id)
                },
                onAvatarTap: handleAvatarTap,
                profileZoomNamespace: zoomNamespace
            )
        case .followers, .following, .mutuals:
            UsersTabContent(
                title: tab.title,
                users: orderedUsers(for: tab),
                visitTimestamps: visitTimestamps,
                searchText: searchText,
                sortMode: sortMode,
                followerTimestamps: followerTimestamps,
                followingTimestamps: followingTimestamps,
                rowAction: defaultRowAction(for: tab),
                activeTab: tab,
                includesVisits: includesVisits,
                isOwnProfile: isOwnProfile,
                isListHiddenFromViewer: !canViewList(for: tab),
                viewModel: listViewModel,
                onUserTap: { user in
                    selectedProfileTarget = SocialProfileNavigationTarget(id: user.id)
                },
                profileZoomNamespace: zoomNamespace,
                rowConfiguration: rowConfiguration(for: tab),
                recentMomentCounts: recentMomentCounts,
                onViewSharedActivity: isOwnProfile && (tab == .following || tab == .mutuals) ? { user in
                    selectedSharedActivityTarget = SharedActivityNavigationTarget(user: user)
                } : nil,
                onRemoveFollower: isOwnProfile && tab == .followers ? { user in
                    (listViewModel as? ProfileViewModel)?.removeFollower(userId: user.id)
                } : nil,
                onAvatarTap: handleAvatarTap,
                mutualUserIds: Set(mutuals.map { $0.id })
            )
        }
    }

    @ViewBuilder
    private var stalkerAlertOverlay: some View {
        if includesVisits,
           visitsViewModel.showStalkerAlert,
           let stalker = visitsViewModel.detectedStalker {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    visitsViewModel.showStalkerAlert = false
                }
                .overlay(
                    StalkerAlertView(
                        stalker: stalker,
                        isPresented: $visitsViewModel.showStalkerAlert,
                        colorScheme: colorScheme
                    )
                )
        }
    }

    private func count(for tab: SocialConnectionTab) -> Int {
        switch tab {
        case .visits:
            return activeGroupedVisits.count
        case .inCommon:
            return inCommonUsers.count
        case .followers:
            if let visibility = connectionVisibility, !visibility.canViewFollowers { return 0 }
            return followers.count
        case .following:
            if let visibility = connectionVisibility, !visibility.canViewFollowing { return 0 }
            return following.count
        case .mutuals:
            return mutuals.count
        }
    }

    private func canViewList(for tab: SocialConnectionTab) -> Bool {
        guard let visibility = connectionVisibility else { return true }
        switch tab {
        case .followers: return visibility.canViewFollowers
        case .following: return visibility.canViewFollowing
        default: return true
        }
    }

    private func users(for tab: SocialConnectionTab) -> [AppUser] {
        guard canViewList(for: tab) else { return [] }
        switch tab {
        case .visits: return []
        case .inCommon: return inCommonUsers
        case .followers: return followers
        case .following: return following
        case .mutuals: return mutuals
        }
    }

    private func orderedUsers(for tab: SocialConnectionTab) -> [AppUser] {
        let baseUsers = users(for: tab)
        guard !isOwnProfile, let currentUserId = currentUser?.id else { return baseUsers }
        guard let viewerIndex = baseUsers.firstIndex(where: { $0.id == currentUserId }) else { return baseUsers }

        var ordered = baseUsers
        let viewer = ordered.remove(at: viewerIndex)
        ordered.insert(viewer, at: 0)
        return ordered
    }

    private func handleAvatarTap(userId: String, hasStory: Bool) {
        SocialConnectionAvatarTapRouting.route(
            userId: userId,
            hasStory: hasStory,
            openProfile: { selectedProfileTarget = SocialProfileNavigationTarget(id: $0) },
            openStories: { userId in
                selectedStoryUserId = userId
                showSpecificUserStories = true
            }
        )
    }

    private func rowConfiguration(for tab: SocialConnectionTab) -> SocialConnectionRowConfiguration {
        switch tab {
        case .inCommon:
            return .init(
                showsRemoveFollower: false,
                showsRelationshipButton: true,
                showsOverflowMenu: false,
                showsFollowBackHint: false,
                showsBio: true,
                showsNewPosts: false
            )
        case .followers:
            if !isOwnProfile {
                return .init(
                    showsRemoveFollower: false,
                    showsRelationshipButton: true,
                    showsOverflowMenu: false,
                    showsFollowBackHint: false,
                    showsBio: true,
                    showsNewPosts: false
                )
            }

            return .init(
                showsRemoveFollower: true,
                showsRelationshipButton: false,
                showsOverflowMenu: false,
                showsFollowBackHint: true,
                showsBio: true,
                showsNewPosts: false
            )
        case .following, .mutuals:
            return .init(
                showsRemoveFollower: false,
                showsRelationshipButton: true,
                showsOverflowMenu: isOwnProfile,
                showsFollowBackHint: false,
                showsBio: true,
                showsNewPosts: isOwnProfile
            )
        case .visits:
            return .init(
                showsRemoveFollower: false,
                showsRelationshipButton: true,
                showsOverflowMenu: false,
                showsFollowBackHint: true,
                showsBio: true,
                showsNewPosts: false
            )
        }
    }

    private func defaultRowAction(for tab: SocialConnectionTab) -> UserListRowAction {
        switch tab {
        case .visits, .inCommon:
            return .follow
        case .followers:
            return isOwnProfile ? .follow : .unfollow
        case .following, .mutuals:
            return .unfollow
        }
    }

    private func setSortMode(_ mode: SocialConnectionsSortMode) {
        guard let selectedTab else { return }
        sortModes[selectedTab] = mode
    }

    private func configureInitialTab() {
        guard !availableTabs.isEmpty else {
            selectedTabIndex = 0
            return
        }
        if let index = availableTabs.firstIndex(of: route.initialTab) {
            selectedTabIndex = index
        } else {
            selectedTabIndex = 0
        }
    }

    private func loadFollowerTimestampsIfNeeded() {
        guard includesVisits,
              selectedTab == .followers || currentSortMode == .newest || currentSortMode == .oldest,
              followerTimestamps.isEmpty,
              !isLoadingFollowerTimestamps,
              let userId = Auth.auth().currentUser?.uid else { return }

        isLoadingFollowerTimestamps = true
        Task {
            defer {
                Task { @MainActor in
                    isLoadingFollowerTimestamps = false
                }
            }
            do {
                let items = try await FirestoreService.shared.fetchFollowersWithTimestamps(userId: userId)
                await MainActor.run {
                    followerTimestamps = Dictionary(uniqueKeysWithValues: items.map { ($0.user.id, $0.timestamp) })
                }
            } catch {
                // Keep default ordering if timestamps fail to load.
            }
        }
    }

    private func loadFollowingTimestampsIfNeeded() {
        guard includesVisits,
              selectedTab == .following,
              currentSortMode == .newest || currentSortMode == .oldest,
              followingTimestamps.isEmpty,
              let userId = Auth.auth().currentUser?.uid else { return }

        Task {
            do {
                let items = try await FirestoreService.shared.fetchFollowingWithTimestamps(userId: userId)
                await MainActor.run {
                    followingTimestamps = Dictionary(uniqueKeysWithValues: items.map { ($0.user.id, $0.timestamp) })
                }
            } catch {
                // Keep default ordering if timestamps fail to load.
            }
        }
    }

    private func loadFollowingInsightsIfNeeded() {
        guard isOwnProfile,
              selectedTab == .following,
              let userId = Auth.auth().currentUser?.uid else { return }

        let authorIds = following.map(\.id)
        guard !authorIds.isEmpty else {
            recentMomentCounts = [:]
            return
        }

        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        Task {
            let counts = await FirestoreService.shared.fetchRecentMomentCounts(for: authorIds, since: since)
            await MainActor.run {
                recentMomentCounts = counts
            }
        }
    }
}

// MARK: - Instagram-style underline tab bar

struct SocialConnectionUnderlineTabBar: View {
    let tabItems: [SocialConnectionTabItem]
    @Binding var selectedIndex: Int
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabItems.enumerated()), id: \.offset) { index, item in
                    tabLabelButton(item: item, index: index)
                        .frame(maxWidth: .infinity)
                }
            }

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(dividerColor)
                    .frame(maxWidth: .infinity, minHeight: 0.5, maxHeight: 0.5)

                GeometryReader { geometry in
                    let tabCount = CGFloat(max(tabItems.count, 1))
                    let tabWidth = geometry.size.width / tabCount
                    let clampedIndex = min(max(selectedIndex, 0), max(tabItems.count - 1, 0))

                    Rectangle()
                        .fill(primaryTextColor)
                        .frame(width: tabWidth, height: 1.5)
                        .offset(x: tabWidth * CGFloat(clampedIndex))
                        .animation(.easeInOut(duration: 0.2), value: selectedIndex)
                }
                .frame(height: 1.5)
            }
            .frame(height: 1.5)
        }
    }

    private func tabLabelButton(item: SocialConnectionTabItem, index: Int) -> some View {
        let isSelected = selectedIndex == index

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedIndex = index
            }
        }) {
            Text(item.title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? primaryTextColor : secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mapping helpers

extension ProfileView.UserListType {
    var socialTab: SocialConnectionTab {
        switch self {
        case .visits: return .visits
        case .followers: return .followers
        case .following: return .following
        case .mutuals: return .mutuals
        }
    }
}

extension UserProfileView.UserListType {
    var socialTab: SocialConnectionTab {
        switch self {
        case .inCommon: return .inCommon
        case .followers: return .followers
        case .following: return .following
        case .mutuals: return .mutuals
        }
    }
}
