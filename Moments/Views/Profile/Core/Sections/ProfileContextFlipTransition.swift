import SwiftUI

struct ProfileContextFlipConfiguration {
    let preferredHeight: CGFloat
    let sourceCornerRadius: CGFloat
    let destinationCornerRadius: CGFloat
    let usesExternalCloseHitTarget: Bool

    static let qr = ProfileContextFlipConfiguration(
        preferredHeight: 500,
        sourceCornerRadius: 48,
        destinationCornerRadius: 30,
        usesExternalCloseHitTarget: false
    )

    static let incognito = ProfileContextFlipConfiguration(
        preferredHeight: 620,
        sourceCornerRadius: ProfileChromeGlassMetrics.controlSize / 2,
        destinationCornerRadius: 30,
        usesExternalCloseHitTarget: true
    )

    static let settingsQR = ProfileContextFlipConfiguration(
        preferredHeight: 500,
        sourceCornerRadius: 18,
        destinationCornerRadius: 30,
        usesExternalCloseHitTarget: false
    )
}

/// Presenta una superficie contextual desde una vista que puede estar lejos del
/// control que la activa. Así, por ejemplo, el menú dispara el QR pero el giro
/// conserva como origen visual el avatar del perfil.
struct ProfileContextFlipTransition<Source: View, Destination: View>: View {
    @Binding var isRequested: Bool
    let configuration: ProfileContextFlipConfiguration
    @ViewBuilder let source: () -> Source
    @ViewBuilder let destination: (@escaping () -> Void) -> Destination

    @State private var sourceFrame: CGRect = .zero
    @State private var presentationSourceFrame: CGRect = .zero
    @State private var sourceImage: UIImage?
    @State private var isPresented = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        source()
            .opacity(isPresented ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                sourceFrame = frame
            }
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                present()
            }
            .fullScreenCover(isPresented: $isPresented, onDismiss: reset) {
                ProfileContextFlipDestination(
                    sourceFrame: presentationSourceFrame,
                    sourceImage: sourceImage,
                    configuration: configuration,
                    destination: destination,
                    onFinish: dismiss
                )
            }
    }

    private func present() {
        guard !isPresented, sourceFrame.width > 0, sourceFrame.height > 0 else {
            isRequested = false
            return
        }

        let renderer = ImageRenderer(
            content: source()
                .environment(\.colorScheme, colorScheme)
                .frame(width: sourceFrame.width, height: sourceFrame.height)
        )
        renderer.proposedSize = ProposedViewSize(sourceFrame.size)
        renderer.scale = displayScale
        sourceImage = renderer.uiImage
        presentationSourceFrame = resolvedPresentationFrame(for: sourceFrame)

        // Deja que el menú termine de retirarse sin retrasar la animación visual.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPresented = true
            }
        }
    }

    private func dismiss() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = false
        }
    }

    private func reset() {
        sourceImage = nil
        presentationSourceFrame = .zero
        isRequested = false
    }

    private func resolvedPresentationFrame(for frame: CGRect) -> CGRect {
        let visibleBounds = UIScreen.main.bounds.insetBy(dx: 0, dy: 8)
        guard frame.intersects(visibleBounds) else {
            // Cuando el avatar ya salió por arriba, el mismo retrato reaparece en
            // el centro del chrome fijado, sin forzar el scroll del perfil.
            let fallbackSize: CGFloat = 44
            return CGRect(
                x: visibleBounds.midX - (fallbackSize / 2),
                y: visibleBounds.minY + 12,
                width: fallbackSize,
                height: fallbackSize
            )
        }
        return frame
    }

}

private struct ProfileContextFlipDestination<Destination: View>: View {
    let sourceFrame: CGRect
    let sourceImage: UIImage?
    let configuration: ProfileContextFlipConfiguration
    @ViewBuilder let destination: (@escaping () -> Void) -> Destination
    let onFinish: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isClosing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let destinationFrame = finalFrame(in: proxy)
            let containerFrame = proxy.frame(in: .global)
            let localSourceFrame = sourceFrame.offsetBy(
                dx: -containerFrame.minX,
                dy: -containerFrame.minY
            )

            ZStack {
                Color.black
                    .opacity(0.42 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                if reduceMotion {
                    destinationContent(frame: destinationFrame)
                        .position(x: destinationFrame.midX, y: destinationFrame.midY)
                        .opacity(progress)
                } else {
                    flippingCard(from: localSourceFrame, to: destinationFrame)
                }

                if configuration.usesExternalCloseHitTarget, progress > 0.82 {
                    Button(action: close) {
                        Color.clear
                            .frame(width: 54, height: 54)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: destinationFrame.maxX - 35,
                        y: destinationFrame.minY + 31
                    )
                    .zIndex(20)
                    .accessibilityLabel(Text("common.close"))
                }
            }
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
        .onAppear(perform: open)
    }

    private func flippingCard(from sourceFrame: CGRect, to destinationFrame: CGRect) -> some View {
        let frame = interpolatedFrame(from: sourceFrame, to: destinationFrame, progress: progress)
        let cornerRadius = mix(
            configuration.sourceCornerRadius,
            configuration.destinationCornerRadius,
            progress
        )

        return ZStack {
            if let sourceImage {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .modifier(ProfileFlipFaceVisibility(progress: progress, showsBackFace: false))
            }

            destinationContent(frame: destinationFrame)
                .scaleEffect(
                    x: frame.width / max(destinationFrame.width, 1),
                    y: frame.height / max(destinationFrame.height, 1)
                )
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(x: -1)
                .modifier(ProfileFlipFaceVisibility(progress: progress, showsBackFace: true))
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.28 * progress), radius: 26 * progress, y: 12 * progress)
        .rotation3DEffect(
            .degrees(180 * progress),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .position(x: frame.midX, y: frame.midY)
    }

    private func destinationContent(frame: CGRect) -> some View {
        destination(close)
            .frame(width: frame.width, height: frame.height)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .clipShape(RoundedRectangle(cornerRadius: configuration.destinationCornerRadius, style: .continuous))
    }

    private func finalFrame(in proxy: GeometryProxy) -> CGRect {
        let horizontalInset: CGFloat = 10
        let topInset = max(proxy.safeAreaInsets.top + 8, 12)
        let bottomInset = max(proxy.safeAreaInsets.bottom + 8, 12)
        let availableHeight = max(proxy.size.height - topInset - bottomInset, 1)
        let height = min(configuration.preferredHeight, availableHeight)

        return CGRect(
            x: horizontalInset,
            y: topInset + ((availableHeight - height) / 2),
            width: max(proxy.size.width - horizontalInset * 2, 1),
            height: height
        )
    }

    private func open() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.44, extraBounce: 0)) {
            progress = 1
        }
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(
            reduceMotion ? .easeIn(duration: 0.16) : .smooth(duration: 0.40, extraBounce: 0),
            completionCriteria: .logicallyComplete
        ) {
            progress = 0
        } completion: {
            onFinish()
        }
    }

    private func interpolatedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: mix(start.minX, end.minX, progress),
            y: mix(start.minY, end.minY, progress),
            width: mix(start.width, end.width, progress),
            height: mix(start.height, end.height, progress)
        )
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

private struct ProfileFlipFaceVisibility: AnimatableModifier {
    var progress: CGFloat
    let showsBackFace: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(showsBackFace ? (progress >= 0.5 ? 1 : 0) : (progress < 0.5 ? 1 : 0))
    }
}
