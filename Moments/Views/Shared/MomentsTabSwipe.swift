import SwiftUI
import UIKit

// MARK: - Deslizar entre pestañas

/// Cámara (creador) ← Inicio ↔ Mensajes ↔ Explorar ↔ Perfil.
/// El ➕ del centro no forma parte de la secuencia: se abre tocándolo.
enum MomentsTabPages {
    /// Lo que hay a la izquierda de Inicio: el creador.
    static let creator = -1
    /// Pestañas en el orden de la barra, sin el ➕ (2).
    static let order = [0, 1, 3, 4]
}

/// Qué pantallas raíz están a la vista. Solo se desliza desde la raíz: dentro de un chat, un
/// perfil abierto o un momento, el deslizamiento es de esa pantalla.
@MainActor
final class MomentsTabRootVisibility: ObservableObject {
    @Published private(set) var visibleRoots: Set<Int> = []

    func setVisible(_ tab: Int, _ visible: Bool) {
        if visible { visibleRoots.insert(tab) } else { visibleRoots.remove(tab) }
    }

    func isRootVisible(_ tab: Int) -> Bool {
        visibleRoots.contains(tab)
    }
}

private struct MomentsTabRootVisibilityKey: EnvironmentKey {
    static let defaultValue: MomentsTabRootVisibility? = nil
}

extension EnvironmentValues {
    /// Solo lo hay dentro de las pestañas; las mismas pantallas abiertas en una hoja no lo tienen.
    var momentsTabRootVisibility: MomentsTabRootVisibility? {
        get { self[MomentsTabRootVisibilityKey.self] }
        set { self[MomentsTabRootVisibilityKey.self] = newValue }
    }
}

extension View {
    /// Pantalla raíz de la pestaña `tab` (0 Inicio, 1 Mensajes, 3 Explorar, 4 Perfil, -1 creador).
    func momentsTabSwipeRoot(_ tab: Int) -> some View {
        modifier(MomentsTabRootModifier(tab: tab))
    }
}

private struct MomentsTabRootModifier: ViewModifier {
    let tab: Int
    @Environment(\.momentsTabRootVisibility) private var rootVisibility

    func body(content: Content) -> some View {
        content
            .onAppear { rootVisibility?.setVisible(tab, true) }
            .onDisappear { rootVisibility?.setVisible(tab, false) }
    }
}

// MARK: - Estado de la transición

/// Las pestañas siguen siendo las nativas (estables, con su ciclo de vida). Al deslizar se fotografía
/// la pantalla actual y se cambia de pestaña por debajo: la nueva entra por encima, o la foto sale
/// por encima, montadas como al navegar en iOS. A la izquierda de Inicio se monta el creador.
@MainActor
final class MomentsTabSwipeState: ObservableObject {
    enum Kind: Equatable {
        case none
        /// Dedo a la izquierda: la pestaña siguiente entra por encima.
        case next
        /// Dedo a la derecha: la foto de la actual sale por encima y deja ver la anterior.
        case previous
        /// Desde Inicio hacia el creador, o desde el creador de vuelta a Inicio.
        case creator
    }

    @Published fileprivate(set) var kind: Kind = .none
    @Published fileprivate(set) var dragX: CGFloat = 0
    @Published fileprivate(set) var snapshot: UIImage?
    @Published fileprivate(set) var isCreatorOpen = false
    /// La barra flotante se oculta un instante para que no salga en la foto.
    @Published fileprivate(set) var hidesTabBarForSnapshot = false
    /// 0…1: cuánto se ve del creador (la barra flotante se desvanece con él).
    @Published fileprivate(set) var creatorProgress: CGFloat = 0

    fileprivate var fromTab = 0
    fileprivate var pendingEnd: (translation: CGFloat, velocity: CGFloat)?
}

/// La barra flotante se aparta mientras se ve el creador y no sale en la foto de la transición.
struct MomentsTabBarSwipeFade<Content: View>: View {
    @ObservedObject var state: MomentsTabSwipeState
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .opacity(state.hidesTabBarForSnapshot ? 0 : 1 - min(state.creatorProgress * 1.6, 1))
            .allowsHitTesting(state.creatorProgress < 0.01)
    }
}

