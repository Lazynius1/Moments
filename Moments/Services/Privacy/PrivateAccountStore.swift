import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// Campos privados de la cuenta propia: users/{uid}/private/account y private/relations
@MainActor
final class PrivateAccountStore: ObservableObject {
    static let shared = PrivateAccountStore()

    struct Snapshot: Sendable {
        let blockedUsers: Set<String>
        let bestFriends: Set<String>
        let blockedBy: Set<String>
        let bestFriendOf: Set<String>
        let email: String?
    }

    @Published private(set) var blockedUsers: Set<String> = []
    @Published private(set) var bestFriends: Set<String> = []
    @Published private(set) var blockedBy: Set<String> = []
    @Published private(set) var bestFriendOf: Set<String> = []
    @Published private(set) var email: String?

    private(set) var userId: String?
    private var accountListener: ListenerRegistration?
    private var relationsListener: ListenerRegistration?
    private var accountLoaded = false
    private var relationsLoaded = false

    private let db = Firestore.firestore()

    private init() {}

    var isLoaded: Bool { accountLoaded && relationsLoaded }

    func start(userId: String) {
        guard !userId.isEmpty else { return }
        if self.userId == userId, accountListener != nil, relationsListener != nil { return }
        stop()
        self.userId = userId

        let privateRef = db.collection("users").document(userId).collection("private")

        accountListener = privateRef.document("account").addSnapshotListener { [weak self] snapshot, error in
            let data: [String: Any]? = error == nil ? (snapshot?.data() ?? [:]) : nil
            let isFinal = Self.isFinalSnapshot(snapshot, error: error)
            Self.onMain {
                self?.applyAccount(data, isFinal: isFinal, for: userId)
            }
        }

        relationsListener = privateRef.document("relations").addSnapshotListener { [weak self] snapshot, error in
            let data: [String: Any]? = error == nil ? (snapshot?.data() ?? [:]) : nil
            let isFinal = Self.isFinalSnapshot(snapshot, error: error)
            Self.onMain {
                self?.applyRelations(data, isFinal: isFinal, for: userId)
            }
        }
    }

    func stop() {
        accountListener?.remove()
        relationsListener?.remove()
        accountListener = nil
        relationsListener = nil
        userId = nil
        accountLoaded = false
        relationsLoaded = false
        blockedUsers = []
        bestFriends = []
        blockedBy = []
        bestFriendOf = []
        email = nil
    }

    /// Espera al primer snapshot de ambos documentos (o al timeout).
    func waitUntilLoaded(timeout: TimeInterval = 3) async {
        // Arranque perezoso si la sesión existe pero aún no se inició el store
        if let currentUid = Auth.auth().currentUser?.uid, userId != currentUid {
            start(userId: currentUid)
        }
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while userId != nil, !isLoaded, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func hasBlockedMe(_ userId: String) -> Bool {
        blockedBy.contains(userId)
    }

    func isBestFriendOf(_ authorId: String) -> Bool {
        bestFriendOf.contains(authorId)
    }

    /// Valores tras la primera carga; usable desde contextos fuera del MainActor.
    func loadedSnapshot(timeout: TimeInterval = 3) async -> Snapshot {
        await waitUntilLoaded(timeout: timeout)
        return Snapshot(
            blockedUsers: blockedUsers,
            bestFriends: bestFriends,
            blockedBy: blockedBy,
            bestFriendOf: bestFriendOf,
            email: email
        )
    }

    // MARK: - Private

    private func applyAccount(_ data: [String: Any]?, isFinal: Bool, for userId: String) {
        guard self.userId == userId else { return }
        if let data {
            blockedUsers = Self.idSet(data["blockedUsers"])
            bestFriends = Self.idSet(data["bestFriends"])
            let mail = (data["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            email = mail.isEmpty ? nil : mail
        }
        // Un error también cuenta como carga para no bloquear a quien espera
        if isFinal { accountLoaded = true }
    }

    private func applyRelations(_ data: [String: Any]?, isFinal: Bool, for userId: String) {
        guard self.userId == userId else { return }
        if let data {
            blockedBy = Self.idSet(data["blockedBy"])
            bestFriendOf = Self.idSet(data["bestFriendOf"])
        }
        if isFinal { relationsLoaded = true }
    }

    // Un documento inexistente leído de caché no es definitivo: se espera al servidor (o al timeout)
    private nonisolated static func isFinalSnapshot(_ snapshot: DocumentSnapshot?, error: Error?) -> Bool {
        guard error == nil, let snapshot else { return true }
        return snapshot.exists || !snapshot.metadata.isFromCache
    }

    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }

    private nonisolated static func idSet(_ value: Any?) -> Set<String> {
        Set(((value as? [String]) ?? []).filter { !$0.isEmpty })
    }
}
