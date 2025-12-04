import Foundation
import Combine

class OnlineStatusService: ObservableObject {
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var onlineStatusTimer: Timer?
    private var lastActivityTimer: Timer?
    
    // ✅ NUEVO: Timers para cambios automáticos de estado
    private var awayTimer: Timer?
    private var offlineTimer: Timer?
    
    @Published var currentUserStatus: OnlineStatus = .offline
    @Published var isOnline: Bool = false
    @Published var lastSeen: Date = Date()
    
    // ✅ NUEVO: Variable para guardar el estado anterior (solo si era online o away) var previousOnlineStatus: OnlineStatus?
    
    init() {
        setupOnlineStatusTracking()
        // ✅ NUEVO: Sincronizar estado local con Firestore
        syncStatusWithFirestore()
    }
    
    deinit {
        onlineStatusTimer?.invalidate()
        lastActivityTimer?.invalidate()
        awayTimer?.invalidate()
        offlineTimer?.invalidate()
    }
    
    // MARK: - Setup
    private func setupOnlineStatusTracking() {
        // Actualizar estado cada 30 segundos
        onlineStatusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateOnlineStatus()
        }
        
        // Actualizar lastSeen cada 5 minutos
        lastActivityTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.updateLastSeen()
        }
        
        // ✅ MEJORADO: Actualizar estado cuando la app entra en background/foreground
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func setStatus(_ status: OnlineStatus) {
        guard let userId = Auth.auth().currentUser?.uid else { 
            return 
        }
        
        
        // ✅ MEJORADO: Cancelar timers automáticos si es un cambio manual
        awayTimer?.invalidate()
        offlineTimer?.invalidate()
        awayTimer = nil
        offlineTimer = nil
        
        // ✅ MEJORADO: Actualizar estado local inmediatamente
        DispatchQueue.main.async {
            self.currentUserStatus = status
            self.isOnline = status == .online
        }
        
        let data: [String: Any] = [
            "onlineStatus": status.rawValue,
            "isOnline": status == .online,
            "lastSeen": FieldValue.serverTimestamp()
        ]
        
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
                // ✅ NUEVO: Revertir estado local si hay error
                DispatchQueue.main.async {
                    self.currentUserStatus = .offline
                    self.isOnline = false
                }
            } else {
            }
        }
    }
    
    func setGlobalStatus(_ status: OnlineStatus) {
        setStatus(status)
    }
    
    func setConversationStatus(_ status: OnlineStatus, for conversationId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let data: [String: Any] = [
            "conversationStatus": [
                conversationId: [
                    "status": status.rawValue,
                    "timestamp": FieldValue.serverTimestamp()
                ]
            ]
        ]
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
            } else {
            }
        }
    }
    
    func getConversationStatus(for conversationId: String, completion: @escaping (OnlineStatus?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil)
            return
        }
        
        db.collection("users").document(userId).getDocument { document, error in
            if let document = document, document.exists {
                let data = document.data()
                if let conversationStatus = data?["conversationStatus"] as? [String: [String: Any]],
                   let conversationData = conversationStatus[conversationId],
                   let statusString = conversationData["status"] as? String {
                    let status = OnlineStatus(rawValue: statusString) ?? .offline
                    completion(status)
                } else {
                    completion(nil)
                }
            } else {
                completion(nil)
            }
        }
    }
    
    func observeUserStatus(userId: String, completion: @escaping (OnlineStatus, Date?) -> Void) -> ListenerRegistration {
        return db.collection("users").document(userId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot else {
                    return
                }
                
                let data = document.data()
                let statusString = data?["onlineStatus"] as? String ?? "offline"
                let status = OnlineStatus(rawValue: statusString) ?? .offline
                
                var lastSeen: Date?
                if let timestamp = data?["lastSeen"] as? Timestamp {
                    lastSeen = timestamp.dateValue()
                }
                
                completion(status, lastSeen)
            }
    }
    
    // MARK: - Private Methods
    private func updateOnlineStatus() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let data: [String: Any] = [
            "isOnline": isOnline,
            "lastSeen": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
            } else {
            }
        }
    }
    
    private func updateLastSeen() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let data: [String: Any] = [
            "lastSeen": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
            } else {
            }
        }
    }
    
    // ✅ NUEVO: Sincronizar estado local con Firestore
    private func syncStatusWithFirestore() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        
        db.collection("users").document(userId).getDocument { [weak self] document, error in
            if let error = error {
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let statusString = data["onlineStatus"] as? String,
                  let status = OnlineStatus(rawValue: statusString) else {
                return
            }
            
            DispatchQueue.main.async {
                self?.currentUserStatus = status
                self?.isOnline = status == .online
            }
        }
    }
    
    // MARK: - Utility Methods
    func formatLastSeen(_ date: Date?) -> String {
        guard let date = date else { return NSLocalizedString("onlineStatus.unknown", comment: "Unknown status") }
        
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return NSLocalizedString("onlineStatus.now", comment: "Now status")
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return String(format: NSLocalizedString("onlineStatus.minutesAgo", comment: "Minutes ago format"), minutes)
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return String(format: NSLocalizedString("onlineStatus.hoursAgo", comment: "Hours ago format"), hours)
        } else {
            let days = Int(timeInterval / 86400)
            return String(format: NSLocalizedString("onlineStatus.daysAgo", comment: "Days ago format"), days)
        }
    }
    
    // ✅ NUEVO: Manejar cuando la app entra en background
    private func handleAppDidEnterBackground() {
        
        // ✅ LÓGICA INTELIGENTE: Solo guardar estado anterior si es online o away
        if currentUserStatus == .online || currentUserStatus == .away {
            previousOnlineStatus = currentUserStatus
            
            // Programar cambios automáticos según el estado actual
            if currentUserStatus == .online {
                // En línea: 10 min → away, 30 min → offline (PRODUCCIÓN)
                awayTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                    self?.setStatus(.away)
                    
                    // ✅ NUEVO: Programar el siguiente cambio DESPUÉS de cambiar a away
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1200) {
                        self?.setStatus(.offline)
                    }
                }
                
            } else if currentUserStatus == .away {
                // Ausente: 20 min → offline (PRODUCCIÓN)
                offlineTimer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: false) { [weak self] _ in
                    self?.setStatus(.offline)
                }
                
            } else if currentUserStatus == .busy {
                // Ocupado: 10 min → offline (directo) - PRODUCCIÓN
                offlineTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                    self?.setStatus(.offline)
                }
            }
            
        } else {
            // Si el estado es desconectado o invisible, no hacer nada
        }
    }
    
    // ✅ NUEVO: Manejar cuando la app vuelve al foreground
    private func handleAppWillEnterForeground() {
        
        // Cancelar timers automáticos
        awayTimer?.invalidate()
        offlineTimer?.invalidate()
        awayTimer = nil
        offlineTimer = nil
        
        // ✅ LÓGICA DE RESTAURACIÓN INTELIGENTE
        if let previousStatus = previousOnlineStatus {
            // Solo restaurar si el estado anterior era online o away
            if previousStatus == .online || previousStatus == .away {
                setStatus(previousStatus)
            } else {
            }
            previousOnlineStatus = nil // Limpiar después de restaurar
        } else {
        }
    }
    
    // ✅ NUEVO: Método para verificar si hay cambios automáticos pendientes
    func hasPendingAutoChanges() -> Bool {
        return awayTimer != nil || offlineTimer != nil
    }
    
    // ✅ NUEVO: Método para obtener información del próximo cambio automático
    func getNextAutoChangeInfo() -> (nextStatus: OnlineStatus, timeRemaining: String)? {
        if awayTimer != nil {
            return (.away, NSLocalizedString("onlineStatus.autoChange.away", comment: "Auto change to away time"))
        } else if offlineTimer != nil {
            return (.offline, NSLocalizedString("onlineStatus.autoChange.offline", comment: "Auto change to offline time"))
        }
        return nil
    }
} 
