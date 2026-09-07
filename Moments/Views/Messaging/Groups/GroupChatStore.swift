import Foundation
import Combine
import CryptoKit
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
    let revision: Int
    let keyVersion: Int
    let wrappedKeys: [String: [String: Any]]
    let date: Date
    let lastMessageId: String
    let readStatus: [String: Bool]
    let muted: [String]
    let pendingNames: [String: String]
    let allMemberNames: [String: String]

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
        revision = data["groupRevision"] as? Int ?? 0
        keyVersion = data["conversationKeyVersion"] as? Int ?? 1
        wrappedKeys = data["wrappedKeys"] as? [String: [String: Any]] ?? [:]
        date = (data["timestamp"] as? Timestamp)?.dateValue() ?? .distantPast
        lastMessageId = data["lastMessageId"] as? String ?? ""
        readStatus = data["readStatus"] as? [String: Bool] ?? [:]
        muted = data["mutedByUserIds"] as? [String] ?? []
        pendingNames = data["pendingInviteNames"] as? [String: String] ?? [:]
        allMemberNames = details.mapValues { $0["username"] as? String ?? "" }
    }
}

struct GroupInvitation: Identifiable {
    let id: String
    let groupId: String
    let name: String
    let inviter: String
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
                            name: $0.get("groupName") as? String ?? "", inviter: $0.get("inviterName") as? String ?? "")
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

    func saveMembers(name: String, ids: [String], to group: GroupConversation?) async -> String? {
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
            _ = try await request("manageGroup", ["action": group == nil ? "create" : "add", "conversationId": id,
                "name": name, "memberIds": ids, "wrappedKeys": envelopes, "revision": group?.revision ?? 0])
            return id
        } catch { self.error = "groups.manageError"; return nil }
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
        guard (response as? HTTPURLResponse)?.statusCode == 200, uid == user.uid else { throw URLError(.badServerResponse) }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
