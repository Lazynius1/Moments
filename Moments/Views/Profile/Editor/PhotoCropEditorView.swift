import SwiftUI
import PhotosUI
import Photos

// MARK: - Extensión para normalizar orientación de imagen
extension UIImage {
    func normalized() -> UIImage {
        guard size.width > 0, size.height > 0 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // ✅ EXTENSIÓN PARA BLUR: Crear fondo desenfocado
    func withBlur(radius: CGFloat) -> UIImage {
        guard let ciImage = CIImage(image: self) else { return self }
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(radius, forKey: kCIInputRadiusKey)
        
        guard let outputImage = blurFilter?.outputImage else { return self }
        
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return self }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: -  Profile Picture Editor
struct PhotoCropEditorView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let originalAsset: PHAsset
    let onSave: (UIImage) -> Void
    
    @State private var offset = CGSize.zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isProcessing = false
    @GestureState private var gestureTranslation = CGSize.zero
    @State private var fullResolutionImage: UIImage?
    @State private var isLoadingImage = true
    
    // ✅ ESTADOS PARA GESTOS MEJORADOS
    @State private var isDragging = false
    @State private var isZooming = false
    @State private var photoAssets: [PHAsset] = []
    @State private var isLoadingRecentPhotos = false
    @State private var visiblePhotoCount: Int = 20
    @State private var availableAlbums: [ProfileAlbumInfo] = []
    @State private var selectedAlbum: ProfileAlbumInfo?
    
    private let imageManager = PHImageManager.default()
    private let outputSize: CGSize = CGSize(width: 400, height: 400) // ✅ COINCIDIR CON STORAGESERVICE
    
    private var cropFrameSide: CGFloat {
        UIScreen.main.bounds.width
    }
    
    private var cropSize: CGFloat {
        cropFrameSide
    }
    
    private var previewFrameSize: CGSize {
        CGSize(width: cropFrameSide, height: cropFrameSide)
    }
    
    var body: some View {
        ZStack {
            // MARK: - 1. Immersive Background
            immersiveBackground
            
            if isLoadingImage {
                loadingView
            } else if let image = fullResolutionImage {
                VStack(spacing: 0) {
                    // Header Flotante
                    headerView
                        .padding(.top, 10)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            // Área de Crop
                            cropAreaView(with: image)
                            
                            albumSelector
                            
                            photoGridSection()
                                .padding(.bottom, 40)
                        }
                    }
                }
            }
            
            if isProcessing {
                processingOverlay
            }
        }
        .onAppear {
            loadFullResolutionImage()
            loadAvailableAlbums()
        }
    }
    
    // MARK: - Vista de carga
    private var immersiveBackground: some View {
        (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .ignoresSafeArea()
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(colorScheme == .dark ? .white : .black)
            
            Text(NSLocalizedString("profileEditor.crop.loadingImage", comment: ""))
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                if !isProcessing {
                    dismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .disabled(isProcessing)
            
            Spacer()
            
            Text(NSLocalizedString("profileEditor.crop.moveAndScale", comment: ""))
                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.3), radius: 2, x: 0, y: 1)
            
            Spacer()
            
            Button(action: {
                // Feedback háptico para confirmar la pulsación
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                cropAndSaveImage()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(isProcessing ? Color.gray.opacity(0.3) : Color.clear)
                    )
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: !isProcessing))
            }
            .disabled(isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Área de crop cuadrada
    private func cropAreaView(with image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image.withBlur(radius: 40))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: previewFrameSize.width, height: previewFrameSize.height)
                .clipped()
                .overlay(
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(colorScheme == .dark ? 0.18 : 0.08)
                )
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: foregroundDisplaySize(for: image.size).width * scale,
                    height: foregroundDisplaySize(for: image.size).height * scale
                )
                .offset(CGSize(width: offset.width + gestureTranslation.width, height: offset.height + gestureTranslation.height))
                .clipped()
                .scaleEffect(isDragging || isZooming ? 1.02 : 1.0)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isDragging), value: isDragging)
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .updating($gestureTranslation) { value, state, _ in
                                if !isProcessing {
                                    state = value.translation
                                    isDragging = true
                                }
                            }
                            .onEnded { value in
                                if !isProcessing {
                                    isDragging = false
                                    let newOffset = CGSize(
                                        width: offset.width + value.translation.width,
                                        height: offset.height + value.translation.height
                                    )
                                    
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        offset = limitOffset(newOffset, imageSize: image.size)
                                    }
                                }
                            },
                        
                        MagnificationGesture()
                            .onChanged { value in
                                if !isProcessing {
                                    isZooming = true
                                    let newScale = lastScale * value
                                    scale = max(getMinimumScale(for: image.size), min(newScale, 4.0))
                                }
                            }
                            .onEnded { _ in
                                if !isProcessing {
                                    isZooming = false
                                    lastScale = scale
                                    
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        offset = limitOffset(offset, imageSize: image.size)
                                    }
                                }
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    if !isProcessing {
                        resetToInitialPosition(for: image.size)
                    }
                }
            
            cropMaskOverlay
            
            if isDragging || isZooming {
                gridOverlay
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: previewFrameSize.width, height: previewFrameSize.height)
        .clipped()
        .onAppear {
            setupInitialTransform(for: image.size)
        }
    }
    
    private var cropMaskOverlay: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(colorScheme == .dark ? 0.76 : 0.52)
            
            LinearGradient(
                colors: [
                    (colorScheme == .dark ? Color.black : Color.white).opacity(colorScheme == .dark ? 0.14 : 0.08),
                    .clear,
                    (colorScheme == .dark ? Color.black : Color.white).opacity(colorScheme == .dark ? 0.28 : 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            Circle()
                .frame(width: cropSize, height: cropSize)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: previewFrameSize.width, height: previewFrameSize.height)
        .allowsHitTesting(false)
    }
    
    // MARK: - Grid de ayuda
    private var gridOverlay: some View {
        ZStack {
            // Líneas verticales
            HStack(spacing: cropSize / 3 - 1) {
                Rectangle()
                    .fill((colorScheme == .dark ? Color.white : Color.primary).opacity(0.2))
                    .frame(width: 1, height: cropSize)
                Rectangle()
                    .fill((colorScheme == .dark ? Color.white : Color.primary).opacity(0.2))
                    .frame(width: 1, height: cropSize)
            }
            
            // Líneas horizontales
            VStack(spacing: cropSize / 3 - 1) {
                Rectangle()
                    .fill((colorScheme == .dark ? Color.white : Color.primary).opacity(0.2))
                    .frame(width: cropSize, height: 1)
                Rectangle()
                    .fill((colorScheme == .dark ? Color.white : Color.primary).opacity(0.2))
                    .frame(width: cropSize, height: 1)
            }
        }
        .frame(width: cropSize, height: cropSize)
    }
    
    private var albumSelector: some View {
        HStack {
            Menu {
                ForEach(availableAlbums) { album in
                    Button(album.title) {
                        selectAlbum(album)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedAlbum?.title ?? NSLocalizedString("profileEditor.category.recent", comment: ""))
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Grid de fotos completo (como ProfileEditor)
    private func photoGridSection() -> some View {
        VStack(spacing: 0) {
            if isLoadingRecentPhotos {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                    spacing: 4
                ) {
                    ForEach(0..<8, id: \.self) { _ in
                        Rectangle()
                            .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                            .frame(height: gridItemSize)
                    }
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                    spacing: 4
                ) {
                    ForEach(Array(photoAssets.prefix(visiblePhotoCount).enumerated()), id: \.element.localIdentifier) { index, asset in
                        
                        PhotoGridItem(
                            asset: asset,
                            isSelected: false,
                            imageManager: imageManager
                        ) {
                            selectNewPhotoFromGrid(asset)
                        }
                        .onAppear {
                            loadMorePhotosIfNeeded(currentIndex: index)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
    
    // MARK: - Configuración inicial
    private func setupInitialTransform(for imageSize: CGSize) {
        let optimalScale = 1.0
        let smartOffset = calculateSmartOffset(imageSize: imageSize, scale: optimalScale)
        
        withAnimation(.easeOut(duration: 0.5)) {
            scale = optimalScale
            lastScale = optimalScale
            offset = smartOffset
        }
    }
    
    // ✅ FUNCIÓN: Reset a posición inicial
    private func resetToInitialPosition(for imageSize: CGSize) {
        let optimalScale = 1.0
        let smartOffset = calculateSmartOffset(imageSize: imageSize, scale: optimalScale)
        
        // ✅ FEEDBACK HÁPTICO PARA RESET
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
        
        withAnimation(.easeOut(duration: 0.5)) {
            scale = optimalScale
            lastScale = optimalScale
            offset = smartOffset
        }
    }
    
    private func getMinimumScale(for imageSize: CGSize) -> CGFloat {
        let _ = imageSize
        return 0.5
    }
    
    private func calculateSmartOffset(imageSize: CGSize, scale: CGFloat) -> CGSize {
        // ✅ CENTRAR PERFECTAMENTE la imagen en el área de crop
        // No aplicar offsets automáticos que causen desalineación
        return CGSize.zero
    }
    
    private func limitOffset(_ proposedOffset: CGSize, imageSize: CGSize) -> CGSize {
        let baseSize = foregroundDisplaySize(for: imageSize)
        let scaledImageWidth = baseSize.width * scale
        let scaledImageHeight = baseSize.height * scale
        
        let maxOffsetX = max(0, (scaledImageWidth - cropSize) / 2)
        let maxOffsetY = max(0, (scaledImageHeight - cropSize) / 2)
        
        let limitedOffsetX = max(-maxOffsetX, min(maxOffsetX, proposedOffset.width))
        let limitedOffsetY = max(-maxOffsetY, min(maxOffsetY, proposedOffset.height))
        
        return CGSize(width: limitedOffsetX, height: limitedOffsetY)
    }
    
    // MARK: - Cargar imagen
    private func loadFullResolutionImage() {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        imageManager.requestImage(
            for: originalAsset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.fullResolutionImage = image?.normalized()
                self.isLoadingImage = false
            }
        }
    }
    
    // MARK: - Overlay de procesamiento
    private var processingOverlay: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("profileEditor.crop.processing", comment: ""))
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        }
    }
    
    // MARK: - Función de crop final
    private func cropAndSaveImage() {
        guard let image = fullResolutionImage else { 
            return 
        }
        
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let croppedImage = self.cropSquareImage(from: image) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.onSave(croppedImage)
                self.dismiss()
            }
        }
    }
    
    // MARK: - Crop final - PERFECTO PARA PROFILEVIEW (110x110)
    private func cropSquareImage(from image: UIImage) -> UIImage? {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, outputSize.width > 0, outputSize.height > 0 else {
            return nil
        }

        let baseSize = foregroundDisplaySize(for: imageSize)
        let scaledWidth = baseSize.width * scale
        let scaledHeight = baseSize.height * scale
        let outputFactor = outputSize.width / cropSize
        
        let finalX = ((cropSize - scaledWidth) / 2 + offset.width) * outputFactor
        let finalY = ((cropSize - scaledHeight) / 2 + offset.height) * outputFactor
        let finalWidth = scaledWidth * outputFactor
        let finalHeight = scaledHeight * outputFactor

        return UIGraphicsImageRenderer(size: outputSize).image { context in
            // ✅ PRIMERO: Dibujar fondo blur de la imagen completa
            let blurImage = image.withBlur(radius: 25) // ✅ BLUR INTENSO para fondo real
            let backgroundRect = CGRect(origin: .zero, size: outputSize)
            blurImage.draw(in: backgroundRect)

            // ✅ SEGUNDO: Agregar overlay oscuro sobre el blur para fondo real
            UIColor.black.withAlphaComponent(0.3).setFill()
            context.cgContext.fill(backgroundRect)

            // ✅ TERCERO: Dibujar la imagen principal en la posición elegida por el usuario
            let drawRect = CGRect(
                x: finalX,
                y: finalY,
                width: finalWidth,
                height: finalHeight
            )
            image.draw(in: drawRect)
        }
    }
    
    // MARK: - Funciones para el grid de fotos
    private func loadRecentPhotos() {
        isLoadingRecentPhotos = true
        visiblePhotoCount = 20
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 200
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var assets: [PHAsset] = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        DispatchQueue.main.async {
            self.photoAssets = assets
            self.isLoadingRecentPhotos = false
        }
    }
    
    private func loadAvailableAlbums() {
        var albums: [ProfileAlbumInfo] = []
        
        let smartAlbumSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumUserLibrary,
            .smartAlbumFavorites,
            .smartAlbumScreenshots,
            .smartAlbumSelfPortraits,
            .smartAlbumRecentlyAdded
        ]
        
        for subtype in smartAlbumSubtypes {
            let fetchResult = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            fetchResult.enumerateObjects { collection, _, _ in
                let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
                if assetCount > 0 {
                    let title = collection.localizedTitle ?? getSmartAlbumTitle(for: subtype)
                    albums.append(ProfileAlbumInfo(
                        id: collection.localIdentifier,
                        title: title,
                        assetCollection: collection,
                        assetCount: assetCount
                    ))
                }
            }
        }
        
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            if assetCount > 0 {
                albums.append(ProfileAlbumInfo(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? NSLocalizedString("profileEditor.album.default", comment: ""),
                    assetCollection: collection,
                    assetCount: assetCount
                ))
            }
        }
        
        albums.sort { $0.assetCount > $1.assetCount }
        
        DispatchQueue.main.async {
            self.availableAlbums = albums
            if let current = self.selectedAlbum {
                self.selectAlbum(current)
            } else if let first = albums.first {
                self.selectedAlbum = first
                self.loadPhotosFromAlbum(first)
            } else {
                self.loadRecentPhotos()
            }
        }
    }
    
    private func getSmartAlbumTitle(for subtype: PHAssetCollectionSubtype) -> String {
        switch subtype {
        case .smartAlbumUserLibrary: return NSLocalizedString("profileEditor.category.recent", comment: "")
        case .smartAlbumFavorites: return NSLocalizedString("profileEditor.album.favorites", comment: "")
        case .smartAlbumScreenshots: return NSLocalizedString("profileEditor.album.screenshots", comment: "")
        case .smartAlbumSelfPortraits: return NSLocalizedString("profileEditor.category.selfies", comment: "")
        case .smartAlbumRecentlyAdded: return NSLocalizedString("profileEditor.category.recent", comment: "")
        default: return NSLocalizedString("profileEditor.album.default", comment: "")
        }
    }
    
    private func loadPhotosFromAlbum(_ album: ProfileAlbumInfo?) {
        isLoadingRecentPhotos = true
        visiblePhotoCount = 20
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 200
        
        let allPhotos: PHFetchResult<PHAsset>
        if let album {
            allPhotos = PHAsset.fetchAssets(in: album.assetCollection, options: fetchOptions)
        } else {
            allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        }
        
        var assets: [PHAsset] = []
        allPhotos.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        DispatchQueue.main.async {
            self.photoAssets = assets
            self.isLoadingRecentPhotos = false
        }
    }
    
    private func selectAlbum(_ album: ProfileAlbumInfo) {
        selectedAlbum = album
        loadPhotosFromAlbum(album)
    }
    
    private func loadMorePhotosIfNeeded(currentIndex: Int) {
        let thresholdIndex = max(visiblePhotoCount - 4, 0)
        guard currentIndex >= thresholdIndex else { return }
        guard visiblePhotoCount < photoAssets.count else { return }
        
        visiblePhotoCount = min(visiblePhotoCount + 20, photoAssets.count)
    }
    
    private func selectNewPhotoFromGrid(_ asset: PHAsset) {
        // Feedback háptico
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Actualizar la imagen principal
        fullResolutionImage = nil
        isLoadingImage = true
        
        // Cargar la nueva imagen en alta resolución
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.fullResolutionImage = image?.normalized()
                self.isLoadingImage = false
                
                // Resetear transformaciones para la nueva imagen
                if let image = image {
                    self.setupInitialTransform(for: image.size)
                }
            }
        }
    }
    
    private func foregroundDisplaySize(for imageSize: CGSize) -> CGSize {
        let widthScale = previewFrameSize.width / imageSize.width
        let heightScale = previewFrameSize.height / imageSize.height
        let fitScale = min(widthScale, heightScale)
        return CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
    }
}

