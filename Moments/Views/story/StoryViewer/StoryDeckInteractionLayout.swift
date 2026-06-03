import SwiftUI
import UIKit

// MARK: - Zonas donde el Deck Pass no debe “robar” el gesto (stickers interactivos)

struct StoryInteractionExclusionZone: Equatable, Identifiable {
    let id: String
    let rect: CGRect
    let intents: Set<StoryGestureIntent>
    let suppressionScope: StoryGestureSuppressionScope
}

struct StoryInteractionExclusionKey: PreferenceKey {
    static var defaultValue: [StoryInteractionExclusionZone] = []

    static func reduce(value: inout [StoryInteractionExclusionZone], nextValue: () -> [StoryInteractionExclusionZone]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Reporta un rectángulo en el espacio del deck para bloquear el pan entre usuarios.
    func storyDeckInteractionExclusion(
        id: String,
        in space: CoordinateSpace,
        intents: Set<StoryGestureIntent> = [.deckSwipe],
        suppressionScope: StoryGestureSuppressionScope = .suppressDeck,
        horizontalInsetFraction: CGFloat = 0,
        verticalInset: CGFloat = 0
    ) -> some View {
        background(
            GeometryReader { geometry in
                let frame = geometry.frame(in: space)
                let horizontalInset = frame.width * horizontalInsetFraction
                let adjustedFrame = frame.insetBy(dx: horizontalInset, dy: verticalInset)
                Color.clear.preference(
                    key: StoryInteractionExclusionKey.self,
                    value: [
                        StoryInteractionExclusionZone(
                            id: id,
                            rect: adjustedFrame,
                            intents: intents,
                            suppressionScope: suppressionScope
                        )
                    ]
                )
            }
        )
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

// MARK: - Pan de rascado reveal (UIKit, no bloquea deck ni taps laterales)

struct RevealScratchPanOverlay: UIViewRepresentable {
    let isEnabled: Bool
    var sidePassThroughFraction: CGFloat = StoryGestureCoordinator.revealSidePassthroughFraction
    let onBegan: () -> Void
    let onPoint: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RevealScratchPanView {
        let view = RevealScratchPanView()
        view.coordinator = context.coordinator
        view.sidePassThroughFraction = sidePassThroughFraction
        return view
    }

    func updateUIView(_ uiView: RevealScratchPanView, context: Context) {
        context.coordinator.parent = self
        uiView.isUserInteractionEnabled = isEnabled
        uiView.sidePassThroughFraction = sidePassThroughFraction
    }

    final class Coordinator: NSObject {
        var parent: RevealScratchPanOverlay?
        fileprivate func beginScratchIfNeeded() {
            parent?.onBegan()
        }

        fileprivate func scratch(at point: CGPoint) {
            parent?.onPoint(point)
        }

        fileprivate func endScratchIfNeeded() {
            parent?.onEnded()
        }
    }

    final class RevealScratchPanView: UIView {
        weak var coordinator: Coordinator?
        var sidePassThroughFraction: CGFloat = 0.26
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
            guard bounds.width > 0 else { return false }
            let side = bounds.width * sidePassThroughFraction
            if point.x < side || point.x > bounds.width - side {
                return false
            }
            return super.point(inside: point, with: event)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let coordinator,
                  coordinator.parent?.isEnabled == true else { return }

            switch recognizer.state {
            case .began:
                coordinator.beginScratchIfNeeded()
                coordinator.scratch(at: recognizer.location(in: self))
            case .changed:
                coordinator.scratch(at: recognizer.location(in: self))
            case .ended, .cancelled, .failed:
                coordinator.endScratchIfNeeded()
            default:
                break
            }
        }
    }
}
