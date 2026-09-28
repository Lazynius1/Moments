import SwiftUI
import FirebaseAuth

/// Read-only counterpart to `HiddenLayersOverlayView` for cropped thumbnail surfaces.
/// It preserves each layer's normalized position while deliberately avoiding discovery,
/// playback and motion inside a scrolling grid.
struct HiddenLayersStaticPreviewSurface: View {
    let moment: Moment
    let size: CGSize
    let settings: MomentGridPreviewSettings

    @State private var layers: [MomentHiddenLayer] = []

    var body: some View {
        GeometryReader { proxy in
            let targetSize = proxy.size
            let mediaCanvasSize = previewMediaCanvasSize(in: targetSize)
            let layerCanvasSize = canonicalLayerCanvasSize
            let canvasScale = (mediaCanvasSize.width / layerCanvasSize.width) * settings.scale

            ZStack {
                ForEach(layers) { layer in
                    layerPreview(layer, in: layerCanvasSize)
                        .zIndex(Double(layer.zIndex))
                }
            }
            .frame(width: layerCanvasSize.width, height: layerCanvasSize.height)
            .scaleEffect(canvasScale)
            .offset(
                x: settings.offsetX * targetSize.width,
                // Kept in sync with GridPreviewThumbnailFrame's historic width-based offset.
                y: settings.offsetY * targetSize.width
            )
            .position(x: targetSize.width / 2, y: targetSize.height / 2)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
        .task(id: moment.id ?? "") {
            await loadLayers()
        }
    }

    @ViewBuilder
    private func layerPreview(_ layer: MomentHiddenLayer, in canvasSize: CGSize) -> some View {
        let frame = HiddenLayerLayout.frame(for: layer, in: CGRect(origin: .zero, size: canvasSize))

        Group {
            if isRevealed(layer) {
                revealedContent(for: layer, frameSize: frame.size)
            } else {
                HiddenLayerHintAppearanceView(
                    type: layer.type,
                    shape: layer.shape,
                    style: layer.hintStyle ?? .actual,
                    isSeen: false,
                    delay: 0,
                    isIntro: false,
                    isAnimated: false
                )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    @ViewBuilder
    private func revealedContent(for layer: MomentHiddenLayer, frameSize: CGSize) -> some View {
        switch layer.type {
        case .text:
            HiddenLayerTextReveal(layer: layer, frameSize: frameSize, isAnimated: false)
        case .image:
            if let mediaURL = layer.mediaURL, let url = URL(string: mediaURL) {
                HiddenLayerImageReveal(
                    url: url,
                    caption: layer.caption,
                    captionStyle: layer.textStyle,
                    frameStyle: layer.imageFrameStyle,
                    imageOffset: CGSize(width: layer.imageOffsetX ?? 0, height: layer.imageOffsetY ?? 0),
                    imageScale: layer.imageScale ?? 1,
                    canvasSize: frameSize,
                    isAnimated: false
                )
            }
        case .audio:
            if let mediaURL = layer.mediaURL {
                HiddenLayerAudioReveal(
                    audioURL: mediaURL,
                    duration: layer.duration ?? 15,
                    frameSize: frameSize,
                    shouldAutoplay: false,
                    isAnimated: false
                )
            }
        }
    }

    private func previewMediaCanvasSize(in targetSize: CGSize) -> CGSize {
        guard targetSize.width > 0, targetSize.height > 0 else { return .zero }

        let sourceAspectRatio = layerCanvasAspectRatio
        let targetAspectRatio = targetSize.width / targetSize.height
        let usesFit = settings.fitMode == .fit

        if (usesFit && sourceAspectRatio > targetAspectRatio) || (!usesFit && sourceAspectRatio < targetAspectRatio) {
            return CGSize(width: targetSize.width, height: targetSize.width / sourceAspectRatio)
        }
        return CGSize(width: targetSize.height * sourceAspectRatio, height: targetSize.height)
    }

    /// Layers are authored on a full-size post. Rendering them on the same
    /// canonical canvas before shrinking avoids the 44pt safety minimum in
    /// `HiddenLayerLayout` making every marker too large in a grid cell.
    private var canonicalLayerCanvasSize: CGSize {
        let width: CGFloat = 393
        return CGSize(width: width, height: width / layerCanvasAspectRatio)
    }

    private var layerCanvasAspectRatio: CGFloat {
        let mediaItem = moment.primaryVisibleMediaItem
        let mediaAspectRatio: CGFloat
        if let feedCrop = mediaItem?.feedCrop, !feedCrop.isFullBounds {
            mediaAspectRatio = feedCrop.cardAspectValue
        } else {
            mediaAspectRatio = mediaItem?.resolvedAspectRatioValue ?? 1
        }
        return min(max(mediaAspectRatio, HiddenLayerLayout.minimumPostAspectRatio), HiddenLayerLayout.maximumPostAspectRatio)
    }

    private func isRevealed(_ layer: MomentHiddenLayer) -> Bool {
        layer.isUnlocked() && UserDefaults.standard.bool(forKey: seenKey(for: layer))
    }

    private func seenKey(for layer: MomentHiddenLayer) -> String {
        let viewerId = Auth.auth().currentUser?.uid ?? "anonymous"
        return "hiddenLayerSeen:\(viewerId):\(moment.id ?? "unknown"):\(layer.id)"
    }

    private func loadLayers() async {
        guard moment.hasHiddenLayers, let momentId = moment.id else {
            layers = []
            return
        }

        await withCheckedContinuation { continuation in
            FirestoreService.shared.fetchHiddenLayers(userId: moment.authorId, momentId: momentId) { result in
                let fetched = (try? result.get()) ?? []
                let visible = fetched
                    .filter(\.isVisibleInViewer)
                    .sorted { $0.zIndex < $1.zIndex }

                Task { @MainActor in
                    layers = visible
                    continuation.resume()
                }
            }
        }
    }
}
