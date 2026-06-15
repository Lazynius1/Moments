import SwiftUI

// MARK: - Liquid Glass variants
enum LiquidGlassVariant {
    case clear
    case identity
    case regular
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

enum ProfilePillTabPalette {
    /// Instagram: en light el thumb seleccionado es #0B1215; en dark es crema #FAF9F6.
    static func selectedThumbFill(for colorScheme: ColorScheme) -> Color {
        invertedCanvas(for: colorScheme).opacity(colorScheme == .dark ? 0.84 : 0.97)
    }

    static func selectedThumbTint(for colorScheme: ColorScheme) -> Color {
        invertedCanvas(for: colorScheme).opacity(colorScheme == .dark ? 0.58 : 0.82)
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
}

// MARK: - Profile chrome controls

struct ProfileChromeIconGlassModifier: ViewModifier {
    let standalone: Bool
    var variant: LiquidGlassVariant = .regular
    var interactive: Bool = true

    func body(content: Content) -> some View {
        if standalone {
            content.liquidGlass(in: Circle(), variant: variant, interactive: interactive)
        } else {
            content
        }
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
                    Capsule()
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
            } else {
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }
}

typealias MomentsGlassCluster = ProfileChromeControlsCluster

struct ProfileChromeIconButton: View {
    let systemName: String
    let foregroundColor: Color
    var preset: MomentsGlassButtonPreset? = nil
    var size: CGFloat = ProfileChromeGlassMetrics.controlSize
    var iconSize: CGFloat = ProfileChromeGlassMetrics.controlIconSize
    var standaloneGlass: Bool = true
    var glassVariant: LiquidGlassVariant = .regular
    let action: () -> Void

    private var resolvedSize: CGFloat {
        preset?.controlSize ?? size
    }

    private var resolvedIconSize: CGFloat {
        preset?.iconSize ?? iconSize
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: resolvedIconSize, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: resolvedSize, height: resolvedSize)
                .modifier(
                    ProfileChromeIconGlassModifier(
                        standalone: standaloneGlass,
                        variant: glassVariant,
                        interactive: true
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
                        Capsule()
                            .glassEffect(.regular, in: Capsule())
                    }
            } else {
                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .liquidGlass(in: Capsule(), variant: .regular)
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
            .liquidGlass(in: Capsule(), variant: .regular, interactive: true)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.07), radius: 5, x: 0, y: 2)
    }
}
