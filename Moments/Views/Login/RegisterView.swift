import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PhotosUI

struct RegisterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var authService = AuthService()
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var selectedInterests: [String] = []
    @State private var availableInterests: [String] = []
    @State private var errorMessage: String? = nil
    @State private var usernameError: String? = nil
    @State private var usernameSuggestions: [String] = []
    @State private var isLoading: Bool = false
    @State private var isCreatingProfile: Bool = false
    @State private var firebaseOperationsCompleted: Bool = false // ✅ Flag para operaciones de Firebase
    @State private var animationFinished: Bool = false // ✅ NUEVO: Flag para la animación de CreatingProfileView
    @State private var showAlert: Bool = false
    @State private var privacyPolicyAccepted: Bool = false
    @State private var showPrivacyPolicy: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var profileImage: UIImage? = nil
    @State private var showPassword: Bool = false
    @State private var currentStep: Int = 1
    @State private var isVisible = false
    @Environment(\.dismiss) var dismiss

    private let registerAccent = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 0.25, green: 0.35, blue: 0.82),
            Color(red: 0.78, green: 0.31, blue: 0.75)
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        ZStack {
            // Enhanced background
            LiquidAuroraBackground()
            
            VStack {
                // Enhanced header with close button
                HStack {
                    Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AuthColors.primary(colorScheme))
                            .frame(width: 36, height: 36)
                            .background {
                                Color.clear
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                    }
                    .accessibilityLabel(Text("register.close"))
                    
                    Spacer()
                    
                    // Enhanced progress indicator
                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { step in
                            Capsule()
                                .fill(
                                    currentStep >= step ?
                                    registerAccent :
                                        LinearGradient(
                                            colors: [.white.opacity(0.24), .white.opacity(0.16)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                                .frame(width: currentStep == step ? 26 : 22, height: 4)
                                .shadow(
                                    color: currentStep >= step ? .blue.opacity(0.2) : .clear,
                                    radius: 3,
                                    x: 0,
                                    y: 0
                                )
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)
                        }
                    }
                    
                    Spacer()
                    
                    // Placeholder para balance
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 36, height: 36)
                }
                .authScreenHorizontalPadding()
                .padding(.top, 10)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.8), value: isVisible)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Enhanced logo and title
                        VStack(spacing: 10) {
                            Image(colorScheme == .dark ? "RegisterLogo2" : "whatsnew2")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: AuthFormMetrics.registerLogoHeight)
                                .shadow(color: .white.opacity(0.22), radius: 8, x: 0, y: 0)
                                .shadow(color: .blue.opacity(0.16), radius: 16, x: 0, y: 0)
                            
                            Text(getStepDescription())
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.84))
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut, value: currentStep)
                        }
                        .authScreenContentWidth()
                        .padding(.top, 8)
                        .scaleEffect(isVisible ? 1.0 : 0.8)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                        
                        // Contenido del paso actual
                        VStack(spacing: 12) {
                            if currentStep == 1 {
                                EnhancedStep1View(
                                    username: $username,
                                    email: $email,
                                    password: $password,
                                    showPassword: $showPassword,
                                    usernameError: $usernameError,
                                    usernameSuggestions: $usernameSuggestions,
                                    authService: authService
                                )
                            } else if currentStep == 2 {
                                EnhancedStep2View(
                                    selectedPhotoItem: $selectedPhotoItem,
                                    profileImage: $profileImage,
                                    availableInterests: $availableInterests,
                                    selectedInterests: $selectedInterests
                                )
                            } else if currentStep == 3 {
                                EnhancedStep3View(
                                    privacyPolicyAccepted: $privacyPolicyAccepted,
                                    showPrivacyPolicy: $showPrivacyPolicy,
                                    username: username,
                                    email: email,
                                    interests: selectedInterests
                                )
                            }
                            
                            AuthRegistrationPrimaryButton(
                                title: currentStep == 3 ? "register.actions.createAccount" : "register.actions.continue",
                                isLoading: isLoading,
                                isEnabled: canProceed(),
                                action: handleNextAction
                            )
                            
                            if currentStep > 1 {
                                Button(action: { currentStep -= 1 }) {
                                    Text("register.back")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background {
                                            Color.clear
                                                .liquidGlass(in: Capsule(), interactive: true)
                                        }
                                }
                            }
                        }
                        .authScreenContentWidth()
                        .offset(y: isVisible ? 0 : 50)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            
            // ✅ Overlay de creación de perfil
            if isCreatingProfile {
                CreatingProfileView { // Pasar closure de completion
                    self.animationFinished = true // Establecer flag de animación
                    self.checkAndCompleteRegistration() // Intentar completar registro
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation {
                isVisible = true
            }
            loadInterests()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("register.attention.title"),
                message: Text(errorMessage ?? NSLocalizedString("register.error.unknown", comment: "Unknown error message")),
                dismissButton: .default(Text("login.ok"))
            )
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
    
    private func getStepDescription() -> String {
        switch currentStep {
        case 1:
            return NSLocalizedString("register.step.description.basic", comment: "Basic data step description")
        case 2:
            return NSLocalizedString("register.step.description.profile", comment: "Profile customization step description")
        case 3:
            return NSLocalizedString("register.step.description.final", comment: "Final step description")
        default:
            return ""
        }
    }
    
    private func canProceed() -> Bool {
        switch currentStep {
        case 1:
            return !username.isEmpty && !email.isEmpty && password.count >= 8 && usernameError == nil
        case 2:
            return !selectedInterests.isEmpty
        case 3:
            return privacyPolicyAccepted
        default:
            return false
        }
    }
    
    private func handleNextAction() {
        if currentStep < 3 {
            withAnimation {
                currentStep += 1
            }
        } else {
            register()
        }
    }
    
    private func loadInterests() {
        authService.fetchAvailableInterests { result in
            switch result {
            case .success(let interests):
                availableInterests = interests
            case .failure:
                availableInterests = fallbackInterests
            }
        }
    }
    
    private var fallbackInterests: [String] {
        [
            NSLocalizedString("register.interest.photography", comment: "Photography"),
            NSLocalizedString("register.interest.travel", comment: "Travel"),
            NSLocalizedString("register.interest.music", comment: "Music"),
            NSLocalizedString("register.interest.cinema", comment: "Cinema"),
            NSLocalizedString("register.interest.art", comment: "Art"),
            NSLocalizedString("register.interest.sports", comment: "Sports"),
            NSLocalizedString("register.interest.books", comment: "Books"),
            NSLocalizedString("register.interest.cooking", comment: "Cooking"),
            NSLocalizedString("register.interest.technology", comment: "Technology"),
            NSLocalizedString("register.interest.fashion", comment: "Fashion"),
            NSLocalizedString("register.interest.gaming", comment: "Gaming"),
            NSLocalizedString("register.interest.fitness", comment: "Fitness")
        ]
    }
    
    // ✅ FUNCIÓN ACTUALIZADA con sistema de creación de perfil
    private func register() {
        isLoading = true
        firebaseOperationsCompleted = false
        animationFinished = false
        
        
        // ✅ IMPORTANTE: Mostrar CreatingProfileView INMEDIATAMENTE
        self.isCreatingProfile = true
        
        // ✅ CRÍTICO: NO USAR DELAY - Llamar register inmediatamente
        self.authService.register(
            username: self.username,
            email: self.email,
            password: self.password,
            interests: self.selectedInterests,
            privacyPolicyAccepted: self.privacyPolicyAccepted,
            profileImage: self.profileImage
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success:
                    self.firebaseOperationsCompleted = true
                    self.checkAndCompleteRegistration()
                    
                case .failure(let error):
                    self.isCreatingProfile = false
                    self.firebaseOperationsCompleted = false
                    self.animationFinished = false
                    
                    self.errorMessage = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }

    // ✅ FUNCIÓN MEJORADA: Asegurar tiempo mínimo de visualización
    private func checkAndCompleteRegistration() {
        
        if firebaseOperationsCompleted && animationFinished {
            
            // ✅ IMPORTANTE: Delay mínimo para asegurar que el usuario vea la animación
            let minimumDisplayTime: TimeInterval = 1.0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + minimumDisplayTime) {
                self.isCreatingProfile = false
                self.authService.completeRegistration()
            }
        } else {
        }
    }
}

