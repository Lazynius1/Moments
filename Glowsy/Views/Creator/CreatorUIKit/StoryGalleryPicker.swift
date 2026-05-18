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
    @State private var showingVideoLengthAlert = false
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
                            let asset = AVAsset(url: videoURL)
                            asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                                DispatchQueue.main.async {
                                    let duration = CMTimeGetSeconds(asset.duration)

                                    if duration <= 60.0 {
                                        let imageGenerator = AVAssetImageGenerator(asset: asset)
                                        imageGenerator.appliesPreferredTrackTransform = true
                                        imageGenerator.maximumSize = CGSize(width: 300, height: 300)

                                        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                                        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { requestedTime, cgImage, actualTime, result, error in
                                            DispatchQueue.main.async {
                                                let thumbnail: UIImage
                                                if let cgImage = cgImage {
                                                    thumbnail = UIImage(cgImage: cgImage)
                                                } else {
                                                    thumbnail = UIImage(systemName: "video.fill") ?? UIImage()
                                                }

                                                let media = CreatorMedia(
                                                    id: UUID().uuidString,
                                                    image: thumbnail,
                                                    videoURL: videoURL,
                                                    type: .video,
                                                    aspectRatio: .nineBySixteen,
                                                    recommendedAspectRatio: .nineBySixteen
                                                )
                                                onSelect(media)
                                                dismiss()
                                            }
                                        }
                                    } else {
                                        videoDuration = duration
                                        showingVideoLengthAlert = true
                                    }
                                }
                            }
                        }
                    }
                )
            }
            .alert("creator.video.length.title", isPresented: $showingVideoLengthAlert) {
                Button("common.understood") {
                    showingVideoLengthAlert = false
                }
            } message: {
                Text(String(format: NSLocalizedString("creator.video.length.warning", comment: "Video length warning"), String(format: "%.0f", videoDuration)))
            }
            .overlay(
                Group {
                    if authorizationStatus == .denied || authorizationStatus == .restricted {
                        permissionDeniedOverlay
                    }
                }
            )
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
}
