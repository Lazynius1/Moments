import SwiftUI

// Scroll → progress 0…1 para MomentsFloatingTabBar (0 = expandida, 1 = encogida).

extension View {
    @ViewBuilder
    func hideNativeTabBar() -> some View {
        self.toolbarVisibility(.hidden, for: .tabBar)
    }

    /// Oculta la floating pill de Moments (además del tab bar nativo si aplica).
    func momentsFloatingTabBarHidden(_ hidden: Bool = true) -> some View {
        modifier(MomentsFloatingTabBarHiddenModifier(hidden: hidden))
    }
}

extension ScrollView {
    @ViewBuilder
    func adoptForFloatingTabBar() -> some View {
        self.modifier(FloatingTabBarScrollViewModifier())
    }
}

private struct MomentsFloatingTabBarHiddenModifier: ViewModifier {
    @EnvironmentObject private var minimize: TabBarMinimizeController
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                if hidden { minimize.requestHidden(true) }
            }
            .onDisappear {
                // Async: la hija puede pedir hide en el mismo ciclo antes de soltar el padre.
                guard hidden else { return }
                DispatchQueue.main.async {
                    minimize.requestHidden(false)
                }
            }
            .onChange(of: hidden) { oldValue, newValue in
                if oldValue == newValue { return }
                if newValue {
                    minimize.requestHidden(true)
                } else {
                    DispatchQueue.main.async {
                        minimize.requestHidden(false)
                    }
                }
            }
    }
}

/// Drag + onScrollGeometryChange → progress 0…1.
fileprivate struct FloatingTabBarScrollViewModifier: ViewModifier {
    @EnvironmentObject private var minimize: TabBarMinimizeController
    @GestureState private var isDragging: Bool = false
    @State private var isScrolledUp: Bool?
    @State private var shiftOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isLargerContent: Bool = false
    @State private var scrollPhase: ScrollPhase = .idle

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(.hidden, for: .tabBar)
            // Barra ~18pt sobre home indicator.
            .safeAreaPadding(.bottom, 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            // minDistance > 0 + solo vertical: un DragGesture(0) se come taps y
            // el scroll horizontal del picker de reacciones del feed.
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .scrollView)
                    .updating($isDragging) { value, out, _ in
                        let vertical = abs(value.translation.height)
                        let horizontal = abs(value.translation.width)
                        out = vertical >= horizontal
                    }
                    .onEnded { value in
                        guard scrollPhase != .idle else { return }
                        let vertical = abs(value.translation.height)
                        let horizontal = abs(value.translation.width)
                        guard vertical >= horizontal else { return }

                        let velocity = -value.velocity.height / 5
                        let resultOffset = scrollOffset + velocity
                        let rawProgress = (resultOffset - shiftOffset) / distance
                        let clampedProgress = max(0, min(1, rawProgress))

                        withAnimation(animation) {
                            minimize.progress = resultOffset > (distance / 2) && isLargerContent
                                ? (clampedProgress > 0.5 ? 1 : 0)
                                : 0
                        }

                        isScrolledUp = nil
                        shiftOffset = scrollOffset - (minimize.progress * distance)
                    }
            )
            .onScrollPhaseChange { _, newPhase in
                scrollPhase = newPhase
            }
            .onScrollGeometryChange(for: CGFloat.self, of: {
                $0.contentSize.height - $0.containerSize.height
            }, action: { _, newValue in
                isLargerContent = newValue > 0
            })
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { oldValue, newValue in
                guard isDragging else { return }
                scrollOffset = newValue
                let scrolledUp = oldValue < newValue

                if isScrolledUp != scrolledUp {
                    isScrolledUp = scrolledUp
                    shiftOffset = newValue - (minimize.progress * distance)
                }

                let rawProgress = (newValue - shiftOffset) / distance
                let clampedProgress = max(0, min(1, rawProgress))

                withAnimation(animation) {
                    minimize.progress = clampedProgress
                }
            }
    }

    private var distance: CGFloat { 100 }

    private var animation: Animation {
        .interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)
    }
}
