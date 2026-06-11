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

    private static let palette: [Color] = [
        Color(hex: "#5b2c6f"),
        Color(hex: "#007bff"),
        Color(hex: "#40dfcf"),
        Color(hex: "#ff6b6b"),
        Color(hex: "#4ecdc4"),
        Color(hex: "#45b7d1"),
        Color(hex: "#96ceb4"),
        Color(hex: "#feca57"),
    ]

    static var inactiveColor: Color { .white.opacity(inactiveOpacity) }

    static func activeColor(for index: Int) -> Color {
        palette[index % palette.count]
    }
}

struct MomentCarouselPageIndicators: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: MomentCarouselIndicatorStyle.spacing) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(
                        currentIndex == index
                            ? MomentCarouselIndicatorStyle.activeColor(for: index)
                            : MomentCarouselIndicatorStyle.inactiveColor
                    )
                    .frame(
                        width: MomentCarouselIndicatorStyle.dotWidth,
                        height: MomentCarouselIndicatorStyle.dotHeight
                    )
                    .scaleEffect(
                        currentIndex == index ? MomentCarouselIndicatorStyle.activeScale : 1.0,
                        anchor: .center
                    )
            }
        }
    }
}
