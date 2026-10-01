import SwiftUI

/// Rebuild music from its metadata, like poll and question stickers. The legacy
/// name is retained for callers; a remote raster is never required to display it.
struct StoryMusicRasterView: View {
    let sticker: StickerItem

    var body: some View {
        if let music = sticker.interactionData?.music, music.style != .hidden {
            StoryMusicStickerArtwork(selection: music)
                .dynamicTypeSize(.large)
                .overlay {
                    switch music.style {
                    case .card:
                        GeometryReader { geometry in
                            StoryMusicEqualizer().position(x: 24, y: geometry.size.height / 2)
                        }
                    case .cover:
                        GeometryReader { geometry in
                            StoryMusicEqualizer().position(x: geometry.size.width / 2 + 50, y: 14)
                        }
                    default:
                        EmptyView()
                    }
                }
        }
    }
}

private struct StoryMusicEqualizer: View {
    @Environment(\.storyMusicIsPlaying) private var playing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !playing || reduceMotion)) { context in
            let time = playing && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3) { index in
                    let height = playing && !reduceMotion ? 6 + abs(sin(time * 4 + Double(index) * 1.7)) * 10 : 6
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white).frame(width: 3, height: height)
                }
            }
            .frame(width: 16, height: 18)
        }
        .frame(width: 24, height: 24)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: 6))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
