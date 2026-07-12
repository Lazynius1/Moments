import FirebaseAppCheck
import FirebaseCore

/// App Attest acredita instalaciones reales de Moments ante Firebase.
/// El simulador usa el proveedor de depuracion, cuyo token se registra de forma
/// explicita en Firebase Console y nunca se distribuye como secreto en el codigo.
final class MomentsAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}
