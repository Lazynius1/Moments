import SwiftUI

/// Transición contextual del archivo: la miniatura gira y se convierte en la
/// actividad de esa historia. El contenido real nunca se rasteriza; solo la cara
/// frontal usa una captura durante la primera mitad del giro.
struct StoryActivityFlipTransition<Source: View>: View {
    let story: Story
    @ViewBuilder let source: () -> Source

    @State private var sourceFrame: CGRect = .zero
    @State private var sourceImage: UIImage?
    @State private var isPresented = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        source()
            .contentShape(.contextMenuPreview, Rectangle())
            .opacity(isPresented ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                sourceFrame = frame
            }
            .contextMenu {
                Button(action: presentActivity) {
                    Label("archivedStories.viewActivity", systemImage: "chart.bar.fill")
                }
            }
            .fullScreenCover(isPresented: $isPresented, onDismiss: {
                sourceImage = nil
            }) {
                StoryActivityFlipDestination(
                    story: story,
                    sourceFrame: sourceFrame,
                    sourceImage: sourceImage,
                    onFinish: dismissActivity
                )
            }
    }

    private func presentActivity() {
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }

        let renderer = ImageRenderer(
            content: source()
                .environment(\.colorScheme, colorScheme)
                .frame(width: sourceFrame.width, height: sourceFrame.height)
        )
        renderer.proposedSize = ProposedViewSize(sourceFrame.size)
        renderer.scale = displayScale
        sourceImage = renderer.uiImage

        // Deja que el menú contextual termine de retirarse antes de presentar el host.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPresented = true
            }
        }
    }

    private func dismissActivity() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = false
        }
    }
}

private struct StoryActivityFlipDestination: View {
    let story: Story
    let sourceFrame: CGRect
    let sourceImage: UIImage?
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
                    destinationContent(story: story, frame: destinationFrame)
                        .position(x: destinationFrame.midX, y: destinationFrame.midY)
                        .opacity(progress)
                } else {
                    flippingCard(
                        sourceFrame: localSourceFrame,
                        destinationFrame: destinationFrame
                    )
                }
            }
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
        .onAppear(perform: open)
    }

    private func flippingCard(sourceFrame: CGRect, destinationFrame: CGRect) -> some View {
        let frame = interpolatedFrame(from: sourceFrame, to: destinationFrame, progress: progress)
        let cornerRadius = 28 * progress

        return ZStack {
            if let sourceImage {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .modifier(StoryFlipFaceVisibility(progress: progress, showsBackFace: false))
            }

            destinationContent(story: story, frame: destinationFrame)
                .scaleEffect(
                    x: frame.width / max(destinationFrame.width, 1),
                    y: frame.height / max(destinationFrame.height, 1)
                )
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(x: -1)
                .modifier(StoryFlipFaceVisibility(progress: progress, showsBackFace: true))
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

    private func destinationContent(story: Story, frame: CGRect) -> some View {
        StoryStatsView(story: story, onClose: close)
            .frame(width: frame.width, height: frame.height)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func finalFrame(in proxy: GeometryProxy) -> CGRect {
        let horizontalInset: CGFloat = 10
        let topInset = max(proxy.safeAreaInsets.top + 8, 12)
        let bottomInset = max(proxy.safeAreaInsets.bottom + 8, 12)
        return CGRect(
            x: horizontalInset,
            y: topInset,
            width: max(proxy.size.width - horizontalInset * 2, 1),
            height: max(proxy.size.height - topInset - bottomInset, 1)
        )
    }

    private func open() {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.18)
            : .smooth(duration: 0.44, extraBounce: 0)
        withAnimation(animation) {
            progress = 1
        }
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        let animation: Animation = reduceMotion
            ? .easeIn(duration: 0.16)
            : .smooth(duration: 0.40, extraBounce: 0)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
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

private struct StoryFlipFaceVisibility: AnimatableModifier {
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
