import SwiftUI
import TOCropViewController

struct CropViewWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let aspectRatio: CreatorMedia.AspectRatio
    let allowFreeCrop: Bool
    let onComplete: (UIImage, CreatorMedia.AspectRatio) -> Void
    @Environment(\.dismiss) private var dismiss

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
            }
        }

        cropViewController.rotateButtonsHidden = false
        cropViewController.resetButtonHidden = false

        cropViewController.toolbar.tintColor = UIColor.white
        cropViewController.toolbar.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        if let titleLabel = cropViewController.titleLabel {
            titleLabel.textColor = UIColor.white
        }
        cropViewController.view.backgroundColor = UIColor.black

        let navController = UINavigationController(rootViewController: cropViewController)
        navController.navigationBar.barStyle = UIBarStyle.black
        navController.navigationBar.tintColor = UIColor.white
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
                finalAspectRatio = CreatorMedia.AspectRatio.fromRatio(imageRatio)
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
