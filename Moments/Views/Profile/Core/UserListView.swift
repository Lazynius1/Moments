import SwiftUI

@MainActor
protocol UserListViewModel {
    func followUser(userId: String)
    func unfollowUser(userId: String)
    func cancelFollowRequest(userId: String)
    func relationshipState(for userId: String) -> FollowButtonState
    func prefetchRelationshipState(for userId: String)
}

final class EmptyUserListViewModel: UserListViewModel, ObservableObject {
    func followUser(userId: String) {}
    func unfollowUser(userId: String) {}
    func cancelFollowRequest(userId: String) {}
    func relationshipState(for userId: String) -> FollowButtonState { .canFollow }
    func prefetchRelationshipState(for userId: String) {}
}

enum UserListRowAction {
    case follow
    case unfollow
    case none
}

// MARK: - Embedded users tab (SocialConnectionsView)

struct UsersTabContent<ViewModel: UserListViewModel>: View {
    let title: String
    let users: [AppUser]
    let visitTimestamps: [String: [Date]]
    let searchText: String
    var sortMode: SocialConnectionsSortMode = .default
    var followerTimestamps: [String: Date] = [:]
    var followingTimestamps: [String: Date] = [:]
    let rowAction: UserListRowAction
    var activeTab: SocialConnectionTab = .followers
    var includesVisits: Bool = false
    var isOwnProfile: Bool = true
    var isListHiddenFromViewer: Bool = false
    let viewModel: ViewModel
    let onUserTap: ((AppUser) -> Void)?
    var profileZoomNamespace: Namespace.ID? = nil
    var rowConfiguration: SocialConnectionRowConfiguration? = nil
    var recentMomentCounts: [String: Int] = [:]
    var onViewSharedActivity: ((AppUser) -> Void)? = nil
    var onRemoveFollower: ((AppUser) -> Void)? = nil
    var onAvatarTap: ((String, Bool) -> Void)? = nil
    var mutualUserIds: Set<String> = []
    var onRefresh: (() async -> Void)? = nil
    var usesOwnScroll: Bool = true
    @Environment(\.colorScheme) var colorScheme

