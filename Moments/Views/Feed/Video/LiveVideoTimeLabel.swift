import SwiftUI

/// Contador de tiempo de vídeo en vivo.
///
/// - Cuando el vídeo NO ha arrancado todavía muestra la duración total: `"0:18"`.
/// - Cuando el vídeo está reproduciéndose muestra `"0:12 / 0:18"`.
/// - Cuando no hay `totalDuration` y no hay tiempo en curso, no renderiza nada.
///
/// **Modos:**
/// - `.standalone` (por defecto): fondo propio con esquinas redondeadas; listo para usar en esquinas de cards.
/// - `.inline`:  sin fondo ni padding; para incrustar dentro de un `HStack` que ya tiene su propio fondo.
struct LiveVideoTimeLabel: View {

    enum DisplayMode {
        case standalone   // fondo propio (RoundedRectangle negro semitransparente)
        case inline       // sin fondo, el padre gestiona el contenedor
    }

    let consumerId: String
    let totalDuration: Double?
    var displayMode: DisplayMode = .standalone

    @ObservedObject private var manager = GlobalVideoManager.shared

    var body: some View {
        let currentSeconds = manager.livePlaybackSeconds[consumerId] ?? 0
        let hasStarted     = currentSeconds > 0.05

        let text: String? = {
            if hasStarted, let total = totalDuration, total > 0 {
                return formatted(currentSeconds) + " / " + formatted(total)
            } else if let total = totalDuration, total > 0 {
                return formatted(total)
            }
            return nil
        }()

        if let text {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .if(displayMode == .standalone) { $0
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let r = s % 60
        return m > 0 ? String(format: "%d:%02d", m, r) : String(format: "0:%02d", r)
    }
}

// MARK: - Conditional modifier helper (si no está ya definido en el proyecto)
private extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
