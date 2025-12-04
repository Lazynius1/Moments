import SwiftUI
import PhotosUI

struct RegisterView: View {
    @StateObject var authService = AuthService()
    @State var username: String = ""
    @State var email: String = ""
    @State var password: String = ""
    @State var selectedInterests: [String] = []
    @State var availableInterests: [String] = []
    @State var errorMessage: String? = nil
    @State var usernameError: String? = nil
    @State var usernameSuggestions: [String] = []
    @State var isLoading: Bool = false
    @State var isCreatingProfile: Bool = false
    @State var firebaseOperationsCompleted: Bool = false // ✅ Flag para operaciones de Firebase
    @State var animationFinished: Bool = false // ✅ NUEVO: Flag para la animación de CreatingProfileView
    @State var showAlert: Bool = false
    @State var privacyPolicyAccepted: Bool = false
    @State var showPrivacyPolicy: Bool = false
    @State var selectedPhotoItem: PhotosPickerItem? = nil
    @State var profileImage: Any? = nil
    @State var showPassword: Bool = false
    @State var currentStep: Int = 1
    @State var isVisible = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Enhanced background
            EnhancedBackgroundView()
            
            VStack {
                // Enhanced header with close button
                HStack {
                    Button(action: { dismiss() }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .frame(width: 36, height: 36)
                                .blur(radius: 10)
                            
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    // Enhanced progress indicator
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { step in
                            Capsule()
                                .fill(
                                    currentStep >= step ?
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                        LinearGradient(
                                            colors: [.white.opacity(0.3), .white.opacity(0.2)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                                .frame(width: 32, height: 4)
                                .shadow(
                                    color: currentStep >= step ? .blue.opacity(0.5) : .clear,
                                    radius: 4,
                                    x: 0,
                                    y: 0
                                )
                                .scaleEffect(currentStep == step ? 1.1 : 1.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)
                        }
                    }
                    
                    Spacer()
                    
                    // Placeholder para balance
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.8), value: isVisible)
                
                ScrollView {
                    VStack(spacing: 25) {
                        // Enhanced logo and title
                        VStack(spacing: 15) {
                            Image("RegisterLogo2")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 200)
                                .shadow(color: .white.opacity(0.8), radius: 15, x: 0, y: 0)
                                .shadow(color: .blue.opacity(0.5), radius: 25, x: 0, y: 0)
                                .padding(.horizontal, 20)
                            
                            Text(getStepDescription())
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut, value: currentStep)
                        }
                        .padding(.top, 20)
                        .scaleEffect(isVisible ? 1.0 : 0.8)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                        
                        // Contenido del paso actual
                        VStack(spacing: 20) {
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
                            
                            // Enhanced action button
                            Button(action: handleNextAction) {
                                HStack(spacing: 12) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text(currentStep == 3 ? NSLocalizedString("register.actions.createAccount", comment: "Create account button") : NSLocalizedString("register.actions.continue", comment: "Continue button"))
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.25, green: 0.35, blue: 0.82),
                                                Color(red: 0.78, green: 0.31, blue: 0.75)
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                            )
                            .disabled(isLoading || !canProceed())
                            .opacity(canProceed() ? 1 : 0.6)
                            .scaleEffect(isLoading ? 0.95 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isLoading)
                            
                            if currentStep > 1 {
                                Button(action: { currentStep -= 1 }) {
                                    Text("register.back")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 24)
                                        .background(
                                            Capsule()
                                                .fill(Color.white.opacity(0.1))
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 40)
                        .background(
                            ZStack {
                                // Enhanced glass morphism effect
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(.ultraThinMaterial)
                                    .background(
                                        RoundedRectangle(cornerRadius: 32)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        .white.opacity(0.1),
                                                        .white.opacity(0.05)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                
                                // Enhanced border gradient
                                RoundedRectangle(cornerRadius: 32)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.3),
                                                .white.opacity(0.1),
                                                .clear
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                        )
                        .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
                        .shadow(color: .blue.opacity(0.1), radius: 50, x: 0, y: 25)
                        .padding(.horizontal, 20)
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
        // Android: Navigation bar hidden handled natively
        // .navigationBarHidden(true)
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
                dismissButton: .default(Text("OK"))
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
                availableInterests = ["Fotografía", "Viajes", "Música", "Cine", "Arte", "Deportes", "Libros", "Cocina", "Tecnología", "Moda", "Gaming", "Fitness"]
            }
        }
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
            let minimumDisplayTime: TimeInterval = 3.0 // 3 segundos mínimo
            
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
    @Binding var username: String
    @Binding var email: String
    @Binding var password: String
    @Binding var showPassword: Bool
    @Binding var usernameError: String?
    @Binding var usernameSuggestions: [String]
    let authService: AuthService
    @State var usernameFocused = false
    @State var emailFocused = false
    @State var passwordFocused = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Enhanced Username
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "at")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("register.username")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                TextField("", text: $username)
                    .placeholder(when: username.isEmpty) {
                        Text("register.username.placeholder")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(usernameFocused ? 0.15 : 0.1))
                            .animation(.easeInOut(duration: 0.2), value: usernameFocused)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                usernameError != nil ?
                                LinearGradient(colors: [.red.opacity(0.5), .red.opacity(0.3)], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(
                                    colors: usernameFocused ? [.blue.opacity(0.5), .purple.opacity(0.3)] : [.white.opacity(0.2), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: usernameFocused ? 2 : 1
                            )
                            .animation(.easeInOut(duration: 0.2), value: usernameFocused)
                    )
                    // Android: Autocapitalization handled natively
                    // .autocapitalization(.none)
                    .onTapGesture {
                        usernameFocused = true
                    }
                    .onChange(of: username) { newValue in
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
                                                Capsule()
                                                    .fill(Color.white.opacity(0.2))
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                                    )
                                            )
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Enhanced Email
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("register.email")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                TextField("", text: $email)
                    .placeholder(when: email.isEmpty) {
                        Text("register.email.placeholder")
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                    .keyboardType(.emailAddress)
                    // Android: Autocapitalization handled natively
                    // .autocapitalization(.none)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(emailFocused ? 0.15 : 0.1))
                            .animation(.easeInOut(duration: 0.2), value: emailFocused)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: emailFocused ? [.blue.opacity(0.5), .purple.opacity(0.3)] : [.white.opacity(0.2), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: emailFocused ? 2 : 1
                            )
                            .animation(.easeInOut(duration: 0.2), value: emailFocused)
                    )
                    .onTapGesture {
                        emailFocused = true
                    }
            }
            
            // Enhanced Password
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("register.password")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                HStack {
                    if showPassword {
                        TextField("", text: $password)
                            .foregroundColor(.white)
                    } else {
                        SecureField("", text: $password)
                            .foregroundColor(.white)
                    }
                    
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 16))
                    }
                }
                .placeholder(when: password.isEmpty) {
                    Text("register.password.requirement")
                        .foregroundColor(.white.opacity(0.5))
                }
                .font(.system(size: 16))
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(passwordFocused ? 0.15 : 0.1))
                        .animation(.easeInOut(duration: 0.2), value: passwordFocused)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: passwordFocused ? [.blue.opacity(0.5), .purple.opacity(0.3)] : [.white.opacity(0.2), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: passwordFocused ? 2 : 1
                        )
                        .animation(.easeInOut(duration: 0.2), value: passwordFocused)
                )
                .onTapGesture {
                    passwordFocused = true
                }
                
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
            usernameError = "3-20 caracteres, solo letras, números, _ o ."
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
            default: return .white.opacity(0.2)
            }
        }
        return .white.opacity(0.2)
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
        default: return .white.opacity(0.5)
        }
    }
}

