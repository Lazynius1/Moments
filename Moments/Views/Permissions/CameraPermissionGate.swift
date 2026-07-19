import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class CameraPermissionGate: ObservableObject {
    enum Stage {
        case primer
        case denied
    }

    @Published var isPresenting = false
    @Published var stage: Stage = .primer

    private var onAuthorized: (() -> Void)?

    func requestCameraAccess(onAuthorized: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            onAuthorized()
        case .notDetermined:
            self.onAuthorized = onAuthorized
            stage = .primer
            isPresenting = true
        default:
            self.onAuthorized = onAuthorized
            stage = .denied
            isPresenting = true
        }
    }

    func confirmFromPrimer() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.stage = .denied
                    return
                }
                self.isPresenting = false
                let continuation = self.onAuthorized
                self.onAuthorized = nil
                continuation?()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        isPresenting = false
    }

    func dismiss() {
        isPresenting = false
    }
}

private struct CameraPermissionGateModifier: ViewModifier {
    @ObservedObject var gate: CameraPermissionGate

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $gate.isPresenting) {
            CameraPermissionPromptView(gate: gate)
        }
    }
}

extension View {
    func cameraPermissionGate(_ gate: CameraPermissionGate) -> some View {
        modifier(CameraPermissionGateModifier(gate: gate))
    }
}

private struct CameraPermissionPromptView: View {
    @ObservedObject var gate: CameraPermissionGate

    var body: some View {
        switch gate.stage {
        case .primer:
            CameraPermissionsview(
                title: NSLocalizedString("permission.camera.primer.title", comment: "Camera primer title"),
                description: NSLocalizedString("permission.camera.primer.subtitle", comment: "Camera primer subtitle"),
                primaryActionTitle: NSLocalizedString("permission.camera.primer.allow", comment: "Allow camera"),
                secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
                showsShutterUI: true
            ) {
                gate.confirmFromPrimer()
            } secondaryAction: {
                gate.dismiss()
            } panorama: {
                Image(.pic1).resizable()
            }
        case .denied:
            CameraPermissionsview(
                title: NSLocalizedString("permission.camera.denied.title", comment: "Camera denied title"),
                description: NSLocalizedString("permission.camera.denied.subtitle", comment: "Camera denied subtitle"),
                primaryActionTitle: NSLocalizedString("permission.camera.denied.openSettings", comment: "Open Settings"),
                secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
                showsShutterUI: false,
                isDenied: true
            ) {
                gate.openSettings()
            } secondaryAction: {
                gate.dismiss()
            } panorama: {
                Image(.pic1).resizable()
            }
        }
    }
}
