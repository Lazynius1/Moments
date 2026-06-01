import CoreLocation
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Combine
import UIKit

struct LoginActivity: Identifiable {
    let id: String
    let timestamp: Date
    let device: String
    let location: String
    let ipAddress: String
    let isSuccessful: Bool
    let failureReason: String?
}

final class RealLoginActivityService: NSObject, ObservableObject {
    static let shared = RealLoginActivityService()

    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentLocationString: String = "Ubicacion no disponible"

    override init() {
        super.init()
        setupLocationManager()
    }

    // MARK: - Public Login Tracking
    func recordSuccessfulLogin(userId: String, method: String = "email") {
        locationManager.requestLocation()

        let now = Date()
        let deviceInfo = getCurrentDeviceInfo()
        let deviceFingerprint = currentDeviceFingerprint()
        let deviceDocId = hash(deviceFingerprint)
        let normalizedLocation = normalizeLocation(currentLocationString)

        let ref = db.collection("users")
            .document(userId)
            .collection("loginActivity")
            .document(deviceDocId)

        ref.getDocument { [weak self] snapshot, _ in
            guard let self = self else { return }

            let existing = snapshot?.data() ?? [:]
            let existed = snapshot?.exists == true

            let previousLocation = existing["locationNormalized"] as? String ?? "unknown"
            let hasPreviousLocation = previousLocation != "unknown"
            let hasCurrentLocation = normalizedLocation != "unknown"
            let locationChanged = existed && hasPreviousLocation && hasCurrentLocation && previousLocation != normalizedLocation

            var payload: [String: Any] = [
                "deviceDocId": deviceDocId,
                "deviceFingerprint": deviceFingerprint,
                "device": deviceInfo,
                "location": self.currentLocationString,
                "locationNormalized": normalizedLocation,
                "ipAddress": self.getCurrentIPAddress(),
                "isSuccessful": true,
                "isActive": true,
                "loginMethod": method,
                "lastSeenAt": Timestamp(date: now),
                "lastSuccessfulAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
                "isNewDevice": !existed,
                "isSuspicious": locationChanged,
                "coordinates": self.getCoordinatesDict()
            ]

            if !existed {
                payload["firstSeenAt"] = Timestamp(date: now)
            }

            if locationChanged {
                payload["suspiciousReason"] = "location_change"
                payload["lastLocationChangeAt"] = Timestamp(date: now)
            } else {
                payload["suspiciousReason"] = FieldValue.delete()
            }

            ref.setData(payload, merge: true)
        }
    }

    func trackFailedLoginAttempt(email: String, reason: String) {
        // Keep data minimal and only under loginActivity when a user is already authenticated.
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let deviceFingerprint = currentDeviceFingerprint()
        let deviceDocId = hash(deviceFingerprint)
        let ref = db.collection("users")
            .document(userId)
            .collection("loginActivity")
            .document(deviceDocId)

        ref.setData([
            "failedAttempts": FieldValue.increment(Int64(1)),
            "lastFailureReason": reason,
            "lastFailedAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    // MARK: - View Data
    func getCurrentSession(userId: String, completion: @escaping (LoginSession?) -> Void) {
        fetchActiveSessions(userId: userId) { result in
            switch result {
            case .failure:
                completion(nil)
            case .success(let sessions):
                guard !sessions.isEmpty else {
                    completion(nil)
                    return
                }

                let currentFingerprint = self.currentDeviceFingerprint()
                if let exact = sessions.first(where: { $0.deviceIdentifier == currentFingerprint }) {
                    completion(exact)
                    return
                }

                completion(sessions.first)
            }
        }
    }

    func fetchActiveSessions(userId: String, completion: @escaping (Result<[LoginSession], Error>) -> Void) {
        fetchLoginActivityDocuments(userId: userId) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let docs):
                let sessions = self.mapDocumentsToSessions(docs).filter { $0.isActive }
                completion(.success(sessions))
            }
        }
    }

