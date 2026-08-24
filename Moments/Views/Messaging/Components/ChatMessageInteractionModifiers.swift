import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

final class ChatTimestampRevealState: ObservableObject {
    @Published var offset: CGFloat = 0
}

enum ChatHorizontalPanDirection {
    case left
    case right
    case both

    func accepts(_ translationX: CGFloat) -> Bool {
        switch self {
        case .left:
            return translationX < 0
        case .right:
            return translationX > 0
        case .both:
            return true
        }
    }
}

/// Reconocedor horizontal: permanece pendiente durante los
/// primeros puntos y falla en cuanto la intención es vertical. De este modo el pan
/// del UICollectionView recibe el scroll sin esperar a que un DragGesture de SwiftUI
/// termine de decidir que no iba a hacer nada.
final class ChatHorizontalPanGestureRecognizer: UIPanGestureRecognizer {
    var allowedDirection: ChatHorizontalPanDirection = .both
    private var firstLocation: CGPoint = .zero
    private var hasValidatedHorizontalIntent = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func reset() {
        super.reset()
        firstLocation = .zero
        hasValidatedHorizontalIntent = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first {
            firstLocation = touch.location(in: view)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else {
            state = .failed
            return
        }

        let location = touch.location(in: view)
        let translation = CGPoint(
            x: location.x - firstLocation.x,
            y: location.y - firstLocation.y
        )
        let horizontal = abs(translation.x)
        let vertical = abs(translation.y)

        if !hasValidatedHorizontalIntent {
            if vertical > 2, vertical > horizontal {
                state = .failed
                return
            }
            if horizontal > 2, !allowedDirection.accepts(translation.x) {
                state = .failed
                return
            }
            if horizontal > 2, horizontal > vertical * 1.2 {
                hasValidatedHorizontalIntent = true
            }
        }

        if hasValidatedHorizontalIntent {
            super.touchesMoved(touches, with: event)
        }
    }
}

struct ChatHorizontalPanValue {
    let translation: CGPoint
    let location: CGPoint
}

struct ChatHorizontalPanGesture: UIGestureRecognizerRepresentable {
    typealias UIGestureRecognizerType = ChatHorizontalPanGestureRecognizer

    let direction: ChatHorizontalPanDirection
    let onChanged: (ChatHorizontalPanValue) -> Void
    let onEnded: (ChatHorizontalPanValue, Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> ChatHorizontalPanGestureRecognizer {
        let recognizer = ChatHorizontalPanGestureRecognizer(target: nil, action: nil)
        recognizer.allowedDirection = direction
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: ChatHorizontalPanGestureRecognizer,
        context: Context
    ) {
        recognizer.allowedDirection = direction
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: ChatHorizontalPanGestureRecognizer,
        context: Context
    ) {
        let value = ChatHorizontalPanValue(
            translation: context.converter.localTranslation ?? .zero,
            location: context.converter.localLocation
        )
        switch recognizer.state {
        case .began, .changed:
            onChanged(value)
        case .ended:
            onEnded(value, true)
        case .cancelled:
            onEnded(value, false)
        default:
            break
        }
    }
}

// MARK: - Reply swipe metrics

enum ChatReplySwipeMetrics {
    static let activationDistance: CGFloat = 84
    static let maxDrag: CGFloat = 108
    static let indicatorSize: CGFloat = 32
    static let hapticStepPoints: CGFloat = 18
    static let hapticStepCount = 4
    static func rubberBandMagnitude(_ raw: CGFloat) -> CGFloat {
        guard raw > 0 else { return 0 }
        if raw <= maxDrag { return raw }
        return maxDrag + (raw - maxDrag) * 0.1
    }

    static func signedDrag(rawHorizontal: CGFloat, isOutgoing: Bool) -> CGFloat {
        let magnitude = rubberBandMagnitude(abs(rawHorizontal))
        guard magnitude > 0 else { return 0 }
        return isOutgoing ? -magnitude : magnitude
    }

    static func progress(for dragOffset: CGFloat) -> CGFloat {
        min(max(abs(dragOffset) / activationDistance, 0), 1)
    }
}

struct ChatReplySwipeIndicator: View {
    let progress: CGFloat
    var isOutgoing: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var circleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1)
    }

    private var progressColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.45)
    }

    private var arrowColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55 + progress * 0.4) : Color.black.opacity(0.35 + progress * 0.45)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(circleFill)

            Circle()
                .stroke(trackColor, lineWidth: 2)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(arrowColor)
                .scaleEffect(x: isOutgoing ? -1 : 1, y: 1)
        }
        .frame(width: ChatReplySwipeMetrics.indicatorSize, height: ChatReplySwipeMetrics.indicatorSize)
        .scaleEffect(0.42 + progress * 0.58)
        .opacity(0.15 + progress * 0.85)
    }
}

