import SwiftUI
import UIKit

/// Keeps the photo and its live overlays in the same native zoom surface.
struct ChatZoomableMedia<Content: View>: UIViewControllerRepresentable {
    let isActive: Bool
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> ChatMediaZoomController<Content> {
        ChatMediaZoomController(content: content())
    }

    func updateUIViewController(_ controller: ChatMediaZoomController<Content>, context: Context) {
        controller.host.rootView = content()
        if !isActive { controller.scroll.setZoomScale(1, animated: false) }
    }
}

final class ChatMediaZoomController<Content: View>: UIViewController, UIScrollViewDelegate {
    let host: UIHostingController<Content>
    let scroll = UIScrollView()
    private var viewport: CGSize = .zero

    init(content: Content) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scroll.backgroundColor = .clear
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.panGestureRecognizer.isEnabled = false
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scroll)
        addChild(host)
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        host.didMove(toParent: self)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        scroll.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        guard viewport != view.bounds.size, view.bounds.width > 0, view.bounds.height > 0 else { return }
        viewport = view.bounds.size
        scroll.setZoomScale(1, animated: false)
        host.view.frame = CGRect(origin: .zero, size: viewport)
        scroll.contentSize = viewport
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // At 1×, horizontal drags remain available to the gallery pager.
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > 1.01
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if scroll.zoomScale > 1.01 {
            scroll.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: host.view)
            let rect = CGRect(x: point.x - viewport.width / 6, y: point.y - viewport.height / 6,
                              width: viewport.width / 3, height: viewport.height / 3)
            scroll.zoom(to: rect, animated: true)
        }
    }
}
