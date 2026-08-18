import SwiftUI
import UIKit

private let feedHighlightGradient = LinearGradient(
    colors: [
        Color(hex: "00A896").opacity(0.8),
        Color.purple.opacity(0.8)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct FloatingGlassFeedToggle: View {
    @Binding var selectedFeedType: FeedType
    @State private var isShowingBrand = true
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    FeedToggleContent(
                        selectedFeedType: $selectedFeedType,
                        isShowingBrand: isShowingBrand
                    )
                }
            } else {
                FeedToggleContent(
                    selectedFeedType: $selectedFeedType,
                    isShowingBrand: isShowingBrand
                )
            }
        }
        .padding(4) // ✅ RESTORED to 4 (Original size)
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .glassEffect(.regular, in: Capsule()) // 💧 'waterDrop' not available, using .regular
            } else {
                ZStack {
                    // Enhanced glass morphism effect (Water Drop) - Fallback
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    // Enhanced border gradient to stimulate light reflection
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
        }
        .task {
            if MotionPolicy.reduceMotion {
                isShowingBrand = false
                return
            }

            do {
                try await Task.sleep(for: .seconds(2.75))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(MotionPolicy.Spring.header) {
                isShowingBrand = false
            }
        }
    }
}

private struct FeedToggleContent: View {
    @Binding var selectedFeedType: FeedType
    let isShowingBrand: Bool

    @Namespace private var animationNamespace

    var body: some View {
        ZStack {
            if isShowingBrand {
                FeedBrandWordmark(namespace: animationNamespace)
                    .transition(.feedBrandDeparture)
            } else {
                NativeFeedSegments(
                    selectedFeedType: $selectedFeedType,
                    namespace: animationNamespace
                )
                .transition(.feedOptionsArrival)
            }
        }
    }
}

private struct FeedBrandWordmark: View {
    let namespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("FeedWordmark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 96, height: 20)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(feedHighlightGradient)
                    .opacity(0.22)
                    .matchedGeometryEffect(id: "background", in: namespace)
            }
            .accessibilityHidden(true)
    }
}

private struct FeedMorphModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat
    let scale: CGFloat
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale)
            .offset(y: verticalOffset)
    }
}

private extension AnyTransition {
    static let feedBrandDeparture = AnyTransition.modifier(
        active: FeedMorphModifier(opacity: 0, blurRadius: 8, scale: 0.9, verticalOffset: -5),
        identity: FeedMorphModifier(opacity: 1, blurRadius: 0, scale: 1, verticalOffset: 0)
    )

    static let feedOptionsArrival = AnyTransition.modifier(
        active: FeedMorphModifier(opacity: 0, blurRadius: 7, scale: 0.94, verticalOffset: 6),
        identity: FeedMorphModifier(opacity: 1, blurRadius: 0, scale: 1, verticalOffset: 0)
    )
}

private struct NativeFeedSegments: View {
    @Binding var selectedFeedType: FeedType
    let namespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
            ZStack(alignment: selectedFeedType == .following ? .leading : .trailing) {
                Capsule()
                    .fill(Color.clear)
                    .frame(width: 84, height: 32)
                    .matchedGeometryEffect(id: "background", in: namespace)
                    .allowsHitTesting(false)

                FeedNativeSegmentedControl(
                    selectedFeedType: $selectedFeedType,
                    colorScheme: colorScheme
                )
                .frame(width: 168, height: 32)
            }
            } else {
                HStack(spacing: 4) {
                    ForEach(FeedType.allCases, id: \.self) { feedType in
                        FeedSegmentButton(
                            feedType: feedType,
                            isSelected: selectedFeedType == feedType,
                            colorScheme: colorScheme,
                            namespace: namespace
                        ) {
                            guard selectedFeedType != feedType else { return }
                            withAnimation(MotionPolicy.reduceMotion ? nil : MotionPolicy.Spring.toggle) {
                                selectedFeedType = feedType
                            }
                            HapticManager.shared.selection()
                        }
                    }
                }
                .frame(width: 168, height: 32)
            }
        }
        .frame(width: 168, height: 32)
        .animation(MotionPolicy.reduceMotion ? nil : MotionPolicy.Spring.toggle, value: selectedFeedType)
    }
}

