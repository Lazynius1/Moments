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

    private init() {
        slots = (0..<poolSize).map { _ in
            Slot(player: AVPlayer(), consumerId: nil, lastUsed: .distantPast)
        }
    }

    func player(for consumerId: String) -> AVPlayer {
        lock.lock()
        defer { lock.unlock() }

        if let index = slots.firstIndex(where: { $0.consumerId == consumerId }) {
            slots[index].lastUsed = Date()
            return slots[index].player
        }

        if let freeIndex = slots.firstIndex(where: { $0.consumerId == nil }) {
            slots[freeIndex].consumerId = consumerId
            slots[freeIndex].lastUsed = Date()
            return slots[freeIndex].player
        }

        let lruIndex = slots.enumerated().min(by: { $0.element.lastUsed < $1.element.lastUsed })?.offset ?? 0
        evictSlot(at: lruIndex)
        slots[lruIndex].consumerId = consumerId
        slots[lruIndex].lastUsed = Date()
        return slots[lruIndex].player
    }

    func release(consumerId: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let index = slots.firstIndex(where: { $0.consumerId == consumerId }) else { return }
        evictSlot(at: index)
    }

    private func evictSlot(at index: Int) {
        let player = slots[index].player
        player.pause()
        player.replaceCurrentItem(with: nil)
        slots[index].consumerId = nil
        slots[index].lastUsed = .distantPast
    }
}
