import SwiftUI

// MARK: - Collapsible offline banner (overlay)

struct CollapsibleOfflineBanner: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var isExpanded = true
    @State private var collapseWorkItem: DispatchWorkItem?

    private let collapseDelay: TimeInterval = 4

    var body: some View {
        Group {
            if !network.isConnected {
                HStack {
                    Spacer(minLength: 0)
                    bannerBody
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            if !network.isConnected {
                handleBecameOffline()
            }
        }
        .onChange(of: network.isConnected) { wasConnected, isConnected in
            if isConnected {
                cancelCollapse()
                isExpanded = true
            } else if wasConnected {
                handleBecameOffline()
            }
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isExpanded), value: isExpanded)
    }

    @ViewBuilder
    private var bannerBody: some View {
        if isExpanded {
            expandedBanner
                .transition(.liquidGlassStretchCenter)
        } else {
            compactOrb
                .transition(.opacity)
        }
    }

    private var expandedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("network.offline.title")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(.primary)

                Text("offline.banner.message")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.primary.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("network.offline.retry")
                .font(.custom("Poppins-SemiBold", size: 11))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    retrySync()
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("network.offline.retry"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Color.clear
                .liquidGlass(in: Capsule(), interactive: false)
        }
        .shadow(color: Color.red.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private var compactOrb: some View {
        Button(action: expandFromCompact) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle(), interactive: false)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
            }
            .shadow(color: Color.red.opacity(0.22), radius: 14, x: 0, y: 8)
            .padding(10)
            .contentShape(Circle())
        }
        .buttonStyle(.momentsPress(scale: 0.9, haptic: .light))
        .accessibilityLabel(Text("network.offline.title"))
        .accessibilityHint(Text("offline.banner.expandHint"))
    }

    private func expandFromCompact() {
        cancelCollapse()
        isExpanded = true
        scheduleCollapse()
    }

    private func handleBecameOffline() {
        isExpanded = true
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        cancelCollapse()
        let work = DispatchWorkItem {
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
                isExpanded = false
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    private func cancelCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func retrySync() {
        HapticManager.shared.lightImpact()
        cancelCollapse()
        isExpanded = true
        scheduleCollapse()
        NotificationCenter.default.post(name: .forceFeedRefresh, object: nil)
    }
}

extension NSNotification.Name {
    static let forceFeedRefresh = NSNotification.Name("ForceFeedRefresh")
}

// MARK: - Modifier

struct OfflineBannerModifier: ViewModifier {
    /// Debajo del header del feed (~88pt) + pequeño margen.
    private let topInsetBelowSafeArea: CGFloat = 92

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                CollapsibleOfflineBanner()
                    .safeAreaPadding(.top, topInsetBelowSafeArea)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .zIndex(9_999)
            }
    }
}

extension View {
    func offlineBannerOverlay() -> some View {
        modifier(OfflineBannerModifier())
    }
}

// MARK: - Liquid glass stretch (center anchor for top banner)

private struct LiquidGlassCenterTransitionModifier: AnimatableModifier {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let metrics = Self.stretchMetrics(for: progress)

        return content
            .scaleEffect(x: metrics.stretchX, y: metrics.squishY, anchor: .center)
            .opacity(max(0, min(1, progress * 1.5)))
            .blur(radius: (1 - progress) * 8)
    }

    private static func stretchMetrics(for progress: Double) -> (stretchX: CGFloat, squishY: CGFloat) {
        if progress <= 0 {
            return (0, 0)
        }
        if progress >= 1 {
            return (CGFloat(progress), CGFloat(progress))
        }
        let envelope = sin(progress * .pi)
        return (
            CGFloat(progress + (0.15 * envelope)),
            CGFloat(progress - (0.05 * envelope))
        )
    }
}

private extension AnyTransition {
    static var liquidGlassStretchCenter: AnyTransition {
        .modifier(
            active: LiquidGlassCenterTransitionModifier(progress: 0),
            identity: LiquidGlassCenterTransitionModifier(progress: 1)
        )
    }
}
