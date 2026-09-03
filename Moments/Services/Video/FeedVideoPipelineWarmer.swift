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
                hostView = host

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    layer.player = nil
                    hostView = nil
                }
            }
        }
    }
}

/// Prepara el primer vídeo real del feed con su item y su decoder. El pool vacío
/// evita el coste de `AVPlayer()`, pero por sí solo no deja contenido listo para play.
@MainActor
enum FeedFirstVideoPrewarmer {
    private static var didPrepare = false
    private(set) static var preparedConsumerId: String?
    private static var statusObservation: NSKeyValueObservation?

    static func prepareFirstVideo(in moments: [Moment]) {
        guard !didPrepare else { return }
        guard let candidate = moments.lazy.compactMap(makeCandidate).first else { return }
        didPrepare = true
        preparedConsumerId = candidate.consumerId

        let urlString = candidate.source.playbackURL.absoluteString
        let consumerId = candidate.consumerId
        let tier = candidate.source.tier ?? VideoPlaybackSelector.shared.recommendedTier()

        // AVPlayer / replaceCurrentItem / preroll: solo main.
        // Playlist HLS + tracks: fuera, luego un hop corto al main.
        Task.detached(priority: .userInitiated) {
            await VideoPreloader.shared.warmAsset(for: urlString)
            await MainActor.run {
                attachPreparedItem(consumerId: consumerId, urlString: urlString, tier: tier)
            }
        }
    }

    private static func attachPreparedItem(
        consumerId: String,
        urlString: String,
        tier: VideoPlaybackTier
    ) {
        let player = SharedVideoPlayerPool.shared.player(for: consumerId)
        guard player.currentItem == nil else { return }

        let item = VideoPreloader.shared.getPlayerItem(for: urlString)
        VideoPlaybackSelector.shared.configure(playerItem: item, tier: tier)
        player.isMuted = true
        player.replaceCurrentItem(with: item)
        DispatchQueue.main.async {
            prerollWhenReady(player)
        }
    }

    /// `preroll` lanza si `player.status != .readyToPlay` (HLS acaba de cargar el item).
    private static func prerollWhenReady(_ player: AVPlayer) {
        statusObservation?.invalidate()
        if player.status == .readyToPlay {
            player.preroll(atRate: 1) { _ in }
            return
        }
        statusObservation = player.observe(\.status, options: [.new]) { player, _ in
            guard player.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                statusObservation?.invalidate()
                statusObservation = nil
                guard player.status == .readyToPlay else { return }
                player.preroll(atRate: 1) { _ in }
            }
        }
    }

    static func isPrepared(consumerId: String) -> Bool {
        preparedConsumerId == consumerId
            && SharedVideoPlayerPool.shared.hasActiveItem(for: consumerId)
    }

    static func consume(consumerId: String) {
        guard preparedConsumerId == consumerId else { return }
        preparedConsumerId = nil
    }

    private struct Candidate {
        let consumerId: String
        let source: VideoPlaybackSource
    }

    private static func makeCandidate(moment: Moment) -> Candidate? {
        let visibleItems = moment.visibleMediaItems
        if let item = visibleItems.first, item.type == .video,
           let source = VideoPlaybackSelector.shared.source(for: item, moment: moment) {
            let consumerId = visibleItems.count > 1
                ? GlobalVideoManager.profileVideoConsumerId(for: moment, mediaItem: item)
                : GlobalVideoManager.profileVideoConsumerId(for: moment)
            return Candidate(consumerId: consumerId, source: source)
        }

        guard moment.shouldUseLegacyMediaFallback,
              let source = VideoPlaybackSelector.shared.source(for: moment) else { return nil }
        return Candidate(
            consumerId: GlobalVideoManager.profileVideoConsumerId(for: moment),
            source: source
        )
    }
}
