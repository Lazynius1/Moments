import SwiftUI
import FirebaseAuth

struct FeedNotificationRoutingModifier: ViewModifier {
    @Binding var showMessages: Bool
    @Binding var showNotifications: Bool
    @Binding var showCreatorView: Bool
    @Binding var showExplore: Bool
    @Binding var showMomentDetail: Bool
    @Binding var targetConversationId: String?
    @Binding var targetMomentId: String?
    @Binding var targetMomentUserId: String?

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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowMessages"))) { _ in
                showMessages = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowNotifications"))) { _ in
                showNotifications = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCreatorView"))) { _ in
                showCreatorView = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowExploreView"))) { _ in
                showExplore = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNotifications"))) { _ in
                showNotifications = true
            }
            .onReceive(navigationService.$pendingNavigation) { navigation in
                guard let navigation else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    switch navigation {
                    case .conversation(let conversationId):
                        targetConversationId = conversationId
                        showMessages = true
                    case .moment(let momentId, let userId):
                        targetMomentId = momentId
                        targetMomentUserId = userId
                        showMomentDetail = true
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConversation"))) { notification in
                guard let conversationId = notification.object as? String,
                      !conversationId.isEmpty else { return }
                targetConversationId = conversationId
                showMessages = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMoment"))) { notification in
                guard let momentId = notification.object as? String,
                      !momentId.isEmpty else { return }

                if let userId = notification.userInfo?["userId"] as? String, !userId.isEmpty {
                    targetMomentId = momentId
                    targetMomentUserId = userId
                    showMomentDetail = true
                    return
                }

                firestoreService.fetchMomentAuthorId(momentId: momentId) { authorId in
                    DispatchQueue.main.async {
                        guard let authorId, !authorId.isEmpty else { return }
                        targetMomentId = momentId
                        targetMomentUserId = authorId
                        showMomentDetail = true
                    }
                }
            }
    }
}

extension View {
    func feedNotificationRouting(
        showMessages: Binding<Bool>,
        showNotifications: Binding<Bool>,
        showCreatorView: Binding<Bool>,
        showExplore: Binding<Bool>,
        showMomentDetail: Binding<Bool>,
        targetConversationId: Binding<String?>,
        targetMomentId: Binding<String?>,
        targetMomentUserId: Binding<String?>,
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
                showMessages: showMessages,
                showNotifications: showNotifications,
                showCreatorView: showCreatorView,
                showExplore: showExplore,
                showMomentDetail: showMomentDetail,
                targetConversationId: targetConversationId,
                targetMomentId: targetMomentId,
                targetMomentUserId: targetMomentUserId,
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
