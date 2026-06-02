import SwiftUI
import UIKit

// MARK: - Zonas donde el Deck Pass no debe “robar” el gesto (stickers interactivos)

struct StoryInteractionExclusionZone: Equatable, Identifiable {
    let id: String
    let rect: CGRect
}

struct StoryInteractionExclusionKey: PreferenceKey {
    static var defaultValue: [StoryInteractionExclusionZone] = []

    static func reduce(value: inout [StoryInteractionExclusionZone], nextValue: () -> [StoryInteractionExclusionZone]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Reporta un rectángulo en el espacio del deck para bloquear el pan entre usuarios.
    func storyDeckInteractionExclusion(id: String, in space: CoordinateSpace) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: StoryInteractionExclusionKey.self,
                    value: [
                        StoryInteractionExclusionZone(
                            id: id,
                            rect: geometry.frame(in: space)
                        )
                    ]
                )
            }
        )
    }
}

func mergedStoryInteractionExclusionZones(
    from zones: [StoryInteractionExclusionZone]
) -> [CGRect] {
    zones.map(\.rect)
}

func isValidStoryInteractionExclusionRect(_ rect: CGRect) -> Bool {
    guard rect.width > 4, rect.height > 4 else { return false }
    let screen = UIScreen.main.bounds
    // Descartar frames erróneos de layout (p. ej. GeometryReader a pantalla completa).
    if rect.width >= screen.width * 0.9, rect.height >= screen.height * 0.9 {
        return false
    }
    return true
}

func touchIsInsideStoryInteractionExclusion(
    _ point: CGPoint,
    zones: [CGRect],
    padding: CGFloat = 32
) -> Bool {
    zones.contains { rect in
        guard isValidStoryInteractionExclusionRect(rect) else { return false }
        return rect.insetBy(dx: -padding, dy: -padding).contains(point)
    }
}

// MARK: - Pan del emoji slider (UIKit, prioridad frente al deck)

struct EmojiSliderVotePanOverlay: UIViewRepresentable {
    let trackFrame: CGRect
    let trackLeading: CGFloat
    let trackWidth: CGFloat
    let isEnabled: Bool
    let currentValue: Double
    let onBegan: () -> Void
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> EmojiSliderVotePanView {
        let view = EmojiSliderVotePanView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: EmojiSliderVotePanView, context: Context) {
        context.coordinator.parent = self
        uiView.isUserInteractionEnabled = isEnabled
        uiView.setNeedsLayout()
    }

    final class Coordinator: NSObject {
        var parent: EmojiSliderVotePanOverlay?
    }

    final class EmojiSliderVotePanView: UIView {
        weak var coordinator: Coordinator?
        private var panRecognizer: UIPanGestureRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = false
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false
            addGestureRecognizer(pan)
            panRecognizer = pan
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let parent = coordinator?.parent else { return false }
            let hitBox = parent.trackFrame.insetBy(dx: -44, dy: -36)
            return hitBox.contains(point)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let parent = coordinator?.parent, parent.isEnabled else { return }

            switch recognizer.state {
            case .began:
                parent.onBegan()
                fallthrough
            case .changed:
                let x = recognizer.location(in: self).x
                parent.onChanged(parent.normalizedValue(for: x))
            case .ended:
                parent.onEnded(parent.normalizedValue(for: recognizer.location(in: self).x))
            case .cancelled, .failed:
                parent.onCancelled()
            default:
                break
            }
        }
    }

    fileprivate func normalizedValue(for locationX: CGFloat) -> Double {
        let minX = trackLeading
        let maxX = trackLeading + trackWidth
        let clampedX = min(max(locationX, minX), maxX)
        return Double((clampedX - minX) / max(trackWidth, 1))
    }
}
