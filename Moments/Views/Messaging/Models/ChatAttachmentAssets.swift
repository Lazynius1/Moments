import Foundation
import CoreLocation

// MARK: - GIF asset (Giphy)

/// Asset ligero que representa un GIF de Giphy seleccionado en el chat.
struct ChatGiphyAsset: Identifiable, Hashable {
    let id: String
    /// URL animada preferida para descargar/enviar (normalmente `fixed_height` o `original`).
    let url: String
    let width: Int
    let height: Int

    init(id: String, url: String, width: Int = 0, height: Int = 0) {
        self.id = id
        self.url = url
        self.width = width
        self.height = height
    }

    init?(gif: GiphyGif) {
        let preferred = gif.images.original?.url ?? gif.images.fixed_height.url
        guard !preferred.isEmpty else { return nil }
        self.id = gif.id
        self.url = preferred
        self.width = Int(gif.images.fixed_height.width) ?? 0
        self.height = Int(gif.images.fixed_height.height) ?? 0
    }

    var downloadURL: URL? { URL(string: url) }
}

// MARK: - Sticker asset (Giphy + recientes)

/// Asset que representa un sticker (Giphy WebP/GIF) seleccionado en el chat.
struct ChatStickerAsset: Identifiable, Hashable, Codable {
    let id: String
    let url: String
    let width: Int
    let height: Int

    init(id: String, url: String, width: Int = 0, height: Int = 0) {
        self.id = id
        self.url = url
        self.width = width
        self.height = height
    }

    init?(gif: GiphyGif) {
        let preferred = gif.images.original?.url ?? gif.images.fixed_height.url
        guard !preferred.isEmpty else { return nil }
        self.id = gif.id
        self.url = preferred
        self.width = Int(gif.images.fixed_height.width) ?? 0
        self.height = Int(gif.images.fixed_height.height) ?? 0
    }

    var downloadURL: URL? { URL(string: url) }
}

// MARK: - Stickers recientes (persistencia local)

/// Guarda/recupera los últimos stickers usados en `UserDefaults` (estilo IG recientes).
enum ChatRecentStickersStore {
    private static let key = "chat.recentStickers.v1"
    private static let maxCount = 30

    static func load() -> [ChatStickerAsset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ChatStickerAsset].self, from: data)) ?? []
    }

    static func add(_ sticker: ChatStickerAsset) {
        var current = load().filter { $0.id != sticker.id }
        current.insert(sticker, at: 0)
        if current.count > maxCount {
            current = Array(current.prefix(maxCount))
        }
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Payload de ubicación (cifrado E2E dentro de `content`)

/// Coordenadas + metadatos de lugar que se serializan a JSON y se cifran como el texto.
/// Así la ubicación (lo sensible) viaja con el mismo cifrado E2E que los mensajes de texto.
struct ChatLocationPayload: Codable {
    let lat: Double
    let lng: Double
    let name: String?
    let address: String?

    init(lat: Double, lng: Double, name: String? = nil, address: String? = nil) {
        self.lat = lat
        self.lng = lng
        self.name = name
        self.address = address
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String) -> ChatLocationPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatLocationPayload.self, from: data)
    }
}

// MARK: - Duración de ubicación en vivo (estilo WhatsApp)

enum LiveLocationDuration: String, CaseIterable, Identifiable, Codable {
    case fifteenMinutes
    case oneHour
    case eightHours

    var id: String { rawValue }

    /// Valor persistido en Firestore (`liveLocationDuration`).
    var firestoreValue: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .oneHour: return "1h"
        case .eightHours: return "8h"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 60 * 60
        case .eightHours: return 8 * 60 * 60
        }
    }

    var localizedTitleKey: String {
        switch self {
        case .fifteenMinutes: return "chat.location.live15m"
        case .oneHour: return "chat.location.live1h"
        case .eightHours: return "chat.location.live8h"
        }
    }

    static func from(firestoreValue: String?) -> LiveLocationDuration? {
        guard let firestoreValue else { return nil }
        return LiveLocationDuration.allCases.first { $0.firestoreValue == firestoreValue }
    }
}
