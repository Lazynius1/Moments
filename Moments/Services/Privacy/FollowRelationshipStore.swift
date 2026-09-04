import Foundation
import FirebaseAuth

enum FollowButtonState: String, Codable {
    case ownProfile
    case blocked
    case following
    case mutuals
    case canFollow
    case canRequestFollow
    case requestPending
    case requestPendingCancellable

    var isFollowingOrMutual: Bool {
        self == .following || self == .mutuals
    }

    var showsProspectFollow: Bool {
        switch self {
        case .canFollow, .canRequestFollow, .requestPendingCancellable: true
        default: false
        }
    }

    var buttonText: String {
        switch self {
        case .ownProfile: NSLocalizedString("userProfile.followButton.ownProfile", comment: "Own profile")
        case .blocked: NSLocalizedString("userProfile.followButton.blocked", comment: "Blocked")
        case .following: NSLocalizedString("userProfile.followButton.following", comment: "Following")
        case .mutuals: NSLocalizedString("audience.type.mutuals", comment: "Mutuals")
        case .canFollow: NSLocalizedString("userProfile.followButton.canFollow", comment: "Follow")
        case .canRequestFollow: NSLocalizedString("userProfile.followButton.canRequestFollow", comment: "Request follow")
        case .requestPending: NSLocalizedString("userProfile.followButton.requestPending", comment: "Request sent")
        case .requestPendingCancellable: NSLocalizedString("userProfile.followButton.cancelRequest", comment: "Cancel request")
        }
    }

    var isActionable: Bool {
        switch self {
        case .ownProfile, .blocked, .requestPending: false
        case .following, .mutuals, .canFollow, .canRequestFollow, .requestPendingCancellable: true
        }
    }

    var isPendingRequest: Bool {
        self == .requestPending || self == .requestPendingCancellable
    }

    var isProspect: Bool {
        self == .canFollow || self == .canRequestFollow
    }

    var buttonColor: String {
        switch self {
        case .ownProfile: "gray"
        case .blocked: "red"
        case .following, .mutuals: "green"
        case .canFollow, .canRequestFollow: "blue"
        case .requestPending, .requestPendingCancellable: "orange"
        }
    }
}

/// Fuente compartida de verdad para cualquier botón de relación.
/// Coordina el estado UI en memoria y reutiliza `LocalPersistenceService`
/// como único snapshot persistente de conexiones.
final class FollowStateStore {
    static let shared = FollowStateStore()
    static let didChangeNotification = Foundation.Notification.Name("FollowStateStoreDidChange")

    private enum EntrySource {
        case localSnapshot
        case confirmed
        case optimistic
    }

    private struct Entry {
        let state: FollowButtonState
        let updatedAt: Date
        let revision: UInt64
        let source: EntrySource
    }

    private struct InFlightResolution {
        var callbacks: [(FollowButtonState?) -> Void]
    }

    private static let obsoletePersistenceKeys = ["follow.relationship.states.v2", "follow.relationship.states.v3"]
    private static let confirmedFreshness: TimeInterval = 15
    private static let optimisticRevalidationDelay: TimeInterval = 3
    private static let confirmedTTL: TimeInterval = 5 * 60
    private static let optimisticTTL: TimeInterval = 10 * 60
    private static let maximumEntryCount = 500

    private var entriesByRelationship: [String: Entry] = [:]
    private var inFlightResolutions: [String: InFlightResolution] = [:]
    private let lock = NSLock()

