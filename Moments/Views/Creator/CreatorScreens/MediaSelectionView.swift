// MARK: - Media Selection View
import SwiftUI
import Photos
import AVFoundation
import UIKit

struct MediaSelectionView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    var animation: Namespace.ID // ✅ Accept Namespace

    @Environment(\.colorScheme) var colorScheme

    @State private var mediaAssets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedAssetIDs: [String] = []
    @State private var isLoadingLibrary = true
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @StateObject private var photosGate = PermissionPrimerGate(.photos)
    @State private var showingVideoTooLongAlert = false
    @State private var rejectedVideoDuration: TimeInterval = 0

    // ✅ Estados para manejo de álbumes
    @State private var availableAlbums: [AlbumInfo] = []
    @State private var selectedAlbum: AlbumInfo?
    @State private var showingAlbumPicker = false
    @State private var cropSessions: [String: AssetCropSession] = [:]
    @State private var cropWindowSizes: [String: CGSize] = [:]
    @State private var previewImages: [String: UIImage] = [:]
    @State private var isMultiSelect = false

    private let imageManager = PHImageManager.default()
    private let thumbnailSize = CGSize(width: 300, height: 300)
    private let columns = [GridItem(.adaptive(minimum: 86, maximum: 150), spacing: 1)]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                headerView
                mainPreviewSection
                    .frame(width: geo.size.width, height: previewHeight(in: geo.size))
                mediaGridSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
        .matchedGeometryEffect(id: "momentSource", in: animation) // ✅ Unfold Target
        .onAppear {
#if DEBUG
            MomentFeedCrop.validateDebugContract()
#endif
            requestPhotoLibraryAccess()
        }
        .onChange(of: selectedAssetIDs.last) { _, id in
            guard let id,
                  let asset = mediaAssets.first(where: { $0.localIdentifier == id }) else { return }
            ensureCropSession(for: asset)
            loadPreviewImage(for: asset)
        }
        .permissionPrimerGate(photosGate)
        .alert("momentVideo.tooLong.title", isPresented: $showingVideoTooLongAlert) {
            Button("common.understood") {
                showingVideoTooLongAlert = false
            }
        } message: {
            Text(String(
                format: NSLocalizedString("momentVideo.tooLong.message", comment: "Moment video exceeds maximum duration message"),
                formatDuration(rejectedVideoDuration),
                formatDuration(CreatorMedia.maxMomentVideoDuration)
            ))
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                currentFlow = .typeSelection
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 40)
            }

            Spacer()

            Text(NSLocalizedString("creator.newMoment", comment: ""))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            Spacer()

            if !selectedAssetIDs.isEmpty {
                Button(action: processSelectedAssets) {
                    Text(NSLocalizedString("creator.next", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "0095F6"))
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea(edges: .top)
        )
        .zIndex(10)
    }

    // MARK: - Preview principal
    private var mainPreviewSection: some View {
        VStack(spacing: 0) {
            let currentAssetID = selectedAssetIDs.last
            let currentAsset = currentAssetID.flatMap { id in
                mediaAssets.first(where: { $0.localIdentifier == id })
            }
            MomentFeedCropCanvas(
                image: currentAssetID.flatMap { previewImages[$0] },
                isVideo: currentAsset?.mediaType == .video,
                videoDurationText: currentAsset.map { formatDuration($0.duration) },
                session: currentCropSession(for: currentAsset),
                cropAspect: sharedCropAspect,
                onSessionChange: { session in
                    if let id = currentAssetID {
                        cropSessions[id] = session
                    }
                },
                showsAspectToggle: currentAssetID != nil && currentAssetID == selectedAssetIDs.first,
                onWindowSizeChange: { size in
                    if let id = currentAssetID {
                        cropWindowSizes[id] = size
                    }
                }
            )
            .id(currentAssetID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Grid de medios
    private var mediaGridSection: some View {
        VStack(spacing: 0) {
            // Separador
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)

            // Header con selector de álbum
            HStack(spacing: 12) {
                Button(action: {
                    showingAlbumPicker = true
                }) {
                    HStack(spacing: 4) {
                        Text(selectedAlbum?.title ?? NSLocalizedString("creator.album.recents", comment: "Recents"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .rotationEffect(.degrees(showingAlbumPicker ? 180 : 0))
                    }
                }

                Spacer()

                Button {
                    isMultiSelect.toggle()
                    if !isMultiSelect, let current = selectedAssetIDs.last {
                        selectedAssetIDs = [current]
                    }
                } label: {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isMultiSelect ? Color(hex: "0B1215") : (colorScheme == .dark ? .white : .black))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(isMultiSelect ? Color.white : (colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)))
                        )
                }
                .accessibilityLabel(Text("creator.multiple"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))

            // Grid de fotos
            if isLoadingLibrary {
                loadingView
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                permissionDeniedView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(mediaAssets, id: \.localIdentifier) { asset in
                            MediaGridCell(
                                asset: asset,
                                thumbnail: thumbnails[asset.localIdentifier],
                                isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                isMultiSelect: isMultiSelect,
                                selectionNumber: isMultiSelect
                                    ? selectedAssetIDs.firstIndex(of: asset.localIdentifier).map { $0 + 1 }
                                    : nil,
                                onTap: { toggleAssetSelection(asset) }
                            )
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showingAlbumPicker) {
            AlbumPickerView(
                albums: availableAlbums,
                selectedAlbum: selectedAlbum,
                onAlbumSelected: { album in
                    selectedAlbum = album
                    showingAlbumPicker = false
                    loadMediaFromAlbum(album)
                }
            )
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color(hex: "007AFF"))

                            Text("creator.gallery.loading")
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(50)
    }

    // MARK: - Funciones

    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if authorizationStatus == .notDetermined {
            photosGate.requestAccess {
                authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                loadAvailableAlbums()
                loadMediaFromLibrary()
            }
        } else if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAvailableAlbums()
            loadMediaFromLibrary()
        } else {
            isLoadingLibrary = false
        }
    }

    private func loadAvailableAlbums() {
        var albums: [AlbumInfo] = []

        // Álbum "Recientes" (Camera Roll)
        let recentsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumUserLibrary,
            options: nil
        )

        recentsFetchResult.enumerateObjects { collection, _, _ in
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            if assetCount > 0 {
                albums.append(AlbumInfo(
                    id: collection.localIdentifier,
                    title: NSLocalizedString("creator.album.recents", comment: "Recents"),
                    assetCollection: collection,
                    assetCount: assetCount
                ))
            }
        }

        // Álbumes del usuario
        let userAlbumsFetchResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        userAlbumsFetchResult.enumerateObjects { collection, _, _ in
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            if assetCount > 0 {
                albums.append(AlbumInfo(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? NSLocalizedString("creator.album.untitled", comment: "Untitled album"),
                    assetCollection: collection,
                    assetCount: assetCount
                ))
            }
        }

        // Álbumes inteligentes adicionales
        let smartAlbumTypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
            .smartAlbumSelfPortraits,
            .smartAlbumVideos,
            .smartAlbumRecentlyAdded
        ]

        for subtype in smartAlbumTypes {
            let smartAlbumFetchResult = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )

            smartAlbumFetchResult.enumerateObjects { collection, _, _ in
                let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
                if assetCount > 0 {
                    let title = collection.localizedTitle ?? getSmartAlbumTitle(for: subtype)
                    albums.append(AlbumInfo(
                        id: collection.localIdentifier,
                        title: title,
                        assetCollection: collection,
                        assetCount: assetCount
                    ))
                }
            }
        }

        // Ordenar álbumes
        albums.sort { first, second in
            if first.title == NSLocalizedString("creator.album.recents", comment: "Recents") { return true }
            if second.title == NSLocalizedString("creator.album.recents", comment: "Recents") { return false }
            return first.assetCount > second.assetCount
        }

        DispatchQueue.main.async {
            self.availableAlbums = albums
            self.selectedAlbum = albums.first
        }
    }

    private func getSmartAlbumTitle(for subtype: PHAssetCollectionSubtype) -> String {
        switch subtype {
        case .smartAlbumFavorites: return NSLocalizedString("creator.album.smart.favorites", comment: "Favorites")
        case .smartAlbumScreenshots: return NSLocalizedString("creator.album.smart.screenshots", comment: "Screenshots")
        case .smartAlbumSelfPortraits: return NSLocalizedString("creator.album.smart.selfies", comment: "Selfies")
        case .smartAlbumVideos: return NSLocalizedString("creator.album.smart.videos", comment: "Videos")
        case .smartAlbumRecentlyAdded: return NSLocalizedString("creator.album.smart.recentlyAdded", comment: "Recently added")
        default: return NSLocalizedString("creator.album.default", comment: "Album")
        }
    }

    private func loadMediaFromAlbum(_ album: AlbumInfo) {
        isLoadingLibrary = true
        mediaAssets = []
        thumbnails = [:]
        selectedAssetIDs = []
        cropSessions = [:]
        previewImages = [:]

        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            // Mantiene el mismo máximo que la biblioteca principal y Android.
            // Sin este límite, abrir un álbum grande materializaba toda su
            // colección antes de que el grid pudiera mostrar los primeros ítems.
            fetchOptions.fetchLimit = 500

            let assets = PHAsset.fetchAssets(in: album.assetCollection, options: fetchOptions)
            var assetArray: [PHAsset] = []

            assets.enumerateObjects { asset, _, _ in
                assetArray.append(asset)
            }

            await MainActor.run {
                self.mediaAssets = assetArray
                loadThumbnails()
                autoSelectFirstIfNeeded()
            }
        }
    }

    private func loadMediaFromLibrary() {
        isLoadingLibrary = true

        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 500

            let assets = PHAsset.fetchAssets(with: fetchOptions)
            var assetArray: [PHAsset] = []

            assets.enumerateObjects { asset, _, _ in
                assetArray.append(asset)
            }

            await MainActor.run {
                self.mediaAssets = assetArray
                loadThumbnails()
                autoSelectFirstIfNeeded()
            }
        }
    }

    private func loadThumbnails() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        for asset in mediaAssets.prefix(50) {
            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image {
                    DispatchQueue.main.async {
                        self.thumbnails[asset.localIdentifier] = image

                        if self.thumbnails.count == 20 && self.isLoadingLibrary {
                            self.isLoadingLibrary = false
                        }
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if isLoadingLibrary {
                isLoadingLibrary = false
            }
        }

        DispatchQueue.global(qos: .background).async {
            for asset in mediaAssets.dropFirst(50) {
                imageManager.requestImage(
                    for: asset,
                    targetSize: thumbnailSize,
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    if let image = image {
                        DispatchQueue.main.async {
                            self.thumbnails[asset.localIdentifier] = image
                        }
                    }
                }
            }
        }
    }

    private var sharedCropAspect: CGFloat {
        guard let id = selectedAssetIDs.first else { return MomentFeedCrop.squareAspect }
        if let session = cropSessions[id] {
            return session.cropAspect
        }
        return MomentFeedCrop.squareAspect
    }

    private func previewHeight(in size: CGSize) -> CGFloat {
        size.width
    }

    private func currentCropSession(for asset: PHAsset?) -> AssetCropSession {
        guard let asset else { return AssetCropSession(pixelWidth: 1, pixelHeight: 1) }
        return cropSessions[asset.localIdentifier]
            ?? AssetCropSession(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
    }

    private func ensureCropSession(for asset: PHAsset) {
        if cropSessions[asset.localIdentifier] == nil {
            cropSessions[asset.localIdentifier] = AssetCropSession(
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            )
        }
    }

    private func autoSelectFirstIfNeeded() {
        guard selectedAssetIDs.isEmpty else { return }
        guard let firstEligible = mediaAssets.first(where: { asset in
            asset.mediaType != .video || asset.duration <= CreatorMedia.maxMomentVideoDuration
        }) else { return }
        ensureCropSession(for: firstEligible)
        selectedAssetIDs = [firstEligible.localIdentifier]
        loadPreviewImage(for: firstEligible)
    }

    private func toggleAssetSelection(_ asset: PHAsset) {
        let assetID = asset.localIdentifier

        if asset.mediaType == .video, asset.duration > CreatorMedia.maxMomentVideoDuration,
           !selectedAssetIDs.contains(assetID) {
            rejectedVideoDuration = asset.duration
            showingVideoTooLongAlert = true
            return
        }

        if isMultiSelect {
            if selectedAssetIDs.contains(assetID) {
                if selectedAssetIDs.count == 1 { return }
                selectedAssetIDs.removeAll { $0 == assetID }
            } else if selectedAssetIDs.count < 20 {
                selectedAssetIDs.append(assetID)
                ensureCropSession(for: asset)
                loadPreviewImage(for: asset)
            }
        } else {
            if selectedAssetIDs == [assetID] { return }
            selectedAssetIDs = [assetID]
            ensureCropSession(for: asset)
            loadPreviewImage(for: asset)
        }

        if thumbnails[assetID] == nil {
            loadGridThumbnail(for: asset)
        }
    }

    private func loadGridThumbnail(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = false

        imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let image {
                DispatchQueue.main.async {
                    self.thumbnails[asset.localIdentifier] = image
                }
            }
        }
    }

    private func loadPreviewImage(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = true

        let width = max(asset.pixelWidth, 1)
        let height = max(asset.pixelHeight, 1)
        let maxSide: CGFloat = 1600
        let scale = min(maxSide / CGFloat(width), maxSide / CGFloat(height), 1)
        let target = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)

        imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                return
            }
            guard let image else { return }
            let oriented = image.momentsOrientedUp()
            DispatchQueue.main.async {
                let id = asset.localIdentifier
                self.previewImages[id] = oriented
                var session = self.cropSessions[id]
                    ?? AssetCropSession(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
                session.applyOrientedSize(oriented.size)
                self.cropSessions[id] = session
            }
        }
    }

    // Reemplaza tu función processSelectedAssets() con esta versión mejorada

    private func processSelectedAssets() {
        let cropAspect = sharedCropAspect
        // La preview gestiona el crop sobre el cuadrado; el aspect solo define el export.
        let window = MomentFeedCrop.squareSize
        Task {
            var processedMedia: [ProcessedMedia] = []
            var lockAspect: CGFloat?

            for assetID in selectedAssetIDs {
                guard let asset = mediaAssets.first(where: { $0.localIdentifier == assetID }) else { continue }
                if asset.mediaType == .video, asset.duration > CreatorMedia.maxMomentVideoDuration {
                    await MainActor.run {
                        rejectedVideoDuration = asset.duration
                        selectedAssetIDs.removeAll { $0 == assetID }
                        showingVideoTooLongAlert = true
                    }
                    return
                }

                if asset.mediaType == .image {
                    if let image = await loadFullImage(for: asset) {
                        let session = cropSessions[assetID] ?? AssetCropSession(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
                        processedMedia.append(
                            framedMedia(
                                from: image,
                                assetID: assetID,
                                type: .image,
                                session: session,
                                cropAspect: cropAspect,
                                window: window,
                                sourceWindow: cropWindowSizes[assetID],
                                lockAspect: lockAspect
                            )
                        )
                        if lockAspect == nil {
                            lockAspect = processedMedia.last.map {
                                $0.image.size.width / max($0.image.size.height, 1)
                            }
                        }
                    }
                } else if asset.mediaType == .video {
                    let (thumbnail, videoURL, videoFileSize) = await loadFullVideo(for: asset)

                    let finalImage = thumbnail ?? createVideoPlaceholder()
                    let session = cropSessions[assetID] ?? AssetCropSession(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
                    processedMedia.append(
                        framedMedia(
                            from: finalImage,
                            assetID: assetID,
                            type: .video,
                            session: session,
                            cropAspect: cropAspect,
                            window: window,
                            sourceWindow: cropWindowSizes[assetID],
                            lockAspect: lockAspect,
                            videoURL: videoURL,
                            videoDuration: asset.duration,
                            videoFileSize: videoFileSize
                        )
                    )
                    if lockAspect == nil {
                        lockAspect = processedMedia.last.map {
                            $0.image.size.width / max($0.image.size.height, 1)
                        }
                    }
                }
            }

            await MainActor.run {
                selectedMediaItems = processedMedia
                currentFlow = .mediaEditing
            }
        }
    }

    // ✅ FUNCIÓN AUXILIAR: Validar videos antes de continuar
    private func validateSelectedMedia() {
        let videoItems = selectedMediaItems.filter { $0.type == .video }

        for videoItem in videoItems {
            _ = videoItem.videoURL
        }
    }

    // ✅ NUEVA FUNCIÓN: Detectar aspect ratio automáticamente SOLO para momentos
    // Reemplaza tu función detectAspectRatio en MediaSelectionView con esta versión mejorada

    private func detectAspectRatio(from image: UIImage) -> CreatorMedia.AspectRatio {
        CreatorMedia.AspectRatio.fromFeedPostRatio(image.size.width / max(image.size.height, 1))
    }

    private func framedMedia(
        from image: UIImage,
        assetID: String,
        type: CreatorMedia.MediaType,
        session: AssetCropSession,
        cropAspect: CGFloat,
        window: CGSize,
        sourceWindow: CGSize?,
        lockAspect: CGFloat? = nil,
        videoURL: URL? = nil,
        videoDuration: Double? = nil,
        videoFileSize: Int64? = nil
    ) -> CreatorMedia {
        let oriented = image.momentsOrientedUp()
        let originalAspect = oriented.size.width / max(oriented.size.height, 1)
        let previewCanvas = sourceWindow ?? window
        let visible = MomentFeedCrop.visiblePhotoRect(
            imageSize: oriented.size,
            canvas: previewCanvas,
            scale: session.scale,
            offset: session.offset,
            fillWindow: session.fillsPreview
        )
        let targetAspect = lockAspect ?? session.cropAspect
        let cropRect = MomentFeedCrop.cropRect(
            visible,
            toAspect: targetAspect,
            in: oriented.size
        )
        let framed = oriented.cropped(to: cropRect)
        let framedAspect = framed.size.width / max(framed.size.height, 1)
        let cardRatio = CreatorMedia.AspectRatio.fromFeedPostRatio(targetAspect)
        var media = CreatorMedia(
            id: assetID,
            image: framed,
            videoURL: videoURL,
            type: type,
            aspectRatio: cardRatio,
            recommendedAspectRatio: cardRatio,
            hasEdits: true,
            videoDuration: videoDuration,
            videoFileSize: videoFileSize
        )
        media.immersiveImage = oriented
        media.immersiveAspectRatio = .custom(originalAspect)
        media.feedCrop = MomentFeedCrop.normalizedFeedCrop(
            cropRect,
            in: oriented.size,
            cardAspect: framedAspect
        )
        return media
    }


    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func loadFullVideo(for asset: PHAsset) async -> (UIImage?, URL?, Int64?) {

        // Cargar thumbnail del video
        let thumbnail = await loadFullImage(for: asset)

        // ✅ MÉTODO MEJORADO: Solicitar video con opciones específicas
        let videoResult: (URL?, Int64?) = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current // Usar versión actual, no la original


            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in


                // Verificar si es degraded (baja calidad)
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return // Esperar la versión de alta calidad
                }

                // Verificar si hay error
                if info?[PHImageErrorKey] as? Error != nil {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                // Verificar si necesita descargar de iCloud
                if let needsDownload = info?[PHImageResultIsInCloudKey] as? Bool, needsDownload {
                    // Ya configuramos isNetworkAccessAllowed = true
                    return
                }

                // Extraer URL del AVAsset
                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                let videoURL = urlAsset.url
                var fileSize: Int64?

                // Verificar tamaño del archivo
                do {
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
                    fileSize = fileAttributes[FileAttributeKey.size] as? Int64
                } catch {
                }

                continuation.resume(returning: (videoURL, fileSize))
            }
        }

        return (thumbnail, videoResult.0, videoResult.1)
    }

    // ✅ FUNCIÓN AUXILIAR: Verificar permisos de acceso a video
    private func checkVideoAccess(for asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false // Solo check local
        options.deliveryMode = .fastFormat

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, audioMix, info in
            DispatchQueue.main.async {
                if info?[PHImageErrorKey] as? Error != nil {
                } else if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud {
                } else if avAsset != nil {
                }
            }
        }
    }

    private func createVideoPlaceholder() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300))
        return renderer.image { context in
            UIColor.systemGray3.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 300, height: 300)))

            let videoIcon = "▶️"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60),
                .foregroundColor: UIColor.white
            ]
            let textSize = videoIcon.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (300 - textSize.width) / 2,
                y: (300 - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            videoIcon.draw(in: textRect, withAttributes: attributes)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Permission Denied View (con instrucciones opcionales)
    private var permissionDeniedView: some View {
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

            // ✅ Instrucciones opcionales para el usuario
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProfileMomentZoomNavigation.canvasBackground(for: colorScheme))
    }
}
