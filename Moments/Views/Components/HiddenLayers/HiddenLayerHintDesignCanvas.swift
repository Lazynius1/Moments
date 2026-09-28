import SwiftUI

#if DEBUG
/// A visual decision board for the unrevealed Hidden Layer affordance.
/// Preview-only: production keeps its current hint until one direction is wired in.
/// Every proposal keeps the same silhouette as production (halo · core · shimmer arc · glint · 12 sparks).
struct HiddenLayerHintDesignCanvas: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hidden Layer hints")
                        .font(.title2.weight(.bold))
                    Text("Same hint DNA as production — only palette and tempo change")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    HintDirectionCard(
                        title: "Moments · Dark",
                        subtitle: "Canvas #0B1215 · white ↔ champagne stars",
                        canvas: Color(hex: "0B1215"),
                        titleColor: .white,
                        subtitleColor: .white.opacity(0.62),
                        hint: AnyView(MomentsAdaptiveHiddenLayerHint(forcedScheme: .dark))
                    )
                    HintDirectionCard(
                        title: "Moments · Light",
                        subtitle: "Canvas #FAF9F6 · ink ↔ warm sand stars",
                        canvas: Color(hex: "FAF9F6"),
                        titleColor: .black,
                        subtitleColor: .black.opacity(0.55),
                        hint: AnyView(MomentsAdaptiveHiddenLayerHint(forcedScheme: .light))
                    )
                    HintDirectionCard(
                        title: "Actual",
                        subtitle: "Warm gold · production twin",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .actual))
                    )
                    HintDirectionCard(
                        title: "Polar",
                        subtitle: "Ice cyan + violet · star sparkles",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .polar))
                    )
                    HintDirectionCard(
                        title: "Ember",
                        subtitle: "Coral + electric amber",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .ember))
                    )
                    HintDirectionCard(
                        title: "Ultraviolet",
                        subtitle: "Violet + lime · star sparkles",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .ultraviolet))
                    )
                    HintDirectionCard(
                        title: "Aurora",
                        subtitle: "Mint + teal · star sparkles",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .aurora))
                    )
                    HintDirectionCard(
                        title: "Rose",
                        subtitle: "Blush + hot pink · softer glow",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .rose))
                    )
                    HintDirectionCard(
                        title: "Plasma",
                        subtitle: "Magenta rim · star sparkles",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .plasma))
                    )
                    HintDirectionCard(
                        title: "Daylight",
                        subtitle: "Cool white + sky blue",
                        hint: AnyView(HiddenLayerHintPrototype(palette: .daylight))
                    )
                }
            }
            .padding(20)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

private struct HintDirectionCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var canvas: Color? = nil
    var titleColor: Color = .white
    var subtitleColor: Color = .white.opacity(0.62)
    let hint: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let canvas {
                    canvas
                } else {
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                hint
            }
            .frame(height: 154)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(title)
                .font(.headline)
                .foregroundStyle(titleColor)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(subtitleColor)
        }
    }
}

/// Hint alineado al canvas Moments: sin arco giratorio, estrellas mágicas
/// que cruzan entre dos colores según el color scheme.
private struct MomentsAdaptiveHiddenLayerHint: View {
    var forcedScheme: ColorScheme? = nil
    @Environment(\.colorScheme) private var environmentScheme

    @State private var pulse = false
    @State private var orbitPhase: CGFloat = 0
    @State private var glint = false

    private var scheme: ColorScheme { forcedScheme ?? environmentScheme }

    private var isDark: Bool { scheme == .dark }

    /// Dark: blanco ↔ champagne. Light: tinta suave ↔ arena cálida.
    private var starA: Color {
        isDark
            ? .white
            : Color(red: 0.18, green: 0.22, blue: 0.26) // soft ink
    }

    private var starB: Color {
        isDark
            ? Color(red: 0.96, green: 0.88, blue: 0.70) // champagne
            : Color(red: 0.78, green: 0.62, blue: 0.38) // warm sand / bronze
    }

    private var haloBase: Color {
        isDark
            ? Color(red: 0.96, green: 0.88, blue: 0.70).opacity(0.42)
            : Color(red: 0.78, green: 0.62, blue: 0.38).opacity(0.28)
    }

