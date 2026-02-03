import SwiftUI
import Kingfisher
import AVFoundation

/// An immersive, story-style viewer for view-once media in chat.
/// Features a top progress bar, glassmorphic header, and gesture-based interactions.
struct ViewOnceImmersiveViewer: View {
    let message: EnhancedMessage
    let onViewed: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // Playback state
    @State private var progress: Double = 0.0
    @State private var duration: Double = 5.0 // Default for images
    @State private var isPaused = false
    @State private var hasMarkedAsViewed = false
    
    // Interaction state
    @State private var dragOffset: CGFloat = 0
    @State private var isClosing = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Black background for the "canvas"
            Color.black.ignoresSafeArea()
            
            // Content layer
            Group {
                if message.type == .viewOnceImage {
                    imageContent
                } else if message.type == .viewOnceVideo {
                    videoContent
                }
            }
            .ignoresSafeArea() // ✅ Full screen content
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
                isPaused = pressing
            }, perform: {})
            
            // UI Overlay layer
            VStack(spacing: 0) {
                if message.type == .viewOnceVideo {
                    HStack(spacing: 4) {
                        StoryProgressBar(progress: progress / duration)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 4)
                } else {
                    // Constant space to keep header position consistent
                    Color.clear.frame(height: 7)
                }
                
                // Header
                HStack(spacing: 12) {
                    // Indicator for View-Once
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash.circle.fill")
                            .font(.system(size: 14))
                        Text(message.type == .viewOnceImage ? "chat.viewOnce.photo" : "chat.viewOnce.video")
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .textCase(.uppercase)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    )
                    
                    Spacer()
                    
                    // Close Button
                    Button(action: { closeViewer() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                
                Spacer()
                
                // Bottom warning
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text("chat.viewOnce.autoDelete")
                        .font(.custom("Poppins-Medium", size: 12))
                }
                .padding(.bottom, 40)
            }
        }
        .statusBar(hidden: false) // ✅ Show status bar (time, battery, etc.)
        .preferredColorScheme(.dark) // ✅ Ensure status bar is white on black background
        .offset(y: dragOffset)
        .animation(.interactiveSpring(), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        closeViewer()
                    } else {
                        dragOffset = 0
                    }
                }
        )
        .onReceive(timer) { _ in
            guard !isPaused && !isClosing else { return }
            
            if message.type == .viewOnceImage {
                if progress < duration {
                    progress += 0.1
                } else {
                    // For images, we don't auto-dismiss, we just stay at 100% 
                    // or we could loop the progress bar if desired.
                    // For now, let's just keep it at 100%.
                }
            }
        }
        .onAppear {
            markAsStarted()
        }
        .onDisappear {
            handleDeletionOnClose()
        }
    }
    
    // MARK: - Content Views
    
    private var imageContent: some View {
        KFImage(URL(string: message.mediaUrl ?? ""))
            .resizable()
            .scaledToFill() // ✅ Fill screen like stories
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
    
    private var videoContent: some View {
        Group {
            if let urlString = message.mediaUrl, let url = URL(string: urlString) {
                MomentsVideoPlayer(
                    url: url,
                    isLooping: true,
                    isPaused: isPaused, // ✅ Pass pause state
                    videoGravity: .resizeAspectFill, // ✅ Fill screen like stories
                    onDurationReceived: { dur in
                        self.duration = dur
                    },
                    onProgressUpdate: { current in
                        if !isPaused {
                            self.progress = current
                        }
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                    Text("chat.video.unavailable")
                        .font(.custom("Poppins-Medium", size: 16))
                }
                .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Helper Views
    
    struct StoryProgressBar: View {
        var progress: Double
        
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                    
                    Capsule()
                        .fill(Color(hex: "FFCC33")) // ✅ Ephemeral neon yellow
                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, progress))))
                }
            }
            .frame(height: 3)
        }
    }
    
    // MARK: - Actions
    
    private func markAsStarted() {
        guard !hasMarkedAsViewed else { return }
        hasMarkedAsViewed = true
        onViewed()
        
        AnalyticsService.shared.trackInteraction("view_once_immersive_opened", details: [
            "messageType": message.type.rawValue,
            "messageId": message.id
        ])
    }
    
    private func closeViewer() {
        isClosing = true
        dismiss()
    }
    
    private func handleDeletionOnClose() {
        AnalyticsService.shared.trackInteraction("view_once_immersive_closed_deleted", details: [
            "messageType": message.type.rawValue,
            "messageId": message.id
        ])
        
        // Trigger deletion via ChatService
        ChatService().deleteViewOnceAfterViewing(
            conversationId: message.conversationId,
            messageId: message.id
        ) { error in
            if let error = error {
                print("❌ Failed to delete view-once message: \(error.localizedDescription)")
            } else {
                print("✅ View-once message deleted successfully")
            }
        }
    }
}
