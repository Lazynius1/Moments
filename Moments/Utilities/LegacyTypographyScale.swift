import CoreGraphics
import UIKit

private let legacyPoppinsScale: CGFloat = 0.94

/// Escala tipográfica legacy con Dynamic Type vía `UIFontMetrics`.
func legacyPoppinsSize(_ size: CGFloat) -> CGFloat {
    let base = round(size * legacyPoppinsScale)
    return UIFontMetrics.default.scaledValue(for: base)
}
