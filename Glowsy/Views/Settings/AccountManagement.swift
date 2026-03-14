import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Account Management Section para SettingsView
struct AccountManagementSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @State private var showDeactivateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteVerification = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        Section(NSLocalizedString("accountManagement.section.title", comment: "Account management section")) {
            // Deactivate account
            SettingsRow(
                icon: "pause.circle",
                title: NSLocalizedString("accountManagement.deactivate.title", comment: "Deactivate account title"),
                subtitle: NSLocalizedString("accountManagement.deactivate.subtitle", comment: "Deactivate account subtitle"),
                action: {
                    showDeactivateConfirmation = true
                },
                isDestructive: false
            )
            
            // Delete account
            SettingsRow(
                icon: "trash.circle",
                title: NSLocalizedString("accountManagement.delete.title", comment: "Delete account title"),
                subtitle: NSLocalizedString("accountManagement.delete.subtitle", comment: "Delete account subtitle"),
                action: {
                    showDeleteConfirmation = true
                },
                isDestructive: true
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
        
        // Deactivate confirmation
        .alert(NSLocalizedString("accountManagement.deactivate.title", comment: "Deactivate account"), isPresented: $showDeactivateConfirmation) {
            Button(NSLocalizedString("accountManagement.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("accountManagement.deactivate", comment: "Deactivate"), role: .destructive) {
                deactivateAccount()
            }
        } message: {
            Text(NSLocalizedString("accountManagement.deactivate.message", comment: "Deactivate account message"))
        }
        
        // Delete confirmation
        .alert(NSLocalizedString("accountManagement.delete.title", comment: "Delete account permanently"), isPresented: $showDeleteConfirmation) {
            Button(NSLocalizedString("accountManagement.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("accountManagement.continue", comment: "Continue"), role: .destructive) {
                showDeleteVerification = true
            }
        } message: {
            Text(NSLocalizedString("accountManagement.delete.message", comment: "Delete account message"))
        }
        
        // Delete verification sheet
        .sheet(isPresented: $showDeleteVerification) {
            DeleteAccountVerificationView(
                isProcessing: $isProcessing,
                onConfirm: { password in
                    deleteAccount(password: password)
                },
                onCancel: {
                    showDeleteVerification = false
                }
            )
        }
        
        // Error alert
        .alert(NSLocalizedString("accountManagement.error.title", comment: "Error"), isPresented: $showError) {
            Button(NSLocalizedString("accountManagement.ok", comment: "OK")) {}
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - Account Actions
    
    private func deactivateAccount() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isProcessing = true
        
        let accountService = AccountManagementService()
        accountService.deactivateAccount(userId: userId) { result in
            DispatchQueue.main.async {
                isProcessing = false
                
                switch result {
                case .success:
                    // Logout after deactivation
                    authService.logout()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func deleteAccount(password: String) {
        guard let user = Auth.auth().currentUser else {
            DispatchQueue.main.async {
                isProcessing = false
                errorMessage = NSLocalizedString("accountManagement.userNotFound", comment: "User not found error")
                showError = true
            }
            return
        }
        
        isProcessing = true
        
        let accountService = AccountManagementService()
        
        // Intentar eliminación normal primero
        accountService.deleteAccount(user: user, password: password) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.showDeleteVerification = false
                }
            case .failure(let error):
                
                // Si falla, intentar eliminación rápida
                accountService.deleteAccountFast(user: user, password: password) { fastResult in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.showDeleteVerification = false
                        
                        switch fastResult {
                        case .success:
                            // Account deleted successfully
                            break
                        case .failure(let fastError):
                            self.errorMessage = String(format: NSLocalizedString("accountManagement.error.delete", comment: "Error deleting account"), fastError.localizedDescription)
                            self.showError = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Delete Account Verification View
struct DeleteAccountVerificationView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isProcessing: Bool
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    
    @State private var password: String = ""
    @State private var confirmText: String = ""
    @State private var agreeToDelete: Bool = false
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isConfirmFocused: Bool
    
    private let requiredText = NSLocalizedString("accountManagement.requiredText", comment: "Required text for deletion")
    
    var isFormValid: Bool {
        !password.isEmpty &&
        confirmText == requiredText &&
        agreeToDelete
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if isProcessing {
                    // Processing overlay
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("accountManagement.deleting")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Warning header
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.red)
                                
                                VStack(spacing: 8) {
                                    Text("accountManagement.permanentDeletion")
                                        .font(.custom("Poppins-Bold", size: 24))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("accountManagement.irreversible")
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 20)
                            
                            // What will be deleted
                            VStack(alignment: .leading, spacing: 16) {
                                Text("accountManagement.willBeDeleted")
                                    .font(.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    DeletedDataRow(icon: "person.circle", text: NSLocalizedString("accountManagement.profileInfo", comment: "Profile info text"))
                                    DeletedDataRow(icon: "photo.on.rectangle", text: NSLocalizedString("accountManagement.storiesMoments", comment: "Stories and moments text"))
                                    DeletedDataRow(icon: "message.circle", text: NSLocalizedString("accountManagement.conversations", comment: "Conversations text"))
                                    DeletedDataRow(icon: "person.2.circle", text: NSLocalizedString("accountManagement.connections", comment: "Connections text"))
                                    DeletedDataRow(icon: "bell.circle", text: NSLocalizedString("accountManagement.notifications", comment: "Notifications text"))
                                    DeletedDataRow(icon: "folder.circle", text: NSLocalizedString("accountManagement.savedContent", comment: "Saved content text"))
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Verification form
                            VStack(spacing: 20) {
                                // Password verification
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("accountManagement.confirmPassword")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    SecureField(NSLocalizedString("accountManagement.currentPassword", comment: "Current password placeholder"), text: $password)
                                        .focused($isPasswordFocused)
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.gray.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                }
                                
                                // Text confirmation
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("accountManagement.writeExactly")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(requiredText)
                                        .font(.custom("Poppins-Bold", size: 18))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.red.opacity(0.1))
                                        )
                                    
                                    TextField(NSLocalizedString("accountManagement.writeHere", comment: "Write here placeholder"), text: $confirmText)
                                        .focused($isConfirmFocused)
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.gray.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(
                                                            confirmText == requiredText ? Color.green : Color.gray.opacity(0.3),
                                                            lineWidth: 1
                                                        )
                                                )
                                        )
                                }
                                
                                // Final agreement
                                HStack(alignment: .top, spacing: 12) {
                                    Button(action: {
                                        agreeToDelete.toggle()
                                    }) {
                                        Image(systemName: agreeToDelete ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 20))
                                            .foregroundColor(agreeToDelete ? Color(hex: "4F46E5") : .gray)
                                    }
                                    
                                    Text("accountManagement.understandIrreversible")
                                        .font(.custom("Poppins-Regular", size: 14))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .padding(.horizontal, 20)
                            
                            // Action buttons
                            VStack(spacing: 16) {
                                Button(action: {
                                    onConfirm(password)
                                }) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text("accountManagement.deleteAccountPermanently")
                                            .font(.custom("Poppins-Bold", size: 16))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isFormValid ? Color.red : Color.gray)
                                    )
                                }
                                .disabled(!isFormValid)
                                
                                Button(action: onCancel) {
                                    Text(NSLocalizedString("accountManagement.cancel", comment: "Cancel button"))
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(Color(hex: "4F46E5"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(hex: "4F46E5"), lineWidth: 2)
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("accountManagement.deleteAccount.title", comment: "Delete Account"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if !isProcessing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("accountManagement.cancel", comment: "Cancel")) {
                            onCancel()
                        }
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(Color(hex: "4F46E5"))
                    }
                }
            }
        }
    }
}

// MARK: - Deleted Data Row
struct DeletedDataRow: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.red)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
        }
    }
}

