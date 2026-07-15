import SwiftUI
import PhotosUI
import FirebaseAuth
import Photos
import Kingfisher

// MARK: - Album Information Model (Local for Profile Editor)
struct ProfileAlbumInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let assetCollection: PHAssetCollection
    let assetCount: Int
    
    static func == (lhs: ProfileAlbumInfo, rhs: ProfileAlbumInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - ACTUALIZACIÓN: GridPhotoPickerView con Editor de Crop
struct GridPhotoPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var currentProfileImage: UIImage?
    var onUploadSuccess: (() -> Void)? = nil // NUEVO: Callback para notificar éxito
    @State private var photoAssets: [PHAsset] = []
    @State private var selectedAsset: PHAsset?
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    @State private var selectedCategory: PhotoCategory = .recent
    
    // NUEVO: Estados para el editor de crop
    @State private var isShowingCropEditor = false
    @State private var selectedAssetForCrop: PHAsset? // Cambio: pasamos el asset
    
    // Estados para upload
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showUploadError = false
    
    // NUEVO: Estados para manejo de álbumes
    @State private var availableAlbums: [ProfileAlbumInfo] = []
    @State private var selectedAlbum: ProfileAlbumInfo?
    @State private var showingAlbumPicker = false
    @State private var isLoadingLibrary = true
    @State private var thumbnails: [PHAsset: UIImage] = [:]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let imageManager = PHImageManager.default()
    private let firestoreService = FirestoreService()
    private let storageService = StorageService()
    
    enum PhotoCategory: CaseIterable {
        case recent, photography, selfies, albums
        
        var title: String {
            switch self {
            case .recent: return NSLocalizedString("profileEditor.category.recent", comment: "")
            case .photography: return NSLocalizedString("profileEditor.category.photography", comment: "")
            case .selfies: return NSLocalizedString("profileEditor.category.selfies", comment: "")
            case .albums: return NSLocalizedString("profileEditor.category.albums", comment: "")
            }
        }
        
        var icon: String {
            switch self {
            case .recent: return "clock"
            case .photography: return "camera"
            case .selfies: return "person.crop.circle"
            case .albums: return "rectangle.stack"
            }
        }
    }
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                    .zIndex(10) // Asegurar que el header esté por encima
                
                if let selectedAsset = selectedAsset {
                    mainPreviewSection(for: selectedAsset)
                }
                
                mediaGridSection
            }
        }
        .onAppear {
            loadInitialPhotos()
        }
        .sheet(isPresented: $isShowingCropEditor) {
            if let assetForCrop = selectedAssetForCrop {
                PhotoCropEditorView(
                    originalAsset: assetForCrop,
                    onSave: { croppedImage in
                        isShowingCropEditor = false
                        currentProfileImage = croppedImage
                        uploadImageToFirebaseWithCleanup(image: croppedImage, userId: Auth.auth().currentUser?.uid ?? "") {
                            onUploadSuccess?()
                            self.dismiss()
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Header estilo Creator
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(10)
                    .background(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .contentShape(Rectangle()) // Área interactiva completa
            
            Spacer()
            
            Text(NSLocalizedString("profileEditor.library", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            if let asset = selectedAsset {
                Button(action: {
                    selectedAssetForCrop = asset
                    isShowingCropEditor = true
                }) {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("profileEditor.next", comment: ""))
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
                .contentShape(Capsule()) // Área interactiva completa
            } else {
                Color.clear.frame(width: 80, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    // MARK: - Preview Principal estilo Creator
    private func mainPreviewSection(for asset: PHAsset) -> some View {
        ZStack {
            // Fondo con Blur
            if let image = thumbnails[asset] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .blur(radius: 40)
                    .opacity(0.6)
                    .overlay(Color.black.opacity(0.1))
            }
            
            // Imagen principal
            if let image = thumbnails[asset] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .padding(.vertical, 10)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: 300)
        .clipped()
        .background(colorScheme == .dark ? Color.black : Color.white)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
        .onAppear {
            loadThumbnail(for: asset)
        }
    }
    
    // MARK: - Grid Section estilo Creator
    private var mediaGridSection: some View {
        VStack(spacing: 0) {
            // Sub-header del Grid con Album y Camara
            HStack {
                Button(action: { showingAlbumPicker = true }) {
                    HStack(spacing: 6) {
                        Text(selectedAlbum?.title ?? NSLocalizedString("profileEditor.category.recent", comment: ""))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                    .clipShape(Capsule())
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photoAssets, id: \.localIdentifier) { asset in
                        PhotoGridItem(
                            asset: asset,
                            isSelected: selectedAsset?.localIdentifier == asset.localIdentifier,
                            imageManager: imageManager,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedAsset = asset
                                    loadThumbnail(for: asset)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showingAlbumPicker) {
            ProfileAlbumPickerView(
                albums: availableAlbums,
                selectedAlbum: selectedAlbum,
                onAlbumSelected: { album in
                    selectedAlbum = album
                    showingAlbumPicker = false
                    loadPhotosFromAlbum(album)
                }
            )
        }
    }
    
    // Funciones de carga auxiliares
    private func loadInitialPhotos() {
        isLoadingLibrary = true
        checkPhotoLibraryPermission()
    }
    
    private func loadThumbnail(for asset: PHAsset) {
        if thumbnails[asset] != nil { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 800),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                DispatchQueue.main.async {
                    thumbnails[asset] = result
                }
            }
        }
    }
    
    // MARK: - Overlay de upload actualizado
    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color(hex: "007AFF"))
                
                Text("profileEditor.uploadingPhoto")
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(.white)
                
                Text("profileEditor.uploadingTime")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 10)
        }
    }
    
    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PhotoCategory.allCases, id: \.self) { category in
                    CategoryFilterButton(
                        title: category.title,
                        icon: category.icon,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation {
                            selectedCategory = category
                        }
                        
                        if category == .albums {
                            if availableAlbums.isEmpty {
                                loadAvailableAlbums()
                            } else if let album = selectedAlbum {
                                loadPhotosFromAlbum(album)
                            } else {
                                loadPhotosForCategory(category)
                            }
                        } else {
                            loadPhotosForCategory(category)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Loading, Permission Views (sin cambios)
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "007AFF"))
            
                            Text("profileEditor.loadingPhotos")
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var requestPermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(Color(hex: "007AFF"))
            
                            Text("profileEditor.photosAccess.title")
                .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                .foregroundStyle(.white)
            
                            Text("profileEditor.photosAccess.description")
                .font(.system(size: legacyPoppinsSize(16)))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(NSLocalizedString("profileEditor.allowAccess", comment: "")) {
                requestPhotoLibraryPermission()
            }
            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color(hex: "007AFF"))
            .clipShape(Capsule())
            .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deniedPermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(colorScheme == .dark ? .gray.opacity(0.8) : .gray.opacity(0.6))
            
            Text("profileEditor.accessDenied.title")
                .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Text("profileEditor.accessDenied.description")
                .font(.system(size: legacyPoppinsSize(16)))
                .foregroundStyle(colorScheme == .dark ? .gray : .gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // ✅ Instrucciones opcionales para el usuario
            Button("creator.permissions.openSettings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.purple, Color.pink]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    // MARK: - Helper Functions (sin cambios)
    private func checkPhotoLibraryPermission() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAvailableAlbums()
            loadPhotosForCategory(.recent)
        }
    }
    
    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                authorizationStatus = status
                if status == .authorized || status == .limited {
                    loadAvailableAlbums()
                    loadPhotosForCategory(.recent)
                }
            }
        }
    }
    
    private func loadPhotosForCategory(_ category: PhotoCategory) {
        isLoading = true
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        var allPhotos: PHFetchResult<PHAsset>
        
        switch category {
        case .recent:
            fetchOptions.fetchLimit = 1000
            allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .photography:
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            allPhotos = PHAsset.fetchAssets(with: fetchOptions)
        case .selfies:
            allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .albums:
            allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        }
        
        var assets: [PHAsset] = []
        allPhotos.enumerateObjects { asset, _, _ in
            if category == .selfies {
                let aspectRatio = Float(asset.pixelWidth) / Float(asset.pixelHeight)
                if aspectRatio >= 0.7 && aspectRatio <= 1.3 {
                    assets.append(asset)
                }
            } else {
                assets.append(asset)
            }
        }
        
        DispatchQueue.main.async {
            self.photoAssets = assets
            self.isLoading = false
            self.isLoadingLibrary = false
            if let firstAsset = assets.first {
                self.selectedAsset = firstAsset
                self.loadThumbnail(for: firstAsset)
            }
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
            if let first = albums.first {
                self.selectedAlbum = first
                self.loadPhotosFromAlbum(first)
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
        isLoading = true
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let allPhotos: PHFetchResult<PHAsset>
        if let album = album {
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
            self.isLoading = false
            self.isLoadingLibrary = false
            if let firstAsset = assets.first {
                self.selectedAsset = firstAsset
                self.loadThumbnail(for: firstAsset)
            }
        }
    }
    
    // MARK: - FUNCIÓN PRINCIPAL ACTUALIZADA: Abrir editor directo
    private func handlePhotoSelection() {
        guard let asset = selectedAsset else { return }
        
        // Pasar directamente el asset al editor
        selectedAssetForCrop = asset
        isShowingCropEditor = true
    }
    
    // MARK: - Función de upload (sin cambios)
    private func uploadImageToFirebaseWithCleanup(image: UIImage, userId: String, completion: (() -> Void)? = nil) {
        guard !userId.isEmpty else { return }
        
        isUploading = true
        
        // 1. Primero obtener la URL anterior para borrarla después
        firestoreService.fetchUserProfile(userId: userId) { result in
            
            let oldImagePath: String?
            switch result {
            case .success(let user):
                oldImagePath = user.profileImagePath
            case .failure:
                oldImagePath = nil
            }
            
            // 2. Subir nueva imagen usando uploadProfileImage (que procesa la imagen correctamente)
            self.storageService.uploadProfileImage(userId: userId, image: image) { result in
                switch result {
                case .success(let newPath):
                    // 3. Actualizar Firestore con nueva URL
                    self.firestoreService.updateProfilePicture(userId: userId, profileImagePath: newPath) { error in
                        DispatchQueue.main.async {
                            self.isUploading = false
                            
                            if let error = error {
                                self.uploadError = String(format: NSLocalizedString("profileEditor.error.updateProfile", comment: ""), error.localizedDescription)
                                self.showUploadError = true
                            } else {
                                // 4. Borrar imagen anterior si existe
                                self.storageService.deleteProfileImage(
                                    userId: userId,
                                    oldImagePath: oldImagePath
                                ) { _ in
                                    // No mostrar error al usuario, es operación secundaria
                                }
                                
                                self.dismiss()
                                completion?()
                            }
                        }
                    }
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.uploadError = String(format: NSLocalizedString("profileEditor.error.uploadImage", comment: ""), error.localizedDescription)
                        self.showUploadError = true
                    }
                }
            }
        }
    }
}
// MARK: - Category Filter Button
private struct CategoryFilterButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
            }
            .foregroundStyle(isSelected ? (colorScheme == .dark ? .white : .black) : (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ?
                Color(hex: "007AFF").opacity(0.3) :
                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ?
                        Color(hex: "007AFF") :
                        (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2)),
                        lineWidth: 1
                    )
            )
        }
    }
}

