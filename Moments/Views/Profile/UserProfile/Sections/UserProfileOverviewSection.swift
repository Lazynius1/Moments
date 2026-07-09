import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// MARK: - ✅ NUEVO: Estadísticas modernas como ProfileView
struct UserProfileOverviewSection: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Binding var socialConnectionsRoute: SocialConnectionsRoute?
    @Binding var selectedTab: UserProfileTabType
    @Binding var showingInterests: Bool
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    private var hasVisibleStats: Bool {
        viewModel.canViewContent
            || viewModel.visibleConnectionTypes.canViewFollowers
            || viewModel.visibleConnectionTypes.canViewFollowing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasVisibleStats {
                UserModernStatsSection(
                    viewModel: viewModel,
                    socialConnectionsRoute: $socialConnectionsRoute,
                    selectedTab: $selectedTab,
                    embeddedStyle: true
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }

            if !interests.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showingInterests.toggle()
                    }
                }) {
                    HStack(spacing: 10) {
                        Text("profile.interests.title")
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundColor(UserProfileColors.textPrimary)

                        Text("· \(interests.count)")
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundColor(UserProfileColors.textSecondary)

                        if !showingInterests, let firstInterest = interests.first {
                            Text(firstInterest)
                                .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                                .foregroundColor(UserProfileColors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(UserProfileColors.textSecondary)
                            .rotationEffect(.degrees(showingInterests ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, hasVisibleStats ? 12 : 0)

                if showingInterests {
                    UserModernInterestsView(
                        interests: interests,
                        showsTitle: false,
                        embeddedStyle: true
                    )
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct UserModernStatsSection: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Binding var socialConnectionsRoute: SocialConnectionsRoute?
    @Binding var selectedTab: UserProfileTabType
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme

    private enum StatAction: Hashable {
        case posts
        case social(UserProfileView.UserListType)
    }

    private var postsCount: Int {
        max(viewModel.moments.count, viewModel.userProfile?.momentsCount ?? 0)
    }

    private var computedStats: [(String, Int, StatAction)] {
        var stats: [(String, Int, StatAction)] = []

        if viewModel.canViewContent {
            stats.append((
                NSLocalizedString("profile.ui.posts", comment: "Posts"),
                postsCount,
                .posts
            ))
            stats.append((
                NSLocalizedString("profile.ui.followers", comment: "Followers"),
                viewModel.visibleConnectionTypes.canViewFollowers ? viewModel.followers.count : 0,
                .social(.followers)
            ))
            stats.append((
                NSLocalizedString("profile.ui.following", comment: "Following"),
                viewModel.visibleConnectionTypes.canViewFollowing ? viewModel.following.count : 0,
                .social(.following)
            ))
        } else {
            if viewModel.visibleConnectionTypes.canViewFollowers {
                stats.append((
                    NSLocalizedString("profile.ui.followers", comment: "Followers"),
                    viewModel.followers.count,
                    .social(.followers)
                ))
            }
            if viewModel.visibleConnectionTypes.canViewFollowing {
                stats.append((
                    NSLocalizedString("profile.ui.following", comment: "Following"),
                    viewModel.following.count,
                    .social(.following)
                ))
            }
        }

        return stats
    }

    var body: some View {
        HStack(spacing: embeddedStyle ? 0 : 8) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    switch stat.2 {
                    case .posts:
                        selectedTab = .moments
                    case .social(let listType):
                        socialConnectionsRoute = SocialConnectionsRoute(initialTab: listType.socialTab)
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(MomentsFormat.count(stat.1, style: .profileStat))
                            .font(.system(size: legacyPoppinsSize(embeddedStyle ? 17 : 18), weight: .bold))
                            .foregroundColor(UserProfileColors.textPrimary)

                        Text(stat.0)
                            .font(.system(size: legacyPoppinsSize(embeddedStyle ? 10 : 11), weight: .medium))
                            .foregroundColor(UserProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, embeddedStyle ? 8 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if embeddedStyle && index < computedStats.count - 1 {
                    Rectangle()
                        .fill(UserProfileColors.borderColor.opacity(colorScheme == .dark ? 0.24 : 0.4))
                        .frame(width: 1, height: 26)
                }
            }
        }
        .padding(.horizontal, embeddedStyle ? 2 : 0)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: socialConnectionsRoute), value: socialConnectionsRoute)
    }
}

// MARK: - ✅ NUEVO: Bio expandible
struct UserExpandableBioView: View {
    let bio: String
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bio)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundColor(UserProfileColors.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 3)
                .background(
                    Text(bio)
                        .font(.system(size: legacyPoppinsSize(15)))
                        .lineLimit(3)
                        .background(GeometryReader { geometry in
                            Color.clear.onAppear {
                                DispatchQueue.main.async {
                                    needsExpansion = bio.count > 100 || bio.filter { $0 == "\n" }.count > 2
                                }
                            }
                        })
                        .hidden()
                )
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isExpanded), value: isExpanded)

            if needsExpansion {
                Button(action: {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("userProfile.seeLess", comment: "See less") : NSLocalizedString("userProfile.seeMore", comment: "See more"))
                        .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        .foregroundColor(UserProfileColors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(UserProfileColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ✅ Avatar actualizado
struct UserModernAvatar: View {
    let profileImagePath: String?
    let userId: String // ✅ NUEVO: Agregar userId como parámetro
    let onOpenStories: () -> Void
    let size: CGFloat
    var showStoryRing: Bool = true
    var refreshTrigger: Int = 0

    var body: some View {
        Group {
            if showStoryRing {
                StoryRingAvatarView(
                    userId: userId,
                    size: size,
                    lineWidth: 3,
                    refreshTrigger: refreshTrigger,
                    isOwnStory: userId == Auth.auth().currentUser?.uid,
                    onTap: { hasStory in
                        if hasStory {
                            onOpenStories()
                        }
                    }
                )
            } else {
                AsyncProfileImageView(userId: userId)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - ✅ NUEVO: Intereses modernos como ProfileView
struct UserModernInterestsView: View {
    let interests: [String]
    var showsTitle: Bool = true
    var embeddedStyle: Bool = false
    @State private var currentUserInterests: [String] = []
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                Text("userProfile.interests")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundColor(UserProfileColors.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(interests, id: \.self) { interest in
                        let emoji = interestEmoji(for: interest)
                        let isShared = currentUserInterests.contains(interest)

                        HStack(spacing: 6) {
                            Text(emoji)
                                .font(.system(size: 16))
                            Text(interest)
                                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                .foregroundColor(isShared ? .white : UserProfileColors.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, embeddedStyle ? 9 : 10)
                        .background(
                            isShared ?
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [embeddedStyle ? UserProfileColors.materialBackground.opacity(0.62) : UserProfileColors.cardBackground, embeddedStyle ? UserProfileColors.materialBackground.opacity(0.62) : UserProfileColors.cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(UserProfileColors.borderColor.opacity(embeddedStyle && !isShared ? 0.18 : 0), lineWidth: embeddedStyle && !isShared ? 1 : 0)
                        )
                        .shadow(
                            color: isShared ? Color.blue.opacity(0.3) : UserProfileColors.shadowColor,
                            radius: isShared ? 6 : (embeddedStyle ? 0 : 4),
                            x: 0,
                            y: isShared ? 3 : (embeddedStyle ? 0 : 2)
                        )
                        .scaleEffect(isShared ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isShared)
                    }
                }
                .padding(.horizontal, embeddedStyle ? 20 : 0)
            }
            .scrollClipDisabled(embeddedStyle)
        }
        .onAppear {
            loadCurrentUserInterests()
        }
    }

    private func loadCurrentUserInterests() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        FirestoreService().db.collection("users").document(currentUserId).getDocument { document, error in
            if let data = document?.data(),
               let userInterests = data["interests"] as? [String] {
                DispatchQueue.main.async {
                    self.currentUserInterests = userInterests
                }
            }
        }
    }

    private func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}
