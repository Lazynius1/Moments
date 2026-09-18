import SwiftUI
import AVFoundation

enum StoryMediaPresentationMode: Equatable {
    case fill
    case fitWithBlur

    var swiftUIContentMode: ContentMode {
        switch self {
        case .fill:
            return .fill
        case .fitWithBlur:
            return .fit
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            return .resizeAspectFill
        case .fitWithBlur:
            return .resizeAspect
        }
    }
}

enum StoryMediaLayoutRules {
    private static let fillTolerance: CGFloat = 0.035

    static func presentationMode(
        for mediaAspectRatio: CGFloat,
        canvasAspectRatio: CGFloat
    ) -> StoryMediaPresentationMode {
        guard
            mediaAspectRatio.isFinite,
            mediaAspectRatio > 0,
            canvasAspectRatio.isFinite,
            canvasAspectRatio > 0
        else {
            return .fill
        }

        return abs(mediaAspectRatio - canvasAspectRatio) <= fillTolerance ? .fill : .fitWithBlur
    }

    static func presentationMode(
        for mediaSize: CGSize,
        canvasSize: CGSize
    ) -> StoryMediaPresentationMode {
        let mediaAspectRatio = mediaSize.width / max(mediaSize.height, 1)
        let canvasAspectRatio = canvasSize.width / max(canvasSize.height, 1)
        return presentationMode(for: mediaAspectRatio, canvasAspectRatio: canvasAspectRatio)
    }
}

// MARK: - Processed Media Model
typealias ProcessedMedia = CreatorMedia

struct CreatorMedia: Identifiable {
    static let maxMomentVideoDuration: Double = 5 * 60
    static let maxMomentVideoUploadSizeBytes: Int64 = 300 * 1024 * 1024
    static let maxMomentVideoReadySizeBytes: Int64 = 100 * 1024 * 1024
    static let maxStoryVideoReadySizeBytes: Int64 = 60 * 1024 * 1024

    let id: String
    var image: UIImage
    var videoURL: URL?
    let type: MediaType
    var aspectRatio: AspectRatio
    var recommendedAspectRatio: AspectRatio?
    var hasEdits: Bool = false
    var thumbnailURL: URL?
    var videoDuration: Double?
    var videoFileSize: Int64?
    var videoResolution: String?
    var tags: [PhotoTag]? = nil // ✅ Etiquetas espaciales para esta imagen
    var storyVideoMode: StoryVideoMode = .normal
    var immersiveImage: UIImage? = nil
    var immersiveAspectRatio: AspectRatio? = nil
    var feedCrop: MediaItemFeedCrop? = nil

    // Helper para acceder al thumbnail de manera segura
    var thumbnail: UIImage? {
        return image
    }

    enum MediaType {
        case image, video
    }

    enum StoryVideoMode: String, Codable, Equatable {
        case normal
        case trimmed
        case autoSplit
    }

    enum AspectRatio: Equatable, Hashable {
        case square          // 1:1
        case portrait        // 4:5
        case landscape       // 16:9
        case nineBySixteen   // 9:16 (stories)
        case custom(CGFloat) // posts de momento: 3:4, 4:5, 1:1, 1.91:1

