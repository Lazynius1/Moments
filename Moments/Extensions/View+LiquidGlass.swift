import SwiftUI

// MARK: - Liquid Glass variants
enum LiquidGlassVariant {
    case clear
    case identity
    case regular
}

// Intención del chrome glass: `tinted` mantiene el tint de canvas (legibilidad
// sobre contenido/media). `native` usa `.regular` limpio para igualar el chrome
// del sistema donde el glass se apoya sobre nuestro propio canvas. `nativeTinted`
// es un punto intermedio: mismo `.regular` del sistema con un toque de tint sutil,
// para sitios que quieren leer "de sistema" sin perder por completo la identidad.
enum MomentsGlassStyle {
    case tinted
    case native
    case nativeTinted
}

enum MomentsGlassControlMetrics {
    static let navigationControlSize: CGFloat = 40
    static let navigationChevronIconSize: CGFloat = 19
    static let toolbarControlSize: CGFloat = 38
    static let toolbarIconSize: CGFloat = 18
    static let compactControlSize: CGFloat = 36
    static let compactIconSize: CGFloat = 17
    static let controlsClusterSpacing: CGFloat = 2
    static let controlsClusterPadding: CGFloat = 4
    static let pillBarHeight: CGFloat = 38
    static let pillSegmentHeight: CGFloat = 28
    static let pillInnerPadding: CGFloat = 4
    static let pillLabelSize: CGFloat = 11
    static let pillIconSize: CGFloat = 11
    static let chromeBackdropFadeTail: CGFloat = 44
    static let chromeBackdropMaxBlurFraction: CGFloat = 0.1
    static let feedDetailBlurFadeTail: CGFloat = 28
    static let chatChromeBlurFadeTail: CGFloat = 22
    static let chatChromeBlurFadeTailExpanded: CGFloat = 30
}

enum MomentsGlassButtonPreset {
    case navigationBack
    case toolbarAction
    case compactChrome

    var controlSize: CGFloat {
        switch self {
        case .navigationBack:
            MomentsGlassControlMetrics.navigationControlSize
        case .toolbarAction:
            MomentsGlassControlMetrics.toolbarControlSize
        case .compactChrome:
            MomentsGlassControlMetrics.compactControlSize
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .navigationBack:
            MomentsGlassControlMetrics.navigationChevronIconSize
        case .toolbarAction:
            MomentsGlassControlMetrics.toolbarIconSize
        case .compactChrome:
            MomentsGlassControlMetrics.compactIconSize
        }
    }
}

enum ProfileChromeGlassMetrics {
    static let controlSize: CGFloat = MomentsGlassControlMetrics.compactControlSize
    static let controlIconSize: CGFloat = MomentsGlassControlMetrics.compactIconSize
    static let controlsClusterSpacing: CGFloat = MomentsGlassControlMetrics.controlsClusterSpacing
    static let controlsClusterPadding: CGFloat = MomentsGlassControlMetrics.controlsClusterPadding
    static let pillBarHeight: CGFloat = MomentsGlassControlMetrics.pillBarHeight
    static let pillSegmentHeight: CGFloat = MomentsGlassControlMetrics.pillSegmentHeight
    static let pillInnerPadding: CGFloat = MomentsGlassControlMetrics.pillInnerPadding
    static let pillLabelSize: CGFloat = MomentsGlassControlMetrics.pillLabelSize
    static let pillIconSize: CGFloat = MomentsGlassControlMetrics.pillIconSize
    static let chromeBackdropFadeTail: CGFloat = MomentsGlassControlMetrics.chromeBackdropFadeTail
    static let chromeBackdropMaxBlurFraction: CGFloat = MomentsGlassControlMetrics.chromeBackdropMaxBlurFraction
    static let feedDetailBlurFadeTail: CGFloat = MomentsGlassControlMetrics.feedDetailBlurFadeTail
    static let chatChromeBlurFadeTail: CGFloat = MomentsGlassControlMetrics.chatChromeBlurFadeTail
    static let chatChromeBlurFadeTailExpanded: CGFloat = MomentsGlassControlMetrics.chatChromeBlurFadeTailExpanded
}

/// Tint de botones glass alineado al canvas de la app.
enum MomentsGlassButtonTint {
    static let dark = Color(hex: "0B1215")
    static let light = Color(hex: "FAF9F6")

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? dark : light
    }
}

// MARK: - Chrome glass tokens

enum MomentsChromeGlass {
    static let defaultTintOpacity: CGFloat = 0.60
    // El canvas negro se lee más translúcido/débil que el blanco al mismo % de opacidad;
    // se refuerza solo el default de dark para igualar la presencia visual del tint claro.
    static let defaultDarkTintOpacity: CGFloat = 0.82
    // Multiplicador sobre el tint ya resuelto (tintOverride o canvasTint) para `.nativeTinted`.
    static let nativeTintedOpacityScale: CGFloat = 0.45

