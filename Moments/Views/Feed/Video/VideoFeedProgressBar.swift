import SwiftUI

/// Barra de progreso aislada para no invalidar el reproductor completo en cada tick.
struct VideoFeedProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 2)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * progress, height: 2)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 0)
        .padding(.bottom, 0)
    }
}
