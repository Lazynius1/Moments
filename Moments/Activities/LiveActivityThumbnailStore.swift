import UIKit

/// Escribe/borra las miniaturas que las Live Activities de subida (story/moment) leen
/// desde el App Group para mostrar una preview real en vez de un icono genérico.
enum LiveActivityThumbnailStore {
    private static let folderName = "LiveActivityThumbnails"
    private static let maxDimension: CGFloat = 200
    private static let jpegQuality: CGFloat = 0.6

    private static var folderURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.glowsyapp") else {
            return nil
        }
        let folder = containerURL.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Guarda una copia redimensionada de `image` y devuelve el nombre de fichero a pasar en los `ActivityAttributes`.
    static func save(_ image: UIImage, id: String) -> String? {
        guard let folderURL else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }
        let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height, 1)
        let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let resized = UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { return nil }
        let fileName = "\(id).jpg"
        let fileURL = folderURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    /// Borra la miniatura al terminar/cancelar la subida, para no acumular ficheros en el App Group.
    static func remove(id: String) {
        guard let folderURL else { return }
        let fileURL = folderURL.appendingPathComponent("\(id).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }
}
