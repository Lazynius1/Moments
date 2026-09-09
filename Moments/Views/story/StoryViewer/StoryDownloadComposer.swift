import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Exporta una historia a MP4 con overlays (stickers + texto), aparte del publish.
/// Foto → vídeo de 5 s. Vídeo → misma duración. El media publicado no se reescribe.
enum StoryDownloadComposer {
    static let stillDuration = CMTime(seconds: 5, preferredTimescale: 600)

    static func canvasSize() -> CGSize {
        evenSize(storyRenderCanvasSize())
    }

    static func exportToTemporaryVideo(
        story: Story,
        stickers: [StickerItem],
        layoutSize: CGSize,
        colorScheme: ColorScheme
    ) async throws -> URL {
        let targetSize = canvasSize()

        guard let mediaURL = URL(string: story.mediaItem.url) else {
            throw StoryDownloadError.missingMedia
        }

        if story.mediaItem.type == .video {
            let (downloadURL, _) = try await URLSession.shared.download(from: mediaURL)
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("story_download_src_\(UUID().uuidString).mp4")
            try FileManager.default.moveItem(at: downloadURL, to: sourceURL)
            defer { try? FileManager.default.removeItem(at: sourceURL) }
            let base = try await exportVideo(
                sourceURL: sourceURL,
                overlay: nil,
                background: solidImage(size: targetSize, color: UIColor(Color(hex: colorScheme == .dark ? "0B1215" : "FAF9F6"))),
                targetSize: targetSize,
                editorCanvasSize: targetSize,
                imageScale: 1,
                imageOffset: .zero,
                imageRotation: .zero
            )
            if stickers.isEmpty && story.resolvedTextOverlays.isEmpty { return base }
            defer { try? FileManager.default.removeItem(at: base) }
            return try await addLiveOverlays(to: base, stickers: stickers,
                textOverlays: story.resolvedTextOverlays, storyId: story.id ?? "",
                userId: story.authorId, size: targetSize, layoutSize: layoutSize, colorScheme: colorScheme)
        }

        let (data, _) = try await URLSession.shared.data(from: mediaURL)
        guard let image = UIImage(data: data) else {
            throw StoryDownloadError.missingMedia
        }
        let frame = compositeStill(image: image, overlay: nil, targetSize: targetSize, layoutWidth: layoutSize.width)
        let base = try await writeStillVideo(from: frame, size: targetSize, duration: stillDuration)
        guard !stickers.isEmpty || !story.resolvedTextOverlays.isEmpty else { return base }
        defer { try? FileManager.default.removeItem(at: base) }
        return try await addLiveOverlays(to: base, stickers: stickers,
            textOverlays: story.resolvedTextOverlays, storyId: story.id ?? "",
            userId: story.authorId, size: targetSize, layoutSize: layoutSize, colorScheme: colorScheme)
    }

    /// Build an independent export scene. UIKit is used only to prepare artwork;
    /// AVFoundation evaluates animation and video on the output timeline.
    @MainActor
    static func addLiveOverlays(
        to sourceURL: URL,
        stickers: [StickerItem],
        textOverlays: [StoryTextOverlayMetadata],
        storyId: String,
        userId: String,
        size: CGSize,
        layoutSize: CGSize,
        colorScheme: ColorScheme,
        textMaxLayoutWidth: CGFloat? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw StoryDownloadError.exportFailed }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_assets_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var mediaSources: [URL: AVURLAsset] = [:]
        let audioURLs = stickers.filter { $0.type == .audio }
            .compactMap { $0.interactionData?.audioURL }.compactMap(URL.init(string:))
        for url in Set(stickers.compactMap(\.videoURL) + audioURLs) {
            try Task.checkCancellation()
            let local: URL
            if url.isFileURL { local = url }
            else {
                let (download, _) = try await URLSession.shared.download(from: url)
                local = directory.appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
                try FileManager.default.moveItem(at: download, to: local)
            }
            mediaSources[url] = AVURLAsset(url: local)
        }
        var gifs: [URL: UIImage] = [:]
        for url in Set(stickers.compactMap(\.gifURL)) {
            if let cached = GIFCache.shared.getGIF(for: url) { gifs[url] = cached }
            else {
                let data: Data
                if url.isFileURL {
                    data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
                } else {
                    data = try await URLSession.shared.data(from: url).0
                }
                let animated = await Task.detached(priority: .userInitiated) {
                    UIImage.animatedImageWithData(data)
                }.value
                guard let animated else { throw StoryDownloadError.missingMedia }
                GIFCache.shared.setGIF(animated, for: url)
                gifs[url] = animated
            }
        }

