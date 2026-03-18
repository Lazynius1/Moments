import SwiftUI

// ✅ Componente de navegación reutilizable para subsecciones
struct SettingsNavigationBar: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    let title: String
    
    var body: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text(title)
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            // Espacio para mantener el título centrado
            Rectangle()
                .fill(.clear)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

// ✅ Fondo moderno reutilizable para subsecciones (ahora negro sólido en dark mode)
struct SettingsSubsectionBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color(hex: "0B1215")
            } else {
                Color(hex: "FAF9F6")
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
    @Environment(\.dismiss) var dismiss
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            SettingsSubsectionBackground()
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }
} 
