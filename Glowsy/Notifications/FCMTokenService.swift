import Foundation
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

class FCMTokenService {
    static let shared = FCMTokenService()
    private init() {}
    
    // ✅ NUEVO: Contador de reintentos por userId para evitar loops infinitos
    private var retryCount: [String: Int] = [:]
    
    // ✅ MEJORADO: Método centralizado con límite de reintentos
    func updateFCMToken() {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }
        
        // ✅ NUEVO: Límite de 3 reintentos por usuario
        let currentRetries = retryCount[userId] ?? 0
        if currentRetries >= 3 {
            return
        }
        
        // ✅ NUEVO: Incrementar contador de reintentos
        retryCount[userId] = currentRetries + 1
        
        // ✅ VERIFICAR que APNs token esté configurado
        if Messaging.messaging().apnsToken == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.updateFCMToken()
            }
            return
        }
        Messaging.messaging().token { [weak self] token, error in
            if let error = error {
                // Reintentar después de 5 segundos si falla
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self?.updateFCMToken()
                }
            } else if let token = token {
                self?.saveFCMToken(token: token, userId: userId)
                
                // ✅ NUEVO: Resetear contador de reintentos en éxito
                self?.retryCount[userId] = 0
            }
        }
    }
    
    // ✅ MÉTODO PRIVADO para guardar en Firestore
    private func saveFCMToken(token: String, userId: String) {
        let userData: [String: Any] = [
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
            "deviceInfo": [
                "model": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            ]
        ]
        
        Firestore.firestore().collection("users").document(userId).updateData(userData) { error in
            if let error = error {
                // ✅ RETRY: Intentar de nuevo en 30 segundos
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    FCMTokenService.shared.updateFCMToken()
                }
            }
        }
    }
    
    // ✅ MEJORADO: Método para limpiar token al hacer logout con notificación al backend
    func clearFCMToken() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Firestore.firestore().collection("users").document(userId).updateData([
            "fcmToken": FieldValue.delete(),
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
            } else {
                // ✅ NUEVO: Notificar al backend para evitar enviar notificaciones
                self.notifyBackendTokenCleared(userId: userId)
            }
        }
    }
    
    // ✅ NUEVO: Notificar al backend cuando el token es eliminado
    private func notifyBackendTokenCleared(userId: String) {
        // Simular llamada al backend (por ejemplo, vía HTTPS function)
        // Aquí podrías invocar una Cloud Function para limpiar el token en otros sistemas
        
        // Ejemplo de implementación futura:
        // Functions.functions().httpsCallable("clearUserToken").call(["userId": userId])
    }
}
