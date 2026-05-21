import SwiftUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import FirebaseFirestore
import AVKit

// MARK: - ✅ CORREGIDA: Vista pública moderna
struct UserModernPublicProfileView: View {
    @ObservedObject var viewModel: UserProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    @ObservedObject var messagingViewModel: MessagingViewModel
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var showingUserList: UserProfileView.UserListType?
    @Binding var selectedMoment: Moment?
    @Binding var showMomentDetail: Bool
    @Binding var selectedMomentIndex: Int
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var navigateToChat: Bool
    @Binding var targetConversation: Conversation?
    @Binding var scrollOffset: CGFloat
    @Binding var showingMessageRequestAlert: Bool
    @Binding var messageRequestText: String
    @Binding var messageRequestError: String?
    @Binding var showingSuccessMessage: Bool
    @Binding var showProfileImageFullscreen: Bool
    let onFollowAction: () -> Void
    let onDismiss: () -> Void

    @State private var showingFullInfo = false // ✅ NUEVO: Colapsable
    @Binding var selectedTab: UserProfileTabType // ✅ NUEVO: Tab seleccionado (Binding)

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Header del perfil
                    UserModernProfileHeader(
                        viewModel: viewModel,
                        storyViewModel: storyViewModel,
                        messagingViewModel: messagingViewModel,
                        showStoryViewer: $showStoryViewer,
                        selectedStoryIndex: $selectedStoryIndex,
                        navigateToChat: $navigateToChat,
                        targetConversation: $targetConversation,
                        showingUserList: $showingUserList,
                        showingMessageRequestAlert: $showingMessageRequestAlert,
                        messageRequestText: $messageRequestText,
                        messageRequestError: $messageRequestError,
                        showingSuccessMessage: $showingSuccessMessage,
                        showProfileImageFullscreen: $showProfileImageFullscreen,
                        onFollowAction: onFollowAction,
                        onDismiss: onDismiss
                    )
                    .padding(.top, 10)
                    .padding(.bottom, 20)

                    UserProfileOverviewSection(
                        viewModel: viewModel,
                        showingUserList: $showingUserList,
                        showingInterests: $showingFullInfo,
                        interests: viewModel.userProfile?.interests ?? []
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    // ✅ NUEVO: Destacadas Compactas (Después del bloque social)
                    if let userId = viewModel.userProfile?.id {
                        ProfileHighlightsView(
                            userId: userId,
                            isOwnProfile: false,
                            isCompact: true
                        )
                        .padding(.bottom, 12)
                    }

                    // Indicador de refresh
                    if viewModel.isRefreshing {
                        UserModernRefreshIndicator()
                            .padding(.bottom, 12)
                    }


                    // ✅ CORREGIDO: Sección de momentos con tabs
                    VStack(spacing: 0) {
                        // Pills Tabs
                        UserProfilePillTabs(selectedTab: $selectedTab)
                            .frame(maxWidth: 240)
                            .padding(.bottom, 12)

                        // Contenido según tab seleccionado
                        switch selectedTab {
                        case .moments:
                            if viewModel.moments.isEmpty {
                                UserModernEmptyMomentsView()
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: UIScreen.main.bounds.width - 40)
                            } else {
                                GeometryReader { geometry in
                                    let spacing: CGFloat = 4
                                    let columns = 3
                                    let totalSpacing = spacing * CGFloat(columns - 1) + 16
                                    let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns), spacing: spacing) {
                                        ForEach(Array(viewModel.moments.enumerated()), id: \.offset) { index, moment in
                                            ScreenshotProtectedView(
                                                isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                            ) {
                                                UserModernMomentThumbnail(
                                                    moment: moment,
                                                    size: itemWidth,
                                                    onTap: {
                                                        selectedMomentIndex = index
                                                        showMomentDetail = true
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                                .frame(height: calculateGridHeight(itemCount: viewModel.moments.count))
                            }

                        case .tagged:
                            // Contenido de momentos etiquetados
                            Group {
                                if viewModel.isLoadingTagged {
                                    ProgressView()
                                        .tint(UserProfileColors.textPrimary)
                                        .frame(height: 400)
                                } else if viewModel.taggedMoments.isEmpty {
                                    ProfileSectionEmptyState(
                                        icon: "person.crop.rectangle",
                                        titleKey: "profile.tagged.empty.title",
                                        subtitleKey: "profile.tagged.empty.description"
                                    )
                                    .frame(height: 400, alignment: .top)
                                } else {
                                    GeometryReader { geometry in
                                        let spacing: CGFloat = 4
                                        let columns = 3
                                        let totalSpacing = spacing * CGFloat(columns - 1) + 16
                                        let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

                                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns), spacing: spacing) {
                                            ForEach(Array(viewModel.taggedMoments.enumerated()), id: \.element.id) { index, moment in
                                                ScreenshotProtectedView(
                                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                                ) {
                                                    UserModernMomentThumbnail(
                                                        moment: moment,
                                                        size: itemWidth,
                                                        onTap: {
                                                            selectedMomentIndex = index
                                                            showMomentDetail = true
                                                        }
                                                    )
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                    }
                                    .frame(height: calculateGridHeight(itemCount: viewModel.taggedMoments.count))
                                }
                            }
                            .onAppear {
                                if viewModel.taggedMoments.isEmpty && !viewModel.isLoadingTagged {
                                    viewModel.fetchTaggedMoments()
                                }
                            }
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: UserScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                )
                .padding(.bottom, safeAreaBottom + 120)
            }
            .coordinateSpace(name: "scroll")
            .refreshable {
                await withCheckedContinuation { continuation in
                    viewModel.refreshProfile()

                    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        if !viewModel.isRefreshing {
                            timer.invalidate()
                            continuation.resume()
                        }
                    }
                }
            }
            .onPreferenceChange(UserScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
        }
    }
}
