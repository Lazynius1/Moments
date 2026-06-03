import UIKit
import SwiftUI

enum StoryDominantColorsExtractor {
    static func extract(from image: UIImage?, maxColors: Int = 6) -> [Color] {
        guard let image, let cgImage = image.cgImage else { return [] }

        let sampleSize = 48
        let width = sampleSize
        let height = sampleSize
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return [] }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return [] }

        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        var buckets: [Int: (r: Int, g: Int, b: Int, count: Int)] = [:]

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = (y * width + x) * bytesPerPixel
                let r = Int(buffer[offset])
                let g = Int(buffer[offset + 1])
                let b = Int(buffer[offset + 2])
                let a = Int(buffer[offset + 3])
                guard a > 40 else { continue }

                let qr = (r / 32) * 32
                let qg = (g / 32) * 32
                let qb = (b / 32) * 32
                let key = (qr << 16) | (qg << 8) | qb

                if var existing = buckets[key] {
                    existing.r += r
                    existing.g += g
                    existing.b += b
                    existing.count += 1
                    buckets[key] = existing
                } else {
                    buckets[key] = (r, g, b, 1)
                }
            }
        }

        let sorted = buckets.values
            .sorted { $0.count > $1.count }
            .prefix(maxColors)
            .map { bucket -> Color in
                let count = max(bucket.count, 1)
                return Color(
                    red: Double(bucket.r / count) / 255.0,
                    green: Double(bucket.g / count) / 255.0,
                    blue: Double(bucket.b / count) / 255.0
                )
            }

        return Array(sorted)
    }

    static func sampleColor(at location: CGPoint, in image: UIImage, viewSize: CGSize) -> Color {
        guard let cgImage = image.cgImage, viewSize.width > 0, viewSize.height > 0 else { return .white }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayed = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (viewSize.width - displayed.width) / 2,
            y: (viewSize.height - displayed.height) / 2
        )

        let localX = (location.x - origin.x) / displayed.width
        let localY = (location.y - origin.y) / displayed.height
        guard (0...1).contains(localX), (0...1).contains(localY) else { return .white }

        let pixelX = Int(localX * imageSize.width)
        let pixelY = Int(localY * imageSize.height)
        guard let cropped = cgImage.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)),
              let data = cropped.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return .white }

        return Color(
            red: Double(ptr[0]) / 255.0,
            green: Double(ptr[1]) / 255.0,
            blue: Double(ptr[2]) / 255.0
        )
    }
}
