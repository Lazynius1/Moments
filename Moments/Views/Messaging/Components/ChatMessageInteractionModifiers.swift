import SwiftUI

// MARK: - Gestos de chat (scroll-friendly)

extension View {
    /// Deslizar a la derecha para responder sin bloquear el scroll vertical.
    func chatReplySwipeGesture(
        dragOffset: Binding<CGFloat>,
        hasTriggeredHaptic: Binding<Bool>,
        onReply: @escaping () -> Void
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 32, coordinateSpace: .local)
                .onChanged { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    guard horizontal > 0, horizontal > vertical * 1.4, horizontal > 22 else { return }

                    dragOffset.wrappedValue = horizontal

                    if horizontal > 60, !hasTriggeredHaptic.wrappedValue {
                        HapticManager.shared.mediumImpact()
                        hasTriggeredHaptic.wrappedValue = true
                    } else if horizontal < 60, hasTriggeredHaptic.wrappedValue {
                        hasTriggeredHaptic.wrappedValue = false
                    }
                }
                .onEnded { _ in
                    if dragOffset.wrappedValue > 70 {
                        onReply()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset.wrappedValue = 0
                        hasTriggeredHaptic.wrappedValue = false
                    }
                }
        )
    }

    /// Long press tolerante a micro-movimientos (más fácil en clusters/media).
    func chatMessageLongPress(onLongPress: @escaping () -> Void) -> some View {
        onLongPressGesture(minimumDuration: 0.42, maximumDistance: 18) {
            HapticManager.shared.heavyImpact()
            onLongPress()
        }
    }
}
