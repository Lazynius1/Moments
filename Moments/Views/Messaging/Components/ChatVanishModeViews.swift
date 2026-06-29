import SwiftUI

enum ChatVanishSwipeMetrics {
    /// Distancia para completar el arco (IG ~88pt).
    static let activationDistance: CGFloat = 88
    static let maxPull: CGFloat = 108
    static let completionThreshold: CGFloat = 0.92
    /// Cada cuántos puntos de pull dispara un tick háptico.
    static let hapticStepPoints: CGFloat = 5

    /// Curva elástica suave — más resistencia al final del pull.
    static func rubberBandPull(from translation: CGFloat) -> CGFloat {
        let raw = max(0, -translation)
        guard raw > 0 else { return 0 }
        let limit = maxPull
        let resistance: CGFloat = 2.4
        return limit * (1 - exp(-raw / (limit / resistance)))
    }

    static func progress(for pull: CGFloat) -> CGFloat {
        min(max(pull / activationDistance, 0), 1)
    }
}

struct ChatVanishModeProgressIndicator: View {
    let progress: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(adaptiveColors.primary.opacity(0.14), lineWidth: 2.5)
                .frame(width: 36, height: 36)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(adaptiveColors.primary.opacity(0.88), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 36, height: 36)
        }
        .accessibilityHidden(true)
    }
}

struct ChatVanishPullRevealLayer: View {
    let pullOffset: CGFloat
    let progress: CGFloat
    let isActive: Bool
    let isDragging: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var hintKey: LocalizedStringKey {
        if isDragging, progress >= ChatVanishSwipeMetrics.completionThreshold {
            return isActive ? "chat.vanish.swipe.release.off" : "chat.vanish.swipe.release"
        }
        return isActive ? "chat.vanish.swipe.hint.off" : "chat.vanish.swipe.hint"
    }

    private var revealOpacity: Double {
        Double(min(1, pullOffset / 28))
    }

    var body: some View {
        VStack(spacing: 8) {
            ChatVanishModeProgressIndicator(progress: progress)
            Text(hintKey)
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .opacity(revealOpacity)
        .scaleEffect(0.94 + min(progress, 1) * 0.06)
        // Centrado en la franja revelada entre input y último mensaje.
        .offset(y: -pullOffset * 0.5)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(isActive ? LocalizedStringKey("chat.vanish.active.accessibility") : LocalizedStringKey("chat.vanish.inactive.accessibility"))
        )
    }
}

/// Overlay flotante — no reserva espacio en el scroll (evita “aire” en reposo).
struct ChatVanishSwipeRevealFooter: View {
    let pullOffset: CGFloat
    let progress: CGFloat
    let isActive: Bool
    let isDragging: Bool

    var body: some View {
        ChatVanishPullRevealLayer(
            pullOffset: pullOffset,
            progress: progress,
            isActive: isActive,
            isDragging: isDragging
        )
    }
}

struct ChatVanishSwipeHint: View {
    let pullOffset: CGFloat
    let progress: CGFloat
    let isActive: Bool
    let isDragging: Bool

    var body: some View {
        ChatVanishSwipeRevealFooter(
            pullOffset: pullOffset,
            progress: progress,
            isActive: isActive,
            isDragging: isDragging
        )
    }
}

