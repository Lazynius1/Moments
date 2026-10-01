import SwiftUI

struct StoryMusicPlayback: ViewModifier {
    let selection: StoryMusicSelection?
    var storyId: String? = nil
    let active: Bool
    let elapsed: Double
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audio = StoryMusicAudioPlayer()
    @State private var resolvedTrackId: String?

    func body(content: Content) -> some View {
        content
            .environment(\.storyMusicIsPlaying, active && scenePhase == .active && audio.isPlaying)
            .task(id: selection?.track.id) {
                audio.stop(); resolvedTrackId = nil
                guard let selection else { return }
                do {
                    let track = try await StoryMusicCatalog.resolve(trackId: selection.track.id, storyId: storyId)
                    guard !Task.isCancelled, let url = track.previewURL else { return }
                    resolvedTrackId = track.id
                    audio.load(selection, url: url, play: false)
                    audio.seek(to: selection.start + min(max(elapsed, 0), selection.duration), play: active && scenePhase == .active)
                } catch {
                    // Keep the visual story usable if its licensed soundtrack is unavailable.
                }
            }
            .onChange(of: active) { _, isActive in
                if isActive && scenePhase == .active { resume() } else { audio.pause() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && active { resume() } else { audio.pause() }
            }
            .onChange(of: selection?.start) { _, _ in resume() }
            .onDisappear { audio.stop() }
    }

    private func resume() {
        guard let selection, resolvedTrackId == selection.track.id else { return }
        audio.seek(to: selection.start + min(max(elapsed, 0), selection.duration), play: active && scenePhase == .active)
    }
}
