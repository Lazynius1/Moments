import AVFoundation
import Foundation

// MARK: - Configuración compartida (feed, reels y cualquier player social)

extension VideoPlaybackSelector {
    /// Bitrate máximo por tier (ABR manual). Misma política en feed y reels.
    static func peakBitRate(for tier: VideoPlaybackTier) -> Double {
        switch tier {
        case .low: return 800_000
        case .medium: return 2_500_000
        case .high: return 5_000_000
        }
    }

    func tier(below tier: VideoPlaybackTier) -> VideoPlaybackTier? {
        switch tier {
        case .high: return .medium
        case .medium: return .low
        case .low: return nil
        }
    }

    func playbackURL(for item: MediaItem, moment: Moment?, tier: VideoPlaybackTier) -> URL? {
        guard item.type == .video else { return nil }

        // MP4 por tier (downgrade manual). HLS se resuelve vía `source(for:)`.
        let mp4Fallback = item.videoVariants?.url(for: tier)
            ?? item.url
        if let url = URL(string: normalizedURLString(mp4Fallback) ?? mp4Fallback) {
            return url
        }
        return source(for: item, moment: moment)?.fallbackMp4URL
            ?? source(for: item, moment: moment)?.playbackURL
    }

    /// Ajustes estándar del feed aplicables a cualquier `AVPlayerItem` social.
    func configure(playerItem: AVPlayerItem, tier: VideoPlaybackTier, isActivelyPlaying: Bool = true) {
        playerItem.preferredForwardBufferDuration = 2.5
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = isActivelyPlaying
        if #available(iOS 14.0, *) {
            playerItem.preferredPeakBitRate = Self.peakBitRate(for: tier)
        }
    }

    func makeConfiguredPlayerItem(
        for item: MediaItem,
        moment: Moment?,
        tier: VideoPlaybackTier? = nil
    ) -> AVPlayerItem? {
        let resolvedTier = tier ?? recommendedTier()
        let url = source(for: item, moment: moment)?.playbackURL
            ?? playbackURL(for: item, moment: moment, tier: resolvedTier)
        guard let url else { return nil }
        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        configure(playerItem: playerItem, tier: resolvedTier)
        return playerItem
    }
}

// MARK: - Downgrade en caliente ante stalls repetidos

/// Si el buffer se vacía varias veces seguidas, baja de tier (high → medium → low).
final class VideoAdaptiveTierController {
    private(set) var currentTier: VideoPlaybackTier
    private let mediaItem: MediaItem?
    private let moment: Moment?
    private let selector = VideoPlaybackSelector.shared
    private var consecutiveStalls = 0
    private let stallsBeforeDowngrade = 2

    var hasVariants: Bool {
        guard let mediaItem else { return false }
        // Con HLS el ABR es nativo; no forzar switch a MP4 por stall.
        if let hls = mediaItem.hlsMasterUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hls.isEmpty {
            return false
        }
        let variants = mediaItem.videoVariants
        return variants?.low != nil || variants?.medium != nil || variants?.high != nil
    }

    init(mediaItem: MediaItem?, moment: Moment?, initialTier: VideoPlaybackTier? = nil) {
        self.mediaItem = mediaItem
        self.moment = moment
        self.currentTier = initialTier ?? selector.recommendedTier()
    }

    /// Llamar cuando la reproducción vuelve a ser estable.
    func notePlaybackHealthy() {
        consecutiveStalls = 0
    }

    /// Registra un stall. Devuelve un nuevo `AVPlayerItem` si toca bajar de calidad.
    func handleStall() -> AVPlayerItem? {
        guard hasVariants, let mediaItem else { return nil }

        consecutiveStalls += 1
        guard consecutiveStalls >= stallsBeforeDowngrade else { return nil }
        guard let nextTier = selector.tier(below: currentTier),
              let url = selector.playbackURL(for: mediaItem, moment: moment, tier: nextTier) else {
            return nil
        }

        consecutiveStalls = 0
        currentTier = nextTier

        let playerItem = VideoPreloader.shared.getPlayerItem(for: url.absoluteString)
        selector.configure(playerItem: playerItem, tier: nextTier)
        return playerItem
    }
}

// MARK: - Recuperación compartida ante buffer vacío / stall

enum VideoPlaybackRecovery {
  /// Reintenta play o sustituye el item por un tier inferior.
  /// `onTierDowngrade` se llama antes de reemplazar el item para que la UI
  /// pueda volver a mostrar el poster (evitar flash negro).
    static func recoverFromStall(
        player: AVPlayer,
        isPlaying: Bool,
        adaptive: VideoAdaptiveTierController?,
        onTierDowngrade: (() -> Void)? = nil,
        onReplaceItem: (AVPlayerItem) -> Void
    ) {
        guard isPlaying else { return }
        guard player.currentItem?.status != .failed else { return }

        if let newItem = adaptive?.handleStall() {
            let resumeTime = player.currentTime()
            onTierDowngrade?()
            onReplaceItem(newItem)
            player.replaceCurrentItem(with: newItem)
            player.seek(to: resumeTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { _ in
                player.play()
            }
            return
        }

        player.play()
    }
}
