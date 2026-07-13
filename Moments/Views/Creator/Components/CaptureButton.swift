import SwiftUI

struct CaptureButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isRecording: Bool
    var lensIconURL: URL? = nil
    let onTap: () -> Void
    let onLongPressStart: () -> Void
    let onLongPressEnd: () -> Void

    @State private var isPressed = false
    @State private var longPressTimer: Timer?

    var body: some View {
        ZStack {
            outerRing

            innerCircle
                .frame(width: 68, height: 68)
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .scaleEffect(isPressed ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
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

    @ViewBuilder
    private var innerCircle: some View {
        if let lensIconURL {
            AsyncImage(url: lensIconURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(innerFillColor)
            }
            .clipShape(Circle())
        } else {
            Circle().fill(innerFillColor)
        }
    }

    private var innerFillColor: Color {
        .white
    }

    private var outerRing: some View {
        Circle()
            .frame(width: 88, height: 88)
            .momentsChromeGlass(
                in: Circle(),
                interactive: true,
                tintOpacity: isRecording ? 0.55 : MomentsChromeGlass.defaultTintOpacity,
                tint: isRecording ? .red : nil
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.2), value: isRecording)
    }
}
