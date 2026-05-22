import AVFoundation
import CoreMedia

extension AVAssetImageGenerator {
    /// Generates a thumbnail CGImage at the given time using the iOS 18+ async API.
    func thumbnailCGImage(at time: CMTime) throws -> CGImage {
        var output: Swift.Result<CGImage, Error>?
        let semaphore = DispatchSemaphore(value: 0)

        generateCGImageAsynchronously(for: time) { image, _, error in
            if let error {
                output = .failure(error)
            } else if let image {
                output = .success(image)
            } else {
                output = .failure(
                    NSError(
                        domain: "AVAssetImageGenerator",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No image returned"]
                    )
                )
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try output!.get()
    }
}
