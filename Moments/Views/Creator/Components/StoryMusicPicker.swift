import SwiftUI
import AVFoundation
import FirebaseAuth
import FirebaseCore

struct StoryMusicTrack: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let duration: Double
    var artworkURL: URL?
    var previewURL: URL?
    var lyrics: String?
    var waveform: [Float]?
}

enum StoryMusicStyle: String, Codable, CaseIterable, Identifiable {
    case hidden, title, card, cover, record, lyrics
    var id: String { rawValue }
    var label: String { NSLocalizedString("story.music.style.\(rawValue)", comment: "Music appearance") }
    var iconAsset: String? {
        switch self {
        case .hidden: "StoryMusicHiddenIcon"
        case .title: "StoryMusicTitleIcon"
        case .card: "StoryMusicCardIcon"
        case .cover: "StoryMusicCoverIcon"
        case .record: "StoryMusicRecordIcon"
        case .lyrics: nil
        }
    }
    var symbol: String {
        switch self {
        case .hidden: return "xmark"
        case .title: return "music.note"
        case .card: return "rectangle"
        case .cover: return "square"
        case .record: return "opticaldisc"
        case .lyrics: return "textformat"
        }
    }
}

struct StoryMusicSelection: Codable, Hashable {
    var track: StoryMusicTrack
    var start: Double = 0
    var duration: Double
    var style: StoryMusicStyle = .card
    var colorHex: String = "FFFFFF"
    var cardStyleVariant: Int? = nil
    var rasterScale: Double? = nil
    // Static lyrics are user-selected; Soundstripe does not document timed lyrics.
    var lyricText: String? = nil

    mutating func clamp(to storyDuration: Double) {
        duration = min(max(storyDuration.isFinite ? storyDuration : 15, 0.1), track.duration)
        start = min(max(start.isFinite ? start : 0, 0), max(track.duration - duration, 0))
    }
}

/// Only our authenticated backend talks to Soundstripe. No vendor key belongs in iOS.
enum StoryMusicCatalog {
    struct Page: Decodable { let tracks: [StoryMusicTrack]; let nextCursor: String? }
    struct Playlist: Decodable, Identifiable, Hashable { let id: String; let title: String; let artworkURL: URL? }
    struct DiscoverPage: Decodable { let playlists: [Playlist]; let nextCursor: String? }
    struct SavedPage: Decodable { let tracks: [StoryMusicTrack] }
    struct SaveResult: Decodable { let saved: Bool }
    static func discover(cursor: String? = nil) async throws -> DiscoverPage {
        try await request("getStoryMusicDiscover", body: cursor.map { ["cursor": $0] } ?? [:])
    }
    static func playlist(_ id: String, cursor: String? = nil) async throws -> Page {
        try await request("getStoryMusicDiscover", body: ["playlistId": id].merging(cursor.map { ["cursor": $0] } ?? [:]) { _, new in new })
    }
    static func saved() async throws -> [StoryMusicTrack] {
        let result: SavedPage = try await request("getStoryMusicSaved", body: [:])
        return result.tracks
    }
    static func save(_ id: String, saved: Bool) async throws {
        let _: SaveResult = try await request("setStoryMusicSaved", body: ["trackId": id, "saved": saved])
    }
    enum CatalogError: Error { case unavailable, unauthorized, invalidResponse }

    static func search(query: String, cursor: String? = nil) async throws -> Page {
        try await request("getStoryMusicCatalog", body: ["query": query, "limit": 30].merging(cursor.map { ["cursor": $0] } ?? [:]) { _, new in new })
    }

    static func resolve(trackId: String, storyId: String? = nil) async throws -> StoryMusicTrack {
        try await request("getStoryMusicTrack", body: ["trackId": trackId].merging(storyId.map { ["storyId": $0] } ?? [:]) { _, new in new })
    }

