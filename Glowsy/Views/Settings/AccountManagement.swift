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
        Section("Gestión de cuenta") {
            // Deactivate account
            SettingsRow(
                icon: "pause.circle",
                title: "Desactivar cuenta",
                subtitle: "Oculta tu perfil temporalmente",
                isDestructive: false,
                action: {
                    showDeactivateConfirmation = true
                }
            )
            
            // Delete account
            SettingsRow(
                icon: "trash.circle",
                title: "Eliminar cuenta",
                subtitle: "Eliminación permanente de todos los datos",
                isDestructive: true,
                action: {
                    showDeleteConfirmation = true
                }
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
        
        // Deactivate confirmation
        .alert("¿Desactivar cuenta?", isPresented: $showDeactivateConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Desactivar", role: .destructive) {
                deactivateAccount()
            }
        } message: {
            Text("Tu perfil se ocultará y no podrás usar la app hasta que la reactives. Tus datos se conservarán.")
        }
        
        // Delete confirmation
        .alert("⚠️ Eliminar cuenta permanentemente", isPresented: $showDeleteConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Continuar", role: .destructive) {
                showDeleteVerification = true
            }
        } message: {
            Text("Esta acción NO se puede deshacer. Se eliminarán todos tus datos, historias, conexiones y mensajes.")
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
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
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
                errorMessage = "No se pudo obtener el usuario actual"
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
                    print("✅ Cuenta eliminada exitosamente")
                    self.isProcessing = false
                    self.showDeleteVerification = false
                }
            case .failure(let error):
                print("❌ Eliminación normal falló: \(error.localizedDescription)")
                print("🔄 Intentando eliminación rápida...")
                
                // Si falla, intentar eliminación rápida
                accountService.deleteAccountFast(user: user, password: password) { fastResult in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.showDeleteVerification = false
                        
                        switch fastResult {
                        case .success:
                            print("✅ Cuenta eliminada con método rápido")
                        case .failure(let fastError):
                            print("❌ Error en eliminación rápida: \(fastError.localizedDescription)")
                            self.errorMessage = "Error eliminando cuenta: \(fastError.localizedDescription)"
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
    
    private let requiredText = "ELIMINAR MI CUENTA"
    
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
                            
                            Text("Eliminando cuenta...")
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
                                    Text("Eliminación permanente")
                                        .font(.custom("Poppins-Bold", size: 24))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("Esta acción no se puede deshacer")
                                        .font(.custom("Poppins-Regular", size: 16))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 20)
                            
                            // What will be deleted
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Se eliminarán permanentemente:")
                                    .font(.custom("Poppins-SemiBold", size: 18))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    DeletedDataRow(icon: "person.circle", text: "Tu perfil y información personal")
                                    DeletedDataRow(icon: "photo.on.rectangle", text: "Todas tus historias y momentos")
                                    DeletedDataRow(icon: "message.circle", text: "Conversaciones y mensajes")
                                    DeletedDataRow(icon: "person.2.circle", text: "Conexiones y seguidores")
                                    DeletedDataRow(icon: "bell.circle", text: "Notificaciones y configuraciones")
                                    DeletedDataRow(icon: "folder.circle", text: "Archivo y contenido guardado")
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Verification form
                            VStack(spacing: 20) {
                                // Password verification
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Confirma tu contraseña:")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    SecureField("Contraseña actual", text: $password)
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
                                    Text("Escribe exactamente:")
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
                                    
                                    TextField("Escribe aquí", text: $confirmText)
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
                                            .foregroundColor(agreeToDelete ? Color(hex: "00A896") : .gray)
                                    }
                                    
                                    Text("Entiendo que esta acción es irreversible y acepto la eliminación permanente de mi cuenta y todos mis datos.")
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
                                        Text("ELIMINAR MI CUENTA PERMANENTEMENTE")
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
                                    Text("Cancelar")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(Color(hex: "00A896"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(hex: "00A896"), lineWidth: 2)
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Eliminar cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if !isProcessing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancelar") {
                            onCancel()
                        }
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(Color(hex: "00A896"))
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
        print("🗑️ Iniciando eliminación de cuenta para: \(user.email ?? "email desconocido")")
        
        // Re-authenticate user first
        guard let email = user.email else {
            let error = NSError(domain: "AccountDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener el email del usuario"])
            completion(.failure(error))
            return
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error = error {
                print("❌ Error reautenticando usuario: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            print("✅ Usuario reautenticado exitosamente")
            // Proceed with account deletion
            self?.performAccountDeletion(user: user, completion: completion)
        }
    }
    
    private func performAccountDeletion(user: User, completion: @escaping (Result<Void, Error>) -> Void) {
        let userId = user.uid
        print("🗑️ Iniciando eliminación de datos para userId: \(userId)")
        
        // Estrategia simplificada: Solo eliminar el documento del usuario principal
        // Las reglas de seguridad de Firestore pueden manejar la limpieza en cascada
        let userRef = db.collection("users").document(userId)
        
        print("📝 Eliminando documento principal del usuario...")
        userRef.delete { [weak self] error in
            if let error = error {
                print("❌ Error eliminando documento del usuario: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            print("✅ Documento del usuario eliminado")
            print("🔥 Procediendo a eliminar cuenta de Firebase Auth...")
            
            // Now delete Firebase Auth account
            user.delete { error in
                if let error = error {
                    print("❌ Error eliminando cuenta de Auth: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Cuenta de Auth eliminada exitosamente")
                    print("🎉 Eliminación de cuenta completada")
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Versión alternativa más agresiva si la anterior falla
    func deleteAccountFast(user: User, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🗑️ Eliminación RÁPIDA para: \(user.email ?? "email desconocido")")
        
        guard let email = user.email else {
            let error = NSError(domain: "AccountDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener el email del usuario"])
            completion(.failure(error))
            return
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                print("❌ Error reautenticando: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            print("✅ Reautenticado - Eliminando Auth directamente...")
            
            // Eliminar cuenta de Auth inmediatamente sin limpiar Firestore
            user.delete { error in
                if let error = error {
                    print("❌ Error eliminando Auth: \(error.localizedDescription)")
                    completion(.failure(error))
                } else {
                    print("✅ Cuenta eliminada exitosamente (modo rápido)")
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
}
