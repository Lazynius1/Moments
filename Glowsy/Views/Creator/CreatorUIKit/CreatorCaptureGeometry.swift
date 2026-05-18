import CoreGraphics

let creatorMomentsCaptureAspectRatio: CGFloat = 9.0 / 16.0

func creatorMomentsAspectRect(aspectRatio: CGFloat, in rect: CGRect) -> CGRect {
    guard rect.width > 0, rect.height > 0 else { return .zero }

    let candidateHeight = rect.width / aspectRatio
    if candidateHeight <= rect.height {
        let y = rect.minY + ((rect.height - candidateHeight) / 2)
        return CGRect(x: rect.minX, y: y, width: rect.width, height: candidateHeight)
    } else {
        let width = rect.height * aspectRatio
        let x = rect.minX + ((rect.width - width) / 2)
        return CGRect(x: x, y: rect.minY, width: width, height: rect.height)
    }
}

func creatorMomentsCaptureRect(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> CGRect {
    let availableRect = CGRect(
        x: 0,
        y: topInset,
        width: size.width,
        height: max(size.height - topInset - bottomInset, 0)
    )
    return creatorMomentsAspectRect(aspectRatio: creatorMomentsCaptureAspectRatio, in: availableRect)
}
