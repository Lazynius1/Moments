struct FeedProfileSheetRoute: Identifiable, Equatable {
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

    var id: String { userId }
}
