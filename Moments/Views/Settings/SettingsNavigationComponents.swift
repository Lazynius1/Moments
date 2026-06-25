import SwiftUI

struct SettingsToolbarBackButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void

    var body: some View {
        ProfileChromeIconButton(
            systemName: "chevron.left",
            foregroundColor: colorScheme == .dark ? .white : .black,
            preset: .navigationBack,
            standaloneGlass: false,
            action: action
        )
    }
}

// ✅ Componente de navegación reutilizable para subsecciones
struct SettingsNavigationBar: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    let title: String
    
    var body: some View {
        HStack {
            SettingsToolbarBackButton(action: { dismiss() })
            
            Spacer()
            
            Text(title)
                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            // Espacio para mantener el título centrado
            Rectangle()
                .fill(.clear)
                .frame(
                    width: MomentsGlassButtonPreset.navigationBack.controlSize,
                    height: MomentsGlassButtonPreset.navigationBack.controlSize
                )
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
    }
}
