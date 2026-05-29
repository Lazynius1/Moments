import WidgetKit
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import FirebaseStorage
import Combine
import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

@MainActor
class AuthService: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: AppUser?
    @Published var currentFirebaseUser: User?
    @Published var isAccountDeactivated: Bool = false
    @Published var deactivatedUserData: AppUser? = nil
    @Published var isVerifyingAccount: Bool = false
    @Published var authState: AuthState = .loading

    // ✅ NUEVO: Flag público para controlar el flujo de registro (observado por las vistas)
    @Published var isRegistering: Bool = false

    // ✅ NUEVO: Para Sign in with Apple
    @Published var currentNonce: String?

    // ✅ NUEVO: Verificar si Apple está vinculado
    var isAppleLinked: Bool {
        return currentFirebaseUser?.providerData.contains { $0.providerID == "apple.com" } ?? false
    }

    // ✅ NUEVO: Queue serial para thread safety
    private let authQueue = DispatchQueue(label: "com.moments.auth", qos: .userInteractive)

    // ✅ Estado serializado por authQueue (legible desde callbacks de Firebase)
    private nonisolated(unsafe) var _registrationState: RegistrationState = .idle
    private nonisolated(unsafe) var _isAuthProcessingEnabled: Bool = true

    enum RegistrationState: Sendable {
        case idle
        case registering
        case completing
    }

    private enum CachedAccountDecision: String, Codable {
        case allowed
        case deactivated
        case suspended
    }

    private struct CachedAccountStatus: Codable {
        let userId: String
        let decision: CachedAccountDecision
        let reason: String?
        let expiresAt: Date?
        let verifiedAt: Date

        var isExpiredSuspension: Bool {
            guard decision == .suspended, let expiresAt else { return false }
            return Date() > expiresAt
        }
    }

    var isInRegistrationProcess: Bool {
        return authQueue.sync {
            return _registrationState != .idle
        }
    }

    private func cachedAccountStatusKey(userId: String) -> String {
        "accountStatus_\(userId)"
    }

    private func loadCachedAccountStatus(userId: String) -> CachedAccountStatus? {
        guard let data = UserDefaults.standard.data(forKey: cachedAccountStatusKey(userId: userId)) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedAccountStatus.self, from: data)
    }

    private func saveCachedAccountStatus(
        userId: String,
        decision: CachedAccountDecision,
        reason: String? = nil,
        expiresAt: Date? = nil
    ) {
        let status = CachedAccountStatus(
            userId: userId,
            decision: decision,
            reason: reason,
            expiresAt: expiresAt,
            verifiedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: cachedAccountStatusKey(userId: userId))
    }

    // ✅ NUEVO: Transition Lock para evitar que el listener interfiera durante handovers críticos
    private nonisolated(unsafe) var _transitionLock: Bool = false

    var isTransitionLocked: Bool {
        return authQueue.sync {
            return _transitionLock
        }
    }

    // ✅ NOEL: No declarar handle aquí para evitar aislamiento en deinit
    // private var authStateHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    private let storage = FirebaseStorage.Storage.storage().reference()
    private let firestoreService = FirestoreService()

    // ✅ NUEVO: Clase para manejar los listeners de forma no aislada (necesario para deinit)
    private final class CleanupHolder {
        var suspensionRegistration: ListenerRegistration?
        var authHandle: AuthStateDidChangeListenerHandle?

        func removeAll() {
            suspensionRegistration?.remove()
            suspensionRegistration = nil
            if let handle = authHandle {
                Auth.auth().removeStateDidChangeListener(handle)
                authHandle = nil
            }
        }
    }

    // ✅ NUEVO: Holder de limpieza (nonisolated let para permitir acceso en deinit)
    nonisolated private let cleanupHolder = CleanupHolder()

    // ✅ Estados de autenticación detallados
    enum AuthState: Equatable {
        case loading
        case verifyingAccount
        case authenticated
        case deactivated
        case suspended(reason: String?, expiresAt: Date?)
        case unauthenticated

        static func == (lhs: AuthState, rhs: AuthState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading),
                 (.verifyingAccount, .verifyingAccount),
                 (.authenticated, .authenticated),
                 (.deactivated, .deactivated),
                 (.unauthenticated, .unauthenticated):
                return true
            case (.suspended(let lhsReason, let lhsExpires), .suspended(let rhsReason, let rhsExpires)):
                return lhsReason == rhsReason && lhsExpires == rhsExpires
            default:
                return false
            }
        }
    }

    init() {
        cleanupHolder.authHandle = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let self = self else { return }


            // ✅ THREAD-SAFE: Verificar estado de registro y LOCK
            let registrationState = self.authQueue.sync { self._registrationState }
            let isAuthProcessingEnabled = self.authQueue.sync { self._isAuthProcessingEnabled }
            let isTransitionLocked = self.authQueue.sync { self._transitionLock }

            // ✅ CRÍTICO: Si hay un LOCK de transición, IGNORAR CUALQUIER CAMBIO
            if isTransitionLocked {
                // Solo actualizamos el usuario interno silenciosamente si es necesario
                if let user = user {
                    DispatchQueue.main.async {
                         // Evitar disparar cambios de UI
                        self.currentFirebaseUser = user
                    }
                }
                return
            }


            // ✅ CRÍTICO: Si está en proceso de registro O procesamiento deshabilitado, pausar
            if registrationState == .registering || !isAuthProcessingEnabled {
                DispatchQueue.main.async {
                    self.currentFirebaseUser = user
                }
                return
            }

            // ✅ NUEVO: Si está completando registro, usar proceso especial
            if registrationState == .completing {
                self.handleRegistrationCompletion(user: user)
                return
            }

            // ✅ CRÍTICO: NUEVA VERIFICACIÓN - Si hay usuario pero es muy reciente (< 5 segundos)
            // probablemente es un registro recién completado
            if let user = user {
                let userCreationTime = user.metadata.creationDate?.timeIntervalSinceNow ?? -999
                let isVeryRecentUser = userCreationTime > -5.0 // Creado hace menos de 5 segundos

                if isVeryRecentUser {

                    DispatchQueue.main.async {
                        self.authState = .verifyingAccount
                        self.isVerifyingAccount = true
                        self.currentFirebaseUser = user
                    }

                    // Usar retry con delay más generoso para usuarios recién creados
                    self.retryUserFetchForNewUser(userId: user.uid) { isActive, userData, isSuspended in
                        DispatchQueue.main.async {
                            self.isVerifyingAccount = false

                            if isSuspended {
                                return
                            }

                            if isActive, let userData = userData {
                                self.saveCachedAccountStatus(userId: user.uid, decision: .allowed)
                                self.isLoggedIn = true
                                self.currentUser = userData
                                self.currentFirebaseUser = user
                                self.isAccountDeactivated = false
                                self.deactivatedUserData = nil
                                self.authState = .authenticated
                                self.startSuspensionListener()

                                // ✅ SwiftData: Guardar usuario actual para acceso offline
                                LocalPersistenceService.shared.saveCurrentUser(userData)

                            } else {
                                self.forceLogout()
                            }
                        }
                    }
                    return
                }
            }

            // ✅ NUEVO: Si detectamos un usuario durante registro pero los flags no están listos, IGNORAR
            if let user = user, self.isRegistering {
                DispatchQueue.main.async {
                    self.currentFirebaseUser = user
                }
                return
            }

            // Si es la primera vez que se dispara el listener y no hay usuario, establecer el estado inicial.
            if self.authState == .loading && user == nil {
                DispatchQueue.main.async {
                    self.authState = .unauthenticated
                }
                return
            }

            // Para todas las demás activaciones (después del chequeo inicial o un login/registro real)
            if let user = user {
                // ✅ CRÍTICO: Si ya estamos logueados con el MISMO usuario, NO resetear el estado.
                // Esto evita el parpadeo o logout involuntario cuando Firebase actualiza el token o el perfil.
                if self.isLoggedIn && self.currentFirebaseUser?.uid == user.uid {
                    DispatchQueue.main.async {
                        self.currentFirebaseUser = user
                    }
                    return
                }

                // ✅ Caché local: útil para offline, pero no debe saltarse controles de estado.
                if let cachedUser = LocalPersistenceService.shared.loadUser(userId: user.uid) {
                    let cachedAccountStatus = self.loadCachedAccountStatus(userId: user.uid)

                    if cachedAccountStatus?.decision == .suspended && cachedAccountStatus?.isExpiredSuspension == false {
                        DispatchQueue.main.async {
                            self.isLoggedIn = false
                            self.currentUser = nil
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = false
                            self.deactivatedUserData = nil
                            self.authState = .suspended(reason: cachedAccountStatus?.reason, expiresAt: cachedAccountStatus?.expiresAt)
                            self.isVerifyingAccount = false
                        }
                        return
                    }

                    if !cachedUser.isActive || cachedAccountStatus?.decision == .deactivated {
                        DispatchQueue.main.async {
                            self.isLoggedIn = false
                            self.currentUser = nil
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = true
                            self.deactivatedUserData = cachedUser
                            self.authState = .deactivated
                            self.isVerifyingAccount = false
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        print("📶 AuthService: Sesión local válida, verificando cuenta en segundo plano")
                        self.isLoggedIn = true
                        self.currentUser = cachedUser
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = false
                        self.deactivatedUserData = nil
                        self.authState = .authenticated
                        self.isVerifyingAccount = false
                    }

                    if !NetworkMonitor.shared.isConnected {
                        return
                    }

                    // Verificación silenciosa: si el servidor confirma bloqueo, se corrige el estado al instante.
                    self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                        if isSuspended {
                            DispatchQueue.main.async {
                                self.isLoggedIn = false
                                self.currentUser = nil
                                self.currentFirebaseUser = user
                                self.isVerifyingAccount = false
                            }
                             return
                        }
                        if isActive {
                            let resolvedUser = userData ?? cachedUser
                            DispatchQueue.main.async {
                                self.saveCachedAccountStatus(userId: user.uid, decision: .allowed)
                                self.isLoggedIn = true
                                self.currentUser = resolvedUser
                                self.currentFirebaseUser = user
                                self.isAccountDeactivated = false
                                self.deactivatedUserData = nil
                                self.authState = .authenticated
                                self.isVerifyingAccount = false
                                self.startSuspensionListener()
                                self.syncProfileDataToWidget(userData: resolvedUser)
                            }
                        } else if let userData = userData {
                            DispatchQueue.main.async {
                                self.saveCachedAccountStatus(userId: user.uid, decision: .deactivated)
                                self.isLoggedIn = false
                                self.currentUser = nil
                                self.currentFirebaseUser = user
                                self.isAccountDeactivated = true
                                self.deactivatedUserData = userData
                                self.authState = .deactivated
                                self.isVerifyingAccount = false
                            }
                        } else {
                            DispatchQueue.main.async {
                                print("📶 AuthService: No se pudo confirmar cuenta; se mantiene sesión local")
                                self.isLoggedIn = true
                                self.currentUser = cachedUser
                                self.currentFirebaseUser = user
                                self.authState = .authenticated
                                self.isVerifyingAccount = false
                            }
                        }
                    }
                    return
                }

                // Si NO hay caché o estamos forzando verificación (Online)
                DispatchQueue.main.async {
                    self.authState = .verifyingAccount
                    self.isVerifyingAccount = true
                    // ✅ IMPORTANTE: Resetear estados previos
                    self.isLoggedIn = false
                    self.isAccountDeactivated = false
                    self.deactivatedUserData = nil
                    self.currentFirebaseUser = user
                    self.currentUser = nil
                }

                // Verificar estado de cuenta y cargar AppUser completo
                self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in

                    DispatchQueue.main.async {
                        self.isVerifyingAccount = false

                        // ✅ CORREGIDO: Verificar suspensión PRIMERO
                        if isSuspended {
                            return
                        }

                        if isActive {
                            if let userData {
                                self.saveCachedAccountStatus(userId: user.uid, decision: .allowed)
                                LocalPersistenceService.shared.saveCurrentUser(userData)
                            }
                            self.isLoggedIn = true
                            self.currentUser = userData
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = false
                            self.deactivatedUserData = nil
                            self.authState = .authenticated

                            // ✅ NUEVO: Iniciar listener de suspensión
                            self.startSuspensionListener()

                            // ✅ Sincronizar datos de perfil para el widget
                            self.syncProfileDataToWidget(userData: userData)

                        } else {
                            self.saveCachedAccountStatus(userId: user.uid, decision: .deactivated)
                            self.isLoggedIn = false
                            self.currentUser = nil
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = true
                            self.deactivatedUserData = userData
                            self.authState = .deactivated
                        }

                    }
                }
            } else {
                DispatchQueue.main.async {
                    // ✅ CORREGIDO: No limpiar si está suspended
                    if case .suspended = self.authState {
                        return
                    }

                    // ✅ NUEVO: Detener listener al limpiar estado
                    self.stopSuspensionListener()

                    self.isLoggedIn = false
                    self.currentUser = nil
                    self.currentFirebaseUser = nil
                    self.isAccountDeactivated = false
                    self.deactivatedUserData = nil
                    self.isVerifyingAccount = false
                    self.isRegistering = false
                    self.authState = .unauthenticated

                    // ✅ Thread-safe cleanup
                    self.authQueue.async {
                        self._registrationState = .idle
                        self._isAuthProcessingEnabled = true
                    }
                }
            }
        }
    }

    // ✅ NUEVA FUNCIÓN: Retry especial para usuarios recién creados
    private func retryUserFetchForNewUser(userId: String, completion: @escaping (Bool, AppUser?, Bool) -> Void) {

        // Para usuarios recién creados, dar más tiempo (hasta 10 segundos)
        retryUserFetchWithCustomParams(userId: userId, maxRetries: 8, baseDelay: 0.5, maxDelay: 1.5, completion: completion)
    }

    // ✅ FUNCIÓN MEJORADA: Retry con parámetros personalizables
    private func retryUserFetchWithCustomParams(userId: String, maxRetries: Int, baseDelay: TimeInterval, maxDelay: TimeInterval, retryCount: Int = 0, completion: @escaping (Bool, AppUser?, Bool) -> Void) {

        let delay = min(Double(retryCount) * baseDelay, maxDelay)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {

            // Verificar suspensión primero
            self.checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
                if isSuspended {
                    DispatchQueue.main.async {
                        self?.authState = .suspended(reason: reason, expiresAt: expiresAt)
                    }
                    completion(false, nil, true)
                    return
                }

                // Intentar obtener usuario de Firestore
                self?.firestoreService.fetchUser(userId: userId) { result in
                    switch result {
                    case .success(let appUser):
                        completion(true, appUser, false)

                    case .failure:

                        if retryCount < maxRetries - 1 {
                            // Continuar reintentando
                            self?.retryUserFetchWithCustomParams(userId: userId, maxRetries: maxRetries, baseDelay: baseDelay, maxDelay: maxDelay, retryCount: retryCount + 1, completion: completion)
                        } else {
                            // Se acabaron los reintentos para usuario recién creado
                            self?.forceLogout()
                            completion(false, nil, false)
                        }
                    }
                }
            }
        }
    }

    deinit {
        stopSuspensionListener()
    }

    // ✅ NUEVA FUNCIÓN: Manejar finalización de registro
    private func handleRegistrationCompletion(user: User?) {
        guard let user = user else {
            return
        }

        DispatchQueue.main.async {
            self.authState = .verifyingAccount
            self.isVerifyingAccount = true
            self.currentFirebaseUser = user
        }

        // ✅ Dar tiempo para que Firestore esté completamente listo
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {

            // NO limpiar el estado aquí. Mantener .completing para bloquear el listener default.

            self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                DispatchQueue.main.async {
                    self.isVerifyingAccount = false

                    if isSuspended {
                        return
                    }

                    if isActive, let userData = userData {
                        // ✅ ÉXITO: Primero establecemos estado autenticado
                        self.isLoggedIn = true
                        self.currentUser = userData
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = false
                        self.deactivatedUserData = nil
                        self.authState = .authenticated

                        self.startSuspensionListener()

                        // ✅ CRÍTICO: No limpiar isRegistering inmediatamente.
                        // Esperamos a que TabBarView desmonte LoginView completamente.
                        // Si lo ponemos a false ahora, el fullScreenCover se cierra antes de que TabBarView cambie.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.isRegistering = false
                            self.authQueue.async {
                                self._registrationState = .idle
                                self._isAuthProcessingEnabled = true
                            }
                        }

                        self.objectWillChange.send()

                        // ✅ NUEVO: Liberar el Transition Lock después de un tiempo seguro
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.authQueue.async {
                                self._transitionLock = false
                            }
                        }

                    } else {
                        // Si falla, reintentar una vez más
                        self.retryUserFetchForNewUser(userId: user.uid) { success, user, suspended in
                            DispatchQueue.main.async {
                                if success, let user = user {
                                    self.isLoggedIn = true
                                    self.currentUser = user
                                    self.currentFirebaseUser = Auth.auth().currentUser
                                    self.authState = .authenticated
                                    self.startSuspensionListener()

                                    // Limpiar flags en retry success CON DELAY
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        self.isRegistering = false
                                        self.authQueue.async {
                                            self._registrationState = .idle
                                            self._isAuthProcessingEnabled = true
                                        }
                                    }

                                    // ✅ NUEVO: Liberar Lock en retry
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        self.authQueue.async {
                                            self._transitionLock = false
                                        }
                                    }

                                } else {
                                    // Si falla definitivamente, entonces limpiamos para mostrar error
                                    self.authState = .deactivated
                                    self.isAccountDeactivated = true
                                    self.deactivatedUserData = userData

                                    self.isRegistering = false
                                    self.authQueue.async {
                                        self._registrationState = .idle
                                        self._isAuthProcessingEnabled = true
                                        // Liberar lock inmediatamente en fallo
                                        self._transitionLock = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // ✅ NUEVO: Listener de suspensión en tiempo real
        func startSuspensionListener() {
            guard let userId = currentUser?.id else {
                return
            }



            let registration = db.collection("users").document(userId)
                .addSnapshotListener { [weak self] snapshot, error in
                    if error != nil {
                        return
                    }

                    guard let data = snapshot?.data() else {
                        return
                    }

                    let isSuspended = data["isSuspended"] as? Bool ?? false

                    if isSuspended {

                        // Verificar si no expiró
                        if let suspendedUntil = data["suspendedUntil"] as? Timestamp {
                            if Date() > suspendedUntil.dateValue() {
                                return
                            }
                        }

                        DispatchQueue.main.async {
                            self?.logout()
                        }
                    }
                }

            cleanupHolder.suspensionRegistration = registration
        }

        nonisolated func stopSuspensionListener() {
            cleanupHolder.removeAll()
        }

        // ✅ Login mejorado con mejor manejo de estados
        func login(identifier: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {

            guard !identifier.isEmpty, !password.isEmpty else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.emptyFields", comment: "Empty fields")])))
                return
            }

            let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
            let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)

            if predicate.evaluate(with: identifier) {
                // Inicio de sesión con email
                Auth.auth().signIn(withEmail: identifier, password: password) { result, error in
                    if let error = error {
                        completion(.failure(self.mapAuthError(error)))
                    } else if let user = result?.user {
                        self.finishCredentialLogin(for: user, completion: completion)
                    } else {
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("login.error.unknown", comment: "Unknown login error")])))
                    }
                }
            } else {
                // Inicio de sesión con username
                if let cachedEmail = UserDefaults.standard.string(forKey: "cachedEmail_\(identifier.lowercased())") {
                    Auth.auth().signIn(withEmail: cachedEmail, password: password) { result, error in
                        if let error = error {
                            completion(.failure(self.mapAuthError(error)))
                        } else if let user = result?.user {
                            DispatchQueue.main.async {
                                self.finishCredentialLogin(for: user, completion: completion)
                            }
                        } else {
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("login.error.unknown", comment: "Unknown login error")])))
                        }
                    }
                } else {
                    // No hay caché, consultar Firestore
                    Firestore.firestore().collection("usernames").document(identifier.lowercased()).getDocument { document, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }

                        guard let data = document?.data() else {
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.usernameNotFound", comment: "Username not found")])))
                            return
                        }

                        // Flujo principal: usernames/{username}.email
                        if let email = data["email"] as? String, !email.isEmpty {
                            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                                if let error = error {
                                    completion(.failure(self.mapAuthError(error)))
                                } else if let user = result?.user {
                                    UserDefaults.standard.set(email, forKey: "cachedEmail_\(identifier.lowercased())")
                                    DispatchQueue.main.async {
                                        self.finishCredentialLogin(for: user, completion: completion)
                                    }
                                } else {
                                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("login.error.unknown", comment: "Unknown login error")])))
                                }
                            }
                            return
                        }

                        // Fallback resiliente: si falta email pero existe userId, buscar email en users/{userId}
                        guard let userId = data["userId"] as? String, !userId.isEmpty else {
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.usernameNotFound", comment: "Username not found")])))
                            return
                        }

                        Firestore.firestore().collection("users").document(userId).getDocument { userDoc, userError in
                            if let userError = userError {
                                completion(.failure(userError))
                                return
                            }

                            guard let userEmail = userDoc?.data()?["email"] as? String, !userEmail.isEmpty else {
                                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.usernameNotFound", comment: "Username not found")])))
                                return
                            }

                            // Auto-repair del índice usernames para próximos logins
                            Firestore.firestore().collection("usernames").document(identifier.lowercased()).setData([
                                "email": userEmail,
                                "updatedAt": FieldValue.serverTimestamp()
                            ], merge: true)

                            Auth.auth().signIn(withEmail: userEmail, password: password) { result, error in
                                if let error = error {
                                    completion(.failure(self.mapAuthError(error)))
                                } else if let user = result?.user {
                                    UserDefaults.standard.set(userEmail, forKey: "cachedEmail_\(identifier.lowercased())")
                                    DispatchQueue.main.async {
                                        self.finishCredentialLogin(for: user, completion: completion)
                                    }
                                } else {
                                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("login.error.unknown", comment: "Unknown login error")])))
                                }
                            }
                        }
                    }
                }
            }
        }

    private func finishCredentialLogin(for user: User, completion: @escaping (Result<Void, Error>) -> Void) {
        authQueue.async {
            self._transitionLock = true
            self._registrationState = .idle
            self._isAuthProcessingEnabled = true
        }

        DispatchQueue.main.async {
            self.currentFirebaseUser = user
            self.isLoggedIn = false
            self.currentUser = nil
            self.isAccountDeactivated = false
            self.deactivatedUserData = nil
            self.isVerifyingAccount = true
            self.isRegistering = false
            self.authState = .verifyingAccount
        }

        checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
            DispatchQueue.main.async {
                self.isVerifyingAccount = false

                if isSuspended {
                    self.authQueue.async { self._transitionLock = false }
                    completion(.success(()))
                    return
                }

                if isActive {
                    if let userData {
                        self.saveCachedAccountStatus(userId: user.uid, decision: .allowed)
                        LocalPersistenceService.shared.saveCurrentUser(userData)
                    }

                    self.isLoggedIn = true
                    self.currentUser = userData
                    self.currentFirebaseUser = user
                    self.isAccountDeactivated = false
                    self.deactivatedUserData = nil
                    self.authState = .authenticated
                    self.startSuspensionListener()
                    self.syncProfileDataToWidget(userData: userData)

                    self.authQueue.async { self._transitionLock = false }
                    completion(.success(()))
                    return
                }

                if let userData {
                    self.saveCachedAccountStatus(userId: user.uid, decision: .deactivated)
                    self.isLoggedIn = false
                    self.currentUser = nil
                    self.currentFirebaseUser = user
                    self.isAccountDeactivated = true
                    self.deactivatedUserData = userData
                    self.authState = .deactivated

                    self.authQueue.async { self._transitionLock = false }
                    completion(.success(()))
                    return
                }

                self.authQueue.async { self._transitionLock = false }
                self.forceLogout()
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("login.error.unknown", comment: "Unknown login error")])))
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Verificar estado y suspensión con retry para registro
    private func checkAccountStatus(userId: String, completion: @escaping (Bool, AppUser?, Bool) -> Void) {

        // ✅ THREAD-SAFE: Verificar estado de registro
        let registrationState = authQueue.sync { _registrationState }

        // ✅ CRÍTICO: Si estamos registrando, usar sistema de retry
        if registrationState == .registering || self.isRegistering {
            retryUserFetch(userId: userId, maxRetries: 5, completion: completion)
            return
        }

        // ✅ NUEVO: Si estamos offline, cargar perfil de SwiftData inmediatamente
        if !NetworkMonitor.shared.isConnected {
            print("📶 AuthService: Modo Offline detectado, cargando perfil local")
            let cachedUser = LocalPersistenceService.shared.loadUser(userId: userId)
            let cachedStatus = loadCachedAccountStatus(userId: userId)

            if cachedStatus?.decision == .suspended && cachedStatus?.isExpiredSuspension == false {
                completion(false, cachedUser, true)
            } else if cachedStatus?.decision == .deactivated || cachedUser?.isActive == false {
                completion(false, cachedUser, false)
            } else {
                completion(cachedUser != nil, cachedUser, false)
            }
            return
        }

        // ✅ SAFE COMPLETION WRAPPER: Evita que el timeout y la red disparen dos veces
        var hasCompleted = false
        let userIdToFetch = userId
        let safeCompletion: (Bool, AppUser?, Bool) -> Void = { isActive, userData, isSuspended in
            if !hasCompleted {
                hasCompleted = true
                completion(isActive, userData, isSuspended)
            }
        }

        // Bootstrap de sesión: si no podemos confirmar estado pero hay caché válida, mantenemos sesión local.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            if !hasCompleted {
                print("⚠️ AuthService: Timeout en bootstrap de sesión (\(userIdToFetch))")
                let cachedUser = LocalPersistenceService.shared.loadUser(userId: userIdToFetch)
                let cachedStatus = self?.loadCachedAccountStatus(userId: userIdToFetch)

                if cachedStatus?.decision == .suspended && cachedStatus?.isExpiredSuspension == false {
                    safeCompletion(false, cachedUser, true)
                    return
                }

                if cachedStatus?.decision == .deactivated || cachedUser?.isActive == false {
                    safeCompletion(false, cachedUser, false)
                    return
                }

                if let cachedUser {
                    DispatchQueue.main.async {
                        if self?.currentFirebaseUser?.uid == userIdToFetch {
                            self?.isLoggedIn = true
                            self?.currentUser = cachedUser
                            self?.isVerifyingAccount = false
                            self?.authState = .authenticated
                        }
                    }
                    safeCompletion(true, cachedUser, false)
                    return
                }

                DispatchQueue.main.async {
                    if self?.currentFirebaseUser?.uid == userIdToFetch {
                        self?.isLoggedIn = false
                        self?.currentUser = nil
                        self?.isVerifyingAccount = false
                        self?.authState = .unauthenticated
                    }
                }
                safeCompletion(false, nil, false)
            }
        }

        // PRIMERO verificar suspensión (solo para usuarios existentes)
        checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
            if hasCompleted { return }

            if isSuspended {
                self?.saveCachedAccountStatus(userId: userId, decision: .suspended, reason: reason, expiresAt: expiresAt)

                DispatchQueue.main.async {
                    self?.authState = .suspended(reason: reason, expiresAt: expiresAt)
                }

                safeCompletion(false, nil, true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    do { try Auth.auth().signOut() } catch {}
                }
                return
            }

            // Si no está suspendido, verificar estado normal
            self?.firestoreService.fetchUser(userId: userId) { result in
                DispatchQueue.main.async {
                    if hasCompleted { return }

                    switch result {
                    case .success(let appUser):
                        self?.saveCachedAccountStatus(userId: userId, decision: appUser.isActive ? .allowed : .deactivated)
                        safeCompletion(appUser.isActive, appUser, false)

                    case .failure(let error):
                        // ✅ Verificar nuevamente si estamos en registro (para evitar falsos negativos)
                        let currentRegistrationState = self?.authQueue.sync { self?._registrationState } ?? .idle

                        if currentRegistrationState == .registering || self?.isRegistering == true {
                            safeCompletion(false, nil, false)
                        } else {
                            // Si la red falla después de arrancar online, no asumimos cuenta válida.
                            let nsError = error as NSError
                            if nsError.domain == FirestoreErrorDomain && (nsError.code == FirestoreErrorCode.unavailable.rawValue || nsError.code == FirestoreErrorCode.deadlineExceeded.rawValue) {
                                print("⚠️ AuthService: No se pudo confirmar el estado de cuenta")
                                let cachedUser = LocalPersistenceService.shared.loadUser(userId: userId)
                                let cachedStatus = self?.loadCachedAccountStatus(userId: userId)

                                if cachedStatus?.decision == .suspended && cachedStatus?.isExpiredSuspension == false {
                                    safeCompletion(false, cachedUser, true)
                                } else if cachedStatus?.decision == .deactivated || cachedUser?.isActive == false {
                                    safeCompletion(false, cachedUser, false)
                                } else if let cachedUser {
                                    safeCompletion(true, cachedUser, false)
                                } else {
                                    safeCompletion(false, nil, false)
                                }
                            } else {
                                self?.forceLogout()
                                safeCompletion(false, nil, false)
                            }
                        }
                    }
                }
            }
        }
    }

        // ✅ NUEVA FUNCIÓN: Retry con backoff exponencial para usuarios en registro
        private func retryUserFetch(userId: String, maxRetries: Int, retryCount: Int = 0, completion: @escaping (Bool, AppUser?, Bool) -> Void) {

            let delay = Double(retryCount) * 0.5 // 0, 0.5, 1.0, 1.5, 2.0 segundos

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {

                // Verificar suspensión primero
                self.checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
                    if isSuspended {
                        DispatchQueue.main.async {
                            self?.authState = .suspended(reason: reason, expiresAt: expiresAt)
                        }
                        completion(false, nil, true)
                        return
                    }

                    // Intentar obtener usuario de Firestore
                    self?.firestoreService.fetchUser(userId: userId) { result in
                        switch result {
                        case .success(let appUser):
                            completion(true, appUser, false)

                        case .failure:

                            if retryCount < maxRetries - 1 {
                                // Continuar reintentando
                                self?.retryUserFetch(userId: userId, maxRetries: maxRetries, retryCount: retryCount + 1, completion: completion)
                            } else {
                                // Se acabaron los reintentos

                                // ✅ Thread-safe check del estado de registro
                                let registrationState = self?.authQueue.sync { self?._registrationState } ?? .idle

                                if registrationState == .registering || self?.isRegistering == true {
                                    completion(true, nil, false) // Asumir activo temporalmente
                                } else {
                                    self?.forceLogout()
                                    completion(false, nil, false)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ✅ NUEVA FUNCIÓN: Limpiar estado y forzar logout
        // ✅ Sincronizar datos básicos del perfil con el Widget
        private func syncProfileDataToWidget(userData: AppUser?) {
            guard let userData = userData else { return }
            let defaults = UserDefaults(suiteName: "group.com.glowsyapp")
            defaults?.set(userData.username, forKey: "widget_user_name")
            defaults?.set(userData.profileImagePath, forKey: "widget_user_profile_image")

            // Forzar recarga del widget
            WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
        }

        private func forceLogout() {
            DispatchQueue.main.async {
                self.isLoggedIn = false
                self.currentUser = nil
                self.currentFirebaseUser = nil
                self.isAccountDeactivated = false
                self.deactivatedUserData = nil
                self.isVerifyingAccount = false
                self.isRegistering = false
                self.authState = .unauthenticated

                // ✅ Thread-safe cleanup
                self.authQueue.async {
                    self._registrationState = .idle
                    self._isAuthProcessingEnabled = true
                    self._transitionLock = false
                }
            }
        }

        // ✅ NUEVA FUNCIÓN: Limpiar estado de registro thread-safe
        private func clearRegistrationState() {

            authQueue.async {
                self._registrationState = .idle
                self._isAuthProcessingEnabled = true
            }

            DispatchQueue.main.async {
                self.isRegistering = false
            }
        }

        // ✅ NUEVA FUNCIÓN: Verificar suspensión de usuario
        public func checkUserSuspension(userId: String, completion: @escaping (Bool, String?, Date?) -> Void) {

            // ✅ NUEVO: Si estamos offline, usar caché local o asumir que no está suspendido
        // para evitar esperas de timeout innecesarias.
        if !NetworkMonitor.shared.isConnected {
            completion(false, nil, nil)
            return
        }

        Firestore.firestore().collection("users").document(userId).getDocument { snapshot, _ in
                guard let data = snapshot?.data() else {
                    completion(false, nil, nil)
                    return
                }

                let isSuspended = data["isSuspended"] as? Bool ?? false

                if isSuspended {
                    // ✅ Verificar si la suspensión ya expiró
                    if let suspendedUntil = data["suspendedUntil"] as? Timestamp {
                        let expirationDate = suspendedUntil.dateValue()
                        if Date() > expirationDate {
                            // Suspensión expirada - reactivar usuario automáticamente
                            Firestore.firestore().collection("users").document(userId).updateData([
                                "isSuspended": false,
                                "suspendedUntil": FieldValue.delete(),
                                "suspensionReason": FieldValue.delete()
                            ]) { _ in }
                            completion(false, nil, nil)
                            return
                        } else {
                            // Suspensión aún válida
                            let reason = data["suspensionReason"] as? String
                            completion(true, reason, expirationDate)
                            return
                        }
                    } else {
                        // Suspensión sin fecha de expiración (permanente)
                        let reason = data["suspensionReason"] as? String
                        completion(true, reason, nil)
                        return
                    }
                }

                completion(false, nil, nil)
            }
        }

        // ✅ MODIFICAR: Completar registro con estado thread-safe
        func completeRegistration() {

            // ✅ THREAD-SAFE: Cambiar a estado de finalización y ACTIVAR LOCK
            authQueue.async {
                self._registrationState = .completing
                self._isAuthProcessingEnabled = true
                self._transitionLock = true
            }

            DispatchQueue.main.async {

                // ✅ Forzar re-evaluación si hay usuario
                if let user = self.currentFirebaseUser {
                    self.handleRegistrationCompletion(user: user)
                } else {
                    self.clearRegistrationState()
                }
            }
        }

    // ✅ NUEVA FUNCIÓN: Completar registro para logins sociales (Apple)
    func completeSocialRegistration(username: String, interests: [String], profileImage: UIImage?, completion: @escaping (Result<Void, Error>) -> Void) {
        // ✅ USAR AUTH DIRECTAMENTE: A veces el @Published currentFirebaseUser tarda un ciclo en actualizarse
        let firebaseUser = Auth.auth().currentUser

        guard let userId = firebaseUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se encontró el ID de usuario de Firebase"])))
            return
        }

        guard let email = firebaseUser?.email else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se encontró el Email del usuario de Firebase"])))
            return
        }

        // 1. Upload imagen si hay
        uploadProfileImageIfNeeded(image: profileImage, userId: userId) { [weak self] profileImagePath in
            guard let self = self else { return }

            // 2. Crear usuario en Firestore
            self.firestoreService.createUser(
                userId: userId,
                username: username,
                email: email,
                interests: interests,
                profileImagePath: profileImagePath
            ) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    // 3. Todo listo, devolver éxito
                // NO llamamos a completeRegistration() aquí. Dejamos que la Vista lo haga
                // para sincronizarlo con la animación (igual que en RegisterView).
                completion(.success(()))
                }
            }
        }
    }

    // ✅ REGISTRO CORREGIDO - Establecer flags SÍNCRONAMENTE antes de crear usuario
    func register(username: String, email: String, password: String, interests: [String], privacyPolicyAccepted: Bool, profileImage: UIImage?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard privacyPolicyAccepted else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.privacyPolicyRequired", comment: "Privacy policy required")])))
            return
        }


        // ✅ CRÍTICO: Establecer flags SÍNCRONAMENTE antes de cualquier operación
        authQueue.sync {
            self._registrationState = .registering
            self._isAuthProcessingEnabled = false
        }

        // ✅ CORREGIDO: usar async en lugar de sync para evitar deadlock
        DispatchQueue.main.async {
            self.isRegistering = true

        }

        // ✅ Pequeño delay para asegurar que los flags se propaguen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Verificar disponibilidad de username
            self.db.collection("usernames").document(username.lowercased()).getDocument { document, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.clearRegistrationState()
                        completion(.failure(error))
                    }
                    return
                }
                if document?.exists ?? false {
                    DispatchQueue.main.async {
                        self.clearRegistrationState()
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.usernameUnavailable", comment: "Username unavailable")])))
                    }
                    return
                }


                // ✅ Crear usuario en Firebase Auth
                Auth.auth().createUser(withEmail: email, password: password) { result, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.clearRegistrationState()
                            completion(.failure(self.mapAuthError(error)))
                            return
                        }
                        guard let userId = result?.user.uid else {
                            self.clearRegistrationState()
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("auth.error.userIdNotFound", comment: "User ID not found")])))
                            return
                        }

                        // Enviar verificación de email
                        result?.user.sendEmailVerification { _ in }

                        // ✅ Upload imagen con mejor control de tiempo
                        self.uploadProfileImageIfNeeded(image: profileImage, userId: userId) { profileImagePath in
                            // Usar FirestoreService para crear el usuario
                            self.firestoreService.createUser(
                                userId: userId,
                                username: username,
                                email: email,
                                interests: interests,
                                profileImagePath: profileImagePath
                            ) { error in
                                DispatchQueue.main.async {
                                    if let error = error {
                                        // Si falla Firestore, eliminar usuario de Auth y limpiar estado
                                        result?.user.delete { _ in }
                                        self.clearRegistrationState()
                                        completion(.failure(error))
                                    } else {
                                        completion(.success(()))
                                        // ✅ NO limpiar estado aquí - se limpiará en completeRegistration()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

        // ✅ NUEVA FUNCIÓN: Upload imagen con mejor control
        private func uploadProfileImageIfNeeded(image: UIImage?, userId: String, completion: @escaping (String?) -> Void) {
            guard let image = image else {
                completion(nil)
                return
            }


            let fileName = "\(UUID().uuidString)_\(userId)"
            let imageRef = storage.child("images/\(fileName).jpg")
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                completion(nil)
                return
            }

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            imageRef.putData(imageData, metadata: metadata) { _, error in
                if error != nil {
                    completion(nil)
                    return
                }

                imageRef.downloadURL { url, error in
                    if error != nil {
                        completion(nil)
                    } else if let url = url {
                        completion(url.absoluteString)
                    } else {
                        completion(nil)
                    }
                }
            }
        }

        // ✅ Función de reactivación mejorada
        func reactivateAccount(completion: @escaping (Result<Void, Error>) -> Void) {
            guard let userId = currentFirebaseUser?.uid else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
                return
            }


            // ✅ Mostrar estado de verificación
            DispatchQueue.main.async {
                self.isVerifyingAccount = true
                self.authState = .verifyingAccount
            }

            let accountService = AccountManagementService()
            accountService.reactivateAccount(userId: userId) { [weak self] result in
                switch result {
                case .success:
                    // ✅ IMPORTANTE: Forzar re-verificación del estado
                    self?.checkAccountStatus(userId: userId) { isActive, userData, _ in
                        DispatchQueue.main.async {
                            self?.isVerifyingAccount = false
                            if isActive, let userData = userData {
                                self?.isLoggedIn = true
                                self?.currentUser = userData
                                self?.isAccountDeactivated = false
                                self?.deactivatedUserData = nil
                                self?.authState = .authenticated

                                // ✅ NUEVO: Iniciar listener después de reactivación
                                self?.startSuspensionListener()

                            } else {
                                // Algo salió mal, mantener estado desactivado
                                self?.authState = .deactivated
                            }
                        }
                    }
                    completion(.success(()))
                case .failure(let error):
                    DispatchQueue.main.async {
                        self?.isVerifyingAccount = false
                        self?.authState = .deactivated
                    }
                    completion(.failure(error))
                }
            }
        }

        // ✅ NUEVA FUNCIÓN: Actualizar currentUser después de cambios
        func refreshCurrentUser() {
            guard let userId = currentFirebaseUser?.uid else {
                return
            }


            firestoreService.fetchUser(userId: userId) { [weak self] result in
                switch result {
                case .success(let appUser):
                    DispatchQueue.main.async {
                        self?.currentUser = appUser
                    }
                case .failure(_):
                    break
                }
            }
        }

        // ✅ NUEVA FUNCIÓN: Actualizar un campo específico del usuario
        func updateUserField<T: Codable>(_ field: String, value: T, completion: @escaping (Bool) -> Void) {
            guard let userId = currentUser?.id else {
                completion(false)
                return
            }

            db.collection("users").document(userId).updateData([
                field: value,
                "updatedAt": FieldValue.serverTimestamp()
            ]) { [weak self] error in
                if error == nil {
                    // Refrescar usuario después de actualización exitosa
                    DispatchQueue.main.async {
                        self?.refreshCurrentUser()
                    }
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }

        func checkUsernameAvailability(username: String, interests: [String], completion: @escaping (Bool, [String]?) -> Void) {
            let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanUsername.isEmpty else {
                completion(true, nil)
                return
            }

            db.collection("usernames").document(cleanUsername).getDocument { document, error in
                if error != nil {
                    completion(false, nil)
                    return
                }

                if !(document?.exists ?? false) {
                    completion(true, nil)
                } else {
                    // Generar sugerencias personalizadas
                    var suggestions: [String] = []

                    // Sugerencias basadas en intereses si están disponibles
                    if !interests.isEmpty {
                        let randomInterest = interests.randomElement()!.lowercased().replacingOccurrences(of: " ", with: "")
                        suggestions.append("\(cleanUsername)_\(randomInterest)")
                    }

                    // Sugerencias con números
                    suggestions.append("\(cleanUsername)\(Int.random(in: 100...999))")
                    suggestions.append("\(cleanUsername)_\(Int.random(in: 10...99))")

                    // Sugerencia con "moments"
                    suggestions.append("\(cleanUsername).moments")

                    // Limitar a 4 sugerencias
                    completion(false, Array(suggestions.prefix(4)))
                }
            }
        }

        func resetPassword(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
            Auth.auth().sendPasswordReset(withEmail: email) { error in
                if let error = error {
                    completion(.failure(self.mapAuthError(error)))
                } else {
                    completion(.success(()))
                }
            }
        }

        func fetchAvailableInterests(completion: @escaping (Result<[String], Error>) -> Void) {
            firestoreService.fetchAvailableInterests(completion: completion)
        }

        func logout() {

            // ✅ Detener listener antes de cerrar sesión
            stopSuspensionListener()

            do {
                try Auth.auth().signOut()

                // ✅ Forzar limpieza inmediata del estado
                DispatchQueue.main.async {
                    self.currentFirebaseUser = nil
                    self.isLoggedIn = false
                    self.currentUser = nil

                    // ✅ NUEVO: Limpiar también estados de suspensión/desactivación
                    self.isAccountDeactivated = false
                    self.deactivatedUserData = nil
                    self.isVerifyingAccount = false
                    self.authState = .unauthenticated
                    self.isRegistering = false

                    // ✅ Thread-safe cleanup
                    self.authQueue.async {
                        self._registrationState = .idle
                        self._isAuthProcessingEnabled = true
                    }

                    // ✅ Forzar notificación de cambios
                    self.objectWillChange.send()

                }

            } catch {

                // ✅ Incluso si Firebase falla, limpiar estado local
                DispatchQueue.main.async {
                    self.currentFirebaseUser = nil
                    self.isLoggedIn = false
                    self.currentUser = nil
                    self.isAccountDeactivated = false
                    self.deactivatedUserData = nil
                    self.isVerifyingAccount = false
                    self.authState = .unauthenticated
                    self.isRegistering = false

                    // ✅ Thread-safe cleanup
                    self.authQueue.async {
                        self._registrationState = .idle
                        self._isAuthProcessingEnabled = true
                    }

                    self.objectWillChange.send()

                }
            }
        }

        private nonisolated func mapAuthError(_ error: Error) -> Error {
            let nsError = error as NSError
            let errorMessage: String
            let rawDescription = nsError.localizedDescription.lowercased()

            switch AuthErrorCode(rawValue: nsError.code) {
            case .emailAlreadyInUse:
                errorMessage = NSLocalizedString("auth.error.emailInUse", comment: "Email already registered")
            case .invalidEmail:
                errorMessage = NSLocalizedString("auth.error.invalidEmail", comment: "Invalid email")
            case .wrongPassword:
                errorMessage = NSLocalizedString("auth.error.wrongPassword", comment: "Wrong password")
            case .userNotFound:
                errorMessage = NSLocalizedString("auth.error.userNotFound", comment: "User not found")
            case .weakPassword:
                errorMessage = NSLocalizedString("auth.error.weakPassword", comment: "Weak password")
            case .networkError:
                errorMessage = NSLocalizedString("auth.error.network", comment: "Network error")
            case .tooManyRequests:
                errorMessage = NSLocalizedString("auth.error.tooManyRequests", comment: "Too many requests")
            case .invalidCredential:
                errorMessage = NSLocalizedString("auth.error.invalidCredentials", comment: "Invalid credentials")
            case .userDisabled:
                errorMessage = NSLocalizedString("auth.error.userDisabled", comment: "User disabled")
            default:
                // ✅ Mensaje más user-friendly basado en el contenido del error
                if rawDescription.contains("malformed") || rawDescription.contains("expired") || rawDescription.contains("invalid credential") {
                    errorMessage = NSLocalizedString("auth.error.invalidCredentials", comment: "Invalid credentials")
                } else if rawDescription.contains("password") || rawDescription.contains("contraseña") || rawDescription.contains("contrasenya") {
                    errorMessage = NSLocalizedString("auth.error.wrongPassword", comment: "Wrong password")
                } else if rawDescription.contains("user") || rawDescription.contains("usuario") || rawDescription.contains("usuari") || rawDescription.contains("not found") {
                    errorMessage = NSLocalizedString("auth.error.userNotFound", comment: "User not found")
                } else if rawDescription.contains("network") || rawDescription.contains("conexión") || rawDescription.contains("connexió") || rawDescription.contains("connection") {
                    errorMessage = NSLocalizedString("auth.error.network", comment: "Network error")
                } else {
                    errorMessage = NSLocalizedString("auth.error.generic", comment: "Generic login error")
                }
            }

            return NSError(domain: "", code: nsError.code, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

    // MARK: - Sign in with Apple Logic

    func startAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    // ✅ NUEVA FUNCIÓN: Vincular cuenta existente con Apple
    func linkWithApple(idToken: String, nonce: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let credential = OAuthProvider.credential(providerID: .apple, idToken: idToken, rawNonce: nonce)

        Auth.auth().currentUser?.link(with: credential) { [weak self] authResult, error in
            if let error = error {
                completion(.failure(self?.mapAuthError(error) ?? error))
            } else {
                // Actualizar usuario interno para reflejar los nuevos providerData
                DispatchQueue.main.async {
                    self?.currentFirebaseUser = authResult?.user
                    completion(.success(()))
                }
            }
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?, email: String?, completion: @escaping (Result<Bool, Error>) -> Void) {

        // 1. ACTIVAR LOCK: Silenciar listener global inmediatamente
        authQueue.async {
            self._transitionLock = true
        }

        let credential = OAuthProvider.credential(providerID: .apple, idToken: idToken, rawNonce: nonce)

        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }

            if let error = error {
                // Liberar lock en error
                self.authQueue.async { self._transitionLock = false }
                completion(.failure(self.mapAuthError(error)))
                return
            }

            guard let user = authResult?.user else {
                self.authQueue.async { self._transitionLock = false }
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Auth failed"])))
                return
            }

            // Verificar si el usuario ya existe en Firestore
            // El lock sigue activo, por lo que el listener global ignorará los eventos de Auth
            self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                DispatchQueue.main.async {
                    if isSuspended {
                        // Usuario existente suspendido: no debe entrar al flujo de registro social.
                        self.isLoggedIn = false
                        self.currentUser = nil
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = false
                        self.deactivatedUserData = nil
                        self.isRegistering = false
                        self.isVerifyingAccount = false
                        self.authQueue.async { self._transitionLock = false }
                        completion(.success(false))
                        return
                    }

                    if isActive, let userData = userData {
                        // USUARIO EXISTENTE: Login normal MANUAL
                        // Hidratamos el estado nosotros mismos para saltarnos el listener
                        self.saveCachedAccountStatus(userId: user.uid, decision: .allowed)
                        LocalPersistenceService.shared.saveCurrentUser(userData)
                        self.isLoggedIn = true
                        self.currentUser = userData
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = false
                        self.deactivatedUserData = nil
                        self.authState = .authenticated

                        // Iniciar listeners
                        self.startSuspensionListener()

                        // Liberar lock ahora que el estado es consistente
                        self.authQueue.async { self._transitionLock = false }

                        completion(.success(true))
                    } else if let userData = userData {
                        // Usuario existente desactivado: mostrar pantalla de cuenta en reposo.
                        self.saveCachedAccountStatus(userId: user.uid, decision: .deactivated)
                        self.isLoggedIn = false
                        self.currentUser = nil
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = true
                        self.deactivatedUserData = userData
                        self.isRegistering = false
                        self.isVerifyingAccount = false
                        self.authState = .deactivated
                        self.authQueue.async { self._transitionLock = false }
                        completion(.success(false))
                    } else {
                        // USUARIO NUEVO: Preparar registro
                        // 1. Establecer flags de registro PROTEGIDOS
                        self.authQueue.async {
                            self._registrationState = .registering
                            self._isAuthProcessingEnabled = false

                            // 2. Transición atómica: Cambiamos de Lock -> Registering
                            // Al quitar el lock, ya estamos en .registering, así que el listener seguirá bloqueado
                            self._transitionLock = false
                        }

                        self.isRegistering = true
                        self.currentFirebaseUser = user

                        completion(.success(false))
                    }
                }
            }
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }

            randoms.forEach { random in
                if remainingLength == 0 { return }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }

    // MARK: - Passkey Custom Token Login

    func signInWithPasskeyToken(_ customToken: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // 1. ACTIVAR LOCK para evitar listeners
        authQueue.async {
            self._transitionLock = true
        }

        Auth.auth().signIn(withCustomToken: customToken) { [weak self] authResult, error in
            guard let self = self else { return }

            if let error = error {
                self.authQueue.async { self._transitionLock = false }
                completion(.failure(self.mapAuthError(error)))
                return
            }

            guard let user = authResult?.user else {
                self.authQueue.async { self._transitionLock = false }
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Auth failed"])))
                return
            }

            // Reutilizamos el check para asegurarnos de que la cuenta sigue activa
            self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                DispatchQueue.main.async {
                    if isSuspended {
                        self.isLoggedIn = false
                        self.currentUser = nil
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = false
                        self.authQueue.async { self._transitionLock = false }
                        completion(.failure(NSError(domain: "", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cuenta suspendida"])))
                        return
                    }

                    if isActive, let userData = userData {
                        self.saveCachedAccountStatus(userId: user.uid, decision: .allowed)
                        LocalPersistenceService.shared.saveCurrentUser(userData)
                        self.isLoggedIn = true
                        self.currentUser = userData
                        self.currentFirebaseUser = user
                        self.authState = .authenticated

                        self.startSuspensionListener()

                        self.authQueue.async { self._transitionLock = false }
                        completion(.success(()))
                    } else if let userData = userData {
                        self.saveCachedAccountStatus(userId: user.uid, decision: .deactivated)
                        self.isLoggedIn = false
                        self.isAccountDeactivated = true
                        self.deactivatedUserData = userData
                        self.authState = .deactivated
                        self.authQueue.async { self._transitionLock = false }
                        completion(.failure(NSError(domain: "", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cuenta desactivada"])))
                    } else {
                        // Un Passkey no debería llegar aquí si el usuario no tiene cuenta,
                        // ya que requerimos que ya esté logueado para registrar el passkey.
                        self.authQueue.async { self._transitionLock = false }
                        completion(.failure(NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "Datos de usuario no encontrados en Firestore"])))
                    }
                }
            }
        }
    }
}
