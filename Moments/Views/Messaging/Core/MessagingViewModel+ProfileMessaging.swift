import Foundation

extension MessagingViewModel {
    struct ProfileMessagePresentation {
        enum Destination {
            case conversation(Conversation)
            case pendingChat(PendingChatContext)
        }

        let destination: Destination
    }

    /// Resuelve la navegación de chat desde perfiles tras `startConversation`.
    /// El flujo v2 publica el destino en `presentationRoute` y deja `requiresMessageRequest` en `false`.
    func consumeProfileMessagePresentation(
        conversation: Conversation?,
        for user: AppUser,
        from currentUserId: String,
        followersCountOverride: Int? = nil,
        momentsCountOverride: Int? = nil
    ) async -> ProfileMessagePresentation? {
        if let conversation {
            presentationRoute = nil
            return ProfileMessagePresentation(destination: .conversation(conversation))
        }

        if let route = presentationRoute {
            presentationRoute = nil
            switch route {
            case .conversation(let resolvedConversation):
                return ProfileMessagePresentation(destination: .conversation(resolvedConversation))
            case .pendingChat(let context):
                return ProfileMessagePresentation(destination: .pendingChat(context))
            }
        }

        if let errorMessage, !errorMessage.isEmpty {
            return nil
        }

        let context = await PendingChatContextFactory.outgoing(
            to: user,
            from: currentUserId,
            followersCountOverride: followersCountOverride,
            momentsCountOverride: momentsCountOverride
        )
        return ProfileMessagePresentation(destination: .pendingChat(context))
    }
}
