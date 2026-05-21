import AVFoundation
import Photos
import SwiftUI

struct StoryGalleryPicker: View {
    let onSelect: (CreatorMedia) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var showingMediaPicker = false
    @State private var showingLongVideoDecision = false
    @State private var showingTrimEditor = false
    @State private var showingVideoTooLongAlert = false
    @State private var pendingLongVideoMedia: CreatorMedia?
    @State private var videoDuration: Double = 0
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined

    var body: some View {
        Color.clear
            .onAppear {
                checkPhotoLibraryPermission()

                if authorizationStatus == .authorized || authorizationStatus == .limited || authorizationStatus == .notDetermined {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingMediaPicker = true
                    }
                }
            }
            .onChange(of: authorizationStatus) { newStatus in
                if (newStatus == .authorized || newStatus == .limited) && !showingMediaPicker {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingMediaPicker = true
                    }
                }
            }
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
                            dismiss()
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
                            dismiss()
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
                            dismiss()
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
                    dismiss()
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

    private func checkPhotoLibraryPermission() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                }
            }
        }
    }

    private var permissionDeniedOverlay: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 60))
                    .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.6))

                Text("creator.gallery.permission")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    Text("creator.permissions.instructions.title")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("creator.permissions.instructions.path")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Button("creator.permissions.openSettings") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
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
                    dismiss()
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
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
                            .font(.custom("Poppins-SemiBold", size: 17))
                            .foregroundColor(primaryTextColor)
                        Text(decisionMessage)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if canAutoSplit {
                    Text("storyVideo.long.revealHint")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(tertiaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 18) {
                    Button(action: onCancel) {
                        Text("common.cancel")
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(secondaryTextColor)
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
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(primaryTextColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false)
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