/// Contenedor: burbuja se desliza; el indicador queda fijo en el hueco.
struct ChatBubbleReplySwipeContainer<Content: View>: View {
    @Binding var dragOffset: CGFloat
    @Binding var hapticStep: Int
    let isOutgoing: Bool
    let cornerRadius: CGFloat
    var isEnabled: Bool = true
    let onReply: () -> Void
    @ViewBuilder let content: () -> Content

    private var dragMagnitude: CGFloat {
        abs(dragOffset)
    }

    var body: some View {
        ZStack(alignment: isOutgoing ? .trailing : .leading) {
            if dragMagnitude > 2 {
                ChatReplySwipeIndicator(
                    progress: ChatReplySwipeMetrics.progress(for: dragOffset),
                    isOutgoing: isOutgoing
                )
                .allowsHitTesting(false)
            }

            content()
                .offset(x: dragOffset)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .chatReplySwipeGesture(
            enabled: isEnabled,
            isOutgoing: isOutgoing,
            dragOffset: $dragOffset,
            hapticStep: $hapticStep,
            onReply: onReply
        )
        .accessibilityAction(named: Text("chat.action.reply")) {
            onReply()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Gestos de chat (scroll-friendly)

extension View {
    /// Deslizar sobre la burbuja para responder: entrantes → derecha, salientes → izquierda.
    @ViewBuilder
    func chatReplySwipeGesture(
        enabled: Bool = true,
        isOutgoing: Bool,
        dragOffset: Binding<CGFloat>,
        hapticStep: Binding<Int>,
        onReply: @escaping () -> Void
    ) -> some View {
        if enabled {
            let gesture = ChatHorizontalPanGesture(
                direction: isOutgoing ? .left : .right,
                onChanged: { value in
                    let horizontal = value.translation.x
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragOffset.wrappedValue = ChatReplySwipeMetrics.signedDrag(
                            rawHorizontal: horizontal,
                            isOutgoing: isOutgoing
                        )
                    }

                    let magnitude = abs(dragOffset.wrappedValue)
                    let progress = ChatReplySwipeMetrics.progress(for: dragOffset.wrappedValue)
                    let nextStep: Int
                    if progress >= 1 {
                        nextStep = ChatReplySwipeMetrics.hapticStepCount + 1
                    } else {
                        nextStep = min(
                            Int(magnitude / ChatReplySwipeMetrics.hapticStepPoints),
                            ChatReplySwipeMetrics.hapticStepCount
                        )
                    }
                    if nextStep != hapticStep.wrappedValue {
                        if nextStep == ChatReplySwipeMetrics.hapticStepCount + 1 {
                            HapticManager.shared.replySwipeThresholdReached()
                        } else if nextStep > 0 || hapticStep.wrappedValue > 0 {
                            HapticManager.shared.replySwipeStep()
                        }
                        hapticStep.wrappedValue = nextStep
                    }
                },
                onEnded: { _, completed in
                    let didComplete = completed
                        && ChatReplySwipeMetrics.progress(for: dragOffset.wrappedValue) >= 1
                    if didComplete {
                        onReply()
                    }
                    if UIAccessibility.isReduceMotionEnabled {
                        dragOffset.wrappedValue = 0
                        hapticStep.wrappedValue = 0
                    } else {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                            dragOffset.wrappedValue = 0
                            hapticStep.wrappedValue = 0
                        }
                    }
                }
            )

            self.gesture(gesture)
        } else {
            self
        }
    }

    /// El reveal global sólo nace en el fondo de la fila. Sobre la burbuja manda reply,
    /// cuya dirección depende de si el mensaje es enviado o recibido.
    @ViewBuilder
    func chatTimestampRevealGutter(
        minLength: CGFloat = 50,
        state: ChatTimestampRevealState,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            Color.clear
                .frame(minWidth: minLength, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .chatTimestampRevealGesture(state: state)
        } else {
            Color.clear
                .frame(minWidth: minLength, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }

    /// Deslizar a la izquierda en cualquier punto de la fila para revelar timestamps.
    func chatTimestampRevealGesture(
        enabled: Bool = true,
        state: ChatTimestampRevealState
    ) -> some View {
        gesture(
            ChatHorizontalPanGesture(
                direction: .left,
                onChanged: { value in
                    guard enabled else { return }
                    let horizontal = value.translation.x

                    let baseOffset = horizontal
                    let offset = baseOffset < -70 ? -70 + (baseOffset + 70) * 0.25 : baseOffset
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        state.offset = max(offset, -90)
                    }
                },
                onEnded: { _, _ in
                    guard enabled else { return }
                    if UIAccessibility.isReduceMotionEnabled {
                        state.offset = 0
                    } else {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.timestampReturn) {
                            state.offset = 0
                        }
                    }
                }
            )
        )
    }

    /// Long press 0.32s; si suelta antes, es tap. El tap de ese mismo pulso no dispara si ya hubo menú.
    func chatMessagePressClassifier(
        isPressing: Binding<Bool>? = nil,
        onTap: (() -> Void)? = nil,
        onLongPress: @escaping () -> Void
    ) -> some View {
        modifier(
            ChatMessagePressClassifierModifier(
                isPressing: isPressing,
                onTap: onTap,
                onLongPress: onLongPress
            )
        )
    }

    /// Long press tolerante a micro-movimientos (más fácil en clusters/media).
    func chatMessageLongPress(
        isPressing: Binding<Bool>? = nil,
        onLongPress: @escaping () -> Void
    ) -> some View {
        chatMessagePressClassifier(isPressing: isPressing, onTap: nil, onLongPress: onLongPress)
    }
}

private struct ChatMessagePressClassifierModifier: ViewModifier {
    var isPressing: Binding<Bool>?
    let onTap: (() -> Void)?
    let onLongPress: () -> Void
    @State private var suppressNextTap = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.32, maximumDistance: 18, perform: {
                suppressNextTap = true
                HapticManager.shared.heavyImpact()
                onLongPress()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    suppressNextTap = false
                }
            }, onPressingChanged: { pressing in
                isPressing?.wrappedValue = pressing
            })
            .modifier(ChatMessagePressTapModifier(
                isEnabled: onTap != nil,
                suppressNextTap: $suppressNextTap,
                onTap: onTap
            ))
    }
}

