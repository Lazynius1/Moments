#if DEBUG
import Foundation
import FirebaseFirestore

/// Siembra la caché en memoria de Firestore con la red apagada: las escrituras
/// quedan como pendientes locales (nunca se envían) y las lecturas posteriores
/// las ven al instante. Cubre las vistas que leen `users/{id}` y comentarios
/// directamente sin pasar por los ganchos del modo captura.
enum ScreenshotFirestoreSeeder {
    static func seed() {
        guard ScreenshotMode.isActive else { return }
        let db = Firestore.firestore()

        for user in ScreenshotFixtures.allUsers {
            db.collection("users").document(user.id).setData(userDocument(user)) { _ in }
        }

        for thread in ScreenshotFixtures.commentThreads {
            guard let momentId = thread.moment.id else { continue }
            let comments = db.collection("users")
                .document(thread.moment.authorId)
                .collection("moments")
                .document(momentId)
                .collection("comments")
            for comment in thread.comments {
                comments.document(comment.id).setData([
                    "authorId": comment.author.id,
                    "username": comment.author.username,
                    "content": comment.text,
                    "timestamp": Timestamp(date: comment.timestamp),
                    "profileImagePath": comment.author.profileImagePath ?? "",
                    "reactions": [String: [String]](),
                    "mentions": [[String: Any]]()
                ]) { _ in }
            }
        }
    }

    /// Mismos campos que decodifica `AppUser` (el `id` va también como campo).
    private static func userDocument(_ user: AppUser) -> [String: Any] {
        [
            "id": user.id,
            "username": user.username,
            "email": "",
            "interests": [String](),
            "isPlusSubscriber": false,
            "profileImagePath": user.profileImagePath ?? "",
            "blockedUsers": [String](),
            "isPrivate": false,
            "showMutuals": true,
            "showFollowing": true,
            "showFollowers": true,
            "bestFriends": user.bestFriends,
            "followersCount": user.followersCount,
            "followingCount": user.followingCount,
            "momentsCount": user.momentsCount,
            "mutualsCount": 0,
            "profileVisitorsCount": 0,
            "isActive": true,
            "isSuspended": false,
            "ownedBadges": [[String: Any]](),
            "showBadge": true,
            "showPlusBadge": true,
            "isVerified": user.isVerified,
            // En línea en las capturas: chat y bandeja sin el «Desconectado».
            "onlineStatus": "online",
            "isOnline": true,
            "lastSeen": Timestamp(date: Date()),
            "showReadReceipts": true,
            "messageRequestPolicy": "everyone"
        ]
    }
}
#endif
