import Foundation
import CoreLocation
import MapKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

class LocationSearchService {
    static let shared = LocationSearchService()
    private let functionsRegion = "europe-southwest1"

    private init() {}

    private struct BackendMapMomentsResponse: Codable {
        let moments: [BackendMoment]
        let source: String?
        let totalCandidates: Int?
        let nextCursor: String?
    }

    private struct BackendMapStoriesResponse: Codable {
        let stories: [BackendMapStory]
        let source: String?
        let totalCandidates: Int?
        let nextCursor: String?
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
        followingOnly: Bool = false,
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
        var socialAuthorIds = Set<String>()
        var socialGraphError = false
        if followingOnly, let uid = Auth.auth().currentUser?.uid {
            socialAuthorIds.insert(uid)
            group.enter()
            Firestore.firestore().collection("users").document(uid).collection("following").getDocuments { snapshot, error in
                if error != nil || snapshot == nil {
                    socialGraphError = true
                } else if let snapshot {
                    socialAuthorIds.formUnion(snapshot.documents.map { ($0.data()["userId"] as? String) ?? $0.documentID })
                }
                group.leave()
            }
        }

        group.enter()
        fetchMapMomentsFromBackend(mode: .region(region), limit: 120, followingOnly: followingOnly) { result in
            switch result {
            case .success(let fetchedMoments):
                moments = fetchedMoments
            case .failure(let error):
                momentsError = error
            }
            group.leave()
        }