    private var haloAccent: Color {
        isDark
            ? Color.white.opacity(0.22)
            : Color(red: 0.18, green: 0.22, blue: 0.26).opacity(0.10)
    }

    private var coreFill: Color {
        isDark ? Color.white.opacity(0.78) : Color(red: 0.22, green: 0.26, blue: 0.30).opacity(0.55)
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    haloBase.opacity(pulse ? 1 : 0.7),
                    haloAccent,
                    .clear
                ],
                center: .center,
                startRadius: 3,
                endRadius: 32
            )
            .blur(radius: 10)
            .blendMode(isDark ? .plusLighter : .multiply)

            RadialGradient(
                colors: [coreFill, .clear],
                center: .center,
                startRadius: 1,
                endRadius: 18
            )
            .blendMode(isDark ? .screen : .normal)

            // Glint puntual (sin arco).
            Circle()
                .fill(isDark ? Color.white : starA)
                .frame(width: 6, height: 6)
                .offset(x: -8, y: -8)
                .opacity(glint ? 0.95 : 0.28)
                .blur(radius: 0.25)

            ForEach(0..<12, id: \.self) { index in
                let twinkle = starTwinkle(for: index)
                MagicalStar(points: index.isMultiple(of: 2) ? 4 : 5)
                    .fill(starColor(for: index))
                    .frame(width: starSize(for: index), height: starSize(for: index))
                    .scaleEffect(twinkle)
                    .opacity(starOpacity(for: index))
                    .blur(radius: twinkle > 1.25 ? 0.45 : 0)
                    .rotationEffect(.degrees(Double(index) * 16 + Double(orbitPhase) * 100))
                    .offset(sparkOffset(for: index))
                    .shadow(color: starB.opacity(isDark ? 0.7 : 0.35), radius: 3)
            }
        }
        .frame(width: 52, height: 52)
        .scaleEffect(pulse ? 1.07 : 0.94)
        .shadow(color: starB.opacity(isDark ? 0.35 : 0.18), radius: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 4.8).repeatForever(autoreverses: false)) { orbitPhase = 1 }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { glint = true }
        }
    }

    private func sparkOffset(for index: Int) -> CGSize {
        let speed = 1 + CGFloat(index % 3) * 0.2
        let angle = (CGFloat(index) * .pi * 2 / 12) + orbitPhase * .pi * 2 * speed
        let radius = 19 + CGFloat(index % 3) * 2
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    private func starSize(for index: Int) -> CGFloat {
        let sizes: [CGFloat] = [6.5, 4.0, 7.5, 3.5, 5.5, 4.5, 7.0, 3.8, 6.0, 5.0, 7.2, 3.2]
        return sizes[index % sizes.count]
    }

    private func starTwinkle(for index: Int) -> CGFloat {
        let phase = orbitPhase * .pi * (8 + CGFloat(index % 5)) + CGFloat(index) * 1.3
        return 0.28 + abs(sin(phase)) * 1.45
    }

    private func starOpacity(for index: Int) -> CGFloat {
        let phase = orbitPhase * .pi * (6 + CGFloat(index % 4)) + CGFloat(index) * 0.9
        return 0.22 + abs(sin(phase)) * 0.78
    }

    /// Cruza starA ↔ starB según el twinkle de cada estrella.
    private func starColor(for index: Int) -> Color {
        let phase = orbitPhase * .pi * (5 + CGFloat(index % 4)) + CGFloat(index) * 1.1
        let t = (sin(phase) + 1) / 2 // 0...1
        return starA.mix(with: starB, amount: t)
    }
}

private extension Color {
    /// Interpolación simple sRGB para el morph de color de las estrellas.
    func mix(with other: Color, amount: CGFloat) -> Color {
        let t = max(0, min(amount, 1))
        let a = UIColor(self)
        let b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            opacity: aa + (ba - aa) * t
        )
    }
}

/// Shared silhouette of the production Hidden Layer hint.
/// Variants only swap colors and subtle animation timing.
private struct HiddenLayerHintPrototype: View {
    struct Palette {
        let base: Color
        let accent: Color
        let coreHighlight: Color
        let arc: Color
        let pulseDuration: Double
        let shimmerDuration: Double
        let orbitDuration: Double
        let glintDuration: Double
        let sparkCount: Int
        let sparkRadius: CGFloat
        /// `true` = chispas con forma de estrella (SF Symbol sparkle).
        let starSparks: Bool

