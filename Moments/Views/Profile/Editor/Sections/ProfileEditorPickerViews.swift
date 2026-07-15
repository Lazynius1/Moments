import SwiftUI
import PhotosUI
import FirebaseAuth
import Photos
import Kingfisher

struct ProfileAlbumPickerView: View {
    let albums: [ProfileAlbumInfo]
    let selectedAlbum: ProfileAlbumInfo?
    let onAlbumSelected: (ProfileAlbumInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var albumThumbnails: [String: UIImage] = [:]

    private let imageManager = PHImageManager.default()

    var body: some View {
        VStack(spacing: 0) {
            // Header estilo Creator
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            HStack {
                Text(NSLocalizedString("profileEditor.album.selectTitle", comment: ""))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(albums) { album in
                        ProfileAlbumRowView(
                            album: album,
                            thumbnail: albumThumbnails[album.id],
                            isSelected: selectedAlbum?.id == album.id
                        ) {
                            onAlbumSelected(album)
                        }
                        .onAppear {
                            loadAlbumThumbnail(for: album)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "00A896").opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .presentationBackground(.clear)
    }

    private func loadAlbumThumbnail(for album: ProfileAlbumInfo) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(in: album.assetCollection, options: fetchOptions)
        guard let firstAsset = assets.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false

        imageManager.requestImage(
            for: firstAsset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    albumThumbnails[album.id] = image
                }
            }
        }
    }
}

// MARK: - Local Album Row for Profile Editor
struct ProfileAlbumRowView: View {
    let album: ProfileAlbumInfo
    let thumbnail: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Miniatura
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 64, height: 64)

                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(String(format: NSLocalizedString("profileEditor.album.photosCount", comment: ""), album.assetCount))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.gray)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "00A896"))
                        .font(.title3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ProfileLibraryCropEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onImageCropped: (UIImage) -> Void

    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var initialAsset: PHAsset?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let initialAsset {
                PhotoCropEditorView(originalAsset: initialAsset) { croppedImage in
                    onImageCropped(croppedImage)
                }
            } else if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(colorScheme == .dark ? .white : .black)
                    Text("profileEditor.loadingPhotos")
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.75) : .black.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                    Text("profileEditor.photosAccess.title")
                        .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text("profileEditor.photosAccess.description")
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Button("creator.permissions.openSettings") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Text("profileEditor.photosAccess.title")
                        .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Button(NSLocalizedString("profileEditor.allowAccess", comment: "")) {
                        requestPermission()
                    }
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadInitialAsset()
        }
    }

    private func loadInitialAsset() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status

        switch status {
        case .authorized, .limited:
            fetchMostRecentAsset()
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            isLoading = false
        @unknown default:
            isLoading = false
        }
    }

    private func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                authorizationStatus = status
                if status == .authorized || status == .limited {
                    fetchMostRecentAsset()
                } else {
                    isLoading = false
                }
            }
        }
    }

    private func fetchMostRecentAsset() {
        isLoading = true

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        DispatchQueue.main.async {
            initialAsset = fetchResult.firstObject
            isLoading = false
            if initialAsset == nil {
                dismiss()
            }
        }
    }
}
