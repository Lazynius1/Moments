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
    @State private var showingCamera = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var showingVideoTooLongAlert = false
    @State private var rejectedVideoDuration: TimeInterval = 0

    // ✅ Estados para manejo de álbumes
    @State private var availableAlbums: [AlbumInfo] = []
    @State private var selectedAlbum: AlbumInfo?
    @State private var showingAlbumPicker = false

    private let imageManager = PHImageManager.default()
    private let thumbnailSize = CGSize(width: 300, height: 300)

    // Grid layout mejorado con columnas fijas para mejor control
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Preview del archivo seleccionado principal
            if !selectedAssetIDs.isEmpty {
                mainPreviewSection
            }

            // Grid de fotos y videos
            mediaGridSection
        }
        .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
        .matchedGeometryEffect(id: "momentSource", in: animation) // ✅ Unfold Target
        .onAppear {
            requestPhotoLibraryAccess()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCapture { media in
                if media.type == .video,
                   let duration = media.videoDuration,
                   duration > CreatorMedia.maxMomentVideoDuration {
                    rejectedVideoDuration = duration
                    showingVideoTooLongAlert = true
                    return
                }
                selectedMediaItems.append(media)
                currentFlow = .mediaEditing
            }
        }
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
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 40, height: 40)
                    .liquidGlass(in: Circle(), interactive: true)
            }

            Spacer()

            Text(NSLocalizedString("creator.newMoment", comment: ""))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()

            if !selectedAssetIDs.isEmpty {
                GlowSharePill(
                    title: "creator.next",
                    icon: "chevron.right",
                    isSmall: true
                ) {
                    processSelectedAssets()
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
            // Preview grande del archivo seleccionado
            if let currentAssetID = selectedAssetIDs.last, // Usar el último seleccionado para el preview principal
               let currentAsset = mediaAssets.first(where: { $0.localIdentifier == currentAssetID }) {

                ZStack {
                    // Fondo Cinemático (Blur)
                    if let thumbnail = thumbnails[currentAssetID] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: UIScreen.main.bounds.width, height: 320)
                            .blur(radius: 30)
                            .opacity(0.6)
                            .overlay(Color.black.opacity(0.2))
                    }

                    if let thumbnail = thumbnails[currentAssetID] {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 300)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            .padding(.vertical, 10)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }

                    // Indicador de video
                    if currentAsset.mediaType == .video {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                    Text(formatDuration(currentAsset.duration))
                                        .font(.caption.bold())
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                                .padding(12)
                            }
                        }
                    }

                    // Botón para deseleccionar rápido
                    VStack {
                        HStack {
                            Button(action: { toggleAssetSelection(currentAsset) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(12)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .frame(height: 320)
                .clipped()
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
            }

            // Carrusel de Multiselección
            if selectedAssetIDs.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedAssetIDs, id: \.self) { id in
                            if let thumb = thumbnails[id] {
                                ZStack {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(id == selectedAssetIDs.last ? Color.pink : Color.white.opacity(0.3), lineWidth: 2)
                                        )
                                }
                                .onTapGesture {
                                    // Mover al final para que sea el preview principal
                                    if let index = selectedAssetIDs.firstIndex(of: id) {
                                        let item = selectedAssetIDs.remove(at: index)
                                        selectedAssetIDs.append(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(
                    (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                        .opacity(colorScheme == .dark ? 0.92 : 0.98)
                )
            }
        }
    }

    // MARK: - Grid de medios
    private var mediaGridSection: some View {
        VStack(spacing: 0) {
            // Separador
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)

            // Header con selector de álbum y botón de cámara
            HStack {
                Button(action: {
                    showingAlbumPicker = true
                }) {
                    HStack(spacing: 6) {
                        Text(selectedAlbum?.title ?? NSLocalizedString("creator.album.recents", comment: "Recents"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.5))
                            .rotationEffect(.degrees(showingAlbumPicker ? 180 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .clipShape(Capsule())
                }

                Spacer()

                Button(action: {
                    showingCamera = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14))
                        Text(NSLocalizedString("creator.camera", comment: ""))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))

            // Grid de fotos
            if isLoadingLibrary {
                loadingView
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                permissionDeniedView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2, pinnedViews: []) {
                        ForEach(mediaAssets, id: \.localIdentifier) { asset in
                            MediaGridCell(
                                asset: asset,
                                thumbnail: thumbnails[asset.localIdentifier],
                                isSelected: selectedAssetIDs.contains(asset.localIdentifier),
                                selectionNumber: selectedAssetIDs.firstIndex(of: asset.localIdentifier).map { $0 + 1 },
                                onTap: { toggleAssetSelection(asset) }
                            )
                            .frame(minHeight: 100) // ✅ NUEVO: Altura mínima para consistencia
                        }
                    }
                    .padding(.horizontal, 2)
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
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(50)
    }

    // MARK: - Funciones

    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                    if status == .authorized || status == .limited {
                        loadAvailableAlbums()
                        loadMediaFromLibrary()
                    } else {
                        isLoadingLibrary = false
                    }
                }
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

        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let assets = PHAsset.fetchAssets(in: album.assetCollection, options: fetchOptions)
            var assetArray: [PHAsset] = []

            assets.enumerateObjects { asset, _, _ in
                assetArray.append(asset)
            }

            await MainActor.run {
                self.mediaAssets = assetArray
                loadThumbnails()
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

    private func toggleAssetSelection(_ asset: PHAsset) {
        let assetID = asset.localIdentifier

        if selectedAssetIDs.contains(assetID) {
            selectedAssetIDs.removeAll { $0 == assetID }
        } else {
            if asset.mediaType == .video, asset.duration > CreatorMedia.maxMomentVideoDuration {
                rejectedVideoDuration = asset.duration
                showingVideoTooLongAlert = true
                return
            }

            if selectedAssetIDs.count < 10 {
                selectedAssetIDs.append(assetID)
            }
        }

        if thumbnails[assetID] == nil {
            loadHighQualityThumbnail(for: asset)
        }
    }

    private func loadHighQualityThumbnail(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 500, height: 500),
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

    // Reemplaza tu función processSelectedAssets() con esta versión mejorada

    private func processSelectedAssets() {
        Task {
            var processedMedia: [ProcessedMedia] = []

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
                        // ✅ Detectar aspect ratio automáticamente
                        let detectedAspectRatio = detectAspectRatio(from: image)

                        let media = CreatorMedia(
                            id: assetID,
                            image: image,
                            videoURL: nil,
                            type: .image,
                            aspectRatio: detectedAspectRatio,
                            recommendedAspectRatio: detectedAspectRatio // ✅ Guardar el aspect ratio detectado como recomendado
                        )
                        processedMedia.append(media)
                    }
                } else if asset.mediaType == .video {
                    let (thumbnail, videoURL, videoFileSize) = await loadFullVideo(for: asset)

                    let finalImage = thumbnail ?? createVideoPlaceholder()

                    // ✅ Detectar aspect ratio del video
                    let detectedAspectRatio = detectAspectRatio(from: finalImage)

                    let media = ProcessedMedia(
                        id: assetID,
                        image: finalImage,
                        videoURL: videoURL,
                        type: .video,
                        aspectRatio: detectedAspectRatio,
                        recommendedAspectRatio: detectedAspectRatio, // ✅ Guardar el aspect ratio detectado como recomendado
                        videoDuration: asset.duration,
                        videoFileSize: videoFileSize
                    )
                    processedMedia.append(media)
                }
            }

            await MainActor.run {
                selectedMediaItems = processedMedia

                // ✅ NUEVA LÓGICA: Determinar flujo basado en tipo de medios
                let hasImages = processedMedia.contains { $0.type == .image }
                let hasVideos = processedMedia.contains { $0.type == .video }


                if hasVideos && !hasImages {
                    // Solo videos: ir al editor de videos
                    currentFlow = .videoEditing
                } else if hasImages && !hasVideos {
                    // Solo imágenes: ir al editor de fotos
                    currentFlow = .mediaEditing
                } else if hasImages && hasVideos {
                    // Mezcla: permitir al usuario elegir o ir directo a caption
                    currentFlow = .captionAndDetails
                } else {
                    // Fallback (no debería pasar)
                    currentFlow = .mediaEditing
                }
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
        let imageRatio = image.size.width / image.size.height

        // ✅ MEJORADO: Tolerancia más amplia (15%) para detectar mejor ratios comunes
        let tolerance: CGFloat = 0.15

        // ✅ MEJORADO: Detectar ratios específicos con mayor precisión y tolerancia

        // 9:16 (Stories/Reels) - ratio ≈ 0.5625
        if abs(imageRatio - 0.5625) < tolerance {
            return .nineBySixteen
        }

        // 4:5 (Portrait posts) - ratio = 0.8
        if abs(imageRatio - 0.8) < tolerance {
            return .portrait
        }

        // 1:1 (Square) - ratio = 1.0
        if abs(imageRatio - 1.0) < tolerance {
            return .square
        }

        // 16:9 (Landscape) - ratio ≈ 1.777
        if abs(imageRatio - 1.777) < tolerance {
            return .landscape
        }

        // ✅ MEJORADO: Detección por rangos más precisos y amplios
        // Rangos ajustados para cubrir más casos comunes
        if imageRatio < 0.65 {
            // Muy vertical (más vertical que 9:16)
            return .nineBySixteen
        } else if imageRatio < 0.85 {
            // Vertical moderado (entre 9:16 y 4:5)
            return .portrait
        } else if imageRatio < 1.15 {
            // Casi cuadrado o cuadrado (entre 4:5 y 16:9)
            return .square
        } else if imageRatio < 2.0 {
            // Horizontal moderado (16:9 o similar)
            return .landscape
        } else {
            // Muy horizontal (panorámica)
            return .landscape
        }
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
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.6))

            Text("creator.gallery.permission")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // ✅ Instrucciones opcionales para el usuario
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
