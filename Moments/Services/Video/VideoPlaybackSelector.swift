import Foundation
import AVFoundation

// MARK: - Variants (Firestore: mediaItem.videoVariants — ABR manual con 3 MP4)

struct VideoVariants: Codable, Equatable {
    let low: String?
    let medium: String?
    let high: String?

    func url(for tier: VideoPlaybackTier) -> String? {
        let candidate: String?
        switch tier {
        case .low: candidate = low
        case .medium: candidate = medium ?? low
        case .high: candidate = high ?? medium ?? low
        }
        guard let candidate,
              !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return candidate
    }

    var allURLs: [String] {
        [low, medium, high].compactMap { value in
            guard let value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
    }
}

enum VideoPlaybackTier: String, Codable {
    case low
    case medium
    case high
}

struct VideoPlaybackSource: Equatable {
    let playbackURL: URL
    let tier: VideoPlaybackTier?
    let preheatURLStrings: [String]
}

// MARK: - Selector (manual ABR: low / medium / high MP4)

final class VideoPlaybackSelector {
    static let shared = VideoPlaybackSelector()

    private init() {}

    func source(for item: MediaItem, moment: Moment? = nil) -> VideoPlaybackSource? {
        guard item.type == .video else { return nil }

        let fallbackURL = resolvedFallbackURL(for: item, moment: moment)
        guard let fallbackURL else { return nil }

        let tier = recommendedTier()
        let tierURLString = item.videoVariants?.url(for: tier) ?? fallbackURL.absoluteString
        guard let playbackURL = URL(string: normalizedURLString(tierURLString) ?? tierURLString) else {
            return nil
        }

        return VideoPlaybackSource(
            playbackURL: playbackURL,
            tier: tier,
            preheatURLStrings: preheatStrings(variants: item.videoVariants, primary: tierURLString, tier: tier)
        )
    }

    func source(for moment: Moment) -> VideoPlaybackSource? {
        guard let item = moment.primaryVisibleMediaItem, item.type == .video else {
            guard moment.shouldUseLegacyMediaFallback,
                  let videoUrl = moment.videoUrl,
                  let url = URL(string: normalizedURLString(videoUrl) ?? videoUrl) else {
                return nil
            }
            return VideoPlaybackSource(
                playbackURL: url,
                tier: recommendedTier(),
                preheatURLStrings: [videoUrl]
            )
        }
        return source(for: item, moment: moment)
    }

    func posterURLString(for item: MediaItem, moment: Moment?) -> String? {
        if let thumb = item.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty {
            return thumb
        }
        if let momentThumb = moment?.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !momentThumb.isEmpty {
            return momentThumb
        }
        if let imagePath = moment?.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            return imagePath
        }
        return nil
    }

    func preloadURLStrings(from moments: [Moment], maxMoments: Int = 6) -> [String] {
        var collected: [String] = []
        var seen = Set<String>()

        for moment in moments.prefix(maxMoments) {
            guard let item = moment.primaryVisibleMediaItem, item.type == .video else { continue }
            guard let source = source(for: item, moment: moment) else { continue }
            for url in source.preheatURLStrings {
                if seen.insert(url).inserted {
                    collected.append(url)
                }
            }
        }
        return collected
    }

    func recommendedTier() -> VideoPlaybackTier {
        let monitor = NetworkMonitor.shared
        if !monitor.isConnected || monitor.shouldUseOfflineMode {
            return .low
        }
        if monitor.isConstrained || monitor.isExpensive {
            return .low
        }
        switch monitor.connectionType {
        case .wifi, .ethernet:
            return .high
        case .cellular:
            return .medium
        case .unknown:
            return .medium
        }
    }

    // MARK: - Private

    private func resolvedFallbackURL(for item: MediaItem, moment: Moment?) -> URL? {
        let raw = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw) { return url }
        if let encoded = normalizedURLString(raw) {
            return URL(string: encoded)
        }
        if let moment,
           moment.shouldUseLegacyMediaFallback,
           let legacy = moment.videoUrl,
           let url = URL(string: normalizedURLString(legacy) ?? legacy) {
            return url
        }
        return nil
    }

    private func preheatStrings(variants: VideoVariants?, primary: String, tier: VideoPlaybackTier) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()

        func append(_ value: String?) {
            guard let value = normalizedURLString(value), seen.insert(value).inserted else { return }
            urls.append(value)
        }

        // Siempre el tier elegido; low solo como fallback (nunca high si el tier es medium/low).
        append(primary)
        if let variants, tier != .low {
            append(variants.url(for: .low))
        }
        return urls
    }

    func normalizedURLString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if URL(string: trimmed) != nil { return trimmed }
        let encoded = trimmed.replacingOccurrences(of: " ", with: "%20")
        return URL(string: encoded) != nil ? encoded : nil
    }
}

// MARK: - Moment helpers

extension Moment {
    func videoPlaybackSource() -> VideoPlaybackSource? {
        VideoPlaybackSelector.shared.source(for: self)
    }

    func videoPosterURLString(for item: MediaItem) -> String? {
        VideoPlaybackSelector.shared.posterURLString(for: item, moment: self)
    }
}
