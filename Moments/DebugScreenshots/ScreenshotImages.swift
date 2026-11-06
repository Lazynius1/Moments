#if DEBUG
import UIKit
import Kingfisher

/// Relación entre los assets de `ScreenshotAssets.xcassets` y sus URLs ficticias.
/// Las URLs son https (muchas vistas exigen `hasPrefix("http")`) sobre un dominio
/// `.invalid`, que nunca resuelve: el contenido lo sirve `ScreenshotURLProtocol`.
enum ScreenshotImages {
    static let host = "moments-screenshots.invalid"

    static let avatars = [
        "ss_me",
        "ss_avatar_lucia", "ss_avatar_theo", "ss_avatar_aiko", "ss_avatar_mateo",
        "ss_avatar_nora", "ss_avatar_sam", "ss_avatar_ines", "ss_avatar_kai"
    ]

    static let moments = [
        "ss_moment_beach_sunset", "ss_moment_rooftop_dinner", "ss_moment_mountain_lake",
        "ss_moment_latte", "ss_moment_concert", "ss_moment_night_market",
        "ss_moment_dog_park", "ss_moment_road_trip", "ss_moment_picnic",
        "ss_moment_ski", "ss_moment_birthday", "ss_moment_lisbon_tram"
    ]

    static let stories = ["ss_story_festival", "ss_story_sunrise", "ss_story_cooking"]

    static let extras = ["ss_hidden_polaroid", "ss_chat_photo", "ss_wallpaper"]

    static var allAssets: [String] { avatars + moments + stories + extras }

    static func url(_ asset: String) -> String {
        "https://\(host)/\(asset).jpg"
    }

    static func assetName(for url: URL) -> String {
        (url.lastPathComponent as NSString).deletingPathExtension
    }

    static func image(_ asset: String) -> UIImage? {
        UIImage(named: asset)
    }

    static func data(for url: URL) -> Data? {
        image(assetName(for: url))?.jpegData(compressionQuality: 0.9)
    }

    /// Precarga avatares y fotos en la caché en memoria de Kingfisher para que
    /// el primer frame ya salga con imagen (el protocolo cubre el resto).
    static func prefillCache() {
        for asset in avatars + moments + extras {
            guard let picture = image(asset) else { continue }
            ImageCache.default.store(picture, forKey: url(asset), toDisk: false)
        }
    }

    /// JPEG reducido en base64 para stickers que guardan la imagen en `content`.
    static func base64JPEG(_ asset: String, maxSide: CGFloat = 480) -> String {
        guard let source = image(asset) else { return "" }
        let longest = max(source.size.width, source.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: (source.size.width * scale).rounded(), height: (source.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)?.base64EncodedString() ?? ""
    }
}
#endif
