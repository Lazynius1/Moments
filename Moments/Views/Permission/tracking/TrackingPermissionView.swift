import SwiftUI

struct TrackingPermissionView: View {
    var stage: PermissionPrimerStage = .primer
    var primaryAction: () -> Void

    private var isDenied: Bool { stage == .denied }

    var body: some View {
        PermissionPrimerScaffold(
            stage: stage,
            iconSymbol: isDenied ? "hand.raised.slash.fill" : "hand.raised.fill",
            title: title,
            description: description,
            primaryActionTitle: primaryActionTitle,
            primaryAction: primaryAction
        ) {
            PermissionPhoneFrame(
                screenBackground: Color(hex: "111318"),
                animated: false,
                appliesDeniedChrome: isDenied
            ) { size, _ in
                TrackingFeedScreen(size: size, isActive: !isDenied)
            } island: { _, _ in
                EmptyView()
            }
        }
    }

    private var title: String {
        stage == .primer
            ? NSLocalizedString("attPreAlert.title", comment: "Tracking primer title")
            : NSLocalizedString("permission.tracking.denied.title", comment: "Tracking denied title")
    }

    private var description: String {
        stage == .primer
            ? NSLocalizedString("attPreAlert.description", comment: "Tracking primer subtitle")
            : NSLocalizedString("permission.tracking.denied.subtitle", comment: "Tracking denied subtitle")
    }

    private var primaryActionTitle: String {
        stage == .primer
            ? NSLocalizedString("attPreAlert.continueButton", comment: "Continue")
            : NSLocalizedString("permission.tracking.denied.openSettings", comment: "Open Settings")
    }
}

private struct TrackingFeedScreen: View {
    let size: CGSize
    var isActive: Bool = true

    private let cardCount = 5
    private let accentIndex = 1
    private let accent = Color(hex: "6C5CE7")

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation) { timeline in
                    feed(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                feed(at: 0)
                    .blur(radius: 2.5)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private let loopDuration: TimeInterval = 9

    private func feed(at t: TimeInterval) -> some View {
        let spacing = size.height * 0.02
        let cardHeight = size.height * 0.26
        let setHeight = (cardHeight + spacing) * CGFloat(cardCount)
        let progress = (t.truncatingRemainder(dividingBy: loopDuration)) / loopDuration
        let scroll = isActive ? CGFloat(progress) * setHeight : max(setHeight - size.height, 0) * 0.4
        let renderedSets = isActive ? 2 : 1

        return VStack(spacing: spacing) {
            ForEach(0..<(cardCount * renderedSets), id: \.self) { index in
                card(highlighted: index % cardCount == accentIndex, height: cardHeight)
            }
        }
        .padding(.horizontal, size.width * 0.05)
        .offset(y: -scroll)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func card(highlighted: Bool, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: size.height * 0.012) {
            HStack(spacing: size.width * 0.03) {
                Circle()
                    .fill(highlighted ? accent : Color.white.opacity(0.18))
                    .frame(width: size.width * 0.1, height: size.width * 0.1)

                VStack(alignment: .leading, spacing: size.height * 0.006) {
                    Capsule().fill(.white.opacity(0.5)).frame(width: size.width * 0.34, height: size.height * 0.012)
                    Capsule().fill(.white.opacity(0.28)).frame(width: size.width * 0.22, height: size.height * 0.01)
                }

                Spacer(minLength: 0)

                if highlighted {
                    HStack(spacing: size.width * 0.01) {
                        Image(systemName: "sparkles")
                            .font(.system(size: size.width * 0.032, weight: .semibold))
                        Text(verbatim: "Ad")
                            .font(.system(size: size.width * 0.032, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, size.width * 0.025)
                    .padding(.vertical, size.height * 0.005)
                    .background(Capsule().fill(accent))
                }
            }

            RoundedRectangle(cornerRadius: size.width * 0.03, style: .continuous)
                .fill(
                    highlighted
                        ? LinearGradient(colors: [accent.opacity(0.85), Color(hex: "4C8DFF").opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                )
                .frame(maxWidth: .infinity)
                .frame(height: height * 0.55)
        }
        .padding(size.width * 0.035)
        .background(
            RoundedRectangle(cornerRadius: size.width * 0.05, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: size.width * 0.05, style: .continuous)
                        .stroke(highlighted ? accent.opacity(0.7) : Color.clear, lineWidth: 1.5)
                )
        )
        .frame(height: height)
    }
}

#Preview("Primer") {
    TrackingPermissionView(stage: .primer, primaryAction: {})
}

#Preview("Denied") {
    TrackingPermissionView(stage: .denied, primaryAction: {})
}
