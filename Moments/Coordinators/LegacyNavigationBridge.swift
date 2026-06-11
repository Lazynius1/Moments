import SwiftUI

/// Puente temporal para migrar emisores `NotificationCenter` → `AppRouter`.
/// No registrar listeners que el propio `AppRouter.dispatchPending` vuelva a emitir
/// (evita bucles). Migrar call sites directamente a `AppRouter.shared.navigate`.
enum LegacyNavigationBridge {
    static func profile(userId: String) {
        AppRouter.shared.navigate(to: .profile(userId: userId))
    }

    static func moment(id: String, authorId: String = "") {
        AppRouter.shared.navigate(to: .moment(id: id, authorId: authorId))
    }

    static func conversation(id: String) {
        AppRouter.shared.navigate(to: .conversation(id: id))
    }

    static func ownProfileTab() {
        AppRouter.shared.navigate(to: .ownProfileTab)
    }

    static func userProfileInFeed(userId: String) {
        AppRouter.shared.navigate(to: .userProfileInFeed(userId: userId))
    }

    static func showExplore() {
        AppRouter.shared.navigate(to: .showExplore)
    }

    static func showUserProfile(userId: String) {
        AppRouter.shared.navigate(to: .showUserProfile(userId: userId))
    }

    static func showMessages() {
        AppRouter.shared.navigate(to: .showMessages)
    }

    static func showNotifications() {
        AppRouter.shared.navigate(to: .showNotifications)
    }

    static func storyChain(chainId: String, title: String) {
        AppRouter.shared.navigate(to: .storyChain(chainId: chainId, title: title))
    }
}
