import SwiftUI
import UIKit

struct StoryLiveTextOverlayView: View {
    let metadata: StoryTextOverlayMetadata
    let containerSize: CGSize
    let replayToken: Int

    var body: some View {
        if let config = metadata.scaledRenderConfiguration(
            containerWidth: containerSize.width
        ) {
            let anchor = metadata.displayPosition(in: containerSize)
            StoryTextOverlayContainerRepresentable(
                configuration: config,
                motion: metadata.motion,
                maxWidth: overlayMaxWidth,
                replayToken: replayToken
            )
            .frame(maxWidth: overlayMaxWidth)
            .position(x: anchor.x, y: anchor.y)
            .allowsHitTesting(false)
        }
    }

    private var overlayMaxWidth: CGFloat {
        max(containerSize.width - 48, 120)
    }
}
