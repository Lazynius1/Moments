import SwiftUI
import UIKit

struct VanishPullResult {
    let completed: Bool
    let progress: CGFloat
    let effectivePull: CGFloat
}

enum ChatVanishSwipeMetrics {
    /// Lift adicional tras revelar UI para completar el arco (IG: ~frames 8→14).
    static let activationDistance: CGFloat = 96
    static let maxPull: CGFloat = 200
    static let completionThreshold: CGFloat = 0.96
    /// Lift mínimo del hilo antes de mostrar anillo/texto (IG: frames 1–5 solo suben chat).
    static let minLiftBeforeUIReveal: CGFloat = 58
    /// Cada cuántos puntos de lift efectivo (post-reveal) dispara un tick háptico.
    static let hapticStepPoints: CGFloat = 10
    static let pullAmplification: CGFloat = 1.0
    /// Tope de elevación del hilo.
    static let maxConversationLift: CGFloat = 168
    /// Exponente > 1: poco lift al inicio, más al final (efecto “estirar” de IG).
    static let liftCurveExponent: CGFloat = 1.08
    static let liftCurveScale: CGFloat = 0.48

    /// Curva elástica suave — más resistencia al final del pull.
    static func rubberBandPull(from translation: CGFloat) -> CGFloat {
        let raw = max(0, -translation)
        guard raw > 0 else { return 0 }
        let limit = maxPull
        let resistance: CGFloat = 2.0
        return limit * (1 - exp(-raw / (limit / resistance)))
    }

    /// Pull directo del dedo en el pan (sin rubber-band intermedio).
    static func pull(fromFingerUpward upward: CGFloat) -> CGFloat {
        scaledPull(from: max(0, upward))
    }

    /// Lift del hilo con resistencia sub-lineal (IG: el dedo recorre más que el chat sube).
    static func conversationLift(fingerUpward upward: CGFloat) -> CGFloat {
        guard upward > 0 else { return 0 }
        let resisted = pow(upward, liftCurveExponent) * liftCurveScale
        return min(resisted, maxConversationLift)
    }

    static func shouldRevealVanishUI(lift: CGFloat) -> Bool {
        lift >= minLiftBeforeUIReveal
    }

    /// Progreso del arco solo después de que el hilo haya subido lo suficiente.
    static func progress(lift: CGFloat) -> CGFloat {
        let adjusted = max(0, lift - minLiftBeforeUIReveal)
        guard adjusted > 0 else { return 0 }
        return min(adjusted / activationDistance, 1)
    }

    static func effectiveLiftForCompletion(_ lift: CGFloat) -> CGFloat {
        max(0, lift - minLiftBeforeUIReveal)
    }

    // Legacy helpers (SwiftUI notice views)
    static let revealStartPull: CGFloat = minLiftBeforeUIReveal

    static func effectiveFingerPull(_ upward: CGFloat) -> CGFloat {
        effectiveLiftForCompletion(conversationLift(fingerUpward: upward))
    }

    static func progress(fingerUpward upward: CGFloat) -> CGFloat {
        progress(lift: conversationLift(fingerUpward: upward))
    }

    /// Overscroll inferior del scroll → pull escalado.
    static func scaledPull(from rawOverscroll: CGFloat) -> CGFloat {
        max(0, rawOverscroll) * pullAmplification
    }

    /// Pull contado solo después del umbral de revelado.
    static func effectivePull(for pull: CGFloat) -> CGFloat {
        max(0, pull - revealStartPull)
    }

    static func shouldRevealUI(for pull: CGFloat) -> Bool {
        shouldRevealVanishUI(lift: conversationLift(fingerUpward: pull))
    }

    static func progress(for pull: CGFloat) -> CGFloat {
        progress(lift: conversationLift(fingerUpward: pull))
    }

    static func conversationLift(for pull: CGFloat) -> CGFloat {
        conversationLift(fingerUpward: pull)
    }
}

// MARK: - UIKit overlay (actualizado en el pan handler sin invalidar SwiftUI)

final class ChatVanishPullOverlayView: UIView {
    private let ringContainer = UIView()
    private let ringBackgroundLayer = CAShapeLayer()
    private let ringProgressLayer = CAShapeLayer()
    private let hintLabel = UILabel()
    private var centerYFromBottomConstraint: NSLayoutConstraint?
    var composerBottomInset: CGFloat = 0

