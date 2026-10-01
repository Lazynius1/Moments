import SwiftUI

extension EnvironmentValues {
    @Entry var storyMusicIsPlaying = true
}

/// Live record artwork; rotation is restricted to the disc, never its labels
/// or the sticker's saved canvas transform.
struct StoryMusicRecordView: View {
    let selection: StoryMusicSelection
    @Environment(\.storyMusicIsPlaying) private var playing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accumulated = 0.0
    @State private var startedAt: Date?

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion)) { context in
                let elapsed = accumulated + (startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
                disc.rotationEffect(.degrees(reduceMotion ? 0 : elapsed * 24))
            }
            .frame(width: 164, height: 164)
            Text(selection.track.title).font(.headline).lineLimit(2)
            Text(selection.track.artist).font(.caption).lineLimit(1)
        }
        .foregroundStyle(Color(hex: selection.colorHex))
        .frame(maxWidth: 220)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: playing, initial: true) { _, value in
            if value && !reduceMotion {
                startedAt = .now
            } else if let startedAt {
                accumulated += Date.now.timeIntervalSince(startedAt)
                self.startedAt = nil
            }
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(.black)
            ForEach(0..<8) { index in
                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    .padding(CGFloat(index * 5 + 4))
            }
            AsyncImage(url: selection.track.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "music.note").font(.title2).foregroundStyle(.white)
            }
            .frame(width: 86, height: 86).clipShape(Circle())
        }
    }
}
