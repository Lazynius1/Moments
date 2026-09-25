import SwiftUI

/// Solo el aura de borde. Todo el chrome interactivo vive en `InAppBannerView`.
struct IncognitoGlobalOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var edgePulse = false

    var body: some View {
        GeometryReader { proxy in
            edgeAura(in: proxy)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { edgePulse = true }
    }

    private func edgeAura(in proxy: GeometryProxy) -> some View {
        let cornerRadius = min(proxy.size.width, proxy.size.height) * 0.136
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.28)
        let glowColor = colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.13)

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    glowColor,
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: edgePulse ? 2.4 : 1.5)
                .opacity(colorScheme == .dark ? 0.95 : 0.88)
        }
        .compositingGroup()
        .padding(1)
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: edgePulse)
    }
}

/// Estado Incognito del único InAppBanner. El timer y su panel participan en
/// el mismo `GlassEffectContainer`; no existe un toast o una pill paralela.
struct InAppIncognitoChrome<Compact: View>: View {
    @ObservedObject var service: IncognitoModeService
    /// Mensaje de activar/pausar: sin panel Pausar ni tap-expand.
    var showsCompactOnly: Bool = false
    let glassNamespace: Namespace.ID
    @ViewBuilder var compact: () -> Compact

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            compact()
                .overlay {
                    if !showsCompactOnly {
                        Color.clear
                            .contentShape(Capsule())
                            .onTapGesture {
                                HapticManager.shared.selection()
                                MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                                    isExpanded.toggle()
                                }
                            }
                            .accessibilityAddTraits(.isButton)
                    }
                }

            if isExpanded, !showsCompactOnly {
                IncognitoPausePanel(
                    service: service,
                    glassNamespace: glassNamespace
                )
                .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isExpanded), value: isExpanded)
        .onChange(of: service.isActive) { _, isActive in
            if !isActive {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded = false
                }
            }
        }
        .onChange(of: showsCompactOnly) { _, only in
            if only { isExpanded = false }
        }
    }

}

/// El contenido y el efecto pertenecen a la misma vista. Esto evita que una
/// capa de glass vacía refracte por encima del texto y del botón.
private struct IncognitoPausePanel: View {
    @ObservedObject var service: IncognitoModeService
    let glassNamespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("incognito.liveHint.active")
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Divider()
                .opacity(colorScheme == .dark ? 0.35 : 0.22)

            pauseButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
        // Conserva la geometría original del expandedPanel (230 × 106).
        // El alto fijo también estabiliza el cuello con la pill del timer.
        .frame(width: 230, height: 106, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .momentsChromeGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            interactive: true,
            style: .tinted
        )
        .modifier(IncognitoPausePanelIdentity(namespace: glassNamespace))
    }

    @ViewBuilder
    private var pauseButton: some View {
        let button = Button {
            HapticManager.shared.mediumImpact()
            service.pause()
        } label: {
            HStack(spacing: 10) {
                if service.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text("incognito.cta.pause")
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(service.isSyncing)

        if #available(iOS 26.0, *) {
            button
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(pauseButtonTint)
                .foregroundStyle(pauseButtonForeground)
        } else {
            button
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(pauseButtonTint)
                .foregroundStyle(pauseButtonForeground)
        }
    }

    private var pauseButtonTint: Color {
        colorScheme == .dark ? Color(white: 0.38) : Color(white: 0.72)
    }

    private var pauseButtonForeground: Color {
        colorScheme == .dark ? .white : .black
    }
}

private struct IncognitoPausePanelIdentity: ViewModifier {
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffectID("incognitoPausePanel", in: namespace)
                // Ya nace en su geometría final para que el container lo pinte
                // conectado al timer desde el primer frame.
                .glassEffectTransition(.identity)
        } else {
            content
        }
    }
}
