import SwiftUI

enum UserProfileZoomNavigation {
    static func sourceID(userId: String) -> String {
        "user-profile-\(userId)"
    }
}

struct UserProfileZoomSourceModifier: ViewModifier {
    let userId: String
    let namespace: Namespace.ID?
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        if let namespace, !userId.isEmpty {
            content.matchedTransitionSource(
                id: UserProfileZoomNavigation.sourceID(userId: userId),
                in: namespace
            ) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
        }
    }
}

extension View {
    func userProfileZoomSource(
        userId: String,
        namespace: Namespace.ID?,
        cornerRadius: CGFloat = 22
    ) -> some View {
        modifier(UserProfileZoomSourceModifier(
            userId: userId,
            namespace: namespace,
            cornerRadius: cornerRadius
        ))
    }

    func userProfileZoomDestination(userId: String, namespace: Namespace.ID) -> some View {
        navigationTransition(
            .zoom(sourceID: UserProfileZoomNavigation.sourceID(userId: userId), in: namespace)
        )
    }
}
