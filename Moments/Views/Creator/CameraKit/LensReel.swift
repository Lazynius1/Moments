import SwiftUI
import UIKit
import SCSDKCameraKit

/// Selector de lentes con la mecánica de una cámara nativa: un `UICollectionView`
/// se mueve por debajo del obturador fijo y la lente más cercana a su centro es la
/// activa. No hay un binding SwiftUI que pueda volver a desplazar el carrusel.
struct LensReel: View {
    let lenses: [Lens]
    @Binding var isRecording: Bool
    let onSelect: (Lens?) -> Void
    let onCapturePhoto: () -> Void
    let onStartVideo: () -> Void
    let onStopVideo: () -> Void

    static let passthroughKey = "__passthrough__"

    @State private var centeredKey = LensReel.passthroughKey

    private var items: [LensCarouselItem] {
        [.passthrough] + lenses.map { LensCarouselItem(id: $0.id, iconURL: $0.iconUrl) }
    }

    private var centeredLens: Lens? {
        lenses.first { $0.id == centeredKey }
    }

    var body: some View {
        LensCarousel(items: items, centeredKey: $centeredKey) { key in
            if key == Self.passthroughKey {
                onSelect(nil)
            } else if let lens = lenses.first(where: { $0.id == key }) {
                onSelect(lens)
            }
        }
        .overlay(alignment: .center) {
            CaptureButton(
                isRecording: $isRecording,
                lensIconURL: centeredLens?.iconUrl,
                onTap: onCapturePhoto,
                onLongPressStart: onStartVideo,
                onLongPressEnd: onStopVideo
            )
        }
        .frame(height: 100)
    }
}

private struct LensCarouselItem: Equatable {
    let id: String
    let iconURL: URL?

    static let passthrough = LensCarouselItem(id: LensReel.passthroughKey, iconURL: nil)
}

private struct LensCarousel: UIViewRepresentable {
    let items: [LensCarouselItem]
    @Binding var centeredKey: String
    let onCenteredItemChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = LensCarouselLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(LensCarouselCell.self, forCellWithReuseIdentifier: LensCarouselCell.reuseIdentifier)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        guard coordinator.items != items else { return }
        coordinator.items = items
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        coordinator.centerInitialItem(in: collectionView)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: LensCarousel
        var items: [LensCarouselItem] = []
        private var centeredIndex: Int?

        init(parent: LensCarousel) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: LensCarouselCell.reuseIdentifier,
                for: indexPath
            ) as! LensCarouselCell
            cell.configure(with: items[indexPath.item])
            return cell
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            selectItemUnderCaptureButton(in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let target = IndexPath(item: indexPath.item, section: 0)
            collectionView.scrollToItem(at: target, at: .centeredHorizontally, animated: true)
        }

        func centerInitialItem(in collectionView: UICollectionView) {
            guard centeredIndex == nil, !items.isEmpty, collectionView.bounds.width > 0 else { return }
            centeredIndex = 0
            collectionView.setContentOffset(
                CGPoint(x: -collectionView.adjustedContentInset.left, y: 0),
                animated: false
            )
            updateVisibleCellAppearance(in: collectionView)
        }

        private func selectItemUnderCaptureButton(in collectionView: UICollectionView) {
            let captureCenterX = collectionView.contentOffset.x + (collectionView.bounds.width / 2)
            let visibleRect = CGRect(
                x: collectionView.contentOffset.x,
                y: 0,
                width: collectionView.bounds.width,
                height: collectionView.bounds.height
            )
            let closest = collectionView.collectionViewLayout
                .layoutAttributesForElements(in: visibleRect)?
                .min { abs($0.center.x - captureCenterX) < abs($1.center.x - captureCenterX) }

            updateVisibleCellAppearance(in: collectionView)

            guard let index = closest?.indexPath.item,
                  index != centeredIndex,
                  items.indices.contains(index) else { return }

            centeredIndex = index
            let key = items[index].id
            parent.centeredKey = key
            parent.onCenteredItemChanged(key)
        }

        private func updateVisibleCellAppearance(in collectionView: UICollectionView) {
            let captureCenterX = collectionView.contentOffset.x + (collectionView.bounds.width / 2)
            for cell in collectionView.visibleCells {
                let distance = abs(cell.center.x - captureCenterX)
                let progress = min(distance / LensCarouselLayout.itemPitch, 1)
                cell.alpha = max(0, progress)
                cell.transform = CGAffineTransform(scaleX: 0.82 + (0.18 * progress), y: 0.82 + (0.18 * progress))
            }
        }
    }
}

private final class LensCarouselLayout: UICollectionViewFlowLayout {
    static let itemSize = CGSize(width: 48, height: 48)
    static let itemPitch: CGFloat = 84

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        scrollDirection = .horizontal
        itemSize = Self.itemSize
        minimumLineSpacing = Self.itemPitch - Self.itemSize.width
        sectionInset = UIEdgeInsets(
            top: max((collectionView.bounds.height - Self.itemSize.height) / 2, 0),
            left: max((collectionView.bounds.width - Self.itemSize.width) / 2, 0),
            bottom: max((collectionView.bounds.height - Self.itemSize.height) / 2, 0),
            right: max((collectionView.bounds.width - Self.itemSize.width) / 2, 0)
        )
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView else { return proposedContentOffset }
        let proposedCenterX = proposedContentOffset.x + (collectionView.bounds.width / 2)
        let searchRect = CGRect(
            x: proposedContentOffset.x,
            y: 0,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        guard let closest = layoutAttributesForElements(in: searchRect)?.min(by: {
            abs($0.center.x - proposedCenterX) < abs($1.center.x - proposedCenterX)
        }) else {
            return proposedContentOffset
        }

        return CGPoint(
            x: closest.center.x - (collectionView.bounds.width / 2),
            y: proposedContentOffset.y
        )
    }
}

private final class LensCarouselCell: UICollectionViewCell {
    static let reuseIdentifier = "LensCarouselCell"
    private static let imageCache = NSCache<NSURL, UIImage>()

    private let imageView = UIImageView()
    private let fallbackView = UIImageView(image: UIImage(systemName: "nosign"))
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 24
        contentView.layer.borderWidth = 1.2
        contentView.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        contentView.backgroundColor = UIColor.white.withAlphaComponent(0.15)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)

        fallbackView.tintColor = .white
        fallbackView.contentMode = .scaleAspectFit
        fallbackView.frame = contentView.bounds.insetBy(dx: 14, dy: 14)
        fallbackView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(fallbackView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = nil
        fallbackView.isHidden = false
    }

    func configure(with item: LensCarouselItem) {
        imageTask?.cancel()
        imageView.image = nil
        fallbackView.isHidden = false

        guard let url = item.iconURL else { return }
        if let image = Self.imageCache.object(forKey: url as NSURL) {
            imageView.image = image
            fallbackView.isHidden = true
            return
        }

        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            Self.imageCache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async {
                guard self?.imageTask?.originalRequest?.url == url else { return }
                self?.imageView.image = image
                self?.fallbackView.isHidden = true
            }
        }
        imageTask?.resume()
    }
}
