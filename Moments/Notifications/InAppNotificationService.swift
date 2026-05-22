import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

@MainActor
class InAppNotificationService: ObservableObject {
    static let shared = InAppNotificationService()
    
    @Published var currentNotification: Notification?
    @Published var showBanner: Bool = false
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let displayDuration: TimeInterval = 4.0
    private var dismissTimer: AnyCancellable?
    
    // ✅ Listener separado para mensajes
    private var messageListener: ListenerRegistration?
    
    private init() {}
    
    func startListing() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Evitar duplicar listeners
        listener?.remove()
        messageListener?.remove()
        
        // Escuchar solo cambios NUEVOS (usando timestamp)
        // Nota: Firestore no soporta "solo nuevos" nativamente sin un campo de fecha.
        // Usamos el momento actual como punto de corte.
        let startTime = Timestamp(date: Date())
        
        listener = db.collection("users").document(userId).collection("notifications")
            .whereField("timestamp", isGreaterThan: startTime)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, snapshot != nil else { return }
                
                snapshot?.documentChanges.forEach { change in
                    if change.type == .added {
                        if let notification = try? change.document.data(as: Notification.self) {
                            self.handleNewNotification(notification)
                        }
                    }
                }
            }
            
        // ✅ START: Escuchar mensajes nuevos (MD/DM)
        // Escuchamos conversaciones donde participamos, ordenadas por actualización
        let messagesQuery = db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            //.order(by: "lastUpdated", descending: true) // Opcional, pero útil
        
        let messagesListener = messagesQuery.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, snapshot != nil else { return }
            
            snapshot?.documentChanges.forEach { change in
                // Interesante: .modified (cuando llega un mensaje nuevo la conversación se modifica)
                if change.type == .modified {
                    let data = change.document.data()
                    
                    // 1. Verificar timestamp reciente
                    // Usamos "timestamp" que es lo que ChatService actualiza
                    if let lastUpdated = (data["timestamp"] as? Timestamp)?.dateValue(),
                       lastUpdated > startTime.dateValue() {
                        
                        // 2. Verificar estado de lectura (La fuente de la verdad)
                        // Si readStatus[userId] es false, es un mensaje NUEVO para mí
                        if let readStatus = data["readStatus"] as? [String: Bool],
                           readStatus[userId] == false {
                            let mutedByUserIds = data["mutedByUserIds"] as? [String] ?? []
                            let isMutedForUser =
                                mutedByUserIds.contains(userId) ||
                                ((data["isMuted"] as? Bool) == true && (data["mutedBy"] as? String) == userId)
                            guard !isMutedForUser else { return }
                            
                            // 3. Identificar al remitente (el otro participante)
                            guard let participants = data["participants"] as? [String] else { return }
                            let otherParticipantId = participants.first { $0 != userId } ?? ""
                            
                            guard !otherParticipantId.isEmpty else { return }
                            
                            // 4. Obtener nombre del remitente (desde participantData cached)
                            var senderName = "User"
                            if let participantData = data["participantData"] as? [String: [String: Any]],
                               let otherData = participantData[otherParticipantId] {
                                senderName = otherData["username"] as? String ?? "User"
                            } else {
                                // Fallback
                                senderName = data["otherParticipantUsername"] as? String ?? "User"
                            }
                            
                            // 5. Crear notificación
                            let conversationId = change.document.documentID
                            let sanitizedPreview = sanitizedConversationPreview(
                                data["lastMessage"] as? String,
                                encryptionVersion: data["encryptionVersion"] as? String
                            )
                            let lastMessagePreview = sanitizedPreview.isEmpty ? MessageType.text.conversationPreview : sanitizedPreview
                            
                            let notification = Notification(
                                id: UUID().uuidString,
                                type: .message,
                                senderId: otherParticipantId,
                                senderUsername: senderName,
                                timestamp: lastUpdated,
                                isPending: true,
                                reaction: lastMessagePreview, // Guardamos preview del mensaje
                                conversationId: conversationId
                            )
                            
                            // 6. Mostrar banner
                            self.handleNewNotification(notification)
                        }
                    }
                }
            }
        }
        // Guardar listener (necesitamos array o similar si queremos manejar múltiples)
        // Por simplicidad en V1 agregamos al `listener` properties si fuera array, pero aquí
        // InAppNotificationService tiene `listener` singular. Necesitamos cambiarlo.
        self.messageListener = messagesListener
        // END
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        
        messageListener?.remove()
        messageListener = nil
    }
    
    func handleNewNotification(_ notification: Notification) {
        // Ignorar notificaciones propias (aunque el backend ya debería filtrarlas)
        guard notification.senderId != Auth.auth().currentUser?.uid else { return }
        
        // UI Updates en Main Thread
        DispatchQueue.main.async {
            // Si ya hay una, la reemplazamos (o podríamos hacer cola, pero V1 reemplaza)
            self.currentNotification = notification
            self.showBanner = true
            
            // Haptic Feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Auto-dismiss
            self.startDismissTimer()
        }
    }
    
    private func startDismissTimer() {
        dismissTimer?.cancel()
        dismissTimer = Just(())
            .delay(for: .seconds(displayDuration), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.showBanner = false
                }
                // Limpiar referencia después de la animación
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.currentNotification = nil
                }
            }
    }
    
    func dismissManually() {
        withAnimation {
            showBanner = false
        }
        dismissTimer?.cancel()
    }
}
