import SwiftUI
import FirebaseAuth
import Combine

struct PasswordChangeView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = PasswordChangeViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 50))
                                .foregroundColor(Color(hex: "4F46E5"))
                            
                            Text(NSLocalizedString("passwordChange.title", comment: "Change password title"))
                                .font(.custom("Poppins-Bold", size: 24))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Text(NSLocalizedString("passwordChange.subtitle", comment: "Change password subtitle"))
                                .font(.custom("Poppins-Regular", size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Current Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString("passwordChange.currentPassword", comment: "Current password"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                HStack {
                                    if viewModel.showCurrentPassword {
                                        TextField(NSLocalizedString("passwordChange.currentPasswordPlaceholder", comment: "Current password placeholder"), text: $viewModel.currentPassword)
                                            .font(.custom("Poppins-Regular", size: 16))
                                    } else {
                                        SecureField(NSLocalizedString("passwordChange.currentPasswordPlaceholder", comment: "Current password placeholder"), text: $viewModel.currentPassword)
                                            .font(.custom("Poppins-Regular", size: 16))
                                    }
                                    
                                    Button(action: {
                                        viewModel.showCurrentPassword.toggle()
                                    }) {
                                        Image(systemName: viewModel.showCurrentPassword ? "eye.slash" : "eye")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.currentPasswordError ? .red : Color(hex: "4F46E5").opacity(0.3), lineWidth: 1)
                                        )
                                )
                                
                                if viewModel.currentPasswordError {
                                    Text(NSLocalizedString("passwordChange.currentPasswordError", comment: "Current password error"))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(.red)
                                }
                            }
                            
                            // New Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString("passwordChange.newPassword", comment: "New password"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                HStack {
                                    if viewModel.showNewPassword {
                                        TextField(NSLocalizedString("passwordChange.newPasswordPlaceholder", comment: "New password placeholder"), text: $viewModel.newPassword)
                                            .font(.custom("Poppins-Regular", size: 16))
                                    } else {
                                        SecureField(NSLocalizedString("passwordChange.newPasswordPlaceholder", comment: "New password placeholder"), text: $viewModel.newPassword)
                                            .font(.custom("Poppins-Regular", size: 16))
                                    }
                                    
                                    Button(action: {
                                        viewModel.showNewPassword.toggle()
                                    }) {
                                        Image(systemName: viewModel.showNewPassword ? "eye.slash" : "eye")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.newPasswordError ? .red : Color(hex: "4F46E5").opacity(0.3), lineWidth: 1)
                                        )
                                )
                                
                                // Password strength indicator
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("passwordChange.strength")
                                            .font(.custom("Poppins-Regular", size: 12))
                                            .foregroundColor(.gray)
                                        
                                        Text(viewModel.passwordStrength.title)
                                            .font(.custom("Poppins-Medium", size: 12))
                                            .foregroundColor(viewModel.passwordStrength.color)
                                    }
                                    
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 4)
                                                .cornerRadius(2)
                                            
                                            Rectangle()
                                                .fill(viewModel.passwordStrength.color)
                                                .frame(width: geometry.size.width * viewModel.passwordStrength.percentage, height: 4)
                                                .cornerRadius(2)
                                                .animation(.easeInOut(duration: 0.3), value: viewModel.passwordStrength.percentage)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                                
                                if viewModel.newPasswordError {
                                    Text(NSLocalizedString("passwordChange.passwordRequirement", comment: "Password requirement"))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(.red)
                                }
                            }
                            
                            // Confirm New Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString("passwordChange.confirmPassword", comment: "Confirm password"))
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                HStack {
                                    if viewModel.showConfirmPassword {
                                        TextField(NSLocalizedString("passwordChange.confirmPasswordPlaceholder", comment: "Confirm password placeholder"), text: $viewModel.confirmPassword)
                                            .font(.custom("Poppins-Regular", size: 16))
                                    } else {
                                        SecureField(NSLocalizedString("passwordChange.confirmPasswordPlaceholder", comment: "Confirm password placeholder"), text: $viewModel.confirmPassword)
                                            .font(.custom("Poppins-Regular", size: 16))
                                    }
                                    
                                    Button(action: {
                                        viewModel.showConfirmPassword.toggle()
                                    }) {
                                        Image(systemName: viewModel.showConfirmPassword ? "eye.slash" : "eye")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.confirmPasswordError ? .red : Color(hex: "4F46E5").opacity(0.3), lineWidth: 1)
                                        )
                                )
                                
                                if viewModel.confirmPasswordError {
                                    Text(NSLocalizedString("passwordChange.passwordsDontMatch", comment: "Passwords don't match"))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Security Tips
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(Color(hex: "4F46E5"))
                                
                                Text(NSLocalizedString("passwordChange.securityTips", comment: "Security tips"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                PasswordSecurityTipRow(icon: "checkmark.circle", text: "Usa al menos 8 caracteres")
                                PasswordSecurityTipRow(icon: "checkmark.circle", text: "Incluye mayúsculas y minúsculas")
                                PasswordSecurityTipRow(icon: "checkmark.circle", text: "Añade números y símbolos")
                                PasswordSecurityTipRow(icon: "checkmark.circle", text: "Evita información personal")
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "4F46E5").opacity(0.1))
                        )
                        .padding(.horizontal)
                        
                        // Change Password Button
                        Button(action: {
                            viewModel.changePassword()
                        }) {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "lock.rotation")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                
                                Text(viewModel.isLoading ? "Cambiando..." : "Cambiar Contraseña")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.isFormValid ? Color(hex: "4F46E5") : Color.gray)
                            )
                        }
                        .disabled(!viewModel.isFormValid || viewModel.isLoading)
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .alert("common.error", isPresented: $viewModel.showError) {
                Button("common.ok") { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert(NSLocalizedString("passwordChange.successMessage", comment: "Success alert title"), isPresented: $viewModel.showSuccess) {
                Button("common.ok") {
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("passwordChange.successMessage", comment: "Success message"))
            }
        }
    }
}

