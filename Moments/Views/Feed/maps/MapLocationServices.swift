import Foundation
import CoreLocation
import MapKit
import FirebaseAuth
import FirebaseCore

class LocationSearchService {
    static let shared = LocationSearchService()
    private let functionsRegion = "europe-southwest1"

    private init() {}

    private struct BackendMapMomentsResponse: Codable {
        let moments: [BackendMoment]
        let source: String?
        let totalCandidates: Int?
    }

    private struct BackendMapStoriesResponse: Codable {
        let stories: [BackendMapStory]
        let source: String?
        let totalCandidates: Int?
    }

    private enum MapQueryMode {
        case location(String)
        case region(MKCoordinateRegion)
    }

    func searchMomentsByLocation(
        locationName: String,
        currentUserId: String?,
        completion: @escaping (Result<[Moment], MapServiceError>) -> Void
    ) {
        guard currentUserId != nil else {
            completion(.failure(.unauthenticated))
            return
        }

        fetchMapMomentsFromBackend(mode: .location(locationName), limit: 400, completion: completion)
    }

    func searchMomentsInRegion(
        region: MKCoordinateRegion,
        currentUserId: String?,
        completion: @escaping (Result<[Moment], MapServiceError>) -> Void
    ) {
        guard currentUserId != nil else {
            completion(.failure(.unauthenticated))
            return
        }

        fetchMapMomentsFromBackend(mode: .region(region), limit: 400, completion: completion)
    }

    func searchDiscoverContentInRegion(
        region: MKCoordinateRegion,
        completion: @escaping (MapDiscoverPayload) -> Void
    ) {
        guard Auth.auth().currentUser != nil else {
            completion(
                MapDiscoverPayload(
                    moments: [],
                    stories: [],
                    source: "unauthenticated",
                    momentsError: .unauthenticated,
                    storiesError: .unauthenticated
                )
            )
            return
        }

        let group = DispatchGroup()
        var moments: [Moment] = []
        var stories: [MapStoryPreview] = []
        var momentsError: MapServiceError?
        var storiesError: MapServiceError?

        group.enter()
        fetchMapMomentsFromBackend(mode: .region(region), limit: 120) { result in
            switch result {
            case .success(let fetchedMoments):
                moments = fetchedMoments
            case .failure(let error):
                momentsError = error
            }
            group.leave()
        }

        group.enter()
        fetchMapStoriesFromBackend(mode: .region(region), limit: 120) { result in
            switch result {
            case .success(let fetchedStories):
                stories = fetchedStories
            case .failure(let error):
                storiesError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion(
                MapDiscoverPayload(
                    moments: moments,
                    stories: stories,
                    source: "backend",
                    momentsError: momentsError,
                    storiesError: storiesError
                )
            )
        }
    }

    func searchStoriesByLocation(
        locationName: String,
        completion: @escaping (Result<[MapStoryPreview], MapServiceError>) -> Void
    ) {
        fetchMapStoriesFromBackend(mode: .location(locationName), limit: 120, completion: completion)
    }

    func buildFriendActivityPins(
        moments: [Moment],
        stories: [MapStoryPreview],
        followingIds: Set<String>,
        within hours: TimeInterval = 48 * 3600
    ) -> [MapFriendActivityPin] {
        let cutoff = Date().addingTimeInterval(-hours)
        var grouped: [String: (coordinate: CLLocationCoordinate2D, latest: Date, moments: Int, stories: Int, username: String, profile: String?)] = [:]

        for moment in moments where followingIds.contains(moment.authorId) && moment.timestamp >= cutoff {
            guard let coordinate = moment.locationCoordinate?.toCLLocationCoordinate2D,
                  CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let key = moment.authorId
            if var entry = grouped[key] {
                entry.moments += 1
                if moment.timestamp > entry.latest {
                    entry.latest = moment.timestamp
                    entry.coordinate = coordinate
                }
                grouped[key] = entry
            } else {
                grouped[key] = (
                    coordinate,
                    moment.timestamp,
                    1,
                    0,
                    moment.username,
                    moment.profileImagePath
                )
            }
        }

        for story in stories where followingIds.contains(story.authorId) && story.timestamp >= cutoff {
            guard let coordinate = story.coordinate, CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let key = story.authorId
            if var entry = grouped[key] {
                entry.stories += 1
                if story.timestamp > entry.latest {
                    entry.latest = story.timestamp
                    entry.coordinate = coordinate
                }
                grouped[key] = entry
            } else {
                grouped[key] = (
                    coordinate,
                    story.timestamp,
                    0,
                    1,
                    story.username,
                    story.profileImagePath
                )
            }
        }

        return grouped.map { authorId, value in
            MapFriendActivityPin(
                id: authorId,
                authorId: authorId,
                username: value.username,
                profileImagePath: value.profile,
                coordinate: value.coordinate,
                latestTimestamp: value.latest,
                momentCount: value.moments,
                storyCount: value.stories
            )
        }
        .sorted { $0.latestTimestamp > $1.latestTimestamp }
    }

    private func fetchMapMomentsFromBackend(
        mode: MapQueryMode,
        limit: Int,
        completion: @escaping (Result<[Moment], MapServiceError>) -> Void
    ) {
        postMapEndpoint(
            functionName: "getMapMomentsPage",
            mode: mode,
            limit: limit
        ) { result in
            guard case .success(let data) = result else {
                if case .failure(let error) = result {
                    completion(.failure(error))
                }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(BackendMapMomentsResponse.self, from: data)
                let moments = decoded.moments
                    .map { $0.toMoment() }
                    .filter { $0.isArchived != true && $0.mapHasRenderableMedia }
                    .sorted { $0.timestamp > $1.timestamp }
                completion(.success(moments))
            } catch {
                completion(.failure(.decoding))
            }
        }
    }

    private func fetchMapStoriesFromBackend(
        mode: MapQueryMode,
        limit: Int,
        completion: @escaping (Result<[MapStoryPreview], MapServiceError>) -> Void
    ) {
        postMapEndpoint(
            functionName: "getMapStoriesPage",
            mode: mode,
            limit: limit
        ) { result in
            guard case .success(let data) = result else {
                if case .failure(let error) = result {
                    completion(.failure(error))
                }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(BackendMapStoriesResponse.self, from: data)
                let stories = decoded.stories.map { $0.toStoryPreview() }
                completion(.success(stories))
            } catch {
                completion(.failure(.decoding))
            }
        }
    }

    private func postMapEndpoint(
        functionName: String,
        mode: MapQueryMode,
        limit: Int,
        completion: @escaping (Result<Data, MapServiceError>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(.unauthenticated))
            return
        }

        Task {
            do {
                let idToken = try await user.getIDToken()
                guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                    await MainActor.run { completion(.failure(.invalidConfiguration)) }
                    return
                }

                guard let url = URL(string: "https://\(functionsRegion)-\(projectId).cloudfunctions.net/\(functionName)") else {
                    await MainActor.run { completion(.failure(.invalidConfiguration)) }
                    return
                }

                var body: [String: Any] = ["limit": limit]
                switch mode {
                case .location(let locationName):
                    body["mode"] = "location"
                    body["locationName"] = locationName
                case .region(let region):
                    body["mode"] = "region"
                    body["centerLatitude"] = region.center.latitude
                    body["centerLongitude"] = region.center.longitude
                    body["latitudeDelta"] = region.span.latitudeDelta
                    body["longitudeDelta"] = region.span.longitudeDelta
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run { completion(.failure(.invalidResponse)) }
                    return
                }

                await MainActor.run { completion(.success(data)) }
            } catch {
                await MainActor.run { completion(.failure(.network)) }
            }
        }
    }
}

