import SwiftUI

fileprivate struct ActivityFilterHeaderMetrics: Equatable {
    var minY: CGFloat = 0
    var height: CGFloat = 0
}

fileprivate struct ActivityFilterHeaderMetricsPreferenceKey: PreferenceKey {
    static var defaultValue = ActivityFilterHeaderMetrics()

    static func reduce(value: inout ActivityFilterHeaderMetrics, nextValue: () -> ActivityFilterHeaderMetrics) {
        let next = nextValue()
        value.minY = min(value.minY, next.minY)
        value.height = max(value.height, next.height)
    }
}

fileprivate enum ActivityFilterScrollMetrics {
    /// Margen extra tras ocultar por completo el bloque de filtros.
    static let scrolledAwayClearance: CGFloat = 6

    /// Delta mínimo de offset para detectar intención de scroll.
    static let directionDeltaThreshold: CGFloat = 8

    static func filtersScrolledAway(metrics: ActivityFilterHeaderMetrics) -> Bool {
        guard metrics.height > 0, metrics.minY.isFinite else { return false }
        return metrics.minY + metrics.height < -scrolledAwayClearance
    }

    static var inlineVisibilityAnimation: Animation {
        .easeOut(duration: 0.18)
    }

    static var floatingRevealAnimation: Animation {
        .easeOut(duration: 0.2)
    }

    static var floatingHideAnimation: Animation {
        .easeOut(duration: 0.16)
    }

    static var floatingChipsTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: -10).combined(with: .opacity),
            removal: .offset(y: -10).combined(with: .opacity)
        )
    }
}

/// Scroll de Tu actividad: chips dentro del scroll (blur nativo en la toolbar).
/// Al bajar desaparecen con el scroll; un pequeño scroll hacia arriba las revela ancladas.
/// Si vuelves a bajar, se ocultan otra vez. Arriba del todo vuelven a su sitio inline.
struct ActivityCollapsibleFilterScroll<Header: View, Content: View>: View {
    var onRefresh: (() async -> Void)?
    @ViewBuilder var header: () -> Header
    var content: (ScrollViewProxy) -> Content
    private let floatingHeaderOverride: (() -> AnyView)?

    init(
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) {
        self.onRefresh = onRefresh
        self.header = header
        self.content = content
        self.floatingHeaderOverride = nil
    }

    init<Floating: View>(
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder floatingHeader: @escaping () -> Floating,
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) {
        self.onRefresh = onRefresh
        self.header = header
        self.content = content
        self.floatingHeaderOverride = { AnyView(floatingHeader()) }
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var filtersHeaderMetrics = ActivityFilterHeaderMetrics()
    @State private var showFloatingFilters = false

    private var filtersScrolledAway: Bool {
        ActivityFilterScrollMetrics.filtersScrolledAway(metrics: filtersHeaderMetrics)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header()
                            .background(
                                GeometryReader { geometry in
                                    let frame = geometry.frame(in: .named("activityFilterScroll"))
                                    Color.clear.preference(
                                        key: ActivityFilterHeaderMetricsPreferenceKey.self,
                                        value: ActivityFilterHeaderMetrics(
                                            minY: frame.minY,
                                            height: frame.height
                                        )
                                    )
                                }
                            )
                            .opacity(filtersScrolledAway ? 0 : 1)
                            .allowsHitTesting(!filtersScrolledAway)
                            .animation(
                                MotionPolicy.animation(ActivityFilterScrollMetrics.inlineVisibilityAnimation, value: filtersScrolledAway),
                                value: filtersScrolledAway
                            )

                        content(proxy)
                    }
                }
                .coordinateSpace(name: "activityFilterScroll")
                .profileGridNavigationChrome(colorScheme: colorScheme)
                .modifier(ActivityCollapsibleFilterScrollRefreshModifier(onRefresh: onRefresh))
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { oldOffset, newOffset in
                    handleScrollDirection(from: oldOffset, to: newOffset)
                }
                .onPreferenceChange(ActivityFilterHeaderMetricsPreferenceKey.self) { value in
                    filtersHeaderMetrics = value
                }
                .onChange(of: filtersScrolledAway) { _, scrolledAway in
                    if !scrolledAway {
                        hideFloatingFilters()
                    }
                }

                floatingFiltersOverlay
                    .animation(
                        MotionPolicy.animation(ActivityFilterScrollMetrics.floatingRevealAnimation, value: showFloatingFilters),
                        value: showFloatingFilters
                    )
            }
        }
    }

    @ViewBuilder
    private var floatingFiltersOverlay: some View {
        if filtersScrolledAway && showFloatingFilters {
            Group {
                if let floatingHeaderOverride {
                    floatingHeaderOverride()
                } else {
                    header()
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .transition(ActivityFilterScrollMetrics.floatingChipsTransition)
        }
    }

    private func handleScrollDirection(from oldOffset: CGFloat, to newOffset: CGFloat) {
        guard filtersScrolledAway else { return }

        let delta = newOffset - oldOffset
        let threshold = ActivityFilterScrollMetrics.directionDeltaThreshold

        if delta < -threshold {
            revealFloatingFilters()
        } else if delta > threshold {
            hideFloatingFilters()
        }
    }

    private func revealFloatingFilters() {
        guard !showFloatingFilters else { return }
        MotionPolicy.withOptionalAnimation(ActivityFilterScrollMetrics.floatingRevealAnimation) {
            showFloatingFilters = true
        }
    }

    private func hideFloatingFilters() {
        guard showFloatingFilters else { return }
        MotionPolicy.withOptionalAnimation(ActivityFilterScrollMetrics.floatingHideAnimation) {
            showFloatingFilters = false
        }
    }
}

private struct ActivityCollapsibleFilterScrollRefreshModifier: ViewModifier {
    let onRefresh: (() async -> Void)?

    func body(content: Content) -> some View {
        if let onRefresh {
            content.momentRefresh {
                await onRefresh()
            }
        } else {
            content
        }
    }
}