    static func canvasTint(for colorScheme: ColorScheme, opacity: CGFloat = defaultTintOpacity) -> Color {
        let resolvedOpacity = (colorScheme == .dark && opacity == defaultTintOpacity)
            ? defaultDarkTintOpacity
            : opacity
        return MomentsGlassButtonTint.canvas(for: colorScheme).opacity(resolvedOpacity)
    }

    static func contentColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : MomentsGlassButtonTint.dark
    }

    /// Fill detrás de `Glass.clear` cuando se use ese estilo.
    static func underlayOpacity(forTintOpacity tintOpacity: CGFloat) -> CGFloat {
        if #available(iOS 27.0, *) {
            return tintOpacity * 0.42
        }
        return tintOpacity
    }

    @available(iOS 26.0, *)
    static func chromeGlass(interactive: Bool, tint: Color) -> Glass {
        var glass = Glass.regular.tint(tint)
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    @available(iOS 26.0, *)
    static func clearChromeGlass(interactive: Bool, tint: Color) -> Glass {
        var glass = Glass.clear.tint(tint)
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    // `.regular` sin tint: look nativo del sistema.
    @available(iOS 26.0, *)
    static func nativeGlass(interactive: Bool) -> Glass {
        interactive ? Glass.regular.interactive() : Glass.regular
    }
}

enum ProfilePillTabPalette {
    /// Pista exterior: canvas de la app (#FAF9F6 light / #0B1215 dark).
    static func trackTint(for colorScheme: ColorScheme) -> Color {
        MomentsChromeGlass.canvasTint(for: colorScheme)
    }

    /// Thumb seleccionado: canvas invertido para contrastar con la pista.
    static func selectedThumbTint(for colorScheme: ColorScheme) -> Color {
        invertedCanvas(for: colorScheme).opacity(MomentsChromeGlass.defaultTintOpacity)
    }

    /// Texto sobre el thumb (invertido respecto al thumb, no al fondo de app).
    static func selectedLabelColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? MomentsGlassButtonTint.dark : MomentsGlassButtonTint.light
    }

    static func unselectedLabelColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45)
    }

    static func selectedShadowColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.12)
    }

    private static func invertedCanvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? MomentsGlassButtonTint.light : MomentsGlassButtonTint.dark
    }
}

// MARK: - Liquid Glass helper
// Aplica .glassEffect() nativo en iOS 26+ y .ultraThinMaterial como fallback en iOS 17.6+
extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        variant: LiquidGlassVariant = .regular,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26.0, *) {
            switch variant {
            case .clear:
                if interactive {
                    self.glassEffect(glassStyle(.clear, interactive: true, tint: tint), in: shape)
                } else {
                    self.glassEffect(glassStyle(.clear, interactive: false, tint: tint), in: shape)
                }
            case .identity:
                if interactive {
                    self.glassEffect(glassStyle(.identity, interactive: true, tint: tint), in: shape)
                } else {
                    self.glassEffect(glassStyle(.identity, interactive: false, tint: tint), in: shape)
                }
            case .regular:
                if interactive {
                    self.glassEffect(glassStyle(.regular, interactive: true, tint: tint), in: shape)
                } else {
                    self.glassEffect(glassStyle(.regular, interactive: false, tint: tint), in: shape)
                }
            }
        } else {
            self
                .background {
                    if let tint {
                        shape.fill(tint.opacity(0.92))
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(shape)
        }
    }

    @available(iOS 26.0, *)
    private func glassStyle(_ variant: LiquidGlassVariant, interactive: Bool, tint: Color?) -> Glass {
        var glass: Glass = switch variant {
        case .clear: .clear
        case .identity: .identity
        case .regular: .regular
        }
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    func momentsChromeGlass<S: Shape>(
        in shape: S,
        interactive: Bool = true,
        style: MomentsGlassStyle = .native,
        tintOpacity: CGFloat = MomentsChromeGlass.defaultTintOpacity,
        tint: Color? = nil
    ) -> some View {
        modifier(
            MomentsChromeGlassModifier(
                shape: shape,
                interactive: interactive,
                style: style,
                tintOpacity: tintOpacity,
                tintOverride: tint
            )
        )
    }
}

private struct MomentsChromeGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    var interactive: Bool
    var style: MomentsGlassStyle = .tinted
    var tintOpacity: CGFloat
    var tintOverride: Color?

    private var resolvedTint: Color {
        tintOverride ?? MomentsChromeGlass.canvasTint(for: colorScheme, opacity: tintOpacity)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .tinted:
                content
                    .glassEffect(
                        MomentsChromeGlass.chromeGlass(interactive: interactive, tint: resolvedTint),
                        in: shape
                    )
            case .native:
                content
                    .glassEffect(
                        MomentsChromeGlass.nativeGlass(interactive: interactive),
                        in: shape
                    )
            case .nativeTinted:
                content
                    .glassEffect(
                        MomentsChromeGlass.chromeGlass(
                            interactive: interactive,
                            tint: resolvedTint.opacity(MomentsChromeGlass.nativeTintedOpacityScale)
                        ),
                        in: shape
                    )
            }
        } else {
            content
                .background {
                    switch style {
                    case .tinted:
                        shape.fill(resolvedTint)
                    case .nativeTinted:
                        shape.fill(resolvedTint.opacity(MomentsChromeGlass.nativeTintedOpacityScale))
                    case .native:
                        EmptyView()
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(shape)
        }
    }
}

