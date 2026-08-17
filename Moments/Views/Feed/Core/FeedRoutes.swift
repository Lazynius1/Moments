import Foundation

struct FeedProfileSheetRoute: Identifiable, Equatable, Hashable {
    let userId: String

    var id: String { userId }

    var zoomSourceID: String {
        UserProfileZoomNavigation.sourceID(userId: userId)
    }
}

struct FeedEchoInvitationRoute: Identifiable {
    let echoId: String

    var id: String { echoId }
}

struct StoryUserPresentationRoute: Identifiable, Equatable {
    let userId: String
    let startStoryId: String?
    let startElapsed: TimeInterval

    var id: String { userId }

    init(userId: String, startStoryId: String? = nil, startElapsed: TimeInterval = 0) {
        self.userId = userId
        self.startStoryId = startStoryId
        self.startElapsed = startElapsed
    }
}
