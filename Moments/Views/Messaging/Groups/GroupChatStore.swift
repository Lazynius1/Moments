import Foundation
import Combine
import CryptoKit
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct GroupMember: Identifiable {
    let id: String
    let name: String
    let image: String
}

struct GroupConversation: Identifiable {
    let id: String
    let name: String
    let members: [GroupMember]
    let admins: [String]
    let owner: String
    let createdBy: String
    let createdAt: Date?
    let revision: Int
    let keyVersion: Int
    let wrappedKeys: [String: [String: Any]]
    let date: Date
    let lastMessageId: String
    let readStatus: [String: Bool]
    let muted: [String]
    let pendingNames: [String: String]
    let allMemberNames: [String: String]
    let image: String
    let memberJoinedAt: [String: Date]

    init(_ doc: DocumentSnapshot) {
        let data = doc.data() ?? [:]
        id = doc.documentID
        name = data["groupName"] as? String ?? ""
        let details = data["participantData"] as? [String: [String: Any]] ?? [:]
        members = (data["participants"] as? [String] ?? []).map {
            GroupMember(id: $0, name: details[$0]?["username"] as? String ?? "", image: details[$0]?["profileImagePath"] as? String ?? "")
        }
        admins = data["adminIds"] as? [String] ?? []
        owner = data["ownerId"] as? String ?? ""
        createdBy = data["createdBy"] as? String ?? owner
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        revision = data["groupRevision"] as? Int ?? 0
        keyVersion = data["conversationKeyVersion"] as? Int ?? 1
        wrappedKeys = data["wrappedKeys"] as? [String: [String: Any]] ?? [:]
        date = (data["timestamp"] as? Timestamp)?.dateValue() ?? .distantPast
        lastMessageId = data["lastMessageId"] as? String ?? ""
        readStatus = data["readStatus"] as? [String: Bool] ?? [:]
        muted = data["mutedByUserIds"] as? [String] ?? []
        pendingNames = data["pendingInviteNames"] as? [String: String] ?? [:]
        allMemberNames = details.mapValues { $0["username"] as? String ?? "" }
        image = data["groupImagePath"] as? String ?? ""
        memberJoinedAt = (data["memberJoinedAt"] as? [String: Timestamp] ?? [:]).mapValues { $0.dateValue() }
    }

    func joinedDate(for memberId: String) -> Date? {
        if let joined = memberJoinedAt[memberId] { return joined }
        if memberId == createdBy || memberId == owner { return createdAt }
        return nil
    }
}

struct GroupInvitation: Identifiable {
    let id: String
    let groupId: String
    let name: String
    let inviter: String
    let image: String
}

struct GroupSkippedInvite {
    let id: String
    let username: String
}

struct GroupSaveResult {
    let id: String
    let skipped: [GroupSkippedInvite]
}

@MainActor
final class GroupChatStore: ObservableObject {
    @Published var invitations: [GroupInvitation] = []
    @Published var groups: [GroupConversation] = []
    @Published var active: GroupConversation?
    @Published var candidates: [GroupMember] = []
    @Published var loading = false
    @Published var busy = false
    @Published var error: String?
    private let db = Firestore.firestore()
    private var creationSignature: String?
    private var creationId: String?
    private var invitationListener: ListenerRegistration?
    private var inboxListener: ListenerRegistration?
    private var groupListener: ListenerRegistration?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var sessionId: String?
    private var activeId: String?
    private var generation = 0
    var uid: String { Auth.auth().currentUser?.uid ?? "" }

    deinit {
        inboxListener?.remove(); groupListener?.remove(); invitationListener?.remove()
        if let authListener { Auth.auth().removeStateDidChangeListener(authListener) }
    }