    func fetchLoginActivity(userId: String, completion: @escaping (Result<[LoginActivity], Error>) -> Void) {
        fetchLoginActivityDocuments(userId: userId) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let docs):
                let activities = docs.compactMap { doc -> LoginActivity? in
                    let data = doc.data()
                    let timestamp = (data["lastSeenAt"] as? Timestamp)?.dateValue()
                        ?? (data["timestamp"] as? Timestamp)?.dateValue()
                        ?? (data["firstSeenAt"] as? Timestamp)?.dateValue()
                        ?? Date()
                    let device = data["device"] as? String ?? "Dispositivo desconocido"
                    let location = data["location"] as? String ?? "Ubicacion no disponible"
                    let ipAddress = data["ipAddress"] as? String ?? "No disponible"
                    let isSuccessful = data["isSuccessful"] as? Bool ?? true
                    return LoginActivity(
                        id: doc.documentID,
                        timestamp: timestamp,
                        device: device,
                        location: location,
                        ipAddress: ipAddress,
                        isSuccessful: isSuccessful,
                        failureReason: data["lastFailureReason"] as? String
                    )
                }
                completion(.success(activities.sorted { $0.timestamp > $1.timestamp }))
            }
        }
    }

    func invalidateSession(
        userId: String,
        session: LoginSession,
        signOutIfCurrentDevice: Bool,
        completion: @escaping (Error?) -> Void
    ) {
        let documentId: String
        if session.id == "local_current_session" {
            documentId = hash(currentDeviceFingerprint())
        } else {
            documentId = session.id
        }

        let now = Timestamp(date: Date())
        db.collection("users")
            .document(userId)
            .collection("loginActivity")
            .document(documentId)
            .setData([
                "isActive": false,
                "sessionRevokedAt": now,
                "sessionRevokedReason": "user_requested_logout_single",
                "updatedAt": now
            ], merge: true) { error in
                if error == nil, signOutIfCurrentDevice {
                    DispatchQueue.main.async { try? Auth.auth().signOut() }
                }
                completion(error)
            }
    }

    func invalidateAllSessions(userId: String, completion: @escaping (Error?) -> Void) {
        db.collection("users")
            .document(userId)
            .collection("loginActivity")
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(error)
                    return
                }

                guard let self = self else {
                    completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"]))
                    return
                }

                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    DispatchQueue.main.async { try? Auth.auth().signOut() }
                    completion(nil)
                    return
                }

                let now = Timestamp(date: Date())
                let batch = self.db.batch()
                for doc in docs {
                    batch.setData([
                        "isActive": false,
                        "sessionRevokedAt": now,
                        "sessionRevokedReason": "user_requested_logout_all",
                        "updatedAt": now
                    ], forDocument: doc.reference, merge: true)
                }

                batch.commit { commitError in
                    if commitError == nil {
                        DispatchQueue.main.async { try? Auth.auth().signOut() }
                    }
                    completion(commitError)
                }
            }
    }

    // MARK: - Location Access
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func getCurrentLocationString() -> String {
        currentLocationString
    }

    func getCoordinatesDict() -> [String: Double] {
        guard let location = currentLocation else { return [:] }
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]
    }

    // MARK: - Internal Fetch
    private func fetchLoginActivityDocuments(userId: String, completion: @escaping (Result<[QueryDocumentSnapshot], Error>) -> Void) {
        let collection = db.collection("users").document(userId).collection("loginActivity")

        collection
            .order(by: "lastSeenAt", descending: true)
            .limit(to: 80)
            .getDocuments { snapshot, error in
                if let snapshot = snapshot {
                    completion(.success(snapshot.documents))
                    return
                }

                collection
                    .order(by: "timestamp", descending: true)
                    .limit(to: 80)
                    .getDocuments { fallbackSnapshot, fallbackError in
                        if let fallbackSnapshot = fallbackSnapshot {
                            completion(.success(fallbackSnapshot.documents))
                        } else {
                            completion(.failure(fallbackError ?? error ?? NSError(domain: "", code: -1)))
                        }
                    }
            }
    }

    private func mapDocumentsToSessions(_ docs: [QueryDocumentSnapshot]) -> [LoginSession] {
        var dedupedByDevice: [String: LoginSession] = [:]

        for doc in docs {
            let data = doc.data()
            let deviceIdentifier = data["deviceFingerprint"] as? String
                ?? data["deviceIdentifier"] as? String
                ?? data["deviceId"] as? String
                ?? ""

            let device = data["device"] as? String ?? "Dispositivo desconocido"
            let location = data["location"] as? String ?? "Ubicacion no disponible"
            let ipAddress = data["ipAddress"] as? String ?? "No disponible"
            let isActive = data["isActive"] as? Bool ?? true
            let isSuspicious = data["isSuspicious"] as? Bool ?? false
            let isNewDevice = data["isNewDevice"] as? Bool ?? false
            let suspiciousReason = data["suspiciousReason"] as? String
            let timestamp = (data["lastSeenAt"] as? Timestamp)?.dateValue()
                ?? (data["timestamp"] as? Timestamp)?.dateValue()
                ?? (data["firstSeenAt"] as? Timestamp)?.dateValue()
                ?? Date()

            let key = canonicalSessionKey(
                deviceIdentifier: deviceIdentifier,
                device: device,
                location: location,
                ipAddress: ipAddress
            )

            let candidate = LoginSession(
                id: doc.documentID,
                device: device,
                location: location,
                ipAddress: ipAddress,
                timestamp: timestamp,
                isActive: isActive,
                deviceIdentifier: deviceIdentifier.isEmpty ? nil : deviceIdentifier,
                isSuspicious: isSuspicious,
                isNewDevice: isNewDevice,
                suspiciousReason: suspiciousReason
            )

            if let existing = dedupedByDevice[key], existing.timestamp >= candidate.timestamp {
                continue
            }
            dedupedByDevice[key] = candidate
        }

        return dedupedByDevice.values.sorted { $0.timestamp > $1.timestamp }
    }

    private func canonicalSessionKey(
        deviceIdentifier: String,
        device: String,
        location: String,
        ipAddress: String
    ) -> String {
        let normalizedDeviceIdentifier = deviceIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !normalizedDeviceIdentifier.isEmpty {
            return "fingerprint:\(normalizedDeviceIdentifier)"
        }

        let normalizedDevice = device
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedIp = normalizeIPAddress(ipAddress)
        if !normalizedIp.isEmpty {
            return "device_ip:\(normalizedDevice)|\(normalizedIp)"
        }

        let normalizedLocation = normalizeLocation(location)
        return "device_location:\(normalizedDevice)|\(normalizedLocation)"
    }

    private func normalizeIPAddress(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty || normalized == "no disponible" || normalized == "n/a" || normalized == "unknown" {
            return ""
        }
        return normalized
    }

    // MARK: - Device / Location Helpers
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }

    func currentDeviceDisplayName() -> String {
        getCurrentDeviceInfo()
    }

    private func getCurrentDeviceInfo() -> String {
        let identifier = hardwareIdentifier()
        let modelName = humanReadableModel(for: identifier)
        return "\(modelName) - iOS \(UIDevice.current.systemVersion)"
    }

    private func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partialResult, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partialResult.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    private func humanReadableModel(for identifier: String) -> String {
        let knownModels: [String: String] = [
            // iPhone 17 family / Air / 17e
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone18,4": "iPhone Air",
            "iPhone18,5": "iPhone 17e",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus"
        ]
        if let model = knownModels[identifier] {
            return model
        }
        return identifier
    }

    private func currentDeviceFingerprint() -> String {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString, !vendorId.isEmpty {
            return vendorId
        }
        return getCurrentDeviceInfo()
    }

    private func normalizeLocation(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if folded.isEmpty { return "unknown" }

        let invalidMarkers = [
            "ubicacion no disponible",
            "error al obtener ubicacion",
            "permisos de ubicacion denegados",
            "location unavailable",
            "unknown"
        ]

        if invalidMarkers.contains(where: { folded.contains($0) }) {
            return "unknown"
        }

        return folded
    }

    private func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func getCurrentIPAddress() -> String {
        var address = "No disponible"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }

        return address
    }
}

extension RealLoginActivityService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateLocationString()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        currentLocationString = "Ubicacion no disponible"
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            currentLocationString = "Ubicacion no disponible"
        default:
            break
        }
    }

    private func updateLocationString() {
        guard let location = currentLocation else {
            currentLocationString = "Ubicacion no disponible"
            return
        }

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self = self, let placemark = placemarks?.first else {
                self?.currentLocationString = "Ubicacion no disponible"
                return
            }

            var components: [String] = []
            if let city = placemark.locality { components.append(city) }
            if let country = placemark.country { components.append(country) }

            if components.isEmpty {
                if let area = placemark.administrativeArea { components.append(area) }
                if let country = placemark.country { components.append(country) }
            }

            self.currentLocationString = components.isEmpty ? "Ubicacion no disponible" : components.joined(separator: ", ")
        }
    }
}
