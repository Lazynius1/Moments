import SwiftUI
import PhotosUI
import FirebaseAuth
import UIKit

enum OnboardingContext {
    case email
    case apple
}

struct ProfileOnboardingView: View {
    let context: OnboardingContext

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var usernameError: String?
    @State private var usernameSuggestions: [String] = []
    @State private var selectedInterests: [String] = []
    @State private var availableInterests: [String] = []
    @State private var profileImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var privacyPolicyAccepted = false
    @State private var showPrivacyPolicy = false
    @State private var currentStep = 1
    @State private var isLoading = false
    @State private var isCreatingProfile = false
    @State private var firebaseOperationsCompleted = false
    @State private var animationFinished = false
    @State private var showAlert = false
    @State private var errorMessage: String?
    @State private var isVisible = false
    @State private var isCancelling = false
    @State private var didRestoreDraft = false

    @ScaledMetric(relativeTo: .body) private var onboardingSectionSpacing = AuthFormMetrics.onboardingSectionSpacing
    @ScaledMetric(relativeTo: .body) private var onboardingTopPadding = AuthFormMetrics.onboardingTopPadding

    private var draftContext: OnboardingDraftContext {
        context == .email ? .email : .apple
    }

    private var accountLabel: String {
        switch context {
        case .email:
            return email
        case .apple:
            return Auth.auth().currentUser?.email
                ?? authService.pendingAppleRegistrationEmail
                ?? NSLocalizedString("register.completeProfile.appleAccount", comment: "Apple account")
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        if currentStep < 3 {
            return "register.actions.continue"
        }
        return context == .email ? "register.actions.createAccount" : "register.completeProfile.finish"
    }

    var body: some View {
        ZStack {
            LiquidAuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: onboardingSectionSpacing) {
                        OnboardingStepHeader(
                            title: stepTitle,
                            subtitle: stepSubtitle,
                            showsLogo: currentStep == 1
                        )
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 12)

                        if authService.isResumingOnboarding {
                            OnboardingResumeBanner()
                                .opacity(isVisible ? 1 : 0)
                        }

                        stepContent
                            .opacity(isVisible ? 1 : 0)
                            .offset(y: isVisible ? 0 : 20)
                    }
                    .authScreenContentWidth()
                    .padding(.top, onboardingTopPadding)
                    .padding(.bottom, 104)
                }
            }

            if isCreatingProfile {
                CreatingProfileView {
                    animationFinished = true
                    checkAndFinalizeRegistration()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                isVisible = true
            }
            loadInterests()
            authService.resumingOnboardingContext = draftContext
            restoreDraftIfNeeded()
            markOnboardingStartedIfNeeded()
        }
        .onChange(of: currentStep) { _, _ in
            persistDraft()
        }
        .onChange(of: username) { _, _ in
            persistDraft()
        }
        .onChange(of: email) { _, _ in
            persistDraft()
        }
        .onChange(of: selectedInterests) { _, _ in
            persistDraft()
        }
        .onChange(of: privacyPolicyAccepted) { _, _ in
            persistDraft()
        }
        .onChange(of: profileImage) { _, _ in
            persistDraft()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("login.error.title"),
                message: Text(errorMessage ?? NSLocalizedString("login.error.unknown", comment: "Unknown error")),
                dismissButton: .default(Text("login.ok"))
            )
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .background {
            if context == .apple {
                NavigationSwipeBackDisabler()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: primaryNavigationAction) {
                Image(systemName: currentStep > 1 ? "chevron.left" : "xmark")
                    .font(.system(size: currentStep > 1 ? 17 : 16, weight: .semibold))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .frame(width: 36, height: 36)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: true)
                    }
            }
            .accessibilityLabel(Text(currentStep > 1 ? "register.back" : "register.close"))
            .disabled(isCancelling)

            Spacer()

            OnboardingProgressDots(currentStep: currentStep, totalSteps: 3)

            Spacer()

            if currentStep > 1 {
                Button(action: context == .apple ? cancelAppleOnboarding : cancelEmailOnboarding) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                        .frame(width: 36, height: 36)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                }
                .accessibilityLabel(Text("onboarding.cancelRegistration"))
                .disabled(isCancelling)
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
            }
        }
        .authScreenHorizontalPadding()
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch (context, currentStep) {
        case (.email, 1):
            OnboardingCredentialsStep(
                username: $username,
                email: $email,
                password: $password,
                showPassword: $showPassword,
                usernameError: $usernameError,
                usernameSuggestions: $usernameSuggestions,
                authService: authService
            )
        case (.email, 2):
            OnboardingProfileInterestsStep(
                selectedPhotoItem: $selectedPhotoItem,
                profileImage: $profileImage,
                showingPhotoPicker: $showingPhotoPicker,
                availableInterests: $availableInterests,
                selectedInterests: $selectedInterests,
                showsPhoto: true
            )
        case (.apple, 1):
            OnboardingIdentityStep(
                selectedPhotoItem: $selectedPhotoItem,
                profileImage: $profileImage,
                showingPhotoPicker: $showingPhotoPicker,
                username: $username,
                usernameError: $usernameError,
                usernameSuggestions: $usernameSuggestions,
                authService: authService
            )
        case (.apple, 2):
            OnboardingProfileInterestsStep(
                selectedPhotoItem: $selectedPhotoItem,
                profileImage: $profileImage,
                showingPhotoPicker: $showingPhotoPicker,
                availableInterests: $availableInterests,
                selectedInterests: $selectedInterests,
                showsPhoto: false
            )
        default:
            OnboardingProfilePreviewStep(
                profileImage: profileImage,
                username: username,
                accountLabel: accountLabel,
                interests: selectedInterests,
                privacyPolicyAccepted: $privacyPolicyAccepted,
                showPrivacyPolicy: $showPrivacyPolicy,
                isAppleAccount: context == .apple
            )
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            AuthRegistrationPrimaryButton(
                title: primaryButtonTitle,
                isLoading: isLoading,
                isEnabled: canProceed(),
                action: handleNext
            )
        }
        .authScreenContentWidth()
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var stepTitle: LocalizedStringKey {
        switch (context, currentStep) {
        case (.email, 1): return "onboarding.email.title.step1"
        case (.email, 2): return "onboarding.title.step2"
        case (.email, 3): return "onboarding.title.step3"
        case (.apple, 1): return "onboarding.apple.title.step1"
        case (.apple, 2): return "onboarding.title.step2"
        case (.apple, 3): return "onboarding.title.step3"
        default: return "register.completeProfile.title"
        }
    }

    private var stepSubtitle: LocalizedStringKey {
        switch (context, currentStep) {
        case (.email, 1): return "onboarding.email.subtitle.step1"
        case (.email, 2): return "onboarding.subtitle.step2"
        case (.email, 3): return "onboarding.subtitle.step3"
        case (.apple, 1): return "onboarding.apple.subtitle.step1"
        case (.apple, 2): return "register.completeProfile.step2"
        case (.apple, 3): return "onboarding.subtitle.step3"
        default: return "register.completeProfile.step3"
        }
    }

    private func canProceed() -> Bool {
        switch (context, currentStep) {
        case (.email, 1):
            return !username.isEmpty && !email.isEmpty && password.count >= 8 && usernameError == nil
        case (.email, 2), (.apple, 2):
            return selectedInterests.count >= RegisterInterestsPolicy.minimum
        case (.apple, 1):
            return !username.isEmpty && usernameError == nil
        default:
            return privacyPolicyAccepted
        }
    }

    private func handleNext() {
        if currentStep < 3 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                currentStep += 1
            }
        } else {
            completeRegistration()
        }
    }

    private func primaryNavigationAction() {
        if currentStep > 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                currentStep -= 1
            }
        } else {
            context == .apple ? cancelAppleOnboarding() : cancelEmailOnboarding()
        }
    }

    private func completeRegistration() {
        isLoading = true
        firebaseOperationsCompleted = false
        animationFinished = false
        isCreatingProfile = true

        switch context {
        case .email:
            authService.register(
                username: username,
                email: email,
                password: password,
                interests: selectedInterests,
                privacyPolicyAccepted: privacyPolicyAccepted,
                profileImage: profileImage
            ) { result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        firebaseOperationsCompleted = true
                        checkAndFinalizeRegistration()
                    case .failure(let error):
                        isCreatingProfile = false
                        if (error as NSError).code == AuthService.RegistrationRecoveryCode.accountAlreadyComplete {
                            dismiss()
                            return
                        }
                        errorMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        case .apple:
            authService.completeSocialRegistration(
                username: username,
                interests: selectedInterests,
                profileImage: profileImage
            ) { result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        firebaseOperationsCompleted = true
                        checkAndFinalizeRegistration()
                    case .failure(let error):
                        isCreatingProfile = false
                        errorMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        }
    }

    private func checkAndFinalizeRegistration() {
        guard firebaseOperationsCompleted && animationFinished else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isCreatingProfile = false
            authService.completeRegistration()
        }
    }

    private func cancelAppleOnboarding() {
        cancelOnboarding()
    }

    private func cancelEmailOnboarding() {
        cancelOnboarding()
    }

    private func cancelOnboarding() {
        guard !isCancelling else { return }
        isCancelling = true
        authService.cancelOnboardingRegistration(deleteIncompleteAccount: true) { _ in
            isCancelling = false
            dismiss()
        }
    }

    private func markOnboardingStartedIfNeeded() {
        guard OnboardingDraftStore.load() == nil else { return }

        OnboardingDraftStore.markStarted(
            context: draftContext,
            firebaseUID: Auth.auth().currentUser?.uid,
            pendingAppleEmail: context == .apple
                ? (Auth.auth().currentUser?.email ?? authService.pendingAppleRegistrationEmail)
                : nil
        )
        persistDraft()
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true

        guard let draft = OnboardingDraftStore.load() else { return }
        guard draft.context == draftContext else { return }
        if let draftUID = draft.firebaseUID,
           let currentUID = Auth.auth().currentUser?.uid,
           draftUID != currentUID {
            return
        }

        if draft.context == .email, draft.firebaseUID == nil, draft.step > 1 {
            // Sin sesión Auth guardada, la contraseña no se persiste: volver al paso 1.
            currentStep = 1
        } else {
            currentStep = min(max(draft.step, 1), 3)
        }
        username = draft.username
        email = draft.email
        selectedInterests = draft.selectedInterests
        privacyPolicyAccepted = draft.privacyPolicyAccepted
        profileImage = OnboardingDraftStore.profileImage(from: draft)

        if context == .apple, let pendingEmail = draft.pendingAppleEmail {
            authService.pendingAppleRegistrationEmail = pendingEmail
        }
    }

    private func persistDraft() {
        authService.persistOnboardingDraft(
            context: draftContext,
            step: currentStep,
            username: username,
            email: email,
            selectedInterests: selectedInterests,
            privacyPolicyAccepted: privacyPolicyAccepted,
            profileImage: profileImage,
            firebaseUID: Auth.auth().currentUser?.uid,
            pendingAppleEmail: context == .apple
                ? (Auth.auth().currentUser?.email ?? authService.pendingAppleRegistrationEmail)
                : nil
        )
    }

    private func loadInterests() {
        authService.fetchAvailableInterests { result in
            if case .success(let interests) = result {
                availableInterests = interests
            } else {
                availableInterests = fallbackInterests
            }
        }
    }

    private var fallbackInterests: [String] {
        [
            NSLocalizedString("register.interest.photography", comment: "Photography"),
            NSLocalizedString("register.interest.travel", comment: "Travel"),
            NSLocalizedString("register.interest.music", comment: "Music"),
            NSLocalizedString("register.interest.technology", comment: "Technology")
        ]
    }
}

