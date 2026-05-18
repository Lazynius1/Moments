import SwiftUI

struct CaptureButton: View {
    @Binding var isRecording: Bool
    let onTap: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    @State private var isPressed = false
    @State private var longPressTimer: Timer?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 88, height: 88)
                .background {
                    Color.clear
                        .liquidGlass(in: Circle(), interactive: true)
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                )

            Circle()
                .fill(isRecording ? Color.red : Color.white)
                .frame(width: isPressed ? 58 : 68, height: isPressed ? 58 : 68)
                .scaleEffect(isRecording ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .scaleEffect(isPressed ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            if isPressed {
                                onLongPressStart()
                            }
                        }
                    }
                }
                .onEnded { _ in
                    isPressed = false

                    if let timer = longPressTimer {
                        timer.invalidate()
                        longPressTimer = nil

                        if isRecording {
                            onLongPressEnd()
                        } else {
                            onTap()
                        }
                    } else if isRecording {
                        onLongPressEnd()
                    }
                }
        )
    }
}
