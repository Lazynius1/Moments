import SwiftUI
import TOCropViewController

struct CropViewWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let aspectRatio: CreatorMedia.AspectRatio
    let allowFreeCrop: Bool
    let onComplete: (UIImage, CreatorMedia.AspectRatio) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(image: UIImage, aspectRatio: CreatorMedia.AspectRatio, allowFreeCrop: Bool = false, onComplete: @escaping (UIImage, CreatorMedia.AspectRatio) -> Void) {
        self.image = image
        self.aspectRatio = aspectRatio
        self.allowFreeCrop = allowFreeCrop
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let cropViewController = TOCropViewController(croppingStyle: .default, image: image)
        cropViewController.delegate = context.coordinator

        if allowFreeCrop {
            switch aspectRatio {
            case .square:
                cropViewController.aspectRatioPreset = .presetSquare
            case .portrait:
                cropViewController.customAspectRatio = CGSize(width: 4, height: 5)
            case .landscape:
                cropViewController.customAspectRatio = CGSize(width: 16, height: 9)
            case .nineBySixteen:
                cropViewController.customAspectRatio = CGSize(width: 9, height: 16)
            case .custom(let ratio):
                cropViewController.customAspectRatio = CGSize(width: ratio, height: 1)
            }
            cropViewController.aspectRatioLockEnabled = false
        } else {
            switch aspectRatio {
            case .square:
                cropViewController.aspectRatioPreset = .presetSquare
                cropViewController.aspectRatioLockEnabled = true
            case .portrait:
                cropViewController.customAspectRatio = CGSize(width: 4, height: 5)
                cropViewController.aspectRatioLockEnabled = true
            case .landscape:
                cropViewController.customAspectRatio = CGSize(width: 16, height: 9)
                cropViewController.aspectRatioLockEnabled = true
            case .nineBySixteen:
                cropViewController.customAspectRatio = CGSize(width: 9, height: 16)
                cropViewController.aspectRatioLockEnabled = true
            case .custom(let ratio):
                cropViewController.customAspectRatio = CGSize(width: ratio, height: 1)
                cropViewController.aspectRatioLockEnabled = true
            }
        }

        cropViewController.rotateButtonsHidden = false
        cropViewController.resetButtonHidden = false

        let canvas = ProfileMomentZoomNavigation.canvasUIColor(for: colorScheme)
        cropViewController.toolbar.tintColor = UIColor.label
        cropViewController.toolbar.backgroundColor = canvas
        if let titleLabel = cropViewController.titleLabel {
            titleLabel.textColor = UIColor.label
        }
        cropViewController.view.backgroundColor = canvas

        let navController = UINavigationController(rootViewController: cropViewController)
        navController.navigationBar.isHidden = true
        navController.modalPresentationStyle = .fullScreen

        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, TOCropViewControllerDelegate {
        let parent: CropViewWrapper

        init(_ parent: CropViewWrapper) {
            self.parent = parent
        }

        func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
            let finalAspectRatio: CreatorMedia.AspectRatio
            if parent.allowFreeCrop {
                let imageRatio = image.size.width / image.size.height
                finalAspectRatio = CreatorMedia.AspectRatio.fromFeedPostRatio(imageRatio)
            } else {
                finalAspectRatio = parent.aspectRatio
            }

            parent.onComplete(image, finalAspectRatio)
            parent.dismiss()
        }

        func cropViewControllerDidCancel(_ cropViewController: TOCropViewController) {
            parent.dismiss()
        }
    }
}
