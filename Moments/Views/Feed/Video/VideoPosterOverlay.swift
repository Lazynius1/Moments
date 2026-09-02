import Kingfisher
import SwiftUI

/// Poster obligatorio hasta que el vídeo esté listo para reproducir.
struct VideoPosterOverlay: View {
    let posterURLString: String?
    let isReadyToPlay: Bool
    var contentMode: SwiftUI.ContentMode = .fill
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if let posterURLString,
               let url = URL(string: posterURLString) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Color.black.opacity(0.85)
            }
        }
        .opacity(isReadyToPlay ? 0 : 1)
        .animation(.easeOut(duration: 0.08), value: isReadyToPlay)
        .allowsHitTesting(!isReadyToPlay)
    }
}