        let logicalWidth = max(layoutSize.width, 1)
        let logicalSize = CGSize(width: logicalWidth, height: logicalWidth * size.height / size.width)
        let scale = size.width / logicalWidth
        let exportDate = Date()
        var scene: [(order: Int, element: StoryExportElement)] = []
        for text in textOverlays {
            try Task.checkCancellation()
            await Task.yield()
            if let layer = StoryExportArtwork.textLayer(text, canvas: logicalSize,
                scale: scale, maxWidth: textMaxLayoutWidth, colorScheme: colorScheme) {
                scene.append((text.layerOrder, .layer(layer)))
            }
        }
        for sticker in stickers {
            try Task.checkCancellation()
            let element: StoryExportElement
            if let url = sticker.videoURL, let source = mediaSources[url] {
                let black = try await StoryExportArtwork.snapshotSticker(sticker,
                    canvas: logicalSize, scale: scale, storyId: storyId, userId: userId,
                    colorScheme: colorScheme, videoColor: .black)
                guard let slot = black.videoSlot, let white = black.whiteImage else {
                    throw StoryDownloadError.exportFailed
                }
                let seconds = try await source.load(.duration).seconds
                guard seconds.isFinite, seconds > 0 else { throw StoryDownloadError.missingMedia }
                element = .video(try StoryExportVideoArtwork(asset: source, duration: seconds,
                    black: black.image, white: white, slot: slot, canvasSize: size))
            } else if let url = sticker.gifURL, let gif = gifs[url] {
                element = .layer(StoryExportArtwork.gifLayer(gif, sticker: sticker,
                    canvas: logicalSize, scale: scale))
            } else if sticker.type == .countdown {
                element = .layer(try await StoryExportArtwork.countdownLayer(sticker,
                    canvas: logicalSize, scale: scale, startDate: exportDate,
                    duration: duration, colorScheme: colorScheme))
            } else if sticker.type == .audio,
                      let path = sticker.interactionData?.audioURL,
                      let url = URL(string: path), let source = mediaSources[url] {
                let seconds = try await source.load(.duration).seconds
                guard seconds.isFinite, seconds > 0 else { throw StoryDownloadError.missingMedia }
                let background = try await StoryExportArtwork.snapshotSticker(sticker,
                    canvas: logicalSize, scale: scale, storyId: storyId,
                    userId: userId, colorScheme: colorScheme)
                element = .layer(StoryExportArtwork.audioLayer(sticker, background: background.image,
                    canvas: logicalSize, scale: scale, duration: seconds))
            } else {
                let artwork = try await StoryExportArtwork.snapshotSticker(sticker,
                    canvas: logicalSize, scale: scale, storyId: storyId,
                    userId: userId, colorScheme: colorScheme)
                let layer = CALayer()
                layer.frame = CGRect(origin: .zero, size: size)
                layer.contents = artwork.image
                element = .layer(layer)
            }
            scene.append((sticker.zIndex, element))
        }
        // Keep the same insertion order for elements sharing a z index.
        let ordered = scene.enumerated().sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.map { $0.element.element }
        let audioSources: [(asset: AVAsset, loops: Bool)] = stickers.compactMap { sticker in
            if sticker.type == .shareMoment, let url = sticker.videoURL, let source = mediaSources[url] {
                return (source, true)
            }
            if sticker.type == .audio, let path = sticker.interactionData?.audioURL,
               let url = URL(string: path), let source = mediaSources[url] { return (source, false) }
            return nil
        }
        var current: AVAsset = try await assetByAddingSharedAudio(to: asset, sources: audioSources)
        var pending: [CALayer] = []
        var outputs: [URL] = []
        var result: URL?
        defer { for url in outputs where url != result { try? FileManager.default.removeItem(at: url) } }
        for element in ordered {
            switch element {
            case .layer(let layer): pending.append(layer)
            case .video(let video):
                if !pending.isEmpty {
                    let output = try await exportLayers(pending, over: current, size: size)
                    outputs.append(output)
                    current = AVURLAsset(url: output)
                    pending.removeAll()
                }
                let output = try await video.export(over: current)
                outputs.append(output)
                current = AVURLAsset(url: output)
            }
        }
        if !pending.isEmpty || outputs.isEmpty {
            let output = try await exportLayers(pending, over: current, size: size)
            outputs.append(output)
        }
        result = outputs.last
        guard let result else { throw StoryDownloadError.exportFailed }
        return result
    }

    @MainActor
    private static func exportLayers(_ layers: [CALayer], over asset: AVAsset, size: CGSize) async throws -> URL {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryDownloadError.missingMedia
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let trackInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        trackInstruction.setTransform(try await track.load(.preferredTransform), at: .zero)
        instruction.layerInstructions = [trackInstruction]
        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        let video = CALayer()
        video.frame = root.bounds
        root.addSublayer(video)
        let artwork = CALayer()
        artwork.frame = root.bounds
        artwork.isGeometryFlipped = true
        for layer in layers { artwork.addSublayer(layer) }
        root.addSublayer(artwork)
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: root)
        return try await StoryExportVideoArtwork.export(asset: asset, composition: composition)
    }

    /// Shared Moment cards autoplay with sound in the viewer. Keep those tracks
    /// in the file as well, looping them for exactly the base story's duration.
    private static func assetByAddingSharedAudio(to base: AVAsset, sources: [(asset: AVAsset, loops: Bool)]) async throws -> AVAsset {
        guard !sources.isEmpty else { return base }
        let duration = try await base.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        let composition = AVMutableComposition()
        for type in [AVMediaType.video, .audio] {
            for track in try await base.loadTracks(withMediaType: type) {
                guard let destination = composition.addMutableTrack(
                    withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw StoryDownloadError.exportFailed }
                let intersection = CMTimeRangeGetIntersection(timeRange, otherRange: try await track.load(.timeRange))
                if intersection.duration > .zero {
                    try destination.insertTimeRange(intersection, of: track, at: intersection.start)
                }
                if type == .video { destination.preferredTransform = try await track.load(.preferredTransform) }
            }
        }
        for entry in sources {
            let source = entry.asset
            guard let track = try await source.loadTracks(withMediaType: .audio).first else { continue }
            let sourceDuration = try await source.load(.duration)
            guard sourceDuration > .zero else { continue }
            let audioRange = CMTimeRangeGetIntersection(
                CMTimeRange(start: .zero, duration: sourceDuration), otherRange: try await track.load(.timeRange)
            )
            guard audioRange.duration > .zero else { continue }
            guard let destination = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw StoryDownloadError.exportFailed }
            var loopStart = CMTime.zero
            while loopStart < duration {
                try Task.checkCancellation()
                let insertionTime = CMTimeAdd(loopStart, audioRange.start)
                if insertionTime >= duration { break }
                let length = CMTimeMinimum(audioRange.duration, CMTimeSubtract(duration, insertionTime))
                try destination.insertTimeRange(
                    CMTimeRange(start: audioRange.start, duration: length), of: track, at: insertionTime
                )
                if !entry.loops { break }
                loopStart = CMTimeAdd(loopStart, sourceDuration)
            }
        }
        return composition
    }

    static func normalizedEditorStickers(
        _ stickers: [StickerItem],
        canvasSize: CGSize
    ) -> [StickerItem] {
        let safeWidth = max(canvasSize.width, 1)
        let safeHeight = max(canvasSize.height, 1)
        let referenceContentWidth: CGFloat = 375
        return stickers.map { stickerItem in
            var normalizedItem = stickerItem
            let normalizedX = stickerItem.position.x / safeWidth
            let normalizedY = stickerItem.position.y / safeHeight
            let normalizedScale = stickerItem.scale * (referenceContentWidth / safeWidth)
            normalizedItem.position = CGPoint(
                x: normalizedX.isFinite ? normalizedX : 0.5,
                y: normalizedY.isFinite ? normalizedY : 0.5
            )
            normalizedItem.scale = normalizedScale.isFinite ? normalizedScale : stickerItem.scale
            normalizedItem.zIndex = stickerItem.zIndex
            return normalizedItem
        }
    }

    static func flattenOverlays(_ images: [UIImage?], size: CGSize) -> UIImage? {
        let layers = images.compactMap { $0 }
        guard !layers.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for layer in layers {
                layer.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    static func writeStillVideo(
        from image: UIImage,
        size: CGSize,
        duration: CMTime = stillDuration
    ) async throws -> URL {
        guard duration.seconds.isFinite, duration.seconds > 0 else { throw StoryDownloadError.exportFailed }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_download_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: outputURL) } }
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw StoryDownloadError.exportFailed
        }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else { throw StoryDownloadError.exportFailed }
        writer.add(input)
        guard let pixelBuffer = makePixelBuffer(from: image, size: size) else {
            throw StoryDownloadError.exportFailed
        }

        guard writer.startWriting() else { throw writer.error ?? StoryDownloadError.exportFailed }
        writer.startSession(atSourceTime: .zero)
        // A two-sample still clip can keep a filter composition frozen between
        // its first and last sample. Supply the complete output timeline.
        let frameCount = max(1, Int(ceil(duration.seconds * 30)))
        for frameIndex in 0..<frameCount {
            try Task.checkCancellation()
            let time = CMTime(value: Int64(frameIndex), timescale: 30)
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? StoryDownloadError.exportFailed }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw writer.error ?? StoryDownloadError.exportFailed
            }
        }
        writer.endSession(atSourceTime: duration)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? StoryDownloadError.exportFailed }
        completed = true
        return outputURL
    }

    static func exportVideo(
        sourceURL: URL,
        overlay: UIImage?,
        background: UIImage,
        targetSize: CGSize,
        editorCanvasSize: CGSize,
        imageScale: CGFloat,
        imageOffset: CGSize,
        imageRotation: Angle
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw StoryDownloadError.missingMedia
        }
        let duration = try await asset.load(.duration)
        let backgroundURL = try await writeStillVideo(
            from: background,
            size: targetSize,
            duration: duration
        )
        defer { try? FileManager.default.removeItem(at: backgroundURL) }

        let composition = AVMutableComposition()
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let timescale = Int32(max(30, min(60, Int(frameRate.rounded()))))
        let blurAsset = AVURLAsset(url: backgroundURL)
        guard let blurTrack = try await blurAsset.loadTracks(withMediaType: .video).first,
              let compositionBackgroundTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ),
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw StoryDownloadError.exportFailed
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionBackgroundTrack.insertTimeRange(timeRange, of: blurTrack, at: .zero)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let audioRange = CMTimeRangeGetIntersection(timeRange, otherRange: try await audioTrack.load(.timeRange))
            if audioRange.duration > .zero {
                try compositionAudioTrack.insertTimeRange(audioRange, of: audioTrack, at: audioRange.start)
            }
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let actualSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let baseRect = storyMediaBaseRect(mediaSize: actualSize, canvasSize: targetSize)
        let scale = baseRect.width / max(actualSize.width, 1)
        let scaledTransform = preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let scaledRect = CGRect(origin: .zero, size: naturalSize).applying(scaledTransform)
        let translation = CGAffineTransform(
            translationX: baseRect.midX - scaledRect.midX,
            y: baseRect.midY - scaledRect.midY
        )
        let scaleFactorX = targetSize.width / max(editorCanvasSize.width, 1)
        let scaleFactorY = targetSize.height / max(editorCanvasSize.height, 1)
        let userTransform = CGAffineTransform.identity
            .translatedBy(
                x: (targetSize.width / 2) + (imageOffset.width * scaleFactorX),
                y: (targetSize.height / 2) + (imageOffset.height * scaleFactorY)
            )
            .rotated(by: imageRotation.radians)
            .scaledBy(x: imageScale, y: imageScale)
            .translatedBy(x: -targetSize.width / 2, y: -targetSize.height / 2)
        let finalTransform = scaledTransform
            .concatenating(translation)
            .concatenating(userTransform)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        let backgroundInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionBackgroundTrack)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction, backgroundInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: timescale)
        videoComposition.instructions = [instruction]

        let renderFrame = CGRect(origin: .zero, size: targetSize)
        let parentLayer = CALayer()
        parentLayer.frame = renderFrame
        let videoLayer = CALayer()
        videoLayer.frame = renderFrame
        parentLayer.addSublayer(videoLayer)
        if let overlay, let cgImage = overlay.cgImage {
            let overlayLayer = CALayer()
            overlayLayer.frame = renderFrame
            overlayLayer.contents = cgImage
            overlayLayer.contentsGravity = .resize
            parentLayer.addSublayer(overlayLayer)
        }
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_download_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw StoryDownloadError.exportFailed
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    static func compositeStill(
        image: UIImage,
        overlay: UIImage?,
        targetSize: CGSize,
        layoutWidth: CGFloat = 375
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderBounds = CGRect(origin: .zero, size: targetSize)
        var background: UIImage?
        if let source = CIImage(image: image.creatorNormalizedUp()) {
            // Same aspect-fill + 20pt blur + 1.1 scale as the story viewer.
            let scale = max(targetSize.width / source.extent.width, targetSize.height / source.extent.height) * 1.1
            let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let centered = scaled.transformed(by: CGAffineTransform(
                translationX: renderBounds.midX - scaled.extent.midX,
                y: renderBounds.midY - scaled.extent.midY
            ))
            let blurred = centered.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 20 * targetSize.width / max(layoutWidth, 1)])
                .cropped(to: renderBounds)
            if let cgImage = CIContext().createCGImage(blurred, from: renderBounds) {
                background = UIImage(cgImage: cgImage)
            }
        }
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            background?.draw(in: renderBounds)
            let mediaRect = storyMediaBaseRect(mediaSize: image.size, canvasSize: targetSize)
            image.draw(in: mediaRect)
            overlay?.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func solidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func storyRenderCanvasSize() -> CGSize {
        let width: CGFloat = 1080
        var height = width / max(creatorMomentsCaptureAspectRatio, 0.0001)
        if height > 3000 { height = 3000 }
        if height < 1200 { height = 1200 }
        return CGSize(width: width, height: height)
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: floor(size.width / 2) * 2,
            height: floor(size.height / 2) * 2
        )
    }

    private static func makePixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        context.clear(CGRect(origin: .zero, size: size))
        // CVPixelBuffer rows start at the top; UIKit drawing needs a flipped CGContext.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        return pixelBuffer
    }
}

