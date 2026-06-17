import Foundation
import CoreLocation
import Combine
import FirebaseAuth

/// Gestiona una sesión de ubicación en vivo: actualiza la posición en Firestore con throttle,
/// soporta background y expira automáticamente según la duración elegida.
@MainActor
final class LiveLocationSharingService: NSObject, ObservableObject {
    static let shared = LiveLocationSharingService()

    struct ActiveSession: Equatable, Codable {
        let ownerUserId: String
        let conversationId: String
        let messageId: String
        let sessionId: String
        let duration: LiveLocationDuration
        let expiresAt: Date
    }

    @Published private(set) var activeSession: ActiveSession?

    private let locationManager = CLLocationManager()
    private let chatService = ChatService.shared
    private var expirationTimer: Timer?
    private var lastUpdateSentAt: Date?
    private let minUpdateInterval: TimeInterval = 10
    private var lastSentCoordinate: CLLocationCoordinate2D?

    /// Evita reanudaciones concurrentes (restoreIfNeeded se llama desde varios puntos).
    private var isRestoring = false

    /// Clave de persistencia para reanudar la sesión tras reabrir la app.
    private let persistenceKey = "liveLocationSharing.activeSession"

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .otherNavigation
    }

    var hasActiveSession: Bool { activeSession != nil }

    func isSharing(conversationId: String) -> Bool {
        activeSession?.conversationId == conversationId
    }

    /// Inicia el tracking en vivo para un mensaje ya creado en Firestore.
    func startSession(
        conversationId: String,
        messageId: String,
        sessionId: String,
        duration: LiveLocationDuration,
        expiresAt: Date
    ) {
        // Si había una sesión anterior, detenerla primero.
        if let existing = activeSession {
            chatService.stopLiveLocationMessage(conversationId: existing.conversationId, messageId: existing.messageId)
        }

        let session = ActiveSession(
            ownerUserId: Auth.auth().currentUser?.uid ?? "",
            conversationId: conversationId,
            messageId: messageId,
            sessionId: sessionId,
            duration: duration,
            expiresAt: expiresAt
        )
        activeSession = session
        persist(session)
        lastUpdateSentAt = nil
        lastSentCoordinate = nil

        beginTracking(expiresAt: expiresAt)
    }

    /// Reanuda una sesión persistida tras reabrir la app.
    /// Solo reanuda si la sesión pertenece al usuario actual, no ha caducado
    /// y el servidor confirma que sigue activa (no detenida desde otro dispositivo).
    func restoreIfNeeded() {
        guard activeSession == nil, !isRestoring else { return }
        guard let session = loadPersistedSession() else { return }

        // Sin sesión de usuario todavía (p. ej. arranque muy temprano): no tocar
        // la persistencia y reintentar en la próxima llamada.
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // La sesión persistida pertenece a otro usuario de este dispositivo.
        guard session.ownerUserId == currentUserId else {
            clearPersistedSession()
            return
        }

        // Caducada localmente: limpiar y marcar parada por seguridad.
        guard session.expiresAt > Date() else {
            clearPersistedSession()
            chatService.stopLiveLocationMessage(
                conversationId: session.conversationId,
                messageId: session.messageId
            )
            return
        }

        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }

            // Validar el estado real en el servidor antes de empezar a publicar.
            guard let status = await chatService.fetchLiveLocationStatus(
                conversationId: session.conversationId,
                messageId: session.messageId
            ) else {
                // Error de red: conservar persistencia y reintentar más tarde.
                return
            }

            guard status.exists,
                  status.senderId == currentUserId,
                  !status.isStopped else {
                clearPersistedSession()
                return
            }

            if let serverExpiry = status.expiresAt, serverExpiry <= Date() {
                clearPersistedSession()
                return
            }

            // Otra llamada pudo haber reanudado/iniciado mientras tanto.
            guard activeSession == nil else { return }

            activeSession = session
            lastUpdateSentAt = nil
            lastSentCoordinate = nil
            beginTracking(expiresAt: session.expiresAt)
        }
    }

    private func beginTracking(expiresAt: Date) {
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        // Muestra la píldora/indicador de ubicación en la barra de estado y Dynamic Island
        // mientras la app está en segundo plano, igual que WhatsApp.
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.startUpdatingLocation()

        scheduleExpiration(at: expiresAt)
    }

    /// Detiene la sesión activa (parada manual o por expiración).
    func stop(markStopped: Bool = true) {
        guard let session = activeSession else { return }
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        expirationTimer?.invalidate()
        expirationTimer = nil

        if markStopped {
            chatService.stopLiveLocationMessage(
                conversationId: session.conversationId,
                messageId: session.messageId
            )
        }
        activeSession = nil
        clearPersistedSession()
        lastUpdateSentAt = nil
        lastSentCoordinate = nil
    }

    /// Detiene tracking y marca el mensaje como parado en Firestore.
    func stopSharing(messageId: String, conversationId: String) {
        if let session = activeSession {
            if session.messageId == messageId || session.conversationId == conversationId {
                stop(markStopped: true)
                return
            }
        }
        clearPersistedSession()
        chatService.stopLiveLocationMessage(
            conversationId: conversationId,
            messageId: messageId
        )
    }

    /// Detiene la sesión solo si corresponde al mensaje indicado.
    func stop(messageId: String) {
        guard activeSession?.messageId == messageId else { return }
        stop(markStopped: true)
    }

    /// Limpieza al cerrar sesión: detiene el GPS y borra la persistencia local
    /// para que la sesión no se reanude bajo otra cuenta del mismo dispositivo.
    func handleUserSignedOut() {
        if activeSession != nil {
            // En este punto Auth ya es nil, así que no intentamos escribir en
            // servidor (fallaría por permisos). El stop en servidor se hace antes
            // del signOut vía `endActiveSessionForSignOut()`.
            stop(markStopped: false)
        } else {
            clearPersistedSession()
        }
        isRestoring = false
    }

    /// Marca la sesión activa como detenida en servidor mientras las credenciales
    /// siguen siendo válidas y espera a que la escritura termine; después apaga el
    /// GPS y limpia la persistencia. Debe llamarse ANTES de `Auth.signOut()`.
    func endActiveSessionForSignOut() async {
        guard let session = activeSession else {
            clearPersistedSession()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            chatService.stopLiveLocationMessage(
                conversationId: session.conversationId,
                messageId: session.messageId
            ) { _ in
                continuation.resume()
            }
        }
        // Teardown local sin volver a escribir en servidor (ya lo hicimos arriba).
        stop(markStopped: false)
    }

    // MARK: - Persistencia

    private func persist(_ session: ActiveSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func loadPersistedSession() -> ActiveSession? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(ActiveSession.self, from: data)
    }

    private func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    private func scheduleExpiration(at date: Date) {
        expirationTimer?.invalidate()
        let interval = max(1, date.timeIntervalSinceNow)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stop(markStopped: true)
            }
        }
        expirationTimer = timer
    }

    private func handleNewLocation(_ location: CLLocation) {
        guard let session = activeSession else { return }

        if Date() >= session.expiresAt {
            stop(markStopped: true)
            return
        }

        let now = Date()
        if let last = lastUpdateSentAt, now.timeIntervalSince(last) < minUpdateInterval {
            return
        }

        // Evitar updates si el desplazamiento es mínimo (<10 m) salvo el primero.
        if let lastCoord = lastSentCoordinate {
            let previous = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            if location.distance(from: previous) < 10 { return }
        }

        lastUpdateSentAt = now
        lastSentCoordinate = location.coordinate
        chatService.updateLiveLocationMessage(
            conversationId: session.conversationId,
            messageId: session.messageId,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}

extension LiveLocationSharingService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handleNewLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silencioso: se reintentará en la próxima actualización.
    }
}
