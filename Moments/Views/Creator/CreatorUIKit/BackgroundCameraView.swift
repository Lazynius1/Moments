import SwiftUI
import AVFoundation

// MARK: - Background Camera View Helper

struct BackgroundCameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .black

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return controller
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = controller.view.bounds
        controller.view.layer.addSublayer(previewLayer)

        context.coordinator.session = session
        context.coordinator.previewLayer = previewLayer

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StopBackgroundCameraSession"),
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.stopSession()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let layer = context.coordinator.previewLayer {
            layer.frame = uiViewController.view.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?

        func stopSession() {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session?.stopRunning()
                self?.session = nil
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            stopSession()
        }
    }
}
