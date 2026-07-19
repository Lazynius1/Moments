import CoreLocation
import SwiftUI
import UIKit

enum LocationPermissionAccessLevel {
    case whenInUse
    case always
}

@MainActor
final class LocationPermissionGate: NSObject, ObservableObject {
    @Published var isPresenting = false
    @Published var stage: PermissionPrimerStage = .primer
    @Published var accessLevel: LocationPermissionAccessLevel = .whenInUse

    private let manager = CLLocationManager()
    private var onGranted: (() -> Void)?
    private var awaitingResponse = false
    private var pendingAlwaysAfterWhenInUse = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestAccess(
        level: LocationPermissionAccessLevel = .whenInUse,
        onGranted: @escaping () -> Void
    ) {
        accessLevel = level
        pendingAlwaysAfterWhenInUse = false

        switch manager.authorizationStatus {
        case .authorizedAlways:
            onGranted()
        case .authorizedWhenInUse:
            if level == .whenInUse {
                onGranted()
            } else {
                self.onGranted = onGranted
                stage = .primer
                isPresenting = true
            }
        case .notDetermined:
            self.onGranted = onGranted
            stage = .primer
            isPresenting = true
        default:
            self.onGranted = onGranted
            stage = .denied
            isPresenting = true
        }
    }

    func primaryAction() {
        if stage == .denied {
            openSettings()
            return
        }

        awaitingResponse = true
        switch accessLevel {
        case .whenInUse:
            manager.requestWhenInUseAuthorization()
        case .always:
            switch manager.authorizationStatus {
            case .authorizedWhenInUse:
                manager.requestAlwaysAuthorization()
            case .notDetermined:
                // iOS requires When In Use first; the native Always prompt follows.
                pendingAlwaysAfterWhenInUse = true
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways:
                finish(granted: true)
            default:
                awaitingResponse = false
                stage = .denied
            }
        }
    }

    func dismiss() {
        isPresenting = false
        awaitingResponse = false
        pendingAlwaysAfterWhenInUse = false
        onGranted = nil
    }

    private func finish(granted: Bool) {
        awaitingResponse = false
        pendingAlwaysAfterWhenInUse = false
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

extension LocationPermissionGate: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard awaitingResponse else { return }
            switch status {
            case .notDetermined:
                return
            case .authorizedAlways:
                finish(granted: true)
            case .authorizedWhenInUse:
                if accessLevel == .always, pendingAlwaysAfterWhenInUse {
                    pendingAlwaysAfterWhenInUse = false
                    manager.requestAlwaysAuthorization()
                    return
                }
                // While Using is enough to continue (user may decline Always in the system sheet).
                finish(granted: true)
            default:
                finish(granted: false)
            }
        }
    }
}

private struct LocationPermissionGateModifier: ViewModifier {
    @ObservedObject var gate: LocationPermissionGate

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $gate.isPresenting) {
            LocationPermissionView(
                stage: gate.stage,
                accessLevel: gate.accessLevel,
                primaryAction: gate.primaryAction,
                secondaryAction: gate.dismiss
            )
        }
    }
}

extension View {
    func locationPermissionGate(_ gate: LocationPermissionGate) -> some View {
        modifier(LocationPermissionGateModifier(gate: gate))
    }
}