// MARK: - Enhanced Step 2: Foto e intereses
struct EnhancedStep2View: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var profileImage: Any?
    @Binding var availableInterests: [String]
    @Binding var selectedInterests: [String]
    @State var showingPhotoPicker = false
    
    var body: some View {
        VStack(spacing: 25) {
            EnhancedProfilePhotoPicker(
                selectedPhotoItem: $selectedPhotoItem,
                profileImage: $profileImage,
                showingPhotoPicker: $showingPhotoPicker
            )
            
            EnhancedInterestsSelector(
                availableInterests: $availableInterests,
                selectedInterests: $selectedInterests
            )
        }
    }
}

// MARK: - Enhanced Profile Photo Picker
struct EnhancedProfilePhotoPicker: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var profileImage: Any?
    @Binding var showingPhotoPicker: Bool
    @State var isPressed = false
    
    var body: some View {
        VStack(spacing: 15) {
            Button(action: { showingPhotoPicker = true }) {
                EnhancedProfilePhotoContent(profileImage: profileImage)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem)
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let data = data {
                        // Android: Image loading will be handled natively
                        // Skip will transpile this to use Android image APIs
                        profileImage = data as Any
                    }
                }
            }
            
                            Text("register.profilePhoto.optional")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Enhanced Profile Photo Content
