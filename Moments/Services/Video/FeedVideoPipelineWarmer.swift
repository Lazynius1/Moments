import AVFoundation
import UIKit

/// Precalienta AVAudioSession + AVPlayerLayer una sola vez al entrar al feed.
/// El primer reel en viewport ya no paga ese coste en medio del scroll.
enum FeedVideoPipelineWarmer {
    private static var didStart = false
    private static var hostView: UIView?

    static func prewarmIfNeeded() {
        guard !didStart else { return }
        didStart = true

        Task(priority: .utility) {
            _ = await MomentsAudioSession.activate(
                category: .playback,
                mode: .moviePlayback
            )

            await MainActor.run {
                // Toca el pool (crea los AVPlayer del pool en cold start).
                _ = SharedVideoPlayerPool.shared

                let player = AVPlayer()
                let host = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
                let layer = AVPlayerLayer(player: player)
                layer.frame = host.bounds
                host.layer.addSublayer(layer)
                host.layoutIfNeeded()
                CATransaction.flush()
                hostView = host

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    layer.player = nil
                    hostView = nil
                }
            }
        }
    }
}