    func start() {
        guard authListener == nil else { return }
        listenInbox(Auth.auth().currentUser?.uid)
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.listenInbox(user?.uid) }
        }
    }

    private func listenInbox(_ userId: String?) {
        guard sessionId != userId || inboxListener == nil else { return }
        inboxListener?.remove(); invitationListener?.remove(); invitations = []
        closeChat()
        groups = []; candidates = []; sessionId = userId
        guard let userId else { return }
        loading = true
        invitationListener = db.collection("groupInvitations").whereField("recipientId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, failure in
                Task { @MainActor in
                    guard let self, self.sessionId == userId else { return }
                    if failure != nil { self.error = "groups.error"; return }
                    self.invitations = (snapshot?.documents ?? []).map {
                        GroupInvitation(id: $0.documentID, groupId: $0.get("groupId") as? String ?? "",
                            name: $0.get("groupName") as? String ?? "", inviter: $0.get("inviterName") as? String ?? "",
                            image: $0.get("groupImagePath") as? String ?? "")
                    }
                }
            }
        inboxListener = db.collection("groupConversations").whereField("participants", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, failure in
                Task { @MainActor in
                    guard let self, self.sessionId == userId else { return }
                    self.loading = false
                    if failure != nil { self.error = "groups.error"; return }
                    self.groups = (snapshot?.documents ?? []).map(GroupConversation.init).sorted { $0.date > $1.date }
                }
            }
    }

    func stop() {
        inboxListener?.remove(); inboxListener = nil; invitationListener?.remove(); invitationListener = nil; invitations = []
        if let authListener { Auth.auth().removeStateDidChangeListener(authListener) }
        authListener = nil; sessionId = nil
        closeChat(); groups = []; candidates = []
    }

    func closeChat() {
        generation += 1
        groupListener?.remove()
        groupListener = nil
        activeId = nil; active = nil
    }

    func open(_ id: String) {
        guard activeId != id else { return }
        closeChat(); activeId = id; loading = true
        let userId = uid
        groupListener = db.collection("groupConversations").document(id).addSnapshotListener { [weak self] snapshot, failure in
            Task { @MainActor in
                guard let self, self.activeId == id, self.uid == userId else { return }
                self.loading = false
                guard failure == nil, let snapshot, snapshot.exists else {
                    self.closeChat(); self.error = "groups.unavailable"; return
                }
                let group = GroupConversation(snapshot)
                guard group.members.contains(where: { $0.id == userId }) else {
                    self.closeChat(); self.error = "groups.unavailable"; return
                }
                self.active = group
            }
        }
    }

    private func key(for group: GroupConversation) throws -> SymmetricKey {
        guard let map = group.wrappedKeys[uid] else { throw URLError(.userAuthenticationRequired) }
        return try EncryptionService.shared.unwrapGroupKey(map)
    }

    func loadCandidates(query: String = "") async {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !uid.isEmpty else { candidates = []; return }
        do {
            let userId = uid
            var request: Query = db.collection("users")
            if !search.isEmpty {
                request = request.whereField("username", isGreaterThanOrEqualTo: search)
                    .whereField("username", isLessThanOrEqualTo: search + "\u{f8ff}")
            }
            let docs = try await request.limit(to: 40).getDocuments()
            let members = docs.documents.compactMap { doc -> GroupMember? in
                let data = doc.data()
                guard doc.documentID != userId, data["isActive"] as? Bool != false else { return nil }
                return GroupMember(id: doc.documentID, name: data["username"] as? String ?? "", image: data["profileImagePath"] as? String ?? "")
            }
            if uid == userId && !Task.isCancelled { candidates = members.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        } catch { self.error = "groups.error" }
    }

    func saveMembers(name: String, ids: [String], to group: GroupConversation?) async -> GroupSaveResult? {
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        do {
            let signature = uid + "\n" + name + "\n" + ids.sorted().joined(separator: "\n")
            if group == nil && creationSignature != signature { creationId = nil; creationSignature = signature }
            if group == nil && creationId == nil { creationId = GroupChatScope.newId() }
            let userId = uid, id = group?.id ?? creationId!
            let key: SymmetricKey
            if let group { key = try self.key(for: group) } else { key = SymmetricKey(size: .bits256) }
            let recipients = group == nil ? [userId] + ids : ids
            var envelopes = try await EncryptionService.shared.buildWrappedConversationKeys(for: recipients, conversationKey: key, wrappedBy: userId)
            guard envelopes.count == recipients.count else { self.error = "groups.keyError"; return nil }
            for recipient in recipients { envelopes[recipient]?.removeValue(forKey: "wrappedAt") }
            let payload = try await request("manageGroup", ["action": group == nil ? "create" : "add", "conversationId": id,
                "name": name, "memberIds": ids, "wrappedKeys": envelopes, "revision": group?.revision ?? 0])
            return GroupSaveResult(id: id, skipped: skippedInvites(from: payload))
        } catch {
            let payload = (error as NSError).userInfo
            let skipped: [GroupSkippedInvite]
            if let rows = payload["skipped"] as? [[String: Any]] {
                skipped = skippedInvites(from: ["skipped": rows])
            } else if let rows = payload["skipped"] as? [[String: String]] {
                skipped = rows.map { GroupSkippedInvite(id: $0["id"] ?? "", username: $0["username"] ?? "") }.filter { !$0.id.isEmpty }
            } else {
                skipped = []
            }
            self.error = inviteForbiddenMessage(skipped)
                ?? (((error as NSError).domain == "GroupChat" && (error as NSError).code == 403)
                    ? "groups.inviteForbidden" : "groups.manageError")
            return nil
        }
    }

    func inviteForbiddenMessage(_ skipped: [GroupSkippedInvite]) -> String? {
        let names = skipped.map { item in
            candidates.first(where: { $0.id == item.id })?.name ?? item.username
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        let joined = ListFormatter.localizedString(byJoining: names)
        let key = names.count == 1 ? "groups.inviteForbiddenOne" : "groups.inviteForbiddenMany"
        return String(format: NSLocalizedString(key, comment: ""), joined)
    }

    private func skippedInvites(from payload: [String: Any]) -> [GroupSkippedInvite] {
        (payload["skipped"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return GroupSkippedInvite(id: id, username: row["username"] as? String ?? "")
        }
    }

    func setPhoto(_ image: UIImage, group: GroupConversation) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let path: String = try await withCheckedThrowingContinuation { continuation in
                StorageService().uploadGroupImage(groupId: group.id, image: image) { continuation.resume(with: $0) }
            }
            _ = try await request("manageGroup", ["action": "setPhoto", "conversationId": group.id, "revision": group.revision, "imagePath": path])
        } catch { self.error = "groups.photoError" }
    }

    @discardableResult
    func command(_ action: String, group: GroupConversation, memberId: String = "", name: String = "", muted: Bool = false) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            _ = try await request("manageGroup", ["action": action, "conversationId": group.id, "revision": group.revision, "memberId": memberId, "name": name, "muted": muted])
            return true
        } catch { self.error = "groups.manageError"; return false }
    }

    func respond(to invitation: GroupInvitation, accept: Bool) async -> Conversation? {
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        do {
            _ = try await request("manageGroup", ["action": accept ? "acceptInvite" : "declineInvite", "conversationId": invitation.groupId])
            guard accept else { return nil }
            let doc = try await db.collection("groupConversations").document(invitation.groupId).getDocument()
            return ChatService.shared.groupConversation(doc, userId: uid)
        } catch { self.error = "groups.manageError"; return nil }
    }

    private func request(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser, let project = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://europe-southwest1-\(project).cloudfunctions.net/\(endpoint)") else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status != 200 || uid != user.uid {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let code = json["error"] as? String
            if code == "inviteForbidden" {
                throw NSError(domain: "GroupChat", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("groups.inviteForbidden", comment: ""),
                    "skipped": skippedInvites(from: json).map { ["id": $0.id, "username": $0.username] }
                ])
            }
            throw URLError(.badServerResponse)
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

