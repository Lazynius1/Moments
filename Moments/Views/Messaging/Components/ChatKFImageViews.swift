import SwiftUI
import Kingfisher

/// Carga de imágenes de chat con las opciones recomendadas de Kingfisher 8.x.
struct ChatKFImage: View {
    let url: URL?
    var downsamplingSize: CGSize? = nil

    var body: some View {
        Group {
            if let url {
                configuredImage(sourceView(for: url))
            } else {
                ChatMediaResolvingPlaceholder()
            }
        }
    }

    private func sourceView(for url: URL) -> KFImage {
        if url.isFileURL {
            KFImage(source: .provider(LocalFileImageDataProvider(fileURL: url)))
        } else {
            KFImage(url)
        }
    }

    @ViewBuilder
    private func configuredImage(_ image: KFImage) -> some View {
        if let downsamplingSize {
            image
                .placeholder { ChatMediaResolvingPlaceholder() }
                .loadTransition(.opacity, animation: .easeOut(duration: 0.2))
                .downsampling(size: downsamplingSize)
                .scaleFactor(UIScreen.main.scale)
                .resizable()
                .scaledToFill()
        } else {
            image
                .placeholder { ChatMediaResolvingPlaceholder() }
                .loadTransition(.opacity, animation: .easeOut(duration: 0.2))
                .resizable()
                .scaledToFill()
        }
    }
}