        group.enter()
        fetchMapStoriesFromBackend(mode: .region(region), limit: 120, followingOnly: followingOnly) { result in
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
                    moments: socialGraphError ? [] : (followingOnly ? moments.filter { socialAuthorIds.contains($0.authorId) } : moments),
                    stories: socialGraphError ? [] : (followingOnly ? stories.filter { socialAuthorIds.contains($0.authorId) } : stories),
                    source: "backend",
                    momentsError: socialGraphError ? .network : momentsError,
                    storiesError: socialGraphError ? .network : storiesError
                )
            )
        }
    }

    /// Both cursors belong to the frozen query, never the current moving camera.
    func searchContentPage(
        region: MKCoordinateRegion? = nil,
        locationName: String? = nil,
        followingOnly: Bool,
        momentsCursor: String? = nil,
        storiesCursor: String? = nil,
        loadMoments: Bool = true,
        loadStories: Bool = true,
        completion: @escaping (MapDiscoverPayload) -> Void
    ) {
        let mode: MapQueryMode
        if let locationName { mode = .location(locationName) }
        else if let region { mode = .region(region) }
        else { return }
        let group = DispatchGroup()
        var payload = MapDiscoverPayload(moments: [], stories: [], source: "backend", momentsError: nil, storiesError: nil)
        var fetchedMoments: [Moment] = []
        var fetchedStories: [MapStoryPreview] = []
        var momentError: MapServiceError?
        var storyError: MapServiceError?
        if loadMoments {
            group.enter()
            postMapEndpoint(functionName: "getMapMomentsPage", mode: mode, limit: 60,
                            followingOnly: followingOnly, paginate: true, cursor: momentsCursor) { result in
                switch result {
                case .success(let data):
                    do {
                        let page = try JSONDecoder().decode(BackendMapMomentsResponse.self, from: data)
                        fetchedMoments = page.moments.map { $0.toMoment() }.filter { $0.isArchived != true && $0.mapHasRenderableMedia }
                        payload.momentsCursor = page.nextCursor
                    } catch { momentError = .decoding }
                case .failure(let error): momentError = error
                }
                group.leave()
            }
        }
        if loadStories {
            group.enter()
            postMapEndpoint(functionName: "getMapStoriesPage", mode: mode, limit: 60,
                            followingOnly: followingOnly, paginate: true, cursor: storiesCursor) { result in
                switch result {
                case .success(let data):
                    do {
                        let page = try JSONDecoder().decode(BackendMapStoriesResponse.self, from: data)
                        fetchedStories = page.stories.map { $0.toStoryPreview() }
                        payload.storiesCursor = page.nextCursor
                    } catch { storyError = .decoding }
                case .failure(let error): storyError = error
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(MapDiscoverPayload(moments: fetchedMoments, stories: fetchedStories,
                source: "backend", momentsError: momentError, storiesError: storyError,
                momentsCursor: payload.momentsCursor, storiesCursor: payload.storiesCursor))
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
        followingOnly: Bool = false,
        completion: @escaping (Result<[Moment], MapServiceError>) -> Void
    ) {
        postMapEndpoint(
            functionName: "getMapMomentsPage",
            mode: mode,
            limit: limit,
            followingOnly: followingOnly
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
        followingOnly: Bool = false,
        completion: @escaping (Result<[MapStoryPreview], MapServiceError>) -> Void
    ) {
        postMapEndpoint(
            functionName: "getMapStoriesPage",
            mode: mode,
            limit: limit,
            followingOnly: followingOnly
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
        followingOnly: Bool = false,
        paginate: Bool = false,
        cursor: String? = nil,
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
                if followingOnly { body["scope"] = "following" }
                if paginate { body["paginate"] = true }
                if let cursor { body["cursor"] = cursor }
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
    private var pendingLocationCompletions: [(CLLocationCoordinate2D?) -> Void] = []
    private var locationRequestToken = UUID()

    var usableCurrentLocation: CLLocation? {
        guard let location = currentLocation,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 5_000,
              abs(location.timestamp.timeIntervalSinceNow) <= 60 else { return nil }
        return location
    }

    private func finishLocationRequest(with coordinate: CLLocationCoordinate2D?) {
        locationRequestToken = UUID()
        let completions = pendingLocationCompletions
        pendingLocationCompletions.removeAll()
        completions.forEach { $0(coordinate) }
    }

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
        guard let location = locations.last,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 5_000,
              abs(location.timestamp.timeIntervalSinceNow) <= 60 else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.finishLocationRequest(with: location.coordinate)
        }
        locationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.finishLocationRequest(with: self.usableCurrentLocation?.coordinate)
        }
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
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            completion(nil)
            return
        }
        if let location = usableCurrentLocation {
            completion(location.coordinate)
            return
        }
        pendingLocationCompletions.append(completion)
        guard pendingLocationCompletions.count == 1 else { return }
        let token = UUID()
        locationRequestToken = token
        locationManager.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard self.locationRequestToken == token else { return }
            self.finishLocationRequest(with: self.usableCurrentLocation?.coordinate)
        }
    }

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }

    static func formatDistance(_ distanceInMeters: Double) -> String {
        MomentsFormat.distance(distanceInMeters)
    }

    static func getLocationPermissionStatus() -> String {
        switch CLLocationManager().authorizationStatus {
        case .notDetermined:
            return NSLocalizedString("maps.permission.notDetermined", comment: "")
        case .restricted:
            return NSLocalizedString("maps.permission.restricted", comment: "")
        case .denied:
            return NSLocalizedString("maps.permission.denied", comment: "")
        case .authorizedAlways:
            return NSLocalizedString("maps.permission.authorizedAlways", comment: "")
        case .authorizedWhenInUse:
            return NSLocalizedString("maps.permission.authorizedWhenInUse", comment: "")
        @unknown default:
            return NSLocalizedString("maps.permission.unknown", comment: "")
        }
    }
}

// MARK: - Región inicial del mapa Discover

