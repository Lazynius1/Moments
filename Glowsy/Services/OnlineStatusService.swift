import Foundation
import FirebaseFirestore
import FirebaseAuth
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
    
    // ✅ NUEVO: Variable para guardar el estado anterior (solo si era online o away)
    private var previousOnlineStatus: OnlineStatus?
    
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
            print("❌ Error: Usuario no autenticado")
            return 
        }
        
        print("🎯 Intentando cambiar estado a: \(status.displayName)")
        
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
        
        print("📝 Datos a enviar: \(data)")
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
                print("❌ Error actualizando estado en línea: \(error.localizedDescription)")
                // ✅ NUEVO: Revertir estado local si hay error
                DispatchQueue.main.async {
                    self.currentUserStatus = .offline
                    self.isOnline = false
                }
            } else {
                print("✅ Estado en línea actualizado exitosamente: \(status.displayName)")
                print("✅ Usuario ID: \(userId)")
                print("✅ Estado guardado: \(status.rawValue)")
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
                print("Error actualizando estado de conversación: \(error.localizedDescription)")
            } else {
                print("Estado de conversación actualizado: \(status.displayName)")
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
                    print("Error observando estado del usuario: \(error?.localizedDescription ?? "Unknown error")")
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
                print("❌ Error actualizando estado online: \(error.localizedDescription)")
            } else {
                print("✅ Estado online actualizado correctamente")
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
                print("❌ Error actualizando lastSeen: \(error.localizedDescription)")
            } else {
                print("✅ LastSeen actualizado correctamente")
            }
        }
    }
    
    // ✅ NUEVO: Sincronizar estado local con Firestore
    private func syncStatusWithFirestore() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("🔄 Sincronizando estado local con Firestore...")
        
        db.collection("users").document(userId).getDocument { [weak self] document, error in
            if let error = error {
                print("❌ Error obteniendo estado de Firestore: \(error.localizedDescription)")
                return
            }
            
            guard let document = document, document.exists,
                  let data = document.data(),
                  let statusString = data["onlineStatus"] as? String,
                  let status = OnlineStatus(rawValue: statusString) else {
                print("⚠️ No se encontró estado en Firestore, usando estado por defecto")
                return
            }
            
            DispatchQueue.main.async {
                self?.currentUserStatus = status
                self?.isOnline = status == .online
                print("✅ Estado sincronizado desde Firestore: \(status.displayName)")
                print("✅ Estado local actualizado: \(self?.currentUserStatus.displayName ?? "nil")")
            }
        }
    }
    
    // MARK: - Utility Methods
    func formatLastSeen(_ date: Date?) -> String {
        guard let date = date else { return "Desconocido" }
        
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "Ahora"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "Hace \(minutes) min"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "Hace \(hours)h"
        } else {
            let days = Int(timeInterval / 86400)
            return "Hace \(days)d"
        }
    }
    
    // ✅ NUEVO: Manejar cuando la app entra en background
    private func handleAppDidEnterBackground() {
        print("📱 App en background - Estado actual: \(currentUserStatus.displayName)")
        
        // ✅ LÓGICA INTELIGENTE: Solo guardar estado anterior si es online o away
        if currentUserStatus == .online || currentUserStatus == .away {
            previousOnlineStatus = currentUserStatus
            print("📱 Guardando estado anterior para restauración: \(currentUserStatus.displayName)")
            
            // Programar cambios automáticos según el estado actual
            if currentUserStatus == .online {
                // En línea: 10 min → away, 30 min → offline (PRODUCCIÓN)
                awayTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                    print("📱 Timer away ejecutado - cambiando a Ausente")
                    self?.setStatus(.away)
                    
                    // ✅ NUEVO: Programar el siguiente cambio DESPUÉS de cambiar a away
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1200) {
                        print("📱 Timer offline ejecutado - cambiando a Desconectado")
                        self?.setStatus(.offline)
                    }
                }
                print("📱 Programado: online → away (10 min) → offline (30 min) - PRODUCCIÓN")
                
            } else if currentUserStatus == .away {
                // Ausente: 20 min → offline (PRODUCCIÓN)
                offlineTimer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: false) { [weak self] _ in
                    print("📱 Timer offline ejecutado - cambiando a Desconectado")
                    self?.setStatus(.offline)
                }
                print("📱 Programado: away → offline (20 min) - PRODUCCIÓN")
                
            } else if currentUserStatus == .busy {
                // Ocupado: 10 min → offline (directo) - PRODUCCIÓN
                offlineTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                    print("📱 Timer offline ejecutado - cambiando a Desconectado")
                    self?.setStatus(.offline)
                }
                print("📱 Programado: busy → offline (10 min, directo) - PRODUCCIÓN")
            }
            
        } else {
            // Si el estado es desconectado o invisible, no hacer nada
            print("📱 Estado \(currentUserStatus.displayName) - No se programa cambio automático")
        }
    }
    
    // ✅ NUEVO: Manejar cuando la app vuelve al foreground
    private func handleAppWillEnterForeground() {
        print("📱 App en foreground")
        
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
                print("📱 Restaurando estado anterior: \(previousStatus.displayName)")
            } else {
                print("📱 No se restaura estado anterior: \(previousStatus.displayName)")
            }
            previousOnlineStatus = nil // Limpiar después de restaurar
        } else {
            print("📱 No hay estado anterior para restaurar")
        }
    }
    
    // ✅ NUEVO: Método para verificar si hay cambios automáticos pendientes
    func hasPendingAutoChanges() -> Bool {
        return awayTimer != nil || offlineTimer != nil
    }
    
    // ✅ NUEVO: Método para obtener información del próximo cambio automático
    func getNextAutoChangeInfo() -> (nextStatus: OnlineStatus, timeRemaining: String)? {
        if awayTimer != nil {
            return (.away, "10 min")
        } else if offlineTimer != nil {
            return (.offline, "30 min")
        }
        return nil
    }
} 
