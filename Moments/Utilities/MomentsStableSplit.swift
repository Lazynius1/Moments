import SwiftUI

/// Reparte dos partes de la misma tarea sin cambiar la identidad de la principal.
/// En el iPhone solo se muestra la principal. En el Duo el `ArrangementView` permanece
/// al abrir y cerrar; cerrado no hay eje de corte y la secundaria no ocupa espacio.
struct MomentsStableSplit<Primary: View, Secondary: View>: View {
    var usesDuo: Bool
    var expanded: Bool
    var beside: Bool
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        if usesDuo {
            if #available(iOS 27.1, *) {
                ArrangementView {
                    primary()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } secondary: {
                    secondary()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .environment(\.momentsSplitPane, true)
                        .opacity(expanded ? 1 : 0)
                        .allowsHitTesting(expanded)
                        .accessibilityHidden(!expanded)
                }
                .arrangementViewStyle(.split.axes(splitAxes))
            } else {
                primary()
            }
        } else {
            primary()
        }
    }

    private var splitAxes: Axis.Set {
        guard expanded else { return [] }
        return beside ? .horizontal : .vertical
    }
}

private struct MomentsSplitPaneKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// La vista está en la segunda pantalla del Duo. Su scroll y su tamaño son los de ese panel.
    var momentsSplitPane: Bool {
        get { self[MomentsSplitPaneKey.self] }
        set { self[MomentsSplitPaneKey.self] = newValue }
    }
}

struct SplitPaneClipModifier: ViewModifier {
    @Environment(\.momentsSplitPane) private var momentsSplitPane

    func body(content: Content) -> some View {
        if momentsSplitPane {
            content.clipped()
        } else {
            content
        }
    }
}
