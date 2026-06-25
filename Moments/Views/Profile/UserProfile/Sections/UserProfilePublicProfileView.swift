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
    @ObservedObject var messagingViewModel: MessagingViewModel
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var socialConnectionsRoute: SocialConnectionsRoute?
    @EnvironmentObject private var heroCoordinator: ProfileGridHeroTransitionCoordinator
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
    let onOpenStories: () -> Void

    @State private var showingFullInfo = false // ✅ NUEVO: Colapsable
    @Binding var selectedTab: UserProfileTabType // ✅ NUEVO: Tab seleccionado (Binding)
    @Namespace private var profileZoomNamespace
    @State private var zoomDestination: ProfileMomentZoomDestination?
    @State private var identityMinY: CGFloat = .greatestFiniteMagnitude
    @State private var tabsMinY: CGFloat = .greatestFiniteMagnitude
    @State private var showingQRCode = false
    @State private var showingReportSheet = false
    @State private var highlightsRefreshToken: Int = 0
    @State private var storyRingRefreshToken: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    private var usernameCollapseProgress: CGFloat {
        ProfileHeaderCollapseMetrics.progress(forTabsMinY: tabsMinY)
    }

    private var tabsArePinned: Bool {
        ProfileHeaderCollapseMetrics.tabsArePinned(tabsMinY: tabsMinY)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
            ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: ProfileHeaderCollapseMetrics.topContentInset)

                    UserModernProfileHeader(
                        viewModel: viewModel,
                        messagingViewModel: messagingViewModel,
                        navigateToChat: $navigateToChat,
                        targetConversation: $targetConversation,
                        socialConnectionsRoute: $socialConnectionsRoute,
                        showingMessageRequestAlert: $showingMessageRequestAlert,
                        messageRequestText: $messageRequestText,
                        messageRequestError: $messageRequestError,
                        showingSuccessMessage: $showingSuccessMessage,
                        showProfileImageFullscreen: $showProfileImageFullscreen,
                        onFollowAction: onFollowAction,
                        onDismiss: onDismiss,
                        onOpenStories: onOpenStories,
                        storyRingRefreshTrigger: storyRingRefreshToken,
                        usernameCollapseProgress: usernameCollapseProgress,
                        showingQRCode: $showingQRCode
                    )
                    .padding(.top, ProfileHeaderCollapseMetrics.headerTopPadding)
                    .padding(.bottom, 4)

                    UserProfileOverviewSection(
                        viewModel: viewModel,
                        socialConnectionsRoute: $socialConnectionsRoute,
                        selectedTab: $selectedTab,
                        showingInterests: $showingFullInfo,
                        interests: viewModel.userProfile?.interests ?? []
                    )
                    .padding(.bottom, 4)

                    // ✅ NUEVO: Destacadas Compactas (Después del bloque social)
                    if let userId = viewModel.userProfile?.id {
                        ProfileHighlightsView(
                            userId: userId,
                            isOwnProfile: false,
                            isCompact: true,
                            refreshTrigger: highlightsRefreshToken
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
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ProfileTabsMinYPreferenceKey.self,
                                        value: geometry.frame(in: .named("profileGridOverlay")).minY
                                    )
                                }
                            )
                            .opacity(tabsArePinned ? 0 : 1)

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
                    highlightsRefreshToken += 1
                    storyRingRefreshToken += 1
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
            .onPreferenceChange(ProfileIdentityMinYPreferenceKey.self) { value in
                identityMinY = value
            }
            .onPreferenceChange(ProfileTabsMinYPreferenceKey.self) { value in
                tabsMinY = value
            }
            .onPreferenceChange(ProfileGridThumbnailFramePreferenceKey.self) { frames in
                heroCoordinator.ingestThumbnailFrames(frames)
            }
            .scrollDisabled(heroCoordinator.isInteractive)
            .profileGridNavigationChrome(colorScheme: colorScheme)
            .scrollClipDisabled()

            ProfileStickyChromeContainer(
                blurProgress: usernameCollapseProgress,
                tabsArePinned: tabsArePinned
            ) {
                ProfileVisitorPinnedTopChrome(
                    viewModel: viewModel,
                    collapseProgress: usernameCollapseProgress,
                    onDismiss: onDismiss,
                    showingQRCode: $showingQRCode,
                    showingReportSheet: $showingReportSheet
                )
            } pinnedTabs: {
                UserProfilePillTabs(selectedTab: $selectedTab)
                    .frame(maxWidth: 240)
            }
            .animation(.easeOut(duration: 0.18), value: tabsArePinned)
            .zIndex(10)
            }
            .coordinateSpace(name: "profileGridOverlay")
            .navigationDestination(item: $socialConnectionsRoute) { route in
                SocialConnectionsScreen(
                    route: route,
                    username: viewModel.userProfile?.username ?? "",
                    availableTabs: SocialConnectionTab.tabs(
                        for: viewModel.visibleConnectionTypes,
                        includesVisits: false
                    ),
                    includesVisits: false,
                    isOwnProfile: false,
                    currentUser: viewModel.viewerProfile,
                    inCommonUsers: viewModel.commonConnections,
                    followers: viewModel.followers,
                    following: viewModel.following,
                    mutuals: viewModel.mutuals,
                    suggestedUsers: viewModel.suggestedConnectionsForViewer,
                    viewerInterests: viewModel.viewerInterests,
                    visitTimestamps: [:],
                    listViewModel: viewModel,
                    profileZoomNamespace: profileZoomNamespace
                )
            }
            .navigationDestination(item: $zoomDestination) { destination in
                ProfileMomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: profileZoomNamespace
                )
            }
            .sheet(isPresented: $showingReportSheet) {
                ReportBottomSheet(
                    userId: viewModel.userId,
                    username: viewModel.userProfile?.username
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                heroCoordinator.openZoomDetail = { zoomDestination = $0 }
                heroCoordinator.clearZoomNavigation = { zoomDestination = nil }
            }
        }
        .profileNavigationSurface(colorScheme: colorScheme)
        .sheet(isPresented: $showingQRCode) {
            QRCodeView(targetUser: viewModel.userProfile)
        }
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
