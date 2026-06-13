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
    @Binding var showingUserList: UserProfileView.UserListType?
    @Binding var showingInterests: Bool
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.canViewConnections {
                UserModernStatsSection(
                    viewModel: viewModel,
                    showingUserList: $showingUserList,
                    embeddedStyle: true
                )
                .frame(maxWidth: .infinity)
            }

            if !interests.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showingInterests.toggle()
                    }
                }) {
                    HStack(spacing: 10) {
                        Text("profile.interests.title")
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(UserProfileColors.textPrimary)

                        Text("· \(interests.count)")
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(UserProfileColors.textSecondary)

                        if !showingInterests, let firstInterest = interests.first {
                            Text(firstInterest)
                                .font(.custom("Poppins-Medium", size: 11))
                                .foregroundColor(UserProfileColors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(UserProfileColors.textSecondary)
                            .rotationEffect(.degrees(showingInterests ? 180 : 0))
                    }
                    .padding(.top, viewModel.canViewConnections ? 12 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showingInterests {
                    UserModernInterestsView(
                        interests: interests,
                        showsTitle: false,
                        embeddedStyle: true
                    )
                    .padding(.top, 10)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

struct UserModernStatsSection: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @Binding var showingUserList: UserProfileView.UserListType?
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme

    private var computedStats: [(String, Int, UserProfileView.UserListType)] {
        [
            (NSLocalizedString("profile.ui.followers", comment: "Followers"), viewModel.admirers.count, .admirers),
            (NSLocalizedString("profile.ui.following", comment: "Following"), viewModel.connections.count, .connections),
            (NSLocalizedString("profile.ui.mutuals", comment: "Mutuals"), viewModel.mutualConnections.count, .mutualConnections)
        ]
    }

    var body: some View {
        HStack(spacing: embeddedStyle ? 0 : 8) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    showingUserList = stat.2
                }) {
                    VStack(spacing: 4) {
                        Text("\(stat.1)")
                            .font(.custom("Poppins-Bold", size: embeddedStyle ? 17 : 18))
                            .foregroundColor(UserProfileColors.textPrimary)

                        Text(stat.0)
                            .font(.custom("Poppins-Medium", size: embeddedStyle ? 10 : 11))
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
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingUserList)
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
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(UserProfileColors.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 3)
                .background(
                    Text(bio)
                        .font(.custom("Poppins-Regular", size: 15))
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
                .animation(.easeInOut(duration: 0.3), value: isExpanded)

            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("userProfile.seeLess", comment: "See less") : NSLocalizedString("userProfile.seeMore", comment: "See more"))
                        .font(.custom("Poppins-Medium", size: 13))
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
    @ObservedObject var storyViewModel: StoryViewModel
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme

    private var hasStory: Bool {
        // ✅ CORREGIDO: Usar userId en lugar de profileImagePath
        return !(storyViewModel.stories[userId]?.isEmpty ?? true)
    }

    private var storyCount: Int {
        return storyViewModel.stories[userId]?.count ?? 0
    }

    private var storyViewedStatus: [Bool] {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let userStories = storyViewModel.stories[userId] else {
            return []
        }

        return userStories.map { story in
            guard let storyId = story.id else { return false }
            let viewers = storyViewModel.storyViewers[storyId] ?? []
            return viewers.contains { $0.userId == currentUserId }
        }
    }

    private var storyAudiences: [String?] {
        return storyViewModel.stories[userId]?.map { $0.audience } ?? []
    }

    private var isOwnStory: Bool {
        return userId == Auth.auth().currentUser?.uid
    }

    var body: some View {
        ZStack {
            if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: size, height: size)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: size * 0.45))
                                    .foregroundColor(.gray.opacity(0.6))
                            )
                            .overlay(ProgressView().tint(Color(hex: "007AFF")))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill) // ✅ CLAVE: aspectRatio en lugar de scaledToFill
                    .frame(width: size, height: size) // ✅ CLAVE: Frame fijo
                    .clipShape(Circle()) // ✅ CLAVE: Clip después del frame
                    .contentShape(Circle()) // ✅ CLAVE: ContentShape para touch
                    .overlay(
                        StorySegmentedRing(
                            storyCount: storyCount,
                            hasStory: hasStory,
                            hasUnseenStory: !storyViewedStatus.allSatisfy { $0 },
                            storyViewedStatus: storyViewedStatus,
                            storyAudiences: storyAudiences,
                            isOwnStory: isOwnStory,
                            colorScheme: colorScheme,
                            ringSize: size,
                            lineWidth: 3
                        )
                    )
                    .shadow(color: Color(hex: "007AFF").opacity(0.2), radius: 15, x: 0, y: 8)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: size * 0.6))
                            .foregroundColor(.gray.opacity(0.6))
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.clear, Color.clear], // ✅ QUITADO: Borde verde
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0 // ✅ QUITADO: Borde
                            )
                    )
                    .shadow(color: Color(hex: "007AFF").opacity(0.15), radius: 12, x: 0, y: 6)
            }
        }
        .onTapGesture {
            if hasStory {
                showStoryViewer = true
                selectedStoryIndex = 0
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
                    .font(.custom("Poppins-SemiBold", size: 18))
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
                                .font(.custom("Poppins-Medium", size: 14))
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
                .padding(.horizontal, 20)
            }
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
