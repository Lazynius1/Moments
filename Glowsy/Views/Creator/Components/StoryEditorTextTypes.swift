import SwiftUI
import UIKit

extension StoryEditingView {

        enum TextStyle: String, CaseIterable {
            case modern
            case classic
            case poster
            case editorial
            case rounded
            case signature
            case marker
            case typewriter
            case handwritten
            case bold
            case neon
            case chalk

            var displayName: String {
                switch self {
                case .modern: return "Modern"
                case .classic: return "Classic"
                case .poster: return "Poster"
                case .editorial: return "Editorial"
                case .rounded: return "Rounded"
                case .signature: return "Signature"
                case .marker: return "Marker"
                case .typewriter: return "Typewriter"
                case .handwritten: return "Handwritten"
                case .bold: return "Bold"
                case .neon: return "Neon"
                case .chalk: return "Chalk"
                }
            }

            static var fontPickerStyles: [TextStyle] {
                [.modern, .classic, .editorial, .rounded, .signature, .typewriter, .handwritten, .bold, .poster]
            }

            func font(size: CGFloat) -> Font {
                switch self {
                case .modern: return .system(size: size, weight: .medium)
                case .classic: return .custom("Georgia", size: max(12, size - 1))
                case .poster: return .custom("Futura-CondensedExtraBold", size: size + 5)
                case .editorial: return .custom("Didot", size: size + 1)
                case .rounded: return .custom("ArialRoundedMTBold", size: size)
                case .signature: return .custom("SnellRoundhand", size: size + 6)
                case .marker: return .custom("MarkerFelt-Wide", size: size + 2)
                case .typewriter: return .custom("Courier New", size: max(12, size - 3))
                case .handwritten: return .custom("Noteworthy-Bold", size: size + 2)
                case .bold: return .custom("AvenirNextCondensed-DemiBold", size: size + 4)
                case .neon: return .system(size: size + 2, weight: .black)
                case .chalk: return .custom("ChalkboardSE-Bold", size: size + 1)
                }
            }

            func uiFont(size: CGFloat) -> UIFont {
                switch self {
                case .modern:
                    return .systemFont(ofSize: size, weight: .medium)
                case .classic:
                    return UIFont(name: "Georgia", size: max(12, size - 1)) ?? .systemFont(ofSize: size)
                case .poster:
                    return UIFont(name: "Futura-CondensedExtraBold", size: size + 5) ?? .boldSystemFont(ofSize: size + 5)
                case .editorial:
                    return UIFont(name: "Didot", size: size + 1) ?? .systemFont(ofSize: size + 1)
                case .rounded:
                    return UIFont(name: "ArialRoundedMTBold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
                case .signature:
                    return UIFont(name: "SnellRoundhand", size: size + 6) ?? .italicSystemFont(ofSize: size + 4)
                case .marker:
                    return UIFont(name: "MarkerFelt-Wide", size: size + 2) ?? .systemFont(ofSize: size + 2, weight: .bold)
                case .typewriter:
                    return UIFont(name: "Courier New", size: max(12, size - 3)) ?? .monospacedSystemFont(ofSize: size - 2, weight: .regular)
                case .handwritten:
                    return UIFont(name: "Noteworthy-Bold", size: size + 2) ?? .systemFont(ofSize: size + 2, weight: .semibold)
                case .bold:
                    return UIFont(name: "AvenirNextCondensed-DemiBold", size: size + 4) ?? .systemFont(ofSize: size + 4, weight: .heavy)
                case .neon:
                    return .systemFont(ofSize: size + 2, weight: .black)
                case .chalk:
                    return UIFont(name: "ChalkboardSE-Bold", size: size + 1) ?? .systemFont(ofSize: size + 1, weight: .bold)
                }
            }

            var backgroundColor: Color {
                switch self {
                case .modern: return Color.black.opacity(0.6)
                case .classic: return Color.clear
                case .poster: return Color.clear
                case .editorial: return Color.clear
                case .rounded: return Color.black.opacity(0.22)
                case .signature: return Color.clear
                case .marker: return Color.yellow.opacity(0.18)
                case .neon: return Color.purple.opacity(0.8)
                case .typewriter: return Color.gray.opacity(0.55)
                case .handwritten: return Color.clear
                case .bold: return Color.clear
                case .chalk: return Color.black.opacity(0.18)
                }
            }
        }

        enum TextBackgroundFill: String, CaseIterable {
            case none
            case black
            case white
        }

        enum TextEffect: String, CaseIterable {
            case none
            case glow
            case marker
            case chalk

            var displayName: String {
                switch self {
                case .none: return "None"
                case .glow: return "Glow"
                case .marker: return "Marker"
                case .chalk: return "Chalk"
                }
            }

            var backgroundColor: Color? {
                switch self {
                case .marker:
                    return Color.yellow.opacity(0.28)
                case .none, .glow, .chalk:
                    return nil
                }
            }

            var uiBackgroundColor: UIColor? {
                switch self {
                case .marker:
                    return UIColor.systemYellow.withAlphaComponent(0.28)
                case .none, .glow, .chalk:
                    return nil
                }
            }

            func shadow(for textColor: Color) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)? {
                switch self {
                case .glow:
                    return (textColor.opacity(0.92), 12, 0, 0)
                case .chalk:
                    return (Color.black.opacity(0.62), 1.0, 1.0, 1.0)
                case .none, .marker:
                    return nil
                }
            }

            func nsShadow(for textColor: UIColor) -> NSShadow? {
                let shadow = NSShadow()
                switch self {
                case .glow:
                    shadow.shadowColor = textColor.withAlphaComponent(0.92)
                    shadow.shadowBlurRadius = 12
                    shadow.shadowOffset = .zero
                    return shadow
                case .chalk:
                    shadow.shadowColor = UIColor.black.withAlphaComponent(0.62)
                    shadow.shadowBlurRadius = 1
                    shadow.shadowOffset = CGSize(width: 1, height: 1)
                    return shadow
                case .none, .marker:
                    return nil
                }
            }
        }

        enum ActiveEditorMode {
            case idle
            case text
            case drawing
            case filters
        }
}
