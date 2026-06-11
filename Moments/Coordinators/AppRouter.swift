import SwiftUI

/// Navegación tipada centralizada. Migración incremental desde `NotificationCenter` y
/// `NotificationNavigationService`.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Destination: Equatable {
        case profile(userId: String)
        case moment(id: String, authorId: String)
        case conversation(id: String)
        case story(storyId: String, authorId: String?)
        case storyChain(chainId: String, title: String)
        case followRequests(requestId: String)
        case notifications(filter: String?)
        case creator
        case echoSuggestion(echoId: String)
        case echo(echoId: String)
        case showUserProfile(userId: String)
        case showMessages
        case showNotifications
        case showProfileVisits
        case showStories
        case scrollFeedToTop
        case ownProfileTab
        case userProfileInFeed(userId: String)
        case showExplore
    }

    private(set) var pending: Destination?

    private init() {}

    func navigate(to destination: Destination) {
        pending = destination
        NotificationNavigationService.shared.syncPendingNavigation(from: destination)
    }

    func clearPending() {
        pending = nil
        NotificationNavigationService.shared.clearPendingNavigation()
    }

    func consumePending() -> Destination? {
        defer { pending = nil }
        return pending
    }
}

// MARK: - Tab bar dispatch

struct AppRouterTabBarContext {
    let selectedTab: Binding<Int>
    let showCreatorView: Binding<Bool>
    let pendingEchoId: Binding<String>
    let showEchoInvitation: Binding<Bool>
    let showEchoViewer: Binding<Bool>
    let onEchoInvitationRoute: (String) -> Void
}

extension AppRouter {
    func dispatchPending(using context: AppRouterTabBarContext) {
        guard let destination = pending else { return }

        switch destination {
        case .moment(let momentId, _):
            context.selectedTab.wrappedValue = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToMoment"),
                object: momentId
            )

        case .profile(let userId):
            context.selectedTab.wrappedValue = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToProfile"),
                object: userId
            )

        case .conversation(let conversationId):
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToConversation"),
                object: conversationId
            )

        case .story(let storyId, let authorId):
            context.selectedTab.wrappedValue = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToStoryInFeed"),
                object: nil,
                userInfo: ["storyId": storyId, "authorId": authorId ?? ""]
            )

        case .storyChain(let chainId, let chainTitle):
            context.selectedTab.wrappedValue = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToStoryChain"),
                object: nil,
                userInfo: ["chainId": chainId, "chainTitle": chainTitle]
            )

        case .followRequests(let requestId):
            context.selectedTab.wrappedValue = 4
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToFollowRequests"),
                object: requestId
            )

        case .notifications(let filter):
            context.selectedTab.wrappedValue = 4
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToNotifications"),
                object: filter
            )

        case .creator:
            context.selectedTab.wrappedValue = 0
            context.showCreatorView.wrappedValue = true

        case .echoSuggestion(let echoId):
            context.pendingEchoId.wrappedValue = echoId
            context.showEchoInvitation.wrappedValue = true
            context.onEchoInvitationRoute(echoId)

        case .echo(let echoId):
            context.pendingEchoId.wrappedValue = echoId
            context.showEchoViewer.wrappedValue = true

        case .showUserProfile(let userId):
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowUserProfile"),
                object: userId
            )

        case .showMessages:
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowMessages"),
                object: nil
            )

        case .showNotifications:
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowNotifications"),
                object: nil
            )

        case .showProfileVisits:
            context.selectedTab.wrappedValue = 4
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowProfileVisits"),
                object: nil
            )

        case .showStories:
            context.selectedTab.wrappedValue = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowStories"),
                object: nil
            )

        case .scrollFeedToTop:
            NotificationCenter.default.post(
                name: NSNotification.Name("ScrollFeedToTop"),
                object: nil
            )

        case .ownProfileTab:
            context.selectedTab.wrappedValue = 4

        case .userProfileInFeed(let userId):
            context.selectedTab.wrappedValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NavigateToUserProfileInFeed"),
                    object: userId
                )
            }

        case .showExplore:
            context.selectedTab.wrappedValue = 0
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowExploreView"),
                object: nil
            )
        }

        clearPending()
    }
}

extension AppRouter.Destination {
    var legacyPendingNavigation: NotificationNavigationService.PendingNavigation? {
        switch self {
        case .profile(let userId):
            return .profile(userId)
        case .moment(let id, let authorId):
            return .moment(id, authorId)
        case .conversation(let id):
            return .conversation(id)
        case .story(let storyId, let authorId):
            return .story(storyId: storyId, authorId: authorId)
        case .storyChain(let chainId, let title):
            return .storyChain(chainId, title)
        case .followRequests(let requestId):
            return .followRequests(requestId)
        case .notifications(let filter):
            return .notifications(filter)
        case .creator:
            return .creator
        case .echoSuggestion(let echoId):
            return .echoSuggestion(echoId)
        case .echo(let echoId):
            return .echo(echoId)
        case .showUserProfile, .showMessages, .showNotifications, .showProfileVisits, .showStories, .scrollFeedToTop,
             .ownProfileTab, .userProfileInFeed, .showExplore:
            return nil
        }
    }
}