// MARK: - Contenedor

struct MomentsTabSwipeContainer<Content: View, Creator: View>: View {
    @Binding var selectedTab: Int
    @Binding var previousSelectedTab: Int
    @ObservedObject var state: MomentsTabSwipeState
    @ObservedObject var roots: MomentsTabRootVisibility
    /// El creador recibe la acción de cerrarse (vuelve a Inicio).
    @ViewBuilder let creator: (_ close: @escaping () -> Void) -> Creator
    @ViewBuilder let content: () -> Content

    @State private var width: CGFloat = 1

    private static var parallax: CGFloat { 1.0 / 3.0 }
    private static var dimming: Double { 0.22 }
    private static var commitFraction: CGFloat { 0.3 }
    private static var spring: Animation { .interpolatingSpring(duration: 0.32, bounce: 0) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isCreatorMounted {
                creator(closeCreator)
                    .offset(x: -width * Self.parallax * (1 - creatorReveal))
                    .brightness(-Self.dimming * Double(1 - creatorReveal))
                    .allowsHitTesting(state.isCreatorOpen && state.kind == .none)
            }

            if state.kind == .next, let snapshot = state.snapshot {
                snapshotView(snapshot)
                    .offset(x: state.dragX * Self.parallax)
                    .brightness(-Self.dimming * Double(progress))
            }

            content()
                // Esquinas del dispositivo al moverse por encima; el recorte cubre también la
                // barra de estado, así el contenido no se corta.
                .mask { movingLayerShape(isMoving: contentIsOnTop).ignoresSafeArea() }
                .shadow(color: .black.opacity(contentIsOnTop ? 0.22 : 0), radius: contentIsOnTop ? 14 : 0, x: contentIsOnTop ? -4 : 0)
                .offset(x: contentOffset)
                .brightness(contentDimming)
                .allowsHitTesting(state.kind == .none && !state.isCreatorOpen)

            if state.kind == .previous, let snapshot = state.snapshot {
                snapshotView(snapshot)
                    .mask { movingLayerShape(isMoving: true).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.22), radius: 14, x: -4)
                    .offset(x: state.dragX)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .gesture(
            MomentsTabSwipeGesture(
                canBegin: canBegin,
                onBegan: began,
                onChanged: { translation in changed(translation) },
                onEnded: { translation, velocity in ended(translation, velocity) }
            )
        )
        .onChange(of: creatorReveal) { _, reveal in state.creatorProgress = reveal }
    }

    // MARK: Geometría

    /// 0…1 del recorrido del gesto en curso.
    private var progress: CGFloat {
        min(max(abs(state.dragX) / width, 0), 1)
    }

    private var isCreatorMounted: Bool {
        state.isCreatorOpen || state.kind == .creator
    }

    /// 0 Inicio a la vista, 1 creador a la vista.
    private var creatorReveal: CGFloat {
        guard isCreatorMounted else { return 0 }
        let base: CGFloat = state.isCreatorOpen ? 1 : 0
        guard state.kind == .creator else { return base }
        return min(max(base + state.dragX / width, 0), 1)
    }

    private var contentOffset: CGFloat {
        switch state.kind {
        case .none:
            return state.isCreatorOpen ? width : 0
        case .creator:
            return creatorReveal * width
        case .next:
            // La pestaña nueva entra desde la derecha (aún sin foto: quieta).
            guard state.snapshot != nil else { return 0 }
            return max(width + state.dragX, 0)
        case .previous:
            // La pestaña anterior está debajo, más lenta.
            guard state.snapshot != nil else { return 0 }
            return -width * Self.parallax * (1 - progress)
        }
    }

    private var contentDimming: Double {
        guard state.kind == .previous, state.snapshot != nil else { return 0 }
        return -Self.dimming * Double(1 - progress)
    }