enum StoryDownloadError: LocalizedError {
    case missingMedia
    case exportFailed

    var errorDescription: String? {
        NSLocalizedString("stories.delivery.failed", comment: "Story media could not be saved")
    }
}

private struct StoryExportVideoFramesKey: EnvironmentKey {
    static let defaultValue: [URL: UIImage]? = nil
}

extension EnvironmentValues {
    /// Export preparation supplies solid artwork to locate a video's visible
    /// region without starting an AVPlayer or recording the screen.
    var storyExportVideoFrames: [URL: UIImage]? {
        get { self[StoryExportVideoFramesKey.self] }
        set { self[StoryExportVideoFramesKey.self] = newValue }
    }
}

private enum StoryExportElement {
    case layer(CALayer)
    case video(StoryExportVideoArtwork)
}

/// All returned layers are newly created and have no UIView delegates or live
/// presentation trees. Only these independent layers enter AVFoundation.
@MainActor
private enum StoryExportArtwork {
    struct VideoSlot {
        let size: CGSize
        let transform: CGAffineTransform
    }
    struct Snapshot {
        let image: CGImage
        let videoSlot: VideoSlot?
        let whiteImage: CGImage?
    }

    static func canvasLayer(_ canvas: CGSize, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: canvas)
        layer.position = CGPoint(x: canvas.width * scale / 2, y: canvas.height * scale / 2)
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        return layer
    }

    static func placement(_ sticker: StickerItem, size: CGSize, canvas: CGSize) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.position = CGPoint(x: sticker.position.x * canvas.width, y: sticker.position.y * canvas.height)
        layer.transform = CATransform3DMakeRotation(sticker.rotation.radians, 0, 0, 1)
        return layer
    }

    static func gifLayer(_ image: UIImage, sticker: StickerItem, canvas: CGSize, scale: CGFloat) -> CALayer {
        let root = canvasLayer(canvas, scale: scale)
        let displayScale = sticker.scale * canvas.width / 375
        let layer = placement(sticker, size: CGSize(width: sticker.image.size.width * displayScale,
            height: sticker.image.size.height * displayScale), canvas: canvas)
        layer.contentsGravity = .resizeAspect
        let sequence = (image.images ?? [image]).compactMap(\.cgImage)
        layer.contents = sequence.first
        if sequence.count > 1 {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = sequence + [sequence[0]]
            animation.keyTimes = (0...sequence.count).map { NSNumber(value: Double($0) / Double(sequence.count)) }
            animation.calculationMode = .discrete
            animation.duration = image.duration > 0 ? image.duration : Double(sequence.count) * 0.1
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.repeatCount = .greatestFiniteMagnitude
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "story.export.gif")
        }
        root.addSublayer(layer)
        return root
    }

    static func textLayer(_ metadata: StoryTextOverlayMetadata, canvas: CGSize, scale: CGFloat,
                          maxWidth: CGFloat?, colorScheme: ColorScheme) -> CALayer? {
        guard let configuration = metadata.scaledRenderConfiguration(containerWidth: canvas.width) else { return nil }
        let width = maxWidth ?? max(canvas.width - 48, 120)
        let view = StoryTextOverlayContainerView()
        let origin = CACurrentMediaTime()
        var independentLayer: CALayer?
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light).performAsCurrent {
            view.apply(configuration: configuration, maxWidth: width)
            StoryTextMotionEngine.apply(to: view, motion: metadata.motion, replayToken: 0)
            view.layoutIfNeeded()
            independentLayer = copyTextLayer(view.layer, views: view, scale: scale, animationOrigin: origin)
        }
        guard let copy = independentLayer else { return nil }
        copy.position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let position = CALayer()
        position.bounds = view.bounds
        position.position = metadata.displayPosition(in: canvas)
        position.transform = CATransform3DMakeRotation(metadata.rotationRadians, 0, 0, 1)
        position.addSublayer(copy)
        let root = canvasLayer(canvas, scale: scale)
        root.addSublayer(position)
        return root
    }

    private static func copyTextLayer(_ source: CALayer, views: UIView, scale: CGFloat,
                                      animationOrigin: CFTimeInterval) -> CALayer {
        let target: CALayer
        switch source {
        case let shape as CAShapeLayer:
            let copy = CAShapeLayer()
            copy.path = shape.path
            copy.fillColor = shape.fillColor
            copy.fillRule = shape.fillRule
            copy.strokeColor = shape.strokeColor
            copy.lineWidth = shape.lineWidth
            copy.lineCap = shape.lineCap
            copy.lineJoin = shape.lineJoin
            copy.strokeStart = shape.strokeStart
            copy.strokeEnd = shape.strokeEnd
            copy.lineDashPattern = shape.lineDashPattern
            target = copy
        case let gradient as CAGradientLayer:
            let copy = CAGradientLayer()
            copy.colors = gradient.colors
            copy.locations = gradient.locations
            copy.startPoint = gradient.startPoint
            copy.endPoint = gradient.endPoint
            copy.type = gradient.type
            target = copy
        case let text as CATextLayer:
            let copy = CATextLayer()
            copy.string = text.string
            copy.font = text.font
            copy.fontSize = text.fontSize
            copy.foregroundColor = text.foregroundColor
            copy.isWrapped = text.isWrapped
            copy.alignmentMode = text.alignmentMode
            copy.truncationMode = text.truncationMode
            target = copy
        case let replicator as CAReplicatorLayer:
            let copy = CAReplicatorLayer()
            copy.instanceCount = replicator.instanceCount
            copy.instanceDelay = replicator.instanceDelay
            copy.instanceTransform = replicator.instanceTransform
            copy.instanceColor = replicator.instanceColor
            copy.instanceRedOffset = replicator.instanceRedOffset
            copy.instanceGreenOffset = replicator.instanceGreenOffset
            copy.instanceBlueOffset = replicator.instanceBlueOffset
            copy.instanceAlphaOffset = replicator.instanceAlphaOffset
            target = copy
        default: target = CALayer()
        }
        target.bounds = source.bounds
        target.position = source.position
        target.anchorPoint = source.anchorPoint
        target.transform = source.transform
        target.sublayerTransform = source.sublayerTransform
        target.zPosition = source.zPosition
        target.opacity = source.opacity
        target.isHidden = source.isHidden
        target.backgroundColor = source.backgroundColor
        target.cornerRadius = source.cornerRadius
        target.cornerCurve = source.cornerCurve
        target.maskedCorners = source.maskedCorners
        target.masksToBounds = source.masksToBounds
        target.borderColor = source.borderColor
        target.borderWidth = source.borderWidth
        target.shadowColor = source.shadowColor
        target.shadowOpacity = source.shadowOpacity
        target.shadowOffset = source.shadowOffset
        target.shadowRadius = source.shadowRadius
        target.shadowPath = source.shadowPath
        target.contents = source.contents
        target.contentsGravity = source.contentsGravity
        target.contentsRect = source.contentsRect
        target.contentsCenter = source.contentsCenter
        target.contentsScale = scale
        target.shouldRasterize = source.shouldRasterize
        target.rasterizationScale = source.rasterizationScale
        if let label = findView(for: source, in: views) as? UILabel, !label.bounds.isEmpty {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            target.contents = UIGraphicsImageRenderer(size: label.bounds.size, format: format).image { _ in
                label.drawText(in: CGRect(origin: .zero, size: label.bounds.size))
            }.cgImage
        } else {
            for child in source.sublayers ?? [] {
                target.addSublayer(copyTextLayer(child, views: views, scale: scale, animationOrigin: animationOrigin))
            }
        }
        if let mask = source.mask {
            target.mask = copyTextLayer(mask, views: views, scale: scale, animationOrigin: animationOrigin)
        }
        for key in source.animationKeys() ?? [] {
            // Animations retrieved from a layer are read-only. Copy before retiming.
            guard let animation = source.animation(forKey: key)?.copy() as? CAAnimation else { continue }
            // Explicit delayed sparkles use the wall clock; all other animations
            // start at zero. Children of animation groups retain relative timing.
            let delay = animation.beginTime > 0 ? max(0, animation.beginTime - animationOrigin) : 0
            animation.beginTime = delay > 0 ? delay : AVCoreAnimationBeginTimeAtZero
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            if animation.repeatCount.isInfinite { animation.repeatCount = .greatestFiniteMagnitude }
            target.add(animation, forKey: key)
        }
        return target
    }

    private static func findView(for layer: CALayer, in view: UIView) -> UIView? {
        if view.layer === layer { return view }
        for child in view.subviews {
            if let found = findView(for: layer, in: child) { return found }
        }
        return nil
    }

    static func countdownLayer(_ sticker: StickerItem, canvas: CGSize, scale: CGFloat,
                               startDate: Date, duration: Double, colorScheme: ColorScheme) async throws -> CALayer {
        let displayScale = sticker.scale * canvas.width / 375
        var images: [CGImage] = []
        var times: [NSNumber] = []
        var pointSize = CGSize.zero
        for second in 0..<max(1, Int(ceil(duration))) {
            try Task.checkCancellation()
            await Task.yield()
            let content = StickerCountdownCardView(title: sticker.interactionData?.countdownTitle ?? "",
                targetAtMs: sticker.interactionData?.countdownTargetAtMs ?? 0,
                styleVariant: sticker.interactionData?.styleVariant ?? 0)
                .environment(\.colorScheme, colorScheme)
                .environment(\.storyExportDate, startDate.addingTimeInterval(Double(second)))
                .fixedSize()
            let renderer = ImageRenderer(content: content)
            renderer.scale = max(0.1, scale * displayScale)
            guard let image = renderer.uiImage, let cgImage = image.cgImage else { throw StoryDownloadError.exportFailed }
            pointSize = image.size
            images.append(cgImage)
            times.append(NSNumber(value: Double(second) / duration))
        }
        guard let last = images.last else { throw StoryDownloadError.exportFailed }
        images.append(last)
        times.append(1)
        let layer = placement(sticker, size: CGSize(width: pointSize.width * displayScale,
            height: pointSize.height * displayScale), canvas: canvas)
        layer.contents = images[0]
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images
        animation.keyTimes = times
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        layer.add(animation, forKey: "story.export.countdown")
        let root = canvasLayer(canvas, scale: scale)
        root.addSublayer(layer)
        return root
    }

    static func audioLayer(_ sticker: StickerItem, background: CGImage, canvas: CGSize,
                           scale: CGFloat, duration: Double) -> CALayer {
        let displayScale = sticker.scale * canvas.width / 375
        let root = canvasLayer(canvas, scale: scale)
        let card = placement(sticker, size: CGSize(width: 72, height: 72), canvas: canvas)
        card.transform = CATransform3DScale(card.transform, displayScale, displayScale, 1)
        let backdrop = CALayer()
        backdrop.frame = CGRect(origin: .zero, size: canvas)
        backdrop.contents = background
        root.addSublayer(backdrop)
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        func symbol(_ name: String) -> CGImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = max(1, scale * displayScale)
            format.opaque = false
            return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 24), format: format).image { _ in
                if let image = UIImage(systemName: name, withConfiguration: configuration)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let fit = min(20 / image.size.width, 24 / image.size.height)
                    let width = image.size.width * fit, height = image.size.height * fit
                    image.draw(in: CGRect(x: (20 - width) / 2, y: (24 - height) / 2, width: width, height: height))
                }
            }.cgImage
        }
        let icon = CALayer()
        icon.frame = CGRect(x: 26, y: 16, width: 20, height: 24)
        icon.contentsGravity = .resizeAspect
        icon.contents = symbol("pause.fill")
        let state = CAKeyframeAnimation(keyPath: "contents")
        let pause = icon.contents
        let mic = symbol("mic.fill")
        if let pause, let mic {
            state.values = [pause, mic]
            state.keyTimes = [0, 1]
            state.calculationMode = .discrete
            state.duration = duration
            state.beginTime = AVCoreAnimationBeginTimeAtZero
            state.isRemovedOnCompletion = false
            state.fillMode = .forwards
            icon.add(state, forKey: "story.export.audio.state")
        }
        card.addSublayer(icon)
        for index in 0..<3 {
            let bar = CALayer()
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: 10)
            bar.position = CGPoint(x: 30 + CGFloat(index) * 6, y: 51)
            bar.cornerRadius = 1.5
            bar.backgroundColor = UIColor.white.cgColor
            let wave = CAKeyframeAnimation(keyPath: "transform.scale.y")
            wave.values = index == 1 ? [1.4, 2.0, 1.0, 1.7, 1.4] : [1.0, 0.6, 1.6, 0.9, 1.0]
            wave.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            wave.calculationMode = .discrete
            wave.duration = 0.8
            wave.repeatDuration = duration
            wave.beginTime = AVCoreAnimationBeginTimeAtZero
            wave.isRemovedOnCompletion = false
            bar.add(wave, forKey: "story.export.audio.wave")
            card.addSublayer(bar)
        }
        let ring = CAShapeLayer()
        ring.frame = card.bounds
        ring.path = UIBezierPath(ovalIn: card.bounds).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.strokeEnd = 0
        ring.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        let progress = CABasicAnimation(keyPath: "strokeEnd")
        progress.fromValue = 0
        progress.toValue = 1
        progress.duration = duration
        progress.beginTime = AVCoreAnimationBeginTimeAtZero
        progress.isRemovedOnCompletion = false
        ring.add(progress, forKey: "story.export.audio.progress")
        let ringGradient = CAGradientLayer()
        ringGradient.frame = card.bounds
        ringGradient.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.8).cgColor]
        ringGradient.startPoint = CGPoint(x: 0.5, y: 0)
        ringGradient.endPoint = CGPoint(x: 0.5, y: 1)
        ringGradient.mask = ring
        card.addSublayer(ringGradient)
        root.addSublayer(card)
        return root
    }

    /// Prepare each static card once (twice for a video matte), never per frame.
    static func snapshotSticker(_ sticker: StickerItem, canvas: CGSize, scale: CGFloat,
                                storyId: String, userId: String, colorScheme: ColorScheme,
                                videoColor: UIColor? = nil) async throws -> Snapshot {
        var frames: [URL: UIImage] = [:]
        if let url = sticker.videoURL, let videoColor {
            frames[url] = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                videoColor.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
        }
        let content = StoryMediaOverlayRendererView(containerSize: canvas, textOverlays: [],
            stickerItems: [sticker], drawingData: nil, storyId: storyId, userId: userId,
            reportsDeckInteractionExclusion: false, allowsStickerHitTesting: false,
            renderingMode: .live, clipCornerRadius: 0)
            .frame(width: canvas.width, height: canvas.height).ignoresSafeArea()
            .environment(\.colorScheme, colorScheme)
            .environment(\.storyExportVideoFrames, frames)
            .environment(\.storyExportAudioBackgroundOnly, sticker.type == .audio)
            .environment(\.storyExportFrameIsExposed,
                storyId == "editor-download" || UserDefaults.standard.bool(forKey: "frame_revealed_\(storyId)"))
        let host = UIHostingController(rootView: content)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { throw StoryDownloadError.exportFailed }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: canvas)
        window.windowLevel = .normal - 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.rootViewController = host
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = CGRect(origin: .zero, size: canvas)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let slot = findVideoSlot(in: host.view, root: host.view, canvas: canvas, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        var complete = false
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            complete = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard complete, let cgImage = image.cgImage else { throw StoryDownloadError.exportFailed }
        var whiteImage: CGImage?
        if videoColor != nil, let videoView = findVideoView(in: host.view) {
            let white = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            // Keep the same card tree and loaded avatar/chrome in both mattes.
            videoView.showExportFrame(white)
            let second = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                complete = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            guard complete, let cgImage = second.cgImage else { throw StoryDownloadError.exportFailed }
            whiteImage = cgImage
        }
        return Snapshot(image: cgImage, videoSlot: slot, whiteImage: whiteImage)
    }

    private static func findVideoView(in view: UIView) -> StickerVideoPlayer.StickerPlayerUIView? {
        if let video = view as? StickerVideoPlayer.StickerPlayerUIView { return video }
        for child in view.subviews {
            if let video = findVideoView(in: child) { return video }
        }
        return nil
    }

    private static func findVideoSlot(in view: UIView, root: UIView, canvas: CGSize, scale: CGFloat) -> VideoSlot? {
        if view is StickerVideoPlayer.StickerPlayerUIView, !view.bounds.isEmpty {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let p = view.convert(CGPoint(x: x, y: y), to: root)
                return CGPoint(x: p.x * scale, y: (canvas.height - p.y) * scale)
            }
            let width = view.bounds.width, height = view.bounds.height
            let origin = point(0, height), x = point(width, height), y = point(0, 0)
            return VideoSlot(size: view.bounds.size, transform: CGAffineTransform(
                a: (x.x - origin.x) / width, b: (x.y - origin.y) / width,
                c: (y.x - origin.x) / height, d: (y.y - origin.y) / height,
                tx: origin.x, ty: origin.y))
        }
        for child in view.subviews {
            if let slot = findVideoSlot(in: child, root: root, canvas: canvas, scale: scale) { return slot }
        }
        return nil
    }
}

