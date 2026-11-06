#if DEBUG
import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import FirebaseFunctions

/// Aísla Firebase en modo captura: todo apunta a un host local sin servicio
/// (puerto 1) y Firestore trabaja solo en memoria y sin red.
/// Llamar justo después de `FirebaseApp.configure()` y antes de cualquier uso.
enum ScreenshotSandbox {
    static let deadHost = "127.0.0.1"
    static let deadPort = 1

    static func configure() {
        // Firestore: caché en memoria, host inalcanzable y red apagada.
        let settings = FirestoreSettings()
        settings.host = "\(deadHost):\(deadPort)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        let db = Firestore.firestore()
        db.settings = settings
        db.disableNetwork { _ in }

        // Auth: emulador inexistente y sin usuario restaurado del llavero.
        let auth = Auth.auth()
        auth.useEmulator(withHost: deadHost, port: deadPort)
        try? auth.signOut()

        // Storage y Functions (región por defecto y la que usa la app).
        Storage.storage().useEmulator(withHost: deadHost, port: deadPort)
        Functions.functions().useEmulator(withHost: deadHost, port: deadPort)
        Functions.functions(region: "europe-southwest1").useEmulator(withHost: deadHost, port: deadPort)
    }
}
#endif
