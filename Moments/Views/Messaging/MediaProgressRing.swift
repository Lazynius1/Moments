import SwiftUI

struct MediaProgressRing: View {
    let progress: Double // 0.0 to 1.0
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4
    
    private let signatureGradient = LinearGradient(
        colors: [Color.blue, Color.purple, Color.pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        ZStack {
            // Background Glass or semi-transparent circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
            
            // Track (faint signature gradient or white)
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
                .frame(width: size - lineWidth, height: size - lineWidth)
            
            // Progress Ring
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    signatureGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size - lineWidth, height: size - lineWidth)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            
            // Percentage Text (Small) - Optional, only if size > 50
            if size > 50 {
                Text("\(Int(progress * 100))%")
                    .font(.custom("Poppins-Bold", size: 10))
                    .foregroundColor(.white)
            }
        }
        .shadow(color: Color.purple.opacity(0.3), radius: 4)
    }
}

struct MediaProgressRing_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MediaProgressRing(progress: 0.65, size: 60)
        }
    }
}
