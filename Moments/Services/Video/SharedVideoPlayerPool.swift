import AVFoundation
import Foundation

enum VideoPlaybackPhase: Equatable {
    case idle
    case loading
    case ready
    case playing
    case waiting
    case failed
}

/// Observa una sola vez el estado real del AVPlayer compartido por feed y Reels.
private final class VideoPlaybackStateTracker {
    private let player: AVPlayer
    private var playerObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var listeners: [ObjectIdentifier: (VideoPlaybackPhase) -> Void] = [:]
    private(set) var phase: VideoPlaybackPhase = .idle

    init(player: AVPlayer) {
        self.player = player
        playerObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.publish() }
        }
        playerStatusObservation = player.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.publish() }
        }
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.observeCurrentItem() }
        }
    }

    func addListener(owner: AnyObject, _ listener: @escaping (VideoPlaybackPhase) -> Void) {
        publish()
        listeners[ObjectIdentifier(owner)] = listener
        listener(phase)
    }

    func removeListener(owner: AnyObject) {
        listeners.removeValue(forKey: ObjectIdentifier(owner))
    }

    func removeAllListeners() {
        listeners.removeAll()
    }

    private func observeCurrentItem() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.publish() }
        }
        publish()
    }

    private func publish() {
        let next: VideoPlaybackPhase
        if player.status == .failed {
            next = .failed
        } else {
            next = itemPhase()
        }
        guard phase != next else { return }
        phase = next
        let currentListeners = Array(listeners.values)
        for listener in currentListeners {
            listener(next)
        }
    }

    private func itemPhase() -> VideoPlaybackPhase {
        switch player.currentItem?.status {
        case nil: return .idle
        case .some(.unknown): return .loading
        case .some(.failed): return .failed
        case .some(.readyToPlay):
            switch player.timeControlStatus {
            case .paused: return .ready
            case .playing: return .playing
            case .waitingToPlayAtSpecifiedRate: return .waiting
            @unknown default: return .ready
            }
        @unknown default: return .loading
        }
    }
}

/// Pool compartido de AVPlayer para feed y reels (máx. 3 instancias activas).
final class SharedVideoPlayerPool {
    static let shared = SharedVideoPlayerPool()

    private struct Slot {
        let player: AVPlayer
        let state: VideoPlaybackStateTracker
        var consumerId: String?
        var lastUsed: Date
        var generation: UInt64
    }

    private let poolSize = 3
    private var slots: [Slot] = []
    private let lock = NSLock()
    private var nextGeneration: UInt64 = 0
    private var owners: [String: ObjectIdentifier] = [:]

    /// Callbacks de desalojo por consumerId. Permiten que un consumer (p. ej. un
    /// VideoPlayerManager) sepa que su AVPlayer fue reasignado a otro contenido y
    /// deje de apuntar a él, evitando reproducir contenido cruzado.
    private var evictionHandlers: [String: [ObjectIdentifier: () -> Void]] = [:]

    private init() {
        slots = (0..<poolSize).map { _ in
            let player = AVPlayer()
            return Slot(
                player: player,
                state: VideoPlaybackStateTracker(player: player),
                consumerId: nil,
                lastUsed: .distantPast,
                generation: 0
            )
        }
    }

    func observeState(of player: AVPlayer, for consumerId: String, owner: AnyObject,
                      _ listener: @escaping (VideoPlaybackPhase) -> Void) {
        lock.lock()
        let state = slots.first {
            $0.consumerId == consumerId && $0.player === player
        }?.state
        lock.unlock()
        state?.addListener(owner: owner, listener)
    }

    func removeStateObserver(of player: AVPlayer, owner: AnyObject) {
        lock.lock()
        let state = slots.first { $0.player === player }?.state
        lock.unlock()
        state?.removeListener(owner: owner)
    }

    /// Feed y Reels pueden observar el mismo slot durante el handoff.
    func setEvictionHandler(for consumerId: String, owner: AnyObject, _ handler: @escaping () -> Void) {
        lock.lock()
        evictionHandlers[consumerId, default: [:]][ObjectIdentifier(owner)] = handler
        lock.unlock()
    }

    func removeEvictionHandler(for consumerId: String, owner: AnyObject) {
        lock.lock()
        evictionHandlers[consumerId]?.removeValue(forKey: ObjectIdentifier(owner))
        if evictionHandlers[consumerId]?.isEmpty == true {
            evictionHandlers.removeValue(forKey: consumerId)
        }
        lock.unlock()
    }