// MARK: - Enhanced Step 1: Información básica
struct EnhancedStep1View: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var username: String
    @Binding var email: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var usernameError: String?
    @Binding var usernameSuggestions: [String]
    let authService: AuthService
    @State private var usernameFocused = false
    @State private var emailFocused = false
    @State private var passwordFocused = false
    
    var body: some View {
        VStack(spacing: 14) {
            // Enhanced Username
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "at")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                    
                    Text("register.username")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                }
                
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
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                    
                    if !usernameSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(usernameSuggestions, id: \.self) { suggestion in
                                    Button(action: {
                                        username = suggestion
                                        usernameError = nil
                                        usernameSuggestions = []
                                    }) {
                                        Text(suggestion)
                                            .font(.system(size: 14))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Color.clear
                                                    .liquidGlass(in: Capsule(), interactive: true)
                                            )
                                            .foregroundColor(AuthColors.primary(colorScheme))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Enhanced Email
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                    
                    Text("register.email")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                }
                
                LiquidGlassTextField(
                    icon: "envelope.fill",
                    placeholder: NSLocalizedString("register.email.placeholder", comment: ""),
                    text: $email,
                    keyboardType: .emailAddress,
                    autocapitalization: .none
                )
            }
            
            // Enhanced Password
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                    
                    Text("register.password")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                }
                
                LiquidGlassSecureField(
                    icon: "lock.fill",
                    placeholder: NSLocalizedString("register.password.requirement", comment: ""),
                    text: $password,
                    isVisible: $showPassword
                )
                
                // Enhanced password strength indicator
                if !password.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<4) { index in
                            Capsule()
                                .fill(passwordStrengthColor(for: index))
                                .frame(height: 4)
                                .shadow(
                                    color: passwordStrengthColor(for: index).opacity(0.5),
                                    radius: passwordStrength() > index ? 2 : 0,
                                    x: 0,
                                    y: 0
                                )
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    Text(passwordStrengthMessage())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(passwordStrengthTextColor())
                }
            }
        }
    }
    
    private func validateUsername(_ username: String) {
        let usernameRegex = "^[a-zA-Z0-9_.]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        
        if username.isEmpty {
            usernameError = nil
            return
        }
        
        if !predicate.evaluate(with: username) {
            usernameError = NSLocalizedString("register.error.usernameFormat", comment: "Username format error")
            usernameSuggestions = []
            return
        }
        
        authService.checkUsernameAvailability(username: username, interests: []) { isAvailable, suggestions in
            if isAvailable {
                usernameError = nil
                usernameSuggestions = []
            } else {
                usernameError = NSLocalizedString("register.error.usernameUnavailable", comment: "Username unavailable error")
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
        case 1: return NSLocalizedString("register.password.weak", comment: "Weak password strength")
        case 2: return NSLocalizedString("register.password.fair", comment: "Fair password strength")
        case 3: return NSLocalizedString("register.password.good", comment: "Good password strength")
        case 4: return NSLocalizedString("register.password.excellent", comment: "Excellent password strength")
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

// MARK: - Enhanced Step 2: Foto e intereses
struct EnhancedStep2View: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var profileImage: UIImage?
    @Binding var availableInterests: [String]
    @Binding var selectedInterests: [String]
    @State private var showingPhotoPicker = false
    
    var body: some View {
        VStack(spacing: 16) {
            EnhancedProfilePhotoPicker(
                selectedPhotoItem: $selectedPhotoItem,
                profileImage: $profileImage,
                showingPhotoPicker: $showingPhotoPicker
            )
            
            EnhancedInterestsSelector(
                availableInterests: $availableInterests,
                selectedInterests: $selectedInterests
            // Replaced by AuthUIComponents.swift
            )
        }
    }
}

// MARK: - Enhanced Step 3: Resumen y políticas
struct EnhancedStep3View: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var privacyPolicyAccepted: Bool
    @Binding var showPrivacyPolicy: Bool
    let username: String
    let email: String
    let interests: [String]
    
    var body: some View {
        VStack(spacing: 16) {
            // Enhanced summary card
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("register.summary.title")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "at")
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                            .frame(width: 20)
                        Text(username)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AuthColors.primary(colorScheme))
                    }
                    
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                            .frame(width: 20)
                        Text(email)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AuthColors.primary(colorScheme))
                    }
                    
                    HStack(alignment: .top) {
                        Image(systemName: "sparkles")
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("register.summary.interests")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                            EnhancedFlowLayout(spacing: 8) {
                                ForEach(interests, id: \.self) { interest in
                                    Text(InterestOption.localize(interest))
                                        .font(.system(size: 14, weight: .medium))
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
            }
            .padding(.vertical, 4)
            
            // Enhanced privacy toggle
            VStack(spacing: 12) {
                Toggle(isOn: $privacyPolicyAccepted) {
                    HStack {
                        Text("register.terms.accept")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.9))
                        
                        Button(action: { showPrivacyPolicy = true }) {
                            Text("register.terms.privacyPolicy")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AuthColors.primary(colorScheme))
                                .underline()
                        }
                    }
                }
                .toggleStyle(EnhancedCustomToggleStyle())
                
                Text("register.verification.notice")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// Replaced by AuthUIComponents.swift

// MARK: - Preview
struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView()
    }
}
