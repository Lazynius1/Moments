import AVFoundation
import UIKit

enum StoryVideoProcessingError: LocalizedError {
    case missingVideo
    case invalidDuration
    case exceedsAutoSplitLimit
    case exportFailed
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .missingVideo:
            return NSLocalizedString("storyVideo.error.missingVideo", comment: "Missing video error")
        case .invalidDuration:
            return NSLocalizedString("storyVideo.error.invalidDuration", comment: "Invalid video duration error")
        case .exceedsAutoSplitLimit:
            return NSLocalizedString("storyVideo.error.exceedsAutoSplitLimit", comment: "Story video exceeds auto split limit error")
        case .exportFailed:
            return NSLocalizedString("storyVideo.error.exportFailed", comment: "Video export failed error")
        case .thumbnailFailed:
            return NSLocalizedString("storyVideo.error.thumbnailFailed", comment: "Thumbnail generation failed error")
        }
    }
}

struct StoryVideoClip {
    let media: CreatorMedia
    let startTime: Double
    let duration: Double
}

final class StoryVideoProcessingService {
    static let shared = StoryVideoProcessingService()
    static let maxStorySegmentDuration: Double = 60.0
    static let maxAutoSplitPartCount = 5
    static var maxAutoSplitDuration: Double {
        CreatorMedia.maxMomentVideoDuration
    }

    private init() {}

    func duration(for videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw StoryVideoProcessingError.invalidDuration
        }
        return seconds
    }

    func exportStoryClip(videoURL: URL, start: Double, end: Double) async throws -> CreatorMedia {
        let asset = AVURLAsset(url: videoURL)
        let fullDuration = try await duration(for: videoURL)
        let safeStart = max(0, min(start, fullDuration))
        let safeEnd = max(safeStart + 0.1, min(end, fullDuration))
        let clipDuration = safeEnd - safeStart

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_clip_\(UUID().uuidString).mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw StoryVideoProcessingError.exportFailed
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: safeStart, preferredTimescale: 600),
            duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
        )

        try await exportSession.export(to: outputURL, as: .mp4)

        let thumbnail = try await generateStoryThumbnail(videoURL: outputURL, time: 0.1)
        return CreatorMedia(
            id: UUID().uuidString,
            image: thumbnail,
            videoURL: outputURL,
            type: .video,
            aspectRatio: .nineBySixteen,
            recommendedAspectRatio: .nineBySixteen,
            hasEdits: true,
            storyVideoMode: .trimmed,
            videoDuration: clipDuration
        )
    }

    func splitStoryVideo(videoURL: URL, maxSegmentDuration: Double = maxStorySegmentDuration) async throws -> [StoryVideoClip] {
        let totalDuration = try await duration(for: videoURL)
        guard maxSegmentDuration > 0 else {
            throw StoryVideoProcessingError.invalidDuration
        }
        guard totalDuration <= Self.maxAutoSplitDuration else {
            throw StoryVideoProcessingError.exceedsAutoSplitLimit
        }

        var clips: [StoryVideoClip] = []
        var start = 0.0

        while start < totalDuration {
            let end = min(start + maxSegmentDuration, totalDuration)
            var media = try await exportStoryClip(videoURL: videoURL, start: start, end: end)
            media.storyVideoMode = .normal
            media.videoDuration = end - start
            clips.append(StoryVideoClip(media: media, startTime: start, duration: end - start))
            start = end
        }

        return clips
    }

    func generateStoryThumbnail(videoURL: URL, time: Double) async throws -> UIImage {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 540, height: 960)

        do {
            let (cgImage, _) = try await generator.image(
                at: CMTime(seconds: max(0, time), preferredTimescale: 600)
            )
            return UIImage(cgImage: cgImage)
        } catch {
            throw StoryVideoProcessingError.thumbnailFailed
        }
    }
}