        static let actual = Palette(
            base: Color(red: 1.0, green: 0.92, blue: 0.62),
            accent: Color(red: 0.98, green: 0.82, blue: 0.42),
            coreHighlight: .white,
            arc: .white,
            pulseDuration: 1.2,
            shimmerDuration: 3.2,
            orbitDuration: 4.5,
            glintDuration: 1.8,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: false
        )

        static let polar = Palette(
            base: Color(red: 0.55, green: 0.95, blue: 1.0),
            accent: Color(red: 0.62, green: 0.48, blue: 1.0),
            coreHighlight: .white,
            arc: Color(red: 0.78, green: 0.98, blue: 1.0),
            pulseDuration: 1.15,
            shimmerDuration: 3.0,
            orbitDuration: 4.2,
            glintDuration: 1.6,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: true
        )

        static let ember = Palette(
            base: Color(red: 1.0, green: 0.55, blue: 0.28),
            accent: Color(red: 1.0, green: 0.78, blue: 0.18),
            coreHighlight: Color(red: 1.0, green: 0.96, blue: 0.82),
            arc: Color(red: 1.0, green: 0.88, blue: 0.55),
            pulseDuration: 1.0,
            shimmerDuration: 2.8,
            orbitDuration: 4.0,
            glintDuration: 1.4,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: false
        )

        static let ultraviolet = Palette(
            base: Color(red: 0.78, green: 0.42, blue: 1.0),
            accent: Color(red: 0.78, green: 1.0, blue: 0.28),
            coreHighlight: .white,
            arc: Color(red: 0.92, green: 0.72, blue: 1.0),
            pulseDuration: 1.1,
            shimmerDuration: 2.6,
            orbitDuration: 3.8,
            glintDuration: 1.5,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: true
        )

        static let aurora = Palette(
            base: Color(red: 0.42, green: 1.0, blue: 0.78),
            accent: Color(red: 0.22, green: 0.82, blue: 0.95),
            coreHighlight: .white,
            arc: Color(red: 0.72, green: 1.0, blue: 0.92),
            pulseDuration: 1.25,
            shimmerDuration: 3.4,
            orbitDuration: 4.8,
            glintDuration: 1.9,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: true
        )

        static let rose = Palette(
            base: Color(red: 1.0, green: 0.62, blue: 0.78),
            accent: Color(red: 1.0, green: 0.32, blue: 0.58),
            coreHighlight: .white,
            arc: Color(red: 1.0, green: 0.86, blue: 0.92),
            pulseDuration: 1.3,
            shimmerDuration: 3.5,
            orbitDuration: 5.0,
            glintDuration: 2.0,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: false
        )

        static let plasma = Palette(
            base: Color(red: 1.0, green: 0.55, blue: 0.92),
            accent: Color(red: 0.95, green: 0.25, blue: 0.72),
            coreHighlight: .white,
            arc: .white,
            pulseDuration: 0.95,
            shimmerDuration: 2.4,
            orbitDuration: 3.6,
            glintDuration: 1.25,
            sparkCount: 12,
            sparkRadius: 20,
            starSparks: true
        )

        static let daylight = Palette(
            base: Color(red: 0.86, green: 0.94, blue: 1.0),
            accent: Color(red: 0.35, green: 0.72, blue: 1.0),
            coreHighlight: .white,
            arc: .white,
            pulseDuration: 1.35,
            shimmerDuration: 3.6,
            orbitDuration: 5.2,
            glintDuration: 2.1,
            sparkCount: 12,
            sparkRadius: 19,
            starSparks: false
        )
    }

