import Foundation
import FirebaseFirestore
import FirebaseAuth

extension ChatService {
    func setVanishMode(
        conversationId: String,
        active: Bool,
        userId: String,
        timer: VanishMessageTimer? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        var payload: [String: Any] = [
            "vanishModeActive": active
        ]
        if active {
            payload["vanishModeEnabledBy"] = userId
            payload["vanishModeEnabledAt"] = FieldValue.serverTimestamp()
            if let timer {
                payload["vanishMessageTimer"] = timer.rawValue
            }
        } else {
            payload["vanishModeEnabledBy"] = FieldValue.delete()
            payload["vanishModeEnabledAt"] = FieldValue.delete()
            payload["vanishMessageTimer"] = FieldValue.delete()
        }

        db.collection("conversations")
            .document(conversationId)
            .updateData(payload, completion: completion)
    }

    func setVanishMessageTimer(
        conversationId: String,
        timer: VanishMessageTimer,
        completion: @escaping (Error?) -> Void
    ) {
        db.collection("conversations")
            .document(conversationId)
            .updateData(["vanishMessageTimer": timer.rawValue], completion: completion)
    }

    func setVanishSettingsNoticeMessageId(
        conversationId: String,
        messageId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection("conversations")
            .document(conversationId)
            .updateData(["vanishSettingsNoticeMessageId": messageId]) { error in
                completion?(error)
            }
    }

    func setVanishDisabledNoticeMessageId(
        conversationId: String,
        messageId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection("conversations")
            .document(conversationId)
            .updateData(["vanishDisabledNoticeMessageId": messageId]) { error in
                completion?(error)
            }
    }

    func clearVanishDisabledNoticeMessageId(
        conversationId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection("conversations")
            .document(conversationId)
            .updateData(["vanishDisabledNoticeMessageId": FieldValue.delete()]) { error in
                completion?(error)
            }
    }

    func clearVanishSettingsNoticeMessageId(
        conversationId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection("conversations")
            .document(conversationId)
            .updateData(["vanishSettingsNoticeMessageId": FieldValue.delete()]) { error in
                completion?(error)
            }
    }

    func sendChatNotice(
        conversationId: String,
        senderId: String,
        noticeKey: String,
        completion: ((String?, Error?) -> Void)? = nil
    ) {
        let messageId = UUID().uuidString
        let message = EnhancedMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: senderId,
            type: .chatNotice,
            content: noticeKey,
            timestamp: Date(),
            status: .sent,
            isRead: true,
            isDeleted: false,
            isViewed: true
        )

        sendMessage(message, useServerTimestamp: true) { result in
            switch result {
            case .success:
                completion?(messageId, nil)
            case .failure(let error):
                completion?(nil, error)
            }
        }
    }

    func updateChatNotice(
        conversationId: String,
        messageId: String,
        noticeKey: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["content": noticeKey]) { error in
                if error == nil {
                    LocalPersistenceService.shared.updateMessageNoticeContent(
                        conversationId: conversationId,
                        messageId: messageId,
                        content: noticeKey
                    )
                }
                completion?(error)
            }
    }

    func stampVanishExpiry(
        conversationId: String,
        messageId: String,
        expiresAt: Date,
        completion: ((Error?) -> Void)? = nil
    ) {
        db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData(["vanishExpiresAt": Timestamp(date: expiresAt)]) { error in
                if error == nil {
                    LocalPersistenceService.shared.updateMessageVanishExpiresAt(
                        conversationId: conversationId,
                        messageId: messageId,
                        expiresAt: expiresAt
                    )
                }
                completion?(error)
            }
    }

    func markVanishMessagesVanishedForMe(
        conversationId: String,
        messageIds: [String],
        userId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard !messageIds.isEmpty else {
            completion?(nil)
            return
        }

        let batch = db.batch()
        for messageId in messageIds {
            let ref = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
            batch.updateData(["vanishedFor": FieldValue.arrayUnion([userId])], forDocument: ref)
        }

        batch.commit { error in
            completion?(error)
        }
    }

    func purgeVanishMessagesLocally(conversationId: String, messageIds: [String]) {
        guard !messageIds.isEmpty else { return }
        for messageId in messageIds {
            LocalPersistenceService.shared.removeCachedMessage(conversationId: conversationId, messageId: messageId)
            ChatCacheStore.deleteMessageFiles(conversationId: conversationId, messageId: messageId)
        }
    }

    func reportVanishScreenshot(
        conversationId: String,
        reporterId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        sendChatNotice(
            conversationId: conversationId,
            senderId: reporterId,
            noticeKey: VanishMessageTimer.screenshotNoticeToken
        ) { _, error in
            completion?(error)
        }
    }

    func reportVanishScreenRecording(
        conversationId: String,
        reporterId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        sendChatNotice(
            conversationId: conversationId,
            senderId: reporterId,
            noticeKey: VanishMessageTimer.screenRecordingNoticeToken
        ) { _, error in
            completion?(error)
        }
    }
}

extension EnhancedMessage {
    /// El destinatario abrió/leyó el mensaje aunque no emita read receipt visible.
    private func recipientHasAcknowledgedRead() -> Bool {
        if isRead || status == .read { return true }
        guard let readBy else { return false }
        return readBy.contains { $0 != senderId }
    }

    /// 1:1 — todos han visto el mensaje vanish (p. ej. para arrancar timer 24h/7d).
    func everyoneHasSeen(for userId: String) -> Bool {
        guard isVanishModeMessage == true, type != .chatNotice else { return false }
        if senderId == userId {
            return recipientHasAcknowledgedRead()
        }
        return isRead || isViewed
    }

    func shouldHideVanishOnChatDismiss(for userId: String, timer: VanishMessageTimer) -> Bool {
        guard isVanishModeMessage == true, type != .chatNotice else { return false }
        if VanishMessageTimer.isExpired(vanishExpiresAt) { return true }

        switch timer {
        case .onceSeen:
            return everyoneHasSeen(for: userId)
        case .hours24, .days7:
            return VanishMessageTimer.isExpired(vanishExpiresAt)
        }
    }
}
