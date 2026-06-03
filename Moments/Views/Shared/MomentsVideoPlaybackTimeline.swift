import SwiftUI

struct MomentsVideoPlaybackTimeline: View {
    let currentTime: Double
    let duration: Double
    var horizontalPadding: CGFloat = 26
    var onSeek: (Double) -> Void

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private var effectiveProgress: Double {
        if isScrubbing {
            return scrubProgress
        }
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private var displayedCurrentTime: Double {
        duration > 0 ? effectiveProgress * duration : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let trackWidth = max(geo.size.width, 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: trackWidth * effectiveProgress, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
                        .offset(x: knobOffset(for: trackWidth))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isScrubbing = true
                            scrubProgress = progress(for: value.location.x, width: trackWidth)
                            onSeek(scrubProgress * duration)
                        }
                        .onEnded { value in
                            guard duration > 0 else {
                                isScrubbing = false
                                return
                            }
                            scrubProgress = progress(for: value.location.x, width: trackWidth)
                            onSeek(scrubProgress * duration)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(displayedCurrentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.custom("Poppins-Medium", size: 11))
            .foregroundColor(.white.opacity(0.92))
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func progress(for locationX: CGFloat, width: CGFloat) -> Double {
        let clampedX = min(max(locationX, 0), width)
        return Double(clampedX / max(width, 1))
    }

    private func knobOffset(for width: CGFloat) -> CGFloat {
        let available = max(width - 12, 0)
        return CGFloat(effectiveProgress) * available
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, !value.isNaN else { return "0:00" }
        let totalSeconds = max(0, Int(value.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
