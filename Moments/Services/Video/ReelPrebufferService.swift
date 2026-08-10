import AVFoundation
import Foundation

/// Mantiene el siguiente reel bufferizado en un player mudo y pausado.
/// Al hacer swipe **no** se reutiliza el mismo `AVPlayerItem` (AVFoundation
/// lanza si un item sigue asociado a otro `AVPlayer`): se mina uno nuevo
/// desde el `AVAsset` ya caliente.
final class ReelPrebufferService {
    static let shared = ReelPrebufferService()

    private let lock = NSLock()
    private let warmPlayer = AVPlayer()
    private var preparedURLString: String?

    private init() {
        warmPlayer.isMuted = true
        warmPlayer.allowsExternalPlayback = false
        warmPlayer.automaticallyWaitsToMinimizeStalling = false
    }

    func prebuffer(urlString: String) {
        lock.lock()
        defer { lock.unlock() }

        guard preparedURLString != urlString else { return }

        let item = VideoPreloader.shared.getPlayerItem(for: urlString)
        VideoPlaybackSelector.shared.configure(
            playerItem: item,
            tier: VideoPlaybackSelector.shared.recommendedTier(),
            isActivelyPlaying: false
        )
        warmPlayer.replaceCurrentItem(with: item)
        preparedURLString = urlString
    }

    /// Asset ya caliente para la URL, o `nil` si no hay match.
    /// Siempre devuelve un **AVPlayerItem nuevo** (nunca el ligado a `warmPlayer`).
    func takePreparedItem(for urlString: String) -> AVPlayerItem? {
        lock.lock()
        defer { lock.unlock() }

        guard preparedURLString == urlString,
              let warmItem = warmPlayer.currentItem,
              warmItem.status != .failed else {
            return nil
        }

        let asset = warmItem.asset
        warmPlayer.replaceCurrentItem(with: nil)
        preparedURLString = nil

        let fresh = AVPlayerItem(asset: asset)
        fresh.preferredForwardBufferDuration = warmItem.preferredForwardBufferDuration
        return fresh
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        warmPlayer.replaceCurrentItem(with: nil)
        preparedURLString = nil
    }
}
