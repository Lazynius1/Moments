import SwiftUI
import Kingfisher
import AVFoundation
import AVKit

// MARK: - View-Once Message Bubble
struct ViewOnceMessageBubble: View {
    let message: EnhancedMessage
    let isCurrentUser: Bool
    let onViewed: () -> Void
    @State private var isViewed = false
    @State private var showFullScreen = false
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Group {
            if message.isViewed && !isCurrentUser {
                // ✅ Mensaje visto por el receptor - YA NO SE PUEDE ABRIR
                ViewOnceOpenedBubble(
                    message: message,
                    adaptiveColors: adaptiveColors
                )
                // ✅ SIN .onTapGesture - completamente inactivo
                
            } else if !message.isViewed && !isCurrentUser {
                // ✅ Mensaje no visto - SE PUEDE ABRIR
                ViewOnceUnreadBubble(
                    message: message,
                    adaptiveColors: adaptiveColors,
                    onTap: {
                        openViewOnceMessage()
                    }
                )
                
            } else {
                // ✅ Mensaje del usuario actual - muestra estado
                ViewOnceSentBubble(
                    message: message,
                    adaptiveColors: adaptiveColors
                )
                // ✅ El remitente tampoco puede re-abrir su propio mensaje
            }
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            ViewOnceFullScreenView(
                message: message,
                onViewed: {
                    isViewed = true
                    onViewed()
                }
            )
        }
    }
    
    private func openViewOnceMessage() {
        // ✅ Solo se puede abrir si NO ha sido visto
        guard !message.isViewed else {
            print("⚠️ View-once message already viewed, cannot open")
            return
        }
        
        showFullScreen = true
        AnalyticsService.shared.trackInteraction("view_once_message_opened", details: [
            "messageType": message.type.rawValue,
            "messageId": message.id
        ])
    }
}

// MARK: - Simplified View-Once Unread Bubble
struct ViewOnceUnreadBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(adaptiveColors.messageBubbleBackground)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: getIconName())
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "00A896"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(getTypeText())
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(adaptiveColors.messageTextColor)
                    
                    Text("Toca para ver")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7))
                    
                    // ✅ Mensaje simple
                    Text("📸 Se borrará al cerrar")
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(Color(hex: "00A896"))
                }
                
                Spacer()
                
                // Unopened indicator
                Circle()
                    .fill(Color(hex: "00A896"))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(adaptiveColors.messageBubbleBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func getIconName() -> String {
        switch message.type {
        case .viewOnceImage:
            return "camera.circle.fill"
        case .viewOnceVideo:
            return "video.circle.fill"
        default:
            return "camera.circle.fill"
        }
    }
    
    private func getTypeText() -> String {
        switch message.type {
        case .viewOnceImage:
            return "Foto"
        case .viewOnceVideo:
            return "Video"
        default:
            return "Media"
        }
    }
}

// MARK: - View-Once Opened Bubble
struct ViewOnceOpenedBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    
    var body: some View {
        HStack(spacing: 12) {
            // Opened icon
            Image(systemName: "eye.slash.circle")
                .font(.system(size: 20))
                .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(getTypeText())
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.7))
                
                Text("Ya visto")
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(adaptiveColors.messageTextColor.opacity(0.5))
                    .italic()
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(adaptiveColors.messageBubbleBackground.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(adaptiveColors.messageBubbleStroke, lineWidth: 0.5)
                )
        )
    }
    
    private func getTypeText() -> String {
        switch message.type {
        case .viewOnceImage:
            return "Foto vista"
        case .viewOnceVideo:
            return "Video visto"
        default:
            return "Media visto"
        }
    }
}

// MARK: - View-Once Sent Bubble
struct ViewOnceSentBubble: View {
    let message: EnhancedMessage
    let adaptiveColors: AdaptiveColors
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(getTypeText())
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("Ver una vez")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                if message.isViewed {
                    Text("✓ Visto")
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    Text("Enviado")
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Sent icon
            Image(systemName: getIconName())
                .font(.system(size: 20))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "00A896").opacity(0.8))
        )
    }
    
    private func getIconName() -> String {
        switch message.type {
        case .viewOnceImage:
            return "camera.fill"
        case .viewOnceVideo:
            return "video.fill"
        default:
            return "camera.fill"
        }
    }
    
    private func getTypeText() -> String {
        switch message.type {
        case .viewOnceImage:
            return "Foto"
        case .viewOnceVideo:
            return "Video"
        default:
            return "Media"
        }
    }
}