private struct StoryExportDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}
extension EnvironmentValues {
    var storyExportDate: Date? {
        get { self[StoryExportDateKey.self] }
        set { self[StoryExportDateKey.self] = newValue }
    }
}

/// Decode only the requested sticker frame, on AVFoundation's rendering queue.
/// The two prepared mattes retain card chrome, rounded clipping and rotation.
private final class StoryExportVideoArtwork {
    private let generator: AVAssetImageGenerator
    private let duration: Double
    private let black: CIImage
    private let white: CIImage
    private let slot: StoryExportArtwork.VideoSlot
    private let canvas: CGRect
    private let kernel: CIColorKernel
    private let lock = NSLock()

    init(asset: AVAsset, duration: Double, black: CGImage, white: CGImage,
         slot: StoryExportArtwork.VideoSlot, canvasSize: CGSize) throws {
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = canvasSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.duration = duration
        self.black = CIImage(cgImage: black)
        self.white = CIImage(cgImage: white)
        self.slot = slot
        canvas = CGRect(origin: .zero, size: canvasSize)
        guard let kernel = CIColorKernel(source: """
            kernel vec4 storyCard(__sample blackCard, __sample whiteCard, __sample video) {
                return vec4(blackCard.rgb + video.rgb * (whiteCard.rgb - blackCard.rgb), blackCard.a);
            }
            """) else { throw StoryDownloadError.exportFailed }
        self.kernel = kernel
    }

