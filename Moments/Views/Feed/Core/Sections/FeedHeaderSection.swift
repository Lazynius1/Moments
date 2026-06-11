import SwiftUI
import FirebaseAuth

struct FeedRefreshIndicator: View {
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                .scaleEffect(0.72)

            Text("feed.refreshing")
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.74) : .black.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(in: Capsule(), interactive: false)
    }
}

struct FeedHeaderBar: View {
    @Binding var showCreatorView: Bool
    @Binding var showNotifications: Bool
    @Binding var showMessages: Bool
    @Binding var showEchoHistory: Bool
    @Binding var showPendingEchoInvitation: Bool
    @Binding var selectedPendingEchoId: String
    @Binding var pendingEchoInvitationRoute: FeedEchoInvitationRoute?

    @ObservedObject var storyRingCoordinator: FeedStoryRingCoordinator
    @ObservedObject var storyUploadService: BackgroundStoryUploadService
    @ObservedObject var badgeService: NotificationBadgeService

    let colorScheme: ColorScheme
    let pendingEchoes: [Echo]
    let onOpenStory: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if storyRingCoordinator.isLoadingStories && storyRingCoordinator.storyUsers.isEmpty {
                StoryRingTraySkeletonRow(colorScheme: colorScheme)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        YourStoryCircleWithProgress(
                            hasStory: storyRingCoordinator.storyUsers.first?.userId == Auth.auth().currentUser?.uid
                                ? (storyRingCoordinator.storyUsers.first?.hasStory ?? false) : false,
                            storyCount: storyRingCoordinator.storyUsers.first?.userId == Auth.auth().currentUser?.uid
                                ? (storyRingCoordinator.storyUsers.first?.storyCount ?? 0) : 0,
                            storyAudiences: storyRingCoordinator.storyUsers.first?.userId == Auth.auth().currentUser?.uid
                                ? (storyRingCoordinator.storyUsers.first?.storyAudiences ?? []) : [],
                            colorScheme: colorScheme,
                            storyUploadService: storyUploadService
                        ) {
                            if let currentUserId = Auth.auth().currentUser?.uid,
                               storyRingCoordinator.storyUsers.first?.hasStory == true,
                               storyRingCoordinator.storyUsers.first?.userId == currentUserId {
                                onOpenStory(currentUserId)
                            } else {
                                showCreatorView = true
                            }
                        }

                        ForEach(Array(storyRingCoordinator.storyUsers.dropFirst().enumerated()), id: \.element.userId) { index, storyUser in
                            RealStoryCircle(
                                userId: storyUser.userId,
                                fallbackUsername: "",
                                hasStory: storyUser.hasStory,
                                hasUnseenStory: storyUser.hasUnseenStory,
                                storyCount: storyUser.storyCount,
                                storyViewedStatus: storyUser.storyViewedStatus,
                                storyAudiences: storyUser.storyAudiences,
                                isOwnStory: false,
                                colorScheme: colorScheme
                            ) {
                                guard !storyUser.userId.isEmpty else { return }
                                onOpenStory(storyUser.userId)
                            }
                            .onAppear {
                                if let currentUserId = Auth.auth().currentUser?.uid {
                                    storyRingCoordinator.loadMoreRingUsersIfNeeded(
                                        visibleIndex: index + 1,
                                        currentUserId: currentUserId
                                    )
                                }
                            }
                        }

                        if storyRingCoordinator.isLoadingMoreRing {
                            StoryRingTrayLoadingTail(colorScheme: colorScheme)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                }
            }

            Spacer()

            HStack(spacing: 20) {
                if !pendingEchoes.isEmpty {
                    Menu {
                        Button(NSLocalizedString("feed.echo.actions.viewInvitations", comment: "View pending invitations")) {
                            if let firstPending = pendingEchoes.first, let echoId = firstPending.id {
                                selectedPendingEchoId = echoId
                                showPendingEchoInvitation = true
                                pendingEchoInvitationRoute = FeedEchoInvitationRoute(echoId: echoId)
                            }
                        }
                        Button(NSLocalizedString("feed.echo.actions.viewHistory", comment: "View echo history")) {
                            showEchoHistory = true
                        }
                    } label: {
                        echoApertureIcon
                    }
                } else {
                    Button(action: { showEchoHistory = true }) {
                        echoApertureIcon
                    }
                }

                ModernNotificationButton(
                    hasNotification: badgeService.unreadNotificationsCount > 0,
                    colorScheme: colorScheme,
                    action: {
                        NotificationService.shared.markAllAsRead()
                        NotificationBadgeService.shared.clearNotificationBadge()
                        showNotifications = true
                    }
                )

                ModernMessageButton(
                    hasMessage: badgeService.unreadMessagesCount > 0,
                    messageCount: badgeService.unreadMessagesCount,
                    colorScheme: colorScheme,
                    action: { showMessages = true }
                )
            }
            .padding(.trailing, 12)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea(edges: .top)
        )
    }

    private var echoApertureIcon: some View {
        ZStack(alignment: .topTrailing) {
            EchoesIconView(
                size: EchoesIconMetrics.feedToolbar,
                gradient: EchoesIconView.echoesBrandGradientHorizontal
            )
            .frame(width: 36, height: 36, alignment: .center)

            if !pendingEchoes.isEmpty {
                Text("\(pendingEchoes.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .offset(x: 5, y: -5)
                    .transition(.scale)
            }
        }
    }
}

struct FeedFloatingSelector: View {
    @Binding var selectedFeedType: FeedType
    @Binding var isManualRefreshing: Bool

    @Bindable var viewModel: FeedViewModel

    let colorScheme: ColorScheme
    let floatingSelectorTopInset: CGFloat
    let isFeedHeaderHidden: Bool
    let pendingEchoesCount: Int

    var body: some View {
        VStack {
            Spacer()
                .frame(height: floatingSelectorTopInset)

            FloatingGlassFeedToggle(selectedFeedType: $selectedFeedType)

            if isManualRefreshing {
                FeedRefreshIndicator(colorScheme: colorScheme)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isFeedHeaderHidden)
        .onChange(of: selectedFeedType) { _, newFeedType in
            UserDefaults.standard.selectedFeedType = newFeedType
            if let userId = Auth.auth().currentUser?.uid {
                viewModel.switchFeedType(to: newFeedType, userId: userId)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pendingEchoesCount)
        .zIndex(998)
    }
}
