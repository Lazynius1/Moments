import Foundation
import CryptoKit
import Security
import FirebaseAuth
import FirebaseFirestore

// MARK: - EncryptionService con Claves Compartidas ULTRA RÁPIDO
class EncryptionService: ObservableObject {
    static let shared = EncryptionService()
    
    // MARK: - Constants
    private let keyChainService = "com.Momentsapp.encryption"
    private let masterKeyTag = "master_encryption_key"
    private let userKeysPrefix = "user_key_"
    private let conversationKeysPrefix = "conversation_key_"
    private let db = Firestore.firestore()
    
    // MARK: - Published Properties
    @Published var isEncryptionEnabled: Bool = true
    @Published var encryptionStatus: EncryptionStatus = .ready
    
    // MARK: - Private Properties
    private var masterKey: SymmetricKey?
    private var userKeys: [String: SymmetricKey] = [:] // userId: key
    private var conversationKeys: [String: SymmetricKey] = [:] // conversationId: key
    
    // MARK: - Initialization
    private init() {
        setupEncryption()
    }
    
    // MARK: - Setup
    private func setupEncryption() {
        encryptionStatus = .initializing
        
        do {
            masterKey = try getOrCreateMasterKey()
            print("🔐 EncryptionService: Master key configured")
            encryptionStatus = .ready
        } catch {
            print("❌ EncryptionService: Error setting up encryption: \(error)")
            encryptionStatus = .error(error.localizedDescription)
            isEncryptionEnabled = false
        }
    }
    
    // MARK: - Master Key Management
    private func getOrCreateMasterKey() throws -> SymmetricKey {
        // Try to retrieve existing key
        if let existingKey = try? retrieveKeyFromKeychain(tag: masterKeyTag) {
            return existingKey
        }
        
        // Create new master key
        let newKey = SymmetricKey(size: .bits256)
        try storeKeyInKeychain(key: newKey, tag: masterKeyTag)
        
        print("🔐 New master key created and stored in Keychain")
        return newKey
    }
    
    // MARK: - User-Specific Keys
    private func getUserKey(for userId: String) throws -> SymmetricKey {
        if let existingKey = userKeys[userId] {
            return existingKey
        }
        
        let keyTag = userKeysPrefix + userId
        
        // Try to retrieve from keychain
        if let storedKey = try? retrieveKeyFromKeychain(tag: keyTag) {
            userKeys[userId] = storedKey
            return storedKey
        }
        
        // Create new user key
        let newKey = SymmetricKey(size: .bits256)
        try storeKeyInKeychain(key: newKey, tag: keyTag)
        userKeys[userId] = newKey
        
        print("🔐 New user key created for: \(userId)")
        return newKey
    }
    
    // MARK: - 🚀 CONVERSACIÓN KEYS INSTANTÁNEAS (Como WhatsApp)
    private func getConversationKey(for conversationId: String) throws -> SymmetricKey {
        // ✅ SOLO CACHÉ - NUNCA BLOQUEAR
        if let existingKey = conversationKeys[conversationId] {
            return existingKey
        }
        
        // ✅ KEYCHAIN RÁPIDO
        let keyTag = conversationKeysPrefix + conversationId
        if let storedKey = try? retrieveKeyFromKeychain(tag: keyTag) {
            conversationKeys[conversationId] = storedKey
            return storedKey
        }
        
        // ✅ ÚLTIMO RECURSO: Crear clave temporal y subir en background
        print("⚡ Creating temporary key for instant messaging")
        let tempKey = SymmetricKey(size: .bits256)
        conversationKeys[conversationId] = tempKey
        try? storeKeyInKeychain(key: tempKey, tag: keyTag)
        
        // ✅ SUBIR EN BACKGROUND (no bloquear)
        uploadKeyInBackground(conversationId: conversationId, key: tempKey)
        
        return tempKey
    }
    
