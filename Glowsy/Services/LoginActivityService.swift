import FirebaseFirestore
import FirebaseAuth
import UIKit
import CoreLocation

struct LoginActivity: Identifiable {
    let id: String
    let timestamp: Date
    let device: String
    let location: String
    let ipAddress: String
    let isSuccessful: Bool
    let failureReason: String?
}

// MARK: - RealLoginActivityService.swift (Archivo separado - SIN extensiones de AnalyticsService)
class RealLoginActivityService: NSObject, ObservableObject {
    static let shared = RealLoginActivityService()
    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentLocationString: String = "Ubicación no disponible"
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Location Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // Precisión de ciudad
        
        // Request permission if not already granted
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }
    
    // MARK: - Get Current Session
    func getCurrentSession(userId: String, completion: @escaping (LoginSession?) -> Void) {
        if let currentSessionId = AnalyticsService.shared.getCurrentSessionId() {
            db.collection("users").document(userId).collection("sessions")
                .document(currentSessionId)
                .getDocument { [weak self] snapshot, _ in
                    guard let self = self else {
                        completion(nil)
                        return
                    }
                    
                    if let snapshot = snapshot,
                       let session = self.makeSession(from: snapshot),
                       session.isActive {
                        completion(session)
                        return
                    }
                    
                    self.fetchMostRecentActiveSession(userId: userId, completion: completion)
                }
            return
        }
        
        fetchMostRecentActiveSession(userId: userId, completion: completion)
    }

    func fetchActiveSessions(userId: String, completion: @escaping (Result<[LoginSession], Error>) -> Void) {
        db.collection("users").document(userId).collection("sessions")
            .whereField("isActive", isEqualTo: true)
            .order(by: "startTime", descending: true)
            .limit(to: 60)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let self = self else {
                    completion(.success([]))
                    return
                }
                
                let sessions = snapshot?.documents.compactMap { self.makeSession(from: $0) } ?? []
                let dedupedSessions = self.dedupeSessionsByDevice(sessions)
                completion(.success(dedupedSessions))
            }
    }
    
    // MARK: - Fetch Login Activity
    func fetchLoginActivity(userId: String, completion: @escaping (Result<[LoginActivity], Error>) -> Void) {
        db.collection("users").document(userId).collection("loginActivity")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                // Agrupar por dispositivo, tomar el más reciente
                var latestByDevice: [String: LoginActivity] = [:]
                snapshot?.documents.forEach { doc in
                    let data = doc.data()
                    guard let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                          let device = data["device"] as? String,
                          let location = data["location"] as? String,
                          let ipAddress = data["ipAddress"] as? String,
                          let isSuccessful = data["isSuccessful"] as? Bool else { return }

                    let activity = LoginActivity(
                        id: doc.documentID,
                        timestamp: timestamp,
                        device: device,
                        location: location,
                        ipAddress: ipAddress,
                        isSuccessful: isSuccessful,
                        failureReason: data["failureReason"] as? String
                    )

                    if let existing = latestByDevice[device], existing.timestamp > timestamp {
                        return
                    }
                    latestByDevice[device] = activity
                }

                let activities = Array(latestByDevice.values).sorted { $0.timestamp > $1.timestamp }.prefix(5)
                completion(.success(Array(activities)))
            }
    }
    // MARK: - Invalidate All Sessions
    func invalidateAllSessions(userId: String, completion: @escaping (Error?) -> Void) {
        // Get all active sessions
        db.collection("users").document(userId).collection("sessions")
            .whereField("isActive", isEqualTo: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(error)
                    return
                }
                
                guard let self = self else {
                    completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"]))
                    return
                }
                
                let batch = self.db.batch()
                var hasUpdates = false
                
                snapshot?.documents.forEach { document in
                    batch.updateData([
                        "isActive": false,
                        "endTime": Timestamp(date: Date()),
                        "logoutReason": "user_requested_logout_all",
                        "logoutLocation": self.currentLocationString
                    ], forDocument: document.reference)
                    hasUpdates = true
                }
                
                if hasUpdates {
                    batch.commit { error in
                        if let error = error {
                            completion(error)
                        } else {
                            // Log the logout event
                            self.logLogoutEvent(userId: userId, reason: "logout_all_sessions")
                            
                            // Force logout the user
                            DispatchQueue.main.async {
                                try? Auth.auth().signOut()
                            }
                            completion(nil)
                        }
                    }
                } else {
                    completion(nil)
                }
            }
    }
    
    // MARK: - Track Failed Login Attempt
    func trackFailedLoginAttempt(email: String, reason: String) {
        let loginData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "device": getCurrentDeviceInfo(),
            "location": currentLocationString,
            "ipAddress": getCurrentIPAddress(),
            "isSuccessful": false,
            "failureReason": reason,
            "attemptedEmail": email,
            "coordinates": getCoordinatesDict()
        ]
        
        // Store in a general failed attempts collection since we don't have userId
        db.collection("failedLoginAttempts").addDocument(data: loginData)
    }
    
    // MARK: - Location Methods
    private func updateLocationString() {
        guard let location = currentLocation else {
            currentLocationString = "Ubicación no disponible"
            return
        }
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self,
                  let placemark = placemarks?.first else {
                self?.currentLocationString = "Ubicación no disponible"
                return
            }
            
            var locationComponents: [String] = []
            
            if let city = placemark.locality {
                locationComponents.append(city)
            }
            
            if let country = placemark.country {
                locationComponents.append(country)
            }
            
            if locationComponents.isEmpty {
                if let administrativeArea = placemark.administrativeArea {
                    locationComponents.append(administrativeArea)
                }
                if let country = placemark.country {
                    locationComponents.append(country)
                }
            }
            
            self.currentLocationString = locationComponents.isEmpty ?
                "Ubicación no disponible" : locationComponents.joined(separator: ", ")
        }
    }
    
    func getCoordinatesDict() -> [String: Double] {
        guard let location = currentLocation else {
            return [:]
        }
        
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]
    }
    
    // MARK: - Log Logout Event
    private func logLogoutEvent(userId: String, reason: String) {
        let logoutData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "device": getCurrentDeviceInfo(),
            "location": currentLocationString,
            "ipAddress": getCurrentIPAddress(),
            "logoutReason": reason,
            "sessionId": AnalyticsService.shared.getCurrentSessionId() ?? "unknown",
            "coordinates": getCoordinatesDict()
        ]
        
        db.collection("users").document(userId).collection("logoutActivity").addDocument(data: logoutData)
    }
    
    // MARK: - Helper Methods
    private func getCurrentDeviceInfo() -> String {
        let device = UIDevice.current
        return "\(device.model) - iOS \(device.systemVersion)"
    }
    
    private func getCurrentIPAddress() -> String {
        // In production, you'd want to get the real IP from your backend
        // This is a simplified version for local network IP
        var address: String = "No disponible"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    
                    let name: String = String(cString: (interface.ifa_name))
                    if name == "en0" || name == "en2" || name == "en3" || name == "en4" || name == "pdp_ip0" || name == "pdp_ip1" || name == "pdp_ip2" || name == "pdp_ip3" {
                        
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    // MARK: - Public Location Methods
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func getCurrentLocationString() -> String {
        return currentLocationString
    }

    // MARK: - Session helpers
    private func fetchMostRecentActiveSession(userId: String, completion: @escaping (LoginSession?) -> Void) {
        db.collection("users").document(userId).collection("sessions")
            .whereField("isActive", isEqualTo: true)
            .order(by: "startTime", descending: true)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, _ in
                guard let self = self else {
                    completion(nil)
                    return
                }
                
                if let document = snapshot?.documents.first,
                   let session = self.makeSession(from: document) {
                    completion(session)
                    return
                }
                
                completion(
                    LoginSession(
                        id: UUID().uuidString,
                        device: self.getCurrentDeviceInfo(),
                        location: self.currentLocationString,
                        ipAddress: self.getCurrentIPAddress(),
                        timestamp: Date(),
                        isActive: true,
                        deviceIdentifier: UIDevice.current.identifierForVendor?.uuidString
                    )
                )
            }
    }
    
    private func makeSession(from snapshot: DocumentSnapshot) -> LoginSession? {
        guard snapshot.exists else { return nil }
        
        let data = snapshot.data() ?? [:]
        let deviceInfo = data["deviceInfo"] as? [String: Any] ?? [:]
        let deviceModel = deviceInfo["model"] as? String ?? "iPhone"
        let systemVersion = deviceInfo["systemVersion"] as? String ?? ""
        let location = data["location"] as? String ?? "Ubicación no disponible"
        let ipAddress = data["ipAddress"] as? String ?? "No disponible"
        let startTime = (data["startTime"] as? Timestamp)?.dateValue() ?? Date()
        let isActive = data["isActive"] as? Bool ?? false
        let deviceIdentifier = (deviceInfo["identifierForVendor"] as? String) ?? (data["deviceId"] as? String)
        
        let deviceLabel = systemVersion.isEmpty ? deviceModel : "\(deviceModel) - iOS \(systemVersion)"
        
        return LoginSession(
            id: snapshot.documentID,
            device: deviceLabel,
            location: location,
            ipAddress: ipAddress,
            timestamp: startTime,
            isActive: isActive,
            deviceIdentifier: deviceIdentifier
        )
    }
    
    private func dedupeSessionsByDevice(_ sessions: [LoginSession]) -> [LoginSession] {
        var seenKeys = Set<String>()
        var deduped: [LoginSession] = []
        
        for session in sessions.sorted(by: { $0.timestamp > $1.timestamp }) {
            let key = normalizedSessionKey(for: session)
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)
            deduped.append(session)
        }
        
        return deduped
    }
    
    private func normalizedSessionKey(for session: LoginSession) -> String {
        if let deviceIdentifier = session.deviceIdentifier,
           !deviceIdentifier.isEmpty,
           deviceIdentifier.lowercased() != "unknown" {
            return "device:\(deviceIdentifier.lowercased())"
        }
        
        return "fallback:\(session.device.lowercased())|\(session.location.lowercased())|\(session.ipAddress.lowercased())"
    }
}

// MARK: - CLLocationManagerDelegate
extension RealLoginActivityService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateLocationString()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        currentLocationString = "Error al obtener ubicación"
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            currentLocationString = "Permisos de ubicación denegados"
        default:
            currentLocationString = "Ubicación no disponible"
        }
    }
} 
