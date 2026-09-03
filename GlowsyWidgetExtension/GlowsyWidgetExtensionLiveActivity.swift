import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Localization Helper

/// Helper para cargar localizaciones desde el bundle del widget extension
private func localizedString(_ key: String, comment: String) -> String {
    return NSLocalizedString(key, bundle: Bundle.main, comment: comment)
}

// MARK: - Preview thumbnail (App Group)

/// Carga la miniatura real de la subida desde el contenedor compartido, si existe.
func liveActivityPreviewImage(fileName: String?) -> UIImage? {
    guard let fileName,
          let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.glowsyapp")
    else { return nil }
    let fileURL = containerURL.appendingPathComponent("LiveActivityThumbnails", isDirectory: true).appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return UIImage(data: data)
}

// MARK: - Thumbnail con anillo de progreso

/// Miniatura real de lo que se sube, con el anillo de progreso dibujado alrededor del borde.
/// Si no hay miniatura (p. ej. vídeo sin frame extraído aún), cae al icono genérico.
struct LiveActivityUploadThumbnail: View {
    let previewImage: UIImage?
    let systemIcon: String
    let status: String
    let progress: Double
    let gradient: LinearGradient
    var size: CGFloat = 44
    var ringWidth: CGFloat = 3

    private var cornerRadius: CGFloat { size * 0.24 }

    var body: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: systemIcon)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(gradient)
                    )
            }

            if status != "completed" {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.gray.opacity(0.25), lineWidth: ringWidth)
                    .frame(width: size, height: size)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(gradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

// MARK: - Story Upload Activity Attributes
@available(iOS 16.1, *)
public struct StoryUploadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var progress: Double
        public var status: String // "uploading", "processing", "completed", "failed"
        public var percentage: Int {
            Int(progress * 100)
        }
        
        public init(progress: Double, status: String) {
            self.progress = progress
            self.status = status
        }
    }
    
    public var storyId: String
    public var mediaType: String // "image" o "video"
    public var previewImageFileName: String? // nombre de fichero dentro del App Group, para mostrar miniatura real

    public init(storyId: String, mediaType: String, previewImageFileName: String? = nil) {
        self.storyId = storyId
        self.mediaType = mediaType
        self.previewImageFileName = previewImageFileName
    }
}

// MARK: - Moment Upload Activity Attributes
@available(iOS 16.1, *)
public struct MomentUploadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var progress: Double
        public var status: String // "uploading", "processing", "completed", "failed"
        public var percentage: Int {
            Int(progress * 100)
        }
        
        public init(progress: Double, status: String) {
            self.progress = progress
            self.status = status
        }
    }
    
    public var momentId: String
    public var mediaType: String // "image", "video", o "mixed"
    public var mediaCount: Int
    public var previewImageFileName: String? // nombre de fichero dentro del App Group, para mostrar miniatura real

    public init(momentId: String, mediaType: String, mediaCount: Int, previewImageFileName: String? = nil) {
        self.momentId = momentId
        self.mediaType = mediaType
        self.mediaCount = mediaCount
        self.previewImageFileName = previewImageFileName
    }
}