// MARK: - Account Management Service
class AccountManagementService {
    private let db = Firestore.firestore()
    
    // MARK: - Deactivate Account
    func deactivateAccount(userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let deactivationData: [String: Any] = [
            "isActive": false,
            "deactivatedAt": Timestamp(date: Date()),
            "deactivatedBy": "user"
        ]
        
        db.collection("users").document(userId).updateData(deactivationData) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Delete Account
    func deleteAccount(user: User, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        
        // Re-authenticate user first
        guard let email = user.email else {
            let error = NSError(domain: "AccountDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("accountManagement.error.noEmail", comment: "No email error")])
            completion(.failure(error))
            return
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Proceed with account deletion
            self?.performAccountDeletion(user: user, completion: completion)
        }
    }
    
    private func performAccountDeletion(user: User, completion: @escaping (Result<Void, Error>) -> Void) {
        let userId = user.uid
        
        // Primero obtener los datos del usuario para eliminar también el username
        let userRef = db.collection("users").document(userId)
        
        userRef.getDocument { [weak self] document, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let document = document, document.exists,
                  let userData = document.data(),
                  let username = userData["username"] as? String else {
                self?.deleteUserDocumentAndAuth(user: user, completion: completion)
                return
            }
            
            
            // Crear batch para eliminar tanto el usuario como el username
            let batch = self?.db.batch()
            
            // Eliminar documento del usuario
            batch?.deleteDocument(userRef)
            
            // Eliminar documento del username
            let usernameRef = self?.db.collection("usernames").document(username.lowercased())
            if let usernameRef = usernameRef {
                batch?.deleteDocument(usernameRef)
            }
            
            // Ejecutar batch
            batch?.commit { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                
                // Limpiar datos relacionados en background
                self?.cleanupUserData(userId: userId, username: username) {
                    
                    // Ahora eliminar la cuenta de Firebase Auth
                    user.delete { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
                }
            }
        }
    }
    
    private func deleteUserDocumentAndAuth(user: User, completion: @escaping (Result<Void, Error>) -> Void) {
        let userId = user.uid
        let userRef = db.collection("users").document(userId)
        
        userRef.delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            
            // Now delete Firebase Auth account
            user.delete { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Versión alternativa más agresiva si la anterior falla
    func deleteAccountFast(user: User, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        
        guard let email = user.email else {
            let error = NSError(domain: "AccountDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("accountManagement.error.noEmail", comment: "No email error")])
            completion(.failure(error))
            return
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            
            // Eliminar cuenta de Auth inmediatamente sin limpiar Firestore
            user.delete { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Reactivate Account
    func reactivateAccount(userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let reactivationData: [String: Any] = [
            "isActive": true,
            "reactivatedAt": Timestamp(date: Date()),
            "deactivatedAt": FieldValue.delete(),
            "deactivatedBy": FieldValue.delete()
        ]
        
        db.collection("users").document(userId).updateData(reactivationData) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Limpieza Completa de Datos del Usuario
    private func cleanupUserData(userId: String, username: String, completion: @escaping () -> Void) {
        
        // Ejecutar limpieza en background para no bloquear la UI
        DispatchQueue.global(qos: .background).async {
            let group = DispatchGroup()
            
            // 1. Limpiar conversaciones
            group.enter()
            self.cleanupConversations(userId: userId) {
                group.leave()
            }
            
            // 2. Limpiar seguimientos
            group.enter()
            self.cleanupFollows(userId: userId) {
                group.leave()
            }
            
            // 3. Limpiar contenido (momentos, historias)
            group.enter()
            self.cleanupContent(userId: userId) {
                group.leave()
            }
            
            // 4. Limpiar notificaciones
            group.enter()
            self.cleanupNotifications(userId: userId) {
                group.leave()
            }
            
            // 5. Limpiar menciones en otros documentos
            group.enter()
            self.cleanupMentions(userId: userId, username: username) {
                group.leave()
            }
            
            // 6. Limpiar customaudience
            group.enter()
            self.cleanupCustomAudience(userId: userId) {
                group.leave()
            }
            
            // 7. Limpiar dailystats
            group.enter()
            self.cleanupDailyStats(userId: userId) {
                group.leave()
            }
            
            // 8. Limpiar loginactivity
            group.enter()
            self.cleanupLoginActivity(userId: userId) {
                group.leave()
            }
            
            // 9. Limpiar novamemory
            group.enter()
            self.cleanupNovaMemory(userId: userId) {
                group.leave()
            }
            
            // 10. Limpiar visitorsummaries
            group.enter()
            self.cleanupVisitorSummaries(userId: userId) {
                group.leave()
            }
            
            // 11. Limpiar visits
            group.enter()
            self.cleanupVisits(userId: userId) {
                group.leave()
            }
            
            group.notify(queue: .main) {
                completion()
            }
        }
    }
    
    private func cleanupConversations(userId: String, completion: @escaping () -> Void) {
        
        // Obtener conversaciones donde participa el usuario
        db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion()
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion()
                    return
                }
                
                let batch = self.db.batch()
                var conversationCount = 0
                
                for document in documents {
                    batch.deleteDocument(document.reference)
                    conversationCount += 1
                }
                
                batch.commit { error in
                    if let error = error {
                    } else {
                    }
                    completion()
                }
            }
    }
    
    private func cleanupFollows(userId: String, completion: @escaping () -> Void) {
        
        let group = DispatchGroup()
        var totalCleaned = 0
        
        // Limpiar following del usuario eliminado
        group.enter()
        db.collection("users").document(userId).collection("following").getDocuments { snapshot, error in
            if let documents = snapshot?.documents {
                let batch = self.db.batch()
                for document in documents {
                    batch.deleteDocument(document.reference)
                    totalCleaned += 1
                }
                batch.commit { _ in }
            }
            group.leave()
        }
        
        // Limpiar followers de otros usuarios que seguían al eliminado
        group.enter()
        db.collection("users").getDocuments { snapshot, error in
            if let documents = snapshot?.documents {
                let batch = self.db.batch()
                for userDoc in documents {
                    let followerRef = userDoc.reference.collection("followers").document(userId)
                    batch.deleteDocument(followerRef)
                    totalCleaned += 1
                }
                batch.commit { _ in }
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion()
        }
    }
    
    private func cleanupContent(userId: String, completion: @escaping () -> Void) {
        
        let group = DispatchGroup()
        var totalCleaned = 0
        
        // Limpiar momentos
        group.enter()
        db.collection("users").document(userId).collection("moments").getDocuments { snapshot, error in
            if let documents = snapshot?.documents {
                let batch = self.db.batch()
                for document in documents {
                    batch.deleteDocument(document.reference)
                    totalCleaned += 1
                }
                batch.commit { _ in }
            }
            group.leave()
        }
        
        // Limpiar historias
        group.enter()
        db.collection("users").document(userId).collection("stories").getDocuments { snapshot, error in
            if let documents = snapshot?.documents {
                let batch = self.db.batch()
                for document in documents {
                    batch.deleteDocument(document.reference)
                    totalCleaned += 1
                }
                batch.commit { _ in }
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion()
        }
    }
    
    private func cleanupNotifications(userId: String, completion: @escaping () -> Void) {
        
        // Limpiar notificaciones del usuario
        db.collection("users").document(userId).collection("notifications").getDocuments { snapshot, error in
            if let documents = snapshot?.documents {
                let batch = self.db.batch()
                for document in documents {
                    batch.deleteDocument(document.reference)
                }
                batch.commit { _ in }
            }
            completion()
        }
    }
    
    private func cleanupMentions(userId: String, username: String, completion: @escaping () -> Void) {
        
        // Buscar comentarios que mencionen al usuario eliminado
        db.collectionGroup("comments")
            .whereField("authorId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
    
    // MARK: - Limpieza de Colecciones Adicionales
    
    private func cleanupCustomAudience(userId: String, completion: @escaping () -> Void) {
        
        db.collection("customaudience")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
    
    private func cleanupDailyStats(userId: String, completion: @escaping () -> Void) {
        
        db.collection("dailystats")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
    
    private func cleanupLoginActivity(userId: String, completion: @escaping () -> Void) {
        db.collection("users")
            .document(userId)
            .collection("loginActivity")
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
    
    private func cleanupNovaMemory(userId: String, completion: @escaping () -> Void) {
        
        db.collection("novamemory")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
    
    private func cleanupVisitorSummaries(userId: String, completion: @escaping () -> Void) {
        
        db.collection("visitorsummaries")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
    
    private func cleanupVisits(userId: String, completion: @escaping () -> Void) {
        
        db.collection("visits")
            .whereField("userId", isEqualTo: userId)
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let batch = self.db.batch()
                    for document in documents {
                        batch.deleteDocument(document.reference)
                    }
                    batch.commit { _ in }
                }
                completion()
            }
    }
}