    private let ringSize: CGFloat = 36
    private let ringLineWidth: CGFloat = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        configureRingContainer()
        configureLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRingLayers()
    }

    private func layoutRingLayers() {
        let inset = ringLineWidth / 2
        let ringRect = CGRect(
            x: inset,
            y: inset,
            width: ringSize - ringLineWidth,
            height: ringSize - ringLineWidth
        )
        let ringPath = UIBezierPath(ovalIn: ringRect)
        ringBackgroundLayer.path = ringPath.cgPath
        ringProgressLayer.path = ringPath.cgPath
        ringBackgroundLayer.frame = ringContainer.bounds
        ringProgressLayer.frame = ringContainer.bounds
    }

    func install(in container: UIView) {
        container.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: container.centerXAnchor),
            leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])
        centerYFromBottomConstraint = centerYAnchor.constraint(equalTo: container.bottomAnchor, constant: -80)
        centerYFromBottomConstraint?.isActive = true
    }

    func setRevealLayout(composerBottomInset inset: CGFloat, conversationLift lift: CGFloat) {
        composerBottomInset = inset
        guard ChatVanishSwipeMetrics.shouldRevealVanishUI(lift: lift) else { return }
        // Centro del hueco entre composer (fijo) y hilo levantado.
        let gapCenterFromBottom = max(inset, 0) + lift * 0.5
        centerYFromBottomConstraint?.constant = -gapCenterFromBottom
    }

    func update(
        lift: CGFloat,
        progress: CGFloat,
        isActive: Bool,
        isDragging: Bool,
        colorScheme: UIUserInterfaceStyle
    ) {
        guard ChatVanishSwipeMetrics.shouldRevealVanishUI(lift: lift) else {
            hide()
            return
        }

        setRevealLayout(composerBottomInset: composerBottomInset, conversationLift: lift)

        let palette = Self.uiPalette(for: colorScheme)
        let adjusted = ChatVanishSwipeMetrics.effectiveLiftForCompletion(lift)

        isHidden = false
        let revealOpacity = min(1, adjusted / 28)
        alpha = revealOpacity

        let scale = 0.94 + min(progress, 1) * 0.06
        ringContainer.transform = CGAffineTransform(scaleX: scale, y: scale)

        ringBackgroundLayer.strokeColor = palette.primary.withAlphaComponent(0.14).cgColor
        ringProgressLayer.strokeColor = palette.primary.withAlphaComponent(0.88).cgColor
        ringProgressLayer.strokeEnd = min(max(progress, 0), 1)

        if isDragging, progress >= ChatVanishSwipeMetrics.completionThreshold {
            hintLabel.text = isActive
                ? NSLocalizedString("chat.vanish.swipe.release.off", comment: "")
                : NSLocalizedString("chat.vanish.swipe.release", comment: "")
        } else {
            hintLabel.text = isActive
                ? NSLocalizedString("chat.vanish.swipe.hint.off", comment: "")
                : NSLocalizedString("chat.vanish.swipe.hint", comment: "")
        }
        hintLabel.textColor = palette.secondary
    }

    private static func uiPalette(for colorScheme: UIUserInterfaceStyle) -> (primary: UIColor, secondary: UIColor) {
        switch colorScheme {
        case .dark:
            return (.white, UIColor.white.withAlphaComponent(0.8))
        default:
            return (.black, UIColor.black.withAlphaComponent(0.7))
        }
    }

    func hide() {
        isHidden = true
        alpha = 0
        ringProgressLayer.strokeEnd = 0
        ringContainer.transform = .identity
    }

    private func configureRingContainer() {
        ringContainer.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.isUserInteractionEnabled = false
        addSubview(ringContainer)

        ringBackgroundLayer.fillColor = UIColor.clear.cgColor
        ringBackgroundLayer.lineWidth = ringLineWidth
        ringBackgroundLayer.lineCap = .round

        ringProgressLayer.fillColor = UIColor.clear.cgColor
        ringProgressLayer.lineWidth = ringLineWidth
        ringProgressLayer.lineCap = .round
        ringProgressLayer.strokeStart = 0
        ringProgressLayer.strokeEnd = 0
        ringProgressLayer.transform = CATransform3DMakeRotation(-CGFloat.pi / 2, 0, 0, 1)

        ringContainer.layer.addSublayer(ringBackgroundLayer)
        ringContainer.layer.addSublayer(ringProgressLayer)
    }

    private func configureLabel() {
        hintLabel.font = .systemFont(ofSize: legacyPoppinsSize(12), weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            ringContainer.topAnchor.constraint(equalTo: topAnchor),
            ringContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),
            hintLabel.topAnchor.constraint(equalTo: ringContainer.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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
        let adjusted = ChatVanishSwipeMetrics.effectivePull(for: pullOffset)
        return Double(min(1, adjusted / 36))
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
