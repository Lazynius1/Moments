import UIKit

extension UIImage {
    /// Re-dibuja a bitmap RGB opaco (scale 1) para subidas a Storage/GCS.
    /// Evita `verify_image_parameters: invalid image bits/pixel or bytes/row` con frames de vídeo o HDR.
    func storageUploadNormalized(maxPixelDimension: CGFloat = 1280) -> UIImage? {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        guard pixelWidth >= 2,
              pixelHeight >= 2,
              pixelWidth.isFinite,
              pixelHeight.isFinite,
              !pixelWidth.isNaN,
              !pixelHeight.isNaN else {
            return nil
        }

        let longSide = max(pixelWidth, pixelHeight)
        let downscale = longSide > maxPixelDimension ? (maxPixelDimension / longSide) : 1
        let drawSize = CGSize(
            width: max(2, floor(pixelWidth * downscale)),
            height: max(2, floor(pixelHeight * downscale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: drawSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: drawSize))
        }

        guard let cgImage = rendered.cgImage,
              cgImage.width >= 2,
              cgImage.height >= 2,
              cgImage.bitsPerPixel > 0,
              cgImage.bytesPerRow > 0 else {
            return nil
        }

        return rendered
    }

    func storageUploadJPEGData(
        compressionQuality: CGFloat = 0.8,
        maxPixelDimension: CGFloat = 1280
    ) -> Data? {
        storageUploadNormalized(maxPixelDimension: maxPixelDimension)?
            .jpegData(compressionQuality: compressionQuality)
    }
}