struct GroupInviteLink: Identifiable {
    let groupId: String
    let token: String
    let secret: Data
    var id: String { groupId + token }
    init?(_ url: URL) {
        guard let fragment = url.fragment, fragment.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let pair: (String, String)?
        if ["moments", "glowsy"].contains(scheme), host == "group", parts.count == 2 {
            pair = (parts[0], parts[1])
        } else if scheme == "https", ["momentsapp.app", "www.momentsapp.app"].contains(host),
                  parts.count == 3, parts[0] == "g" {
            pair = (parts[1], parts[2])
        } else if scheme == "https", host.contains("cloudfunctions.net"),
                  parts.count >= 4, parts[parts.count - 3] == "join" {
            pair = (parts[parts.count - 2], parts[parts.count - 1])
        } else {
            pair = nil
        }
        guard let (id, inviteToken) = pair, GroupChatScope.isGroup(id),
              inviteToken.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        groupId = id
        token = inviteToken
        secret = Data(stride(from: 0, to: 64, by: 2).map { index in
            let start = fragment.index(fragment.startIndex, offsetBy: index)
            return UInt8(fragment[start..<fragment.index(start, offsetBy: 2)], radix: 16)!
        })
    }
    static func url(groupId: String, token: String, secret: Data) throws -> URL {
        guard let url = URL(string: "https://momentsapp.app/g/\(groupId)/\(token)#\(secret.map { String(format: "%02x", $0) }.joined())") else { throw URLError(.badURL) }
        return url
    }
}

