import SwiftUI
import UIKit

struct StoryLiveTextOverlayView: View {
    let metadata: StoryTextOverlayMetadata
    let containerSize: CGSize
    let replayToken: Int
    var animates: Bool = true
    var maxLayoutWidth: CGFloat? = nil

    var body: some View {
        if let config = metadata.scaledRenderConfiguration(
            containerWidth: containerSize.width
        ) {
            let anchor = metadata.displayPosition(in: containerSize)
            StoryTextOverlayContainerRepresentable(
                configuration: config,
                motion: animates ? metadata.motion : .none,
                maxWidth: overlayMaxWidth,
                replayToken: replayToken
            )
            .frame(maxWidth: overlayMaxWidth)
            .rotationEffect(.radians(metadata.rotationRadians))
            .position(x: anchor.x, y: anchor.y)
            .allowsHitTesting(false)
        }
    }

    private var overlayMaxWidth: CGFloat {
        if let maxLayoutWidth { return maxLayoutWidth }
        return metadata.resolvedMaxLayoutWidth(for: containerSize.width)
    }
}
