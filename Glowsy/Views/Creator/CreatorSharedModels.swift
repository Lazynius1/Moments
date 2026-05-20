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
    
    enum AspectRatio: Equatable {
        case square          // 1:1
        case portrait        // 4:5
        case landscape       // 16:9
        case nineBySixteen   // 9:16 (stories)
        
        var value: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8  // 4:5
            case .landscape: return 1.777 // 16:9
            case .nineBySixteen: return 0.5625 // 9:16
            }
        }
        
        var displayName: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .landscape: return "16:9"
            case .nineBySixteen: return "9:16"
            }
        }
        
        var ratio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 4.0/5.0
            case .landscape: return 16.0/9.0
            case .nineBySixteen: return 9.0/16.0
            }
        }
        
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
    }
    
    // MARK: - Initializers & Helpers
    
    init(id: String, image: UIImage, videoURL: URL?, type: MediaType, aspectRatio: AspectRatio, recommendedAspectRatio: AspectRatio? = nil, hasEdits: Bool = false, thumbnailURL: URL? = nil, tags: [PhotoTag]? = nil, storyVideoMode: StoryVideoMode = .normal, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil) {
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
    }
    
    init(type: MediaType, image: UIImage, videoURL: URL?, aspectRatio: AspectRatio, recommendedAspectRatio: AspectRatio? = nil, thumbnailURL: URL? = nil, storyVideoMode: StoryVideoMode = .normal, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil) {
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
    }
    
    func with(videoURL: URL? = nil, aspectRatio: AspectRatio? = nil, recommendedAspectRatio: AspectRatio? = nil, hasEdits: Bool? = nil, thumbnailURL: URL? = nil, image: UIImage? = nil, tags: [PhotoTag]? = nil, storyVideoMode: StoryVideoMode? = nil, videoDuration: Double? = nil, videoFileSize: Int64? = nil, videoResolution: String? = nil) -> CreatorMedia {
        CreatorMedia(
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
    }
    
    var isValidVideo: Bool {
        return type == .video && videoURL != nil && FileManager.default.fileExists(atPath: videoURL!.path)
    }
    
    var videoInfo: (duration: Double, fileSize: Int64)? {
        guard let videoURL = videoURL, type == .video else { return nil }
        
        do {
            let asset = AVAsset(url: videoURL)
            let duration = asset.duration.seconds
            
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = fileAttributes[FileAttributeKey.size] as? Int64 ?? 0
            
            return (duration: duration, fileSize: fileSize)
        } catch {
            return nil
        }
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
                        Image(systemName: icon)
                            .font(.system(size: isSmall ? 10 : 12))
                    }
                }
            }
            .foregroundColor(.white)
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
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Selected Media Blur Background
// MARK: - Selected Media Blur Background
struct SelectedMediaBlurView: View {
    let mediaItems: [CreatorMedia]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base background
            Color.black.ignoresSafeArea()
            
            if !mediaItems.isEmpty {
                GeometryReader { geometry in
                    let displayItems = Array(mediaItems.prefix(4))
                    
                    ZStack {
                        // Dynamic layout based on count to fill space
                        switch displayItems.count {
                        case 1:
                            // Full screen
                            Image(uiImage: displayItems[0].image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                
                        case 2:
                            // Split vertically (Top/Bottom) with slight overlap
                            ForEach(0..<2, id: \.self) { index in
                                Image(uiImage: displayItems[index].image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.height * 0.6)
                                    .position(
                                        x: geometry.size.width / 2,
                                        y: index == 0 ? geometry.size.height * 0.25 : geometry.size.height * 0.75
                                    )
                            }
                            
                        case 3:
                            // Top half full width, bottom half split
                            ForEach(0..<3, id: \.self) { index in
                                let item = displayItems[index]
                                if index == 0 {
                                    // Top Hero
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geometry.size.width, height: geometry.size.height * 0.6)
                                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.25)
                                } else {
                                    // Bottom Left/Right
                                    let isRight = index == 2
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6)
                                        .position(
                                            x: isRight ? geometry.size.width * 0.75 : geometry.size.width * 0.25,
                                            y: geometry.size.height * 0.75
                                        )
                                }
                            }
                            
                        default: // 4 or more
                            // 2x2 Grid with overlap
                            ForEach(0..<displayItems.count, id: \.self) { index in
                                let item = displayItems[index]
                                let isRight = index % 2 != 0
                                let isBottom = index >= 2
                                
                                Image(uiImage: item.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6)
                                    .position(
                                        x: isRight ? geometry.size.width * 0.75 : geometry.size.width * 0.25,
                                        y: isBottom ? geometry.size.height * 0.75 : geometry.size.height * 0.25
                                    )
                            }
                        }
                    }
                    .blur(radius: 40) // Moderate blur as requested (balanced for text legibility vs aesthetics)
                    .overlay(Color.black.opacity(0.4)) // Darker overlay for text contrast
                }
                .ignoresSafeArea()
            } else {
                // Fallback gradient
                LinearGradient(
                    colors: [Color.black, Color.purple.opacity(0.2), Color.blue.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
    }
}