// MARK: - Header

private struct OnboardingStepHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let showsLogo: Bool

    @ScaledMetric(relativeTo: .body) private var logoHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .body) private var spacingBeforeFields: CGFloat = 4
    @ScaledMetric(relativeTo: .title3) private var titleFontSize: CGFloat = 20.9

    var body: some View {
        VStack(spacing: showsLogo ? 18 : 0) {
            if showsLogo {
                Image(colorScheme == .dark ? "RegisterLogo2" : "whatsnew2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: logoHeight)
                    .shadow(color: .white.opacity(0.18), radius: 6, x: 0, y: 0)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: titleFontSize).weight(.semibold))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, spacingBeforeFields)
    }
}

private struct OnboardingProgressDots: View {
    @Environment(\.colorScheme) private var colorScheme
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...totalSteps, id: \.self) { step in
                Capsule()
                    .fill(dotColor(for: step))
                    .frame(width: step == currentStep ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: currentStep)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Color.clear
                .momentsChromeGlass(in: Capsule(), interactive: false)
        }
        .accessibilityLabel(Text("\(currentStep)/\(totalSteps)"))
    }

    private func dotColor(for step: Int) -> Color {
        if step <= currentStep {
            return AuthColors.primary(colorScheme).opacity(0.82)
        }
        return AuthColors.primary(colorScheme).opacity(0.22)
    }
}

