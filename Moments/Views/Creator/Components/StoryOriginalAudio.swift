import SwiftUI

struct StoryOriginalAudioSource: Identifiable {
    let ownerId: String
    let storyId: String
    let stickerId: String
    var id: String { "\(ownerId):\(storyId):\(stickerId)" }
    var body: [String: Any] { ["ownerId": ownerId, "storyId": storyId, "stickerId": stickerId] }
}
struct StoryOriginalAudioDetail: Decodable {
    let track: StoryMusicTrack
    var creatorId: String? = nil
    let canSave: Bool
    let reason: String?
    let saved: Bool
}
enum StoryOriginalAudioCatalog {
    struct Page: Decodable { let tracks: [StoryMusicTrack]; let nextCursor: String? }
    static func detail(_ source: StoryOriginalAudioSource) async throws -> StoryOriginalAudioDetail {
        try await StoryMusicCatalog.request("getStoryOriginalAudio", body: source.body)
    }
    static func save(_ source: StoryOriginalAudioSource, id: String, saved: Bool) async throws {
        let _: StoryMusicCatalog.SaveResult = try await StoryMusicCatalog.request("setStoryOriginalAudioSaved",
            body: source.body.merging(["audioId": id, "saved": saved]) { _, new in new })
    }
    static func saved(cursor: String? = nil) async throws -> Page {
        try await StoryMusicCatalog.request("getStoryOriginalAudioSaved", body: cursor.map { ["cursor": $0] } ?? [:])
    }
    static func resolve(_ id: String) async throws -> StoryMusicTrack {
        try await StoryMusicCatalog.request("resolveStoryOriginalAudio", body: ["audioId": id])
    }
}

struct StoryAudioPicker: View {
    let onRecord: (Data, Double) -> Void
    let onUse: (Data, Double, String) -> Void
    @State private var tab = 0
    @State private var tracks: [StoryMusicTrack] = []
    @State private var nextCursor: String?
    @State private var loaded = false
    @State private var loading = false
    @State private var failed = false
    @State private var previewId: String?
    @State private var usingId: String?
    @StateObject private var audio = StoryMusicAudioPlayer()
    var body: some View {
        VStack(spacing: 20) {
            Picker("story.audio.title", selection: $tab) {
                Text("story.audio.record").tag(0)
                Text("story.audio.saved").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 24)
            if tab == 0 {
                AudioStickerRecordingView(onAdd: onRecord)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if tracks.isEmpty && loaded && !failed { Text("story.audio.empty").foregroundStyle(.secondary).padding(24) }
                        ForEach(tracks) { track in
                            HStack(spacing: 12) {
                                Button { Task { await preview(track) } } label: {
                                    Image(systemName: audio.isPlaying && previewId == track.id ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                                }.accessibilityLabel(Text("story.music.preview"))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("story.audio.original").font(.headline)
                                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                                    Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button { Task { await use(track) } } label: {
                                    if usingId == track.id { ProgressView() } else { Image(systemName: "plus").frame(width: 44, height: 44) }
                                }.accessibilityLabel(Text("story.audio.use"))
                            }
                            .disabled(usingId != nil)
                            .onAppear { if track.id == tracks.last?.id, nextCursor != nil { Task { await load() } } }
                        }
                        if loading { ProgressView().padding() }
                        if failed { Text("story.audio.unavailable").font(.footnote).foregroundStyle(.secondary); Button("story.audio.retry") { loaded = false; nextCursor = nil; tracks = []; Task { await load() } } }
                    }.padding(.horizontal, 24)
                }
            }
        }
        .tint(.primary)
        .task(id: tab) { audio.stop(); if tab == 1 && !loaded { await load() } }
        .onDisappear { audio.stop() }
    }
    private func load() async {
        guard !loading, !loaded || nextCursor != nil else { return }
        loading = true; failed = false
        defer { loading = false }
        do {
            let page = try await StoryOriginalAudioCatalog.saved(cursor: nextCursor)
            guard !Task.isCancelled else { return }
            tracks.append(contentsOf: page.tracks.filter { item in !tracks.contains { $0.id == item.id } })
            nextCursor = page.nextCursor; loaded = true
        } catch { if !Task.isCancelled { failed = true } }
    }
    private func preview(_ track: StoryMusicTrack) async {
        if audio.isPlaying && previewId == track.id { audio.pause(); return }
        audio.stop(); failed = false
        do {
            let resolved = try await StoryOriginalAudioCatalog.resolve(track.id)
            guard !Task.isCancelled, let url = resolved.previewURL else { return }
            previewId = track.id
            audio.load(StoryMusicSelection(track: resolved, duration: resolved.duration), url: url, play: true)
        } catch { failed = true }
    }
    private func use(_ track: StoryMusicTrack) async {
        guard usingId == nil else { return }
        audio.stop(); usingId = track.id; failed = false
        defer { usingId = nil }
        do {
            let resolved = try await StoryOriginalAudioCatalog.resolve(track.id)
            guard let url = resolved.previewURL else { return }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                  !data.isEmpty, data.count <= 12 * 1024 * 1024 else { failed = true; return }
            onUse(data, resolved.duration, track.id)
        } catch { if !Task.isCancelled { failed = true } }
    }
}
