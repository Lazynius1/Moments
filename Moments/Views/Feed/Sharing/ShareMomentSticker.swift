import SwiftUI
import Kingfisher

struct ShareMomentSticker: View {
    let moment: Moment
    let profileImage: UIImage?
    let contentImage: UIImage?
    var renderClean: Bool = false // ✅ NUEVO: Para capturar sin overlays
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .top) { // Use ZStack to layer content and header
            // 1. MAIN CONTENT (Image/Video + Caption)
            ZStack(alignment: .bottom) {
                if let contentImage = contentImage {
                    Image(uiImage: contentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 260, height: calculatedHeight)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 260, height: calculatedHeight)
                }
                
                // Video Play Icon Overlay
                if moment.videoUrl != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // CAPTION (Floating at bottom)
                if !moment.content.isEmpty && !renderClean {
                    Text(moment.content)
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(12)
                        .padding(.bottom, 8) // Adjusted spacing since no watermark
                }
                
                // GALLERY INDICATOR (Top Right)
                if (moment.mediaItems?.count ?? 0) > 1 && !renderClean {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "square.on.square.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(12)
                                .padding(.top, 42) // Positioned below the header text
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 260, height: calculatedHeight)
            
            // 2. FLOATING HEADER (Overlay Layer)
            if !renderClean {
                HStack(spacing: 10) {
                    // Profile Image with Glow
                    if let profileImage = profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.5), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 34, height: 34)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                            .font(.system(size: legacyPoppinsSize(13), weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                colors: [.black, .black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
        }
        .frame(width: 260)
        .background(
            ZStack {
                // Base solid for better clipping
                RoundedRectangle(cornerRadius: FeedMomentCardLayout.mediaCornerRadius, style: .continuous)
                    .fill(Color(white: 0.1))
                
                // Deep glass material
                RoundedRectangle(cornerRadius: FeedMomentCardLayout.mediaCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: FeedMomentCardLayout.mediaCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FeedMomentCardLayout.mediaCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.05), .white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
    }
    
    // ✅ CALCULAR ALTURA DINÁMICA SEGÚN ASPECT RATIO
    private var calculatedHeight: CGFloat {
        if let ratioString = moment.aspectRatio {
            let components = ratioString.split(separator: ":")
            if components.count == 2,
               let w = Double(components[0]),
               let h = Double(components[1]) {
                let ratio = CGFloat(h / w)
                // Capped ratio to avoid extremes (max 16:9, min 4:5ish)
                let finalRatio = min(max(ratio, 0.5), 1.8) 
                return 260 * finalRatio
            }
        }
        
        // Fallback: Usar dimensiones de la imagen si no hay metadata
        if let contentImage = contentImage {
            let ratio = contentImage.size.height / contentImage.size.width
            let finalRatio = min(max(ratio, 0.5), 1.8)
            return 260 * finalRatio
        }
        
        return 340 // Fallback estándar (aprox 3:4)
    }
}
