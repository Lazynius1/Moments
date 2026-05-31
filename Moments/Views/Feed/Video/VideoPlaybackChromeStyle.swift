import SwiftUI

/// Estilo de controles del reproductor (Instagram Reels 2026 vs clásico).
enum VideoPlaybackChromeStyle {
    /// Barra de progreso, mute persistente, overlay play grande al tap.
    case classic
    /// Sin barra; tap = pausa; mute + play pequeños solo cuando está pausado.
    case socialReels
}

/// Controles centrados al pausar (patrón Instagram Reels 2026).
struct SocialVideoPausedControls: View {
    let isMuted: Bool
    let onToggleMute: () -> Void
    let onTogglePlay: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isMuted
                ? NSLocalizedString("feed.video.unmute", comment: "Unmute video")
                : NSLocalizedString("feed.video.mute", comment: "Mute video")
            )

            Button(action: onTogglePlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("feed.video.play", comment: "Play video"))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}