    /// La capa que se mueve por encima lleva las esquinas del dispositivo (como al navegar en iOS):
    /// por ellas asoma la pantalla de debajo. En reposo, sin recorte.
    private func movingLayerShape(isMoving: Bool) -> AnyShape {
        if isMoving, #available(iOS 26.0, *) {
            return AnyShape(ConcentricRectangle(corners: .concentric, isUniform: true))
        }
        return AnyShape(Rectangle())
    }

    /// La pestaña está por encima de otra capa (sombra en su borde, como al navegar en iOS).
    private var contentIsOnTop: Bool {
        switch state.kind {
        case .next: return state.snapshot != nil
        case .creator: return true
        case .none: return state.isCreatorOpen
        case .previous: return false
        }
    }

    /// La foto ocupa la ventana entera, colocada desde la esquina superior.
    private func snapshotView(_ image: UIImage) -> some View {
        GeometryReader { _ in
            Image(uiImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Gesto

    private func neighbor(_ direction: MomentsTabSwipeDirection) -> Int? {
        guard let index = MomentsTabPages.order.firstIndex(of: selectedTab) else { return nil }
        let target = index + (direction == .next ? 1 : -1)
        return MomentsTabPages.order.indices.contains(target) ? MomentsTabPages.order[target] : nil
    }

    private func canBegin(_ direction: MomentsTabSwipeDirection) -> Bool {
        guard state.kind == .none else { return false }
        if state.isCreatorOpen {
            return direction == .next && roots.isRootVisible(MomentsTabPages.creator)
        }
        guard roots.isRootVisible(selectedTab) else { return false }
        if direction == .previous && selectedTab == 0 { return true }
        return neighbor(direction) != nil
    }

    private func began(_ direction: MomentsTabSwipeDirection, _ window: UIWindow?) {
        state.dragX = 0
        state.pendingEnd = nil
        if state.isCreatorOpen || (direction == .previous && selectedTab == 0) {
            state.kind = .creator
            return
        }
        guard let target = neighbor(direction) else { return }
        state.fromTab = selectedTab
        state.kind = direction == .next ? .next : .previous
        // La barra fuera de la foto; tras pintarse sin ella, foto y cambio de pestaña.
        state.hidesTabBarForSnapshot = true
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                state.snapshot = window.map(Self.snapshot(of:))
                state.hidesTabBarForSnapshot = false
                withTransaction(Self.instant) {
                    selectedTab = target
                    previousSelectedTab = target
                }
                if let pending = state.pendingEnd {
                    ended(pending.translation, pending.velocity)
                }
            }
        }
    }

    private func changed(_ translation: CGFloat) {
        switch state.kind {
        case .next: state.dragX = min(translation, 0)
        case .previous: state.dragX = max(translation, 0)
        case .creator:
            state.dragX = state.isCreatorOpen ? min(translation, 0) : max(translation, 0)
        case .none: break
        }
    }

    private func ended(_ translation: CGFloat, _ velocity: CGFloat) {
        changed(translation)
        let projected = abs(state.dragX + velocity * 0.2)
        let towardsGesture = state.kind == .next || (state.kind == .creator && state.isCreatorOpen)
            ? (state.dragX + velocity * 0.2) < 0
            : (state.dragX + velocity * 0.2) > 0
        let commit = towardsGesture && projected > width * Self.commitFraction

        switch state.kind {
        case .none:
            return
        case .next, .previous:
            // Aún sin foto: se termina en cuanto llegue.
            guard state.snapshot != nil else {
                state.pendingEnd = (translation, velocity)
                return
            }
            let goal: CGFloat = commit ? (state.kind == .next ? -width : width) : 0
            withAnimation(Self.spring) { state.dragX = goal } completion: {
                if commit {
                    HapticManager.shared.selection()
                } else {
                    withTransaction(Self.instant) {
                        selectedTab = state.fromTab
                        previousSelectedTab = state.fromTab
                    }
                }
                finish()
            }
        case .creator:
            let opening = !state.isCreatorOpen
            let goal: CGFloat = commit ? (opening ? width : -width) : 0
            withAnimation(Self.spring) { state.dragX = goal } completion: {
                if commit {
                    if opening { HapticManager.shared.mediumImpact() }
                    state.isCreatorOpen = opening
                }
                finish()
            }
        }
    }

    private func finish() {
        withTransaction(Self.instant) {
            state.kind = .none
            state.dragX = 0
            state.snapshot = nil
            state.pendingEnd = nil
        }
    }

    /// La ✕ del creador: Inicio vuelve por encima, como al deslizar.
    private func closeCreator() {
        guard state.isCreatorOpen, state.kind == .none else { return }
        state.kind = .creator
        state.dragX = 0
        withAnimation(Self.spring) { state.dragX = -width } completion: {
            state.isCreatorOpen = false
            finish()
        }
    }

    private static func snapshot(of window: UIWindow) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    private static var instant: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}

