import ImageIO
import SwiftUI
import UIKit

// MARK: - GIF/Sticker image cache (sobrevive al reciclado de celdas en LazyVStack)
final class ChatGIFImageCache {
    static let shared = ChatGIFImageCache()

    private let lock = NSLock()
    private var memory: [String: UIImage] = [:]
    private var inFlight: [String: [UUID: (UIImage?) -> Void]] = [:]

    func cachedImage(for url: URL) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return memory[url.absoluteString]
    }

    func load(url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString

        if let cached = cachedImage(for: url) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        let token = UUID()
        lock.lock()
        if var handlers = inFlight[key] {
            handlers[token] = completion
            inFlight[key] = handlers
            lock.unlock()
            return
        }
        inFlight[key] = [token: completion]
        lock.unlock()

        let finish: (UIImage?) -> Void = { image in
            self.lock.lock()
            if let image {
                self.memory[key] = image
            }
            let pending = self.inFlight.removeValue(forKey: key) ?? [:]
            let handlers = Array(pending.values)
            self.lock.unlock()
            DispatchQueue.main.async {
                handlers.forEach { $0(image) }
            }
        }

        if url.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url) else {
                    finish(nil)
                    return
                }
                finish(Self.decodeImage(from: data))
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil else {
                finish(nil)
                return
            }
            finish(Self.decodeImage(from: data))
        }.resume()
    }

    func prefetch(url: URL) {
        load(url: url) { _ in }
    }

    private static func decodeImage(from data: Data) -> UIImage? {
        if let animatedImage = UIImage.animatedImageWithData(data) {
            return animatedImage
        }
        return UIImage(data: data)
    }
}

// MARK: - Animated GIF View
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.clear
        imageView.isUserInteractionEnabled = false
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        context.coordinator.load(url: url, into: imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = .scaleAspectFit
        context.coordinator.load(url: url, into: uiView)
    }

    final class Coordinator {
        private var currentURL: URL?
        private var requestToken = UUID()

        func load(url: URL?, into imageView: UIImageView) {
            guard let url else {
                currentURL = nil
                imageView.image = nil
                return
            }

            if let cached = ChatGIFImageCache.shared.cachedImage(for: url) {
                currentURL = url
                imageView.image = cached
                return
            }

            let needsReload = currentURL != url || imageView.image == nil
            guard needsReload else { return }

            currentURL = url
            imageView.image = nil
            let token = UUID()
            requestToken = token

            ChatGIFImageCache.shared.load(url: url) { image in
                guard token == self.requestToken, self.currentURL == url else { return }
                imageView.image = image
            }
        }
    }
}

// MARK: - UIImage Extension para GIFs
extension UIImage {
    static func animatedImageWithData(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return UIImage(data: data)
        }

        var images: [UIImage] = []
        var totalDuration: Double = 0

        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }

            let image = UIImage(cgImage: cgImage)
            images.append(image)

            var frameDuration: Double = 0.1

            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {

                if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime] as? Double {
                    frameDuration = delayTime
                } else if let delayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
                    frameDuration = delayTime
                }

                frameDuration = max(frameDuration, 0.02)
            }

            totalDuration += frameDuration
        }

        guard !images.isEmpty else { return nil }

        return UIImage.animatedImage(with: images, duration: totalDuration)
    }
}

struct ModernGiphyGridView: View {
    let gifs: [GiphyGif]
    let onSelect: (GiphyGif) -> Void

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(gifs) { gif in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        onSelect(gif)
                    }
                }) {
                    if let url = URL(string: gif.images.fixed_height.url) {
                        AnimatedGIFView(url: url)
                            .frame(height: 120)
                            .clipped()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 120)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: gif.id)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Giphy Models
struct GiphyResponse: Codable {
    let data: [GiphyGif]
}

struct GiphyGif: Codable, Identifiable {
    let id: String
    let images: GiphyImages

    var preferredStickerURL: URL? {
        URL(string: images.original?.url ?? images.fixed_height.url)
    }

    /// Relación ancho/alto del preview `fixed_height` (para masonry de GIFs).
    var previewAspectRatio: CGFloat {
        let w = max(CGFloat(Int(images.fixed_height.width) ?? 1), 1)
        let h = max(CGFloat(Int(images.fixed_height.height) ?? 1), 1)
        return w / h
    }
}

struct GiphyImages: Codable {
    let fixed_height: GiphyImage
    let original: GiphyImage?
}

struct GiphyImage: Codable {
    let url: String
    let width: String
    let height: String
}
