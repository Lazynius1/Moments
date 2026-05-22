import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

// MARK: - Account Management Section para SettingsView
struct AccountManagementSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @State private var showDeactivateConfirmation = false
    @State private var showDeleteVerification = false
    @State private var isProcessing = false
    @State private var deletePasswordErrorMessage: String?
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
                    showDeleteVerification = true
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

        // Delete verification sheet
        .sheet(isPresented: $showDeleteVerification) {
            DeleteAccountVerificationView(
                isProcessing: $isProcessing,
                passwordErrorMessage: $deletePasswordErrorMessage,
                onConfirm: { password in
                    deleteAccount(password: password)
                },
                onCancel: {
                    deletePasswordErrorMessage = nil
                    showDeleteVerification = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(isProcessing)
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
        deletePasswordErrorMessage = nil

        let accountService = AccountManagementService()

        accountService.deleteAccount(user: user, password: password) { result in
            DispatchQueue.main.async {
                self.isProcessing = false

                switch result {
                case .success:
                    self.showDeleteVerification = false
                case .failure(let error):
                    if let passwordError = AccountDeletionErrorPresenter.passwordMessage(for: error) {
                        self.deletePasswordErrorMessage = passwordError
                    } else {
                        self.errorMessage = String(format: NSLocalizedString("accountManagement.error.delete", comment: "Error deleting account"), error.localizedDescription)
                        self.showError = true
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
    @Binding var passwordErrorMessage: String?
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    private enum FlowDestination: Equatable {
        case overview
        case confirmation
    }

    @State private var flowDestination: FlowDestination = .overview
    @State private var navigatingForward = true
    @State private var password: String = ""
    @State private var isPasswordVisible = false
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
        ZStack {
            Color.clear.ignoresSafeArea()

            if flowDestination == .overview {
                overviewContent
                    .transition(flowTransition)
            } else {
                confirmationContent
                    .transition(flowTransition)
            }

            if isProcessing {
                processingOverlay
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: flowDestination)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
        .animation(.easeInOut(duration: 0.18), value: passwordErrorMessage)
        .onChange(of: password) { _, _ in
            passwordErrorMessage = nil
        }
        .disabled(isProcessing)
    }

    private var overviewContent: some View {
        VStack(spacing: 0) {
            DeleteAccountHeader(
                title: NSLocalizedString("accountManagement.deleteAccount.title", comment: "Delete Account"),
                subtitle: NSLocalizedString("accountManagement.irreversible", comment: "Irreversible warning"),
                leadingIcon: "chevron.left",
                onLeadingTap: onCancel
            )
            .padding(.horizontal, 22)
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Text("accountManagement.permanentDeletion")
                            .font(.custom("Poppins-SemiBold", size: 22))
                            .foregroundColor(AuthColors.primary(colorScheme))
                            .multilineTextAlignment(.center)

                        Text("accountManagement.willBeDeleted")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 18)

                    VStack(spacing: 0) {
                        DeleteAccountImpactRow(icon: "person", text: NSLocalizedString("accountManagement.profileInfo", comment: "Profile info text"))
                        DeleteAccountImpactRow(icon: "photo.on.rectangle", text: NSLocalizedString("accountManagement.storiesMoments", comment: "Stories and moments text"))
                        DeleteAccountImpactRow(icon: "message", text: NSLocalizedString("accountManagement.conversations", comment: "Conversations text"))
                        DeleteAccountImpactRow(icon: "person.2", text: NSLocalizedString("accountManagement.connections", comment: "Connections text"))
                        DeleteAccountImpactRow(icon: "bell", text: NSLocalizedString("accountManagement.notifications", comment: "Notifications text"))
                        DeleteAccountImpactRow(icon: "folder", text: NSLocalizedString("accountManagement.savedContent", comment: "Saved content text"))
                    }

                    VStack(spacing: 10) {
                        Button(action: { navigate(to: .confirmation) }) {
                            HStack(spacing: 10) {
                                Text(NSLocalizedString("accountManagement.continue", comment: "Continue"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .background {
                            Color.clear
                                .liquidGlass(in: Capsule(), interactive: true)
                        }

                        Button(action: onCancel) {
                            Text(NSLocalizedString("accountManagement.cancel", comment: "Cancel button"))
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(AuthColors.primary(colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background {
                                    Color.clear
                                        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
    }

    private var confirmationContent: some View {
        VStack(spacing: 0) {
            DeleteAccountHeader(
                title: NSLocalizedString("accountManagement.confirmPassword", comment: "Confirm password"),
                subtitle: NSLocalizedString("accountManagement.delete.message", comment: "Delete account message"),
                leadingIcon: "chevron.left",
                onLeadingTap: { navigate(to: .overview, forward: false) }
            )
            .padding(.horizontal, 22)
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("accountManagement.confirmPassword")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(AuthColors.primary(colorScheme))

                        HStack(spacing: 12) {
                            ZStack(alignment: .leading) {
                                if password.isEmpty {
                                    Text(NSLocalizedString("accountManagement.currentPassword", comment: "Current password placeholder"))
                                        .font(.custom("Poppins-Regular", size: 15))
                                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.42))
                                }

                                if isPasswordVisible {
                                    TextField("", text: $password)
                                        .focused($isPasswordFocused)
                                        .font(.custom("Poppins-Regular", size: 15))
                                        .foregroundColor(AuthColors.primary(colorScheme))
                                        .textContentType(.password)
                                } else {
                                    SecureField("", text: $password)
                                        .focused($isPasswordFocused)
                                        .font(.custom("Poppins-Regular", size: 15))
                                        .foregroundColor(AuthColors.primary(colorScheme))
                                        .textContentType(.password)
                                }
                            }

                            Button(action: { isPasswordVisible.toggle() }) {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.58))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 18)
                        .padding(.trailing, 12)
                        .frame(height: 54)
                        .background {
                            Color.clear
                                .liquidGlass(in: Capsule(), interactive: true)
                        }
                        .overlay {
                            Capsule()
                                .stroke(passwordErrorMessage == nil ? Color.clear : Color.red.opacity(0.46), lineWidth: 1)
                        }

                        if let passwordErrorMessage {
                            Text(passwordErrorMessage)
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(.red.opacity(colorScheme == .dark ? 0.88 : 0.78))
                                .padding(.horizontal, 18)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("accountManagement.writeExactly")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(AuthColors.primary(colorScheme))

                        Text(requiredText)
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .frame(height: 42)

                        TextField(
                            "",
                            text: $confirmText,
                            prompt: Text(NSLocalizedString("accountManagement.writeHere", comment: "Write here placeholder"))
                                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.42))
                        )
                        .focused($isConfirmFocused)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(AuthColors.primary(colorScheme))
                        .textInputAutocapitalization(.characters)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 12)
                        .overlay {
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(confirmText == requiredText ? Color.green.opacity(0.45) : AuthColors.secondary(colorScheme, opacity: 0.16))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }

                    Button(action: { agreeToDelete.toggle() }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: agreeToDelete ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(agreeToDelete ? .red : AuthColors.secondary(colorScheme, opacity: 0.45))
                                .padding(.top, 1)

                            Text("accountManagement.understandIrreversible")
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onConfirm(password) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                            Text(NSLocalizedString("accountManagement.deleteAccountPermanently", comment: "Delete account permanently"))
                                .font(.custom("Poppins-SemiBold", size: 15))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background {
                        Color.clear
                            .liquidGlass(in: Capsule(), interactive: isFormValid)
                    }
                    .opacity(isFormValid ? 1.0 : 0.45)
                    .disabled(!isFormValid)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                ProgressView()
                    .tint(AuthColors.primary(colorScheme))

                Text("accountManagement.deleting")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(AuthColors.primary(colorScheme))
            }
            .padding(.horizontal, 22)
            .frame(height: 58)
            .background {
                Color.clear
                    .liquidGlass(in: Capsule())
            }
        }
    }

    private var flowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func navigate(to destination: FlowDestination, forward: Bool = true) {
        navigatingForward = forward
        passwordErrorMessage = nil
        flowDestination = destination
    }
}

enum AccountDeletionErrorPresenter {
    static func passwordMessage(for error: Error) -> String? {
        let nsError = error as NSError
        let firebaseInvalidCredentialCodes = [17004, 17009]
        let message = error.localizedDescription.lowercased()

        guard firebaseInvalidCredentialCodes.contains(nsError.code) ||
                (nsError.domain.lowercased().contains("auth") &&
                 (message.contains("password") || message.contains("credential"))) else {
            return nil
        }

        return NSLocalizedString("auth.error.wrongPassword", comment: "Wrong password")
    }
}

// MARK: - Deleted Data Row
private struct DeleteAccountHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let leadingIcon: String
    let onLeadingTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: onLeadingTap) {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                        .frame(width: 40, height: 40)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(spacing: 5) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 56)
            }
            .padding(.top, 2)
        }
    }
}

private struct DeleteAccountImpactRow: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))
                .frame(width: 22, alignment: .center)

            Text(text)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(AuthColors.primary(colorScheme))
                .lineLimit(2)

            Spacer()
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Account Management Service
class AccountManagementService {
    private let db = Firestore.firestore()
    private let functionsRegion = "europe-southwest1"
    private let deleteAccountFunctionName = "deleteMyAccount"

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

            self.requestBackendAccountDeletion(user: user, completion: completion)
        }
    }

    private func requestBackendAccountDeletion(user: User, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://\(functionsRegion)-\(projectID).cloudfunctions.net/\(deleteAccountFunctionName)") else {
            completion(.failure(NSError(domain: "AccountDeletion", code: -2, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("accountManagement.error.delete", comment: "Could not delete account")])))
            return
        }

        user.getIDTokenForcingRefresh(true) { token, tokenError in
            if let tokenError = tokenError {
                completion(.failure(tokenError))
                return
            }

            guard let token = token else {
                completion(.failure(NSError(domain: "AccountDeletion", code: -3, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("accountManagement.userNotFound", comment: "User not found error")])))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 35
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["source": "settings"], options: [])

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(NSError(domain: "AccountDeletion", code: -4, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("accountManagement.error.delete", comment: "Could not delete account")])))
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let serverMessage: String
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorText = json["error"] as? String {
                        serverMessage = errorText
                    } else {
                        serverMessage = NSLocalizedString("accountManagement.error.delete", comment: "Could not delete account")
                    }

                    completion(.failure(NSError(domain: "AccountDeletion", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: serverMessage])))
                    return
                }

                do {
                    try Auth.auth().signOut()
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }.resume()
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