    private static func request<T: Decodable>(_ function: String, body: [String: Any]) async throws -> T {
        guard let user = Auth.auth().currentUser else { throw CatalogError.unauthorized }
        guard let project = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://europe-southwest1-\(project).cloudfunctions.net/\(function)") else { throw CatalogError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CatalogError.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class StoryMusicAudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var failed = false
    @Published private(set) var elapsed: Double = 0
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var selection: StoryMusicSelection?
    private var generation = UUID()
    private let audioSession = MomentsAudioSessionLease()
    private var activationTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: MomentsAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    func load(_ selection: StoryMusicSelection, url: URL, play: Bool) {
        stop()
        self.selection = selection
        let player = AVPlayer(url: url)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.08, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, self.player === player, let selection = self.selection else { return }
                if time.seconds.isFinite {
                    self.elapsed = min(max(time.seconds - selection.start, 0), selection.duration)
                }
                if time.seconds >= selection.start + selection.duration {
                    self.player?.seek(to: CMTime(seconds: selection.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                if self.player?.currentItem?.status == .failed { self.failed = true; self.pause() }
            }
        }
        seek(to: selection.start, play: play)
    }

    func seek(to seconds: Double, play: Bool) {
        guard let player else { return }
        let generation = UUID()
        self.generation = generation
        activationTask?.cancel()
        player.pause()
        if !play { audioSession.deactivate() }
        elapsed = max(seconds - (selection?.start ?? 0), 0)
        isPlaying = play
        player.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor in
                guard let self, self.generation == generation, completed, play else { return }
                self.play()
            }
        }
    }
    func update(_ selection: StoryMusicSelection) { self.selection = selection; seek(to: selection.start, play: isPlaying) }
    func play() {
        guard player != nil else { return }
        activationTask?.cancel()
        let generation = self.generation
        activationTask = Task { @MainActor [weak self] in
            guard let self, await self.audioSession.activate(),
                  !Task.isCancelled, self.generation == generation else { return }
            self.player?.play()
            self.isPlaying = true
        }
    }
    func pause() {
        generation = UUID()
        activationTask?.cancel()
        activationTask = nil
        player?.pause()
        isPlaying = false
        audioSession.deactivate()
    }
    func stop() {
        pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil; player = nil; selection = nil; failed = false; elapsed = 0
    }
    deinit {
        activationTask?.cancel()
        audioSession.deactivate()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        player?.pause()
    }
}

extension StoryMusicSelection {
    /// Logical points shared with the Android native music artwork, independent of PNG density.
    var artworkLayoutSize: CGSize {
        if style == .hidden { return CGSize(width: 1, height: 1) }
        let compact = style == .card
        let limit: CGFloat = compact ? 180 : (style == .title ? 260 : 220)
        let titleFont = UIFont.systemFont(ofSize: compact ? 14 : 17, weight: .semibold)
        let artistFont = UIFont.systemFont(ofSize: compact ? 11 : 12)
        let measuredTitle = (track.title as NSString).boundingRect(
            with: CGSize(width: limit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont], context: nil)
        let measuredArtist = (track.artist as NSString).size(withAttributes: [.font: artistFont])
        let textWidth = min(max(ceil(max(measuredTitle.width, measuredArtist.width)) + 2, 1), limit)
        let titleHeight = min(ceil(measuredTitle.height), ceil(titleFont.lineHeight * (compact ? 1 : 2)))
        let artistHeight = ceil(artistFont.lineHeight)
        switch style {
        case .card: return CGSize(width: 56 + textWidth, height: 48)
        case .cover: return CGSize(width: max(128, textWidth), height: 128 + 10 + titleHeight + 4 + artistHeight)
        case .record: return CGSize(width: max(164, textWidth), height: 164 + 8 + titleHeight + 8 + artistHeight)
        default: return CGSize(width: textWidth, height: titleHeight + 4 + artistHeight)
        }
    }
}

