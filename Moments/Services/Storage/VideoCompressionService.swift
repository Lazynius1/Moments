import AVFoundation
import Foundation

enum VideoCompressionPreset {
    case moment
    case story
    case chat
}

enum VideoCompressionError: LocalizedError {
    case invalidSource
    case exportFailed
    case outputTooLarge(size: Int64, limit: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "No se pudo leer el vídeo."
        case .exportFailed:
            return "No se pudo comprimir el vídeo."
        case .outputTooLarge(let size, let limit):
            return "El vídeo sigue siendo demasiado grande (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) tras comprimir. Máximo: \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))."
        }
    }
}

struct VideoCompressionLimits {
    let compressIfLargerThan: Int64
    let maxOutputBytes: Int64
}

struct VideoCompressionService {
    static let shared = VideoCompressionService()

    func limits(for preset: VideoCompressionPreset) -> VideoCompressionLimits {
        switch preset {
        case .moment:
            return VideoCompressionLimits(
                compressIfLargerThan: CreatorMedia.maxMomentVideoUploadSizeBytes,
                maxOutputBytes: CreatorMedia.maxMomentVideoUploadSizeBytes
            )
        case .story:
            return VideoCompressionLimits(
                compressIfLargerThan: CreatorMedia.maxStoryVideoReadySizeBytes,
                maxOutputBytes: CreatorMedia.maxStoryVideoReadySizeBytes * 5
            )
        case .chat:
            return VideoCompressionLimits(
                compressIfLargerThan: 12 * 1024 * 1024,
                maxOutputBytes: 80 * 1024 * 1024
            )
        }
    }

    func prepareVideoForUpload(
        inputURL: URL,
        preset: VideoCompressionPreset
    ) async throws -> URL {
        let limits = limits(for: preset)
        let inputSize = try fileSize(at: inputURL)

        guard inputSize > limits.compressIfLargerThan else {
            return inputURL
        }

        let compressedURL = try await compressVideo(inputURL: inputURL)
        let compressedSize = try fileSize(at: compressedURL)

        guard compressedSize <= limits.maxOutputBytes else {
            try? FileManager.default.removeItem(at: compressedURL)
            throw VideoCompressionError.outputTooLarge(size: compressedSize, limit: limits.maxOutputBytes)
        }

        if compressedURL != inputURL {
            // Caller uploads compressed file; original can remain for local preview until upload completes.
        }

        return compressedURL
    }

    func prepareVideoDataForUpload(
        data: Data,
        preset: VideoCompressionPreset,
        preferredExtension: String = "mp4"
    ) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video_upload_\(UUID().uuidString).\(preferredExtension)")
        try data.write(to: tempURL, options: .atomic)
        return try await prepareVideoForUpload(inputURL: tempURL, preset: preset)
    }

    private func compressVideo(inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(UUID().uuidString).mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw VideoCompressionError.exportFailed
        }

        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.export(to: outputURL, as: .mp4)
        return outputURL
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}
