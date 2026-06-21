import AVFoundation
import Foundation

/// Pool compartido de AVPlayer para feed y reels (máx. 3 instancias activas).
final class SharedVideoPlayerPool {
    static let shared = SharedVideoPlayerPool()

    private struct Slot {
        let player: AVPlayer
        var consumerId: String?
        var lastUsed: Date
    }

    private let poolSize = 3
    private var slots: [Slot] = []
    private let lock = NSLock()

    /// Callbacks de desalojo por consumerId. Permiten que un consumer (p. ej. un
    /// VideoPlayerManager) sepa que su AVPlayer fue reasignado a otro contenido y
    /// deje de apuntar a él, evitando reproducir contenido cruzado.
    private var evictionHandlers: [String: () -> Void] = [:]

    private init() {
        slots = (0..<poolSize).map { _ in
            Slot(player: AVPlayer(), consumerId: nil, lastUsed: .distantPast)
        }
    }

    /// Registra un callback que se invoca cuando el slot del consumer es desalojado.
    func setEvictionHandler(for consumerId: String, _ handler: @escaping () -> Void) {
        lock.lock()
        evictionHandlers[consumerId] = handler
        lock.unlock()
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
            slots[freeIndex].consumerId = consumerId
            slots[freeIndex].lastUsed = Date()
            let player = slots[freeIndex].player
            lock.unlock()
            return player
        }

        let lruIndex = slots.enumerated().min(by: { $0.element.lastUsed < $1.element.lastUsed })?.offset ?? 0
        let evictedConsumer = slots[lruIndex].consumerId
        evictSlot(at: lruIndex)
        slots[lruIndex].consumerId = consumerId
        slots[lruIndex].lastUsed = Date()
        let player = slots[lruIndex].player
        let handler = evictedConsumer.flatMap { evictionHandlers[$0] }
        lock.unlock()

        // Notificar fuera del lock para evitar reentradas/deadlocks.
        handler?()
        return player
    }

    func release(consumerId: String) {
        lock.lock()

        guard let index = slots.firstIndex(where: { $0.consumerId == consumerId }) else {
            evictionHandlers.removeValue(forKey: consumerId)
            lock.unlock()
            return
        }
        evictSlot(at: index)
        evictionHandlers.removeValue(forKey: consumerId)
        lock.unlock()
    }

    func hasActiveItem(for consumerId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let index = slots.firstIndex(where: { $0.consumerId == consumerId }) else { return false }
        return slots[index].player.currentItem != nil
    }

    private func evictSlot(at index: Int) {
        let player = slots[index].player
        player.pause()
        player.replaceCurrentItem(with: nil)
        slots[index].consumerId = nil
        slots[index].lastUsed = .distantPast
    }
}