enum MapRegionStore {
    private static let lastRegionKey = "discoverMap.lastRegion"
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)

    /// Centro de España como fallback geográfico (no Madrid hardcoded).
    static let spainCenter = CLLocationCoordinate2D(latitude: 40.0, longitude: -4.0)

    static func initialRegion() -> MKCoordinateRegion {
        loadSavedRegion() ?? MKCoordinateRegion(center: spainCenter, span: defaultSpan)
    }

    static func save(region: MKCoordinateRegion) {
        let payload: [String: Double] = [
            "lat": region.center.latitude,
            "lon": region.center.longitude,
            "latDelta": region.span.latitudeDelta,
            "lonDelta": region.span.longitudeDelta
        ]
        UserDefaults.standard.set(payload, forKey: lastRegionKey)
    }

    private static func loadSavedRegion() -> MKCoordinateRegion? {
        guard let payload = UserDefaults.standard.dictionary(forKey: lastRegionKey) as? [String: Double],
              let lat = payload["lat"],
              let lon = payload["lon"],
              let latDelta = payload["latDelta"],
              let lonDelta = payload["lonDelta"] else {
            return nil
        }

        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)),
              latDelta.isFinite, lonDelta.isFinite, latDelta > 0, lonDelta > 0,
              !(abs(lat - 40) < 0.0001 && abs(lon + 4) < 0.0001) else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    static func resolveFallbackRegion(completion: @escaping (MKCoordinateRegion) -> Void) {
        if let saved = loadSavedRegion() {
            completion(saved)
            return
        }

        guard let userId = Auth.auth().currentUser?.uid else {
            completion(MKCoordinateRegion(center: spainCenter, span: defaultSpan))
            return
        }

        FirestoreService.shared.db.collection("users").document(userId).collection("moments")
            .order(by: "timestamp", descending: true)
            .limit(to: 8)
            .getDocuments { snapshot, _ in
                if let document = snapshot?.documents.first(where: { doc in
                    let data = doc.data()
                    return data["latitude"] != nil && data["longitude"] != nil
                }) {
                    let data = document.data()
                    if let lat = data["latitude"] as? Double,
                       let lon = data["longitude"] as? Double,
                       CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        completion(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                        ))
                        return
                    }
                }

                completion(MKCoordinateRegion(center: spainCenter, span: defaultSpan))
            }
    }
}

/// Título de lugar con ciudad: «Ciutat Vella, Barcelona».
enum MapLocationDisplayFormatter {
    private static var cityCache: [String: String] = [:]

    static func formattedTitle(place: String, city: String?) -> String {
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlace.isEmpty else { return city ?? "" }
        if trimmedPlace.contains(",") { return trimmedPlace }

        guard let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty else {
            return trimmedPlace
        }
        if trimmedPlace.localizedCaseInsensitiveContains(city) {
            return trimmedPlace
        }
        return "\(trimmedPlace), \(city)"
    }

    static func city(from placemark: CLPlacemark) -> String? {
        if let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines), !locality.isEmpty {
            return locality
        }
        if let area = placemark.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines), !area.isEmpty {
            return area
        }
        return nil
    }

    static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f|%.2f", coordinate.latitude, coordinate.longitude)
    }

    static func resolveTitle(
        place: String,
        coordinate: CLLocationCoordinate2D?,
        completion: @escaping (String) -> Void
    ) {
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPlace.contains(",") {
            completion(trimmedPlace)
            return
        }
        guard let coordinate else {
            completion(trimmedPlace)
            return
        }

        let key = cacheKey(for: coordinate)
        if let cachedCity = cityCache[key] {
            completion(formattedTitle(place: trimmedPlace, city: cachedCity))
            return
        }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Task {
            let placemarks: [CLPlacemark]
            do {
                placemarks = try await geocoder.reverseGeocodeLocation(location)
            } catch {
                await MainActor.run {
                    completion(trimmedPlace)
                }
                return
            }

            await MainActor.run {
                let resolvedCity = placemarks.first.flatMap { Self.city(from: $0) }
                if let resolvedCity, !resolvedCity.isEmpty {
                    cityCache[key] = resolvedCity
                }
                completion(formattedTitle(place: trimmedPlace, city: resolvedCity))
            }
        }
    }
}
