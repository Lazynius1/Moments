import SwiftUI

struct MicrophonePermissionView: View {
    var stage: PermissionPrimerStage = .primer
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    private var isDenied: Bool { stage == .denied }

    var body: some View {
        PermissionPrimerScaffold(
            stage: stage,
            iconSymbol: isDenied ? "mic.slash" : "mic",
            title: title,
            description: description,
            primaryActionTitle: primaryActionTitle,
            secondaryActionTitle: NSLocalizedString("permission.microphone.primer.notNow", comment: "Not now"),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ) {
            PermissionPhoneFrame(
                animated: false,
                showsIslandIndicators: !isDenied,
                appliesDeniedChrome: isDenied
            ) { size, _ in
                MicrophonePulseScreen(size: size, isActive: !isDenied)
            } island: { ratio, _ in
                Circle()
                    .fill(.orange)
                    .frame(width: 10 * ratio, height: 10 * ratio)
                    .offset(x: 12 * ratio)
            }
        }
    }

    private var title: String {
        stage == .primer
            ? NSLocalizedString("permission.microphone.primer.title", comment: "Mic primer title")
            : NSLocalizedString("permission.microphone.denied.title", comment: "Mic denied title")
    }

    private var description: String {
        stage == .primer
            ? NSLocalizedString("permission.microphone.primer.subtitle", comment: "Mic primer subtitle")
            : NSLocalizedString("permission.microphone.denied.subtitle", comment: "Mic denied subtitle")
    }

    private var primaryActionTitle: String {
        stage == .primer
            ? NSLocalizedString("permission.microphone.primer.allow", comment: "Allow mic")
            : NSLocalizedString("permission.microphone.denied.openSettings", comment: "Open Settings")
    }
}

private struct MicrophonePulseScreen: View {
    let size: CGSize
    var isActive: Bool = true
    private let waveCount = 3
    private let period: Double = 2.4

    private var waveGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "FF9F45"), Color(hex: "FF3D71")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            PermissionPhoneWallpaper()
                .overlay(Color.black.opacity(0.55))

            Group {
                if isActive {
                    TimelineView(.animation) { timeline in
                        waves(at: timeline.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    waves(at: 0)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func waves(at t: TimeInterval) -> some View {
        ZStack {
            if isActive {
                ForEach(0..<waveCount, id: \.self) { index in
                    let phase = ((t + Double(index) * period / Double(waveCount))
                        .truncatingRemainder(dividingBy: period)) / period
                    let arcSize = size.width * (0.24 + CGFloat(phase) * 0.5)

                    ForEach([true, false], id: \.self) { facingRight in
                        SoundWaveArc(facingRight: facingRight)
                            .stroke(waveGradient, style: StrokeStyle(lineWidth: size.width * 0.018, lineCap: .round))
                            .frame(width: arcSize, height: arcSize)
                            .opacity(1 - phase)
                    }
                }
            }

            Image(systemName: isActive ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: size.width * 0.22, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.55))
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }
}

private struct SoundWaveArc: Shape {
    var facingRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        if facingRight {
            path.addArc(center: center, radius: radius, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
        } else {
            path.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(225), clockwise: false)
        }
        return path
    }
}

#Preview("Primer") {
    MicrophonePermissionView(stage: .primer, primaryAction: {}, secondaryAction: {})
}

#Preview("Denied") {
    MicrophonePermissionView(stage: .denied, primaryAction: {}, secondaryAction: {})
}
