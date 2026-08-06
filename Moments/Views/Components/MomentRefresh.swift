import SwiftUI
import UIKit

// Pull-to-refresh Moments (iOS 26+):
// Mecánica Kavsoft (`.refreshable` nativo + tint clear + progress 0…1)
// + gota Liquid Glass Moments (overlay global TabBar / sheets).
// < iOS 26: `.refreshable` estándar.

@MainActor
final class MomentRefreshState: ObservableObject {
    static let shared = MomentRefreshState()

    /// 0…1 (estilo Kavsoft; ~60pt de pull = 1).
    @Published private(set) var scrollProgress: CGFloat = 0
    @Published private(set) var isRefreshing = false

    /// Evita pisar el reset animado al soltar.
    private(set) var isAnimating = false

    private var actualProgress: CGFloat = 0

    var isActive: Bool { scrollProgress > 0.02 || isRefreshing }

    /// Pull “efectivo” para la gota (1 mientras refresca).
    var heldProgress: CGFloat {
        isRefreshing ? 1 : scrollProgress
    }

    func updateScrollOffset(_ offset: CGFloat) {
        // offset: contentOffset.y + contentInsets.top (negativo al tirar).
        let progress = max(min(-offset / 60, 1), 0)
        actualProgress = progress
        guard !isAnimating else { return }
        scrollProgress = isRefreshing ? 1 : progress
    }

    func beginNativeRefresh() {
        isRefreshing = true
        scrollProgress = 1
    }

    func endNativeRefresh() {
        if actualProgress == 0 {
            isAnimating = true
            withAnimation(.easeInOut(duration: 0.2), completionCriteria: .logicallyComplete) {
                self.scrollProgress = 0.01
            } completion: {
                self.scrollProgress = 0
                self.isAnimating = false
            }
        } else {
            scrollProgress = actualProgress
        }
        isRefreshing = false
    }
}

// MARK: - Modifier (mecánica Kavsoft)

@available(iOS 26.0, *)
private struct MomentRefreshModifier: ViewModifier {
    let action: () async -> Void
    @State private var tintColor: Color = .gray
    @State private var isTintUpdateAvailable = false

    func body(content: Content) -> some View {
        content
            .background(
                MomentRefreshControlTintUpdater(color: $tintColor) { available in
                    isTintUpdateAvailable = available
                }
            )
            .compositingGroup()
            .mask {
                Rectangle()
                    .ignoresSafeArea()
            }
            .refreshable {
                let state = MomentRefreshState.shared
                state.beginNativeRefresh()
                await action()
                state.endNativeRefresh()
            }
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { _, newValue in
                guard isTintUpdateAvailable else { return }
                MomentRefreshState.shared.updateScrollOffset(newValue)
            }
            .onGeometryChange(for: EdgeInsets.self) {
                $0.safeAreaInsets
            } action: { newValue in
                tintColor = newValue.top < 70 ? .clear : .gray
            }
    }
}

/// Localiza el UIRefreshControl nativo y aplica tint (clear = invisible).
private struct MomentRefreshControlTintUpdater: UIViewRepresentable {
    @Binding var color: Color
    var result: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        updateTint(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        updateTint(uiView)
    }

    private func updateTint(_ view: UIView) {
        DispatchQueue.main.async {
            if let compositingGroup = view.superview?.superview,
               let scrollview = compositingGroup.subviews.last?.subviews.last as? UIScrollView {
                scrollview.refreshControl?.tintColor = UIColor(color)
                result(true)
            } else {
                result(false)
            }
        }
    }
}

// MARK: - API pública

extension View {
    /// Sustituye a `.refreshable`. iOS 26+: nativo + gota Moments. Antes: nativo solo.
    @ViewBuilder
    func momentRefresh(action: @escaping () async -> Void) -> some View {
        if #available(iOS 26.0, *) {
            modifier(MomentRefreshModifier(action: action))
        } else {
            refreshable { await action() }
        }
    }

    /// Gota en pantallas modales (sheet / fullScreenCover).
    @ViewBuilder
    func momentRefreshOverlayHost() -> some View {
        if #available(iOS 26.0, *) {
            overlay(alignment: .top) {
                MomentRefreshGota(state: .shared)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}

// MARK: - Gota Liquid Glass (visual Moments)

@available(iOS 26.0, *)
struct MomentRefreshGota: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: MomentRefreshState
    @Namespace private var glassNS

    private let dropSize: CGFloat = 40

    /// Descenso de la gota (0 = fundida en el rasgo).
    private var travel: CGFloat {
        state.heldProgress * 63
    }

    // Mismo tinted Moments que la floating tab bar; sin interactive (no es control tocable).
    private var glass: Glass {
        MomentsChromeGlass.chromeGlass(
            interactive: false,
            tint: MomentsChromeGlass.canvasTint(for: colorScheme)
        )
    }

    private struct AnchorSpec {
        let size: CGSize
        let top: CGFloat
        let shape: AnyShape
    }

    private func anchorSpec(width: CGFloat, safeTop: CGFloat) -> AnchorSpec {
        if safeTop >= 55 {
            return AnchorSpec(size: CGSize(width: 126, height: 37.33), top: 14, shape: AnyShape(Capsule()))
        }

        let notchShape = AnyShape(UnevenRoundedRectangle(bottomLeadingRadius: 21, bottomTrailingRadius: 21))
        if safeTop >= 40 {
            let isWideNotch = width >= 410 || (width <= 380 && safeTop <= 46)
            if isWideNotch {
                return AnchorSpec(size: CGSize(width: 209, height: 30), top: 2, shape: notchShape)
            } else {
                return AnchorSpec(size: CGSize(width: 162, height: 33), top: 2, shape: notchShape)
            }
        }

        return AnchorSpec(size: CGSize(width: 120, height: 30), top: max(0, safeTop - 30), shape: AnyShape(Capsule()))
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = max(proxy.safeAreaInsets.top, 20)
            // Kavsoft: no pintar si el chrome (nav) hincha el safe area.
            let chromeOk = safeTop < 70
            let anchor = anchorSpec(width: proxy.size.width, safeTop: safeTop)
            let progress = state.heldProgress
            let spinnerOpacity: CGFloat = {
                if state.isRefreshing { return 1 }
                return progress > 0.8 ? (progress - 0.8) / 0.2 : 0
            }()

            GlassEffectContainer(spacing: 34) {
                ZStack(alignment: .top) {
                    Color.clear
                        .frame(width: anchor.size.width, height: anchor.size.height)
                        .glassEffect(glass, in: anchor.shape)
                        .glassEffectID("island", in: glassNS)

                    ProgressView()
                        .tint(MomentsChromeGlass.contentColor(for: colorScheme))
                        .opacity(spinnerOpacity)
                        .frame(width: dropSize, height: dropSize)
                        .glassEffect(glass, in: Circle())
                        .glassEffectID("drop", in: glassNS)
                        .offset(y: (anchor.size.height - dropSize) / 2 + travel)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: anchor.top - safeTop)
            .opacity(chromeOk && state.isActive ? 1 : 0)
            .animation(.snappy(duration: 0.32), value: travel)
            .animation(.easeOut(duration: 0.15), value: state.isActive)
            .allowsHitTesting(false)
        }
    }
}
