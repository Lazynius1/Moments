import SwiftUI
import AVFoundation

enum MomentCarouselPresentationMode: Equatable {
    case fill
    case fitWithBlur

    var swiftUIContentMode: ContentMode {
        switch self {
        case .fill:
            return .fill
        case .fitWithBlur:
            return .fit
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            return .resizeAspectFill
        case .fitWithBlur:
            return .resizeAspect
        }
    }
}

enum MomentCarouselLayoutRules {
    private static let horizontalTolerance: CGFloat = 0.035
    private static let squareCutoff: CGFloat = 1.15

    static func presentationMode(
        for mediaAspectRatio: CGFloat,
        canvasAspectRatio: CGFloat
    ) -> MomentCarouselPresentationMode {
        guard
            mediaAspectRatio.isFinite,
            mediaAspectRatio > 0,
            canvasAspectRatio.isFinite,
            canvasAspectRatio > 0
        else {
            return .fill
        }

        // Feed/post carousels should behave like normal posts for vertical
        // and near-square media. Reserve blur only for clearly landscape items.
        let clearlyWiderThanCanvas = mediaAspectRatio > (canvasAspectRatio + horizontalTolerance)
        let isClearlyLandscape = mediaAspectRatio > squareCutoff

        return (clearlyWiderThanCanvas && isClearlyLandscape) ? .fitWithBlur : .fill
    }
}

// MARK: - Indicadores de página (unificados en feed, detalle, explore, mapa, guardados)

enum MomentCarouselIndicatorStyle {
    static let dotWidth: CGFloat = 6
    static let dotHeight: CGFloat = 4
    static let spacing: CGFloat = 6
    static let activeScale: CGFloat = 1.15
    static let inactiveOpacity: Double = 0.35

    /// Canvas AdaptiveColors: dark `#0B1215` / light `#FAF9F6`.
    static let canvasDark = Color(hex: "0B1215")
    static let canvasLight = Color(hex: "FAF9F6")

    static var inactiveColor: Color { canvasLight.opacity(inactiveOpacity) }

    /// Punto activo: el color del canvas contrario (se lee sobre media y sobre el fondo).
    static func activeColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? canvasLight : canvasDark
    }

    static func inactiveColor(for colorScheme: ColorScheme) -> Color {
        activeColor(for: colorScheme).opacity(inactiveOpacity)
    }
}

/// Métricas compartidas para cards estilo feed (edge-to-edge).
enum FeedMomentCardLayout {
    /// Padding lateral del scroll que envuelve las cards.
    static let listHorizontalPadding: CGFloat = 4
    /// Padding interno del header (avatar + username).
    static let headerHorizontalPadding: CGFloat = 8
    /// Padding de la rail de acciones sobre el media.
    static let actionRowHorizontalPadding: CGFloat = 4
    /// Padding del caption bajo el media (alineado con el borde del media / action row).
    static let captionHorizontalPadding: CGFloat = 4
    /// Radio suave compartido: feed, reels, canvas de stories y editor.
    static let mediaCornerRadius: CGFloat = 12

    static var continuousRoundedRect: RoundedRectangle {
        RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
    }

    static func scaledMediaCornerRadius(_ scale: CGFloat) -> CGFloat {
        mediaCornerRadius * scale
    }

    /// Alias semántico para el canvas de stories (mismo radio que el feed).
    static var storyCanvasCornerRadius: CGFloat { mediaCornerRadius }

    /// Long-press peek y hero del grid de perfil.
    static var peekCornerRadius: CGFloat { mediaCornerRadius }

    static func mediaContentWidth(containerWidth: CGFloat) -> CGFloat {
        max(containerWidth - (listHorizontalPadding * 2), 1)
    }
}

/// Puntos de carrusel (feed / eco / detalle).
/// IG 2026: hold hasta que se abre la pastilla, luego arrastra L/R para pasar slides.
struct MomentCarouselPageIndicators: View {
    enum Tone {
        /// Sobre la foto (puntos blancos).
        case onMedia
        /// Debajo de la card (canvas AdaptiveColors).
        case onCanvas
    }

    let count: Int
    @Binding var currentIndex: Int
    var tone: Tone = .onMedia

    @Environment(\.colorScheme) private var colorScheme
    @State private var isScrubbing = false

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var activeFill: Color {
        MomentCarouselIndicatorStyle.activeColor(for: colorScheme)
    }

    private var inactiveFill: Color {
        MomentCarouselIndicatorStyle.inactiveColor(for: colorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = isScrubbing
                ? MomentCarouselIndicatorStyle.spacing + 4
                : MomentCarouselIndicatorStyle.spacing
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(currentIndex == index ? activeFill : inactiveFill)
                        .frame(
                            width: isScrubbing ? 8 : MomentCarouselIndicatorStyle.dotWidth,
                            height: isScrubbing ? 8 : MomentCarouselIndicatorStyle.dotHeight
                        )
                        .scaleEffect(
                            currentIndex == index ? MomentCarouselIndicatorStyle.activeScale : 1.0,
                            anchor: .center
                        )
                }
            }
            .padding(.horizontal, isScrubbing ? 14 : 10)
            .padding(.vertical, isScrubbing ? 10 : 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(isScrubbing ? 1 : 0)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(adaptiveColors.primary.opacity(isScrubbing ? 0.16 : 0), lineWidth: 1)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(scrubGesture(width: proxy.size.width))
        }
        .frame(height: isScrubbing ? 36 : 24)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isScrubbing)
        .animation(.easeInOut(duration: 0.12), value: currentIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(currentIndex + 1) de \(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                commitIndex(min(count - 1, currentIndex + 1))
            case .decrement:
                commitIndex(max(0, currentIndex - 1))
            @unknown default:
                break
            }
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.16)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if !isScrubbing {
                        isScrubbing = true
                        HapticManager.shared.lightImpact()
                    }
                    guard let drag else { return }
                    commitIndex(index(at: drag.location.x, width: width))
                default:
                    break
                }
            }
            .onEnded { _ in
                isScrubbing = false
            }
    }

    private func index(at x: CGFloat, width: CGFloat) -> Int {
        guard count > 1, width > 0 else { return 0 }
        let t = min(max(x / width, 0), 0.999)
        return Int(t * CGFloat(count))
    }

    private func commitIndex(_ next: Int) {
        let clamped = min(max(next, 0), max(count - 1, 0))
        guard clamped != currentIndex else { return }
        currentIndex = clamped
        HapticManager.shared.selection()
    }
}
