import SwiftUI

struct PhotoTagOverlayView: View {
    let tags: [PhotoTag]
    let isVisible: Bool
    var onTagTap: ((String) -> Void)? = nil // ✅ Callback for navigation
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isVisible {
                    ForEach(tags) { tag in
                        PhotoTagBubble(tag: tag, containerSize: geo.size)
                            .onTapGesture {
                                onTagTap?(tag.userId) // ✅ Trigger navigation
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
        }
        .allowsHitTesting(isVisible) // Only allow taps if visible
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isVisible)
    }
}

private struct PhotoTagBubble: View {
    let tag: PhotoTag
    let containerSize: CGSize
    @State private var isAnimating = false
    
    var body: some View {
        let xPos = CGFloat(tag.x) * containerSize.width
        let yPos = CGFloat(tag.y) * containerSize.height
        
        VStack(spacing: 4) {
            // Label bubble
            HStack(spacing: 4) {
                Text(tag.username)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
            )
            .background(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            
            // Triangle pointer
            Image(systemName: "triangle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.black.opacity(0.75))
                .rotationEffect(.degrees(180))
                .offset(y: -2)
        }
        .position(x: xPos, y: yPos - 30) // Offset upwards
        .onAppear {
            isAnimating = true
        }
    }
}
