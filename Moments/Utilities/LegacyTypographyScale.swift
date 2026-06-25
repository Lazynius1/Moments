import CoreGraphics

private let legacyPoppinsScale: CGFloat = 0.94

func legacyPoppinsSize(_ size: CGFloat) -> CGFloat {
    round(size * legacyPoppinsScale)
}
