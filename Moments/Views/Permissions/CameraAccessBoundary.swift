import AVFoundation
import SwiftUI
import UIKit

struct CameraAccessBoundary<Content: View>: View {
    var requiresMicrophone: Bool = false
    var onCancel: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var micStatus = AVAudioApplication.shared.recordPermission

    private enum Phase { case camera, microphone, ready }

    private var phase: Phase {
        if cameraStatus != .authorized { return .camera }
        if requiresMicrophone && micStatus != .granted { return .microphone }
        return .ready
    }

    var body: some View {
        Group {
            switch phase {
            case .ready:
                content()
            case .camera:
                cameraScreen
            case .microphone:
                microphoneScreen
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            micStatus = AVAudioApplication.shared.recordPermission
        }
    }

    @ViewBuilder
    private var cameraScreen: some View {
        if cameraStatus == .notDetermined {
            CameraPermissionsview(
                title: NSLocalizedString("permission.camera.primer.title", comment: "Camera primer title"),
                description: NSLocalizedString("permission.camera.primer.subtitle", comment: "Camera primer subtitle"),
                primaryActionTitle: NSLocalizedString("permission.camera.primer.allow", comment: "Allow camera"),
                secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
                showsShutterUI: true
            ) {
                requestCamera()
            } secondaryAction: {
                onCancel()
            } panorama: {
                Image(.pic1).resizable()
            }
        } else {
            CameraPermissionsview(
                title: NSLocalizedString("permission.camera.denied.title", comment: "Camera denied title"),
                description: NSLocalizedString("permission.camera.denied.subtitle", comment: "Camera denied subtitle"),
                primaryActionTitle: NSLocalizedString("permission.camera.denied.openSettings", comment: "Open Settings"),
                secondaryActionTitle: NSLocalizedString("permission.camera.primer.notNow", comment: "Not now"),
                showsShutterUI: false,
                isDenied: true
            ) {
                openSettings()
            } secondaryAction: {
                onCancel()
            } panorama: {
                Image(.pic1).resizable()
            }
        }
    }

    private var microphoneScreen: some View {
        MicrophonePermissionView(
            stage: micStatus == .undetermined ? .primer : .denied,
            primaryAction: {
                if micStatus == .undetermined {
                    requestMicrophone()
                } else {
                    openSettings()
                }
            },
            secondaryAction: onCancel
        )
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraStatus = granted ? .authorized : .denied
            }
        }
    }

    private func requestMicrophone() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                micStatus = granted ? .granted : .denied
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