/// El tap solo se instala si hay `onTap`; si no, los enlaces/spoilers del texto siguen recibiendo el gesto.
private struct ChatMessagePressTapModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var suppressNextTap: Bool
    let onTap: (() -> Void)?

    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture {
                guard !suppressNextTap else {
                    suppressNextTap = false
                    return
                }
                onTap?()
            }
        } else {
            content
        }
    }
}

/// Apertura del cuerpo del mensaje (tap corto o tap sobre la burbuja elevada).
enum ChatMessageBodyOpen {
    static func viewOnceReplayAvailable(message: EnhancedMessage, currentUserId: String) -> Bool {
        message.allowReplay == true
            && message.replayAvailableInCurrentChatSession
            && !message.replayConsumedInCurrentChatSession
            && !message.hasBeenReplayedBy(userId: currentUserId)
    }

    static func viewOnceEffectiveViewed(message: EnhancedMessage) -> Bool {
        message.isViewed || message.replayAvailableInCurrentChatSession
    }

    static func isOpenable(_ message: EnhancedMessage, isCurrentUser: Bool, currentUserId: String) -> Bool {
        guard !message.isDeleted else { return false }
        switch message.type {
        case .image, .video, .location, .sharedMoment, .sharedStory, .ephemeral:
            return true
        case .viewOnceImage, .viewOnceVideo:
            guard !isCurrentUser else { return false }
            if viewOnceEffectiveViewed(message: message) {
                return viewOnceReplayAvailable(message: message, currentUserId: currentUserId)
            }
            return true
        default:
            return false
        }
    }

    @MainActor
    static func open(
        _ message: EnhancedMessage,
        isCurrentUser: Bool,
        currentUserId: String,
        cluster: [EnhancedMessage]? = nil,
        onOpenMedia: (EnhancedMessage) -> Void,
        onOpenCluster: (([EnhancedMessage]) -> Void)? = nil,
        onMomentNavigation: ((EnhancedMessage) -> Void)?,
        onStoryNavigation: ((EnhancedMessage) -> Void)?,
        onViewOnceOpen: ((EnhancedMessage, Bool) -> Void)?,
        onOpenLocation: ((EnhancedMessage) -> Void)?,
        onHydrateMedia: ((EnhancedMessage) -> Void)?,
        onMessageViewed: ((String) -> Void)?,
        persistsViewState: Bool = true
    ) {
        if let cluster, cluster.count > 1 {
            onOpenCluster?(cluster)
            return
        }
        guard !message.isDeleted else { return }
        switch message.type {
        case .image, .video:
            onOpenMedia(message)
        case .location:
            onOpenLocation?(message)
        case .sharedMoment:
            onMomentNavigation?(message)
        case .sharedStory:
            onStoryNavigation?(message)
        case .viewOnceImage, .viewOnceVideo:
            guard !isCurrentUser else { return }
            let viewed = viewOnceEffectiveViewed(message: message)
            if viewed {
                guard viewOnceReplayAvailable(message: message, currentUserId: currentUserId) else { return }
                onViewOnceOpen?(message, true)
            } else {
                onViewOnceOpen?(message, false)
            }
        case .ephemeral:
            if !message.isViewed {
                if persistsViewState {
                    onHydrateMedia?(message)
                    onMessageViewed?(message.id)
                    ChatService().markEphemeralAsViewed(
                        conversationId: message.conversationId,
                        messageId: message.id
                    ) { _ in }
                } else {
                    onOpenMedia(message)
                }
            } else {
                onOpenMedia(message)
            }
        default:
            break
        }
    }
}
