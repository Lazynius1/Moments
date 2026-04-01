import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var appearAnimation = false

    var body: some View {
        ScreenshotProtectedView(isProtected: true) {
        ZStack {
            // 1. Capa de Fondo Base
            if colorScheme == .dark {
                Color.black.ignoresSafeArea()
            } else {
                Color.white.ignoresSafeArea()
            }

            // 2. Orbes decorativos ambientales
            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .fill(Color(hex: "4F46E5").opacity(colorScheme == .dark ? 0.25 : 0.1))
                        .frame(width: geometry.size.width * 0.8)
                        .blur(radius: 80)
                        .offset(x: -geometry.size.width * 0.2, y: -geometry.size.height * 0.1)

                    Circle()
                        .fill(Color(hex: "9333EA").opacity(colorScheme == .dark ? 0.25 : 0.1))
                        .frame(width: geometry.size.width * 0.7)
                        .blur(radius: 70)
                        .offset(x: geometry.size.width * 0.5, y: geometry.size.height * 0.6)
                }
            }
            .ignoresSafeArea()

            // 3. Efecto Glassmorphic Principal
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            // 4. Contenido
            VStack(spacing: 0) {
                // Header con Logo y Título
                VStack(spacing: 20) {
                    Image("LoginLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .shadow(color: Color(hex: "4F46E5").opacity(0.4), radius: 20, x: 0, y: 0)
                        .scaleEffect(appearAnimation ? 1.0 : 0.6)
                        .opacity(appearAnimation ? 1.0 : 0.0)

                    VStack(spacing: 8) {
                        Text(NSLocalizedString("whatsNew.title", comment: ""))
                            .font(.custom("Poppins-Bold", size: 30))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "4F46E5"), Color(hex: "9333EA")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text(NSLocalizedString("whatsNew.subtitle", comment: ""))
                            .font(.custom("Poppins-Medium", size: 17))
                            .foregroundColor(.secondary)
                    }
                    .offset(y: appearAnimation ? 0 : 20)
                    .opacity(appearAnimation ? 1.0 : 0.0)
                }
                .padding(.top, 40)
                .padding(.bottom, 30)

                // Lista de novedades
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {

                        WhatsNewFeatureRow(
                            icon: "wand.and.stars.inverse",
                            color: Color(hex: "4F46E5"),
                            title: NSLocalizedString("whatsNew.blackout.title", comment: ""),
                            description: NSLocalizedString("whatsNew.blackout.description", comment: ""),
                            delay: 0.1
                        )

                        WhatsNewFeatureRow(
                            icon: "slider.horizontal.below.rectangle",
                            color: Color(hex: "0EA5E9"),
                            title: NSLocalizedString("whatsNew.activity.title", comment: ""),
                            description: NSLocalizedString("whatsNew.activity.description", comment: ""),
                            delay: 0.2
                        )

                        WhatsNewFeatureRow(
                            icon: "square.grid.2x2.fill",
                            color: Color(hex: "F59E0B"),
                            title: NSLocalizedString("whatsNew.archive.title", comment: ""),
                            description: NSLocalizedString("whatsNew.archive.description", comment: ""),
                            delay: 0.3
                        )

                        WhatsNewFeatureRow(
                            icon: "person.crop.circle.badge.checkmark",
                            color: Color(hex: "EC4899"),
                            title: NSLocalizedString("whatsNew.notifications.title", comment: ""),
                            description: NSLocalizedString("whatsNew.notifications.description", comment: ""),
                            delay: 0.4
                        )

                        WhatsNewFeatureRow(
                            icon: "paintpalette.fill",
                            color: Color(hex: "10B981"),
                            title: NSLocalizedString("whatsNew.privacy.title", comment: ""),
                            description: NSLocalizedString("whatsNew.privacy.description", comment: ""),
                            delay: 0.5
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }

                // footer con botón
                VStack(spacing: 0) {
                    Button(action: {
                        withAnimation { dismiss() }
                    }) {
                        Text(NSLocalizedString("whatsNew.button", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 17))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "4F46E5"), Color(hex: "9333EA")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color(hex: "4F46E5").opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                }
                .padding(24)
                .background(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(colorScheme == .dark ? 0.7 : 0.55)
                        .blur(radius: 20)
                )
                .offset(y: appearAnimation ? 0 : 20)
                .opacity(appearAnimation ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
                appearAnimation = true
            }
        }
        } // end ScreenshotProtectedView
    }
}



// MARK: - Fila estándar

struct WhatsNewFeatureRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let color: Color
    let title: String
    let description: String
    let delay: Double
    @State private var appear = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 17))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: appear ? 0 : 50)
        .opacity(appear ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(delay)) {
                appear = true
            }
        }
    }
}

#Preview {
    WhatsNewView()
}
