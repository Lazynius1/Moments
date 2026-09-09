import Foundation
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

/// Sheet presentations for a group invite. Already-member stays on the sheet until the user opens the chat.
enum GroupJoinSheetPhase: Equatable {
    case loading, direct, approval, sending, sent, pending, alreadyMember, error, unavailable, full
}

@MainActor
final class GroupRequestsNavigation: ObservableObject {
    static let shared = GroupRequestsNavigation()
    @Published var pendingSent = false
}

@MainActor
final class GroupJoinSheetStore: ObservableObject {
    @Published private(set) var phase: GroupJoinSheetPhase = .loading
    @Published private(set) var name = ""
    @Published private(set) var image = ""
    @Published private(set) var requiresApproval = false
    @Published private(set) var busy = false
    @Published private(set) var joined = false
    @Published private(set) var errorTitle = "sheet.errorLoadTitle"
    @Published private(set) var errorBody = "sheet.errorBody"
    private enum Operation { case load, submit, cancel }
    private var retryOperation: Operation = .load
    private var link: GroupInviteLink?
    private var userId: String?
    private var generation = 0
    private var pendingListener: ListenerRegistration?

    deinit { pendingListener?.remove() }

    func stop() {
        generation += 1
        pendingListener?.remove(); pendingListener = nil
        busy = false
    }

    func load(_ link: GroupInviteLink) async {
        guard !busy else { return }
        stop(); self.link = link; userId = Auth.auth().currentUser?.uid
        joined = false; phase = .loading; busy = true; retryOperation = .load
        let version = generation
        defer { if valid(version) { busy = false } }
        do {
            let result = try await preview(link)
            guard valid(version) else { return }
            updateMetadata(result)
            if !applyResolvedStatus(result) {
                // Verify the fragment before offering an action that needs the key.
                _ = try decodedKey(link, result)
                phase = requiresApproval ? .approval : .direct
            }
        } catch { if valid(version) { present(error) } }
    }

    func submit() async {
        guard !busy, let link, let userId, Auth.auth().currentUser?.uid == userId else { return }
        busy = true; phase = .sending; retryOperation = .submit
        let version = generation, expectedApproval = requiresApproval
        defer { if valid(version) { busy = false } }
        do {
            let result = try await preview(link)
            guard valid(version) else { return }
            updateMetadata(result)
            if applyResolvedStatus(result) { return }
            if requiresApproval != expectedApproval {
                phase = requiresApproval ? .approval : .direct
                return
            }
            let key = try decodedKey(link, result)
            let wrapped = try await EncryptionService.shared.buildWrappedConversationKeys(
                for: [userId], conversationKey: key, wrappedBy: userId)
            guard valid(version) else { return }
            guard let envelope = wrapped[userId] else { throw failure("keyUnavailable") }
            let response = try await GroupChatAPI.request("manageGroup", body: [
                "action": "joinLink", "conversationId": link.groupId, "token": link.token,
                "requiresApproval": expectedApproval, "wrappedKey": envelope
            ])
            guard valid(version) else { return }
            if response["pending"] as? Bool == true {
                phase = response["alreadyPending"] as? Bool == true ? .pending : .sent
                watchPending(link, version: version)
            } else { joined = true }
        } catch {
            guard valid(version) else { return }
            if (error as NSError).userInfo["serverCode"] as? String == "approvalChanged" {
                busy = false
                await load(link)
            } else { present(error) }
        }
    }

    func cancel() async {
        guard !busy, let link, let userId, Auth.auth().currentUser?.uid == userId else { return }
        busy = true; phase = .pending; retryOperation = .cancel
        let version = generation
        defer { if valid(version) { busy = false } }
        do {
            let result = try await GroupChatAPI.request("manageGroup", body: ["action": "cancelJoin", "conversationId": link.groupId])
            guard valid(version) else { return }
            if result["isMember"] as? Bool == true { phase = .alreadyMember; return }
            busy = false
            await load(link)
        } catch { if valid(version) { present(error) } }
    }

    func retry() async {
        switch retryOperation {
        case .load: if let link { await load(link) }
        case .submit: await submit()
        case .cancel: await cancel()
        }
    }

    func refreshPending() async {
        guard !busy, phase == .pending || phase == .sent, let link else { return }
        await load(link)
    }

    private func preview(_ link: GroupInviteLink) async throws -> [String: Any] {
        try await GroupChatAPI.request("manageGroup", body: ["action": "previewLink", "conversationId": link.groupId, "token": link.token])
    }
    private func updateMetadata(_ data: [String: Any]) {
        name = data["name"] as? String ?? ""
        image = data["image"] as? String ?? ""
        requiresApproval = data["requiresApproval"] as? Bool == true
    }
    private func applyResolvedStatus(_ data: [String: Any]) -> Bool {
        if data["isMember"] as? Bool == true { phase = .alreadyMember; return true }
        if data["pending"] as? Bool == true {
            phase = .pending
            if let link { watchPending(link, version: generation) }
            return true
        }
        if data["isFull"] as? Bool == true { phase = .full; return true }
        return false
    }
    private func decodedKey(_ link: GroupInviteLink, _ data: [String: Any]) throws -> SymmetricKey {
        guard let text = data["encryptedKey"] as? String, let bytes = Data(base64Encoded: text) else { throw failure("linkUnavailable") }
        do {
            let key = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: SymmetricKey(data: link.secret), authenticating: Data(link.groupId.utf8))
            guard key.count == 32 else { throw failure("linkUnavailable") }
            return SymmetricKey(data: key)
        } catch { throw failure("linkUnavailable") }
    }
    private func valid(_ version: Int) -> Bool {
        generation == version && userId != nil && Auth.auth().currentUser?.uid == userId
    }
    private func failure(_ code: String) -> NSError { NSError(domain: "GroupLink", code: 0, userInfo: ["serverCode": code]) }
    private func present(_ error: Error) {
        let code = (error as NSError).userInfo["serverCode"] as? String ?? ""
        switch code {
        case "linkUnavailable", "unavailable", "invalidGroup": phase = .unavailable
        case "groupFull", "invalidMembers": phase = .full
        default:
            phase = .error
            switch retryOperation {
            case .load: errorTitle = "sheet.errorLoadTitle"
            case .submit: errorTitle = requiresApproval ? "sheet.errorSendTitle" : "sheet.errorJoinTitle"
            case .cancel: errorTitle = "sheet.errorCancelTitle"
            }
            errorBody = code == "keyUnavailable" ? "keyError" : "sheet.errorBody"
        }
    }
    private func watchPending(_ link: GroupInviteLink, version: Int) {
        pendingListener?.remove()
        guard let userId else { return }
        pendingListener = Firestore.firestore().collection("groupJoinRequests").whereField("recipientId", isEqualTo: userId)
            .addSnapshotListener { [weak self] doc, _ in
                Task { @MainActor in
                    guard let self, self.valid(version), !self.busy,
                          let doc, !doc.metadata.isFromCache, !doc.documents.contains(where: { $0.documentID == "\(link.groupId)_\(userId)" }),
                          self.phase == .pending || self.phase == .sent else { return }
                    await self.load(link)
                }
            }
    }
}
