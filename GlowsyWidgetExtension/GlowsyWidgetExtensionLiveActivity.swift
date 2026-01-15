import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Localization Helper

/// Helper para cargar localizaciones desde el bundle del widget extension
private func localizedString(_ key: String, comment: String) -> String {
    return NSLocalizedString(key, bundle: Bundle.main, comment: comment)
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
    
    public init(storyId: String, mediaType: String) {
        self.storyId = storyId
        self.mediaType = mediaType
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
    
    public init(momentId: String, mediaType: String, mediaCount: Int) {
        self.momentId = momentId
        self.mediaType = mediaType
        self.mediaCount = mediaCount
    }
}

// MARK: - Story Upload Activity Widget
@available(iOS 16.1, *)
struct GlowsyWidgetExtensionLiveActivity: Widget {
    // ✅ Gradiente del story ring (azul → morado → rosa)
    private var storyRingGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple, Color.pink],
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
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StoryUploadActivityAttributes.self) { context in
            // Lock screen/banner UI
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if context.state.status == "completed" {
                        Text(getCompletionEmoji())
                            .font(.system(size: 24))
                    } else {
                        Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : "photo.fill")
                            .foregroundStyle(storyRingGradient)
                    }
                    
                    Text(localizedString("liveActivity.uploadingStory", comment: "Uploading story title"))
                        .font(.headline)
                    
                    Spacer()
                    
                    if context.state.status == "completed" {
                        Text(localizedString("liveActivity.completed", comment: "Completed status"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(storyRingGradient)
                    } else {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                                
                                Circle()
                                    .trim(from: 0, to: context.state.progress)
                                    .stroke(storyRingGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 20, height: 20)
                            
                            Text("\(context.state.percentage)%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(storyRingGradient)
                        }
                    }
                }
                
                ProgressView(value: context.state.progress)
                    .tint(storyRingGradient)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.1))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        if context.state.status == "completed" {
                            Text(getCompletionEmoji())
                                .font(.system(size: 28))
                        } else {
                            Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : "photo.fill")
                                .foregroundStyle(storyRingGradient)
                                .font(.title2)
                        }
                        
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
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                    
                                    Circle()
                                        .trim(from: 0, to: context.state.progress)
                                        .stroke(storyRingGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                }
                                .frame(width: 32, height: 32)
                                
                                Text("\(context.state.percentage)%")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(storyRingGradient)
                            }
                            
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
                    }
                    .frame(width: 14, height: 14)
                    
                    Text("\(context.state.percentage)%")
                        .font(.system(size: 12, weight: .semibold))
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
    // ✅ Gradiente del story ring (azul → morado → rosa)
    private var storyRingGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple, Color.pink],
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
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MomentUploadActivityAttributes.self) { context in
            // Lock screen/banner UI
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if context.state.status == "completed" {
                        Text(getCompletionEmoji())
                            .font(.system(size: 24))
                    } else {
                        Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : 
                              context.attributes.mediaType == "mixed" ? "photo.stack.fill" : "photo.fill")
                            .foregroundStyle(storyRingGradient)
                    }
                    
                    Text(localizedString("liveActivity.uploadingMoment", comment: "Uploading moment title"))
                        .font(.headline)
                    
                    Spacer()
                    
                    if context.state.status == "completed" {
                        Text(localizedString("liveActivity.completed", comment: "Completed status"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(storyRingGradient)
                    } else {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                                
                                Circle()
                                    .trim(from: 0, to: context.state.progress)
                                    .stroke(storyRingGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 20, height: 20)
                            
                            Text("\(context.state.percentage)%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(storyRingGradient)
                        }
                    }
                }
                
                ProgressView(value: context.state.progress)
                    .tint(storyRingGradient)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.1))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        if context.state.status == "completed" {
                            Text(getCompletionEmoji())
                                .font(.system(size: 28))
                        } else {
                            Image(systemName: context.attributes.mediaType == "video" ? "video.fill" : 
                                  context.attributes.mediaType == "mixed" ? "photo.stack.fill" : "photo.fill")
                                .foregroundStyle(storyRingGradient)
                                .font(.title2)
                        }
                        
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
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                                    
                                    Circle()
                                        .trim(from: 0, to: context.state.progress)
                                        .stroke(storyRingGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                }
                                .frame(width: 32, height: 32)
                                
                                Text("\(context.state.percentage)%")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(storyRingGradient)
                            }
                            
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
                    }
                    .frame(width: 14, height: 14)
                    
                    Text("\(context.state.percentage)%")
                        .font(.system(size: 12, weight: .semibold))
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
