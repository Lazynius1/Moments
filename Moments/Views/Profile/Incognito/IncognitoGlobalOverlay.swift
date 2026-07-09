import SwiftUI

struct IncognitoGlobalOverlay: View {
    @ObservedObject var service: IncognitoModeService
    @Environment(\.colorScheme) private var colorScheme

    @State private var isExpanded = false
    @State private var edgePulse = false

    private var auraPrimary: Color {
        colorScheme == .dark ? Color(hex: "A7F3FF") : Color(hex: "0F8EAD")
    }

    private var auraSecondary: Color {
        colorScheme == .dark ? Color(hex: "6E8BFF") : Color(hex: "275DCC")
    }

    private var pillTitleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                edgeAura(in: proxy)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    pill
                        .padding(.top, max(proxy.safeAreaInsets.top + 38, 52))
                        .padding(.horizontal, 16)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            edgePulse = true
        }
        .onChange(of: service.isActive) { _, isActive in
            if !isActive {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded = false
                }
            }
        }
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isExpanded), value: isExpanded)
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
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: edgePulse)
    }

    private var pill: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedPanel
                    .padding(.top, 48)
                    .transition(.incognitoPillDrop)
            }

            compactPill
        }
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? 164 : 40, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var compactPill: some View {
        Button {
            HapticManager.shared.selection()
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pillTitleColor)
                    .frame(width: 18, height: 18)

                Text(service.formattedTime)
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(pillTitleColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12),
            radius: 10,
            x: 0,
            y: 6
        )
        .frame(width: 108, height: 40)
    }

    private var expandedPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .frame(width: 230, height: 106)
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("incognito.liveHint.active")
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    HapticManager.shared.mediumImpact()
                    service.pause()
                } label: {
                    HStack(spacing: 10) {
                        if service.isSyncing {
                            ProgressView()
                                .tint(pillTitleColor)
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }

                        Text("incognito.cta.pause")
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    }
                    .foregroundStyle(pillTitleColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: !service.isSyncing))
                }
                .buttonStyle(.plain)
                .disabled(service.isSyncing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 230, height: 106)
        }
        .frame(width: 230, height: 106, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.10 : 0.08),
                    lineWidth: 0.75
                )
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10),
            radius: 16,
            x: 0,
            y: 8
        )
    }
}

private struct IncognitoDropTransitionModifier: AnimatableModifier {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = max(0, min(progress, 1))
        let stretch = clamped + (sin(clamped * .pi) * 0.08)
        let translate = (1 - clamped) * -18

        return content
            .scaleEffect(x: 1, y: max(0.001, stretch), anchor: .top)
            .offset(y: translate)
            .opacity(clamped)
            .blur(radius: (1 - clamped) * 6)
    }
}

private extension AnyTransition {
    static var incognitoPillDrop: AnyTransition {
        .modifier(
            active: IncognitoDropTransitionModifier(progress: 0),
            identity: IncognitoDropTransitionModifier(progress: 1)
        )
    }
}
