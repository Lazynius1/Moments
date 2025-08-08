import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class OnlineStatusService: ObservableObject {
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var onlineStatusTimer: Timer?
    private var lastActivityTimer: Timer?
    
    @Published var currentUserStatus: OnlineStatus = .offline
    @Published var isOnline: Bool = false
    @Published var lastSeen: Date = Date()
    
    init() {
        setupOnlineStatusTracking()
    }
    
    deinit {
        onlineStatusTimer?.invalidate()
        lastActivityTimer?.invalidate()
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
        
        // Actualizar estado cuando la app entra en background/foreground
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.setStatus(.away)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.setStatus(.online)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func setStatus(_ status: OnlineStatus) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        currentUserStatus = status
        isOnline = status == .online
        
        let data: [String: Any] = [
            "onlineStatus": status.rawValue,
            "isOnline": isOnline,
            "lastSeen": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId).updateData(data) { error in
            if let error = error {
                print("Error actualizando estado en línea: \(error.localizedDescription)")
            } else {
                print("Estado en línea actualizado: \(status.displayName)")
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
        
        db.collection("users").document(userId).updateData(data)
    }
    
    private func updateLastSeen() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let data: [String: Any] = [
            "lastSeen": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId).updateData(data)
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
} 