    private init() {
        Self.obsoletePersistenceKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func relationshipKey(viewerId: String, targetUserId: String) -> String {
        "\(viewerId)|\(targetUserId)"
    }

    func state(for userId: String) -> FollowButtonState? {
        guard let viewerId = Auth.auth().currentUser?.uid else { return nil }
        return state(viewerId: viewerId, targetUserId: userId)
    }

    func state(viewerId: String, targetUserId: String) -> FollowButtonState? {
        if let memoryState = memoryState(viewerId: viewerId, targetUserId: targetUserId) {
            return memoryState
        }
        guard Thread.isMainThread else {
            Task { @MainActor [weak self] in
                _ = self?.hydrateLocalSnapshot(viewerId: viewerId, targetUserId: targetUserId)
            }
            return nil
        }
        return MainActor.assumeIsolated {
            hydrateLocalSnapshot(viewerId: viewerId, targetUserId: targetUserId)
        }
    }

    private func memoryState(viewerId: String, targetUserId: String) -> FollowButtonState? {
        let key = relationshipKey(viewerId: viewerId, targetUserId: targetUserId)
        let now = Date()
        lock.lock()
        let entry = entriesByRelationship[key]
        let isValid = entry.map { Self.isValid($0, now: now) } ?? false
        if !isValid, entry != nil { entriesByRelationship.removeValue(forKey: key) }
        lock.unlock()
        return isValid ? entry?.state : nil
    }

    @MainActor
    private func hydrateLocalSnapshot(viewerId: String, targetUserId: String) -> FollowButtonState? {
        let cached = LocalPersistenceService.shared.cachedFollowRelationship(
            viewerId: viewerId,
            targetUserId: targetUserId
        )
        let snapshotState: FollowButtonState?
        if cached.isMutual {
            snapshotState = .mutuals
        } else if cached.isFollowing {
            snapshotState = .following
        } else {
            snapshotState = nil
        }
        guard let snapshotState else { return nil }
        return write(
            snapshotState,
            source: .localSnapshot,
            viewerId: viewerId,
            targetUserId: targetUserId,
            expectedRevision: nil,
            shouldSyncPersistentSnapshot: false
        )
    }

    /// Las escrituras públicas proceden de acciones UI y avanzan la revisión.
    func setState(_ state: FollowButtonState, for userId: String) {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        setState(state, viewerId: viewerId, targetUserId: userId)
    }

    func setState(_ state: FollowButtonState, viewerId: String, targetUserId: String) {
        write(
            state,
            source: .optimistic,
            viewerId: viewerId,
            targetUserId: targetUserId,
            expectedRevision: nil
        )
    }

    func resolve(
        viewerId: String,
        targetUserId: String,
        completion: @escaping (FollowButtonState?) -> Void
    ) {
        guard viewerId != targetUserId else {
            setState(.ownProfile, viewerId: viewerId, targetUserId: targetUserId)
            completion(.ownProfile)
            return
        }

        let key = relationshipKey(viewerId: viewerId, targetUserId: targetUserId)
        let now = Date()
        lock.lock()
        if let entry = entriesByRelationship[key] {
            let age = now.timeIntervalSince(entry.updatedAt)
            let isFresh = (entry.source == .confirmed && age < Self.confirmedFreshness)
                || (entry.source == .optimistic && age < Self.optimisticRevalidationDelay)
            if isFresh {
                lock.unlock()
                completion(entry.state)
                return
            }
        }
        if inFlightResolutions[key] != nil {
            inFlightResolutions[key]?.callbacks.append(completion)
            lock.unlock()
            return
        }
        let revision = entriesByRelationship[key]?.revision ?? 0
        inFlightResolutions[key] = InFlightResolution(callbacks: [completion])
        lock.unlock()

        PrivacyService.shared.resolveFollowButtonState(viewerId: viewerId, targetUserId: targetUserId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let authoritativeState):
                let resolvedState = self.write(
                    authoritativeState,
                    source: .confirmed,
                    viewerId: viewerId,
                    targetUserId: targetUserId,
                    expectedRevision: revision
                )
                self.finishResolution(key: key, state: resolvedState)
            case .failure:
                if let memoryState = self.memoryState(viewerId: viewerId, targetUserId: targetUserId) {
                    self.finishResolution(key: key, state: memoryState)
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.finishResolution(
                        key: key,
                        state: self.hydrateLocalSnapshot(viewerId: viewerId, targetUserId: targetUserId)
                    )
                }
            }
        }
    }

    private func finishResolution(key: String, state: FollowButtonState?) {
        lock.lock()
        let callbacks = inFlightResolutions.removeValue(forKey: key)?.callbacks ?? []
        lock.unlock()
        callbacks.forEach { $0(state) }
    }

    func reconciledState(_ authoritativeState: FollowButtonState, for userId: String) -> FollowButtonState {
        authoritativeState
    }

    @discardableResult
    private func write(
        _ state: FollowButtonState,
        source: EntrySource,
        viewerId: String,
        targetUserId: String,
        expectedRevision: UInt64?,
        shouldSyncPersistentSnapshot: Bool = true
    ) -> FollowButtonState {
        let key = relationshipKey(viewerId: viewerId, targetUserId: targetUserId)
        let previousState: FollowButtonState?
        let effectiveState: FollowButtonState
        let didWrite: Bool
        lock.lock()
        let current = entriesByRelationship[key]
        let currentRevision = current?.revision ?? 0
        previousState = current?.state
        let rejectsStaleWrite = expectedRevision != nil && expectedRevision != currentRevision
        let rejectsOptimisticDowngrade = source == .confirmed
            && current.map { !Self.confirmedShouldReplace(state, current: $0, now: Date()) } == true
        if rejectsStaleWrite || rejectsOptimisticDowngrade {
            effectiveState = current?.state ?? state
            didWrite = false
        } else {
            entriesByRelationship[key] = Entry(
                state: state,
                updatedAt: Date(),
                revision: currentRevision &+ 1,
                source: source
            )
            Self.prune(&entriesByRelationship, now: Date())
            effectiveState = state
            didWrite = true
        }
        lock.unlock()

        guard didWrite else { return effectiveState }
        if shouldSyncPersistentSnapshot {
            persistSnapshot(state, viewerId: viewerId, targetUserId: targetUserId)
        }
        if previousState != state {
            postChange(state: state, viewerId: viewerId, targetUserId: targetUserId)
        }
        return state
    }

    private func postChange(state: FollowButtonState, viewerId: String, targetUserId: String) {
        let post = {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: nil,
                userInfo: ["viewerId": viewerId, "userId": targetUserId, "state": state]
            )
        }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }

    private static func isValid(_ entry: Entry, now: Date) -> Bool {
        let ttl = entry.source == .optimistic ? optimisticTTL : confirmedTTL
        return now.timeIntervalSince(entry.updatedAt) <= ttl
    }

    /// Un confirmado no puede deshacer un tap reciente hasta que expire el TTL
    /// optimista, salvo bloqueo / perfil propio o un confirmado de la misma familia.
    private static func confirmedShouldReplace(
        _ confirmed: FollowButtonState,
        current: Entry,
        now: Date
    ) -> Bool {
        guard current.source == .optimistic else { return true }
        guard now.timeIntervalSince(current.updatedAt) <= optimisticTTL else { return true }
        if confirmed == .blocked || confirmed == .ownProfile { return true }
        if confirmed == current.state { return true }
        if current.state.isFollowingOrMutual && confirmed.isFollowingOrMutual { return true }
        if current.state.isPendingRequest && confirmed.isPendingRequest { return true }
        if current.state.isProspect && confirmed.isProspect { return true }
        return false
    }

    private static func prune(_ entries: inout [String: Entry], now: Date) {
        entries = entries.filter { isValid($0.value, now: now) }
        guard entries.count > maximumEntryCount else { return }
        let keep = entries
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .prefix(maximumEntryCount)
            .map { ($0.key, $0.value) }
        entries = Dictionary(uniqueKeysWithValues: keep)
    }

    private func persistSnapshot(
        _ state: FollowButtonState,
        viewerId: String,
        targetUserId: String
    ) {
        guard state != .ownProfile else { return }
        Task { @MainActor in
            LocalPersistenceService.shared.updateCachedFollowRelationship(
                viewerId: viewerId,
                targetUserId: targetUserId,
                isFollowing: state == .following || state == .mutuals,
                isMutual: state == .mutuals
            )
        }
    }
}
