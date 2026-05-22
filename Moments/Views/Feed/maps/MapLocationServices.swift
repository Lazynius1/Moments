import Foundation
import CoreLocation
import MapKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

class LocationSearchService {
    static let shared = LocationSearchService()
    private let db = Firestore.firestore()
    private let privacyService = PrivacyService()
    private let functionsRegion = "europe-southwest1"

    private init() {}

    private struct BackendMapMomentsResponse: Codable {
        let moments: [BackendMoment]
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
        completion: @escaping ([Moment]) -> Void
    ) {
        guard currentUserId != nil else {
            searchMomentsByLocationLegacy(
                locationName: locationName,
                currentUserId: currentUserId,
                completion: completion
            )
            return
        }

        fetchMapMomentsFromBackend(mode: .location(locationName), limit: 400) { [weak self] backendMoments in // ✅ Aumentado límite para no perder posts antiguos
            if let backendMoments {
                completion(backendMoments)
                return
            }

            self?.searchMomentsByLocationLegacy(
                locationName: locationName,
                currentUserId: currentUserId,
                completion: completion
            )
        }
    }

    func searchMomentsInRegion(
        region: MKCoordinateRegion,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        guard currentUserId != nil else {
            searchMomentsInRegionLegacy(
                region: region,
                currentUserId: currentUserId,
                completion: completion
            )
            return
        }

        fetchMapMomentsFromBackend(mode: .region(region), limit: 400) { [weak self] backendMoments in // ✅ Aumentado límite para no perder posts antiguos
            if let backendMoments {
                completion(backendMoments)
                return
            }

            self?.searchMomentsInRegionLegacy(
                region: region,
                currentUserId: currentUserId,
                completion: completion
            )
        }
    }

    private func fetchMapMomentsFromBackend(
        mode: MapQueryMode,
        limit: Int,
        completion: @escaping ([Moment]?) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            completion(nil)
            return
        }

        Task {
            do {
                let idToken = try await user.getIDToken()
                guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                    await MainActor.run { completion(nil) }
                    return
                }

                guard let url = URL(string: "https://\(functionsRegion)-\(projectId).cloudfunctions.net/getMapMomentsPage") else {
                    await MainActor.run { completion(nil) }
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
                    await MainActor.run { completion(nil) }
                    return
                }

                let decoded = try JSONDecoder().decode(BackendMapMomentsResponse.self, from: data)
                let moments = decoded.moments
                    .map { $0.toMoment() }
                    .filter { $0.isArchived != true }
                    .sorted { $0.timestamp > $1.timestamp }

                await MainActor.run { completion(moments) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }

    private func searchMomentsByLocationLegacy(
        locationName: String,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        let now = Date()

        db.collectionGroup("moments")
            .whereField("location", isEqualTo: locationName)
            .whereField("audience", isEqualTo: "everyone")
            .limit(to: 400) // ✅ Limite super alto para pillar posts antiguos sin saturar la RAM
            .getDocuments { [weak self] snapshot, error in
                if let _ = error {
                    completion([])
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }

                let group = DispatchGroup()
                var moments: [Moment] = []
                let syncQueue = DispatchQueue(label: "location.moments.sync")

                for document in documents {
                    group.enter()
                    do {
                        var moment = try document.data(as: Moment.self)
                        moment.id = document.documentID

                        guard moment.isArchived != true else {
                            group.leave()
                            continue
                        }

                        let isAuthor = (currentUserId == moment.authorId)
                        if !isAuthor,
                           let scheduledDate = moment.scheduledDate,
                           scheduledDate > now {
                            group.leave()
                            continue
                        }

                        guard moment.mapHasRenderableMedia,
                              !moment.username.isEmpty else {
                            group.leave()
                            continue
                        }

                        if let currentUserId = currentUserId {
                            self?.privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                                if canView {
                                    syncQueue.async {
                                        moments.append(moment)
                                    }
                                }
                                group.leave()
                            }
                        } else {
                            syncQueue.async {
                                moments.append(moment)
                            }
                            group.leave()
                        }
                    } catch {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    completion(moments.sorted { $0.timestamp > $1.timestamp })
                }
            }
    }

    private func searchMomentsInRegionLegacy(
        region: MKCoordinateRegion,
        currentUserId: String?,
        completion: @escaping ([Moment]) -> Void
    ) {
        let now = Date()
        let latitudeMin = max(-90.0, region.center.latitude - (region.span.latitudeDelta / 2.0))
        let latitudeMax = min(90.0, region.center.latitude + (region.span.latitudeDelta / 2.0))
        let longitudeMin = max(-180.0, region.center.longitude - (region.span.longitudeDelta / 2.0))
        let longitudeMax = min(180.0, region.center.longitude + (region.span.longitudeDelta / 2.0))

        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("locationCoordinate.latitude", isGreaterThanOrEqualTo: latitudeMin)
            .whereField("locationCoordinate.latitude", isLessThanOrEqualTo: latitudeMax)
            .order(by: "locationCoordinate.latitude")
            .limit(to: 400) // ✅ Limite super alto para pillar posts antiguos sin saturar la RAM
            .getDocuments { [weak self] snapshot, error in
                if let _ = error {
                    completion([])
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }

                let group = DispatchGroup()
                var moments: [Moment] = []
                let syncQueue = DispatchQueue(label: "location.region.moments.sync")

                for document in documents {
                    group.enter()
                    do {
                        var moment = try document.data(as: Moment.self)
                        moment.id = document.documentID

                        guard moment.isArchived != true else {
                            group.leave()
                            continue
                        }

                        let isAuthor = (currentUserId == moment.authorId)
                        if !isAuthor,
                           let scheduledDate = moment.scheduledDate,
                           scheduledDate > now {
                            group.leave()
                            continue
                        }

                        guard moment.mapHasRenderableMedia,
                              !moment.username.isEmpty else {
                            group.leave()
                            continue
                        }

                        guard let coordinate = moment.locationCoordinate else {
                            group.leave()
                            continue
                        }

                        guard coordinate.longitude >= longitudeMin, coordinate.longitude <= longitudeMax else {
                            group.leave()
                            continue
                        }

                        if let currentUserId = currentUserId {
                            self?.privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                                if canView {
                                    syncQueue.async {
                                        moments.append(moment)
                                    }
                                }
                                group.leave()
                            }
                        } else {
                            syncQueue.async {
                                moments.append(moment)
                            }
                            group.leave()
                        }
                    } catch {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    completion(moments.sorted { $0.timestamp > $1.timestamp })
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
