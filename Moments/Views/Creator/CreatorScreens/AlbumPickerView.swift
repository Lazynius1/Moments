import Photos
import SwiftUI

struct AlbumInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let assetCollection: PHAssetCollection
    let assetCount: Int

    static func == (lhs: AlbumInfo, rhs: AlbumInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct AlbumPickerView: View {
    let albums: [AlbumInfo]
    let selectedAlbum: AlbumInfo?
    let onAlbumSelected: (AlbumInfo) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var albumThumbnails: [String: UIImage] = [:]

    private let imageManager = PHImageManager.default()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            albumListView
            cancelButton
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
                                    Color.pink.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 20, x: 0, y: 10)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(false)
        .presentationBackground(.clear)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var headerView: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.6))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Text(NSLocalizedString("creator.album.select", comment: "Select Album"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .padding(.bottom, 20)
        }
    }

    private var albumListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(albums) { album in
                    AlbumRowView(
                        album: album,
                        thumbnail: albumThumbnails[album.id],
                        isSelected: selectedAlbum?.id == album.id,
                        onTap: {
                            onAlbumSelected(album)
                        }
                    )
                    .onAppear {
                        loadAlbumThumbnail(for: album)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var cancelButton: some View {
        Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
            withAnimation(.easeOut(duration: 0.3)) {
                dismiss()
            }
        }
        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
        .foregroundStyle(colorScheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private func loadAlbumThumbnail(for album: AlbumInfo) {
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
            targetSize: CGSize(width: 150, height: 150),
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

private struct AlbumRowView: View {
    let album: AlbumInfo
    let thumbnail: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)

                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundStyle(.gray)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(String(format: NSLocalizedString("creator.album.elements", comment: "Album elements"), album.assetCount))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(.gray.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "00A896"))
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color(hex: "00A896").opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