// MARK: - Reconocedor

enum MomentsTabSwipeDirection {
    /// Dedo hacia la derecha.
    case previous
    /// Dedo hacia la izquierda.
    case next
}

/// Pan horizontal que cede ante lo que ya se desliza en horizontal (carruseles, fila de
/// historias, pestañas del perfil) mientras ese contenido pueda moverse en esa dirección.
private struct MomentsTabSwipeGesture: UIGestureRecognizerRepresentable {
    let canBegin: (MomentsTabSwipeDirection) -> Bool
    let onBegan: (MomentsTabSwipeDirection, UIWindow?) -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> MomentsTabSwipeRecognizer {
        let recognizer = MomentsTabSwipeRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: MomentsTabSwipeRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: MomentsTabSwipeRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            if let direction = recognizer.direction { onBegan(direction, recognizer.view?.window) }
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(0, 0)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(canBegin: canBegin)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (MomentsTabSwipeDirection) -> Bool

        init(canBegin: @escaping (MomentsTabSwipeDirection) -> Bool) {
            self.canBegin = canBegin
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? MomentsTabSwipeRecognizer, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) * 1.3 else { return false }
            let direction: MomentsTabSwipeDirection = velocity.x < 0 ? .next : .previous
            guard canBegin(direction) else { return false }
            if horizontalScrollCanMove(at: pan.location(in: view), in: view, direction: direction) { return false }
            pan.direction = direction
            return true
        }

        /// Los scrolls verticales esperan a que este gesto falle, igual que los horizontales
        /// cuando ya están en un extremo.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scrollView = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scrollView.panGestureRecognizer else { return false }
            guard scrollView.isHorizontallyScrollable else { return true }
            return scrollView.isAtHorizontalStart || scrollView.isAtHorizontalEnd
        }

        /// ¿Hay bajo el dedo contenido horizontal que aún puede moverse en esa dirección?
        private func horizontalScrollCanMove(at point: CGPoint, in root: UIView, direction: MomentsTabSwipeDirection) -> Bool {
            var current = root.hitTest(point, with: nil)
            while let view = current, view !== root.superview {
                if let scrollView = view as? UIScrollView, scrollView.isScrollEnabled, scrollView.isHorizontallyScrollable {
                    let canMove = direction == .next ? !scrollView.isAtHorizontalEnd : !scrollView.isAtHorizontalStart
                    if canMove { return true }
                }
                current = view.superview
            }
            return false
        }
    }
}

private final class MomentsTabSwipeRecognizer: UIPanGestureRecognizer {
    fileprivate(set) var direction: MomentsTabSwipeDirection?

    override func reset() {
        super.reset()
        direction = nil
    }
}

private extension UIScrollView {
    var isHorizontallyScrollable: Bool {
        contentSize.width + adjustedContentInset.left + adjustedContentInset.right > bounds.width + 1
    }

    var isAtHorizontalStart: Bool {
        contentOffset.x <= -adjustedContentInset.left + 1
    }

    var isAtHorizontalEnd: Bool {
        contentOffset.x >= contentSize.width + adjustedContentInset.right - bounds.width - 1
    }
}