// MARK: - Photo Grid Item (copiado de ProfileEditor)
private struct PhotoGridItem: View {
    @Environment(\.colorScheme) var colorScheme
    let asset: PHAsset
    let isSelected: Bool
    let imageManager: PHImageManager
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    private var itemSize: CGFloat {
        gridItemSize
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: itemSize, height: itemSize)
                        .clipped()
                } else {
                    Rectangle()
                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                        .frame(width: itemSize, height: itemSize)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(colorScheme == .dark ? .white : .black)
                        )
                }
                
                // Overlay de selección (no usado en el editor, pero mantenemos la estructura)
                if isSelected {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: itemSize, height: itemSize)
                        .overlay(
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .background(Circle().fill(colorScheme == .dark ? .black : .white))
                                        .padding(8)
                                }
                                Spacer()
                            }
                        )
                        .overlay(
                            Rectangle()
                                .stroke((colorScheme == .dark ? Color.white : Color.black).opacity(0.4), lineWidth: 2)
                        )
                }
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        let targetSize = CGSize(
            width: itemSize * UIScreen.main.scale,
            height: itemSize * UIScreen.main.scale
        )
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                self.image = result
                self.isLoading = false
            }
        }
    }
}

private var gridItemSize: CGFloat {
    let screenWidth = UIScreen.main.bounds.width
    let horizontalPadding: CGFloat = 12
    let totalSpacing: CGFloat = 12
    return floor((screenWidth - horizontalPadding - totalSpacing) / 4)
}
