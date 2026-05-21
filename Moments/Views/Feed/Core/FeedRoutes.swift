struct FeedProfileSheetRoute: Identifiable, Equatable {
    let userId: String

    var id: String { userId }
}

struct FeedEchoInvitationRoute: Identifiable {
    let echoId: String

    var id: String { echoId }
}