    private var filteredUsers: [AppUser] {
        let base: [AppUser]
        if searchText.isEmpty {
            base = users
        } else {
            base = users.filter { user in
                user.username.localizedCaseInsensitiveContains(searchText) ||
                (user.bio?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return SocialConnectionsSorting.sortUsers(
            base,
            mode: sortMode,
            timestamps: activeTab == .followers ? followerTimestamps : (activeTab == .following ? followingTimestamps : [:])
        )
    }

    var body: some View {
        Group {
            if usesOwnScroll {
                if filteredUsers.isEmpty {
                    if users.isEmpty {
                        refreshableScroll(minHeight: 400) {
                            emptyStateView
                        }
                    } else {
                        refreshableScroll(minHeight: 400) {
                            SocialConnectionsNoResultsView(colorScheme: colorScheme)
                        }
                    }
                } else {
                    refreshableScroll {
                        userListContent
                    }
                }
            } else {
                embeddedListContent
            }
        }
    }

    @ViewBuilder
    private var embeddedListContent: some View {
        if filteredUsers.isEmpty {
            if users.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, minHeight: 400, alignment: .center)
            } else {
                SocialConnectionsNoResultsView(colorScheme: colorScheme)
                    .frame(maxWidth: .infinity, minHeight: 400, alignment: .center)
            }
        } else {
            userListContent
        }
    }

    private var userListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredUsers) { user in
                SocialConnectionUserRow(
                    user: user,
                    subtitle: nil,
                    viewModel: viewModel,
                    onUserTap: onUserTap,
                    profileZoomNamespace: profileZoomNamespace,
                    activeTab: activeTab,
                    includesVisits: includesVisits,
                    configuration: rowConfiguration ?? .init(
                        showsRemoveFollower: false,
                        showsRelationshipButton: rowAction != .none,
                        showsOverflowMenu: rowAction == .unfollow,
                        showsFollowBackHint: false,
                        showsBio: true,
                        showsNewPosts: false
                    ),
                    newContentCount: recentMomentCounts[user.id],
                    onViewSharedActivity: onViewSharedActivity,
                    onRemoveFollower: onRemoveFollower,
                    onAvatarTap: onAvatarTap,
                    isMutual: mutualUserIds.contains(user.id)
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func refreshableScroll<Content: View>(minHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        if let onRefresh {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: minHeight ?? 0, alignment: .center)
            }
            .momentRefresh {
                await onRefresh()
            }
        } else {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: minHeight ?? 0, alignment: .center)
            }
        }
    }

    private var emptyStateView: some View {
        let content = emptyStateContent()
        let iconColor = colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.88)

        return VStack(spacing: 20) {
            Image(systemName: content.icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.monochrome)

            VStack(spacing: 8) {
                Text(content.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text(content.description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
        .momentsEmptyStateAppear()
    }

    private struct UserListEmptyStateContent {
        let title: String
        let description: String
        let icon: String
    }

    private func emptyStateContent() -> UserListEmptyStateContent {
        if isListHiddenFromViewer {
            switch activeTab {
            case .followers:
                return UserListEmptyStateContent(
                    title: NSLocalizedString("userListView.empty.hidden.followers.title", comment: "Hidden followers title"),
                    description: NSLocalizedString("userListView.empty.hidden.followers.description", comment: "Hidden followers description"),
                    icon: "eye.slash"
                )
            case .following:
                return UserListEmptyStateContent(
                    title: NSLocalizedString("userListView.empty.hidden.following.title", comment: "Hidden following title"),
                    description: NSLocalizedString("userListView.empty.hidden.following.description", comment: "Hidden following description"),
                    icon: "eye.slash"
                )
            default:
                break
            }
        }

        if !isOwnProfile {
            switch activeTab {
            case .followers:
                return UserListEmptyStateContent(
                    title: NSLocalizedString("userListView.empty.visitor.followers.title", comment: "Visitor empty followers title"),
                    description: NSLocalizedString("userListView.empty.visitor.followers.description", comment: "Visitor empty followers description"),
                    icon: "person.2"
                )
            case .following:
                return UserListEmptyStateContent(
                    title: NSLocalizedString("userListView.empty.visitor.following.title", comment: "Visitor empty following title"),
                    description: NSLocalizedString("userListView.empty.visitor.following.description", comment: "Visitor empty following description"),
                    icon: "person.2"
                )
            case .mutuals:
                return UserListEmptyStateContent(
                    title: NSLocalizedString("userListView.empty.visitor.mutuals.title", comment: "Visitor empty mutuals title"),
                    description: NSLocalizedString("userListView.empty.visitor.mutuals.description", comment: "Visitor empty mutuals description"),
                    icon: "arrow.triangle.2.circlepath"
                )
            default:
                break
            }
        }

        return UserListEmptyStateContent(
            title: String(format: NSLocalizedString("userListView.empty.title", comment: "Empty state title"), title.lowercased()),
            description: String(format: NSLocalizedString("userListView.empty.description", comment: "Empty state description"), title.lowercased()),
            icon: emptyStateIcon(for: activeTab)
        )
    }

    private func emptyStateIcon(for tab: SocialConnectionTab) -> String {
        switch tab {
        case .visits: return "eye.slash"
        case .followers, .following: return "person.2"
        case .mutuals: return "arrow.triangle.2.circlepath"
        case .inCommon: return "person.2"
        }
    }
}

struct CommonConnectionsTabContent<ViewModel: UserListViewModel>: View {
    let commonUsers: [AppUser]
    let suggestedUsers: [AppUser]
    let viewerInterests: [String]
    let viewModel: ViewModel
    let onUserTap: ((AppUser) -> Void)?
    var onAvatarTap: ((String, Bool) -> Void)? = nil
    var profileZoomNamespace: Namespace.ID? = nil
    var onRefresh: (() async -> Void)? = nil
    var usesOwnScroll: Bool = true
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            if usesOwnScroll {
                if commonUsers.isEmpty && suggestedUsers.isEmpty {
                    refreshableScroll(minHeight: 400) {
                        SocialConnectionsNoResultsView(colorScheme: colorScheme)
                    }
                } else {
                    refreshableScroll {
                        commonConnectionsContent
                    }
                }
            } else if commonUsers.isEmpty && suggestedUsers.isEmpty {
                SocialConnectionsNoResultsView(colorScheme: colorScheme)
                    .frame(maxWidth: .infinity, minHeight: 400, alignment: .center)
            } else {
                commonConnectionsContent
            }
        }
    }

    private var commonConnectionsContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if !commonUsers.isEmpty {
                sectionHeader(NSLocalizedString("socialConnections.common.section.people", comment: ""))

                ForEach(commonUsers) { user in
                    SocialConnectionUserRow(
                        user: user,
                        subtitle: nil,
                        viewModel: viewModel,
                        onUserTap: onUserTap,
                        profileZoomNamespace: profileZoomNamespace,
                        activeTab: .inCommon,
                        configuration: .init(
                            showsRemoveFollower: false,
                            showsRelationshipButton: true,
                            showsOverflowMenu: false,
                            showsFollowBackHint: false,
                            showsBio: true,
                            showsNewPosts: false
                        ),
                        onAvatarTap: onAvatarTap
                    )
                }
            }

            if !suggestedUsers.isEmpty {
                sectionHeader(NSLocalizedString("explore.suggestedUsers.suggestedForYou", comment: ""))

                ForEach(suggestedUsers) { user in
                    SuggestedUserRow(
                        user: user,
                        commonInterests: Set(user.interests).intersection(Set(viewerInterests)).count,
                        buttonState: viewModel.relationshipState(for: user.id),
                        profileZoomNamespace: profileZoomNamespace,
                        onFollow: {
                            let state = viewModel.relationshipState(for: user.id)
                            if state == .canFollow || state == .canRequestFollow {
                                viewModel.followUser(userId: user.id)
                            } else if state == .requestPendingCancellable {
                                viewModel.cancelFollowRequest(userId: user.id)
                            }
                        },
                        onTap: {
                            onUserTap?(user)
                        }
                    )
                    .onAppear {
                        viewModel.prefetchRelationshipState(for: user.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func refreshableScroll<Content: View>(minHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        if let onRefresh {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: minHeight ?? 0, alignment: .center)
            }
            .momentRefresh {
                await onRefresh()
            }
        } else {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: minHeight ?? 0, alignment: .center)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }
}

struct SocialConnectionsNoResultsView: View {
    let colorScheme: ColorScheme

    var body: some View {
        let iconColor = colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.88)

        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.monochrome)

            VStack(spacing: 8) {
                Text(NSLocalizedString("userListView.noResults.title", comment: "No results title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text(NSLocalizedString("userListView.noResults.description", comment: "No results description"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

struct UserListView<ViewModel: UserListViewModel>: View {
    let title: String
    let users: [AppUser]
    let visitTimestamps: [String: [Date]]
    let viewModel: ViewModel
    let onDismiss: () -> Void
    let rowAction: UserListRowAction
    let onUserTap: ((AppUser) -> Void)?
    var profileZoomNamespace: Namespace.ID? = nil
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            headerView
            searchBarView
            UsersTabContent(
                title: title,
                users: users,
                visitTimestamps: visitTimestamps,
                searchText: searchText,
                rowAction: rowAction,
                viewModel: viewModel,
                onUserTap: onUserTap,
                profileZoomNamespace: profileZoomNamespace
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // ✅ Header actualizado sin padding extra del handle
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Text("\(users.count) \(users.count == 1 ? NSLocalizedString("userListView.person.singular", comment: "Person singular") : NSLocalizedString("userListView.person.plural", comment: "Person plural"))")
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
    
    // ✅ Searchbar para buscar usuarios
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
                .font(.system(size: 16))

            TextField(NSLocalizedString("userListView.search.placeholder", comment: "Search users placeholder"), text: $searchText)
                .font(.system(size: legacyPoppinsSize(16)))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .textFieldStyle(PlainTextFieldStyle())

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .momentsChromeGlass(in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// ✅ Fila de usuario modernizada con el estilo del ContextMenu
struct ModernProfileUserRowView<ViewModel: UserListViewModel>: View {
    let user: AppUser
    let visitTimestamps: [Date]
    let rowAction: UserListRowAction
    let viewModel: ViewModel
    let onDismiss: () -> Void
    let onUserTap: ((AppUser) -> Void)?
    var profileZoomNamespace: Namespace.ID? = nil
    
    @State private var isPressed: Bool = false
    @State private var showingUnfollowConfirmation = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // ✅ Avatar con anillo de historias y carga async consistente
            avatarView
            
            // ✅ Información del usuario
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(user.username)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    if user.isVerified {
                        VerifiedBadge(size: 14)
                    }
                }
                
                // Bio o información adicional
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        .lineLimit(1)
                }
                
                // ✅ Indicador de visitas frecuentes modernizado
                if shouldShowFrequentVisitsIndicator() {
                    frequentVisitsIndicator
                }
            }
            
            Spacer()
            
            // ✅ Botón de acción modernizado
            actionButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            (colorScheme == .dark ? Color.white : Color.black)
                .opacity(isPressed ? 0.06 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { openUserProfile() }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        })
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                viewModel.unfollowUser(userId: user.id)
                FollowStateStore.shared.setState(.canFollow, for: user.id)
                withAnimation(.easeOut(duration: 0.3)) {
                    onDismiss()
                }
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
    }
    
    // ✅ Avatar con círculo de fondo igual que el ContextMenu
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "007AFF").opacity(0.15))
                .frame(width: 48, height: 48)
            
            StoryRingAvatarView(
                userId: user.id,
                size: 44,
                lineWidth: 2.1,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                baseStrokeWidth: 0.9,
                profileZoomNamespace: profileZoomNamespace
            )
        }
    }
    
    // ✅ Indicador de visitas frecuentes con el estilo del ContextMenu
    private var frequentVisitsIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
            
            Text(NSLocalizedString("userListView.frequentVisits", comment: "Frequent visits indicator"))
                .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // ✅ Botón de acción con el estilo del ContextMenu
    private var actionButton: some View {
        Group {
            if rowAction == .follow {
                Button(action: {
                    viewModel.followUser(userId: user.id)
                    FollowStateStore.shared.setState(.following, for: user.id)
                    withAnimation(.easeOut(duration: 0.3)) {
                        onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                        Text(NSLocalizedString("userListView.followButton", comment: "Follow button"))
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
                }
            } else if rowAction == .unfollow {
                Button(action: {
                    showingUnfollowConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 12, weight: .medium))
                        Text(NSLocalizedString("userListView.unfollowButton", comment: "Unfollow button"))
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
                }
            } else {
                // ✅ Chevron para otros casos
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
    }
    
    private func shouldShowFrequentVisitsIndicator() -> Bool {
        return visitTimestamps.count >= 3 &&
               visitTimestamps.allSatisfy { Date().timeIntervalSince($0) < 24 * 3600 }
    }

    private func openUserProfile() {
        if let onUserTap {
            onUserTap(user)
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            onDismiss()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            LegacyNavigationBridge.profile(userId: user.id)
        }
    }
}
