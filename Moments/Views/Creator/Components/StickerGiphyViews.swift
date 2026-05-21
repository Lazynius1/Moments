import ImageIO
import SwiftUI
import UIKit

// MARK: - Animated GIF View
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.clear

        if let url = url {
            loadAnimatedGIF(url: url, into: imageView)
        }

        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    private func loadAnimatedGIF(url: URL, into imageView: UIImageView) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }

            DispatchQueue.main.async {
                if let animatedImage = UIImage.animatedImageWithData(data) {
                    imageView.image = animatedImage
                } else if let staticImage = UIImage(data: data) {
                    imageView.image = staticImage
                }
            }
        }.resume()
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
