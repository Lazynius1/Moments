import Foundation
import FirebaseFunctions

enum ViewOnceConsumptionReason: String {
    case viewOnce
    case replay
    case abandonReplay
}

final class ViewOnceConsumptionService {
    static let shared = ViewOnceConsumptionService()

    private lazy var functions = Functions.functions(region: "europe-southwest1")

    private init() {}

    func consume(
        conversationId: String,
        messageId: String,
        reason: ViewOnceConsumptionReason,
        completion: @escaping (Error?) -> Void
    ) {
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "messageId": messageId,
            "reason": reason.rawValue
        ]

        functions.httpsCallable("consumeViewOnceMessage").call(payload) { _, error in
            completion(error)
        }
    }
}
