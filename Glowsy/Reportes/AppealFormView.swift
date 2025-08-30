import SwiftUI

struct AppealFormView: View {
    let suspensionReason: String?
    @Binding var isPresented: Bool
    @EnvironmentObject var authService: AuthService
    
    // Form state
    @State private var appealMessage: String = ""
    @State private var contactEmail: String = ""
    @State private var additionalInfo: String = ""
    
    // UI state
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isVisible = false
    @State private var characterCount = 0
    @State private var messageError: String?
    
    // Success state
    @State private var appealResult: AppealResult?
    @State private var showSuccessView = false
    
    // Service
    @StateObject private var appealService = AppealService.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                EnhancedBackgroundView()
                
                if showSuccessView {
                    AppealSuccessView(
                        result: appealResult!,
                        onDismiss: {
                            isPresented = false
                        }
                    )
                } else {
                    formContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancelar") {
                    isPresented = false
                }
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .medium)),
                
                trailing: Button(NSLocalizedString("appeal.submitButton", comment: "Submit appeal button")) {
                    submitAppeal()
                }
                .foregroundColor(canSubmit ? .white : .gray)
                .font(.system(size: 16, weight: .semibold))
                .disabled(!canSubmit || isLoading)
            )
        }
        .onAppear {
            setupInitialData()
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                isVisible = true
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text(NSLocalizedString("appeal.error.ok", comment: "OK button for error alerts")))
            )
        }
    }
    
    private var formContent: some View {
        ScrollView {
            VStack(spacing: 30) {
                AppealFormHeader()
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)
                
                formFields
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var formFields: some View {
        VStack(spacing: 24) {
            // Email field
            AppealEmailField(
                email: $contactEmail,
                title: NSLocalizedString("appeal.contactEmail", comment: "Contact email field title"),
                placeholder: "tu@email.com"
                )
            
            // Suspension info (read-only)
            if let reason = suspensionReason {
                AppealInfoCard(
                    title: NSLocalizedString("appeal.suspensionReason", comment: "Suspension reason field title"),
                    content: reason,
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
            
            // Main appeal message
            AppealMessageField(
                message: $appealMessage,
                characterCount: $characterCount,
                messageError: $messageError,
                title: NSLocalizedString("appeal.yourAppeal", comment: "Your appeal field title"),
                placeholder: "Explica por qué consideras que la suspensión es incorrecta. Sé específico y proporciona contexto sobre la situación."
            )
            
            // Additional info (optional)
            AppealOptionalField(
                text: $additionalInfo,
                title: NSLocalizedString("appeal.additionalInfo", comment: "Additional info field title"),
                placeholder: "Cualquier información extra que consideres relevante..."
            )
            
            // Character counter and requirements
            AppealRequirements(characterCount: characterCount)
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
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
                
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    // MARK: - Computed Properties
    private var canSubmit: Bool {
        !contactEmail.isEmpty &&
        contactEmail.contains("@") &&
        characterCount >= 50 &&
        characterCount <= 2000 &&
        !isLoading
    }
    
    // MARK: - Functions
    private func setupInitialData() {
        // Pre-fill email if available
        if let userEmail = authService.currentFirebaseUser?.email {
            contactEmail = userEmail
        }
        
        // Pre-fill message template
        if let reason = suspensionReason {
            appealMessage = """
            Hola,
            
            Mi cuenta ha sido suspendida por: "\(reason)"
            
            Considero que esta suspensión es incorrecta porque:
            
            
            
            Agradezco su revisión de mi caso.
            """
        }
        
        updateCharacterCount()
    }
    
    private func updateCharacterCount() {
        characterCount = appealMessage.trimmingCharacters(in: .whitespacesAndNewlines).count
        
        // Update error state
        if characterCount < 50 && !appealMessage.isEmpty {
            messageError = "Mínimo 50 caracteres (actual: \(characterCount))"
        } else if characterCount > 2000 {
            messageError = "Máximo 2000 caracteres (actual: \(characterCount))"
        } else {
            messageError = nil
        }
    }
    
    private func submitAppeal() {
        guard let userId = authService.currentFirebaseUser?.uid else {
                            showError(title: NSLocalizedString("appeal.error.title", comment: "Error title"), message: NSLocalizedString("appeal.error.userInfo", comment: "Could not get user info"))
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let response = try await appealService.submitAppeal(
                    userId: userId,
                    message: appealMessage,
                    email: contactEmail,
                    additionalInfo: additionalInfo.isEmpty ? nil : additionalInfo
                )
                
                await MainActor.run {
                    isLoading = false
                    if response.success {
                        appealResult = AppealResult(from: response)
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                            showSuccessView = true
                        }
                    } else {
                        showError(title: NSLocalizedString("appeal.error.title", comment: "Error title"), message: response.message ?? NSLocalizedString("appeal.error.unknown", comment: "Unknown error"))
                    }
                }
                
            } catch let error as AppealError {
                await MainActor.run {
                    isLoading = false
                    showError(title: NSLocalizedString("appeal.error.submit", comment: "Error submitting appeal"), message: error.localizedDescription)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    showError(title: NSLocalizedString("appeal.error.unexpected", comment: "Unexpected error"), message: error.localizedDescription)
                }
            }
        }
    }
    
    private func showError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Appeal Form Header
struct AppealFormHeader: View {
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                Image(systemName: "scale.3d")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .white.opacity(glowIntensity), radius: 10, x: 0, y: 0)
            }
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("appeal.title", comment: "Appeal title"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Text(NSLocalizedString("appeal.subtitle", comment: "Appeal subtitle"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            }
        }
        .padding(.top, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

// MARK: - Appeal Form Components
struct AppealEmailField: View {
    @Binding var email: String
    let title: String
    let placeholder: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            TextField(placeholder, text: $email)
                .foregroundColor(.primary)
                .font(.system(size: 16))
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(isFocused ? 0.15 : 0.1))
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.2),
                            lineWidth: isFocused ? 2 : 1
                        )
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                .onTapGesture {
                    isFocused = true
                }
        }
    }
}

