import SwiftUI

// MARK: - Collapsible offline banner (overlay)
// Layout: compacto a la izquierda → expand hacia la derecha.
// Tamaño / tipografía: iOS originales.
//
// iOS 26+ morph (regla Moments + guía Apple):
// UNA sola superficie glass persistente cuya geometría anima
// (cápsula 44×44 = círculo → píldora ancha). Misma lección que
// VoiceRecordingFloatingControl: NO glassEffectUnion / IDs distintos
// sobre formas pequeñas con contenido (se quedan en “canica”).
// Estado con withAnimation { }. Controles: .interactive().
// <26: material + scale/opacity anclado a leading.

struct CollapsibleOfflineBanner: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true
    @State private var collapseWorkItem: DispatchWorkItem?
    @Namespace private var offlineGlassNS

    private let collapseDelay: TimeInterval = 4
    private let compactSize: CGFloat = 44
    /// Más corto que `.default` del sistema; el morph de la gota sigue, pero sin lag.
    private var morphAnimation: Animation { .snappy(duration: 0.32) }

    var body: some View {
        Group {
            if !network.isConnected {
                HStack(spacing: 0) {
                    bannerBody
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
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
    }

    @ViewBuilder
    private var bannerBody: some View {
        if #available(iOS 26.0, *) {
            liquidGlassBanner
        } else {
            fallbackBanner
        }
    }

    // MARK: - iOS 26+ Liquid Glass (una gota que crece / encoge)

    @available(iOS 26.0, *)
    private var liquidGlassBanner: some View {
        GlassEffectContainer(spacing: 0) {
            bannerChrome
                .glassEffect(
                    MomentsChromeGlass.chromeGlass(
                        interactive: true,
                        tint: MomentsChromeGlass.canvasTint(for: colorScheme)
                    ),
                    in: Capsule()
                )
                // Mismo ID en ambos estados: identidad continua de la gota.
                .glassEffectID("offlineBanner", in: offlineGlassNS)
        }
        .frame(maxWidth: isExpanded ? .infinity : compactSize, alignment: .leading)
        // Tap solo en compacto; si no, el gesto se come el Retry.
        .overlay {
            if !isExpanded {
                Color.clear
                    .contentShape(Circle())
                    .onTapGesture { expandFromCompact() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("network.offline.title"))
                    .accessibilityHint(Text("offline.banner.expandHint"))
            }
        }
    }

    /// Contenido + tamaño de la gota. Compacto = 44×44 (cápsula = círculo).
    private var bannerChrome: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: isExpanded ? 18 : 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(
                    width: isExpanded ? nil : compactSize,
                    height: isExpanded ? nil : compactSize
                )

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    Text("network.offline.title")
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("offline.banner.message")
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: retrySync) {
                    Text("network.offline.retry")
                        .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("network.offline.retry"))
            }
        }
        .padding(.horizontal, isExpanded ? 14 : 0)
        .padding(.vertical, isExpanded ? 10 : 0)
        .frame(
            minWidth: isExpanded ? nil : compactSize,
            minHeight: isExpanded ? nil : compactSize
        )
        .contentShape(Capsule())
    }

    // MARK: - Fallback < iOS 26

    private var fallbackBanner: some View {
        Group {
            if isExpanded {
                bannerChrome
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Capsule(), interactive: false, style: .tinted)
                    }
                    .shadow(color: Color.red.opacity(0.22), radius: 18, x: 0, y: 10)
                    .transition(.offlineExpandFromLeading)
            } else {
                Button(action: expandFromCompact) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: compactSize, height: compactSize)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
                        }
                        .shadow(color: Color.red.opacity(0.22), radius: 14, x: 0, y: 8)
                        .contentShape(Circle())
                }
                .buttonStyle(.momentsPress(scale: 0.9, haptic: .light))
                .accessibilityLabel(Text("network.offline.title"))
                .accessibilityHint(Text("offline.banner.expandHint"))
                .transition(.offlineExpandFromLeading)
            }
        }
        .frame(maxWidth: isExpanded ? .infinity : compactSize, alignment: .leading)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isExpanded), value: isExpanded)
    }

    // MARK: - Actions

    private func expandFromCompact() {
        HapticManager.shared.lightImpact()
        cancelCollapse()
        MotionPolicy.withOptionalAnimation(morphAnimation) {
            isExpanded = true
        }
        scheduleCollapse()
    }

    private func handleBecameOffline() {
        isExpanded = true
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        cancelCollapse()
        let work = DispatchWorkItem {
            MotionPolicy.withOptionalAnimation(morphAnimation) {
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
        MotionPolicy.withOptionalAnimation(morphAnimation) {
            isExpanded = true
        }
        scheduleCollapse()
        NotificationCenter.default.post(name: .forceFeedRefresh, object: nil)
    }
}

extension NSNotification.Name {
    static let forceFeedRefresh = NSNotification.Name("ForceFeedRefresh")
}

// MARK: - Modifier

struct OfflineBannerModifier: ViewModifier {
    /// Misma altura que `FeedFloatingSelector` (`feedHeaderHeight` / `floatingSelectorTopInset`).
    private let topInsetBelowSafeArea: CGFloat = 88

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                CollapsibleOfflineBanner()
                    .safeAreaPadding(.top, topInsetBelowSafeArea)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .zIndex(9_999)
            }
    }
}

extension View {
    func offlineBannerOverlay() -> some View {
        modifier(OfflineBannerModifier())
    }
}

// MARK: - Fallback transition (leading-anchored expand / shrink)

private struct OfflineLeadingExpandModifier: AnimatableModifier {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: max(0.01, progress),
                y: max(0.85, 0.85 + 0.15 * progress),
                anchor: .leading
            )
            .opacity(max(0, min(1, progress * 1.35)))
    }
}

private extension AnyTransition {
    /// Expand / shrink anclado a la izquierda (paridad Android expandHorizontally Start).
    static var offlineExpandFromLeading: AnyTransition {
        .modifier(
            active: OfflineLeadingExpandModifier(progress: 0),
            identity: OfflineLeadingExpandModifier(progress: 1)
        )
    }
}