// MARK: - Profile chrome controls

struct ProfileChromeIconGlassModifier: ViewModifier {
    let standalone: Bool
    var interactive: Bool = true
    var tintOpacity: CGFloat = MomentsChromeGlass.defaultTintOpacity
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if standalone {
            content.momentsChromeGlass(
                in: Circle(),
                interactive: interactive,
                tintOpacity: tintOpacity,
                tint: tint
            )
        } else {
            content
        }
    }
}

private struct ProfileChromeClusterBackground: View {
    var body: some View {
        Color.clear
            .momentsChromeGlass(in: Capsule(), interactive: true)
    }
}

struct ProfileChromeControlsCluster<Content: View>: View {
    var spacing: CGFloat = ProfileChromeGlassMetrics.controlsClusterSpacing
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    HStack(spacing: spacing) {
                        content()
                    }
                }
                .padding(ProfileChromeGlassMetrics.controlsClusterPadding)
                .background {
                    ProfileChromeClusterBackground()
                }
            } else {
                HStack(spacing: 8) {
                    content()
                }
                .padding(ProfileChromeGlassMetrics.controlsClusterPadding)
                .background {
                    ProfileChromeClusterBackground()
                }
            }
        }
    }
}

typealias MomentsGlassCluster = ProfileChromeControlsCluster

struct ProfileChromeIconButton: View {
    let systemName: String
    var foregroundColor: Color?
    var preset: MomentsGlassButtonPreset? = nil
    var size: CGFloat = ProfileChromeGlassMetrics.controlSize
    var iconSize: CGFloat = ProfileChromeGlassMetrics.controlIconSize
    var standaloneGlass: Bool = true
    var tint: Color? = nil
    var accessibilityLabelText: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var resolvedForegroundColor: Color {
        foregroundColor ?? MomentsChromeGlass.contentColor(for: colorScheme)
    }

    private var resolvedSize: CGFloat {
        preset?.controlSize ?? size
    }

    private var resolvedIconSize: CGFloat {
        preset?.iconSize ?? iconSize
    }

    private var resolvedAccessibilityLabel: String {
        if let accessibilityLabelText, !accessibilityLabelText.isEmpty {
            return accessibilityLabelText
        }
        switch systemName {
        case "chevron.left":
            return NSLocalizedString("common.back", comment: "Back")
        case "xmark", "xmark.circle.fill":
            return NSLocalizedString("common.close", comment: "Close")
        case "square.and.pencil", "plus.message", "plus.bubble":
            return NSLocalizedString("messaging.newConversation", comment: "New conversation")
        default:
            return systemName
                .replacingOccurrences(of: ".fill", with: "")
                .replacingOccurrences(of: ".", with: " ")
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: resolvedIconSize, weight: .semibold))
                .foregroundStyle(resolvedForegroundColor)
                .frame(width: resolvedSize, height: resolvedSize)
                .modifier(
                    ProfileChromeIconGlassModifier(
                        standalone: standaloneGlass,
                        interactive: true,
                        tint: tint
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.momentsPressIcon)
        .accessibilityLabel(resolvedAccessibilityLabel)
    }
}

typealias MomentsGlassIconButton = ProfileChromeIconButton

struct ProfileGlassPillTrack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content()
                    .padding(ProfileChromeGlassMetrics.pillInnerPadding)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Capsule(), interactive: false)
                    }
            } else {
                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .momentsChromeGlass(in: Capsule(), interactive: false)
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.07), lineWidth: 0.75)
                        )
                    content()
                        .padding(ProfileChromeGlassMetrics.pillInnerPadding)
                }
            }
        }
    }
}

typealias MomentsGlassPillBar = ProfileGlassPillTrack

struct ProfileGlassPillThumb: View {
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.035))
            .frame(width: width, height: ProfileChromeGlassMetrics.pillSegmentHeight)
            .momentsChromeGlass(in: Capsule(), interactive: true)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.07), radius: 5, x: 0, y: 2)
    }
}

/// Fondo chrome unificado para la tab bar principal (legacy + iOS 26 toolbar).
struct MomentsTabBarChromeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.clear)
            .momentsChromeGlass(in: Rectangle(), interactive: false)
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(
                        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
                    )
            }
            .ignoresSafeArea(edges: .bottom)
    }
}
