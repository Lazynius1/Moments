import SwiftUI

/// Estilo de press unificado: escala + opacidad con spring y haptic opcional al tocar.
struct MomentsPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    var pressedOpacity: CGFloat = 0.88
    var haptic: PressHaptic = .none

    enum PressHaptic {
        case none
        case selection
        case light
        case medium

        func fire() {
            switch self {
            case .none:
                break
            case .selection:
                HapticManager.shared.selection()
            case .light:
                HapticManager.shared.lightImpact()
            case .medium:
                HapticManager.shared.mediumImpact()
            }
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(
                MotionPolicy.animation(MotionPolicy.Spring.press, value: configuration.isPressed),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    haptic.fire()
                }
            }
    }
}

extension ButtonStyle where Self == MomentsPressButtonStyle {
    static var momentsPress: MomentsPressButtonStyle { .init() }

    static func momentsPress(
        scale: CGFloat = 0.94,
        pressedOpacity: CGFloat = 0.88,
        haptic: MomentsPressButtonStyle.PressHaptic = .none
    ) -> MomentsPressButtonStyle {
        MomentsPressButtonStyle(scale: scale, pressedOpacity: pressedOpacity, haptic: haptic)
    }

    /// Filas y listas: escala más sutil.
    static var momentsPressSubtle: MomentsPressButtonStyle {
        MomentsPressButtonStyle(scale: 0.96, pressedOpacity: 0.92, haptic: .light)
    }

    /// Iconos compactos en toolbars.
    static var momentsPressIcon: MomentsPressButtonStyle {
        MomentsPressButtonStyle(scale: 0.92, pressedOpacity: 0.9, haptic: .selection)
    }
}