extension GroupChatStore {
    func invitationLink(_ group: GroupConversation, renew: Bool = false) async -> URL? {
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        do {
            let groupKey = try key(for: group)
            let aad = Data(group.id.utf8)
            if !renew {
                let existing = try await request("manageGroup", ["action": "getLink", "conversationId": group.id])
                if let token = existing["token"] as? String, let box = existing["secretBox"] as? String,
                   let data = Data(base64Encoded: box) {
                    let secret = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: groupKey, authenticating: aad)
                    return try GroupInviteLink.url(groupId: group.id, token: token, secret: secret)
                }
            }
            let secretKey = SymmetricKey(size: .bits256)
            let secret = secretKey.withUnsafeBytes { Data($0) }
            let token = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
            let encryptedKey = try AES.GCM.seal(groupKey.withUnsafeBytes { Data($0) }, using: secretKey, authenticating: aad).combined!
            let secretBox = try AES.GCM.seal(secret, using: groupKey, authenticating: aad).combined!
            _ = try await request("manageGroup", ["action": "setLink", "conversationId": group.id, "revision": group.revision,
                "token": token, "encryptedKey": encryptedKey.base64EncodedString(), "secretBox": secretBox.base64EncodedString()])
            return try GroupInviteLink.url(groupId: group.id, token: token, secret: secret)
        } catch { self.error = "groups.linkError"; return nil }
    }

    func previewLink(_ link: GroupInviteLink) async -> (name: String, image: String)? {
        do {
            let result = try await request("manageGroup", ["action": "previewLink", "conversationId": link.groupId, "token": link.token])
            _ = try linkKey(link, result)
            guard let name = result["name"] as? String else { return nil }
            return (name, result["image"] as? String ?? "")
        } catch { self.error = "groups.linkError"; return nil }
    }
    private func linkKey(_ link: GroupInviteLink, _ result: [String: Any]) throws -> SymmetricKey {
        guard let box = result["encryptedKey"] as? String, let data = Data(base64Encoded: box) else { throw URLError(.badServerResponse) }
        let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: link.secret), authenticating: Data(link.groupId.utf8))
        guard raw.count == 32 else { throw URLError(.cannotDecodeContentData) }
        return SymmetricKey(data: raw)
    }
    func joinLink(_ link: GroupInviteLink) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            let result = try await request("manageGroup", ["action": "previewLink", "conversationId": link.groupId, "token": link.token])
            let userId = uid
            let key = try linkKey(link, result)
            var envelopes = try await EncryptionService.shared.buildWrappedConversationKeys(for: [userId], conversationKey: key, wrappedBy: userId)
            guard var envelope = envelopes.removeValue(forKey: userId) else { throw URLError(.userAuthenticationRequired) }
            envelope.removeValue(forKey: "wrappedAt")
            _ = try await request("manageGroup", ["action": "joinLink", "conversationId": link.groupId, "token": link.token, "wrappedKey": envelope])
            return true
        } catch { self.error = "groups.linkError"; return false }
    }
}
