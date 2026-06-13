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
    @EnvironmentObject private var heroCoordinator: ProfileGridHeroTransitionCoordinator
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
    @Namespace private var profileZoomNamespace
    @State private var zoomDestination: ProfileMomentZoomDestination?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
            ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                .ignoresSafeArea()
                .allowsHitTesting(false)

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
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                    UserProfileOverviewSection(
                        viewModel: viewModel,
                        showingUserList: $showingUserList,
                        showingInterests: $showingFullInfo,
                        interests: viewModel.userProfile?.interests ?? []
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                    // ✅ NUEVO: Destacadas Compactas (Después del bloque social)
                    if let userId = viewModel.userProfile?.id {
                        ProfileHighlightsView(
                            userId: userId,
                            isOwnProfile: false,
                            isCompact: true
                        )
                        .padding(.bottom, 8)
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
                            .padding(.bottom, 4)

                        // Contenido según tab seleccionado
                        switch selectedTab {
                        case .moments:
                            if viewModel.moments.isEmpty {
                                UserModernEmptyMomentsView()
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: UIScreen.main.bounds.width - 40)
                            } else {
                                GeometryReader { geometry in
                                    ProfileMomentsBentoGrid(
                                        moments: viewModel.moments,
                                        availableWidth: geometry.size.width,
                                        descriptors: ProfileBentoTileAssigner.assign(moments: viewModel.moments)
                                    ) { moment, itemWidth, index, descriptor in
                                                ScreenshotProtectedView(
                                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                                ) {
                                                    UserModernMomentThumbnail(
                                                        moment: moment,
                                                        size: itemWidth,
                                                        zoomNamespace: profileZoomNamespace,
                                                        zoomSourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, gridIndex: index),
                                                        onTap: {
                                                            heroCoordinator.openDirectDetail(
                                                                moments: viewModel.moments,
                                                                initialIndex: index,
                                                                feedKind: .userProfileMoments
                                                            )
                                                        },
                                                        onLongPress: {
                                                            openVisitorGridMenu(moment: moment, index: index)
                                                        },
                                                        gridIndex: index,
                                                        descriptor: descriptor
                                                    )
                                                }
                                    }
                                }
                                .frame(height: calculateBentoGridHeight(moments: viewModel.moments))
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
                                        ProfileMomentsBentoGrid(
                                            moments: viewModel.taggedMoments,
                                            availableWidth: geometry.size.width,
                                            descriptors: ProfileBentoTileAssigner.simple(moments: viewModel.taggedMoments)
                                        ) { moment, itemWidth, index, descriptor in
                                            ScreenshotProtectedView(
                                                isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                            ) {
                                                UserModernMomentThumbnail(
                                                    moment: moment,
                                                    size: itemWidth,
                                                    zoomNamespace: profileZoomNamespace,
                                                    zoomSourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, gridIndex: index),
                                                    onTap: {
                                                        heroCoordinator.openDirectDetail(
                                                            moments: viewModel.taggedMoments,
                                                            initialIndex: index,
                                                            feedKind: .userProfileTagged
                                                        )
                                                    },
                                                    onLongPress: {
                                                        openVisitorGridMenu(moment: moment, index: index)
                                                    },
                                                    gridIndex: index,
                                                    descriptor: descriptor
                                                )
                                            }
                                        }
                                    }
                                    .frame(height: calculateTaggedGridHeight(moments: viewModel.taggedMoments))
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

                    _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        Task { @MainActor in
                            if !viewModel.isRefreshing {
                                timer.invalidate()
                                continuation.resume()
                            }
                        }
                    }
                }
            }
            .onPreferenceChange(UserScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .onPreferenceChange(ProfileGridThumbnailFramePreferenceKey.self) { frames in
                heroCoordinator.ingestThumbnailFrames(frames)
            }
            .scrollDisabled(heroCoordinator.isInteractive)
            .profileGridNavigationChrome(colorScheme: colorScheme)
            }
            .coordinateSpace(name: "profileGridOverlay")
            .navigationDestination(item: $zoomDestination) { destination in
                ProfileMomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: profileZoomNamespace
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                heroCoordinator.openZoomDetail = { zoomDestination = $0 }
                heroCoordinator.clearZoomNavigation = { zoomDestination = nil }
            }
        }
        .profileNavigationSurface(colorScheme: colorScheme)
    }

    private func openVisitorGridMenu(moment: Moment, index: Int) {
        heroCoordinator.openMenu(moment: moment, index: index, kind: .visitor)
    }

    private func momentsForZoomDestination(_ destination: ProfileMomentZoomDestination) -> [Moment] {
        switch destination.feedKind {
        case .userProfileMoments:
            return viewModel.moments
        case .userProfileTagged:
            return viewModel.taggedMoments
        default:
            return []
        }
    }
}