        var value: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8  // 4:5
            case .landscape: return 1.777 // 16:9
            case .nineBySixteen: return 0.5625 // 9:16
            case .custom(let ratio): return ratio
            }
        }

        var displayName: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .landscape: return "16:9"
            case .nineBySixteen: return "9:16"
            case .custom(let ratio):
                if abs(ratio - MomentFeedCrop.reelsGridAspect) < 0.02 { return "3:4" }
                if abs(ratio - MomentFeedCrop.landscapeMax) < 0.03 { return "1.91:1" }
                if abs(ratio - 3.0 / 2.0) < 0.02 { return "3:2" }
                if abs(ratio - 4.0 / 3.0) < 0.02 { return "4:3" }
                return String(format: "%.4f", Double(ratio))
            }
        }

        var ratio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 4.0/5.0
            case .landscape: return 16.0/9.0
            case .nineBySixteen: return 9.0/16.0
            case .custom(let value): return value
            }
        }

        /// Buckets para historias / cámara 9:16. No usar en posts de momento.
        static func fromRatio(_ ratio: CGFloat) -> AspectRatio {
            let tolerance: CGFloat = 0.15

            if abs(ratio - 0.5625) < tolerance { return .nineBySixteen }
            if abs(ratio - 0.8) < tolerance { return .portrait }
            if abs(ratio - 1.0) < tolerance { return .square }
            if abs(ratio - 1.777) < tolerance { return .landscape }

            if ratio < 0.65 { return .nineBySixteen }
            else if ratio < 0.85 { return .portrait }
            else if ratio < 1.15 { return .square }
            else { return .landscape }
        }

        /// Ratio de la card: 3:4 / 4:5 / 1:1 / 1.91:1. Reels 9:16 → 4:5.
        static func fromFeedPostRatio(_ ratio: CGFloat) -> AspectRatio {
            let safe = MomentFeedCrop.feedCardAspect(from: ratio)
            if abs(safe - MomentFeedCrop.squareAspect) < 0.008 { return .square }
            if abs(safe - MomentFeedCrop.portraitMax) < 0.008 { return .portrait }
            if abs(safe - MomentFeedCrop.reelsGridAspect) < 0.008 {
                return .custom(MomentFeedCrop.reelsGridAspect)
            }
            if abs(safe - MomentFeedCrop.landscapeMax) < 0.015 {
                return .custom(MomentFeedCrop.landscapeMax)
            }
            return .custom(safe)
        }

        static func parsePersisted(_ string: String?) -> AspectRatio {
            guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return .square
            }
            switch raw {
            case "1:1": return .square
            case "4:5": return .portrait
            case "3:4": return .custom(MomentFeedCrop.reelsGridAspect)
            case "1.91:1": return .custom(MomentFeedCrop.landscapeMax)
            case "16:9": return .landscape
            case "9:16": return .nineBySixteen
            default:
                if raw.contains(":") {
                    let parts = raw.split(separator: ":")
                    if parts.count == 2,
                       let w = Double(parts[0]),
                       let h = Double(parts[1]),
                       h > 0 {
                        return .fromFeedPostRatio(CGFloat(w / h))
                    }
                }
                if let value = Double(raw), value > 0 {
                    return .fromFeedPostRatio(CGFloat(value))
                }
                return .square
            }
        }
    }

    // MARK: - Initializers & Helpers

    init(id: String, image: UIImage, videoURL: URL?, type: MediaType, aspectRatio: AspectRatio, recommendedAspectRatio: AspectRatio? = nil, hasEdits: Bool = false, thumbnailURL: URL? = nil, tags: [PhotoTag]? = nil, storyVideoMode: StoryVideoMode = .normal, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil, feedCrop: MediaItemFeedCrop? = nil) {
        self.id = id
        self.image = image
        self.videoURL = videoURL
        self.type = type
        self.aspectRatio = aspectRatio
        self.recommendedAspectRatio = recommendedAspectRatio ?? aspectRatio
        self.hasEdits = hasEdits
        self.thumbnailURL = thumbnailURL
        self.tags = tags
        self.storyVideoMode = storyVideoMode
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
        self.immersiveImage = nil
        self.immersiveAspectRatio = nil
        self.feedCrop = feedCrop
    }

    init(type: MediaType, image: UIImage, videoURL: URL?, aspectRatio: AspectRatio, recommendedAspectRatio: AspectRatio? = nil, thumbnailURL: URL? = nil, storyVideoMode: StoryVideoMode = .normal, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil, feedCrop: MediaItemFeedCrop? = nil) {
        self.id = UUID().uuidString
        self.image = image
        self.videoURL = videoURL
        self.type = type
        self.aspectRatio = aspectRatio
        self.recommendedAspectRatio = recommendedAspectRatio ?? aspectRatio
        self.hasEdits = false
        self.thumbnailURL = thumbnailURL
        self.storyVideoMode = storyVideoMode
        self.videoDuration = videoDuration
        self.videoFileSize = videoFileSize
        self.videoResolution = videoResolution
        self.immersiveImage = nil
        self.immersiveAspectRatio = nil
        self.feedCrop = feedCrop
    }

    func with(videoURL: URL? = nil, aspectRatio: AspectRatio? = nil, recommendedAspectRatio: AspectRatio? = nil, hasEdits: Bool? = nil, thumbnailURL: URL? = nil, image: UIImage? = nil, tags: [PhotoTag]? = nil, storyVideoMode: StoryVideoMode? = nil, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil) -> CreatorMedia {
        var copy = CreatorMedia(
            id: self.id,
            image: image ?? self.image,
            videoURL: videoURL ?? self.videoURL,
            type: self.type,
            aspectRatio: aspectRatio ?? self.aspectRatio,
            recommendedAspectRatio: recommendedAspectRatio ?? self.recommendedAspectRatio,
            hasEdits: hasEdits ?? self.hasEdits,
            thumbnailURL: thumbnailURL ?? self.thumbnailURL,
            tags: tags ?? self.tags,
            storyVideoMode: storyVideoMode ?? self.storyVideoMode,
            videoDuration: videoDuration ?? self.videoDuration,
            videoFileSize: videoFileSize ?? self.videoFileSize,
            videoResolution: videoResolution ?? self.videoResolution
        )
        copy.immersiveImage = self.immersiveImage
        copy.immersiveAspectRatio = self.immersiveAspectRatio
        copy.feedCrop = self.feedCrop
        return copy
    }

    var isValidVideo: Bool {
        return type == .video && videoURL != nil && FileManager.default.fileExists(atPath: videoURL!.path)
    }

}

// MARK: - Shared UI Components

struct GlowSharePill: View {
    let title: String
    var icon: String = "paperplane.fill"
    var isLoading: Bool = false
    var isSmall: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            // Haptic feedback should be handled by a global helper if available,
            // otherwise we can omit it or use UIImpactFeedbackGenerator directly here if needed.
            // Assuming hapticFeedback is a View extension or global func available in the module.
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    HStack(spacing: 6) {
                        Text(NSLocalizedString(title, comment: ""))
                            .font(.system(size: isSmall ? 13 : 15, weight: .bold, design: .rounded))
                        if let customIcon = AttachmentIcon(rawValue: icon) {
                            AttachmentIconView(icon: customIcon, size: isSmall ? 10 : 12, tintColor: .white)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: isSmall ? 10 : 12))
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isSmall ? 14 : 20)
            .padding(.vertical, isSmall ? 8 : 10)
            .background(
                ZStack {
                    // Glow background
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.pink.opacity(0.4), radius: 8, x: 0, y: 4)

                    // Glass shine
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
            )
            .contentShape(Capsule())
        }
        .disabled(isLoading)
        .buttonStyle(CreatorScaleButtonStyle()) // Using a custom button style instead of .pressAnimation() extension to be safe
    }
}

// Simple scale button style to replicate .pressAnimation()
struct CreatorScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MomentsPressButtonStyle(scale: 0.95, pressedOpacity: 0.9, haptic: .light)
            .makeBody(configuration: configuration)
    }
}
