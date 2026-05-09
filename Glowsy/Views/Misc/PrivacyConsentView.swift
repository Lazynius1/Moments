import SwiftUI

// MARK: - Privacy Consent View (Glassmorphism)
// Mismo diseño que el ATTPreAlertView aprobado por usuario
struct PrivacyConsentView: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    // Callback para iniciar el flujo real (UMP -> ATT)
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            // Fondo con blur para focus
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Prevenir cierre accidental
                }
            
            VStack(spacing: 24) {
                // Icono animado/destacado
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.primary)
                }

                VStack(spacing: 16) {
                    // Usando claves de localización existentes que el usuario ya tiene
                    Text(NSLocalizedString("attPreAlert.title", comment: "ATT Pre-Alert title"))
                        .font(.custom("Poppins-SemiBold", size: 20))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    VStack(spacing: 12) {
                        Text(NSLocalizedString("attPreAlert.description", comment: "ATT Pre-Alert description"))
                            .font(.custom("Poppins-Regular", size: 15))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary.opacity(0.7))
                        
                        // Information Box
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                            
                            Text(NSLocalizedString("attPreAlert.info", comment: "ATT Pre-Alert info message"))
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(.primary.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    LiquidGlassButton(
                        title: NSLocalizedString("attPreAlert.continueButton", comment: "ATT Pre-Alert continue button"),
                        icon: nil,
                        action: {
                            isPresented = false
                            // Pequeño retraso para permitir que el fullScreenCover se cierre
                            // antes de que UMP intente mostrar su propio diálogo
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onContinue()
                            }
                        },
                        style: .primary
                    )
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 30)
            .background {
                Color.clear
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 15)
            .padding(.horizontal, 30)
        }
    }
}
