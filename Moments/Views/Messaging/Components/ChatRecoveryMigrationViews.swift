import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins
import UIKit

struct ChatRecoveryMigrateSourceView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session: ChatRecoveryMigrationSession?
    @State private var qrImage: UIImage?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var currentTime = Date()
    @State private var didCopy = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(NSLocalizedString("chatRecovery.migrate.subtitle", comment: "Show this QR on the new phone"))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                        )

                    if let remaining = remainingText {
                        Text(remaining)
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    // Fallback if the other phone can't scan: copy silently, never show the raw link.
                    Button(didCopy
                           ? NSLocalizedString("chatRecovery.migrate.codeCopied", comment: "Link copied")
                           : NSLocalizedString("chatRecovery.migrate.copyCode", comment: "Copy link for the other phone")) {
                        guard let payload = session?.qrPayload else { return }
                        UIPasteboard.general.string = payload
                        didCopy = true
                    }
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(NSLocalizedString("chatRecovery.action.retry", comment: "Retry")) {
                        Task { await startMigration() }
                    }
                }

                Spacer()
            }
            .padding(.top, 12)
            .navigationTitle(NSLocalizedString("chatRecovery.migrate.title", comment: "Move to another phone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("chatRecovery.action.close", comment: "Close")) {
                        dismiss()
                    }
                }
            }
            .task {
                await startMigration()
            }
            .onReceive(timer) { date in
                currentTime = date
            }
        }
    }

    private var remainingText: String? {
        guard let expiresAt = session?.expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSince(currentTime)
        guard remaining > 0 else {
            return NSLocalizedString("chatRecovery.error.migrationExpired", comment: "Migration code expired")
        }
        let totalSeconds = Int(remaining.rounded(.up))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(
            format: NSLocalizedString("chatRecovery.migrate.expire", comment: "Expires in %@"),
            String(format: "%d:%02d", minutes, seconds)
        )
    }

    private func startMigration() async {
        isLoading = true
        errorMessage = nil
        didCopy = false
        defer { isLoading = false }

        do {
            let session = try await EncryptionService.shared.beginDeviceMigration()
            self.session = session
            self.qrImage = Self.makeQRCode(from: session.qrPayload)
        } catch {
            errorMessage = error.localizedDescription
            session = nil
            qrImage = nil
        }
    }

    private static func makeQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct ChatRecoveryMigrateTargetView: View {
    let onSuccess: () -> Void
    let onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(NSLocalizedString("chatRecovery.migrate.enterCode", comment: "Scan the QR on your other phone"))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    showScanner = true
                } label: {
                    Text(isSubmitting
                           ? NSLocalizedString("chatRecovery.migrate.completing", comment: "Completing…")
                           : NSLocalizedString("chatRecovery.migrate.scan", comment: "Scan QR"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)

                Button(NSLocalizedString("chatRecovery.migrate.paste", comment: "Paste link from clipboard")) {
                    pasteAndSubmit()
                }
                .disabled(isSubmitting)

                Spacer()
            }
            .padding(20)
            .navigationTitle(NSLocalizedString("chatRecovery.restore.fromOtherDevice", comment: "Coming from another phone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("chatRecovery.action.close", comment: "Close")) {
                        onCancel?()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                ChatRecoveryQRScannerView { scanned in
                    showScanner = false
                    submit(scanned)
                }
            }
        }
    }

    private func pasteAndSubmit() {
        guard let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else {
            errorMessage = NSLocalizedString("chatRecovery.migrate.clipboardEmpty", comment: "Nothing to paste from clipboard")
            return
        }
        submit(pasted)
    }

    private func submit(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            defer { isSubmitting = false }
            do {
                try await EncryptionService.shared.completeDeviceMigration(qrOrCode: trimmed)
                await ChatAccessCoordinator.shared.refreshAccess()
                onSuccess()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ChatRecoverySavePINToVaultView: View {
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var pin = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var activeField: ChatRecoveryPINField.Kind = .primary

    var body: some View {
        let palette = ChatRecoveryPalette(colorScheme: colorScheme)

        ChatRecoveryFormContainer(
            title: NSLocalizedString("chatRecovery.vault.saveTitle", comment: "Save PIN on this phone"),
            subtitle: NSLocalizedString("chatRecovery.vault.saveSubtitle", comment: "Enter your recovery PIN once so this phone can restore without typing it next time")
        ) {
            ChatRecoveryPINField(
                title: NSLocalizedString("chatRecovery.field.recoveryPin", comment: "Recovery PIN"),
                subtitle: NSLocalizedString("chatRecovery.field.sixDigits", comment: "6 digits"),
                text: $pin,
                length: 6,
                kind: .primary,
                activeField: $activeField
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(palette.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            Button(isSubmitting
                   ? NSLocalizedString("chatRecovery.action.saving", comment: "Saving")
                   : NSLocalizedString("chatRecovery.action.savePin", comment: "Save PIN")) {
                save()
            }
            .buttonStyle(ChatRecoveryPrimaryButtonStyle())
            .disabled(isSubmitting)

            Button(NSLocalizedString("chatRecovery.action.notNow", comment: "Not now")) {
                onDone()
            }
            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
            .foregroundStyle(palette.mutedAction)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            activeField = .primary
        }
    }

    private func save() {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPIN(trimmed, length: 6) else {
            errorMessage = NSLocalizedString("chatRecovery.error.enterRecoveryPin", comment: "Enter your 6-digit recovery PIN")
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await EncryptionService.shared.saveRecoveryPINToDeviceVault(trimmed)
                onDone()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ChatRecoveryQRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ChatRecoveryQRScannerController {
        let controller = ChatRecoveryQRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ChatRecoveryQRScannerController, context: Context) {}
}

final class ChatRecoveryQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var didEmit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return
        }

        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        contextPreviewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private var contextPreviewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contextPreviewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              value.contains("moments-migrate://")
        else {
            return
        }
        didEmit = true
        session.stopRunning()
        onCode?(value)
    }
}