// MARK: - Step 1 (email): credentials

private struct OnboardingCredentialsStep: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var username: String
    @Binding var email: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var usernameError: String?
    @Binding var usernameSuggestions: [String]
    let authService: AuthService

    @ScaledMetric(relativeTo: .body) private var fieldSpacing = AuthFormMetrics.onboardingFieldSpacing

    var body: some View {
        VStack(spacing: fieldSpacing) {
            LiquidGlassTextField(
                icon: "at",
                placeholder: NSLocalizedString("register.username.placeholder", comment: ""),
                text: $username,
                isError: usernameError != nil,
                autocapitalization: .none
            )
            .onChange(of: username) { _, newValue in
                validateUsername(newValue)
            }

            if let error = usernameError {
                usernameFeedback(error: error)
            }

            LiquidGlassTextField(
                icon: "envelope.fill",
                placeholder: NSLocalizedString("register.email.placeholder", comment: ""),
                text: $email,
                keyboardType: .emailAddress,
                autocapitalization: .none
            )

            VStack(alignment: .leading, spacing: 8) {
                LiquidGlassSecureField(
                    icon: "lock.fill",
                    placeholder: NSLocalizedString("register.password.requirement", comment: ""),
                    text: $password,
                    isVisible: $showPassword
                )

                if !password.isEmpty {
                    passwordStrengthIndicator
                }
            }
        }
    }

    @ViewBuilder
    private func usernameFeedback(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.red.opacity(0.8))

            if !usernameSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(usernameSuggestions, id: \.self) { suggestion in
                            Button {
                                username = suggestion
                                usernameError = nil
                                usernameSuggestions = []
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Capsule(), interactive: true)
                                    }
                                    .foregroundColor(AuthColors.primary(colorScheme))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var passwordStrengthIndicator: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(passwordStrengthColor(for: index))
                        .frame(height: 4)
                }
            }

            Text(passwordStrengthMessage())
                .font(.caption.weight(.medium))
                .foregroundColor(passwordStrengthTextColor())
        }
        .padding(.horizontal, 4)
    }

    private func validateUsername(_ value: String) {
        let usernameRegex = "^[a-zA-Z0-9_.]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)

        if value.isEmpty {
            usernameError = nil
            return
        }

        if !predicate.evaluate(with: value) {
            usernameError = NSLocalizedString("register.error.usernameFormat", comment: "Username format error")
            usernameSuggestions = []
            return
        }

        authService.checkUsernameAvailability(username: value, interests: []) { available, suggestions in
            if available {
                usernameError = nil
                usernameSuggestions = []
            } else {
                usernameError = NSLocalizedString("register.error.usernameUnavailable", comment: "Username unavailable")
                usernameSuggestions = suggestions ?? []
            }
        }
    }

    private func passwordStrength() -> Int {
        var strength = 0
        if password.count >= 8 { strength += 1 }
        if password.contains(where: { $0.isLetter }) { strength += 1 }
        if password.contains(where: { $0.isNumber }) { strength += 1 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { strength += 1 }
        return strength
    }

    private func passwordStrengthColor(for index: Int) -> Color {
        let strength = passwordStrength()
        if index < strength {
            switch strength {
            case 1: return .red.opacity(0.8)
            case 2: return .orange.opacity(0.8)
            case 3: return .yellow.opacity(0.8)
            case 4: return .green.opacity(0.8)
            default: return AuthColors.subtle(colorScheme, opacity: 0.2)
            }
        }
        return AuthColors.subtle(colorScheme, opacity: 0.2)
    }

    private func passwordStrengthMessage() -> String {
        switch passwordStrength() {
        case 1: return NSLocalizedString("register.password.weak", comment: "")
        case 2: return NSLocalizedString("register.password.fair", comment: "")
        case 3: return NSLocalizedString("register.password.good", comment: "")
        case 4: return NSLocalizedString("register.password.excellent", comment: "")
        default: return ""
        }
    }

    private func passwordStrengthTextColor() -> Color {
        switch passwordStrength() {
        case 1: return .red.opacity(0.8)
        case 2: return .orange.opacity(0.8)
        case 3: return .yellow.opacity(0.8)
        case 4: return .green.opacity(0.8)
        default: return AuthColors.secondary(colorScheme, opacity: 0.5)
        }
    }
}

