import SwiftUI

/// Cómo decide el reproductor cuándo reproducirse automáticamente.
enum VideoPlaybackActivationMode: Equatable {
    /// Feed / detalle perfil: solo si `FeedVisibilityCoordinator` lo marca activo.
    case feedVisibility
    /// Hero de perfil y previews: reproduce al aparecer.
    case alwaysWhenVisible
}

/// Estilo de controles del reproductor (moderno vs clásico).
enum VideoPlaybackChromeStyle {
    /// Barra de progreso, mute persistente, overlay play grande al tap.
    case classic
    /// Sin barra; tap = pausa; mute + play pequeños solo cuando está pausado.
    case socialReels
}

/// Controles centrados al pausar.
struct SocialVideoPausedControls: View {
    let isMuted: Bool
    let onToggleMute: () -> Void
    let onTogglePlay: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
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

/// Oscurece solo el vídeo del post (no la pantalla) al terminar, como Instagram.
struct FeedVideoEndedOverlay: View {
    let onWatchAgain: () -> Void

    var body: some View {
        Button(action: onWatchAgain) {
            ZStack {
                Color.black.opacity(0.45)
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                    Text(NSLocalizedString("feed.video.watchAgain", comment: "Watch again"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("feed.video.watchAgain", comment: "Watch again"))
    }
}