struct PasswordSecurityTipRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "4F46E5"))
                .font(.system(size: 12))
            
            Text(text)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}

class PasswordChangeViewModel: ObservableObject {
    @Published var currentPassword = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    
    @Published var showCurrentPassword = false
    @Published var showNewPassword = false
    @Published var showConfirmPassword = false
    
    @Published var currentPasswordError = false
    @Published var newPasswordError = false
    @Published var confirmPasswordError = false
    
    @Published var isLoading = false
    @Published var showError = false
    @Published var showSuccess = false
    @Published var errorMessage = ""
    
    private var cancellables = Set<AnyCancellable>()
    
    var passwordStrength: PasswordStrength {
        return evaluatePasswordStrength(newPassword)
    }
    
    var isFormValid: Bool {
        return !currentPassword.isEmpty &&
               newPassword.count >= 8 &&
               newPassword == confirmPassword &&
               !currentPasswordError &&
               !newPasswordError &&
               !confirmPasswordError
    }
    
    init() {
        // Observe password changes
        $newPassword
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.validateNewPassword(newValue)
            }
            .store(in: &cancellables)
        
        $confirmPassword
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.validateConfirmPassword(newValue)
            }
            .store(in: &cancellables)
    }
    
    private func validateNewPassword(_ password: String) {
        newPasswordError = !password.isEmpty && password.count < 8
    }
    
    private func validateConfirmPassword(_ password: String) {
        confirmPasswordError = !password.isEmpty && password != newPassword
    }
    
    func changePassword() {
        guard isFormValid else { return }
        
        isLoading = true
        currentPasswordError = false
        
        guard let user = Auth.auth().currentUser else {
            showErrorAlert("No se encontró usuario autenticado")
            return
        }
        
        // Re-authenticate user with current password
        let credential = EmailAuthProvider.credential(withEmail: user.email ?? "", password: currentPassword)
        
        user.reauthenticate(with: credential) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isLoading = false
                    self?.currentPasswordError = true
                    self?.showErrorAlert("La contraseña actual es incorrecta")
                    return
                }
                
                // Update password
                user.updatePassword(to: self?.newPassword ?? "") { error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        
                        if let error = error {
                            self?.showErrorAlert("Error al cambiar contraseña: \(error.localizedDescription)")
                        } else {
                            self?.showSuccess = true
                        }
                    }
                }
            }
        }
    }
    
    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func evaluatePasswordStrength(_ password: String) -> PasswordStrength {
        var score = 0
        
        // Length check
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        
        // Character variety checks
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil { score += 1 }
        
        switch score {
        case 0...2:
            return PasswordStrength(title: "Débil", color: .red, percentage: 0.25)
        case 3...4:
            return PasswordStrength(title: "Regular", color: .orange, percentage: 0.5)
        case 5:
            return PasswordStrength(title: "Buena", color: .yellow, percentage: 0.75)
        case 6:
            return PasswordStrength(title: "Fuerte", color: .green, percentage: 1.0)
        default:
            return PasswordStrength(title: "Muy Fuerte", color: .green, percentage: 1.0)
        }
    }
}

struct PasswordStrength {
    let title: String
    let color: Color
    let percentage: Double
}