// MARK: - Simplified View-Once Full Screen View
struct ViewOnceFullScreenView: View {
    let message: EnhancedMessage
    let onViewed: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var hasBeenViewed = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if message.type == .viewOnceImage {
                    ViewOnceImageView(imageUrl: message.mediaUrl)
                } else if message.type == .viewOnceVideo {
                    SimpleViewOnceVideoView(videoUrl: message.mediaUrl)
                }
            }
            
            // Simple top overlay
            VStack {
                HStack {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.custom("Poppins-Medium", size: 16))
                    
                    Spacer()
                    
                    // Simple indicator
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash.circle.fill")
                            .font(.system(size: 16))
                        Text("Ver una vez")
                            .font(.custom("Poppins-Medium", size: 14))
                    }
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                }
                .padding()
                
                Spacer()
                
                // Simple bottom warning
                if !hasBeenViewed {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                            
                            Text("Se borrará al cerrar")
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                        )
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            markAsViewed()
        }
        .onDisappear {
            // Se borra al cerrar la vista
            if hasBeenViewed {
                triggerMessageDeletion()
            }
        }
    }
    
    private func markAsViewed() {
        guard !hasBeenViewed else { return }
        hasBeenViewed = true
        onViewed()
        
        AnalyticsService.shared.trackInteraction("view_once_opened", details: [
            "messageType": message.type.rawValue,
            "messageId": message.id
        ])
    }
    
    // ✅ Activar eliminación al cerrar
    private func triggerMessageDeletion() {
        AnalyticsService.shared.trackInteraction("view_once_closed_and_deleted", details: [
            "messageType": message.type.rawValue,
            "messageId": message.id
        ])
        
        // Marcar para eliminación inmediata
        ChatService().deleteViewOnceAfterViewing(
            conversationId: message.conversationId,
            messageId: message.id
        ) { error in
            if let error = error {
                print("❌ Error deleting view-once message: \(error.localizedDescription)")
            } else {
                print("✅ View-once message deleted successfully")
            }
        }
    }
}

// MARK: - Simplified Video View
struct SimpleViewOnceVideoView: View {
    let videoUrl: String?
    
    var body: some View {
        if let videoUrl = videoUrl, let url = URL(string: videoUrl) {
            VideoPlayer(player: AVPlayer(url: url))
                .onAppear {
                    // Auto-play
                    let player = AVPlayer(url: url)
                    player.play()
                }
        } else {
            VStack {
                Image(systemName: "video.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.5))
                Text("Video no disponible")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.custom("Poppins-Regular", size: 16))
            }
        }
    }
}

// ✅ NUEVO: Indicador de progreso del video
struct VideoProgressIndicator: View {
    let currentTime: Double
    let duration: Double
    
    private var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    private var timeRemaining: Int {
        guard duration > 0 else { return 0 }
        return max(0, Int(duration - currentTime))
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
                Text("\(timeRemaining)s")
                    .font(.custom("Poppins-Bold", size: 14))
            }
            .foregroundColor(.white)
            
            // Progress bar
            ProgressView(value: progressPercentage)
                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                .frame(width: 60)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
    }
}

// MARK: - View-Once Image View
struct ViewOnceImageView: View {
    let imageUrl: String?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    var body: some View {
        if let imageUrl = imageUrl, let url = URL(string: imageUrl) {
            KFImage(url)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = value
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                scale = max(1.0, min(scale, 3.0))
                            }
                        }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                                .onEnded { _ in
                                    withAnimation(.spring()) {
                                        offset = .zero
                                    }
                                }
                        )
                )
        } else {
            VStack {
                Image(systemName: "photo")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.5))
                Text("Imagen no disponible")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.custom("Poppins-Regular", size: 16))
            }
        }
    }
}

// MARK: - Enhanced View-Once Video View with Duration Tracking
struct ViewOnceVideoView: View {
    let videoUrl: String?
    let onDurationReceived: (Double) -> Void
    let onTimeUpdate: (Double) -> Void
    let onVideoFinished: () -> Void
    
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    
    var body: some View {
        Group {
            if let videoUrl = videoUrl, let url = URL(string: videoUrl) {
                ChatVideoPlayerView(
                    url: url,
                    onDurationReceived: onDurationReceived,
                    onTimeUpdate: onTimeUpdate,
                    onVideoFinished: onVideoFinished
                )
            } else {
                VStack {
                    Image(systemName: "video")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Video no disponible")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.custom("Poppins-Regular", size: 16))
                }
            }
        }
    }
}

// ✅ NUEVO: Video Player con tracking completo
struct ChatVideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    let onDurationReceived: (Double) -> Void
    let onTimeUpdate: (Double) -> Void
    let onVideoFinished: () -> Void
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.showsPlaybackControls = true
        
        // Set up observers
        setupPlayerObservers(player: player)
        
        // Auto-play
        player.play()
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
    
    private func setupPlayerObservers(player: AVPlayer) {
        // Observer para duración
        player.currentItem?.asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            DispatchQueue.main.async {
                if let duration = player.currentItem?.duration {
                    let durationSeconds = CMTimeGetSeconds(duration)
                    if !durationSeconds.isNaN && !durationSeconds.isInfinite {
                        onDurationReceived(durationSeconds)
                    }
                }
            }
        }
        
        // Observer para tiempo actual
        let timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 1),
            queue: .main
        ) { time in
            let currentSeconds = CMTimeGetSeconds(time)
            if !currentSeconds.isNaN && !currentSeconds.isInfinite {
                onTimeUpdate(currentSeconds)
            }
        }
        
        // Observer para fin del video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            onVideoFinished()
        }
    }
}