    // ✅ NUEVA FUNCIÓN: Subir clave en background
    private func uploadKeyInBackground(conversationId: String, key: SymmetricKey) {
        DispatchQueue.global(qos: .background).async {
            let keyData = key.withUnsafeBytes { Data($0) }
            let keyDataString = keyData.base64EncodedString()
            
            self.db.collection("conversations")
                .document(conversationId)
                .updateData([
                    "encryptionKey": keyDataString,
                    "encryptionKeyCreatedAt": FieldValue.serverTimestamp(),
                    "encryptionVersion": "1.0"
                ]) { error in
                    if let error = error {
                        print("❌ Background key upload failed: \(error)")
                    } else {
                        print("✅ Background key uploaded for: \(conversationId)")
                    }
                }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Precargar claves al abrir el chat
    func preloadConversationKey(for conversationId: String) {
        guard conversationKeys[conversationId] == nil else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.db.collection("conversations")
                .document(conversationId)
                .getDocument { snapshot, error in
                    guard let data = snapshot?.data(),
                          let keyDataString = data["encryptionKey"] as? String,
                          let keyData = Data(base64Encoded: keyDataString) else {
                        return
                    }
                    
                    let sharedKey = SymmetricKey(data: keyData)
                    
                    DispatchQueue.main.async {
                        self.conversationKeys[conversationId] = sharedKey
                        let keyTag = self.conversationKeysPrefix + conversationId
                        try? self.storeKeyInKeychain(key: sharedKey, tag: keyTag)
                        print("✅ Preloaded key for: \(conversationId)")
                    }
                }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Establecer clave de conversación directamente
    func setConversationKey(_ key: SymmetricKey, for conversationId: String) {
        conversationKeys[conversationId] = key
        let keyTag = conversationKeysPrefix + conversationId
        try? storeKeyInKeychain(key: key, tag: keyTag)
        print("✅ Directly set conversation key for: \(conversationId)")
    }
    
    // MARK: - 🔄 SHARED KEY MANAGEMENT (Legacy - para compatibilidad)
    private func fetchSharedConversationKey(conversationId: String) throws -> SymmetricKey? {
        let semaphore = DispatchSemaphore(value: 0)
        var fetchedKey: SymmetricKey?
        var fetchError: Error?
        
        db.collection("conversations")
            .document(conversationId)
            .getDocument { snapshot, error in
                defer { semaphore.signal() }
                
                if let error = error {
                    fetchError = error
                    return
                }
                
                guard let data = snapshot?.data(),
                      let keyDataString = data["encryptionKey"] as? String,
                      let keyData = Data(base64Encoded: keyDataString) else {
                    print("🔍 No shared encryption key found in Firestore")
                    return
                }
                
                fetchedKey = SymmetricKey(data: keyData)
                print("✅ Successfully fetched shared encryption key from Firestore")
            }
        
        _ = semaphore.wait(timeout: .now() + 2.0) // Reduced timeout
        
        if let error = fetchError {
            throw error
        }
        
        return fetchedKey
    }
    
    private func uploadSharedConversationKey(conversationId: String, key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let keyDataString = keyData.base64EncodedString()
        
        db.collection("conversations")
            .document(conversationId)
            .updateData([
                "encryptionKey": keyDataString,
                "encryptionKeyCreatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ Error uploading shared encryption key: \(error.localizedDescription)")
                } else {
                    print("✅ Shared encryption key uploaded to Firestore: \(conversationId)")
                }
            }
    }
    
    // MARK: - ⚡ ASYNC KEY FETCHING (RECOMENDADO)
    func fetchConversationKeyAsync(for conversationId: String, completion: @escaping (Result<SymmetricKey, Error>) -> Void) {
        // ✅ Para llamadas asíncronas que no bloqueen la UI
        
        // 1. Verificar caché
        if let existingKey = conversationKeys[conversationId] {
            completion(.success(existingKey))
            return
        }
        
        // 2. Verificar Keychain
        let keyTag = conversationKeysPrefix + conversationId
        if let storedKey = try? retrieveKeyFromKeychain(tag: keyTag) {
            conversationKeys[conversationId] = storedKey
            completion(.success(storedKey))
            return
        }
        
        // 3. Fetch desde Firestore
        db.collection("conversations")
            .document(conversationId)
            .getDocument { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Obtener clave compartida o crear nueva
                if let data = snapshot?.data(),
                   let keyDataString = data["encryptionKey"] as? String,
                   let keyData = Data(base64Encoded: keyDataString) {
                    
                    // Usar clave existente
                    let sharedKey = SymmetricKey(data: keyData)
                    self.conversationKeys[conversationId] = sharedKey
                    try? self.storeKeyInKeychain(key: sharedKey, tag: keyTag)
                    completion(.success(sharedKey))
                    
                } else {
                    // Crear nueva clave compartida
                    let newKey = SymmetricKey(size: .bits256)
                    self.conversationKeys[conversationId] = newKey
                    try? self.storeKeyInKeychain(key: newKey, tag: keyTag)
                    
                    // Subir a Firestore
                    self.uploadSharedConversationKey(conversationId: conversationId, key: newKey)
                    completion(.success(newKey))
                }
            }
    }
    
    // MARK: - Public Encryption Methods (UNCHANGED)
    
    /// Encrypt Gemini conversation data (user-specific)
    func encryptGeminiData(_ text: String, for userId: String) -> String? {
        guard isEncryptionEnabled else { return text }
        
        do {
            let key = try getUserKey(for: userId)
            return try encrypt(text: text, with: key)
        } catch {
            print("❌ Error encrypting Gemini data: \(error)")
            return text // Fallback to plain text
        }
    }
    
    /// Decrypt Gemini conversation data (user-specific)
    func decryptGeminiData(_ encryptedText: String, for userId: String) -> String? {
        guard isEncryptionEnabled else { return encryptedText }
        
        do {
            let key = try getUserKey(for: userId)
            return try decrypt(encryptedText: encryptedText, with: key)
        } catch {
            print("❌ Error decrypting Gemini data: \(error)")
            return encryptedText // Fallback to encrypted text
        }
    }
    
    /// Encrypt chat message data (conversation-specific)
    func encryptChatMessage(_ text: String, for conversationId: String) -> String? {
        guard isEncryptionEnabled else { return text }
        
        do {
            let key = try getConversationKey(for: conversationId) // ✅ USA CLAVE COMPARTIDA
            return try encrypt(text: text, with: key)
        } catch {
            print("❌ Error encrypting chat message: \(error)")
            return text // Fallback to plain text
        }
    }
    
    /// Decrypt chat message data (conversation-specific)
    func decryptChatMessage(_ encryptedText: String, for conversationId: String) -> String? {
        guard isEncryptionEnabled else { return encryptedText }
        
        do {
            let key = try getConversationKey(for: conversationId) // ✅ USA CLAVE COMPARTIDA
            return try decrypt(encryptedText: encryptedText, with: key)
        } catch {
            print("❌ Error decrypting chat message: \(error)")
            return encryptedText // Fallback to encrypted text
        }
    }
    
    /// Encrypt user profile data (user-specific)
    func encryptUserData(_ text: String, for userId: String) -> String? {
        guard isEncryptionEnabled else { return text }
        
        do {
            let key = try getUserKey(for: userId)
            return try encrypt(text: text, with: key)
        } catch {
            print("❌ Error encrypting user data: \(error)")
            return text // Fallback to plain text
        }
    }
    
    /// Decrypt user profile data (user-specific)
    func decryptUserData(_ encryptedText: String, for userId: String) -> String? {
        guard isEncryptionEnabled else { return encryptedText }
        
        do {
            let key = try getUserKey(for: userId)
            return try decrypt(encryptedText: encryptedText, with: key)
        } catch {
            print("❌ Error decrypting user data: \(error)")
            return encryptedText // Fallback to encrypted text
        }
    }
    
    // MARK: - Core Encryption/Decryption (UNCHANGED)
    private func encrypt(text: String, with key: SymmetricKey) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }
        
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined?.base64EncodedString() ?? ""
    }
    
