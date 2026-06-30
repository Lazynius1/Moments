import SwiftUI
import UIKit

// MARK: - Reply swipe metrics (estilo Instagram DM)

enum ChatReplySwipeMetrics {
    static let activationDistance: CGFloat = 84
    static let maxDrag: CGFloat = 108
    static let indicatorSize: CGFloat = 32

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

/// Contenedor: burbuja se desliza; el indicador queda fijo en el hueco (estilo Instagram).
struct ChatBubbleReplySwipeContainer<Content: View>: View {
    @Binding var dragOffset: CGFloat
    @Binding var hasTriggeredHaptic: Bool
    let isOutgoing: Bool
    let cornerRadius: CGFloat
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
            isOutgoing: isOutgoing,
            dragOffset: $dragOffset,
            hasTriggeredHaptic: $hasTriggeredHaptic,
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
    func chatReplySwipeGesture(
        isOutgoing: Bool,
        dragOffset: Binding<CGFloat>,
        hasTriggeredHaptic: Binding<Bool>,
        onReply: @escaping () -> Void
    ) -> some View {
        let gesture = DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)

                let isValidDirection = isOutgoing ? horizontal < 0 : horizontal > 0
                guard isValidDirection else {
                    if dragOffset.wrappedValue != 0 {
                        dragOffset.wrappedValue = 0
                    }
                    return
                }
                guard abs(horizontal) > vertical * 2.1, abs(horizontal) > 8 else { return }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragOffset.wrappedValue = ChatReplySwipeMetrics.signedDrag(
                        rawHorizontal: horizontal,
                        isOutgoing: isOutgoing
                    )
                }

                let progress = ChatReplySwipeMetrics.progress(for: dragOffset.wrappedValue)
                if progress >= 1, !hasTriggeredHaptic.wrappedValue {
                    HapticManager.shared.heavyImpact()
                    hasTriggeredHaptic.wrappedValue = true
                } else if progress < 0.9, hasTriggeredHaptic.wrappedValue {
                    hasTriggeredHaptic.wrappedValue = false
                }
            }
            .onEnded { _ in
                let didComplete = ChatReplySwipeMetrics.progress(for: dragOffset.wrappedValue) >= 1
                if didComplete {
                    HapticManager.shared.success()
                    onReply()
                }
                if UIAccessibility.isReduceMotionEnabled {
                    dragOffset.wrappedValue = 0
                    hasTriggeredHaptic.wrappedValue = false
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        dragOffset.wrappedValue = 0
                        hasTriggeredHaptic.wrappedValue = false
                    }
                }
            }

        return simultaneousGesture(gesture)
    }

    /// Zona vacía de la fila donde el swipe izquierdo revela el timestamp (no la burbuja).
    func chatTimestampRevealGutter(
        minLength: CGFloat = 50,
        timestampRevealOffset: Binding<CGFloat>
    ) -> some View {
        Color.clear
            .frame(minWidth: minLength, maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .chatTimestampRevealGesture(timestampRevealOffset: timestampRevealOffset)
    }

    /// Deslizar a la izquierda en huecos en blanco para revelar timestamps.
    func chatTimestampRevealGesture(timestampRevealOffset: Binding<CGFloat>) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)

                    guard abs(horizontal) > vertical * 1.4, abs(horizontal) > 16 else { return }
                    guard horizontal < 0 else { return }

                    let baseOffset = horizontal
                    let offset = baseOffset < -70 ? -70 + (baseOffset + 70) * 0.25 : baseOffset
                    timestampRevealOffset.wrappedValue = max(offset, -90)
                }
                .onEnded { _ in
                    if UIAccessibility.isReduceMotionEnabled {
                        timestampRevealOffset.wrappedValue = 0
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                            timestampRevealOffset.wrappedValue = 0
                        }
                    }
                }
        )
    }

    /// Long press tolerante a micro-movimientos (más fácil en clusters/media).
    func chatMessageLongPress(
        isPressing: Binding<Bool>? = nil,
        onLongPress: @escaping () -> Void
    ) -> some View {
        onLongPressGesture(minimumDuration: 0.42, maximumDistance: 18, pressing: { pressing in
            isPressing?.wrappedValue = pressing
        }) {
            HapticManager.shared.heavyImpact()
            onLongPress()
        }
    }
}