struct StoryMusicStickerArtwork: View {
    let selection: StoryMusicSelection
    var artwork: UIImage? = nil
    @Environment(\.colorScheme) private var colorScheme
    private var color: Color { Color(hex: selection.colorHex) }
    private func textWidth(limit: CGFloat, compact: Bool = false) -> CGFloat {
        let titleFont = compact ? UIFont.systemFont(ofSize: 14, weight: .semibold) : UIFont.preferredFont(forTextStyle: .headline)
        let artistFont = compact ? UIFont.systemFont(ofSize: 11) : UIFont.preferredFont(forTextStyle: .caption1)
        let titleWidth = (selection.track.title as NSString).boundingRect(
            with: CGSize(width: limit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: titleFont], context: nil).width
        let artistWidth = (selection.track.artist as NSString).size(withAttributes: [.font: artistFont]).width
        return min(max(ceil(max(titleWidth, artistWidth)) + 2, 1), limit)
    }
    var body: some View {
        Group {
            switch selection.style {
            case .hidden: Color.clear.frame(width: 1, height: 1)
            case .title:
                VStack(spacing: 4) { Text(selection.track.title).font(.headline).lineLimit(2); Text(selection.track.artist).font(.caption).lineLimit(1) }
                    .frame(width: textWidth(limit: 260))
                    .foregroundStyle(color).shadow(color: .black.opacity(0.5), radius: 2)
            case .lyrics:
                Text(selection.lyricText ?? "").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(color).shadow(color: .black.opacity(0.5), radius: 2).frame(maxWidth: 260)
            case .card:
                HStack(spacing: 8) {
                    cover(side: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selection.track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(selection.track.artist).font(.system(size: 11)).lineLimit(1)
                    }.frame(width: textWidth(limit: 180, compact: true), alignment: .leading)
                }
                .foregroundStyle(momentsCardStickerTextColor(styleVariant: selection.cardStyleVariant ?? 0, colorScheme: colorScheme))
                .padding(8)
                .background {
                    momentsCardStickerBackgroundGradient(styleVariant: selection.cardStyleVariant ?? 0, colorScheme: colorScheme)
                        .clipShape(.rect(cornerRadius: 10))
                }
            case .record:
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(.black)
                        ForEach(0..<8) { index in
                            Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                .padding(CGFloat(index * 5 + 4))
                        }
                        cover(side: 86).clipShape(Circle())
                    }.frame(width: 164, height: 164)
                    Text(selection.track.title).font(.headline).lineLimit(2)
                    Text(selection.track.artist).font(.caption).lineLimit(1)
                }.foregroundStyle(color).frame(width: max(164, textWidth(limit: 220)))
            case .cover:
                VStack(spacing: 10) {
                    cover(side: 128)
                    VStack(spacing: 4) {
                        Text(selection.track.title).font(.headline).lineLimit(2)
                        Text(selection.track.artist).font(.caption).lineLimit(1)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(color)
                .frame(width: max(128, textWidth(limit: 220)))
                .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func cover(side: CGFloat) -> some View {
        Group {
            if let artwork { Image(uiImage: artwork).resizable().scaledToFill() }
            else {
                AsyncImage(url: selection.track.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note").font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.15))
                }
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .clipShape(.rect(cornerRadius: 8))
    }
}

@MainActor
final class StoryMusicLibrary: ObservableObject {
    @Published var tracks: [StoryMusicTrack] = []
    @Published var busy: Set<String> = []
    @Published var failed = false
    func contains(_ id: String) -> Bool { tracks.contains { $0.id == id } }
    func load() async {
        do { tracks = try await StoryMusicCatalog.saved(); failed = false }
        catch { if !Task.isCancelled { failed = true } }
    }
    func toggle(_ track: StoryMusicTrack) async {
        guard !busy.contains(track.id) else { return }
        busy.insert(track.id)
        defer { busy.remove(track.id) }
        let saved = !contains(track.id)
        do {
            try await StoryMusicCatalog.save(track.id, saved: saved)
            tracks.removeAll { $0.id == track.id }
            if saved { tracks.insert(track, at: 0) }
            failed = false
            InAppNotificationService.shared.showActionToast(InAppActionToast(
                systemImage: saved ? "bookmark.fill" : "bookmark",
                prefix: NSLocalizedString(saved ? "story.music.saved.confirmation" : "story.music.unsaved.confirmation", comment: "Music bookmark confirmation")
            ))
        } catch { failed = true }
    }
}

struct StoryMusicTrackSheet: View {
    let track: StoryMusicTrack
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var library = StoryMusicLibrary()
    @StateObject private var audio = StoryMusicAudioPlayer()
    @State private var resolving = false
    @State private var failed = false
    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                AsyncImage(url: track.artworkURL) { image in image.resizable().scaledToFill() }
                    placeholder: { Image(systemName: "music.note").font(.largeTitle) }
                    .frame(width: 96, height: 96).clipShape(.rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text(track.title).font(.title2.bold())
                    Text(track.artist).foregroundStyle(.secondary)
                    Text(String(format: "%d:%02d", Int(track.duration) / 60, Int(track.duration) % 60)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                previewButton
                Button { Task { await library.toggle(track) } } label: {
                    Image(systemName: library.contains(track.id) ? "bookmark.fill" : "bookmark").font(.title2).frame(width: 44, height: 44)
                }.buttonStyle(.bordered).disabled(library.busy.contains(track.id))
                    .accessibilityLabel(NSLocalizedString(library.contains(track.id) ? "story.music.unsave" : "story.music.save", comment: "Bookmark"))
            }
            if failed || library.failed || audio.failed { Text(NSLocalizedString("story.music.unavailable.detail", comment: "Retry")).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(24).padding(.top, 12)
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("story.music.posts", comment: "Song posts")).font(.headline).padding(.horizontal, 24)
            Text(NSLocalizedString("story.music.posts.placeholder", comment: "Future song posts")).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(.primary.opacity(0.06)).aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }.allowsHitTesting(false)
        }
        }.tint(.primary)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .task { await library.load() }
        .onDisappear { audio.stop() }
    }
    private var previewButton: some View {
        let button = Button { Task { await preview() } } label: {
            Label(NSLocalizedString("story.music.preview", comment: "Listen"), systemImage: audio.isPlaying ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        return Group {
            if #available(iOS 26.0, *) {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .tint(colorScheme == .dark ? Color.white : Color.black)
        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        .disabled(resolving)
    }

    private func preview() async {
        if audio.isPlaying { audio.pause(); return }
        resolving = true; failed = false
        defer { resolving = false }
        do {
            let resolved = try await StoryMusicCatalog.resolve(trackId: track.id)
            guard !Task.isCancelled, let url = resolved.previewURL else { return }
            audio.load(StoryMusicSelection(track: resolved, duration: resolved.duration), url: url, play: true)
        } catch { failed = true }
    }
}

struct StoryMusicPicker: View {
    let existing: StoryMusicSelection?
    let storyDuration: Double
    let onApply: (StoryMusicSelection, UIImage?) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var library = StoryMusicLibrary()
    @State private var tab = "songs"
    @State private var playlists: [StoryMusicCatalog.Playlist] = []
    @State private var selectedPlaylist: StoryMusicCatalog.Playlist?
    @State private var query = ""
    @State private var tracks: [StoryMusicTrack] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var error = false
    @State private var selection: StoryMusicSelection?
    @State private var artwork: UIImage?
    @State private var isApplying = false
    @State private var isResolving = false
    @State private var requestGeneration = UUID()
    @State private var selectionGeneration = UUID()
    @StateObject private var audio = StoryMusicAudioPlayer()

    var body: some View {
        catalog
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selection {
                catalogPreview(selection)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .padding(.top, 12)
        .tint(Color.primary)
        .task(id: "\(tab)|\(selectedPlaylist?.id ?? "")|\(query)") {
            do { try await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 300)) } catch { return }
            await search(reset: true)
        }
        .task {
            await library.load()
            if var existing {
                existing.clamp(to: storyDuration)
                selection = existing
                await select(existing.track, keeping: existing)
            }
        }
        .onDisappear { audio.stop() }
    }

    private var catalog: some View {
        VStack {
            HStack { Image(systemName: "magnifyingglass"); TextField(NSLocalizedString("story.music.search", comment: "Search"), text: $query).autocorrectionDisabled() }
                .padding(14).background(.primary.opacity(0.06), in: Capsule()).padding(.horizontal)
            HStack(spacing: 8) {
                ForEach(["songs", "discover", "saved"], id: \.self) { value in
                    Button(NSLocalizedString("story.music.tab.\(value)", comment: "Music tab")) { tab = value; selectedPlaylist = nil }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .tint(tab == value ? Color.primary : Color.secondary)
                }
            }.padding(.horizontal)
            if let selectedPlaylist {
                Button { self.selectedPlaylist = nil } label: { Label(selectedPlaylist.title, systemImage: "chevron.left") }.padding(.horizontal)
            }
            if library.failed { Button(NSLocalizedString("story.music.retry", comment: "Retry")) { Task { await library.load() } }.font(.caption) }
            if isLoading && tracks.isEmpty { ProgressView().frame(maxHeight: .infinity) }
            else if error && tracks.isEmpty {
                ContentUnavailableView {
                    Label(NSLocalizedString("story.music.unavailable", comment: "Catalog unavailable"), systemImage: "music.note")
                } description: { Text(NSLocalizedString("story.music.unavailable.detail", comment: "Catalog retry")) }
                actions: { Button(NSLocalizedString("story.music.retry", comment: "Retry")) { Task { await search(reset: true) } } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if tab == "discover" && selectedPlaylist == nil && query.isEmpty {
                            ForEach(playlists) { playlist in
                                Button { selectedPlaylist = playlist } label: {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: playlist.artworkURL) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note.list") }
                                            .frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
                                        Text(playlist.title).font(.headline)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }.padding(.vertical, 8)
                                }.buttonStyle(.plain)
                            }
                        }
                        ForEach(visibleTracks) { track in trackRow(track) }
                        if let cursor, !error {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .task(id: cursor) { await search(reset: false) }
                        }
                        if error && !tracks.isEmpty { Button(NSLocalizedString("story.music.retry", comment: "Retry")) { Task { await search(reset: false) } } }
                        if !isLoading && !error && visibleTracks.isEmpty && (tab != "discover" || !query.isEmpty || selectedPlaylist != nil || playlists.isEmpty) { Text(NSLocalizedString("story.music.empty", comment: "No results")).foregroundStyle(.secondary).padding() }
                    }.padding(.horizontal)
                }
            }
        }
    }

    private func trackRow(_ track: StoryMusicTrack) -> some View {
                            HStack {
                            Button { Task { await select(track) } } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: track.artworkURL) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note") }
                                        .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) { Text(track.title).font(.headline); Text(track.artist).font(.subheadline).foregroundStyle(.secondary) }
                                    Spacer()
                                    if selection?.track.id == track.id {
                                        Image(systemName: "waveform")
                                    }

                                }.padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { Task { await library.toggle(track) } } label: {
                                Image(systemName: library.contains(track.id) ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
                            }.buttonStyle(.plain).disabled(library.busy.contains(track.id))
                                .accessibilityLabel(NSLocalizedString(library.contains(track.id) ? "story.music.unsave" : "story.music.save", comment: "Bookmark"))
                            }
    }

    private var visibleTracks: [StoryMusicTrack] {
        if tab == "saved" {
            return library.tracks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
        }
        return tracks
    }

    private func catalogPreview(_ current: StoryMusicSelection) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: current.track.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: { Image(systemName: "music.note") }
                .frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(current.track.title).font(.headline).lineLimit(1)
                Text(current.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { audio.isPlaying ? audio.pause() : audio.play() } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }.accessibilityLabel(NSLocalizedString("story.music.preview", comment: "Preview"))
            catalogContinueButton
            .disabled(isApplying || isResolving || error || current.track.previewURL == nil)
            .accessibilityLabel(NSLocalizedString("story.music.done", comment: "Edit selection"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
        .buttonStyle(.plain)
    }

    private var catalogContinueButton: some View {
        let button = Button { Task { await apply() } } label: {
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 22, height: 22)
        }
        return Group {
            if #available(iOS 26.0, *) {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(colorScheme == .dark ? Color.white : Color.black)
        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        .frame(minWidth: 44, minHeight: 44)
    }

    private func search(reset: Bool) async {
        guard reset || (!isLoading && cursor != nil) else { return }
        let generation = UUID(); requestGeneration = generation
        isLoading = true; error = false
        do {
            if tab == "saved" {
                if reset { await library.load() }
                guard requestGeneration == generation else { return }
                tracks = []; cursor = nil; isLoading = false; return
            }
            if tab == "discover", selectedPlaylist == nil, query.isEmpty {
                let page = try await StoryMusicCatalog.discover(cursor: reset ? nil : cursor)
                guard !Task.isCancelled, requestGeneration == generation else { return }
                if reset { playlists = page.playlists } else { let ids = Set(playlists.map(\.id)); playlists += page.playlists.filter { !ids.contains($0.id) } }
                tracks = []; cursor = page.nextCursor; isLoading = false; return
            }
            let page: StoryMusicCatalog.Page
            if let selectedPlaylist, query.isEmpty { page = try await StoryMusicCatalog.playlist(selectedPlaylist.id, cursor: reset ? nil : cursor) }
            else { page = try await StoryMusicCatalog.search(query: query, cursor: reset ? nil : cursor) }
            guard !Task.isCancelled, requestGeneration == generation else { return }
            let valid = page.tracks.filter { $0.duration.isFinite && $0.duration >= storyDuration }
            if reset { tracks = valid } else { let ids = Set(tracks.map(\.id)); tracks += valid.filter { !ids.contains($0.id) } }
            cursor = page.nextCursor
        } catch { if requestGeneration == generation { self.error = true } }
        if requestGeneration == generation { isLoading = false }
    }

    private func select(_ track: StoryMusicTrack, keeping existing: StoryMusicSelection? = nil) async {
        let generation = UUID()
        selectionGeneration = generation
        var value = existing ?? StoryMusicSelection(track: track, duration: storyDuration)
        value.clamp(to: storyDuration)
        value.lyricText = value.lyricText ?? track.lyrics?.components(separatedBy: .newlines).first(where: { !$0.isEmpty })
        selection = value; artwork = nil; error = false; isResolving = true

        defer { if selectionGeneration == generation { isResolving = false } }
        do {
            let resolved = try await StoryMusicCatalog.resolve(trackId: track.id)
            guard selectionGeneration == generation, !Task.isCancelled else { return }
            selection?.track = resolved
            selection?.clamp(to: storyDuration)
            if let url = resolved.previewURL, let selection { audio.load(selection, url: url, play: true) }
            else { selection = nil }
            if let url = resolved.artworkURL, let (data, _) = try? await URLSession.shared.data(from: url), selectionGeneration == generation { artwork = UIImage(data: data) }
        } catch { if selectionGeneration == generation { selection = nil; self.error = true } }
    }

    private func apply() async {
        guard var selection, !error else { return }
        isApplying = true
        selection.clamp(to: storyDuration)
        audio.stop(); onApply(selection, artwork); dismiss()
        isApplying = false
    }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

/// Scroll the complete song under a fixed window. There are no resize handles.
struct StoryMusicWaveform: View {
    static var selectionGradient: LinearGradient {
        LinearGradient(colors: [.blue, .purple, .pink],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    let track: StoryMusicTrack
    @Binding var selection: StoryMusicSelection
    var playing: Bool = false
    var progress: Double = 0
    var onScrubbing: (Bool) -> Void = { _ in }
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var isScrubbing = false
    var body: some View {
        GeometryReader { proxy in
            let window = min(max(proxy.size.width * 0.34, 96), 144)
            let pointsPerSecond = window / max(CGFloat(selection.duration), 0.1)
            let side = max((proxy.size.width - window) / 2, 0)
            ScrollView(.horizontal) {
                let trackWidth = CGFloat(track.duration) * pointsPerSecond
                let pitch = VoiceMessageLayout.barWidth + VoiceMessageLayout.barSpacing
                let count = max(1, min(2000, Int(trackWidth / pitch)))
                let levels = ChatVoiceWaveformSamples.resampled(track.waveform ?? [], count: count)
                waveformBars(levels, color: .white.opacity(0.45))
                .frame(width: trackWidth, height: 64)
                .overlay {
                    Self.selectionGradient
                        .frame(width: window, height: 64)
                        .offset(x: CGFloat(selection.start) * pointsPerSecond)
                        .frame(width: trackWidth, height: 64, alignment: .leading)
                        .mask {
                            waveformBars(levels, color: .white)
                                .frame(width: trackWidth, height: 64)
                        }
                        .allowsHitTesting(false)
                }
            }
            .contentMargins(.leading, side, for: .scrollContent)
            .contentMargins(.trailing, side, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Double.self) { geometry in
                Double((geometry.contentOffset.x + geometry.contentInsets.leading) / pointsPerSecond)
            } action: { _, start in
                selection.start = min(max(start, 0), max(track.duration - selection.duration, 0))
            }
            .onScrollPhaseChange { _, phase in
                isScrubbing = phase != .idle
                onScrubbing(phase != .idle)
            }
            .overlay {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 3)
                    Rectangle().fill(.white)
                        .frame(width: 2, height: 46)
                        .offset(x: CGFloat(min(max(progress / max(selection.duration, 0.1), 0), 1)) * (window - 4) + 2)
                        .opacity(playing ? 1 : 0)
                }.frame(width: window, height: 58).allowsHitTesting(false)
            }
            .task(id: track.id) { scrollPosition.scrollTo(x: CGFloat(selection.start) * pointsPerSecond) }
            .onChange(of: selection.start) { _, start in
                guard !isScrubbing else { return }
                scrollPosition.scrollTo(x: CGFloat(start) * pointsPerSecond)
            }
            .onChange(of: selection.duration) { _, _ in
                scrollPosition.scrollTo(x: CGFloat(selection.start) * pointsPerSecond)
            }
            .accessibilityLabel(NSLocalizedString("story.music.fragment", comment: "Selected fragment"))
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 1.0 : -1.0
                selection.start = min(max(selection.start + delta, 0), max(track.duration - selection.duration, 0))
                scrollPosition.scrollTo(x: CGFloat(selection.start) * pointsPerSecond)
            }
        }
    }

    private func waveformBars(_ levels: [Float], color: Color) -> some View {
        VisualWaveformView(
            levels: levels, color: color, activeColor: color, progress: 0,
            height: 38, barWidth: VoiceMessageLayout.barWidth,
            spacing: VoiceMessageLayout.barSpacing
        )
    }
}

extension UIColor {
    var musicHex: String {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
