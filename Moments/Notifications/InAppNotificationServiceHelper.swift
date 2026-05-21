import Foundation
import FirebaseFirestore
import FirebaseAuth

extension InAppNotificationService {
    
    // ✅ Helper para procesar notificación de mensaje con nombre correcto
    func handleNewMessageNotification(_ partialNotification: Notification, conversationData: [String: Any], currentUserId: String) {
        // En una conversación 1v1, otherParticipantUsername es el nombre del OTRO usuario.
        // Si el senderId coincide con otherParticipantId, usamos ese nombre.
        
        // Obtenemos los participantes y buscamos el nombre del sender
        var senderName = partialNotification.senderUsername
        
        // Logica simplificada: si otherParticipantId == senderId, usamos otherParticipantUsername
        if let otherId = conversationData["otherParticipantId"] as? String,
           otherId == partialNotification.senderId,
           let otherName = conversationData["otherParticipantUsername"] as? String {
            senderName = otherName
        }
        
        // Creamos la notificación final con el nombre correcto
        let finalNotification = Notification(
            id: partialNotification.id,
            type: .message,
            senderId: partialNotification.senderId,
            senderUsername: senderName,
            timestamp: partialNotification.timestamp,
            isPending: true,
            reaction: partialNotification.reaction,  // message preview
            conversationId: partialNotification.conversationId ?? partialNotification.momentId
        )
        
        // Pasamos al handler estándar
        self.handleNewNotification(finalNotification)
    }
}
