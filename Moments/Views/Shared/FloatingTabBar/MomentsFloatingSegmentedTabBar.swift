import SwiftUI
import UIKit

/// UISegmentedControl con gota deslizante al arrastrar (mismo patrón que el sample).
struct MomentsFloatingSegmentedTabBar: UIViewRepresentable {
    @Binding var selection: Int
    var images: [UIImage]
    var selectedTintColor: UIColor
    var accessibilityLabels: [String]
    var preservesImageColors: Set<Int>
    var onInteraction: () -> Void
    var onReselect: (Int) -> Void

    func makeUIView(context: Context) -> MomentsFloatingSegmentedControl {
        let control = MomentsFloatingSegmentedControl(items: images)
        control.selectedSegmentIndex = clampedSelection
        control.selectedSegmentTintColor = selectedTintColor
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        control.onTouchBegan = onInteraction
        control.onReselect = onReselect

        // Este control solo se conserva para iOS 26+, donde el chrome nativo
        // sigue siendo el comportamiento visual esperado.
        DispatchQueue.main.async {
            for subview in control.subviews {
                if subview is UIImageView && subview != control.subviews.last {
                    subview.alpha = 0
                }
            }
        }

        return control
    }

    func updateUIView(_ uiView: MomentsFloatingSegmentedControl, context: Context) {
        context.coordinator.parent = self
        uiView.onTouchBegan = onInteraction
        uiView.onReselect = onReselect
        uiView.selectedSegmentTintColor = selectedTintColor

        let index = clampedSelection
        if uiView.selectedSegmentIndex != index {
            uiView.selectedSegmentIndex = index
        }

        if uiView.numberOfSegments == images.count {
            for (i, image) in images.enumerated() {
                uiView.setImage(image, forSegmentAt: i)
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MomentsFloatingSegmentedControl,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.replacingUnspecifiedDimensions().width,
            height: 54
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private var clampedSelection: Int {
        min(max(selection, 0), max(images.count - 1, 0))
    }

    final class Coordinator: NSObject {
        var parent: MomentsFloatingSegmentedTabBar

        init(parent: MomentsFloatingSegmentedTabBar) {
            self.parent = parent
        }

        @objc
        func valueChanged(_ sender: UISegmentedControl) {
            let index = sender.selectedSegmentIndex
            guard index >= 0 else { return }
            parent.selection = index
        }
    }
}

final class MomentsFloatingSegmentedControl: UISegmentedControl {
    var onTouchBegan: (() -> Void)?
    var onReselect: ((Int) -> Void)?
    private var indexAtTouchBegan: Int = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        indexAtTouchBegan = selectedSegmentIndex
        onTouchBegan?()
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if selectedSegmentIndex == indexAtTouchBegan {
            onReselect?(selectedSegmentIndex)
        }
    }
}
