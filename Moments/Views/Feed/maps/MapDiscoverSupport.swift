import Foundation
import CoreLocation
import MapKit

enum MapServiceError: Error, Equatable {
    case unauthenticated
    case invalidConfiguration
    case network
    case invalidResponse
    case decoding
}

enum MapDiscoverContentFilter: String, CaseIterable, Identifiable {
    case all
    case friends
    case places

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "maps.filter.all"
        case .friends: return "maps.filter.friends"
        case .places: return "maps.filter.places"
        }
    }
}

struct BackendMapStory: Codable, Identifiable {
    let id: String
    let authorId: String
    let username: String
    let profileImagePath: String?
    let timestamp: Double?
    let expirationDate: Double?
    let audience: String?
    let locationName: String?
    let locationCoordinate: Moment.LocationCoordinate?
    let locationFuzzed: Bool?
    let previewUrl: String?
    let contentType: String?

    func toStoryPreview() -> MapStoryPreview {
        MapStoryPreview(
            id: id,
            authorId: authorId,
            username: username,
            profileImagePath: profileImagePath,
            timestamp: timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(),
            locationName: locationName,
            coordinate: locationCoordinate?.toCLLocationCoordinate2D,
            previewURL: previewUrl,
            locationFuzzed: locationFuzzed == true
        )
    }
}

struct MapStoryPreview: Identifiable, Hashable {
    let id: String
    let authorId: String
    let username: String
    let profileImagePath: String?
    let timestamp: Date
    let locationName: String?
    let coordinate: CLLocationCoordinate2D?
    let previewURL: String?
    let locationFuzzed: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(authorId)
    }

    static func == (lhs: MapStoryPreview, rhs: MapStoryPreview) -> Bool {
        lhs.id == rhs.id && lhs.authorId == rhs.authorId
    }
}

struct MapFriendActivityPin: Identifiable, Hashable {
    let id: String
    let authorId: String
    let username: String
    let profileImagePath: String?
    let coordinate: CLLocationCoordinate2D
    let latestTimestamp: Date
    let momentCount: Int
    let storyCount: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MapFriendActivityPin, rhs: MapFriendActivityPin) -> Bool {
        lhs.id == rhs.id
    }
}

enum MapVisibilityPolicy {
    /// Si hay ubicación en el post, aparece en el mapa para quien pueda ver el contenido.
    /// `onlyMe` nunca sale en mapa ajeno; el resto lo decide `canViewerSeeMoment` / `canViewerSeeStory`.
    static func resolvedVisibility(hasLocation: Bool, audience: String?) -> String {
        guard hasLocation else { return "hidden" }
        if audience == "onlyMe" { return "hidden" }
        return "public"
    }

    static func storyMapLocation(from stickers: [StickerData]?) -> (name: String, coordinate: CLLocationCoordinate2D)? {
        guard let stickers else { return nil }
        for sticker in stickers where sticker.type == StickerItem.StickerType.location.rawValue {
            guard let latitude = sticker.latitude,
                  let longitude = sticker.longitude else { continue }
            let name = sticker.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (name, CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        return nil
    }
}

struct MapDiscoverPayload {
    let moments: [Moment]
    let stories: [MapStoryPreview]
    let source: String
    let momentsError: MapServiceError?
    let storiesError: MapServiceError?

    var hasContent: Bool {
        !moments.isEmpty || !stories.isEmpty
    }

    var isCompleteFailure: Bool {
        !hasContent && momentsError != nil && storiesError != nil
    }

    var hasPartialFailure: Bool {
        hasContent && (momentsError != nil || storiesError != nil)
    }
}

struct MapMomentDetailRoute: Identifiable {
    let id = UUID()
    let moments: [Moment]
    let initialIndex: Int
    let locationName: String
}

enum MapSheetPresentationDelay {
    static let dismissBeforeNextPresentation: TimeInterval = 0.45
    static let reopenBottomSheetAfterDetail: TimeInterval = 0.35
}

enum MapDiscoverTimeFilter: String, CaseIterable, Identifiable {
    case today
    case week
    case all

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .today: return "maps.timeFilter.today"
        case .week: return "maps.timeFilter.week"
        case .all: return "maps.timeFilter.all"
        }
    }

    var cutoffDate: Date? {
        switch self {
        case .today:
            return Calendar.current.date(byAdding: .hour, value: -24, to: Date())
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .all:
            return nil
        }
    }
}

enum MapDistanceFormatter {
    static func string(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) -> String? {
        guard let origin, CLLocationCoordinate2DIsValid(origin) else { return nil }
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let to = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let meters = from.distance(from: to)

        if meters < 1000 {
            return String(format: NSLocalizedString("maps.distance.meters", comment: "Distance in meters"), Int(meters))
        }
        let kilometers = meters / 1000
        if kilometers < 10 {
            return String(format: NSLocalizedString("maps.distance.kilometersDecimal", comment: "Distance in km with decimal"), kilometers)
        }
        return String(format: NSLocalizedString("maps.distance.kilometers", comment: "Distance in km"), Int(kilometers))
    }
}

enum MapRelativeTimeFormatter {
    static func string(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Reverse geocoding del centro del mapa con cache por celda (~1 km).
final class MapZoneContextService {
    static let shared = MapZoneContextService()

    private let geocoder = CLGeocoder()
    private var cache: [String: String] = [:]
    private var lastRequestedKey: String?

    private init() {}

    func zoneName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        let key = cacheKey(for: coordinate)

        if let cached = cache[key] {
            completion(cached)
            return
        }

        lastRequestedKey = key
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ) { [weak self] placemarks, _ in
            guard let self, self.lastRequestedKey == key else { return }

            let placemark = placemarks?.first
            let name = placemark?.subLocality
                ?? placemark?.locality
                ?? placemark?.administrativeArea

            DispatchQueue.main.async {
                if let name, !name.isEmpty {
                    self.cache[key] = name
                    completion(name)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f|%.2f", coordinate.latitude, coordinate.longitude)
    }
}
