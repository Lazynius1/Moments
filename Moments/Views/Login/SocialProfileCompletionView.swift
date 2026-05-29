import SwiftUI
import PhotosUI
import FirebaseAuth

struct SocialProfileCompletionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var authService: AuthService
    @State private var username: String = ""
    @State private var selectedInterests: [String] = []
    @State private var availableInterests: [String] = []
    @State private var profileImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var usernameError: String? = nil
    @State private var usernameSuggestions: [String] = []
    @State private var isLoading: Bool = false
    @State private var showAlert: Bool = false
    @State private var errorMessage: String? = nil
    @State private var currentStep: Int = 1
    @State private var isCreatingProfile: Bool = false
    @State private var firebaseOperationsCompleted: Bool = false // ✅ FALTA ESTA VARIABLE
    @State private var animationFinished: Bool = false
    @State private var privacyPolicyAccepted: Bool = false
    @State private var showPrivacyPolicy: Bool = false
    @State private var showingPhotoPicker: Bool = false
    @State private var isVisible = false

    private var displayEmail: String {
        Auth.auth().currentUser?.email ?? NSLocalizedString("register.completeProfile.appleAccount", comment: "Apple account")
    }
    
    var body: some View {
        ZStack {
            LiquidAuroraBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { step in
                            Capsule()
                                .fill(
                                    currentStep >= step ?
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9),
                                            Color.white.opacity(0.58)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [.white.opacity(0.22), .white.opacity(0.12)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: currentStep == step ? 26 : 22, height: 4)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)
                        }
                    }

                    Spacer()
                }
                .authScreenHorizontalPadding()
                .padding(.top, 10)
                .opacity(isVisible ? 1 : 0)
                
                ScrollView {
                    VStack(spacing: 16) {
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
                        .scaleEffect(isVisible ? 1 : 0.8)
                        .opacity(isVisible ? 1 : 0)

                        VStack(spacing: 12) {
                        if currentStep == 1 {
                            // Step 1: Username and Photo
                            VStack(spacing: 16) {
                                EnhancedProfilePhotoPicker(
                                    selectedPhotoItem: $selectedPhotoItem,
                                    profileImage: $profileImage,
                                    showingPhotoPicker: $showingPhotoPicker
                                )
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "at")
                                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.7))
                                        Text("register.username")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AuthColors.primary(colorScheme))
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
                                    }
                                }
                            }
                            
                        } else if currentStep == 2 {
                            // Step 2: Interests
                            VStack(spacing: 16) {
                                EnhancedInterestsSelector(
                                    availableInterests: $availableInterests,
                                    selectedInterests: $selectedInterests
                                )
                            }
                        } else {
                            EnhancedStep3View(
                                privacyPolicyAccepted: $privacyPolicyAccepted,
                                showPrivacyPolicy: $showPrivacyPolicy,
                                username: username,
                                email: displayEmail,
                                interests: selectedInterests
                            )
                        }
                        
                        AuthRegistrationPrimaryButton(
                            title: currentStep == 3 ? "register.completeProfile.finish" : "register.actions.continue",
                            isLoading: isLoading,
                            isEnabled: canProceed(),
                            action: handleNext
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
                        .opacity(isVisible ? 1 : 0)

                        Spacer(minLength: 50)
                    }
                }
            }
            
            // ✅ Overlay de creación de perfil (Integración idéntica a RegisterView)
            if isCreatingProfile {
                CreatingProfileView { 
                    self.animationFinished = true
                    self.checkAndFinalizeRegistration()
                }
            }
        }
        .onAppear {
            withAnimation {
                isVisible = true
            }
            loadInterests()
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
        .navigationBarHidden(true)
    }
    
    private func getStepDescription() -> String {
        switch currentStep {
        case 1:
            return NSLocalizedString("register.completeProfile.step1", comment: "Choose how others will see you")
        case 2:
            return NSLocalizedString("register.completeProfile.step2", comment: "Pick interests")
        case 3:
            return NSLocalizedString("register.completeProfile.step3", comment: "Final step")
        default:
            return ""
        }
    }
    
    private func validateUsername(_ username: String) {
        if username.count < 3 {
            usernameError = NSLocalizedString("register.error.usernameTooShort", comment: "Username too short")
            return
        }
        authService.checkUsernameAvailability(username: username, interests: []) { available, suggestions in
            if available {
                usernameError = nil
            } else {
                usernameError = NSLocalizedString("register.error.usernameUnavailable", comment: "Username unavailable")
            }
        }
    }
    
    private func loadInterests() {
        authService.fetchAvailableInterests { result in
            if case .success(let interests) = result {
                availableInterests = interests
            } else {
                availableInterests = [
                    NSLocalizedString("register.interest.photography", comment: "Photography"),
                    NSLocalizedString("register.interest.travel", comment: "Travel"),
                    NSLocalizedString("register.interest.music", comment: "Music"),
                    NSLocalizedString("register.interest.technology", comment: "Technology")
                ]
            }
        }
    }
    
    private func canProceed() -> Bool {
        switch currentStep {
        case 1: return !username.isEmpty && usernameError == nil
        case 2: return !selectedInterests.isEmpty
        case 3: return privacyPolicyAccepted
        default: return false
        }
    }
    
    private func handleNext() {
        if currentStep < 3 {
            withAnimation { currentStep += 1 }
        } else {
            completeRegistration()
        }
    }
    
    // ✅ FUNCIÓN MODIFICADA: Iniciar proceso con animación
    private func completeRegistration() {
        isLoading = true
        animationFinished = false
        firebaseOperationsCompleted = false // Reiniciar estado
        isCreatingProfile = true // Mostrar animación
        
        authService.completeSocialRegistration(
            username: username,
            interests: selectedInterests,
            profileImage: profileImage
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success:
                    // Guardar éxito en estado persistente
                    self.firebaseOperationsCompleted = true
                    // Intentar finalizar
                    self.checkAndFinalizeRegistration()
                    
                case .failure(let error):
                    // Si falla, ocultar animación y mostrar error
                    self.isCreatingProfile = false
                    self.firebaseOperationsCompleted = false
                    self.errorMessage = error.localizedDescription
                    self.showAlert = true
                }
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Sincronizar finalización
    private func checkAndFinalizeRegistration() {
        // Solo procedemos si TENEMOS ÉXITO GUARDADO y la animación terminó
        if firebaseOperationsCompleted && animationFinished {
            
            // Pequeño delay de gracia para asegurar que el usuario vea el éxito
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isCreatingProfile = false
                
                // ✅ MANUALMENTE completar el registro aquí, sincronizado con la animación
                // Esto dispara el cambio de estado en AuthService -> TabBarView
                self.authService.completeRegistration()
            }
            
        } else if animationFinished && !firebaseOperationsCompleted {
            // Caso raro: animación terminó pero operación aún no (o falló antes pero se manejó en failure)
            // Aquí simplemente esperamos a que llegue el callback de completeSocialRegistration
        }
    }}