    /// Solo el dueño actual puede reproducir, pausar o liberar este slot.
    @discardableResult
    func claim(_ player: AVPlayer, for consumerId: String, owner: AnyObject) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slots.first(where: { $0.consumerId == consumerId && $0.player === player }) else {
            return nil
        }
        owners[consumerId] = ObjectIdentifier(owner)
        return slot.generation
    }

    func isOwned(_ player: AVPlayer, by owner: AnyObject, for consumerId: String, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return owners[consumerId] == ObjectIdentifier(owner)
            && slots.contains {
                $0.consumerId == consumerId && $0.player === player && $0.generation == generation
            }
    }

    func player(for consumerId: String) -> AVPlayer {
        lock.lock()

        if let index = slots.firstIndex(where: { $0.consumerId == consumerId }) {
            slots[index].lastUsed = Date()
            let player = slots[index].player
            lock.unlock()
            return player
        }

        if let freeIndex = slots.firstIndex(where: { $0.consumerId == nil }) {
            nextGeneration &+= 1
            slots[freeIndex].consumerId = consumerId
            slots[freeIndex].lastUsed = Date()
            slots[freeIndex].generation = nextGeneration
            let player = slots[freeIndex].player
            lock.unlock()
            return player
        }

        // Mantener el player que está reproduciendo o esperando buffer. El LRU
        // debe desalojar primero un vídeo pausado, aunque se usara más tarde.
        let pausedSlots = slots.enumerated().filter {
            $0.element.player.timeControlStatus == .paused
        }
        let candidates = pausedSlots.isEmpty ? Array(slots.enumerated()) : pausedSlots
        let lruIndex = candidates.min(by: {
            $0.element.lastUsed < $1.element.lastUsed
        })?.offset ?? 0
        let evictedConsumer = slots[lruIndex].consumerId
        let handlers = evictedConsumer.flatMap { evictionHandlers.removeValue(forKey: $0) } ?? [:]
        if let evictedConsumer { owners.removeValue(forKey: evictedConsumer) }
        evictSlot(at: lruIndex)
        nextGeneration &+= 1
        slots[lruIndex].consumerId = consumerId
        slots[lruIndex].lastUsed = Date()
        slots[lruIndex].generation = nextGeneration
        let player = slots[lruIndex].player
        lock.unlock()

        // Notificar fuera del lock para evitar reentradas/deadlocks.
        handlers.values.forEach { $0() }
        return player
    }

    func release(consumerId: String) {
        lock.lock()
        let handlers = evictionHandlers.removeValue(forKey: consumerId) ?? [:]
        owners.removeValue(forKey: consumerId)
        guard let index = slots.firstIndex(where: { $0.consumerId == consumerId }) else {
            lock.unlock()
            handlers.values.forEach { $0() }
            return
        }
        evictSlot(at: index)
        lock.unlock()
        handlers.values.forEach { $0() }
    }

    func release(_ player: AVPlayer, consumerId: String, owner: AnyObject, generation: UInt64) {
        lock.lock()
        guard owners[consumerId] == ObjectIdentifier(owner),
              let index = slots.firstIndex(where: {
                  $0.consumerId == consumerId && $0.player === player && $0.generation == generation
              }) else {
            lock.unlock()
            return
        }
        let handlers = evictionHandlers.removeValue(forKey: consumerId) ?? [:]
        owners.removeValue(forKey: consumerId)
        evictSlot(at: index)
        lock.unlock()
        handlers.values.forEach { $0() }
    }

    func hasActiveItem(for consumerId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let index = slots.firstIndex(where: { $0.consumerId == consumerId }) else { return false }
        return slots[index].player.currentItem != nil
    }

    /// Un AVPlayer del pool puede haber sido reasignado aunque conserve un item.
    /// La vista que lo tenía no debe reproducir ese item como si fuera suyo.
    func isAssigned(_ player: AVPlayer, to consumerId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return slots.contains { $0.consumerId == consumerId && $0.player === player }
    }

    func currentTimeSeconds(for consumerId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let index = slots.firstIndex(where: { $0.consumerId == consumerId }) else { return 0 }
        let seconds = CMTimeGetSeconds(slots[index].player.currentTime())
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return seconds
    }

    private func evictSlot(at index: Int) {
        slots[index].state.removeAllListeners()
        let player = slots[index].player
        player.pause()
        player.replaceCurrentItem(with: nil)
        slots[index].consumerId = nil
        slots[index].lastUsed = .distantPast
    }
}
