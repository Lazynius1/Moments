import SwiftUI
import UIKit

/// UISegmentedControl con gota deslizante al arrastrar (mismo patrón que el sample).
struct MomentsFloatingSegmentedTabBar: UIViewRepresentable {
    @Binding var selection: Int
    var images: [UIImage]
    var onInteraction: () -> Void
    var onReselect: (Int) -> Void

    func makeUIView(context: Context) -> MomentsFloatingSegmentedControl {
        let control = MomentsFloatingSegmentedControl(items: images)
        control.selectedSegmentIndex = clampedSelection
        control.selectedSegmentTintColor = UIColor(Color.gray.opacity(0.25))
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        control.onTouchBegan = onInteraction
        control.onReselect = onReselect

        // Quitar fondos internos para que se vea el glass Moments.
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
