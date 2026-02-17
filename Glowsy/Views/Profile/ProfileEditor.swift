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
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(10)
                    .background(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .contentShape(Rectangle()) // Área interactiva completa
            
            Spacer()
            
            Text(NSLocalizedString("profileEditor.library", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
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
                    .foregroundColor(.white)
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
                    .frame(width: UIScreen.main.bounds.width, height: 300)
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
                    .cornerRadius(12)
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
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
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
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.white)
                
                Text("profileEditor.uploadingTime")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.8))
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
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var requestPermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "007AFF"))
            
                            Text("profileEditor.photosAccess.title")
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(.white)
            
                            Text("profileEditor.photosAccess.description")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(NSLocalizedString("profileEditor.allowAccess", comment: "")) {
                requestPhotoLibraryPermission()
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.white)
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
                .foregroundColor(colorScheme == .dark ? .gray.opacity(0.8) : .gray.opacity(0.6))
            
            Text("profileEditor.accessDenied.title")
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("profileEditor.accessDenied.description")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // ✅ Instrucciones opcionales para el usuario
            Button("creator.permissions.openSettings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.white)
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
                                ) { deleteError in
                                    if let deleteError = deleteError {

                                    }
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
                    .font(.custom("Poppins-Medium", size: 14))
            }
            .foregroundColor(isSelected ? (colorScheme == .dark ? .white : .black) : (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)))
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
                        .frame(width: UIScreen.main.bounds.width / 3 - 4, height: UIScreen.main.bounds.width / 3 - 4)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: UIScreen.main.bounds.width / 3 - 4, height: UIScreen.main.bounds.width / 3 - 4)
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
                                    .foregroundColor(.white)
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
        
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width / 3 * UIScreen.main.scale,
            height: UIScreen.main.bounds.width / 3 * UIScreen.main.scale
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
    @State private var isShowingPhotoPicker: Bool = false
    @State private var currentProfileImage: UIImage?
    @State private var isShowingInterestsPicker: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var activeSection: EditSection = .basic
    
    // Estado de carga y error
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    // Servicio de Firestore
    private let firestoreService = FirestoreService()
    
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
        NavigationView {
            ZStack {
                // MARK: - 1. Immersive Background
                immersiveBackground
                
                if isLoading {
                    // Vista de carga
                    loadingView
                } else if let errorMessage = errorMessage {
                    // Vista de error
                    errorView(message: errorMessage)
                } else {
                    // Vista principal
                    VStack(spacing: 0) {
                        // Header con navegación Flotante
                        profileHeader
                            .padding(.top, 10)
                        
                        // Navegación por pestañas (simplificada)
                        if EditSection.allCases.count > 1 {
                            sectionTabs
                                .padding(.top, 10)
                        }
                        
                        // Contenido según la sección activa
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
            .navigationBarHidden(true)
            .sheet(isPresented: $isShowingPhotoPicker) {
                GridPhotoPickerView(
                    selectedPhoto: $selectedPhoto,
                    currentProfileImage: $currentProfileImage,
                    onUploadSuccess: {
                        // Si se subió una foto con éxito, ya no necesitamos subirla en onSave
                        self.selectedPhoto = nil 
                    }
                )
            }
            .sheet(isPresented: $isShowingInterestsPicker) {
                interestsPickerSheet
            }
            .alert("Eliminar foto de perfil", isPresented: $showingDeleteConfirmation) {
                Button("Eliminar", role: .destructive) {
                    currentProfileImage = nil
                    selectedPhoto = nil
                }
                Button("Cancelar", role: .cancel) { }
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
        ZStack {
            // Capa 1: Gradiente Base
            Color(hex: "0F2027").ignoresSafeArea()
            
            // Capa 2: Imagen desenfocada si existe
            GeometryReader { proxy in
                if let uiImage = currentProfileImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 50)
                        .opacity(0.4)
                } else if let path = profileImagePath, let url = URL(string: path) {
                    KFImage(url)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 50)
                        .opacity(0.4)
                } else {
                    LinearGradient(
                        colors: [Color(hex: "0F2027"), Color(hex: "203A43"), Color(hex: "2C5364")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.6)
                }
            }
            .ignoresSafeArea()
            
            // Capa 3: Overlay oscuro
            Color.black.opacity(0.4).ignoresSafeArea()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("profileEditor.loadingProfile")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red.opacity(0.8))
            
            Text("profileEditor.error")
                .font(.custom("Poppins-Bold", size: 18))
                .foregroundColor(.white)
            
            Text(message)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(NSLocalizedString("profileEditor.retry", comment: "")) {
                loadUserData()
            }
            .font(.custom("Poppins-SemiBold", size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(hex: "00A896"))
            .clipShape(Capsule())
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
                    self.selectedInterests = Set(user.interests ?? [])
                    
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
            // MARK: - Barra de Navegación Flotante
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                }
                
                Spacer()
                
                Text("profileEditor.title")
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                Spacer()
                
                Button(action: { saveProfile() }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(characterCount <= 150 ? Color(hex: "00A896") : Color.gray.opacity(0.5))
                        )
                        .shadow(radius: 5)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .disabled(characterCount > 150)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // MARK: - Avatar Central con Efectos Premium
            VStack(spacing: 20) {
                ZStack {
                    // Círculo de Brillo de Fondo
                    Circle()
                        .fill(Color(hex: "00A896").opacity(0.2))
                        .frame(width: 130, height: 130)
                        .blur(radius: 15)
                    
                    // Imagen de perfil o placeholder
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
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 110, height: 110)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    }
                    
                    // Borde Premium Animado (estático por ahora pero con gradiente)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "00A896"),
                                    Color.white.opacity(0.5),
                                    Color(hex: "00A896").opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 118, height: 118)
                    
                    // Botón de Cámara Overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { isShowingPhotoPicker = true }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color(hex: "00A896"))
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .frame(width: 110, height: 110)
                }
                .onTapGesture {
                    isShowingPhotoPicker = true
                }
                
                // Botones de Acción Rápidos (Cristal)
                HStack(spacing: 16) {
                    Button(action: { isShowingPhotoPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 14))
                            Text("profileEditor.change")
                                .font(.custom("Poppins-Medium", size: 13))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                    }
                    
                    if currentProfileImage != nil || selectedPhoto != nil {
                        Button(action: { showingDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }
    
    // MARK: - Pestañas de sección
    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(EditSection.allCases, id: \.self) { section in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            activeSection = section
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(section.title)
                                .font(.custom("Poppins-SemiBold", size: 14))
                        }
                        .foregroundColor(activeSection == section ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            ZStack {
                                if activeSection == section {
                                    Color(hex: "00A896").opacity(0.3)
                                    BlurView(style: .systemUltraThinMaterialDark)
                                } else {
                                    Color.white.opacity(0.05)
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    activeSection == section ?
                                    Color(hex: "00A896").opacity(0.8) :
                                    Color.white.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Sección de perfil básico
    private var basicProfileSection: some View {
        VStack(spacing: 24) {
            // MARK: - Information Card (Glass)
            VStack(spacing: 20) {
                // Nombre de usuario (solo lectura)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "at")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "00A896"))
                        
                        Text("profileEditor.username")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        Text("profileEditor.notEditable")
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Capsule())
                    }
                    
                    Text("\(username)")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                }
                
                // Email (solo lectura)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "00A896"))
                        
                        Text("profileEditor.email")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Spacer()
                        
                        Text("profileEditor.notEditable")
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Capsule())
                    }
                    
                    Text(email)
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                }
                
                // Sitio web (editable)
                profileInputField(
                    title: NSLocalizedString("profileEditor.website", comment: "Website"),
                    placeholder: "www.yoursite.com",
                    text: $website,
                    icon: "link"
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // MARK: - Bio Card (Glass)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "00A896"))
                    
                    Text("profileEditor.bio")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(characterCount)/150")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(characterCount > 150 ? .red : .white.opacity(0.5))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $newBio)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 100)
                        .padding(12)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                        .onChange(of: newBio) { newValue in
                            characterCount = newValue.count
                        }
                    
                    if newBio.isEmpty {
                        Text("profileEditor.bio.placeholder")
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
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
                        .foregroundColor(Color(hex: "00A896"))
                    
                    Text("profileEditor.interests.title")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { isShowingInterestsPicker = true }) {
                        Text(NSLocalizedString("creator.edit", comment: ""))
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(Color(hex: "00A896"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "00A896").opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                Text("profileEditor.interests.description")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, -10)
                
                // Grid de intereses seleccionados
                if selectedInterests.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.2))
                        
                        VStack(spacing: 4) {
                            Text("profileEditor.interests.empty.title")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("profileEditor.interests.empty.subtitle")
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        
                        Button(NSLocalizedString("profileEditor.addInterests", comment: "")) {
                            isShowingInterestsPicker = true
                        }
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "00A896"))
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                } else {
                    // Flow layout de intereses seleccionados
                    ProfileFlowLayoutt(spacing: 10) {
                        ForEach(Array(selectedInterests.sorted()), id: \.self) { interest in
                            HStack(spacing: 6) {
                                Text(InterestPickerRow.interestEmoji(for: interest))
                                    .font(.system(size: 14))
                                Text(InterestOption.localize(interest))
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                        }
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Componentes auxiliares
    private func profileInputField(title: String, placeholder: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "00A896"))
                
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white)
                .padding(16)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Sheet selector de intereses
    private var interestsPickerSheet: some View {
        NavigationView {
            ZStack {
                immersiveBackground
                
                VStack(spacing: 0) {
                    // Header con contador
                    interestPickerHeader
                        .padding(.top, 20)
                    
                    // Grid de intereses
                    interestPickerGrid
                }
            }
            .navigationTitle(NSLocalizedString("profileEditor.interests.navigationTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("profileEditor.done", comment: "")) {
                        isShowingInterestsPicker = false
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Componentes del selector de intereses
    private var interestPickerHeader: some View {
        HStack {
            Text("profileEditor.interests.select.title")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Text("\(selectedInterests.count)/5")
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(selectedInterests.count >= 5 ? .red : Color(hex: "00A896"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
    
    // MARK: - Función para guardar perfil
    private func saveProfile() {
        guard let userId = Auth.auth().currentUser?.uid else {
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
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isSelected ?
                Color(hex: "00A896").opacity(0.2) :
                (colorScheme == .dark ? Color.white : Color.black).opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ?
                        Color(hex: "00A896") :
                        (colorScheme == .dark ? Color.white : Color.black).opacity(0.2),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
    
    static func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}


// MARK: - Local Album Picker for Profile Editor
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
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
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
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(String(format: NSLocalizedString("profileEditor.album.photosCount", comment: ""), album.assetCount))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
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