    private func frame(at time: Double) throws -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        let mediaTime = CMTime(seconds: time.truncatingRemainder(dividingBy: duration), preferredTimescale: 600)
        let image = CIImage(cgImage: try generator.copyCGImage(at: mediaTime, actualTime: nil))
        let rect = CGRect(origin: .zero, size: slot.size)
        let scale = max(rect.width / image.extent.width, rect.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let fitted = scaled.transformed(by: CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX, y: rect.midY - scaled.extent.midY))
            .cropped(to: rect).transformed(by: slot.transform)
        guard let result = kernel.apply(extent: canvas, arguments: [black, white, fitted]) else {
            throw StoryDownloadError.exportFailed
        }
        return result
    }

    func export(over asset: AVAsset) async throws -> URL {
        let composition = AVMutableVideoComposition(asset: asset) { [self] request in
            autoreleasepool {
                do {
                    let overlay = try frame(at: request.compositionTime.seconds)
                    request.finish(with: overlay.composited(over: request.sourceImage), context: nil)
                } catch { request.finish(with: error) }
            }
        }
        composition.renderSize = canvas.size
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        return try await Self.export(asset: asset, composition: composition)
    }

    static func export(asset: AVAsset, composition: AVVideoComposition) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_download_\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw StoryDownloadError.exportFailed
        }
        session.videoComposition = composition
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if audioTracks.count > 1 {
                let mix = AVMutableAudioMix()
                mix.inputParameters = audioTracks.map { track in
                    let parameters = AVMutableAudioMixInputParameters(track: track)
                    parameters.setVolume(1, at: .zero)
                    return parameters
                }
                session.audioMix = mix
            }
            try await session.export(to: output, as: .mp4)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}

private struct StoryExportAudioBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var storyExportAudioBackgroundOnly: Bool {
        get { self[StoryExportAudioBackgroundKey.self] }
        set { self[StoryExportAudioBackgroundKey.self] = newValue }
    }
}

private struct StoryExportFrameExposedKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}
extension EnvironmentValues {
    var storyExportFrameIsExposed: Bool? {
        get { self[StoryExportFrameExposedKey.self] }
        set { self[StoryExportFrameExposedKey.self] = newValue }
    }
}
