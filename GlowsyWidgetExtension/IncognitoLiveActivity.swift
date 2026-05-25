import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
private enum IncognitoLiveActivityConstants {
    static let accent = Color.white
    static let pauseBackground = Color.white.opacity(0.18)
}

@available(iOS 18.0, *)
private func incognitoText(_ key: String, _ comment: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: comment)
}

@available(iOS 18.0, *)
private struct CountdownText: View {
    let remainingSeconds: Int
    let size: CGFloat
    let width: CGFloat
    var weight: Font.Weight = .regular

    private var endDate: Date {
        Date().addingTimeInterval(TimeInterval(max(remainingSeconds, 0)))
    }

    var body: some View {
        Text(endDate, style: .timer)
            .font(.system(size: size, weight: weight, design: .rounded).monospacedDigit())
            .foregroundStyle(IncognitoLiveActivityConstants.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.52)
            .frame(width: width, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(Text(incognitoText("incognito.activity.remaining", "Remaining time")))
    }
}

@available(iOS 18.0, *)
private struct PauseButton: View {
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Button(intent: PauseIncognitoIntent()) {
            ZStack {
                Circle()
                    .fill(IncognitoLiveActivityConstants.pauseBackground)

                Image(systemName: "pause.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(IncognitoLiveActivityConstants.accent)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(incognitoText("incognito.activity.pause", "Pause incognito")))
    }
}

@available(iOS 18.0, *)
private struct CompactGlyph: View {
    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(IncognitoLiveActivityConstants.accent)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

@available(iOS 18.0, *)
private struct TimerLabel: View {
    let size: CGFloat

    var body: some View {
        Text(incognitoText("incognito.activity.title", "Incognito activity title"))
            .font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundStyle(IncognitoLiveActivityConstants.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
    }
}

@available(iOS 18.0, *)
private struct TimerActivityRow: View {
    let remainingSeconds: Int
    let pauseSize: CGFloat
    let pauseIconSize: CGFloat
    let titleSize: CGFloat
    let timerSize: CGFloat
    let timerWidth: CGFloat
    var titleTimerSpacing: CGFloat = 14

    var body: some View {
        HStack(spacing: 16) {
            PauseButton(size: pauseSize, iconSize: pauseIconSize)

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: titleTimerSpacing) {
                TimerLabel(size: titleSize)

                CountdownText(
                    remainingSeconds: remainingSeconds,
                    size: timerSize,
                    width: timerWidth
                )
            }
            .layoutPriority(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

@available(iOS 18.0, *)
private struct LockScreenIncognitoActivity: View {
    let context: ActivityViewContext<IncognitoActivityAttributes>

    var body: some View {
        TimerActivityRow(
            remainingSeconds: context.state.remainingSeconds,
            pauseSize: 52,
            pauseIconSize: 19,
            titleSize: 20,
            timerSize: 42,
            timerWidth: 132
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .center)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.white)
    }
}

@available(iOS 18.0, *)
private struct ExpandedIncognitoActivity: View {
    let context: ActivityViewContext<IncognitoActivityAttributes>

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            TimerLabel(size: 13)

            CountdownText(
                remainingSeconds: context.state.remainingSeconds,
                size: 44,
                width: 116
            )
        }
        .frame(width: 176, alignment: .trailing)
    }
}

@available(iOS 18.0, *)
private struct CompactCountdown: View {
    let remainingSeconds: Int

    var body: some View {
        CountdownText(
            remainingSeconds: remainingSeconds,
            size: 13,
            width: 48,
            weight: .semibold
        )
    }
}

@available(iOS 18.0, *)
struct IncognitoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IncognitoActivityAttributes.self) { context in
            LockScreenIncognitoActivity(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    PauseButton(size: 50, iconSize: 20)
                }
                .contentMargins(.leading, 16)

                DynamicIslandExpandedRegion(.trailing, priority: 3) {
                    ExpandedIncognitoActivity(context: context)
                }
                .contentMargins(.trailing, 16)
            } compactLeading: {
                CompactGlyph()
            } compactTrailing: {
                CompactCountdown(remainingSeconds: context.state.remainingSeconds)
            } minimal: {
                CompactCountdown(remainingSeconds: context.state.remainingSeconds)
            }
            .keylineTint(IncognitoLiveActivityConstants.accent)
            .contentMargins(.leading, 16, for: .expanded)
            .contentMargins(.trailing, 16, for: .expanded)
            .widgetURL(URL(string: "moments://profile"))
        }
    }
}