// MARK: - Photo Grid Item
private struct PhotoGridItem: View {
    let asset: PHAsset
    let isSelected: Bool
    let imageManager: PHImageManager
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        )
                }
                
                // Overlay de selección estilo Creator
                VStack {
                    HStack {
                        Spacer()
                        if isSelected {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "007AFF"))
                                    .frame(width: 22, height: 22)
                                    .shadow(radius: 2)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(6)
                        } else {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 22, height: 22)
                                .padding(6)
                        }
                    }
                    Spacer()
                }
                
                if isSelected {
                    Rectangle()
                        .stroke(Color(hex: "007AFF"), lineWidth: 3)
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
        
        // Resolución fija razonable para la miniatura del grid (independiente del dispositivo).
        let targetSize = CGSize(width: 400, height: 400)
        
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

// MARK: - Flow Layout
struct ProfileFlowLayoutt: Layout {
    var spacing: CGFloat
    var horizontalPadding: CGFloat = 16 // Margen lateral para evitar cortes
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size = CGSize.zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentX + subviewSize.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: subviewSize.width, height: subviewSize.height))
                
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
            }
            
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Vista de edición de perfil enfocada
struct ModernEditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var newBio: String
    var onSave: (PhotosPickerItem?, String, String?, [String]?) -> Void // ✅ UPGRADE: Incluye website e intereses

    
    // Estados para edición de perfil - AHORA CON DATOS REALES
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var website: String = ""
    @State private var profileImagePath: String? = nil
    @State private var selectedInterests: Set<String> = []
    
    // Estados de UI
    @State private var characterCount: Int = 0
    @State private var isShowingPhotoActions: Bool = false
    @State private var isShowingPhotoLibraryCrop: Bool = false
    @State private var isShowingCameraCapture: Bool = false
    @State private var currentProfileImage: UIImage?
    @State private var isShowingInterestsPicker: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var activeSection: EditSection = .basic
    
    // Estado de carga y error
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    // Servicio de Firestore
    private let firestoreService = FirestoreService()
    private let storageService = StorageService()
    
    // Secciones de edición simplificadas
    enum EditSection: CaseIterable {
        case basic, interests
        
        var title: String {
            switch self {
            case .basic: return NSLocalizedString("profileEditor.section.basic", comment: "")
            case .interests: return NSLocalizedString("profileEditor.section.interests", comment: "")
            }
        }
        
        var icon: String {
            switch self {
            case .basic: return "person.crop.circle"
            case .interests: return "heart.circle"
            }
        }
    }
    
    // Lista de intereses disponibles (cargada desde la base de datos)
    @State private var availableInterests: [String] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                immersiveBackground
                
                if isLoading {
                    loadingView
                } else if let errorMessage = errorMessage {
                    errorView(message: errorMessage)
                } else {
                    VStack(spacing: 0) {
                        profileHeader
                            .padding(.top, 10)
                        
                        if EditSection.allCases.count > 1 {
                            sectionTabs
                                .padding(.top, 6)
                        }
                        
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 24) {
                                switch activeSection {
                                case .basic:
                                    basicProfileSection
                                case .interests:
                                    interestsSection
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingPhotoActions) {
                photoActionsSheet
            }
            .fullScreenCover(isPresented: $isShowingPhotoLibraryCrop) {
                ProfileLibraryCropEntryView { croppedImage in
                    currentProfileImage = croppedImage
                    uploadCapturedProfileImage(croppedImage)
                }
            }
            .fullScreenCover(isPresented: $isShowingCameraCapture) {
                CameraCapture { media in
                    guard media.type == .image else { return }
                    let image = media.image
                    currentProfileImage = image
                    uploadCapturedProfileImage(image)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingInterestsPicker) {
                interestsPickerSheet
            }
            .alert("profileEditor.deletePhoto.title", isPresented: $showingDeleteConfirmation) {
                Button("common.delete", role: .destructive) {
                    deleteCurrentProfileImage()
                }
                Button("common.cancel", role: .cancel) { }
            } message: {
                Text("profileEditor.deletePhoto.confirm")
            }
        }
        .onAppear {
            loadUserData()
            loadInterests()
        }
    }
    
    // MARK: - Subviews Inmersivas
    private var immersiveBackground: some View {
        (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .ignoresSafeArea()
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("profileEditor.loadingProfile")
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.red.opacity(0.8))
            
            Text("profileEditor.error")
                .font(.system(size: legacyPoppinsSize(18), weight: .bold))
                .foregroundStyle(.white)
            
            Text(message)
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(NSLocalizedString("profileEditor.retry", comment: "")) {
                loadUserData()
            }
            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
        }
    }

    
    // MARK: - Función para cargar intereses disponibles
    private func loadInterests() {
        firestoreService.fetchAvailableInterests { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let interests):
                    availableInterests = interests
                case .failure:
                    // Fallback a lista por defecto si falla la carga
                    availableInterests = [
                        "Música", "Cine", "Deportes", "Viajes", "Fotografía", "Arte", "Tecnología",
                        "Lectura", "Cocina", "Moda", "Gaming", "Fitness", "Naturaleza", "Animales",
                        "Baile", "Teatro", "Escritura", "Ciencia", "Historia", "Idiomas", "Anime",
                        "K-pop", "Streaming", "Yoga", "Meditación", "Senderismo", "Ciclismo"
                    ]
                }
            }
        }
    }
    
    // MARK: - Función para cargar datos del usuario
    private func loadUserData() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Usuario no autenticado"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        firestoreService.fetchUserProfile(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    // Cargar datos del usuario
                    self.username = user.username
                    self.email = user.email
                    self.profileImagePath = user.profileImagePath
                    self.newBio = user.bio ?? ""
                    self.characterCount = self.newBio.count
                    self.selectedInterests = Set(user.interests)
                    
                    // ✅ AHORA SÍ: Cargamos el website
                    self.website = user.websiteUrl ?? ""
                    
                    self.isLoading = false
                    
                case .failure(let error):
                    self.errorMessage = "Error al cargar perfil: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Header del perfil
    private var profileHeader: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding(10)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }
                
                Spacer()
                
                Text("profileEditor.title")
                    .font(.system(size: legacyPoppinsSize(18), weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Button(action: { saveProfile() }) {
                    Text("common.save")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(characterCount <= 150 ? (colorScheme == .dark ? .white : .black) : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: characterCount <= 150))
                }
                .disabled(characterCount > 150)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            VStack(spacing: 20) {
                ZStack {
                    if let currentImage = currentProfileImage {
                        Image(uiImage: currentImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else if let path = profileImagePath, let url = URL(string: path) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            .frame(width: 110, height: 110)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.35))
                            )
                    }
                    
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 1)
                        .frame(width: 118, height: 118)
                    
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { isShowingPhotoActions = true }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .padding(8)
                                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                            }
                        }
                    }
                    .frame(width: 110, height: 110)
                }
                .onTapGesture {
                    isShowingPhotoActions = true
                }
                
                Button(action: { isShowingPhotoActions = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 14))
                        Text("profileEditor.change")
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                }
            }
            .padding(.bottom, 10)
        }
    }
    
    // MARK: - Pestañas de sección
    private var sectionTabs: some View {
        HStack(spacing: 10) {
            ForEach(EditSection.allCases, id: \.self) { section in
                Button(action: {
                    withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
                        activeSection = section
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(section.title)
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    }
                    .foregroundStyle(activeSection == section ? (colorScheme == .dark ? .white : .black) : (colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.55)))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        activeSection == section
                        ? AnyView(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                        : AnyView(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)))
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    // MARK: - Sección de perfil básico
    private var basicProfileSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "at")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                        
                        Text("profileEditor.username")
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                        
                        Spacer()
                        
                        Text("profileEditor.notEditable")
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                            .clipShape(Capsule())
                    }
                    
                    Text("\(username)")
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                        
                        Text("profileEditor.email")
                            .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                        
                        Spacer()
                        
                        Text("profileEditor.notEditable")
                            .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                            .clipShape(Capsule())
                    }
                    
                    Text(email)
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                profileInputField(
                    title: NSLocalizedString("profileEditor.website", comment: "Website"),
                    placeholder: "www.yoursite.com",
                    text: $website,
                    icon: "link"
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                    
                    Text("profileEditor.bio")
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    Text("\(characterCount)/150")
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundStyle(characterCount > 150 ? .red : (colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.45)))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $newBio)
                        .font(.system(size: legacyPoppinsSize(15)))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 100)
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onChange(of: newBio) { _, newValue in
                            characterCount = newValue.count
                        }
                    
                    if newBio.isEmpty {
                        Text("profileEditor.bio.placeholder")
                            .font(.system(size: legacyPoppinsSize(15)))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.28))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
    
    // MARK: - Sección de intereses
    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: - Information Card (Glass)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                    
                    Text("profileEditor.interests.title")
                        .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    Button(action: { isShowingInterestsPicker = true }) {
                        Text(NSLocalizedString("creator.edit", comment: ""))
                            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                    }
                }
                
                Text("profileEditor.interests.description")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                    .padding(.top, -10)
                
                // Grid de intereses seleccionados
                if selectedInterests.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.16))
                        
                        VStack(spacing: 4) {
                            Text("profileEditor.interests.empty.title")
                                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.78))
                            
                            Text("profileEditor.interests.empty.subtitle")
                                .font(.system(size: legacyPoppinsSize(13)))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        
                        Button(NSLocalizedString("profileEditor.addInterests", comment: "")) {
                            isShowingInterestsPicker = true
                        }
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ProfileFlowLayoutt(spacing: 10) {
                        ForEach(Array(selectedInterests.sorted()), id: \.self) { interest in
                            HStack(spacing: 6) {
                                Text(InterestPickerRow.interestEmoji(for: interest))
                                    .font(.system(size: 14))
                                Text(InterestOption.localize(interest))
                                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: false))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Componentes auxiliares
    private func profileInputField(title: String, placeholder: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                
                Text(title)
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
            }
            
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.28)))
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .padding(16)
                .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Sheet selector de intereses
    private var interestsPickerSheet: some View {
        VStack(spacing: 0) {
            interestPickerHeader
                .padding(.top, 14)
            
            interestPickerGrid
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Componentes del selector de intereses
    private var interestPickerHeader: some View {
        HStack(alignment: .center) {
            Button(action: { isShowingInterestsPicker = false }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(10)
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("profileEditor.interests.navigationTitle")
                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text("profileEditor.interests.select.title")
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.55))
            }
            
            Spacer()
            
            Text("\(selectedInterests.count)/5")
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundStyle(selectedInterests.count >= 5 ? .red : (colorScheme == .dark ? .white : .black))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: false))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var interestPickerGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(availableInterests, id: \.self) { interest in
                    InterestPickerRow(
                        interest: interest,
                        isSelected: selectedInterests.contains(interest),
                        isDisabled: !selectedInterests.contains(interest) && selectedInterests.count >= 5,
                        onTap: {
                            handleInterestTap(interest)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Función auxiliar para manejar la selección de intereses
    private func handleInterestTap(_ interest: String) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else if selectedInterests.count < 5 {
            selectedInterests.insert(interest)
        }
    }
    
    private var photoActionsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isShowingPhotoActions = false }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .padding(10)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }
                
                Spacer()
                
                Text("profileEditor.change")
                    .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Color.clear
                    .frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
            
            VStack(spacing: 0) {
                photoActionRow(
                    icon: "photo.on.rectangle",
                    title: NSLocalizedString("profileEditor.library", comment: "")
                ) {
                    isShowingPhotoActions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isShowingPhotoLibraryCrop = true
                    }
                }
                
                photoActionRow(
                    icon: "camera.fill",
                    title: NSLocalizedString("creator.camera", comment: "")
                ) {
                    isShowingPhotoActions = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isShowingCameraCapture = true
                    }
                }
                
                if currentProfileImage != nil || selectedPhoto != nil || profileImagePath != nil {
                    photoActionRow(
                        icon: "trash",
                        title: NSLocalizedString("profileEditor.deletePhoto.title", comment: ""),
                        isDestructive: true
                    ) {
                        isShowingPhotoActions = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .presentationDetents([.height(photoActionsSheetHeight)])
        .presentationDragIndicator(.visible)
    }
    
    private func photoActionRow(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDestructive ? .red.opacity(0.9) : (colorScheme == .dark ? .white : .black))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(isDestructive ? .red.opacity(0.9) : (colorScheme == .dark ? .white : .black))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
    }
    
    private var photoActionsSheetHeight: CGFloat {
        let rowCount: CGFloat = (currentProfileImage != nil || selectedPhoto != nil || profileImagePath != nil) ? 3 : 2
        return 96 + (rowCount * 52) + 24
    }
    
    private func uploadCapturedProfileImage(_ image: UIImage) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        errorMessage = nil
        
        firestoreService.fetchUserProfile(userId: userId) { result in
            let oldImagePath: String?
            switch result {
            case .success(let user):
                oldImagePath = user.profileImagePath
            case .failure:
                oldImagePath = nil
            }
            
            self.storageService.uploadProfileImage(userId: userId, image: image) { uploadResult in
                switch uploadResult {
                case .success(let newPath):
                    self.firestoreService.updateProfilePicture(userId: userId, profileImagePath: newPath) { error in
                        DispatchQueue.main.async {
                            self.isLoading = false
                            
                            if let error = error {
                                self.errorMessage = String(format: NSLocalizedString("profileEditor.error.updateProfile", comment: ""), error.localizedDescription)
                            } else {
                                self.profileImagePath = newPath
                                self.selectedPhoto = nil
                                self.storageService.deleteProfileImage(userId: userId, oldImagePath: oldImagePath) { _ in }
                            }
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = String(format: NSLocalizedString("profileEditor.error.uploadImage", comment: ""), error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func deleteCurrentProfileImage() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let oldImagePath = profileImagePath
        isLoading = true
        errorMessage = nil
        
        firestoreService.removeProfilePicture(userId: userId) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.isLoading = false
                    self.errorMessage = String(format: NSLocalizedString("profileEditor.error.updateProfile", comment: ""), error.localizedDescription)
                    return
                }
                
                self.storageService.deleteProfileImage(userId: userId, oldImagePath: oldImagePath) { _ in }
                self.currentProfileImage = nil
                self.selectedPhoto = nil
                self.profileImagePath = nil
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Función para guardar perfil
    private func saveProfile() {
        guard Auth.auth().currentUser?.uid != nil else {
            errorMessage = NSLocalizedString("profileEditor.error.unauthenticated", comment: "")
            return
        }
        
        // Mostrar indicador de guardado (aunque ahora es casi instantáneo)
        isLoading = true
        
        // Llamar a la función onSave que maneja bio, website e intereses
        // Nota: Pasamos nil para la foto siempre aquí para evitar que el ViewModel
        // intente subirla DE NUEVO, ya que nuestro picker ya lo hizo.
        onSave(nil, newBio, website.isEmpty ? nil : website, Array(selectedInterests))
        
        // Éxito inmediato (Optimistic UI) - cerrar la vista
        // No esperamos a Firestore ya que OfflineSyncService se encargará en el background
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isLoading = false
            self.dismiss()
        }
    }
    
    // MARK: - Función auxiliar para actualizar intereses
    private func updateUserInterests(userId: String, interests: [String], completion: @escaping (Error?) -> Void) {
        let userRef = firestoreService.db.collection("users").document(userId)
        userRef.updateData([
            "interests": interests
        ]) { error in
            completion(error)
        }
    }
}

// MARK: - Componente individual de interés
private struct InterestPickerRow: View {
    let interest: String
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(InterestPickerRow.interestEmoji(for: interest))
                    .font(.system(size: 16))
                Text(InterestOption.localize(interest))
                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                if isSelected {
                    Color.clear.momentsChromeGlass(in: RoundedRectangle(cornerRadius: 12), interactive: false)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ?
                        (colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)) :
                        (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isSelected), value: isSelected)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
    
    static func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}


// MARK: - Local Album Picker for Profile Editor
