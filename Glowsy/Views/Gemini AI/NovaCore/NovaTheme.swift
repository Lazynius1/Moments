import SwiftUI
import UIKit

// MARK: - Colores modernos
struct ModernGeminiColors {
    static let primary = Color(hex: "00A896")
    static let secondary = Color(hex: "6B73FF")
    static let accent = Color(hex: "9B59B6")

    // Colores adaptativos
    static var background: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Color(hex: "0B1215")) : UIColor(Color(hex: "FAF9F6"))
        })
    }

    static var secondaryBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.02) : UIColor.black.withAlphaComponent(0.02)
        })
    }

    static var cardBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.05) : UIColor.black.withAlphaComponent(0.03)
        })
    }

    static var materialBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.05)
        })
    }

    static var textPrimary: Color {
        Color(UIColor.label)
    }

    static var textSecondary: Color {
        Color(UIColor.secondaryLabel)
    }

    static var textTertiary: Color {
        Color(UIColor.tertiaryLabel)
    }

    static var borderColor: Color {
        Color(UIColor.separator)
    }

    static var shadowColor: Color {
        Color(UIColor.label).opacity(0.1)
    }
}

// MARK: - ✅ CONFIGURACIÓN DE LOGS PARA EVITAR SPAM
struct LogConfig {
    static let isVerboseLogging: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    static func log(_ message: String, category: String = "Nova") {
        if isVerboseLogging {
            print("[\(category)] \(message)")
        } else {
            // Fallback: al menos loggear cosas críticas de Feed si el usuario lo pide
            if category == "Feed" || category == "BackendFeed" {
                print("[\(category)] \(message)")
            }
        }
    }
}
