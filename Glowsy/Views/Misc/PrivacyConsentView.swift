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
                        .fill(Color(hex: "00A896").opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 16) {
                    // Usando claves de localización existentes que el usuario ya tiene
                    Text(NSLocalizedString("attPreAlert.title", comment: "ATT Pre-Alert title"))
                        .font(.custom("Poppins-SemiBold", size: 20))
                        .multilineTextAlignment(.center)
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    VStack(spacing: 12) {
                        Text(NSLocalizedString("attPreAlert.description", comment: "ATT Pre-Alert description"))
                            .font(.custom("Poppins-Regular", size: 15))
                            .multilineTextAlignment(.center)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        
                        // Information Box
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "00A896"))
                            
                            Text(NSLocalizedString("attPreAlert.info", comment: "ATT Pre-Alert info message"))
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "00A896").opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "00A896").opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        isPresented = false
                        // Iniciar flujo unificado
                        onContinue()
                    } label: {
                        Text(NSLocalizedString("attPreAlert.continueButton", comment: "ATT Pre-Alert continue button"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color(hex: "00A896"))
                            )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color(hex: "00A896").opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 30)
        }
    }
}