struct ChatDisappearingNoticeRow: View {
    let noticeToken: String
    let actorUserId: String?
    let currentUserId: String
    let otherParticipantName: String
    var onChangeTimer: (() -> Void)?
    var onTurnOn: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var bodyColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.52)
    }

    private var actionColor: Color {
        colorScheme == .dark ? Color.orange : Color(red: 0.78, green: 0.24, blue: 0.18)
    }

    private var isSelfActor: Bool {
        guard let actorUserId, !actorUserId.isEmpty else { return true }
        return actorUserId == currentUserId
    }

    private var actorDisplayName: String {
        let trimmed = otherParticipantName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSLocalizedString("messaging.user.default", comment: "Default user name")
        }
        return trimmed
    }

    var body: some View {
        Group {
            if let timer = VanishMessageTimer.parseEnabledNotice(noticeToken) {
                enabledNotice(timer: timer)
            } else if noticeToken == VanishMessageTimer.disabledNoticeToken {
                disabledNotice
            } else if noticeToken == VanishMessageTimer.screenshotNoticeToken {
                plainNotice("chat.vanish.screenshot")
            } else if noticeToken == VanishMessageTimer.screenRecordingNoticeToken {
                plainNotice("chat.vanish.screenRecording")
            } else if noticeToken == "chat.vanish.enabled" {
                enabledNotice(timer: .hours24)
            } else if noticeToken == "chat.vanish.disabled" {
                disabledNotice
            } else if noticeToken.hasPrefix("chat.vanish.") {
                plainNotice(noticeToken)
            } else {
                plainNotice(noticeToken)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func enabledNotice(timer: VanishMessageTimer) -> some View {
        let prefix = isSelfActor
            ? Text(LocalizedStringKey("chat.vanish.notice.enabled.prefix.self"))
            : Text(
                String(
                    format: NSLocalizedString(
                        "chat.vanish.notice.enabled.prefix.other",
                        comment: "Other user enabled vanish notice prefix"
                    ),
                    actorDisplayName
                )
            )

        (
            prefix
            + Text(LocalizedStringKey(timer.noticeDurationKey))
            + Text(LocalizedStringKey("chat.vanish.notice.enabled.suffix"))
            + Text(" ")
            + Text(LocalizedStringKey("chat.vanish.notice.change"))
                .foregroundColor(actionColor)
                .fontWeight(.semibold)
        )
        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
        .foregroundStyle(bodyColor)
        .multilineTextAlignment(.center)
        .onTapGesture {
            onChangeTimer?()
        }
    }

    private var disabledNotice: some View {
        let bodyText = isSelfActor
            ? Text(LocalizedStringKey("chat.vanish.notice.disabled.self"))
            : Text(
                String(
                    format: NSLocalizedString(
                        "chat.vanish.notice.disabled.other",
                        comment: "Other user disabled vanish notice"
                    ),
                    actorDisplayName
                )
            )

        return (
            bodyText
            + Text(" ")
            + Text(LocalizedStringKey("chat.vanish.notice.turnOn"))
                .foregroundColor(actionColor)
                .fontWeight(.semibold)
        )
        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
        .foregroundStyle(bodyColor)
        .multilineTextAlignment(.center)
        .onTapGesture {
            onTurnOn?()
        }
    }

    private func plainNotice(_ key: String) -> some View {
        Text(LocalizedStringKey(key))
            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
            .foregroundStyle(bodyColor)
            .multilineTextAlignment(.center)
    }
}

struct ChatVanishTimerSheet: View {
    @Binding var isPresented: Bool
    let selectedTimer: VanishMessageTimer
    let onSelect: (VanishMessageTimer?) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    timerRow(.onceSeen)
                    timerRow(.hours24)
                    timerRow(.days7)
                }

                Section {
                    Button(role: .destructive) {
                        onSelect(nil)
                        isPresented = false
                    } label: {
                        HStack {
                            Text(LocalizedStringKey("chat.vanish.timer.off"))
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey("chat.vanish.timer.sheet.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("common.done")) {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func timerRow(_ timer: VanishMessageTimer) -> some View {
        Button {
            onSelect(timer)
            isPresented = false
        } label: {
            HStack {
                Text(LocalizedStringKey(timer.localizationKey))
                Spacer()
                if timer == selectedTimer {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .foregroundStyle(colorScheme == .dark ? .white : .black)
    }
}

private extension VanishMessageTimer {
    var noticeDurationKey: String {
        switch self {
        case .onceSeen: return "chat.vanish.notice.duration.onceSeen"
        case .hours24: return "chat.vanish.notice.duration.24h"
        case .days7: return "chat.vanish.notice.duration.7d"
        }
    }
}

struct ChatVanishInboxIndicator: View {
    let isUnread: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var ringColor: Color {
        if isUnread {
            return Color(hex: "007AFF")
        }
        return colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.32)
    }

    var body: some View {
        Circle()
            .stroke(ringColor, style: StrokeStyle(lineWidth: 1.5, dash: [2.2, 2.8]))
            .frame(width: 15, height: 15)
            .accessibilityLabel(Text(LocalizedStringKey("chat.vanish.active.accessibility")))
    }
}

struct ChatNoticeTimelineRow: View {
    let noticeKey: String
    let actorUserId: String?
    let currentUserId: String
    let otherParticipantName: String
    var onChangeTimer: (() -> Void)?
    var onTurnOn: (() -> Void)?

    var body: some View {
        ChatDisappearingNoticeRow(
            noticeToken: noticeKey,
            actorUserId: actorUserId,
            currentUserId: currentUserId,
            otherParticipantName: otherParticipantName,
            onChangeTimer: onChangeTimer,
            onTurnOn: onTurnOn
        )
    }
}