struct AppealMessageField: View {
    @Binding var message: String
    @Binding var characterCount: Int
    @Binding var messageError: String?
    let title: String
    let placeholder: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text(String(format: NSLocalizedString("appeal.field.characterCount", comment: "Character count format"), characterCount))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(characterCount < 50 ? .orange : characterCount > 2000 ? .red : .white.opacity(0.6))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isFocused ? 0.15 : 0.1))
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isFocused ? Color.purple.opacity(0.5) : Color.white.opacity(0.2),
                                lineWidth: isFocused ? 2 : 1
                            )
                            .animation(.easeInOut(duration: 0.2), value: isFocused)
                    )
                
                if message.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 16))
                        .padding(16)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $message)
                    .foregroundColor(.primary)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color.clear)
                    .onChange(of: message) { _ in
                        updateCharacterCount()
                    }
                    .onTapGesture {
                        isFocused = true
                    }
            }
            .frame(minHeight: 150)
            
            if let error = messageError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    private func updateCharacterCount() {
        characterCount = message.trimmingCharacters(in: .whitespacesAndNewlines).count
        
        if characterCount < 50 && !message.isEmpty {
            messageError = "Mínimo 50 caracteres (actual: \(characterCount))"
        } else if characterCount > 2000 {
            messageError = "Máximo 2000 caracteres (actual: \(characterCount))"
        } else {
            messageError = nil
        }
    }
}

struct AppealOptionalField: View {
    @Binding var text: String
    let title: String
    let placeholder: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isFocused ? 0.1 : 0.05))
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isFocused ? Color.blue.opacity(0.3) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                            .animation(.easeInOut(duration: 0.2), value: isFocused)
                    )
                
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $text)
                    .foregroundColor(.primary)
                    .font(.system(size: 14))
                    .padding(8)
                    .background(Color.clear)
                    .onTapGesture {
                        isFocused = true
                    }
            }
            .frame(minHeight: 80)
        }
    }
}

struct AppealInfoCard: View {
    let title: String
    let content: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Text(content)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct AppealRequirements: View {
    let characterCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
                
                Text(NSLocalizedString("appeal.requirements", comment: "Requirements title"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                RequirementRow(
                    text: "Mínimo 50 caracteres",
                    isCompleted: characterCount >= 50,
                    icon: characterCount >= 50 ? "checkmark.circle.fill" : "circle"
                )
                
                RequirementRow(
                    text: "Máximo 2000 caracteres",
                    isCompleted: characterCount <= 2000,
                    icon: characterCount <= 2000 ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                
                RequirementRow(
                    text: "Email válido requerido",
                    isCompleted: true, // Se valida dinámicamente
                    icon: "checkmark.circle.fill"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct RequirementRow: View {
    let text: String
    let isCompleted: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isCompleted ? .green : .orange)
            
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
}

// MARK: - Appeal Success View
struct AppealSuccessView: View {
    let result: AppealResult
    let onDismiss: () -> Void
    @State private var isVisible = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Success animation
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 120
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 20)
                    .scaleEffect(pulseScale)
                
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.4), lineWidth: 2)
                    )
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.green)
                    .scaleEffect(isVisible ? 1.0 : 0.5)
            }
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            
            // Success content
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text(NSLocalizedString("appeal.success.title", comment: "Appeal success title"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(result.message)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                
                // Ticket info card
                if let ticketNumber = result.ticketNumber {
                    VStack(spacing: 20) {
                        AppealInfoCard(
                            title: NSLocalizedString("appeal.success.ticketNumber", comment: "Ticket number title"),
                            content: ticketNumber,
                            icon: "ticket.fill",
                            color: .purple
                        )
                        
                        if let responseTime = result.estimatedResponseTime {
                            AppealInfoCard(
                                title: NSLocalizedString("appeal.success.estimatedResponse", comment: "Estimated response time title"),
                                content: responseTime,
                                icon: "clock.fill",
                                color: .blue
                            )
                        }
                        
                        if let priority = result.priority {
                            AppealInfoCard(
                                title: NSLocalizedString("appeal.success.priority", comment: "Assigned priority title"),
                                content: priority.capitalized,
                                icon: "flag.fill",
                                color: priorityColor(for: priority)
                            )
                        }
                    }
                }
                
                // Next steps
                if !result.nextSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.green.opacity(0.8))
                            
                            Text(NSLocalizedString("appeal.nextSteps", comment: "Next steps label"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.nextSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.green.opacity(0.8))
                                    
                                    Text(step)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
            .offset(y: isVisible ? 0 : 30)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3), value: isVisible)
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                    
                    Text(NSLocalizedString("appeal.understood", comment: "Understood button"))
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: .green.opacity(0.3), radius: 15, x: 0, y: 8)
            }
            .padding(.horizontal, 20)
            .offset(y: isVisible ? 0 : 30)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.6), value: isVisible)
        }
        .padding(.horizontal, 20)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                isVisible = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
    
    private func priorityColor(for priority: String) -> Color {
        switch priority.lowercased() {
        case "high":
            return .red
        case "medium":
            return .orange
        case "low":
            return .green
        default:
            return .blue
        }
    }
}

// MARK: - Preview
struct AppealFormView_Previews: PreviewProvider {
    static var previews: some View {
        AppealFormView(
            suspensionReason: "Publicación de contenido inapropiado",
            isPresented: .constant(true)
        )
        .environmentObject(AuthService())
    }
}