    let palette: Palette
    @State private var pulse = false
    @State private var shimmerPhase: CGFloat = 0
    @State private var orbitPhase: CGFloat = 0
    @State private var glint = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    palette.base.opacity(pulse ? 0.56 : 0.38),
                    palette.accent.opacity(pulse ? 0.32 : 0.16),
                    .clear
                ],
                center: .center,
                startRadius: 4,
                endRadius: 34
            )
            .blur(radius: 10)
            .blendMode(.plusLighter)

            ZStack {
                RadialGradient(
                    colors: [
                        palette.coreHighlight.opacity(0.72),
                        palette.base.opacity(0.62),
                        .clear
                    ],
                    center: .center,
                    startRadius: 1,
                    endRadius: 22
                )

                Circle()
                    .trim(from: 0.10, to: 0.52)
                    .stroke(palette.arc.opacity(0.52), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 37, height: 37)
                    .rotationEffect(.degrees(-35))
                    .rotationEffect(.degrees(shimmerPhase * 360))
                    .blur(radius: 2)
            }
            .blendMode(.screen)

            Circle()
                .fill(palette.coreHighlight)
                .frame(width: 7, height: 7)
                .offset(x: -9, y: -9)
                .opacity(glint ? 1 : 0.32)
                .blur(radius: 0.3)

            ForEach(0..<palette.sparkCount, id: \.self) { index in
                let color = index.isMultiple(of: 3) ? palette.accent : palette.base
                Group {
                    if palette.starSparks {
                        MagicalStar(points: index.isMultiple(of: 2) ? 4 : 5)
                            .fill(
                                RadialGradient(
                                    colors: [.white, color],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 4
                                )
                            )
                            .frame(
                                width: starSize(for: index),
                                height: starSize(for: index)
                            )
                            .scaleEffect(starTwinkle(for: index))
                            .opacity(starOpacity(for: index))
                            .blur(radius: starTwinkle(for: index) > 1.2 ? 0.4 : 0)
                            .rotationEffect(.degrees(Double(index) * 18 + Double(orbitPhase) * 120))
                    } else {
                        Circle()
                            .fill(color)
                            .frame(width: index.isMultiple(of: 4) ? 3.5 : 2)
                    }
                }
                .offset(sparkOffset(for: index))
                .shadow(
                    color: palette.accent.opacity(palette.starSparks ? 0.95 : 0.8),
                    radius: palette.starSparks ? 3.5 : 2
                )
            }
        }
        .frame(width: 52, height: 52)
        .scaleEffect(pulse ? 1.08 : 0.93)
        .shadow(color: palette.accent.opacity(0.46), radius: 15)
        .onAppear {
            withAnimation(.easeInOut(duration: palette.pulseDuration).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: palette.shimmerDuration).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
            withAnimation(.linear(duration: palette.orbitDuration).repeatForever(autoreverses: false)) {
                orbitPhase = 1
            }
            withAnimation(.easeInOut(duration: palette.glintDuration).repeatForever(autoreverses: true)) {
                glint = true
            }
        }
    }

    private func sparkOffset(for index: Int) -> CGSize {
        let count = CGFloat(max(palette.sparkCount, 1))
        let speed = 1 + CGFloat(index % 3) * 0.2
        let angle = (CGFloat(index) * .pi * 2 / count) + orbitPhase * .pi * 2 * speed
        let radius = palette.sparkRadius + CGFloat(index % 3) * 2
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    private func starSize(for index: Int) -> CGFloat {
        let sizes: [CGFloat] = [6.5, 4.0, 7.5, 3.5, 5.5, 4.5, 7.0, 3.8, 6.0, 5.0, 7.2, 3.2]
        return sizes[index % sizes.count]
    }

    /// Crecen y se apagan como destellos mágicos, desfasados por partícula.
    private func starTwinkle(for index: Int) -> CGFloat {
        let phase = orbitPhase * .pi * (8 + CGFloat(index % 5)) + CGFloat(index) * 1.3
        return 0.28 + abs(sin(phase)) * 1.45
    }

    private func starOpacity(for index: Int) -> CGFloat {
        let phase = orbitPhase * .pi * (6 + CGFloat(index % 4)) + CGFloat(index) * 0.9
        return 0.18 + abs(sin(phase)) * 0.82
    }
}

/// Estrella dibujada (4 o 5 puntas), no SF Symbol.
private struct MagicalStar: Shape {
    var points: Int = 4

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * (points == 4 ? 0.28 : 0.38)
        let count = max(points, 3)
        var path = Path()
        for i in 0..<(count * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = CGFloat(i) * .pi / CGFloat(count) - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Hidden Layer hint directions") {
    HiddenLayerHintDesignCanvas()
}
#endif
