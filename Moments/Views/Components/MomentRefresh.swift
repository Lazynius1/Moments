import SwiftUI

// Pull-to-refresh con efecto "gota" (Liquid Glass, iOS 26+): una gota nace fundida
// en la Dynamic Island y se despega al tirar, con el spinner del sistema al refrescar.
// En < iOS 26 cae al `.refreshable` estándar.
//
// Piezas:
//  1) MomentRefreshState.shared — estado ÚNICO compartido (pull + isRefreshing + action).
//  2) .momentRefresh { }        — se aplica al scroll; mide el pull y fija la action.
//  3) MomentRefreshGota(state:.shared) — la gota; se dibuja UNA sola vez en TabBarView (raíz).

@MainActor
final class MomentRefreshState: ObservableObject {
    // Única instancia: la gota se dibuja una sola vez a nivel raíz (TabBarView)
    // y cualquier `.momentRefresh { }` de la pantalla activa la alimenta.
    static let shared = MomentRefreshState()

    @Published private(set) var pull: CGFloat = 0
    @Published private(set) var isRefreshing = false

    let threshold: CGFloat = 90
    var action: (() async -> Void)?

    var isActive: Bool { pull > 2 || isRefreshing }

    // Pull "efectivo" (fijo al umbral mientras refresca).
    var heldPull: CGFloat {
        isRefreshing ? threshold : min(pull, threshold)
    }

    func updatePull(_ value: CGFloat) {
        guard !isRefreshing else { return }
        pull = max(0, value)
        // Dispara al cruzar el umbral DURANTE el drag (al soltar el scroll ya rebotó a 0).
        if pull >= threshold { startRefresh() }
    }

    private func startRefresh() {
        guard !isRefreshing, let action else { return }
        isRefreshing = true
        pull = threshold
        Task {
            await action()
            withAnimation(.snappy(duration: 0.35)) {
                isRefreshing = false
                pull = 0
            }
        }
    }
}

// MARK: - Detección (en el scroll)

private struct MomentRefreshDetector: ViewModifier {
    @ObservedObject var state: MomentRefreshState

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, pull in
                state.updatePull(pull)
            }
    }
}

extension View {
    // iOS 26+: detecta el pull y alimenta el estado compartido; la gota se dibuja
    // una sola vez a nivel raíz (TabBarView), por encima de todo.
    // < iOS 26: cae al `.refreshable` estándar.
    // Sustituye directamente a `.refreshable { … }`.
    @ViewBuilder
    func momentRefresh(action: @escaping () async -> Void) -> some View {
        if #available(iOS 26.0, *) {
            self
                .onAppear { MomentRefreshState.shared.action = action }
                .modifier(MomentRefreshDetector(state: MomentRefreshState.shared))
        } else {
            self.refreshable { await action() }
        }
    }
}

// MARK: - Gota (nivel superior de la pantalla)

@available(iOS 26.0, *)
struct MomentRefreshGota: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: MomentRefreshState
    @Namespace private var glassNS

    private let dropSize: CGFloat = 40

    // Descenso de la gota (0 = fundida dentro del rasgo superior).
    private var travel: CGFloat {
        state.heldPull * 0.7
    }

    // Tu moment glass (clear + canvas tint): morphea como líquido.
    private var glass: Glass {
        MomentsChromeGlass.clearChromeGlass(
            interactive: false,
            tint: MomentsChromeGlass.canvasTint(for: colorScheme)
        )
    }

    // Geometría del rasgo superior (isla / notch / clásico) según el safe area del sistema.
    private struct AnchorSpec {
        let size: CGSize
        let top: CGFloat        // desde el borde físico
        let shape: AnyShape
    }

    private func anchorSpec(width: CGFloat, safeTop: CGFloat) -> AnchorSpec {
        // Dynamic Island: medidas constantes en todos los modelos con isla.
        // top=14 es el que quedó clavado en el iPhone 17 Pro Max.
        if safeTop >= 55 {
            return AnchorSpec(size: CGSize(width: 126, height: 37.33), top: 14, shape: AnyShape(Capsule()))
        }

        // Notch: distinguir ancho (X/XS/XR/11) vs estrecho (12/13/14) por tamaño de pantalla + safe area.
        let notchShape = AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: 21, bottomTrailingRadius: 21))
        if safeTop >= 40 {
            let isWideNotch = width >= 410 || (width <= 380 && safeTop <= 46)
            // top ligeramente > 0: el ancla baja un pelín para que el "estirón"
            // líquido se vea justo en el borde inferior del notch, no pegado al filo.
            if isWideNotch {
                // X, XS, XR, 11, 11 Pro/Max → notch ancho ~209×30.
                return AnchorSpec(size: CGSize(width: 209, height: 30), top: 2, shape: notchShape)
            } else {
                // 12, 13, 14 (y minis) → notch estrecho ~162×33.
                return AnchorSpec(size: CGSize(width: 162, height: 33), top: 2, shape: notchShape)
            }
        }

        // Sin notch (poco común en iOS 26): cápsula bajo la status bar.
        return AnchorSpec(size: CGSize(width: 120, height: 30), top: max(0, safeTop - 30), shape: AnyShape(Capsule()))
    }

    var body: some View {
        // GeometryReader SIN ignoresSafeArea → safeAreaInsets.top es el REAL del sistema.
        GeometryReader { proxy in
            let safeTop = max(proxy.safeAreaInsets.top, 20)
            let anchor = anchorSpec(width: proxy.size.width, safeTop: safeTop)

            GlassEffectContainer(spacing: 34) {
                ZStack(alignment: .top) {
                    // Ancla con la forma real del rasgo (isla = capsule, notch = rect redondeado).
                    Color.clear
                        .frame(width: anchor.size.width, height: anchor.size.height)
                        .glassEffect(glass, in: anchor.shape)
                        .glassEffectID("island", in: glassNS)

                    // Gota: fundida en el rasgo en reposo; desciende al tirar. Spinner
                    // del sistema como contenido nítido sobre el glass.
                    ProgressView()
                        .tint(MomentsChromeGlass.contentColor(for: colorScheme))
                        .opacity(state.isRefreshing ? 1 : 0)
                        .frame(width: dropSize, height: dropSize)
                        .glassEffect(glass, in: Circle())
                        .glassEffectID("drop", in: glassNS)
                        .offset(y: (anchor.size.height - dropSize) / 2 + travel)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Subir desde el borde del safe area hasta el borde físico (isla/notch).
            .offset(y: anchor.top - safeTop)
            .opacity(state.isActive ? 1 : 0)
            .animation(.snappy(duration: 0.32), value: travel)
            .animation(.easeOut(duration: 0.15), value: state.isActive)
            .allowsHitTesting(false)
        }
    }
}
