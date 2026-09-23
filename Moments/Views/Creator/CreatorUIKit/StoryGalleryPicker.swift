import AVFoundation
import Photos
import SwiftUI

struct StoryGalleryPicker: View {
    let onSelect: (CreatorMedia) -> Void
    /// En el Duo abierto en horizontal la galería vive en la otra pantalla, no en un sheet.
    var inline: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(onSelect: @escaping (CreatorMedia) -> Void, inline: Bool = false) {
        self.onSelect = onSelect
        self.inline = inline
    }

    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showingMediaPicker = false
    @State private var showingLongVideoDecision = false
    @State private var showingTrimEditor = false
    @State private var showingVideoTooLongAlert = false
    @State private var pendingLongVideoMedia: CreatorMedia?
    @State private var videoDuration: Double = 0
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @StateObject private var photosGate = PermissionPrimerGate(.photos)

    var body: some View {
        Group {
            if inline {
                inlinePicker
            } else {
                Color.clear
            }
        }
            .onAppear {
                resolvePhotoLibraryAccess()
            }
            .onChange(of: authorizationStatus) { _, newStatus in
                guard !inline else { return }
                if (newStatus == .authorized || newStatus == .limited) && !showingMediaPicker {
                    presentMediaPickerSoon()
                }
            }
            .onChange(of: photosGate.isPresenting) { _, presenting in
                guard !presenting else { return }
                authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if authorizationStatus != .authorized && authorizationStatus != .limited {
                    closeIfSheet()
                }
            }
            .permissionPrimerGate(photosGate)
            .sheet(isPresented: $showingMediaPicker) {
                StoryMediaPicker(
                    selectedImage: $selectedImage,
                    selectedVideoURL: $selectedVideoURL,
                    onSelect: { image, videoURL in
                        if let image = image {
                            let media = CreatorMedia(
                                id: UUID().uuidString,
                                image: image,
                                videoURL: nil,
                                type: .image,
                                aspectRatio: .nineBySixteen,
                                recommendedAspectRatio: .nineBySixteen
                            )
                            onSelect(media)
                            closeIfSheet()
                        } else if let videoURL = videoURL {
                            Task {
                                await handleSelectedVideo(videoURL)
                            }
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingTrimEditor) {
                if let media = pendingLongVideoMedia, let videoURL = media.videoURL {
                    StoryVideoTrimEditorView(
                        videoURL: videoURL,
                        duration: videoDuration,
                        onCancel: {
                            showingTrimEditor = false
                            showingLongVideoDecision = true
                        },
                        onComplete: { trimmedMedia in
                            showingTrimEditor = false
                            onSelect(trimmedMedia)
                            closeIfSheet()
                        }
                    )
                }
            }
            .alert("storyVideo.tooLong.title", isPresented: $showingVideoTooLongAlert) {
                Button("common.understood") {
                    showingVideoTooLongAlert = false
                    showingMediaPicker = true
                }
            } message: {
                Text(String(
                    format: NSLocalizedString("storyVideo.tooLong.message", comment: "Story video exceeds maximum gallery duration message"),
                    formatDuration(videoDuration),
                    formatDuration(StoryVideoProcessingService.maxAutoSplitDuration)
                ))
            }
            .overlay(
                Group {
                    if authorizationStatus == .denied || authorizationStatus == .restricted {
                        permissionDeniedOverlay
                    }
                }
            )
            .overlay {
                if showingLongVideoDecision, let media = pendingLongVideoMedia {
                    StoryLongVideoDecisionOverlay(
                        duration: videoDuration,
                        partCount: Int(ceil(videoDuration / StoryVideoProcessingService.maxStorySegmentDuration)),
                        canAutoSplit: videoDuration <= StoryVideoProcessingService.maxAutoSplitDuration,
                        thumbnail: media.image,
                        onConfirmSplit: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                showingLongVideoDecision = false
                            }
                            onSelect(media.with(storyVideoMode: .autoSplit, videoDuration: videoDuration))
                            closeIfSheet()
                        },
                        onEdit: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                showingLongVideoDecision = false
                            }
                            showingTrimEditor = true
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                showingLongVideoDecision = false
                            }
                            pendingLongVideoMedia = nil
                            showingMediaPicker = true
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
    }

    private func handleSelectedVideo(_ videoURL: URL) async {
        do {
            let duration = try await StoryVideoProcessingService.shared.duration(for: videoURL)
            let thumbnail = (try? await StoryVideoProcessingService.shared.generateStoryThumbnail(videoURL: videoURL, time: 0.1))
                ?? UIImage(systemName: "video.fill")
                ?? UIImage()
            let media = CreatorMedia(
                id: UUID().uuidString,
                image: thumbnail,
                videoURL: videoURL,
                type: .video,
                aspectRatio: .nineBySixteen,
                recommendedAspectRatio: .nineBySixteen,
                videoDuration: duration
            )

            await MainActor.run {
                videoDuration = duration
                if duration > StoryVideoProcessingService.maxAutoSplitDuration {
                    pendingLongVideoMedia = nil
                    showingMediaPicker = false
                    showingVideoTooLongAlert = true
                } else if duration <= StoryVideoProcessingService.maxStorySegmentDuration {
                    onSelect(media)
                    closeIfSheet()
                } else {
                    pendingLongVideoMedia = media
                    showingMediaPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            showingLongVideoDecision = true
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                showingMediaPicker = true
            }
        }
    }

    private func resolvePhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch authorizationStatus {
        case .authorized, .limited:
            if !inline { presentMediaPickerSoon() }
        case .notDetermined:
            photosGate.requestAccess {
                authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if authorizationStatus == .authorized || authorizationStatus == .limited {
                    presentMediaPickerSoon()
                }
            }
        default:
            break
        }
    }

    private func presentMediaPickerSoon() {
        guard !inline else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showingMediaPicker = true
        }
    }

    @ViewBuilder
    private var inlinePicker: some View {
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            StoryMediaPicker(
                selectedImage: $selectedImage,
                selectedVideoURL: $selectedVideoURL,
                onSelect: { image, videoURL in
                    if let image = image {
                        let media = CreatorMedia(
                            id: UUID().uuidString,
                            image: image,
                            videoURL: nil,
                            type: .image,
                            aspectRatio: .nineBySixteen,
                            recommendedAspectRatio: .nineBySixteen
                        )
                        onSelect(media)
                    } else if let videoURL = videoURL {
                        Task {
                            await handleSelectedVideo(videoURL)
                        }
                    }
                }
            )
        } else {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
        }
    }