// MARK: - Story Upload Activity Widget
@available(iOS 16.1, *)
struct GlowsyWidgetExtensionLiveActivity: Widget {
    // Gradiente del story ring (paleta de marca: teal → azul)
    private var storyRingGradient: LinearGradient {
        LinearGradient(
            colors: [MomentsBrand.teal, MomentsBrand.blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // ✅ Lista de emojis para el easter egg al completar
    private let completionEmojis = ["😊", "😄", "✨", "🎉", "👍", "💫", "❤️", "🥳", "😎", "🔥"]
    
    // ✅ Función para obtener un emoji aleatorio
    private func getCompletionEmoji() -> String {
        return completionEmojis.randomElement() ?? "😊"
    }
    
    // ✅ Refinement: Rotating Aurora Orb (Premium micro-animation)
    private var rotatingAuroraOrb: some View {
        Circle()
            .fill(storyRingGradient)
            .frame(width: 8, height: 8)
            .blur(radius: 2)
            .phaseAnimator([0, 360]) { content, phase in
                content.rotationEffect(.degrees(phase))
            } animation: { _ in
                .linear(duration: 3).repeatForever(autoreverses: false)
            }
    }
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StoryUploadActivityAttributes.self) { context in
            // Lock screen/banner UI
            HStack(spacing: 12) {
                LiveActivityUploadThumbnail(
                    previewImage: liveActivityPreviewImage(fileName: context.attributes.previewImageFileName),
                    systemIcon: context.attributes.mediaType == "video" ? "video.fill" : "photo.fill",
                    status: context.state.status,
                    progress: context.state.progress,
                    gradient: storyRingGradient
                )

                Text(localizedString("liveActivity.uploadingStory", comment: "Uploading story title"))
                    .font(.headline)

                Spacer()

                if context.state.status == "completed" {
                    Text(getCompletionEmoji())
                        .font(.system(size: 24))
                } else {
                    Text("\(context.state.percentage)%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(storyRingGradient)
                        .monospacedDigit()
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.1))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        LiveActivityUploadThumbnail(
                            previewImage: liveActivityPreviewImage(fileName: context.attributes.previewImageFileName),
                            systemIcon: context.attributes.mediaType == "video" ? "video.fill" : "photo.fill",
                            status: context.state.status,
                            progress: context.state.progress,
                            gradient: storyRingGradient,
                            size: 36,
                            ringWidth: 2.5
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizedString("liveActivity.uploadingStory", comment: "Uploading story title"))
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(context.state.status == "uploading" ? localizedString("liveActivity.uploading", comment: "Uploading status") :
                                 context.state.status == "processing" ? localizedString("liveActivity.processing", comment: "Processing status") :
                                 context.state.status == "completed" ? localizedString("liveActivity.completed", comment: "Completed status") : localizedString("liveActivity.error", comment: "Error status"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if context.state.status == "completed" {
                            Text(getCompletionEmoji())
                                .font(.system(size: 32))
                        } else {
                            Text("\(context.state.percentage)%")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(storyRingGradient)
                                .monospacedDigit()

                            ProgressView(value: context.state.progress)
                                .tint(storyRingGradient)
                                .frame(width: 100)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Espacio adicional si es necesario
                }
            } compactLeading: {
                // Compact leading - icono o emoji
                if context.state.status == "completed" {
                    Text(getCompletionEmoji())
                        .font(.system(size: 16))
                } else {
                    Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : "photo.fill")
                        .foregroundStyle(storyRingGradient)
                }
            } compactTrailing: {
                // Compact trailing - porcentaje con círculo
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        
                        Circle()
                            .trim(from: 0, to: context.state.progress)
                            .stroke(storyRingGradient, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        // ✅ Refinement: Rotating Orb
                        if context.state.status == "uploading" {
                            rotatingAuroraOrb
                                .offset(y: -7)
                                .rotationEffect(.degrees(context.state.progress * 360))
                        }
                    }
                    .frame(width: 14, height: 14)
                    
                    Text("\(context.state.percentage)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(storyRingGradient)
                        .monospacedDigit()
                }
            } minimal: {
                // Minimal - solo icono con indicador de progreso o emoji
                if context.state.status == "completed" {
                    Text(getCompletionEmoji())
                        .font(.system(size: 18))
                } else {
                    ZStack {
                        Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : "photo.fill")
                            .foregroundStyle(storyRingGradient)
                        
                        if context.state.progress < 1.0 {
                            Circle()
                                .trim(from: 0, to: context.state.progress)
                                .stroke(storyRingGradient, lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Moment Upload Activity Widget
@available(iOS 16.1, *)
struct MomentUploadLiveActivity: Widget {
    // Gradiente del story ring (paleta de marca: teal → azul)
    private var storyRingGradient: LinearGradient {
        LinearGradient(
            colors: [MomentsBrand.teal, MomentsBrand.blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // ✅ Lista de emojis para el easter egg al completar
    private let completionEmojis = ["😊", "😄", "✨", "🎉", "👍", "💫", "❤️", "🥳", "😎", "🔥"]
    
    // ✅ Función para obtener un emoji aleatorio
    private func getCompletionEmoji() -> String {
        return completionEmojis.randomElement() ?? "😊"
    }
    
    // ✅ Refinement: Rotating Aurora Orb (shared)
    private var rotatingAuroraOrb: some View {
        Circle()
            .fill(storyRingGradient)
            .frame(width: 8, height: 8)
            .blur(radius: 2)
            .phaseAnimator([0, 360]) { content, phase in
                content.rotationEffect(.degrees(phase))
            } animation: { _ in
                .linear(duration: 3).repeatForever(autoreverses: false)
            }
    }
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MomentUploadActivityAttributes.self) { context in
            // Lock screen/banner UI
            HStack(spacing: 12) {
                LiveActivityUploadThumbnail(
                    previewImage: liveActivityPreviewImage(fileName: context.attributes.previewImageFileName),
                    systemIcon: context.attributes.mediaType == "video" ? "video.fill" :
                        context.attributes.mediaType == "mixed" ? "photo.stack.fill" : "photo.fill",
                    status: context.state.status,
                    progress: context.state.progress,
                    gradient: storyRingGradient
                )

                Text(localizedString("liveActivity.uploadingMoment", comment: "Uploading moment title"))
                    .font(.headline)

                Spacer()

                if context.state.status == "completed" {
                    Text(getCompletionEmoji())
                        .font(.system(size: 24))
                } else {
                    Text("\(context.state.percentage)%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(storyRingGradient)
                        .monospacedDigit()
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.1))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        LiveActivityUploadThumbnail(
                            previewImage: liveActivityPreviewImage(fileName: context.attributes.previewImageFileName),
                            systemIcon: context.attributes.mediaType == "video" ? "video.fill" :
                                context.attributes.mediaType == "mixed" ? "photo.stack.fill" : "photo.fill",
                            status: context.state.status,
                            progress: context.state.progress,
                            gradient: storyRingGradient,
                            size: 36,
                            ringWidth: 2.5
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizedString("liveActivity.uploadingMoment", comment: "Uploading moment title"))
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(context.state.status == "uploading" ? localizedString("liveActivity.uploading", comment: "Uploading status") :
                                 context.state.status == "processing" ? localizedString("liveActivity.processing", comment: "Processing status") :
                                 context.state.status == "completed" ? localizedString("liveActivity.completed", comment: "Completed status") : localizedString("liveActivity.error", comment: "Error status"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if context.state.status == "completed" {
                            Text(getCompletionEmoji())
                                .font(.system(size: 32))
                        } else {
                            Text("\(context.state.percentage)%")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(storyRingGradient)
                                .monospacedDigit()

                            ProgressView(value: context.state.progress)
                                .tint(storyRingGradient)
                                .frame(width: 100)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Espacio adicional si es necesario
                }
            } compactLeading: {
                // Compact leading - icono o emoji
                if context.state.status == "completed" {
                    Text(getCompletionEmoji())
                        .font(.system(size: 16))
                } else {
                    Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : 
                          context.attributes.mediaType == "mixed" ? "photo.stack.fill" : "photo.fill")
                        .foregroundStyle(storyRingGradient)
                }
            } compactTrailing: {
                // Compact trailing - porcentaje con círculo
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        
                        Circle()
                            .trim(from: 0, to: context.state.progress)
                            .stroke(storyRingGradient, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        
                        // ✅ Refinement: Rotating Orb
                        if context.state.status == "uploading" {
                            rotatingAuroraOrb
                                .offset(y: -7)
                                .rotationEffect(.degrees(context.state.progress * 360))
                        }
                    }
                    .frame(width: 14, height: 14)
                    
                    Text("\(context.state.percentage)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(storyRingGradient)
                        .monospacedDigit()
                }
            } minimal: {
                // Minimal - solo icono con indicador de progreso o emoji
                if context.state.status == "completed" {
                    Text(getCompletionEmoji())
                        .font(.system(size: 18))
                } else {
                    ZStack {
                        Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : 
                              context.attributes.mediaType == "mixed" ? "photo.stack.fill" : "photo.fill")
                            .foregroundStyle(storyRingGradient)
                        
                        if context.state.progress < 1.0 {
                            Circle()
                                .trim(from: 0, to: context.state.progress)
                                .stroke(storyRingGradient, lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                }
            }
        }
    }
}
