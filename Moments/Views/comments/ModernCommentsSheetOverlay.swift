import SwiftUI
import UIKit

// MARK: - Overlay custom de comentarios (no .sheet del sistema)

/// Inset inferior del teclado dentro del panel (el sheet no se desplaza).
private struct CommentsKeyboardBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var commentsKeyboardBottomInset: CGFloat {
        get { self[CommentsKeyboardBottomInsetKey.self] }
        set { self[CommentsKeyboardBottomInsetKey.self] = newValue }
    }
}

struct ModernCommentsSheetOverlay: View {
    @Binding var moment: Moment?
    var firestoreService: FirestoreService
    /// Reels: solo medium (el vídeo escala con la altura cubierta).
    var locksToMedium: Bool = false
    /// Altura del panel visible desde abajo (para videoScale en Reels).
    var onCoveredHeightChange: ((CGFloat) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// Altura interactiva (1:1 con el dedo; al soltar hace snap).
    @State private var sheetHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var gestureStartHeight: CGFloat = 0
    @State private var isDragging = false
    @State private var didDismissKeyboardThisDrag = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var isPresented = false

    private var canvas: Color {
        AdaptiveColors(colorScheme: colorScheme).surfaceBackground
    }

    private var mediumHeight: CGFloat {
        // Feed/detalle: medium más alto (estilo IG ~60%). Reels se queda en 50% por el videoScale.
        max(containerHeight * (locksToMedium ? 0.5 : 0.62), 1)
    }
    private var largeHeight: CGFloat { max(containerHeight * 0.92, 1) }
    private var maxHeight: CGFloat { locksToMedium ? mediumHeight : largeHeight }

    private func composerKeyboardInset(safeBottom: CGFloat) -> CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        return max(0, keyboardHeight - safeBottom)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeBottom = proxy.safeAreaInsets.bottom
            let availableHeight = proxy.size.height
            let keyboardInset = composerKeyboardInset(safeBottom: safeBottom)
            let visibleHeight = isPresented ? sheetHeight : 0

            ZStack(alignment: .bottom) {
                // Dim a pantalla completa detrás del sheet (si solo va arriba, la línea del composer se ve rara).
                Color.black.opacity(colorScheme == .dark ? 0.45 : 0.28)
                    .ignoresSafeArea()
                    .opacity(isPresented || isDragging ? 1 : 0)
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    sheetHandle
                        .gesture(sheetDragGesture)

                    if let moment {
                        ModernCommentsView(moment: moment)
                            .environmentObject(firestoreService)
                            .environment(\.commentsKeyboardBottomInset, keyboardInset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                // Anclado abajo: al crecer la altura solo se estira hacia arriba (chicle IG), no se recentra.
                .frame(height: max(sheetHeight, 0), alignment: .bottom)
                .frame(maxWidth: .infinity)
                .background(canvas)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 22,
                        style: .continuous
                    )
                )
                .offset(y: isPresented ? 0 : max(sheetHeight, mediumHeight) + 40)
            }
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                syncContainerHeight(availableHeight, presentIfNeeded: true)
                onCoveredHeightChange?(visibleHeight)
            }
            .onChange(of: availableHeight) { _, newValue in
                syncContainerHeight(newValue, presentIfNeeded: false)
            }
            .onChange(of: visibleHeight) { _, newValue in
                onCoveredHeightChange?(newValue)
            }
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .onChange(of: moment?.id) { _, _ in
            resetToMedium()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            let animation = Self.keyboardAnimation(from: note)
            let targetHeight = (!locksToMedium && containerHeight > 1) ? largeHeight : sheetHeight
            // Una sola animación: estira altura + inset (sin reconstruir / recentrar).
            withAnimation(animation) {
                keyboardHeight = frame.height
                if abs(sheetHeight - targetHeight) > 1 {
                    sheetHeight = targetHeight
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            withAnimation(Self.keyboardAnimation(from: note)) {
                keyboardHeight = 0
            }
        }
        .onDisappear {
            onCoveredHeightChange?(0)
        }
        .transition(.opacity)
        .zIndex(80)
    }

    private var sheetHandle: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard containerHeight > 1 else { return }
                if !isDragging {
                    isDragging = true
                    gestureStartHeight = sheetHeight
                    didDismissKeyboardThisDrag = false
                }

                // IG: al bajar con teclado, primero se oculta el teclado.
                if keyboardHeight > 0, !didDismissKeyboardThisDrag, value.translation.height > 4 {
                    didDismissKeyboardThisDrag = true
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }

                let proposed = gestureStartHeight - value.translation.height
                let floor = mediumHeight * 0.32
                let ceiling = maxHeight + (locksToMedium ? 0 : 20)
                // Sin animación durante el drag: acompaña el dedo frame a frame.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    sheetHeight = min(max(proposed, floor), ceiling)
                }
            }
            .onEnded { value in
                isDragging = false
                didDismissKeyboardThisDrag = false
                guard containerHeight > 1 else { return }

                let velocity = value.velocity.height
                let projected = sheetHeight - velocity * 0.12

                if locksToMedium {
                    if projected < mediumHeight * 0.62 || velocity > 900 {
                        dismiss()
                    } else {
                        snap(to: mediumHeight)
                    }
                    return
                }

                if projected < mediumHeight * 0.55 || (velocity > 1100 && sheetHeight < mediumHeight * 0.85) {
                    dismiss()
                    return
                }

                let midPoint = (mediumHeight + largeHeight) / 2
                if velocity < -700 {
                    snap(to: largeHeight)
                } else if velocity > 700 {
                    if sheetHeight > midPoint {
                        snap(to: mediumHeight)
                    } else {
                        dismiss()
                    }
                } else if projected >= midPoint {
                    snap(to: largeHeight)
                } else {
                    snap(to: mediumHeight)
                }
            }
    }

    private func snap(to height: CGFloat) {
        withAnimation(.interpolatingSpring(duration: 0.34, bounce: 0.08)) {
            sheetHeight = height
        }
    }

    private func syncContainerHeight(_ height: CGFloat, presentIfNeeded: Bool) {
        guard height > 1 else { return }
        let previous = containerHeight
        containerHeight = height
        if sheetHeight < 1 {
            sheetHeight = mediumHeight
            if presentIfNeeded {
                withAnimation(.interpolatingSpring(duration: 0.38, bounce: 0.06)) {
                    isPresented = true
                }
            } else {
                isPresented = true
            }
        } else if !isDragging,
                  keyboardHeight == 0,
                  previous > 1,
                  abs(previous - height) > 80 {
            // Solo en rotación / split grande. No tocar altura con el teclado (evita “reconstruir”).
            let previousMedium = previous * (locksToMedium ? 0.5 : 0.62)
            let previousLarge = previous * 0.92
            let wasLarge = sheetHeight > (previousMedium + previousLarge) / 2
            sheetHeight = locksToMedium ? mediumHeight : (wasLarge ? largeHeight : mediumHeight)
        }
    }

    private func resetToMedium() {
        isDragging = false
        guard containerHeight > 1 else { return }
        sheetHeight = mediumHeight
    }

    private func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.interpolatingSpring(duration: 0.32, bounce: 0.02)) {
            isPresented = false
            sheetHeight = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            moment = nil
        }
    }

    /// Curva/duración del teclado del sistema para que sheet + inset no peleen.
    private static func keyboardAnimation(from note: Foundation.Notification) -> Animation {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveValue = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int)
            ?? UIView.AnimationCurve.easeInOut.rawValue
        let curve = UIView.AnimationCurve(rawValue: curveValue) ?? .easeInOut
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .linear:
            return .linear(duration: duration)
        case .easeInOut:
            return .easeInOut(duration: duration)
        @unknown default:
            // Curva “keyboard” (7) y otras: easeInOut suave, sin bounce.
            return .easeInOut(duration: duration)
        }
    }
}

extension View {
    /// Overlay custom de comentarios. En Reels: `locksToMedium: true` + `onCoveredHeightChange` para videoScale.
    func momentsCommentsOverlay(
        moment: Binding<Moment?>,
        firestoreService: FirestoreService,
        locksToMedium: Bool = false,
        onCoveredHeightChange: ((CGFloat) -> Void)? = nil
    ) -> some View {
        self
            .ignoresSafeArea(.keyboard)
            .momentsFloatingTabBarHidden(moment.wrappedValue != nil)
            .overlay {
                if moment.wrappedValue != nil {
                    ModernCommentsSheetOverlay(
                        moment: moment,
                        firestoreService: firestoreService,
                        locksToMedium: locksToMedium,
                        onCoveredHeightChange: onCoveredHeightChange
                    )
                }
            }
    }
}
