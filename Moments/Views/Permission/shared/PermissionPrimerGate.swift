import AVFoundation
import Photos
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class PermissionPrimerGate: ObservableObject {
    enum Kind {
        case microphone
        case photos
        case photosSave
        case notifications
    }

    let kind: Kind
    @Published var isPresenting = false
    @Published var stage: PermissionPrimerStage = .primer

    private var onGranted: (() -> Void)?

    init(_ kind: Kind) {
        self.kind = kind
    }

    func requestAccess(onGranted: @escaping () -> Void) {
        switch currentState {
        case .authorized:
            onGranted()
        case .notDetermined:
            self.onGranted = onGranted
            stage = .primer
            isPresenting = true
        case .denied:
            self.onGranted = onGranted
            stage = .denied
            isPresenting = true
        }
    }

    func primaryAction() {
        if stage == .primer {
            requestNative()
        } else {
            openSettings()
        }
    }

    func dismiss() {
        isPresenting = false
    }

    private enum State { case authorized, notDetermined, denied }

    private var currentState: State {
        switch kind {
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .authorized
            case .undetermined: return .notDetermined
            default: return .denied
            }
        case .photos:
            return mapPhotos(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .photosSave:
            return mapPhotos(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        case .notifications:
            return notificationsState
        }
    }

    private func mapPhotos(_ status: PHAuthorizationStatus) -> State {
        switch status {
        case .authorized, .limited: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private var notificationsState: State {
        switch cachedNotificationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private var cachedNotificationStatus: UNAuthorizationStatus = .notDetermined

    func refreshNotificationStatus(_ completion: @escaping () -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.cachedNotificationStatus = settings.authorizationStatus
                completion()
            }
        }
    }

    private func requestNative() {
        switch kind {
        case .microphone:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { self.finish(granted: granted) }
            }
        case .photos:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async { self.finish(granted: self.mapPhotos(status) == .authorized) }
            }
        case .photosSave:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async { self.finish(granted: self.mapPhotos(status) == .authorized) }
            }
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    self.cachedNotificationStatus = granted ? .authorized : .denied
                    self.finish(granted: granted)
                }
            }
        }
    }

    private func finish(granted: Bool) {
        guard granted else {
            stage = .denied
            return
        }
        isPresenting = false
        let continuation = onGranted
        onGranted = nil
        continuation?()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        isPresenting = false
    }
}

private struct PermissionPrimerGateModifier: ViewModifier {
    @ObservedObject var gate: PermissionPrimerGate

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $gate.isPresenting) {
            screen
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch gate.kind {
        case .microphone:
            MicrophonePermissionView(stage: gate.stage, primaryAction: gate.primaryAction, secondaryAction: gate.dismiss)
        case .photos, .photosSave:
            PhotosPermissionView(stage: gate.stage, primaryAction: gate.primaryAction, secondaryAction: gate.dismiss)
        case .notifications:
            NotificationsPermissionView(stage: gate.stage, primaryAction: gate.primaryAction, secondaryAction: gate.dismiss)
        }
    }
}

extension View {
    func permissionPrimerGate(_ gate: PermissionPrimerGate) -> some View {
        modifier(PermissionPrimerGateModifier(gate: gate))
    }
}