    private func decrypt(encryptedText: String, with key: SymmetricKey) throws -> String {
        guard let encryptedData = Data(base64Encoded: encryptedText) else {
            throw EncryptionError.invalidInput
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        
        return decryptedString
    }
    
    // MARK: - Keychain Operations (UNCHANGED)
    private func storeKeyInKeychain(key: SymmetricKey, tag: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: tag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to store key: \(status)")
        }
    }
    
    private func retrieveKeyFromKeychain(tag: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to retrieve key: \(status)")
        }
        
        guard let keyData = result as? Data else {
            throw EncryptionError.keychainError("Invalid key data")
        }
        
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Key Management (UPDATED)
    func deleteUserKeys(for userId: String) {
        userKeys.removeValue(forKey: userId)
        
        let keyTag = userKeysPrefix + userId
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: keyTag
        ]
        
        SecItemDelete(query as CFDictionary)
        print("🗑️ User keys deleted for: \(userId)")
    }
    
    func deleteConversationKeys(for conversationId: String) {
        conversationKeys.removeValue(forKey: conversationId)
        
        let keyTag = conversationKeysPrefix + conversationId
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService,
            kSecAttrAccount as String: keyTag
        ]
        
        SecItemDelete(query as CFDictionary)
        print("🗑️ Conversation keys deleted for: \(conversationId)")
    }
    
    func deleteAllKeys() {
        userKeys.removeAll()
        conversationKeys.removeAll()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyChainService
        ]
        
        SecItemDelete(query as CFDictionary)
        print("🗑️ All encryption keys deleted")
    }
    
    // MARK: - Settings (UNCHANGED)
    func toggleEncryption(_ enabled: Bool) {
        isEncryptionEnabled = enabled
        print("🔐 Encryption \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Utility Methods (UPDATED)
    func getEncryptionInfo() -> EncryptionInfo {
        return EncryptionInfo(
            isEnabled: isEncryptionEnabled,
            status: encryptionStatus,
            userKeysCount: userKeys.count,
            conversationKeysCount: conversationKeys.count,
            hasValidMasterKey: masterKey != nil
        )
    }
    
    // ✅ NUEVA FUNCIÓN: Precargar claves de conversaciones activas
    func preloadConversationKeys(for conversationIds: [String]) {
        print("🔄 Preloading conversation keys for \(conversationIds.count) conversations")
        
        for conversationId in conversationIds {
            preloadConversationKey(for: conversationId)
        }
    }
}

// MARK: - Supporting Types (UNCHANGED)
enum EncryptionStatus: Equatable {
    case ready
    case initializing
    case error(String)
    
    var description: String {
        switch self {
        case .ready:
            return "Listo"
        case .initializing:
            return "Inicializando..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

enum EncryptionError: LocalizedError {
    case invalidInput
    case encryptionFailed
    case decryptionFailed
    case keychainError(String)
    case keyNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Datos de entrada inválidos"
        case .encryptionFailed:
            return "Error en la encriptación"
        case .decryptionFailed:
            return "Error en la desencriptación"
        case .keychainError(let message):
            return "Error en Keychain: \(message)"
        case .keyNotFound:
            return "Clave no encontrada"
        }
    }
}

struct EncryptionInfo {
    let isEnabled: Bool
    let status: EncryptionStatus
    let userKeysCount: Int
    let conversationKeysCount: Int
    let hasValidMasterKey: Bool
    
    var statusDescription: String {
        if !isEnabled {
            return "Encriptación deshabilitada"
        }
        
        switch status {
        case .ready:
            return "✅ Activa y funcionando"
        case .initializing:
            return "⏳ Inicializando..."
        case .error(let message):
            return "❌ Error: \(message)"
        }
    }
}
