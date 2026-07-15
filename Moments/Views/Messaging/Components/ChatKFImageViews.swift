import SwiftUI
import Kingfisher

/// Carga de imágenes de chat con las opciones recomendadas de Kingfisher 8.x.
struct ChatKFImage: View {
    @Environment(\.displayScale) private var displayScale
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
                .scaleFactor(displayScale)
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

/// Precalienta imágenes remotas de la galería del cluster en Kingfisher.
/// Las URLs locales (`file://`) ya vienen del caché descifrado y no necesitan prefetch.
enum ChatMediaGalleryPrefetcher {
    static func prefetch(messages: [EnhancedMessage]) {
        let remoteURLs = messages.compactMap { message -> URL? in
            let urlString: String?
            if message.type == .video {
                urlString = message.thumbnailUrl ?? message.mediaUrl
            } else {
                urlString = message.mediaUrl
            }
            guard let urlString, let url = URL(string: urlString), !url.isFileURL else { return nil }
            return url
        }

        guard !remoteURLs.isEmpty else { return }
        ImagePrefetchManager.shared.prefetch(urls: remoteURLs)
    }
}
