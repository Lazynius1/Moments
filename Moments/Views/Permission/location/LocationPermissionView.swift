import SwiftUI

struct LocationPermissionView: View {
    var stage: PermissionPrimerStage = .primer
    var accessLevel: LocationPermissionAccessLevel = .whenInUse
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    private var isDenied: Bool { stage == .denied }

    var body: some View {
        PermissionPrimerScaffold(
            stage: stage,
            iconSymbol: iconSymbol,
            title: title,
            description: description,
            primaryActionTitle: primaryActionTitle,
            secondaryActionTitle: NSLocalizedString("permission.location.primer.notNow", comment: "Not now"),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ) {
            PermissionPhoneFrame(
                screenBackground: Color(hex: "1B2A24"),
                animated: !isDenied,
                islandPlacement: .leading,
                showsIslandIndicators: !isDenied,
                appliesDeniedChrome: isDenied
            ) { size, _ in
                LocationMapScreen(
                    size: size,
                    emphasizesAlways: accessLevel == .always,
                    isActive: !isDenied
                )
            } island: { ratio, _ in
                Image(systemName: "location.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14 * ratio, height: 14 * ratio)
                    .foregroundStyle(Color(hex: "4C8DFF"))
            }
        }
    }

    private var iconSymbol: String {
        if isDenied { return "location.slash" }
        return accessLevel == .always ? "location.fill" : "location"
    }

    private var title: String {
        switch (stage, accessLevel) {
        case (.primer, .whenInUse):
            return NSLocalizedString("permission.location.primer.title", comment: "Location primer title")
        case (.primer, .always):
            return NSLocalizedString("permission.location.always.primer.title", comment: "Always location primer title")
        case (.denied, .whenInUse):
            return NSLocalizedString("permission.location.denied.title", comment: "Location denied title")
        case (.denied, .always):
            return NSLocalizedString("permission.location.always.denied.title", comment: "Always location denied title")
        }
    }

    private var description: String {
        switch (stage, accessLevel) {
        case (.primer, .whenInUse):
            return NSLocalizedString("permission.location.primer.subtitle", comment: "Location primer subtitle")
        case (.primer, .always):
            return NSLocalizedString("permission.location.always.primer.subtitle", comment: "Always location primer subtitle")
        case (.denied, .whenInUse):
            return NSLocalizedString("permission.location.denied.subtitle", comment: "Location denied subtitle")
        case (.denied, .always):
            return NSLocalizedString("permission.location.always.denied.subtitle", comment: "Always location denied subtitle")
        }
    }

    private var primaryActionTitle: String {
        switch (stage, accessLevel) {
        case (.primer, .whenInUse):
            return NSLocalizedString("permission.location.primer.allow", comment: "Allow location")
        case (.primer, .always):
            return NSLocalizedString("permission.location.always.primer.allow", comment: "Allow always")
        case (.denied, _):
            return NSLocalizedString("permission.location.denied.openSettings", comment: "Open Settings")
        }
    }
}

private struct LocationMapScreen: View {
    let size: CGSize
    var emphasizesAlways: Bool = false
    var isActive: Bool = true

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation) { timeline in
                    mapContent(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                mapContent(at: 0)
            }
        }
    }

    private func mapContent(at t: TimeInterval) -> some View {
        let panX = isActive ? CGFloat(sin(t * 0.4)) * size.width * 0.5 : 0
        let panY = isActive ? CGFloat(cos(t * 0.32)) * size.height * 0.1 : 0
        let pulse = isActive ? (sin(t * 2.2) + 1) / 2 : 0.35

        return ZStack {
            Group {
                if let ui = UIImage(named: "PermissionMap") {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width * 2, height: size.height * 1.4)
                        .offset(x: panX, y: panY)
                } else {
                    LinearGradient(
                        colors: [Color(hex: "24382E"), Color(hex: "1B2A24")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            if emphasizesAlways {
                liveLocationDot(pulse: CGFloat(pulse))
            } else {
                locationPin(pulse: CGFloat(pulse))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func locationPin(pulse: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: "4C8DFF").opacity(0.22))
                .frame(width: size.width * (0.32 + 0.14 * pulse))
                .frame(height: size.width * (0.32 + 0.14 * pulse))

            Image(systemName: "mappin.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width * 0.2)
                .foregroundStyle(.white, Color(hex: "4C8DFF"))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        }
    }

    /// Blue user-location puck (Maps/Messages style) for live / Always.
    private func liveLocationDot(pulse: CGFloat) -> some View {
        let accuracy = size.width * (0.38 + 0.16 * pulse)
        let core = size.width * 0.13

        return ZStack {
            Circle()
                .fill(Color(hex: "4C8DFF").opacity(0.18))
                .frame(width: accuracy, height: accuracy)

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: max(2, size.width * 0.018))
                .background(Circle().fill(Color(hex: "4C8DFF")))
                .frame(width: core, height: core)
                .shadow(color: Color(hex: "4C8DFF").opacity(0.45), radius: 6, y: 1)
        }
    }
}

#Preview("Primer") {
    LocationPermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
}

#Preview("Always") {
    LocationPermissionView(stage: .primer, accessLevel: .always, primaryAction: {}, secondaryAction: {})
}

#Preview("Denied") {
    LocationPermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
}
