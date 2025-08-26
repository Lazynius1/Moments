import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Combine
import Foundation
import UIKit

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
    
    // ✅ NUEVO: Queue serial para thread safety
    private let authQueue = DispatchQueue(label: "com.moments.auth", qos: .userInteractive)
    
    // ✅ NUEVO: Estado de registro thread-safe
    private var _registrationState: RegistrationState = .idle
    private var _isAuthProcessingEnabled: Bool = true
    
    enum RegistrationState {
        case idle
        case registering
        case completing
    }
    
    // ✅ NUEVO: Computed properties thread-safe
    var isInRegistrationProcess: Bool {
        return authQueue.sync {
            return _registrationState != .idle
        }
    }
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    private let storage = FirebaseStorage.Storage.storage().reference()
    private let firestoreService = FirestoreService()
    
    // ✅ NUEVO: Listener de suspensión en tiempo real
    private var suspensionListener: ListenerRegistration?
    
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
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let self = self else { return }
            
            
            // ✅ THREAD-SAFE: Verificar estado de registro
            let registrationState = self.authQueue.sync { self._registrationState }
            let isAuthProcessingEnabled = self.authQueue.sync { self._isAuthProcessingEnabled }
            
            
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
                                self.isLoggedIn = true
                                self.currentUser = userData
                                self.currentFirebaseUser = user
                                self.isAccountDeactivated = false
                                self.deactivatedUserData = nil
                                self.authState = .authenticated
                                self.startSuspensionListener()
                                
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
                            self.isLoggedIn = true
                            self.currentUser = userData
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = false
                            self.deactivatedUserData = nil
                            self.authState = .authenticated
                            
                            // ✅ NUEVO: Iniciar listener de suspensión
                            self.startSuspensionListener()
                            
                        } else {
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
                        
                    case .failure(let error):
                        
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
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
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
            self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                DispatchQueue.main.async {
                    self.isVerifyingAccount = false
                    
                    if isSuspended {
                        return
                    }
                    
                    if isActive, let userData = userData {
                        self.isLoggedIn = true
                        self.currentUser = userData
                        self.currentFirebaseUser = user
                        self.isAccountDeactivated = false
                        self.deactivatedUserData = nil
                        self.authState = .authenticated
                        self.startSuspensionListener()
                        
                        // ✅ Limpiar estado de registro
                        self.authQueue.async {
                            self._registrationState = .idle
                        }
                        self.isRegistering = false
                        
                    } else {
                        self.authState = .deactivated
                        self.isAccountDeactivated = true
                        self.deactivatedUserData = userData
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
            
            
            suspensionListener = db.collection("users").document(userId)
                .addSnapshotListener { [weak self] snapshot, error in
                    if let error = error {
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
        }
        
        func stopSuspensionListener() {
            suspensionListener?.remove()
            suspensionListener = nil
        }
        
        // ✅ Login mejorado con mejor manejo de estados
        func login(identifier: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
            
            guard !identifier.isEmpty, !password.isEmpty else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "El identificador y la contraseña son obligatorios."])))
                return
            }
            
            let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
            let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
            
            if predicate.evaluate(with: identifier) {
                // Inicio de sesión con email
                Auth.auth().signIn(withEmail: identifier, password: password) { result, error in
                    if let error = error {
                        completion(.failure(self.mapAuthError(error)))
                    } else {
                        completion(.success(()))
                    }
                }
            } else {
                // Inicio de sesión con username
                if let cachedEmail = UserDefaults.standard.string(forKey: "cachedEmail_\(identifier.lowercased())") {
                    Auth.auth().signIn(withEmail: cachedEmail, password: password) { result, error in
                        if let error = error {
                            completion(.failure(self.mapAuthError(error)))
                        } else {
                            completion(.success(()))
                        }
                    }
                } else {
                    // No hay caché, consultar Firestore
                    db.collection("usernames").document(identifier.lowercased()).getDocument { document, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        
                        guard let data = document?.data(),
                              let email = data["email"] as? String else {
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no encontrado. Por favor, verifica tu nombre de usuario."])))
                            return
                        }
                        
                        // Iniciar sesión con el email obtenido
                        Auth.auth().signIn(withEmail: email, password: password) { result, error in
                            if let error = error {
                                completion(.failure(self.mapAuthError(error)))
                            } else {
                                UserDefaults.standard.set(email, forKey: "cachedEmail_\(identifier.lowercased())")
                                completion(.success(()))
                            }
                        }
                    }
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
            
            // PRIMERO verificar suspensión (solo para usuarios existentes)
            checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
                if isSuspended {
                    
                    DispatchQueue.main.async {
                        self?.authState = .suspended(reason: reason, expiresAt: expiresAt)
                    }
                    
                    completion(false, nil, true)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        do {
                            try Auth.auth().signOut()
                        } catch {
                        }
                    }
                    return
                }
                
                // Si no está suspendido, verificar estado normal
                self?.firestoreService.fetchUser(userId: userId) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let appUser):
                            let isActive = appUser.isActive
                            completion(isActive, appUser, false)
                            
                        case .failure(let error):
                            
                            // ✅ Verificar nuevamente si estamos en registro
                            let currentRegistrationState = self?.authQueue.sync { self?._registrationState } ?? .idle
                            
                            if currentRegistrationState == .registering || self?.isRegistering == true {
                                completion(false, nil, false)
                            } else {
                                self?.forceLogout()
                                completion(false, nil, false)
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
                            
                        case .failure(let error):
                            
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
            
            db.collection("users").document(userId).getDocument { snapshot, error in
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
                            self.db.collection("users").document(userId).updateData([
                                "isSuspended": false,
                                "suspendedUntil": FieldValue.delete(),
                                "suspensionReason": FieldValue.delete()
                            ]) { error in
                                if let error = error {
                                } else {
                                }
                            }
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
            
            // ✅ THREAD-SAFE: Cambiar a estado de finalización
            authQueue.async {
                self._registrationState = .completing
                self._isAuthProcessingEnabled = true
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
    
    // ✅ REGISTRO CORREGIDO - Establecer flags SÍNCRONAMENTE antes de crear usuario
    func register(username: String, email: String, password: String, interests: [String], privacyPolicyAccepted: Bool, profileImage: UIImage?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard privacyPolicyAccepted else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Debes aceptar las políticas de privacidad."])))
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
                    self.clearRegistrationState()
                    completion(.failure(error))
                    return
                }
                if document?.exists ?? false {
                    self.clearRegistrationState()
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nombre de usuario no disponible."])))
                    return
                }
                
                
                // ✅ Crear usuario en Firebase Auth
                Auth.auth().createUser(withEmail: email, password: password) { result, error in
                    if let error = error {
                        self.clearRegistrationState()
                        completion(.failure(self.mapAuthError(error)))
                        return
                    }
                    guard let userId = result?.user.uid else {
                        self.clearRegistrationState()
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener el ID del usuario."])))
                        return
                    }
                    
                    
                    // Enviar verificación de email
                    result?.user.sendEmailVerification { error in
                        if let error = error {
                        } else {
                        }
                    }
                    
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
                            if let error = error {
                                
                                // Si falla Firestore, eliminar usuario de Auth y limpiar estado
                                result?.user.delete { _ in
                                }
                                
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
                if let error = error {
                    completion(nil)
                    return
                }
                
                imageRef.downloadURL { url, error in
                    if let error = error {
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
                    self?.refreshCurrentUser()
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
                if let error = error {
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
        
        private func mapAuthError(_ error: Error) -> Error {
            let nsError = error as NSError
            let errorMessage: String
            
            switch AuthErrorCode(rawValue: nsError.code) {
            case .emailAlreadyInUse:
                errorMessage = "Este correo ya está registrado. Intenta iniciar sesión."
            case .invalidEmail:
                errorMessage = "El correo electrónico no es válido."
            case .wrongPassword:
                errorMessage = "Contraseña incorrecta. Inténtalo de nuevo."
            case .userNotFound:
                errorMessage = "No se encontró un usuario con estas credenciales."
            case .weakPassword:
                errorMessage = "La contraseña es muy débil. Usa al menos 8 caracteres con letras y números."
            case .networkError:
                errorMessage = "Error de conexión. Verifica tu internet e intenta de nuevo."
            case .tooManyRequests:
                errorMessage = "Demasiados intentos. Por favor, espera un momento."
            default:
                errorMessage = "Error: \(nsError.localizedDescription)"
            }
            
            return NSError(domain: "", code: nsError.code, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
