import AVFoundation
import Foundation

// Mantiene el siguiente reel ya bufferizado en un player mudo y pausado,
// para que al hacer swipe el item se transfiera con su buffer intacto.
final class ReelPrebufferService {
    static let shared = ReelPrebufferService()

    private let warmPlayer = AVPlayer()
    private var preparedURLString: String?

    private init() {
        warmPlayer.isMuted = true
        warmPlayer.allowsExternalPlayback = false
    }

    func prebuffer(urlString: String) {
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

    func takePreparedItem(for urlString: String) -> AVPlayerItem? {
        guard preparedURLString == urlString,
              let item = warmPlayer.currentItem,
              item.status != .failed else {
            return nil
        }
        warmPlayer.replaceCurrentItem(with: nil)
        preparedURLString = nil
        return item
    }

    func discard() {
        warmPlayer.replaceCurrentItem(with: nil)
        preparedURLString = nil
    }
}
