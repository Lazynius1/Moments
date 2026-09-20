import SwiftUI

private struct SettingsSplitBackActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var settingsSplitBackAction: (() -> Void)? {
        get { self[SettingsSplitBackActionKey.self] }
        set { self[SettingsSplitBackActionKey.self] = newValue }
    }
}

private struct SettingsSidebarBackIsVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsSidebarBackIsVisible: Bool {
        get { self[SettingsSidebarBackIsVisibleKey.self] }
        set { self[SettingsSidebarBackIsVisibleKey.self] = newValue }
    }
}

struct SettingsToolbarBackButton: View {
    @Environment(\.settingsSplitBackAction) private var splitBackAction
    @Environment(\.settingsSidebarBackIsVisible) private var sidebarBackIsVisible
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if !sidebarBackIsVisible {
            Button(action: splitBackAction ?? action) {
                Image(systemName: "chevron.backward")
            }
            .accessibilityLabel(Text("common.back"))
        } else {
            EmptyView()
        }
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
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
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
        .settingsSubsectionNavigationChrome()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
    }
}

extension View {
    /// Canvas + fix del bloque sólido que NavigationStack pinta bajo la toolbar en subsecciones.
    func settingsSubsectionNavigationChrome(colorScheme: ColorScheme? = nil) -> some View {
        modifier(SettingsSubsectionNavigationChromeModifier(colorScheme: colorScheme))
    }
}

private struct SettingsSubsectionNavigationChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var environmentColorScheme
    let colorScheme: ColorScheme?

    private var resolvedColorScheme: ColorScheme {
        colorScheme ?? environmentColorScheme
    }

    func body(content: Content) -> some View {
        content
            .momentZoomNavigationSurface(colorScheme: resolvedColorScheme)
            .profileGridNavigationChrome(colorScheme: resolvedColorScheme)
            .navigationBarBackButtonHidden(true)
            .navigationInteractivePopEnabled()
            .toolbarBackground(.hidden, for: .navigationBar)
            // iOS 27 default hard → soft tipo 26 bajo la toolbar transparente.
            .momentsScrollEdgeChrome()
            // Subsecciones (Tu actividad, etc.): no devolver la floating tab bar al hacer push.
            .momentsFloatingTabBarHidden()
    }
}
