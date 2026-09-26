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

struct CommentsSheetGrabber: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.34 : 0.25))
            .frame(width: 36, height: 5)
        .frame(maxWidth: .infinity, minHeight: 25, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Altura interactiva (1:1 con el dedo; al soltar hace snap).
    @State private var sheetHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var gestureStartHeight: CGFloat = 0
    @State private var isDragging = false
    @State private var isSheetDragEligible = false
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
    private var keyboardRaisedHeight: CGFloat {
        max(mediumHeight, min(containerHeight * 0.72, largeHeight))
    }
    private var maxHeight: CGFloat { locksToMedium ? mediumHeight : largeHeight }

    private var presentationProgress: CGFloat {
        guard mediumHeight > 1 else { return 0 }
        return min(max(sheetHeight / mediumHeight, 0), 1)
    }

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
                    .opacity((isPresented || isDragging) ? presentationProgress : 0)
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
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
                        topLeadingRadius: 26,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 26,
                        style: .continuous
                    )
                )
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 26,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 26,
                        style: .continuous
                    )
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08),
                        lineWidth: 0.5
                    )
                    .mask(alignment: .top) {
                        Rectangle().frame(height: 80)
                    }
                    .allowsHitTesting(false)
                }
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18),
                    radius: 24,
                    x: 0,
                    y: -5
                )
                .offset(y: isPresented ? 0 : max(sheetHeight, mediumHeight) + 40)
                // Como en un sheet del sistema, el grabber y la cabecera forman una única zona de arrastre.
                // La lista queda fuera para que su scroll mantenga prioridad.
                .simultaneousGesture(sheetDragGesture)
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
            let targetHeight: CGFloat
            if containerHeight <= 1 {
                targetHeight = sheetHeight
            } else if locksToMedium {
                targetHeight = keyboardRaisedHeight
            } else {
                targetHeight = largeHeight
            }
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
                if locksToMedium, containerHeight > 1 {
                    sheetHeight = mediumHeight
                }
            }
        }
        .onDisappear {
            onCoveredHeightChange?(0)
        }
        .transition(.opacity)
        .zIndex(80)
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard containerHeight > 1 else { return }
                if !isDragging {
                    let panelTop = containerHeight - sheetHeight
                    // Grabber (25 pt) + cabecera (~70 pt). Los gestos que empiezan en la lista
                    // pertenecen al ScrollView y nunca mueven el panel.
                    isSheetDragEligible = value.startLocation.y <= panelTop + 104
                    guard isSheetDragEligible else { return }
                    isDragging = true
                    gestureStartHeight = sheetHeight
                    didDismissKeyboardThisDrag = false
                }
                guard isSheetDragEligible else { return }

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
                let ceiling = maxHeight
                // Sin animación durante el drag: acompaña el dedo frame a frame.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    sheetHeight = rubberBandedHeight(proposed, lowerBound: floor, upperBound: ceiling)
                }
            }
            .onEnded { value in
                guard isSheetDragEligible, isDragging else {
                    isSheetDragEligible = false
                    return
                }
                isDragging = false
                isSheetDragEligible = false
                didDismissKeyboardThisDrag = false
                guard containerHeight > 1 else { return }

                let velocity = value.velocity.height
                let projected = gestureStartHeight - value.predictedEndTranslation.height

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
        withAnimation(sheetAnimation(duration: 0.34, bounce: 0.08)) {
            sheetHeight = height
        }
    }

    /// Resistencia de goma parecida a UISheetPresentationController: el panel puede ceder,
    /// pero cada punto extra mueve cada vez menos la hoja.
    private func rubberBandedHeight(
        _ proposed: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        if proposed < lowerBound {
            return lowerBound - rubberBandDistance(lowerBound - proposed)
        }
        if proposed > upperBound {
            return upperBound + rubberBandDistance(proposed - upperBound)
        }
        return proposed
    }

    private func rubberBandDistance(_ distance: CGFloat) -> CGFloat {
        let dimension = max(containerHeight, 1)
        let coefficient: CGFloat = 0.34
        return (distance * coefficient * dimension) / (dimension + coefficient * distance)
    }

    private func sheetAnimation(duration: Double, bounce: Double) -> Animation {
        reduceMotion
            ? .easeOut(duration: min(duration, 0.2))
            : .interpolatingSpring(duration: duration, bounce: bounce)
    }

    private func syncContainerHeight(_ height: CGFloat, presentIfNeeded: Bool) {
        guard height > 1 else { return }
        let previous = containerHeight
        containerHeight = height
        if sheetHeight < 1 {
            sheetHeight = mediumHeight
            if presentIfNeeded {
                withAnimation(sheetAnimation(duration: 0.38, bounce: 0.06)) {
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
        withAnimation(sheetAnimation(duration: 0.32, bounce: 0.02)) {
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
            .overlay {
                if moment.wrappedValue != nil {
                    ModernCommentsSheetOverlay(
                        moment: moment,
                        firestoreService: firestoreService,
                        locksToMedium: locksToMedium,
                        onCoveredHeightChange: onCoveredHeightChange
                    )
                    // El hold pertenece al ciclo de vida del panel. Reels usa el panel
                    // medium y no tiene floating tab bar, así que allí no se solicita.
                    .momentsFloatingTabBarHidden(!locksToMedium)
                }
            }
    }
}
