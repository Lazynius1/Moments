import SwiftUI
import FirebaseAuth
import AuthenticationServices

struct SetPasswordView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    @State private var emailInput = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    @State private var appleIdentityVerified = false
    @State private var verificationErrorMessage: String?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var didUpdateEmail = false

    private var requiresAppleVerification: Bool {
        authService.isAppleLinked
    }

    private var needsEditableEmail: Bool {
        authService.requiresBackupEmailSetup
    }

    private var normalizedEmailInput: String {
        emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var currentAuthEmail: String {
        authService.currentFirebaseUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var shouldUpdateEmailBeforeLinking: Bool {
        needsEditableEmail || normalizedEmailInput != currentAuthEmail
    }

    private var isFormValid: Bool {
        let passwordsValid = newPassword.count >= 8 && newPassword == confirmPassword
        let emailValid = AuthService.isValidEmail(normalizedEmailInput) && !AuthService.isApplePrivateRelayEmail(normalizedEmailInput)

        if requiresAppleVerification {
            return passwordsValid && emailValid && appleIdentityVerified
        }
        return passwordsValid && emailValid
    }

    var body: some View {
        ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(SettingsProfileColors.accent(colorScheme))

                            Text("settings.security.password.add")
                                .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)

                            Text(needsEditableEmail
                                 ? "settings.security.password.addSheetDescriptionNoEmail"
                                 : "settings.security.password.addSheetDescription")
                                .font(.system(size: legacyPoppinsSize(16)))
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        emailSection

                        if requiresAppleVerification {
                            appleVerificationSection
                        }

                        VStack(spacing: 20) {
                            passwordField(
                                title: "passwordChange.newPassword",
                                placeholder: "passwordChange.newPasswordPlaceholder",
                                text: $newPassword,
                                isVisible: $showNewPassword
                            )

                            passwordField(
                                title: "passwordChange.confirmPassword",
                                placeholder: "passwordChange.confirmPasswordPlaceholder",
                                text: $confirmPassword,
                                isVisible: $showConfirmPassword
                            )
                        }
                        .padding(.horizontal)

                        Button(action: savePassword) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                }

                                Text("settings.security.password.save")
                                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            }
                            .foregroundStyle(isFormValid ? SettingsProfileColors.accentContrastingText(colorScheme) : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isFormValid ? SettingsProfileColors.accent(colorScheme) : Color.gray)
                            )
                        }
                        .disabled(!isFormValid || isLoading)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationInteractivePopEnabled()
            .toolbarBackground(.hidden, for: .navigationBar)
            .momentsScrollEdgeChrome()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsToolbarBackButton(action: { dismiss() })
                }
            }
            .onAppear {
                switch authService.backupEmailStatus {
                case .usable:
                    emailInput = authService.currentFirebaseUser?.email ?? ""
                case .appleRelay, .missing:
                    emailInput = ""
                }
            }
            .alert("common.error", isPresented: $showError) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .tint(colorScheme == .dark ? .white : .black)
            .alert("settings.security.password.addSuccess", isPresented: $showSuccess) {
                Button("common.ok") { dismiss() }
            } message: {
                Text(didUpdateEmail
                     ? NSLocalizedString("settings.security.password.addSuccessMessageVerify", comment: "")
                     : NSLocalizedString("settings.security.password.addSuccessMessage", comment: ""))
            }
    }

    @ViewBuilder
    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.security.password.accountEmail")
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            if needsEditableEmail {
                TextField(
                    NSLocalizedString("settings.security.password.enterEmail", comment: ""),
                    text: $emailInput
                )
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: legacyPoppinsSize(16)))
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )

                if authService.backupEmailStatus == .appleRelay {
                    Text("settings.security.password.relayWarning")
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.orange)
                } else {
                    Text("settings.security.password.emailRequired")
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.65))
                }
            } else {
                Text(emailInput)
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                    )

                Text("settings.security.password.emailLoginHint")
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.65))
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var appleVerificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.security.password.verifyApple")
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            if appleIdentityVerified {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("accountManagement.identityVerified")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
            } else {
                SignInWithAppleButton(.continue) { request in
                    let nonce = authService.startAppleSignIn()
                    request.requestedScopes = []
                    request.nonce = nonce
                } onCompletion: { result in
                    handleAppleVerification(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: AuthFormMetrics.buttonHeight)
                .clipShape(RoundedRectangle(cornerRadius: AuthFormMetrics.buttonCornerRadius, style: .continuous))
            }

            if let verificationErrorMessage {
                Text(verificationErrorMessage)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    private func passwordField(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        isVisible: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            HStack {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: text)
                        .font(.system(size: legacyPoppinsSize(16)))
                } else {
                    SecureField(placeholder, text: text)
                        .font(.system(size: legacyPoppinsSize(16)))
                }

                Button(action: { isVisible.wrappedValue.toggle() }) {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(.gray)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
            )
        }
    }

    private func savePassword() {
        guard isFormValid else { return }
        isLoading = true

        if shouldUpdateEmailBeforeLinking {
            authService.updateAccountEmail(normalizedEmailInput) { result in
                switch result {
                case .success:
                    didUpdateEmail = true
                    linkPassword()
                case .failure(let error):
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } else {
            linkPassword()
        }
    }

    private func linkPassword() {
        authService.linkPassword(email: normalizedEmailInput, password: newPassword) { result in
            isLoading = false
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccess = true
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleAppleVerification(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = authService.currentNonce,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                verificationErrorMessage = NSLocalizedString("settings.security.appleId.error.token", comment: "")
                return
            }

            isLoading = true
            authService.reauthenticateWithApple(idToken: idToken, nonce: nonce) { result in
                isLoading = false
                switch result {
                case .success:
                    appleIdentityVerified = true
                    verificationErrorMessage = nil
                case .failure(let error):
                    appleIdentityVerified = false
                    verificationErrorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            verificationErrorMessage = error.localizedDescription
        }
    }
}