// MARK: - Step 1 (apple): photo + username

private struct OnboardingIdentityStep: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var profileImage: UIImage?
    @Binding var showingPhotoPicker: Bool
    @Binding var username: String
    @Binding var usernameError: String?
    @Binding var usernameSuggestions: [String]
    let authService: AuthService

    @ScaledMetric(relativeTo: .body) private var fieldSpacing = AuthFormMetrics.onboardingFieldSpacing

    var body: some View {
        VStack(spacing: fieldSpacing) {
            EnhancedProfilePhotoPicker(
                selectedPhotoItem: $selectedPhotoItem,
                profileImage: $profileImage,
                showingPhotoPicker: $showingPhotoPicker
            )

            VStack(spacing: 8) {
                LiquidGlassTextField(
                    icon: "at",
                    placeholder: NSLocalizedString("register.username.placeholder", comment: ""),
                    text: $username,
                    isError: usernameError != nil,
                    autocapitalization: .none
                )
                .onChange(of: username) { _, newValue in
                    validateUsername(newValue)
                }

                if let error = usernameError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func validateUsername(_ value: String) {
        if value.count < 3 {
            usernameError = NSLocalizedString("register.error.usernameTooShort", comment: "")
            return
        }

        authService.checkUsernameAvailability(username: value, interests: []) { available, suggestions in
            if available {
                usernameError = nil
                usernameSuggestions = []
            } else {
                usernameError = NSLocalizedString("register.error.usernameUnavailable", comment: "")
                usernameSuggestions = suggestions ?? []
            }
        }
    }
}

// MARK: - Interests (+ optional photo)

private struct OnboardingProfileInterestsStep: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var profileImage: UIImage?
    @Binding var showingPhotoPicker: Bool
    @Binding var availableInterests: [String]
    @Binding var selectedInterests: [String]
    let showsPhoto: Bool

    @ScaledMetric(relativeTo: .body) private var fieldSpacing = AuthFormMetrics.onboardingFieldSpacing

    var body: some View {
        VStack(spacing: fieldSpacing) {
            if showsPhoto {
                EnhancedProfilePhotoPicker(
                    selectedPhotoItem: $selectedPhotoItem,
                    profileImage: $profileImage,
                    showingPhotoPicker: $showingPhotoPicker
                )
            }

            EnhancedInterestsSelector(
                availableInterests: $availableInterests,
                selectedInterests: $selectedInterests
            )
        }
    }
}

// MARK: - Summary preview

private struct OnboardingProfilePreviewStep: View {
    @Environment(\.colorScheme) private var colorScheme
    let profileImage: UIImage?
    let username: String
    let accountLabel: String
    let interests: [String]
    @Binding var privacyPolicyAccepted: Bool
    @Binding var showPrivacyPolicy: Bool
    let isAppleAccount: Bool

    @ScaledMetric(relativeTo: .body) private var fieldSpacing = AuthFormMetrics.onboardingFieldSpacing
    @ScaledMetric(relativeTo: .body) private var previewPhotoSize = AuthFormMetrics.onboardingPreviewPhotoSize
    @ScaledMetric(relativeTo: .title3) private var usernameFontSize: CGFloat = 19.0
    @ScaledMetric(relativeTo: .largeTitle) private var placeholderIconSize: CGFloat = 32

    var body: some View {
        VStack(spacing: fieldSpacing) {
            VStack(spacing: 18) {
                profilePreview
                VStack(spacing: 6) {
                    Text("@\(username)")
                        .font(.system(size: usernameFontSize).weight(.semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))

                    HStack(spacing: 6) {
                        Image(systemName: isAppleAccount ? "applelogo" : "envelope.fill")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))
                        Text(accountLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.78))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }

                if !interests.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("register.summary.interests")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.68))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        EnhancedFlowLayout(spacing: 8) {
                            ForEach(interests, id: \.self) { interest in
                                Text(InterestOption.localize(interest))
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background {
                                        Color.clear
                                            .liquidGlass(in: Capsule())
                                    }
                                    .foregroundColor(AuthColors.primary(colorScheme))
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background {
                Color.clear
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
            }

            VStack(spacing: 12) {
                Toggle(isOn: $privacyPolicyAccepted) {
                    HStack(spacing: 4) {
                        Text("register.terms.accept")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))

                        Button(action: { showPrivacyPolicy = true }) {
                            Text("register.terms.privacyPolicy")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AuthColors.primary(colorScheme))
                                .underline()
                        }
                    }
                }
                .toggleStyle(EnhancedCustomToggleStyle())

                if !isAppleAccount {
                    Text("register.verification.notice")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    @ViewBuilder
    private var profilePreview: some View {
        if let profileImage {
            Image(uiImage: profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: previewPhotoSize, height: previewPhotoSize)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.42), .blue.opacity(0.24)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        } else {
            Circle()
                .fill(AuthColors.subtle(colorScheme, opacity: 0.1))
                .frame(width: previewPhotoSize, height: previewPhotoSize)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: placeholderIconSize).weight(.medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.42))
                }
        }
    }
}

private struct OnboardingResumeBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AuthColors.primary(colorScheme))

            Text("onboarding.resume.banner")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.82))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: false)
        }
    }
}

/// Evita salir del onboarding con swipe y borrar la cuenta Auth por accidente.
private struct NavigationSwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