    private func closeIfSheet() {
        guard !inline else { return }
        dismiss()
    }

    private var permissionDeniedOverlay: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                AttachmentIconView(
                    icon: .photos,
                    preset: .permissionPromptLarge,
                    tintColor: colorScheme == .dark ? .gray : .gray.opacity(0.6)
                )

                Text("creator.gallery.permission")
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    Text("creator.permissions.instructions.title")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text("creator.permissions.instructions.path")
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(colorScheme == .dark ? .gray : .gray.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Button("creator.permissions.openSettings") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple, Color.pink]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }

                Button("common.close") {
                    closeIfSheet()
                }
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .gray : .gray.opacity(0.7))
            }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct StoryLongVideoDecisionOverlay: View {
    let duration: Double
    let partCount: Int
    let canAutoSplit: Bool
    let thumbnail: UIImage
    let onConfirmSplit: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color.black.opacity(0.86)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.58)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.5)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.34 : 0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 82)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("storyVideo.long.title")
                            .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                        Text(decisionMessage)
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if canAutoSplit {
                    Text("storyVideo.long.revealHint")
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(tertiaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 18) {
                    Button(action: onCancel) {
                        Text("common.cancel")
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(MomentRowButtonStyle())

                    Spacer()

                    Button(action: onEdit) {
                        Label("storyVideo.long.edit", systemImage: "slider.horizontal.3")
                            .padding(.horizontal, 4)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(MomentRowButtonStyle())

                    if canAutoSplit {
                        Button(action: onConfirmSplit) {
                            Label("storyVideo.long.confirm", systemImage: "scissors")
                                .padding(.horizontal, 4)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(MomentRowButtonStyle())
                    }
                }
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundStyle(primaryTextColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false)
            .padding(.horizontal, 18)
        }
    }

    private var decisionMessage: String {
        if canAutoSplit {
            return String(
                format: NSLocalizedString("storyVideo.long.message", comment: "Long story video message"),
                formatDuration(duration),
                partCount
            )
        }

        return String(
            format: NSLocalizedString("storyVideo.long.tooLongForSplit", comment: "Story video too long for automatic split message"),
            formatDuration(duration),
            formatDuration(StoryVideoProcessingService.maxAutoSplitDuration),
            StoryVideoProcessingService.maxAutoSplitPartCount
        )
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