// ✅ CLASE LOCATIONUTILITIES (SIN CAMBIOS - YA ESTÁ BIEN)
class LocationUtilities: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationUtilities()
    private let locationManager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // Permisos denegados
            break
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            // Permisos denegados
            break
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }

        DispatchQueue.main.async {
            self.currentLocation = location
        }

        locationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Error de ubicación
    }

    static func getCoordinates(for locationName: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        let authStatus = CLLocationManager().authorizationStatus
        if authStatus == .denied || authStatus == .restricted {
            completion(nil)
            return
        }

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(locationName) { placemarks, error in
            guard error == nil else {
                completion(nil)
                return
            }

            if let placemark = placemarks?.first,
               let location = placemark.location {
                completion(location.coordinate)
            } else {
                completion(nil)
            }
        }
    }

    static func getLocationName(for coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard error == nil else {
                completion(nil)
                return
            }

            if let placemark = placemarks?.first {
                var locationComponents: [String] = []

                if let name = placemark.name {
                    locationComponents.append(name)
                } else if let locality = placemark.locality {
                    locationComponents.append(locality)
                }

                if let administrativeArea = placemark.administrativeArea {
                    locationComponents.append(administrativeArea)
                }

                if let country = placemark.country {
                    locationComponents.append(country)
                }

                let locationName = locationComponents.joined(separator: ", ")
                let finalName = locationName.isEmpty ? "Ubicación desconocida" : locationName
                completion(finalName)
            } else {
                completion("Ubicación desconocida")
            }
        }
    }

    func getCurrentLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                completion(self.currentLocation?.coordinate)
            }

        case .notDetermined:
            requestLocationPermission()
            completion(nil)

        default:
            completion(nil)
        }
    }

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }

    static func formatDistance(_ distanceInMeters: Double) -> String {
        if distanceInMeters < 1000 {
            return String(format: "%.0f m", distanceInMeters)
        } else {
            let kilometers = distanceInMeters / 1000
            return String(format: "%.1f km", kilometers)
        }
    }

    static func getLocationPermissionStatus() -> String {
        switch CLLocationManager().authorizationStatus {
        case .notDetermined:
            return "No determinado"
        case .restricted:
            return "Restringido"
        case .denied:
            return "Denegado"
        case .authorizedAlways:
            return "Autorizado siempre"
        case .authorizedWhenInUse:
            return "Autorizado en uso"
        @unknown default:
            return "Desconocido"
        }
    }
}
