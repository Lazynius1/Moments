import SwiftUI
import FirebaseAuth

struct FeedNotificationRoutingModifier: ViewModifier {
    @Binding var showNotifications: Bool
    @Binding var showCreatorView: Bool
    @Binding var showExplore: Bool
    @Binding var zoomDestination: MomentZoomDestination?
    @Binding var zoomResolvedMoment: Moment?

    let notificationSummaryService: NotificationSummaryService
    let badgeService: NotificationBadgeService
    let navigationService: NotificationNavigationService
    let storyRingCoordinator: FeedStoryRingCoordinator
    let firestoreService: FirestoreService
    let onOpenUserProfile: (String) -> Void
    let onOpenStory: (_ storyId: String, _ authorId: String?) -> Void
    let onOpenStoryChain: (_ chainId: String, _ chainTitle: String) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                notificationSummaryService.markAppClosed()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    notificationSummaryService.checkShouldShowSummary(
                        unreadNotifications: badgeService.unreadNotificationsCount,
                        unreadMessages: badgeService.unreadMessagesCount
                    )
                }
            }
            // Mensajes: TabBarView escucha ShowMessages / NavigateToConversation → tab 1.
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNotifications"))) { _ in
                showNotifications = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCreatorView"))) { _ in
                showCreatorView = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowExploreView"))) { _ in
                showExplore = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToNotifications"))) { _ in
                showNotifications = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNotifications"))) { _ in
                showNotifications = true
            }
            .onReceive(navigationService.$pendingNavigation) { navigation in
                guard let navigation else { return }

                switch navigation {
                case .conversation(let conversationId):
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NavigateToConversation"),
                        object: conversationId
                    )
                case .moment(let momentId, let userId):
                    openSharedMoment(momentId: momentId, userId: userId)
                case .profile:
                    break
                case .story(let storyId, let authorId):
                    onOpenStory(storyId, authorId)
                case .notifications:
                    showNotifications = true
                default:
                    break
                }

                navigationService.clearPendingNavigation()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StoryUploaded"))) { _ in
                if let userId = Auth.auth().currentUser?.uid {
                    Task {
                        await storyRingCoordinator.loadStoryUsers(userId: userId, firestoreService: firestoreService)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToUserProfileInFeed"))) { notification in
                if let userId = notification.object as? String, !userId.isEmpty {
                    onOpenUserProfile(userId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToStoryChainInFeed"))) { notification in
                if let userInfo = notification.userInfo,
                   let chainId = userInfo["chainId"] as? String,
                   let chainTitle = userInfo["chainTitle"] as? String {
                    onOpenStoryChain(chainId, chainTitle)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToStoryInFeed"))) { notification in
                guard let userInfo = notification.userInfo,
                      let storyId = userInfo["storyId"] as? String else { return }
                let authorId = (userInfo["authorId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                onOpenStory(storyId, authorId?.isEmpty == false ? authorId : nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMoment"))) { notification in
                guard let momentId = notification.object as? String else { return }
                let userId = notification.userInfo?["userId"] as? String ?? ""
                openSharedMoment(momentId: momentId, userId: userId)
            }
    }

    private func openSharedMoment(momentId: String, userId: String) {
        let momentId = momentId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !momentId.isEmpty else { return }

        if !userId.isEmpty {
            presentSharedMoment(momentId: momentId, authorId: userId)
            return
        }

        firestoreService.fetchMomentAuthorId(momentId: momentId) { authorId in
            DispatchQueue.main.async {
                guard let authorId, !authorId.isEmpty else { return }
                presentSharedMoment(momentId: momentId, authorId: authorId)
            }
        }
    }

    /// Misma presentación que el tap en notificaciones: NavigationStack → SingleMomentDetailView.
    private func presentSharedMoment(momentId: String, authorId: String) {
        firestoreService.fetchMoment(momentId: momentId, userId: authorId) { result in
            DispatchQueue.main.async {
                guard case .success(let moment) = result else { return }
                zoomResolvedMoment = moment
                zoomDestination = MomentZoomDestination(
                    zoomSourceID: ProfileMomentZoomNavigation.sourceID(
                        moment: moment,
                        index: 0,
                        prefix: "shared-moment"
                    ),
                    initialIndex: 0,
                    initialMomentId: moment.id,
                    presentation: .single
                )
                HapticManager.shared.lightImpact()
            }
        }
    }
}

extension View {
    func feedNotificationRouting(
        showNotifications: Binding<Bool>,
        showCreatorView: Binding<Bool>,
        showExplore: Binding<Bool>,
        zoomDestination: Binding<MomentZoomDestination?>,
        zoomResolvedMoment: Binding<Moment?>,
        notificationSummaryService: NotificationSummaryService,
        badgeService: NotificationBadgeService,
        navigationService: NotificationNavigationService,
        storyRingCoordinator: FeedStoryRingCoordinator,
        firestoreService: FirestoreService,
        onOpenUserProfile: @escaping (String) -> Void,
        onOpenStory: @escaping (_ storyId: String, _ authorId: String?) -> Void,
        onOpenStoryChain: @escaping (_ chainId: String, _ chainTitle: String) -> Void
    ) -> some View {
        modifier(
            FeedNotificationRoutingModifier(
                showNotifications: showNotifications,
                showCreatorView: showCreatorView,
                showExplore: showExplore,
                zoomDestination: zoomDestination,
                zoomResolvedMoment: zoomResolvedMoment,
                notificationSummaryService: notificationSummaryService,
                badgeService: badgeService,
                navigationService: navigationService,
                storyRingCoordinator: storyRingCoordinator,
                firestoreService: firestoreService,
                onOpenUserProfile: onOpenUserProfile,
                onOpenStory: onOpenStory,
                onOpenStoryChain: onOpenStoryChain
            )
        )
    }
}
