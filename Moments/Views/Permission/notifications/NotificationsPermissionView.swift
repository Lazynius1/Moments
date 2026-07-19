import SwiftUI
import UIKit

struct NotificationsPermissionView: View {
    var stage: PermissionPrimerStage = .primer
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    private var isDenied: Bool { stage == .denied }

    var body: some View {
        PermissionPrimerScaffold(
            stage: stage,
            iconSymbol: isDenied ? "bell.slash" : "bell.badge",
            title: title,
            description: description,
            primaryActionTitle: primaryActionTitle,
            secondaryActionTitle: NSLocalizedString("permission.notifications.primer.notNow", comment: "Not now"),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ) {
            PermissionPhoneFrame(
                screenBackground: Color(hex: "0A0A0C"),
                animated: false,
                showsStatusBarTime: false,
                appliesDeniedChrome: isDenied
            ) { size, _ in
                NotificationBannerScreen(size: size, isActive: !isDenied)
            } island: { _, _ in
                EmptyView()
            }
        }
    }

    private var title: String {
        stage == .primer
            ? NSLocalizedString("permission.notifications.primer.title", comment: "Notifications primer title")
            : NSLocalizedString("permission.notifications.denied.title", comment: "Notifications denied title")
    }

    private var description: String {
        stage == .primer
            ? NSLocalizedString("permission.notifications.primer.subtitle", comment: "Notifications primer subtitle")
            : NSLocalizedString("permission.notifications.denied.subtitle", comment: "Notifications denied subtitle")
    }

    private var primaryActionTitle: String {
        stage == .primer
            ? NSLocalizedString("permission.notifications.primer.allow", comment: "Allow notifications")
            : NSLocalizedString("permission.notifications.denied.openSettings", comment: "Open Settings")
    }
}

private struct NotificationBannerScreen: View {
    let size: CGSize
    var isActive: Bool = true

    private var iconSize: CGFloat { size.width * 0.105 }
    private var cardRadius: CGFloat { size.width * 0.065 }

    var body: some View {
        ZStack {
            PermissionPhoneWallpaper()
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.28), .clear, .black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: size.height * 0.028) {
                lockScreenClock

                if isActive {
                    notificationCard
                        .keyframeAnimator(initialValue: BannerState(), repeating: true) { content, state in
                            content
                                .offset(y: state.yOffset)
                                .scaleEffect(state.scale, anchor: .top)
                                .opacity(state.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.yOffset) {
                                CubicKeyframe(-size.height * 0.08, duration: 0.35)
                                SpringKeyframe(0, duration: 0.85, spring: .snappy(extraBounce: 0.12))
                                LinearKeyframe(0, duration: 2.2)
                                CubicKeyframe(-size.height * 0.02, duration: 0.45)
                            }
                            KeyframeTrack(\.scale) {
                                CubicKeyframe(0.94, duration: 0.35)
                                SpringKeyframe(1, duration: 0.85, spring: .snappy)
                                LinearKeyframe(1, duration: 2.2)
                                CubicKeyframe(0.98, duration: 0.45)
                            }
                            KeyframeTrack(\.opacity) {
                                CubicKeyframe(0, duration: 0.25)
                                CubicKeyframe(1, duration: 0.35)
                                LinearKeyframe(1, duration: 2.45)
                                CubicKeyframe(0, duration: 0.4)
                            }
                        }
                } else {
                    notificationCard
                        .opacity(0.45)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, size.width * 0.045)
            .padding(.top, size.height * 0.105)
        }
        .frame(width: size.width, height: size.height)
    }

    private var lockScreenClock: some View {
        VStack(spacing: size.height * 0.002) {
            TimelineView(.everyMinute) { context in
                Text(
                    context.date,
                    format: .dateTime.weekday(.wide).day().month(.wide)
                )
                .font(.system(size: size.width * 0.048, weight: .semibold, design: .default))
                .foregroundStyle(.white.opacity(0.9))
            }

            Text(verbatim: "9:41")
                .font(.system(size: size.width * 0.26, weight: .thin, design: .default))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    /// Lock-screen style notification: app icon + app name/time + title + body.
    private var notificationCard: some View {
        let shape = RoundedRectangle(cornerRadius: cardRadius, style: .continuous)

        return HStack(alignment: .top, spacing: size.width * 0.03) {
            appIcon
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous))

            VStack(alignment: .leading, spacing: size.height * 0.004) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "Moments")
                        .font(.system(size: size.width * 0.034, weight: .semibold, design: .default))
                        .foregroundStyle(.white.opacity(0.72))
                        .textCase(.uppercase)
                        .tracking(0.3)

                    Spacer(minLength: 4)

                    Text(NSLocalizedString("permission.notifications.mock.now", comment: "Notification time label"))
                        .font(.system(size: size.width * 0.032, weight: .regular, design: .default))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(NSLocalizedString("permission.notifications.mock.sender", comment: "Mock sender name"))
                    .font(.system(size: size.width * 0.042, weight: .semibold, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(NSLocalizedString("permission.notifications.mock.body", comment: "Mock notification body"))
                    .font(.system(size: size.width * 0.04, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, size.width * 0.035)
        .padding(.vertical, size.width * 0.032)
        .momentsChromeGlass(in: shape, interactive: false, style: .native)
    }

    /// Same source iOS uses for notification app artwork when available.
    @ViewBuilder
    private var appIcon: some View {
        if let icon = Self.bundleAppIcon {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(.logo)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private static var bundleAppIcon: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for name in files.reversed() {
                if let image = UIImage(named: name) {
                    return image
                }
            }
        }
        return UIImage(named: "AppIcon")
    }
}

private struct BannerState {
    var yOffset: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: CGFloat = 0
}

#Preview("Primer") {
    NotificationsPermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
}

#Preview("Denied") {
    NotificationsPermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
}
