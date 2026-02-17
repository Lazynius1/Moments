import SwiftUI
import PhotosUI

struct SocialProfileCompletionView: View {
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
    
    var body: some View {
        ZStack {
            LiquidAuroraBackground()
                .ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Text("register.completeProfile.title")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 30) {
                        if currentStep == 1 {
                            // Step 1: Username and Photo
                            VStack(spacing: 25) {
                                Text("register.completeProfile.step1")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                
                                EnhancedProfilePhotoPicker(
                                    selectedPhotoItem: $selectedPhotoItem,
                                    profileImage: $profileImage,
                                    showingPhotoPicker: $showingPhotoPicker
                                )
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "at")
                                            .foregroundColor(.white.opacity(0.7))
                                        Text("register.username")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    LiquidGlassTextField(
                                        icon: "at",
                                        placeholder: NSLocalizedString("register.username.placeholder", comment: ""),
                                        text: $username,
                                        isError: usernameError != nil,
                                        autocapitalization: .none
                                    )
                                    .onChange(of: username) { newValue in
                                        validateUsername(newValue)
                                    }
                                    
                                    if let error = usernameError {
                                        Text(error)
                                            .font(.system(size: 12))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                }
                            }
                            .padding(24)
                            .background(glassBackground())
                            
                        } else if currentStep == 2 {
                            // Step 2: Interests
                            VStack(spacing: 25) {
                                Text("register.completeProfile.step2")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                EnhancedInterestsSelector(
                                    availableInterests: $availableInterests,
                                    selectedInterests: $selectedInterests
                                )
                            }
                            .padding(24)
                            .background(glassBackground())
                        } else {
                            // Step 3: Privacy and Consent
                            VStack(spacing: 25) {
                                Text("register.completeProfile.step3")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Toggle(isOn: $privacyPolicyAccepted) {
                                    HStack {
                                        Text("register.terms.accept")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.9))
                                        
                                        Button(action: { showPrivacyPolicy = true }) {
                                            Text("register.terms.privacyPolicy")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.white)
                                                .underline()
                                        }
                                    }
                                }
                                .toggleStyle(EnhancedCustomToggleStyle())
                            }
                            .padding(24)
                            .background(glassBackground())
                        }
                        
                        // Action Button
                        Button(action: handleNext) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(currentStep == 3 ? NSLocalizedString("register.completeProfile.finish", comment: "Finish profile") : NSLocalizedString("register.actions.continue", comment: "Continue"))
                                        .font(.system(size: 18, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(16)
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(isLoading || !canProceed())
                        .opacity(canProceed() ? 1.0 : 0.6)
                        
                        if currentStep > 1 {
                            Button(action: { currentStep -= 1 }) {
                                Text("register.back")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                    }
                    .padding(24)
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
            loadInterests()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage ?? "Ocurrió un error"), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .navigationBarHidden(true)
    }
    
    private func glassBackground() -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private func validateUsername(_ username: String) {
        if username.count < 3 {
            usernameError = "Mínimo 3 caracteres"
            return
        }
        authService.checkUsernameAvailability(username: username, interests: []) { available, suggestions in
            if available {
                usernameError = nil
            } else {
                usernameError = "Nombre de usuario no disponible"
            }
        }
    }
    
    private func loadInterests() {
        authService.fetchAvailableInterests { result in
            if case .success(let interests) = result {
                availableInterests = interests
            } else {
                availableInterests = ["Fotografía", "Viajes", "Música", "Tecnología"]
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
        
        let startTime = Date()
        
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
