import Foundation
import UIKit
import Intents
import FirebaseAuth

final class ChatSendMessageIntentHandler: NSObject, INSendMessageIntentHandling {
    func confirm(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        completion(INSendMessageIntentResponse(code: .ready, userActivity: nil))
    }

    func handle(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        let trimmed = intent.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard
            !trimmed.isEmpty,
            let conversationId = intent.conversationIdentifier,
            let senderId = Auth.auth().currentUser?.uid
        else {
            completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
            return
        }

        Task { @MainActor in
            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CommunicationReply") {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }

            let finish: (INSendMessageIntentResponseCode) -> Void = { code in
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
                completion(INSendMessageIntentResponse(code: code, userActivity: nil))
            }

            ChatService.shared.sendTextMessage(
                conversationId: conversationId,
                senderId: senderId,
                content: trimmed
            ) { result in
                NotificationBadgeService.shared.setupListeners()
                switch result {
                case .success:
                    finish(.success)
                case .failure:
                    finish(.failure)
                }
            }
        }
    }
}
