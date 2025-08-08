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
            
            print("🔄 Firebase Auth usuario detectado: \(user?.uid ?? "nil")")
            print("   - Email: \(user?.email ?? "N/A")")
            
            // ✅ THREAD-SAFE: Verificar estado de registro
            let registrationState = self.authQueue.sync { self._registrationState }
            let isAuthProcessingEnabled = self.authQueue.sync { self._isAuthProcessingEnabled }
            
            print("   - registrationState: \(registrationState)")
            print("   - isAuthProcessingEnabled: \(isAuthProcessingEnabled)")
            print("   - isRegistering (Published): \(self.isRegistering)")
            
            // ✅ CRÍTICO: Si está en proceso de registro O procesamiento deshabilitado, pausar
            if registrationState == .registering || !isAuthProcessingEnabled {
                print("🚧 Registro en proceso - pausando AuthStateListener")
                DispatchQueue.main.async {
                    self.currentFirebaseUser = user
                }
                return
            }
            
            // ✅ NUEVO: Si está completando registro, usar proceso especial
            if registrationState == .completing {
                print("🎯 Completando registro - proceso especial")
                self.handleRegistrationCompletion(user: user)
                return
            }
            
            // ✅ CRÍTICO: NUEVA VERIFICACIÓN - Si hay usuario pero es muy reciente (< 5 segundos)
            // probablemente es un registro recién completado
            if let user = user {
                let userCreationTime = user.metadata.creationDate?.timeIntervalSinceNow ?? -999
                let isVeryRecentUser = userCreationTime > -5.0 // Creado hace menos de 5 segundos
                
                if isVeryRecentUser {
                    print("🆕 Usuario muy reciente detectado (creado hace \(abs(userCreationTime)) segundos)")
                    print("   - Probablemente es un registro recién completado")
                    print("   - Usando sistema de retry para esperar documento de Firestore")
                    
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
                                print("🛡️ Usuario suspendido")
                                return
                            }
                            
                            if isActive, let userData = userData {
                                print("✅ Usuario recién registrado - configurando estado logueado")
                                self.isLoggedIn = true
                                self.currentUser = userData
                                self.currentFirebaseUser = user
                                self.isAccountDeactivated = false
                                self.deactivatedUserData = nil
                                self.authState = .authenticated
                                self.startSuspensionListener()
                                
                            } else {
                                print("❌ Error: usuario recién creado no encontrado en Firestore")
                                self.forceLogout()
                            }
                        }
                    }
                    return
                }
            }
            
            // ✅ NUEVO: Si detectamos un usuario durante registro pero los flags no están listos, IGNORAR
            if let user = user, self.isRegistering {
                print("🚨 LISTENER TEMPRANO DETECTADO - Usuario en registro pero flags inconsistentes")
                print("   - Ignorando esta ejecución del listener")
                print("   - El listener correcto se ejecutará cuando los flags estén sincronizados")
                DispatchQueue.main.async {
                    self.currentFirebaseUser = user
                }
                return
            }
            
            // Si es la primera vez que se dispara el listener y no hay usuario, establecer el estado inicial.
            if self.authState == .loading && user == nil {
                DispatchQueue.main.async {
                    self.authState = .unauthenticated
                    print("✅ Chequeo inicial de AuthStateListener completado (no user).")
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
                    print("🔄 Estados reseteados - iniciando verificación")
                }
                
                // Verificar estado de cuenta y cargar AppUser completo
                self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                    print("🔄 Resultado de verificación:")
                    print("   - isActive: \(isActive)")
                    print("   - userData disponible: \(userData != nil)")
                    print("   - isSuspended: \(isSuspended)")
                    
                    DispatchQueue.main.async {
                        self.isVerifyingAccount = false
                        
                        // ✅ CORREGIDO: Verificar suspensión PRIMERO
                        if isSuspended {
                            print("🛡️ Manteniendo estado suspended - no sobrescribir")
                            return
                        }
                        
                        if isActive {
                            print("✅ Cuenta activa - configurando estado logueado")
                            self.isLoggedIn = true
                            self.currentUser = userData
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = false
                            self.deactivatedUserData = nil
                            self.authState = .authenticated
                            
                            // ✅ NUEVO: Iniciar listener de suspensión
                            self.startSuspensionListener()
                            
                        } else {
                            print("⚠️ Cuenta desactivada - configurando estado desactivado")
                            self.isLoggedIn = false
                            self.currentUser = nil
                            self.currentFirebaseUser = user
                            self.isAccountDeactivated = true
                            self.deactivatedUserData = userData
                            self.authState = .deactivated
                        }
                        
                        print("🔄 Estado final configurado:")
                        print("   - isLoggedIn: \(self.isLoggedIn)")
                        print("   - currentUser: \(self.currentUser?.username ?? "nil")")
                        print("   - isPlusSubscriber: \(self.currentUser?.isPlusSubscriber ?? false)")
                        print("   - isAccountDeactivated: \(self.isAccountDeactivated)")
                        print("   - authState: \(self.authState)")
                    }
                }
            } else {
                print("🔄 Sin usuario autenticado - limpiando estado")
                DispatchQueue.main.async {
                    // ✅ CORREGIDO: No limpiar si está suspended
                    if case .suspended = self.authState {
                        print("🛡️ Manteniendo estado suspended después de signOut")
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
        print("🆕 Iniciando retry especial para usuario recién creado: \(userId)")
        
        // Para usuarios recién creados, dar más tiempo (hasta 10 segundos)
        retryUserFetchWithCustomParams(userId: userId, maxRetries: 8, baseDelay: 0.5, maxDelay: 1.5, completion: completion)
    }

    // ✅ FUNCIÓN MEJORADA: Retry con parámetros personalizables
    private func retryUserFetchWithCustomParams(userId: String, maxRetries: Int, baseDelay: TimeInterval, maxDelay: TimeInterval, retryCount: Int = 0, completion: @escaping (Bool, AppUser?, Bool) -> Void) {
        
        let delay = min(Double(retryCount) * baseDelay, maxDelay)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            print("🔄 Intento \(retryCount + 1)/\(maxRetries) de obtener usuario recién creado")
            
            // Verificar suspensión primero
            self.checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
                if isSuspended {
                    print("🚫 Usuario suspendido durante retry")
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
                        print("✅ Usuario recién creado obtenido exitosamente en intento \(retryCount + 1)")
                        completion(true, appUser, false)
                        
                    case .failure(let error):
                        print("❌ Intento \(retryCount + 1) falló: \(error.localizedDescription)")
                        
                        if retryCount < maxRetries - 1 {
                            // Continuar reintentando
                            print("🔄 Reintentando usuario recién creado en \(min(Double(retryCount + 1) * baseDelay, maxDelay)) segundos...")
                            self?.retryUserFetchWithCustomParams(userId: userId, maxRetries: maxRetries, baseDelay: baseDelay, maxDelay: maxDelay, retryCount: retryCount + 1, completion: completion)
                        } else {
                            // Se acabaron los reintentos para usuario recién creado
                            print("❌ Se agotaron los reintentos para usuario recién creado")
                            print("❌ Esto es un error crítico - el documento debería existir")
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
            print("❌ No hay usuario en finalización de registro")
            return
        }
        
        print("🎯 Manejando finalización de registro para: \(user.uid)")
        
        DispatchQueue.main.async {
            self.authState = .verifyingAccount
            self.isVerifyingAccount = true
            self.currentFirebaseUser = user
        }
        
        // ✅ Dar tiempo para que Firestore esté completamente listo
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔄 Verificando usuario después de delay de finalización")
            self.checkAccountStatus(userId: user.uid) { isActive, userData, isSuspended in
                DispatchQueue.main.async {
                    self.isVerifyingAccount = false
                    
                    if isSuspended {
                        print("🛡️ Usuario suspendido en finalización")
                        return
                    }
                    
                    if isActive, let userData = userData {
                        print("✅ Registro completado exitosamente")
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
                        print("❌ Error en finalización - usuario no activo")
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
                print("⚠️ No hay usuario para iniciar listener de suspensión")
                return
            }
            
            print("👂 Iniciando listener de suspensión para: \(userId)")
            
            suspensionListener = db.collection("users").document(userId)
                .addSnapshotListener { [weak self] snapshot, error in
                    if let error = error {
                        print("❌ Error en listener de suspensión: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = snapshot?.data() else {
                        print("📄 No hay datos en listener de suspensión")
                        return
                    }
                    
                    let isSuspended = data["isSuspended"] as? Bool ?? false
                    
                    if isSuspended {
                        print("🚫 SUSPENSIÓN DETECTADA EN TIEMPO REAL")
                        
                        // Verificar si no expiró
                        if let suspendedUntil = data["suspendedUntil"] as? Timestamp {
                            if Date() > suspendedUntil.dateValue() {
                                print("⏰ Suspensión expirada - no cerrar sesión")
                                return
                            }
                        }
                        
                        print("🚪 Cerrando sesión por suspensión")
                        DispatchQueue.main.async {
                            self?.logout()
                        }
                    }
                }
        }
        
        func stopSuspensionListener() {
            print("🛑 Deteniendo listener de suspensión")
            suspensionListener?.remove()
            suspensionListener = nil
        }
        
        // ✅ Login mejorado con mejor manejo de estados
        func login(identifier: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
            print("🔐 Iniciando sesión con identificador: \(identifier)")
            
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
                        print("❌ Error al iniciar sesión con email: \(error.localizedDescription)")
                        completion(.failure(self.mapAuthError(error)))
                    } else {
                        print("✅ Login exitoso en Firebase Auth - AuthStateListener manejará el resto")
                        completion(.success(()))
                    }
                }
            } else {
                // Inicio de sesión con username
                if let cachedEmail = UserDefaults.standard.string(forKey: "cachedEmail_\(identifier.lowercased())") {
                    print("📧 Email encontrado en caché para username \(identifier): \(cachedEmail)")
                    Auth.auth().signIn(withEmail: cachedEmail, password: password) { result, error in
                        if let error = error {
                            print("❌ Error al iniciar sesión con email en caché: \(error.localizedDescription)")
                            completion(.failure(self.mapAuthError(error)))
                        } else {
                            print("✅ Login exitoso con username (desde caché)")
                            completion(.success(()))
                        }
                    }
                } else {
                    // No hay caché, consultar Firestore
                    db.collection("usernames").document(identifier.lowercased()).getDocument { document, error in
                        if let error = error {
                            print("❌ Error al buscar username: \(error.localizedDescription)")
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
                                print("❌ Error al iniciar sesión: \(error.localizedDescription)")
                                completion(.failure(self.mapAuthError(error)))
                            } else {
                                print("✅ Login exitoso con username")
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
            print("🔍 Verificando estado de cuenta para usuario: \(userId)")
            
            // ✅ THREAD-SAFE: Verificar estado de registro
            let registrationState = authQueue.sync { _registrationState }
            
            print("   - registrationState: \(registrationState)")
            print("   - isRegistering (Published): \(self.isRegistering)")
            
            // ✅ CRÍTICO: Si estamos registrando, usar sistema de retry
            if registrationState == .registering || self.isRegistering {
                print("🚀 Usuario en proceso de registro - usando sistema de retry...")
                retryUserFetch(userId: userId, maxRetries: 5, completion: completion)
                return
            }
            
            // PRIMERO verificar suspensión (solo para usuarios existentes)
            checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
                if isSuspended {
                    print("🚫 Usuario suspendido - configurando estado suspended")
                    
                    DispatchQueue.main.async {
                        self?.authState = .suspended(reason: reason, expiresAt: expiresAt)
                    }
                    
                    completion(false, nil, true)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        do {
                            try Auth.auth().signOut()
                        } catch {
                            print("❌ Error al cerrar sesión del usuario suspendido: \(error)")
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
                            print("📊 Usuario obtenido - isActive: \(isActive)")
                            completion(isActive, appUser, false)
                            
                        case .failure(let error):
                            print("❌ Error al obtener AppUser: \(error.localizedDescription)")
                            
                            // ✅ Verificar nuevamente si estamos en registro
                            let currentRegistrationState = self?.authQueue.sync { self?._registrationState } ?? .idle
                            
                            if currentRegistrationState == .registering || self?.isRegistering == true {
                                print("⚠️ Error durante registro - el documento probablemente no existe aún")
                                completion(false, nil, false)
                            } else {
                                print("❌ Error al obtener usuario existente - forzando logout")
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
                print("🔄 Intento \(retryCount + 1)/\(maxRetries) de obtener usuario en registro")
                
                // Verificar suspensión primero
                self.checkUserSuspension(userId: userId) { [weak self] isSuspended, reason, expiresAt in
                    if isSuspended {
                        print("🚫 Usuario suspendido durante retry")
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
                            print("✅ Usuario obtenido exitosamente en intento \(retryCount + 1)")
                            completion(true, appUser, false)
                            
                        case .failure(let error):
                            print("❌ Intento \(retryCount + 1) falló: \(error.localizedDescription)")
                            
                            if retryCount < maxRetries - 1 {
                                // Continuar reintentando
                                print("🔄 Reintentando en \(Double(retryCount + 1) * 0.5) segundos...")
                                self?.retryUserFetch(userId: userId, maxRetries: maxRetries, retryCount: retryCount + 1, completion: completion)
                            } else {
                                // Se acabaron los reintentos
                                print("❌ Se agotaron los reintentos. Documento probablemente no creado.")
                                
                                // ✅ Thread-safe check del estado de registro
                                let registrationState = self?.authQueue.sync { self?._registrationState } ?? .idle
                                
                                if registrationState == .registering || self?.isRegistering == true {
                                    print("🚀 Aún en registro - asumir que documento se creará")
                                    completion(true, nil, false) // Asumir activo temporalmente
                                } else {
                                    print("❌ No en registro - forzar logout")
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
            print("🚨 Forzando logout por error crítico")
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
            print("🧹 AuthService: Limpiando estado de registro")
            
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
            print("🚫 Verificando suspensión para usuario: \(userId)")
            
            db.collection("users").document(userId).getDocument { snapshot, error in
                guard let data = snapshot?.data() else {
                    print("📄 No se pudo obtener datos del usuario para verificar suspensión")
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
                            print("⏰ Suspensión expirada - reactivando automáticamente")
                            self.db.collection("users").document(userId).updateData([
                                "isSuspended": false,
                                "suspendedUntil": FieldValue.delete(),
                                "suspensionReason": FieldValue.delete()
                            ]) { error in
                                if let error = error {
                                    print("❌ Error al reactivar usuario: \(error.localizedDescription)")
                                } else {
                                    print("✅ Usuario reactivado automáticamente")
                                }
                            }
                            completion(false, nil, nil)
                            return
                        } else {
                            // Suspensión aún válida
                            let reason = data["suspensionReason"] as? String
                            print("🚫 Usuario suspendido hasta: \(expirationDate)")
                            completion(true, reason, expirationDate)
                            return
                        }
                    } else {
                        // Suspensión sin fecha de expiración (permanente)
                        let reason = data["suspensionReason"] as? String
                        print("🚫 Usuario suspendido permanentemente")
                        completion(true, reason, nil)
                        return
                    }
                }
                
                print("✅ Usuario no suspendido")
                completion(false, nil, nil)
            }
        }
        
        // ✅ MODIFICAR: Completar registro con estado thread-safe
        func completeRegistration() {
            print("🎉 Completando proceso de registro...")
            
            // ✅ THREAD-SAFE: Cambiar a estado de finalización
            authQueue.async {
                self._registrationState = .completing
                self._isAuthProcessingEnabled = true
            }
            
            DispatchQueue.main.async {
                print("✅ Estado cambiado a completing - re-evaluando...")
                
                // ✅ Forzar re-evaluación si hay usuario
                if let user = self.currentFirebaseUser {
                    print("🔄 Iniciando proceso de finalización para usuario: \(user.uid)")
                    self.handleRegistrationCompletion(user: user)
                } else {
                    print("⚠️ No hay Firebase user para completar registro")
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
        
        print("🚀 AuthService.register: Iniciando registro para usuario: \(username)")
        
        // ✅ CRÍTICO: Establecer flags SÍNCRONAMENTE antes de cualquier operación
        authQueue.sync {
            self._registrationState = .registering
            self._isAuthProcessingEnabled = false
        }
        
        // ✅ CORREGIDO: usar async en lugar de sync para evitar deadlock
        DispatchQueue.main.async {
            self.isRegistering = true
            
            print("🔧 Flags establecidos:")
            print("   - _registrationState: \(self.authQueue.sync { self._registrationState })")
            print("   - _isAuthProcessingEnabled: \(self.authQueue.sync { self._isAuthProcessingEnabled })")
            print("   - isRegistering: \(self.isRegistering)")
        }
        
        // ✅ Pequeño delay para asegurar que los flags se propaguen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Verificar disponibilidad de username
            self.db.collection("usernames").document(username.lowercased()).getDocument { document, error in
                if let error = error {
                    print("❌ Error al verificar username: \(error.localizedDescription)")
                    self.clearRegistrationState()
                    completion(.failure(error))
                    return
                }
                if document?.exists ?? false {
                    print("❌ Nombre de usuario \(username) no disponible")
                    self.clearRegistrationState()
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nombre de usuario no disponible."])))
                    return
                }
                
                print("🎯 Username disponible - creando usuario en Firebase Auth")
                
                // ✅ Crear usuario en Firebase Auth
                Auth.auth().createUser(withEmail: email, password: password) { result, error in
                    if let error = error {
                        print("❌ Error al crear usuario en Firebase Auth: \(error.localizedDescription)")
                        self.clearRegistrationState()
                        completion(.failure(self.mapAuthError(error)))
                        return
                    }
                    guard let userId = result?.user.uid else {
                        print("❌ No se pudo obtener el ID del usuario")
                        self.clearRegistrationState()
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener el ID del usuario."])))
                        return
                    }
                    
                    print("✅ Usuario creado en Firebase Auth: \(userId)")
                    
                    // Enviar verificación de email
                    result?.user.sendEmailVerification { error in
                        if let error = error {
                            print("⚠️ Error al enviar verificación de email: \(error.localizedDescription)")
                        } else {
                            print("📧 Correo de verificación enviado a \(email)")
                        }
                    }
                    
                    // ✅ Upload imagen con mejor control de tiempo
                    self.uploadProfileImageIfNeeded(image: profileImage, userId: userId) { profileImagePath in
                        print("🔄 Creando usuario en Firestore...")
                        
                        // Usar FirestoreService para crear el usuario
                        self.firestoreService.createUser(
                            userId: userId,
                            username: username,
                            email: email,
                            interests: interests,
                            profileImagePath: profileImagePath
                        ) { error in
                            if let error = error {
                                print("❌ Error al crear usuario en Firestore: \(error.localizedDescription)")
                                
                                // Si falla Firestore, eliminar usuario de Auth y limpiar estado
                                result?.user.delete { _ in
                                    print("🗑️ Usuario eliminado de Auth debido a error en Firestore")
                                }
                                
                                self.clearRegistrationState()
                                completion(.failure(error))
                            } else {
                                print("✅ Usuario creado exitosamente en Firestore")
                                print("🎉 AuthService.register: Registro completo")
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
                print("📸 No hay imagen para subir")
                completion(nil)
                return
            }
            
            print("📸 Iniciando subida de imagen para usuario: \(userId)")
            
            let fileName = "\(UUID().uuidString)_\(userId)"
            let imageRef = storage.child("images/\(fileName).jpg")
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Error al convertir imagen a datos")
                completion(nil)
                return
            }
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            imageRef.putData(imageData, metadata: metadata) { _, error in
                if let error = error {
                    print("⚠️ Error al subir imagen: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                imageRef.downloadURL { url, error in
                    if let error = error {
                        print("⚠️ Error al obtener URL de imagen: \(error.localizedDescription)")
                        completion(nil)
                    } else if let url = url {
                        print("📸 Imagen subida exitosamente: \(url.absoluteString)")
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
            
            print("🔄 Reactivando cuenta para usuario: \(userId)")
            
            // ✅ Mostrar estado de verificación
            DispatchQueue.main.async {
                self.isVerifyingAccount = true
                self.authState = .verifyingAccount
            }
            
            let accountService = AccountManagementService()
            accountService.reactivateAccount(userId: userId) { [weak self] result in
                switch result {
                case .success:
                    print("✅ Cuenta reactivada exitosamente en Firestore")
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
                                
                                print("✅ Estado actualizado - cuenta reactivada completamente")
                            } else {
                                // Algo salió mal, mantener estado desactivado
                                self?.authState = .deactivated
                                print("⚠️ Error: cuenta no se reactivó correctamente")
                            }
                        }
                    }
                    completion(.success(()))
                case .failure(let error):
                    print("❌ Error al reactivar cuenta: \(error.localizedDescription)")
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
                print("⚠️ No hay Firebase user para refrescar")
                return
            }
            
            print("🔄 Refrescando currentUser para: \(userId)")
            
            firestoreService.fetchUser(userId: userId) { [weak self] result in
                switch result {
                case .success(let appUser):
                    DispatchQueue.main.async {
                        self?.currentUser = appUser
                        print("✅ CurrentUser actualizado: \(appUser.username)")
                        print("   - isPlusSubscriber: \(appUser.isPlusSubscriber)")
                    }
                case .failure(let error):
                    print("❌ Error al actualizar currentUser: \(error.localizedDescription)")
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
                    print("❌ Error al actualizar campo \(field): \(error?.localizedDescription ?? "unknown")")
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
                    print("Error al verificar disponibilidad de username: \(error.localizedDescription)")
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
            print("🚪 Logout iniciado...")
            
            // ✅ Detener listener antes de cerrar sesión
            stopSuspensionListener()
            
            do {
                try Auth.auth().signOut()
                print("🔓 Firebase signOut exitoso")
                
                // ✅ Forzar limpieza inmediata del estado
                DispatchQueue.main.async {
                    print("🧹 Limpiando estado local forzadamente...")
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
                    
                    print("✅ Estado local limpiado")
                }
                
            } catch {
                print("❌ Error al cerrar sesión: \(error.localizedDescription)")
                
                // ✅ Incluso si Firebase falla, limpiar estado local
                DispatchQueue.main.async {
                    print("🧹 Limpiando estado local por error...")
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
                    
                    print("✅ Estado limpiado después de error")
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