private struct FeedSegmentButton: View {
    let feedType: FeedType
    let isSelected: Bool
    let colorScheme: ColorScheme
    let namespace: Namespace.ID
    let action: () -> Void

    private var labelColor: Color {
        colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.78)
    }

    private var selectedLabelColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var selectedBackground: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(feedHighlightGradient.opacity(0.68))
        }
        return AnyShapeStyle(Color.black.opacity(0.12))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: feedType.icon)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 11, weight: .semibold))
                Text(feedType.title)
                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? selectedLabelColor : labelColor)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 9)
            .background {
                if isSelected {
                    Capsule()
                        .fill(selectedBackground)
                        .matchedGeometryEffect(id: "background", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct FeedNativeSegmentedControl: UIViewRepresentable {
    @Binding var selectedFeedType: FeedType
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> MomentsFloatingSegmentedControl {
        let control = MomentsFloatingSegmentedControl(items: titles)
        control.selectedSegmentIndex = selectedIndex
        control.apportionsSegmentWidthsByContent = false
        control.backgroundColor = .clear
        control.selectedSegmentTintColor = makeStaticAuroraTint()
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        applyAppearance(to: control)

        // Igual que la tabbar: elimina las placas internas y conserva la gota.
        DispatchQueue.main.async {
            for subview in control.subviews {
                if subview is UIImageView && subview != control.subviews.last {
                    subview.alpha = 0
                }
            }
        }

        return control
    }

    func updateUIView(_ control: MomentsFloatingSegmentedControl, context: Context) {
        context.coordinator.parent = self

        for (index, title) in titles.enumerated() where control.titleForSegment(at: index) != title {
            control.setTitle(title, forSegmentAt: index)
        }

        if control.selectedSegmentIndex != selectedIndex {
            control.selectedSegmentIndex = selectedIndex
        }

        applyAppearance(to: control)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var titles: [String] {
        FeedType.allCases.map(\.title)
    }

    private var selectedIndex: Int {
        FeedType.allCases.firstIndex(of: selectedFeedType) ?? 0
    }

    private func applyAppearance(to control: UISegmentedControl) {
        let normalColor = colorScheme == .dark
            ? UIColor.white.withAlphaComponent(0.7)
            : UIColor.black.withAlphaComponent(0.8)
        let font = UIFont.systemFont(ofSize: legacyPoppinsSize(12), weight: .semibold)

        control.setTitleTextAttributes(
            [.foregroundColor: normalColor, .font: font],
            for: .normal
        )
        control.setTitleTextAttributes(
            [.foregroundColor: UIColor.white, .font: font],
            for: .selected
        )
    }

    /// Fotograma fijo de la paleta del `AuroraMeshLayer` del login.
    /// `UISegmentedControl` recibe el resultado como tint para conservar
    /// su thumb nativo deformable sin mantener un TimelineView animándose.
    private func makeStaticAuroraTint() -> UIColor {
        let size = CGSize(width: 84, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1).cgColor,
                UIColor(red: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1).cgColor,
                UIColor(red: 255 / 255, green: 55 / 255, blue: 95 / 255, alpha: 1).cgColor,
                UIColor(red: 2 / 255, green: 195 / 255, blue: 154 / 255, alpha: 1).cgColor
            ] as CFArray

            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors,
                locations: [0, 0.34, 0.67, 1]
            ) else {
                return
            }

            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }

        // Funciona como tint del material del thumb, no como una placa opaca.
        // El alpha deja pasar el glass nativo y suaviza el aurora en un área pequeña.
        return UIColor(patternImage: image).withAlphaComponent(0.58)
    }

    final class Coordinator: NSObject {
        var parent: FeedNativeSegmentedControl

        init(parent: FeedNativeSegmentedControl) {
            self.parent = parent
        }

        @objc
        func valueChanged(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard FeedType.allCases.indices.contains(index) else { return }

            let feedType = FeedType.allCases[index]
            guard parent.selectedFeedType != feedType else { return }
            parent.selectedFeedType = feedType
            HapticManager.shared.selection()
        }
    }
}

// Preview to verify the design
struct FloatingGlassFeedToggle_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FloatingGlassFeedToggle(selectedFeedType: .constant(.forYou))
        }
    }
}
