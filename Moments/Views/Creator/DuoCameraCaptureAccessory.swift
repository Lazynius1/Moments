import SwiftUI
import AVFoundation

/// Puente entre las cámaras existentes y la escena accesoria exterior de Duo.
/// La sesión de captura sigue perteneciendo a la pantalla principal; la
/// accesoria añade únicamente otra capa de preview y estado no interactivo.
@MainActor
final class DuoCameraAccessoryCoordinator: ObservableObject {
    static let shared = DuoCameraAccessoryCoordinator()

    @Published fileprivate(set) var session: AVCaptureSession?
    @Published var isEnabled = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private init() {}

    func activate(session: AVCaptureSession) {
        self.session = session
        isEnabled = true
    }

    func updateRecording(_ recording: Bool, duration: TimeInterval = 0) {
        isRecording = recording
        recordingDuration = duration
    }

    func deactivate(session: AVCaptureSession) {
        guard self.session === session else { return }
        isEnabled = false
        isRecording = false
        recordingDuration = 0
        self.session = nil
    }
}

private struct DuoCameraSessionPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        PreviewView()
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}

private struct DuoCameraAccessoryView: View {
    @ObservedObject var coordinator: DuoCameraAccessoryCoordinator

    var body: some View {
        ZStack {
            Color.black
            DuoCameraSessionPreview(session: coordinator.session)

            VStack(spacing: 12) {
                HStack {
                    Text("Moments")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    if coordinator.isRecording {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(formattedDuration)
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.black.opacity(0.28))

                Spacer()

                Text(
                    coordinator.isRecording
                        ? NSLocalizedString("creator.recording", value: "Recording", comment: "Duo camera recording state")
                        : NSLocalizedString("creator.camera.ready", value: "Camera ready", comment: "Duo camera ready state")
                )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.38), in: Capsule())
                    .padding(.bottom, 18)
            }
        }
        .ignoresSafeArea()
    }

    private var formattedDuration: String {
        let total = max(0, Int(coordinator.recordingDuration))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct DuoCameraAccessoryModifier: ViewModifier {
    @ObservedObject var coordinator: DuoCameraAccessoryCoordinator

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.sceneAccessory {
                CameraCaptureAccessory(isEnabled: $coordinator.isEnabled) {
                    DuoCameraAccessoryView(coordinator: coordinator)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func momentsDuoCameraAccessory() -> some View {
        modifier(DuoCameraAccessoryModifier(coordinator: .shared))
    }
}
