import AVFoundation
import SwiftUI

struct CameraCapture: UIViewControllerRepresentable {
    var mediaTypes: [String] = ["public.image", "public.movie"]
    let onCapture: (CreatorMedia) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = mediaTypes
        picker.delegate = context.coordinator
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 60
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture

        init(_ parent: CameraCapture) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                let detectedRatio = CreatorMedia.AspectRatio.fromRatio(image.size.width / image.size.height)
                let media = CreatorMedia(
                    id: UUID().uuidString,
                    image: image,
                    videoURL: nil,
                    type: .image,
                    aspectRatio: detectedRatio,
                    recommendedAspectRatio: detectedRatio
                )
                parent.onCapture(media)
            } else if let videoURL = info[.mediaURL] as? URL {
                let asset = AVURLAsset(url: videoURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true

                Task {
                    do {
                        let (cgImage, _) = try await generator.image(at: .zero)
                        let thumbnail = UIImage(cgImage: cgImage)
                        let detectedRatio = CreatorMedia.AspectRatio.fromRatio(thumbnail.size.width / thumbnail.size.height)
                        let media = CreatorMedia(
                            id: UUID().uuidString,
                            image: thumbnail,
                            videoURL: videoURL,
                            type: .video,
                            aspectRatio: detectedRatio,
                            recommendedAspectRatio: detectedRatio
                        )
                        await MainActor.run {
                            parent.onCapture(media)
                        }
                    } catch {
                    }
                }
            }

            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
