import SwiftUI
import FirebaseAuth

// MARK: - Selector de Temas de Perfil
struct ProfileThemeSelector: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedTheme: ProfileTheme
    @State private var isUpdating = false
    
    private let user: AppUser
    
    init(user: AppUser) {
        self.user = user
        self._selectedTheme = State(initialValue: user.currentProfileTheme)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fondo con el tema seleccionado
                selectedTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Text("Tema del Perfil")
                            .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("Personaliza el fondo de tu perfil")
                            .font(.system(size: legacyPoppinsSize(16)))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Vista previa del perfil mejorada
                    EnhancedProfilePreviewCard(theme: selectedTheme)
                        .frame(height: 200)
                        .padding(.horizontal, 20)
                    
                    // Lista de temas disponibles
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(user.availableProfileThemes, id: \.self) { theme in
                                ThemeCard(
                                    theme: theme,
                                    isSelected: selectedTheme == theme,
                                    isAvailable: theme.isAvailableForUser(user)
                                ) {
                                    selectedTheme = theme
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Botón de guardar
                    Button(action: saveTheme) {
                        HStack {
                            if isUpdating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                            }
                            
                            Text(isUpdating ? "Guardando..." : "Guardar Tema")
                                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(selectedTheme.colors.first ?? .blue)
                        )
                        .disabled(isUpdating)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
    
    private func saveTheme() {
        isUpdating = true
        
        authService.updateUserField("selectedProfileTheme", value: selectedTheme.rawValue) { success in
            DispatchQueue.main.async {
                isUpdating = false
                if success {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Tarjeta de Vista Previa del Perfil
struct ProfilePreviewCard: View {
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
                Text("Tu Perfil")
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

// MARK: - Tarjeta de Tema
struct ThemeCard: View {
    let theme: ProfileTheme
    let isSelected: Bool
    let isAvailable: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Vista previa del gradiente
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        colorScheme == .dark ? 
                        theme.darkBackgroundGradient : 
                        theme.backgroundGradient
                    )
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(
                                isSelected ? Color.white : Color.clear,
                                lineWidth: 3
                            )
                    )
                    .overlay(
                        // Indicador de selección
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(.black.opacity(0.3))
                                            .frame(width: 30, height: 30)
                                    )
                            }
                        }
                    )
                
                // Información del tema
                VStack(spacing: 4) {
                    HStack {
                        Text(theme.emoji)
                            .font(.system(size: 16))
                        
                        Text(theme.displayName)
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    Text(theme.description)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    // Precio si aplica
                    if let price = theme.price {
                        Text(price)
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isSelected ? Color.blue : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1.0 : 0.5)
    }
}

// MARK: - Extensión para obtener colores del tema
extension ProfileTheme {
    var colors: [Color] {
        switch self {
        case .default: return [.blue, .purple]
        case .supporter: return [.red, .pink]
        case .earlyAdopter: return [.blue, .purple]
        case .champion: return [.yellow, .orange]
        case .vip: return [.purple, .indigo]
        case .plus: return [.yellow, .orange]
        }
    }
} 