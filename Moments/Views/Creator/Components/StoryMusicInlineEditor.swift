import SwiftUI
import AVFoundation

/// Music uses the same point-sized image and canvas transforms as other stickers.
@MainActor
enum StoryMusicStickerRenderer {
    static let rasterScale: CGFloat = 3

    static func image(_ selection: StoryMusicSelection, artwork: UIImage?, colorScheme: ColorScheme = .light) -> UIImage? {
        let renderer = ImageRenderer(content: StoryMusicStickerArtwork(selection: selection, artwork: artwork).environment(\.colorScheme, colorScheme))
        // Persist this density with the music metadata so decoding restores
        // logical points, rather than treating the high-resolution pixels as size.
        renderer.scale = rasterScale
        return renderer.uiImage
    }
}

struct StoryMusicInlineEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var sticker: StickerItem
    let canvasSize: CGSize
    let canvasTop: CGFloat
    let bottomInset: CGFloat
    let allowsDurationSelection: Bool
    let onPlaybackChanged: (Bool) -> Void
    let onDone: () -> Void
    @State private var selection: StoryMusicSelection
    @State private var original: StickerItem
    @State private var artwork: UIImage?
    @State private var showingCatalog = false
    @State private var showingDurationPicker = false
    @State private var loading = false
    @State private var failed = false
    @State private var waveformLoading = false
    @State private var waveformFailed = false
    @State private var playbackRevision = UUID()
    @StateObject private var audio = StoryMusicAudioPlayer()
    static let paletteColors = ["FFFFFF", "000000", "FFCB6B", "FF7C9C", "BCA6FF", "85D9C8"]

    init(sticker: Binding<StickerItem>, music: StoryMusicSelection, canvasSize: CGSize, canvasTop: CGFloat, bottomInset: CGFloat, allowsDurationSelection: Bool = true, onPlaybackChanged: @escaping (Bool) -> Void, onDone: @escaping () -> Void) {
        self._sticker = sticker
        self.canvasSize = canvasSize
        self.canvasTop = canvasTop
        self.bottomInset = bottomInset
        self.allowsDurationSelection = allowsDurationSelection
        self.onDone = onDone
        self.onPlaybackChanged = onPlaybackChanged
        let value = sticker.wrappedValue
        var editableMusic = music
        if editableMusic.style == .lyrics { editableMusic.style = .card }
        self._selection = State(initialValue: editableMusic)
        self._original = State(initialValue: value)
    }

    private var availableStyles: [StoryMusicStyle] {
        StoryMusicStyle.allCases.filter { $0 != .lyrics }
    }

    var body: some View {
        VStack(spacing: 0) {
            trackButton.padding(.top, canvasTop + 62)
            Spacer().allowsHitTesting(false)
            controls.padding(.bottom, max(bottomInset, 12) + 40)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .task(id: playbackRevision) { await preparePlayback() }
        .onDisappear { audio.stop(); onPlaybackChanged(false) }
        .onChange(of: audio.isPlaying) { _, value in onPlaybackChanged(value) }
        .onChange(of: sticker.interactionData?.music?.colorHex) { _, hex in
            guard let hex, selection.colorHex != hex else { return }
            selection.colorHex = hex
            updateSticker()
        }
        .onChange(of: sticker.interactionData?.music?.cardStyleVariant) { _, variant in
            guard selection.cardStyleVariant != variant else { return }
            selection.cardStyleVariant = variant
            updateSticker()
        }
        .sheet(isPresented: $showingCatalog) {
            StoryMusicPicker(existing: selection, storyDuration: selection.duration,
                             onApply: { value, image in
                var replacement = value
                replacement.colorHex = selection.colorHex
                replacement.cardStyleVariant = selection.cardStyleVariant
                replacement.style = selection.style
                selection = replacement
                artwork = image
                updateSticker()
                showingCatalog = false
                playbackRevision = UUID()
            }, onRemove: {})
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var trackButton: some View {
        Button { audio.pause(); showingCatalog = true } label: {
            HStack(spacing: 8) {
                AsyncImage(url: selection.track.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Image(systemName: "music.note") }
                    .frame(width: 28, height: 28).clipShape(.rect(cornerRadius: 6))
                Text(selection.track.title).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .momentsChromeGlass(in: Capsule(), interactive: true, style: .tinted)
        }.buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(availableStyles) { style in styleButton(style) }
                }
                .frame(minWidth: max(canvasSize.width - 32, 0))
                .padding(.horizontal, 16)
            }.scrollIndicators(.hidden)
            ZStack {
                Text("\(time(selection.start)) – \(time(selection.start + selection.duration))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                HStack {
                    durationControl
                    Spacer()
                    Button { audio.isPlaying ? audio.pause() : audio.play() } label: {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 44, height: 44).foregroundStyle(.black).background(.white, in: Circle())
                    }
                    .disabled(loading || failed)
                    .accessibilityLabel(NSLocalizedString("story.music.preview", comment: "Preview"))
                }
            }.padding(.horizontal, 24)
            songTimeline.padding(.horizontal, 24)
            waveformContent.frame(height: 64)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var durationControl: some View {
        let maximum = max(15, Int(min(selection.track.duration, 60).rounded(.down)))
        if allowsDurationSelection, selection.track.duration >= 15 {
            Button { showingDurationPicker = true } label: {
                HStack(spacing: 5) {
                    Text(time(selection.duration)).font(.caption.monospacedDigit())
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .momentsChromeGlass(in: Capsule(), interactive: false, style: .tinted)
            }
            .buttonStyle(.plain)
            .disabled(loading || failed)
            .popover(isPresented: $showingDurationPicker) {
                Picker(NSLocalizedString("story.music.fragment", comment: "Selected fragment"), selection: Binding(
                    get: { Int(selection.duration.rounded()) },
                    set: { seconds in
                        var fragment = selection
                        fragment.clamp(to: Double(seconds))
                        fragmentBinding.wrappedValue = fragment
                    }
                )) {
                    ForEach(15...maximum, id: \.self) { seconds in
                        Text(time(Double(seconds))).tag(seconds)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 180, height: 216)
                .presentationCompactAdaptation(.popover)
            }
        } else {
            Text(time(selection.duration)).font(.caption.monospacedDigit())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
        }
    }

    private var songTimeline: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let total = max(selection.track.duration, 0.1)
                let startX = proxy.size.width * CGFloat(selection.start / total)
                let span = proxy.size.width * CGFloat(selection.duration / total)
                let cursorX = proxy.size.width * CGFloat((selection.start + min(max(audio.elapsed, 0), selection.duration)) / total)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2)).frame(height: 3)
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: max(span, 6), height: 7)
                        .offset(x: startX)
                    Circle().fill(.white).frame(width: 10, height: 10)
                        .offset(x: min(max(cursorX - 5, 0), max(proxy.size.width - 10, 0)))
                    Slider(value: Binding(
                        get: { selection.start },
                        set: { value in
                            var fragment = selection
                            fragment.start = min(value, max(selection.track.duration - selection.duration, 0))
                            fragmentBinding.wrappedValue = fragment
                        }
                    ), in: 0...max(selection.track.duration - selection.duration, 0.1), onEditingChanged: { editing in
                        if editing { audio.pause() } else { audio.play() }
                    })
                    .opacity(0.01)
                    .disabled(loading || failed)
                    .accessibilityLabel(NSLocalizedString("story.music.fragment", comment: "Selected fragment"))
                }
                .frame(height: 44)
            }
            .frame(height: 44)
            HStack {
                Text(time(0))
                Spacer()
                Text(time(selection.track.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.65))
        }
    }

    @ViewBuilder
    private var waveformContent: some View {
        if waveformLoading {
            ProgressView().tint(.white)
                .frame(maxWidth: .infinity)
        } else if waveformFailed {
            Button(NSLocalizedString("story.music.retry", comment: "Retry")) {
                Task {
                    if failed { await preparePlayback() } else { await loadWaveform() }
                }
            }.font(.caption).frame(maxWidth: .infinity)
        } else if selection.track.waveform?.isEmpty == false {
            StoryMusicWaveform(track: selection.track, selection: fragmentBinding,
                               playing: audio.isPlaying, progress: audio.elapsed,
                               onScrubbing: { scrubbing in
                if scrubbing { audio.pause() } else { audio.play() }
            })
        } else {
            ProgressView().tint(.white).frame(maxWidth: .infinity)
        }
    }

    private func styleButton(_ style: StoryMusicStyle) -> some View {
        let selected = selection.style == style
        let foreground = selected
            ? AnyShapeStyle(StoryMusicWaveform.selectionGradient)
            : AnyShapeStyle(Color.white)
        let traits: AccessibilityTraits = selected ? .isSelected : []
        return Button {
            selection.style = style
            updateSticker()
        } label: {
            Group {
                if let asset = style.iconAsset {
                    Image(asset).renderingMode(.template)
                        .resizable().scaledToFit()
                } else {
                    Image(systemName: style.symbol)
                        .resizable().scaledToFit()
                }
            }
            .frame(width: 24, height: 24)
            .foregroundStyle(foreground)
            .frame(width: 44, height: 44)
            .momentsChromeGlass(in: Circle(), interactive: true, style: .tinted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(traits)
    }

    private var fragmentBinding: Binding<StoryMusicSelection> {
        Binding(get: { selection }, set: {
            selection = $0
            audio.update($0)
            persistSelection()
        })
    }

    @MainActor
    private func updateSticker() {
        guard let image = StoryMusicStickerRenderer.image(selection, artwork: artwork, colorScheme: colorScheme) else { return }
        sticker = replacingImage(image, data: persistedData())
    }

    private func persistedData() -> StickerItem.StickerInteractionData {
        var value = selection
        value.rasterScale = Double(StoryMusicStickerRenderer.rasterScale)
        value.track.waveform = nil
        value.track.previewURL = nil
        var data = sticker.interactionData ?? .init()
        data.music = value
        return data
    }

    private func persistSelection() {
        sticker.interactionData = persistedData()
    }

    @MainActor
    private func preparePlayback() async {
        audio.stop()
        loading = true
        failed = false
        let trackID = selection.track.id
        let revision = playbackRevision
        defer { if playbackRevision == revision { loading = false } }
        do {
            let resolved = try await StoryMusicCatalog.resolve(trackId: trackID)
            guard !Task.isCancelled, selection.track.id == trackID, playbackRevision == revision else { return }
            selection.track = resolved
            selection.clamp(to: selection.duration)
            if selection.style == .lyrics { selection.style = .card }
            selection.lyricText = selection.lyricText ?? resolved.lyrics?.components(separatedBy: .newlines).first(where: { !$0.isEmpty })
            guard let url = resolved.previewURL else { failed = true; waveformFailed = true; return }
            audio.load(selection, url: url, play: true)
            loading = false
            if let artURL = resolved.artworkURL,
               let (data, _) = try? await URLSession.shared.data(from: artURL) {
                guard !Task.isCancelled, selection.track.id == trackID, playbackRevision == revision else { return }
                artwork = UIImage(data: data)
            }
            updateSticker()
            await loadWaveform()
        } catch {
            guard !Task.isCancelled, selection.track.id == trackID, playbackRevision == revision else { return }
            failed = true
            waveformFailed = true
        }
    }

    @MainActor
    private func loadWaveform() async {
        let revision = playbackRevision
        guard let url = selection.track.previewURL else { waveformFailed = true; return }
        waveformLoading = true
        waveformFailed = false
        defer { if playbackRevision == revision { waveformLoading = false } }
        do {
            let peaks = try await StoryMusicWaveformLoader.load(url: url, duration: selection.track.duration)
            guard !Task.isCancelled, playbackRevision == revision else { return }
            guard !peaks.isEmpty else { waveformFailed = true; return }
            selection.track.waveform = peaks
        } catch {
            guard !Task.isCancelled, playbackRevision == revision else { return }
            waveformFailed = true
        }
    }

    private func replacingImage(_ image: UIImage, data: StickerItem.StickerInteractionData?) -> StickerItem {
        StickerItem(id: sticker.id, image: image, position: sticker.position,
                    scale: sticker.scale, rotation: sticker.rotation, zIndex: sticker.zIndex,
                    gifURL: sticker.gifURL, videoURL: sticker.videoURL, isAnimated: sticker.isAnimated,
                    type: sticker.type, interactionData: data)
    }

    private func cancel() {
        audio.stop()
        // The shared focus owner restores the transform when editing closes.
        sticker = replacingImage(original.image, data: original.interactionData)
        onDone()
    }

    private func time(_ value: Double) -> String {
        String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}
