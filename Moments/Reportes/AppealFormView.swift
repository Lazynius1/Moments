import SwiftUI

struct AppealFormView: View {
    let suspensionReason: String?
    @Binding var isPresented: Bool
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) private var colorScheme
    
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
                Color.clear.ignoresSafeArea()
                
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
            .toolbar(.hidden, for: .navigationBar)
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
            VStack(spacing: 26) {
                AppealSheetHeader(
                    canSubmit: canSubmit,
                    isLoading: isLoading,
                    dismiss: { isPresented = false },
                    submit: submitAppeal
                )
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)

                AppealFormHeader()
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isVisible)

                formFields
                    .offset(y: isVisible ? 0 : 30)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: isVisible)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
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
                placeholder: NSLocalizedString("appeal.yourAppeal.placeholder", comment: "Appeal message placeholder")
            )
            
            // Additional info (optional)
            AppealOptionalField(
                text: $additionalInfo,
                title: NSLocalizedString("appeal.additionalInfo", comment: "Additional info field title"),
                placeholder: NSLocalizedString("appeal.additionalInfo.placeholder", comment: "Additional appeal information placeholder")
            )
            
            // Character counter and requirements
            AppealRequirements(characterCount: characterCount, email: contactEmail)
        }
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
private struct AppealSheetHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let canSubmit: Bool
    let isLoading: Bool
    let dismiss: () -> Void
    let submit: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                        .frame(width: 38, height: 38)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }

                Spacer()

                Button(action: submit) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AuthColors.primary(colorScheme)))
                            .scaleEffect(0.8)
                            .frame(width: 84, height: 38)
                    } else {
                        Text(NSLocalizedString("appeal.submitButton", comment: "Submit appeal button"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(canSubmit ? AuthColors.primary(colorScheme) : AuthColors.secondary(colorScheme, opacity: 0.42))
                            .frame(height: 38)
                            .padding(.horizontal, 14)
                    }
                }
                .background {
                    Color.clear
                        .liquidGlass(in: Capsule(), interactive: canSubmit && !isLoading)
                }
                .disabled(!canSubmit || isLoading)
            }
        }
    }
}

struct AppealFormHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scale.3d")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(AuthColors.primary(colorScheme))
            
            VStack(spacing: 12) {
                Text(NSLocalizedString("appeal.title", comment: "Appeal title"))
                    .font(.custom("Poppins-Bold", size: 26))
                    .foregroundColor(AuthColors.primary(colorScheme))
                
                Text(NSLocalizedString("appeal.subtitle", comment: "Appeal subtitle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.top, 10)
    }
}

// MARK: - Appeal Form Components
struct AppealEmailField: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var email: String
    let title: String
    let placeholder: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
            }
            
            TextField(placeholder, text: $email)
                .foregroundColor(AuthColors.primary(colorScheme))
                .font(.system(size: 16))
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(16)
                .background(
                    Color.clear
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AuthColors.subtle(colorScheme, opacity: isFocused ? 0.28 : 0.12), lineWidth: isFocused ? 1.4 : 0.8)
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                )
                .onTapGesture {
                    isFocused = true
                }
        }
    }
}

struct AppealMessageField: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                
                Spacer()
                
                Text(String(format: NSLocalizedString("appeal.field.characterCount", comment: "Character count format"), characterCount))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(characterCount < 50 ? .orange : characterCount > 2000 ? .red : AuthColors.secondary(colorScheme, opacity: 0.62))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .frame(minHeight: 150)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AuthColors.subtle(colorScheme, opacity: isFocused ? 0.28 : 0.12), lineWidth: isFocused ? 1.4 : 0.8)
                            .animation(.easeInOut(duration: 0.2), value: isFocused)
                    )
                
                if message.isEmpty {
                    Text(placeholder)
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.48))
                        .font(.system(size: 16))
                        .padding(16)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $message)
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .onChange(of: message) { _, _ in
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
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let title: String
    let placeholder: String
    @State private var isFocused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.68))
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.68))
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .frame(minHeight: 80)
                    .background {
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AuthColors.subtle(colorScheme, opacity: isFocused ? 0.24 : 0.1), lineWidth: 0.8)
                            .animation(.easeInOut(duration: 0.2), value: isFocused)
                    )
                
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.46))
                        .font(.system(size: 14))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $text)
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .font(.system(size: 14))
                    .padding(8)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                    .onTapGesture {
                        isFocused = true
                    }
            }
            .frame(minHeight: 80)
        }
    }
}

struct AppealInfoCard: View {
    @Environment(\.colorScheme) private var colorScheme
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
                    .foregroundColor(AuthColors.primary(colorScheme))
            }
            
            Text(content)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(colorScheme == .dark ? 0.24 : 0.18), lineWidth: 0.8)
                        .allowsHitTesting(false)
                )
        )
    }
}

struct AppealRequirements: View {
    @Environment(\.colorScheme) private var colorScheme
    let characterCount: Int
    let email: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue.opacity(0.8))
                
                Text(NSLocalizedString("appeal.requirements", comment: "Requirements title"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuthColors.primary(colorScheme))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                RequirementRow(
                    text: "Mínimo 50 caracteres",
                    isCompleted: characterCount >= 50,
                    icon: characterCount >= 50 ? "checkmark.circle.fill" : "circle"
                )
                
                RequirementRow(
                    text: "Máximo 2000 caracteres",
                    isCompleted: characterCount > 0 && characterCount <= 2000,
                    icon: characterCount > 0 && characterCount <= 2000 ? "checkmark.circle.fill" : characterCount > 2000 ? "xmark.circle.fill" : "circle"
                )
                
                RequirementRow(
                    text: "Email válido requerido",
                    isCompleted: email.contains("@"),
                    icon: email.contains("@") ? "checkmark.circle.fill" : "circle"
                )
            }
        }
        .padding(16)
        .background(
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
    }
}

struct RequirementRow: View {
    @Environment(\.colorScheme) private var colorScheme
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
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
            
            Spacer()
        }
    }
}

// MARK: - Appeal Success View
struct AppealSuccessView: View {
    @Environment(\.colorScheme) private var colorScheme
    let result: AppealResult
    let onDismiss: () -> Void
    @State private var isVisible = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.green)
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text(NSLocalizedString("appeal.success.title", comment: "Appeal success title"))
                        .font(.custom("Poppins-Bold", size: 28))
                        .foregroundColor(AuthColors.primary(colorScheme))
                        .multilineTextAlignment(.center)
                    
                    Text(result.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.74))
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
                                .foregroundColor(AuthColors.primary(colorScheme))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.nextSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.green.opacity(0.8))
                                    
                                    Text(step)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.76))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        Color.clear
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
                }
            }
            .offset(y: isVisible ? 0 : 30)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3), value: isVisible)
            
            Spacer()
            
            LiquidGlassButton(
                title: NSLocalizedString("appeal.understood", comment: "Understood button"),
                icon: "checkmark.circle",
                action: onDismiss
            )
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