struct EnhancedProfilePhotoContent: View {
    let profileImage: Any?
    @State var glowIntensity: Double = 0.3
    
    var body: some View {
        ZStack {
            if profileImage != nil {
                // Android: Image loading will be handled natively
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .blue.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: .white.opacity(glowIntensity), radius: 10, x: 0, y: 0)
                    .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 0)
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.05)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white.opacity(0.8), .blue.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("register.profilePhoto.add")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.4), .blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                            )
                    )
                    .shadow(color: .white.opacity(0.1), radius: 15, x: 0, y: 0)
            }
            
            if profileImage != nil {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .blue.opacity(0.8)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 18
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                    )
                    .offset(x: 40, y: 40)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .shadow(color: .white.opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Enhanced Interests Selector
struct EnhancedInterestsSelector: View {
    @Binding var availableInterests: [String]
    @Binding var selectedInterests: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("register.interests.title")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text(String(format: NSLocalizedString("register.interests.count", comment: "Interests count"), selectedInterests.count))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                    )
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(availableInterests, id: \.self) { interest in
                    EnhancedInterestChip(
                        interest: interest,
                        isSelected: selectedInterests.contains(interest),
                        onTap: {
                            if selectedInterests.contains(interest) {
                                selectedInterests.removeAll { $0 == interest }
                            } else if selectedInterests.count < 5 {
                                selectedInterests.append(interest)
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Enhanced Interest Chip
struct EnhancedInterestChip: View {
    let interest: String
    let isSelected: Bool
    let onTap: () -> Void
    @State var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            Text(interest)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            isSelected ?
                            LinearGradient(
                                colors: [.blue.opacity(0.4), .purple.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [.white.opacity(0.1), .white.opacity(0.05)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected ?
                                    LinearGradient(
                                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [.white.opacity(0.2), .white.opacity(0.1)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .shadow(
                            color: isSelected ? .blue.opacity(0.3) : .clear,
                            radius: isSelected ? 8 : 0,
                            x: 0,
                            y: isSelected ? 4 : 0
                        )
                )
                .scaleEffect(isSelected ? 1.05 : (isPressed ? 0.95 : 1.0))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Placeholder Extension
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Enhanced Step 3: Resumen y políticas
struct EnhancedStep3View: View {
    @Binding var privacyPolicyAccepted: Bool
    @Binding var showPrivacyPolicy: Bool
    let username: String
    let email: String
    let interests: [String]
    
    var body: some View {
        VStack(spacing: 25) {
            // Enhanced summary card
            VStack(alignment: .leading, spacing: 20) {
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
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Image(systemName: "at")
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 20)
                        Text(username)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 20)
                        Text(email)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    HStack(alignment: .top) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("register.summary.interests")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            EnhancedFlowLayout(spacing: 8) {
                                ForEach(interests, id: \.self) { interest in
                                    Text(interest)
                                        .font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
            
            // Enhanced privacy toggle
            VStack(spacing: 15) {
                Toggle(isOn: $privacyPolicyAccepted) {
                    HStack {
                        Text("register.terms.accept")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Button(action: { showPrivacyPolicy = true }) {
                            Text("register.terms.privacyPolicy")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .underline()
                        }
                    }
                }
                .toggleStyle(EnhancedCustomToggleStyle())
                
                Text("register.verification.notice")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Enhanced Custom Toggle Style
struct EnhancedCustomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .fill(
                        configuration.isOn ?
                        LinearGradient(
                            colors: [.green.opacity(0.8), .green.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 50, height: 28)
                    .shadow(
                        color: configuration.isOn ? .green.opacity(0.3) : .clear,
                        radius: configuration.isOn ? 8 : 0,
                        x: 0,
                        y: 0
                    )
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0.8)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 12
                        )
                    )
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .offset(x: configuration.isOn ? 11 : -11)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

// MARK: - Enhanced Flow Layout
struct EnhancedFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX,
                                     y: result.positions[index].y + bounds.minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}

// MARK: - Preview
struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView()
    }
}
