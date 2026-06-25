import SwiftUI

// MARK: - Demostración de Temas de Perfil
struct ProfileThemeDemo: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTheme: ProfileTheme = .default
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fondo con el tema seleccionado
                selectedTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Text("Demostración de Temas")
                            .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("Prueba los diferentes temas de perfil")
                            .font(.system(size: legacyPoppinsSize(16)))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Vista previa del perfil
                    ProfilePreviewCard(theme: selectedTheme)
                        .frame(height: 200)
                        .padding(.horizontal, 20)
                    
                    // Selector de temas
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(ProfileTheme.allCases, id: \.self) { theme in
                                ThemeCard(
                                    theme: theme,
                                    isSelected: selectedTheme == theme,
                                    isAvailable: true
                                ) {
                                    selectedTheme = theme
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Información del tema
                    VStack(spacing: 8) {
                        Text("Tema: \(selectedTheme.displayName)")
                            .font(.system(size: legacyPoppinsSize(18), weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(selectedTheme.description)
                            .font(.system(size: legacyPoppinsSize(14)))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        if let price = selectedTheme.price {
                            Text("Precio: \(price)")
                                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        // Cerrar la vista
                    }
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
}

// MARK: - Vista previa del perfil para demo
struct DemoProfilePreviewCard: View {
    let theme: ProfileTheme
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Fondo con el tema
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    colorScheme == .dark ? 
                    theme.darkBackgroundGradient : 
                    theme.backgroundGradient
                )
            
            VStack(spacing: 12) {
                // Avatar simulado
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    )
                
                // Nombre simulado
                Text("Usuario Demo")
                    .font(.system(size: legacyPoppinsSize(18), weight: .bold))
                    .foregroundColor(.white)
                
                // Badge simulado
                HStack(spacing: 8) {
                    Text(theme.emoji)
                        .font(.system(size: 20))
                    
                    Text(theme.displayName)
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(.white.opacity(0.2))
                )
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    ProfileThemeDemo()
} 