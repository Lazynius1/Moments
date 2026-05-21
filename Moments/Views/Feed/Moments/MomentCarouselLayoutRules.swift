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
