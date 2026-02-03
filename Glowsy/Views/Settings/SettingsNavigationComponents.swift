import SwiftUI

// ✅ Componente de navegación reutilizable para subsecciones
struct SettingsNavigationBar: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    let title: String
    
    var body: some View {
        HStack {
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "00A896"))
                }
            }
            
            Spacer()
            
            Text(title)
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            // Espacio para mantener el título centrado
            Circle()
                .fill(.clear)
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// ✅ Fondo moderno reutilizable para subsecciones (ahora negro sólido en dark mode)
struct SettingsSubsectionBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color(hex: "f8f9fa")
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.02 : 0.02)
        }
        .ignoresSafeArea()
    }
}

// ✅ Wrapper para subsecciones con navegación consistente
struct SettingsSubsectionWrapper<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            SettingsSubsectionBackground()
            
            VStack(spacing: 0) {
                SettingsNavigationBar(title: title)
                    .padding(.top, 8)
                
                content
            }
        }
        .navigationBarHidden(true)
    }
} 