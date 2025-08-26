import SwiftUI
import PhotosUI
import FirebaseAuth
import Photos

// MARK: - ACTUALIZACIÓN: GridPhotoPickerView con Editor de Crop
struct GridPhotoPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var currentProfileImage: UIImage?
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
    
    
    private let imageManager = PHImageManager.default()
    private let firestoreService = FirestoreService()
    private let storageService = StorageService()
    
    enum PhotoCategory: CaseIterable {
        case recent, photography, selfies, albums
        
        var title: String {
            switch self {
            case .recent: return "Recientes"
            case .photography: return "Fotografía"
            case .selfies: return "Selfies"
            case .albums: return "Álbumes"
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
        NavigationView {
            ZStack {
                // Fondo consistente con tu app
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header con navegación
                    headerView
                    
                    // Contenido según estado de autorización
                    if authorizationStatus == .authorized || authorizationStatus == .limited {
                        if isLoading {
                            loadingView
                        } else {
                            photoGridView
                        }
                    } else if authorizationStatus == .denied {
                        deniedPermissionView
                    } else {
                        requestPermissionView
                    }
                }
                
                // Overlay de upload
                if isUploading {
                    uploadingOverlay
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            checkPhotoLibraryPermission()
        }
        .alert("Error al subir imagen", isPresented: $showUploadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadError ?? "Error desconocido")
        }
        // NUEVO: Sheet para el editor de crop natural
        .sheet(isPresented: $isShowingCropEditor) {
            if let assetForCrop = selectedAssetForCrop {
                PhotoCropEditorView(
                    originalAsset: assetForCrop, // Pasamos el asset
                    onSave: { croppedImage in
                        // Guardar la imagen recortada
                        currentProfileImage = croppedImage
                        uploadImageToFirebaseWithCleanup(image: croppedImage, userId: Auth.auth().currentUser?.uid ?? "")
                    }
                )
            }
        }
    }
    
    // MARK: - Header View (sin cambios)
    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancelar") {
                    if !isUploading {
                        dismiss()
                    }
                }
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white.opacity(isUploading ? 0.4 : 0.8))
                .disabled(isUploading)
                
                Spacer()
                
                Text("profileEditor.library")
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(.white)
                
                Spacer()
                
                // ACTUALIZADO: Cambio de texto del botón
                Button("Siguiente") {
                    handlePhotoSelection()
                }
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(selectedAsset != nil && !isUploading ? Color(hex: "00A896") : .gray)
                .disabled(selectedAsset == nil || isUploading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Filtros de categoría
            if !isUploading {
                categoryFilters
            }
        }
    }
    
    // NUEVO: Overlay de upload actualizado
    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color(hex: "00A896"))
                
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
    
    // MARK: - Category Filters (sin cambios)
    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PhotoCategory.allCases, id: \.self) { category in
                    CategoryFilterButton(
                        title: category.title,
                        icon: category.icon,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                        loadPhotosForCategory(category)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Photo Grid View (sin cambios significativos)
    private var photoGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                spacing: 2
            ) {
                ForEach(photoAssets.indices, id: \.self) { index in
                    let asset = photoAssets[index]
                    
                    PhotoGridItem(
                        asset: asset,
                        isSelected: selectedAsset?.localIdentifier == asset.localIdentifier,
                        imageManager: imageManager
                    ) {
                        if !isUploading {
                            selectedAsset = asset
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Loading, Permission Views (sin cambios)
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "00A896"))
            
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
                .foregroundColor(Color(hex: "00A896"))
            
                            Text("profileEditor.photosAccess.title")
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(.white)
            
                            Text("profileEditor.photosAccess.description")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Permitir acceso") {
                requestPhotoLibraryPermission()
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color(hex: "00A896"))
            .clipShape(Capsule())
            .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var deniedPermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red.opacity(0.8))
            
                            Text("profileEditor.accessDenied.title")
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(.white)
            
                            Text("profileEditor.accessDenied.description")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Abrir Configuración") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color(hex: "00A896"))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Functions (sin cambios)
    private func checkPhotoLibraryPermission() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadPhotosForCategory(.recent)
        }
    }
    
    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                authorizationStatus = status
                if status == .authorized || status == .limited {
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
    private func uploadImageToFirebaseWithCleanup(image: UIImage, userId: String) {
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
                                self.uploadError = "Error al actualizar perfil: \(error.localizedDescription)"
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
                            }
                        }
                    }
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.uploadError = "Error al subir imagen: \(error.localizedDescription)"
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
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.custom("Poppins-Medium", size: 14))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ?
                Color(hex: "00A896").opacity(0.3) :
                Color.white.opacity(0.1)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ?
                        Color(hex: "00A896") :
                        Color.white.opacity(0.2),
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
                
                // Overlay de selección
                if isSelected {
                    Rectangle()
                        .fill(.clear)
                        .frame(width: UIScreen.main.bounds.width / 3 - 4, height: UIScreen.main.bounds.width / 3 - 4)
                        .overlay(
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color(hex: "00A896"))
                                        .background(Circle().fill(.white))
                                        .padding(8)
                                }
                                Spacer()
                            }
                        )
                        .overlay(
                            Rectangle()
                                .stroke(Color(hex: "00A896"), lineWidth: 3)
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
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var newBio: String
    var onSave: (PhotosPickerItem?, String) -> Void
    
    // Estados para edición de perfil - AHORA CON DATOS REALES
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var website: String = ""
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
            case .basic: return "Perfil"
            case .interests: return "Intereses"
            }
        }
        
        var icon: String {
            switch self {
            case .basic: return "person.crop.circle"
            case .interests: return "heart.circle"
            }
        }
    }
    
    // Lista de intereses disponibles
    private let availableInterests = [
        "Música", "Cine", "Deportes", "Viajes", "Fotografía", "Arte", "Tecnología",
        "Lectura", "Cocina", "Moda", "Gaming", "Fitness", "Naturaleza", "Animales",
        "Baile", "Teatro", "Escritura", "Ciencia", "Historia", "Idiomas", "Anime",
        "K-pop", "Streaming", "Yoga", "Meditación", "Senderismo", "Ciclismo"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                // Fondo glassmorphic consistente con tu app
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if isLoading {
                    // Vista de carga
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color(hex: "00A896"))
                        
                        Text("profileEditor.loadingProfile")
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if let errorMessage = errorMessage {
                    // Vista de error
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red.opacity(0.8))
                        
                        Text("profileEditor.error")
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(.white)
                        
                        Text(errorMessage)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button("Reintentar") {
                            loadUserData()
                        }
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "00A896"))
                        .clipShape(Capsule())
                    }
                } else {
                    // Vista principal
                    VStack(spacing: 0) {
                        // Header con navegación
                        profileHeader
                        
                        // Navegación por pestañas (simplificada)
                        if EditSection.allCases.count > 1 {
                            sectionTabs
                        }
                        
                        // Contenido según la sección activa
                        ScrollView {
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
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $isShowingPhotoPicker) {
                GridPhotoPickerView(
                    selectedPhoto: $selectedPhoto,
                    currentProfileImage: $currentProfileImage
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
                    self.newBio = user.bio ?? ""
                    self.characterCount = self.newBio.count
                    self.selectedInterests = Set(user.interests ?? [])
                    
                    // Nota: website no está en el modelo AppUser actual
                    // Si lo añades al modelo, descomenta esta línea:
                    // self.website = user.website ?? ""
                    
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
        VStack(spacing: 20) {
            // Barra de navegación
            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text("profileEditor.title")
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Guardar") {
                    saveProfile()
                }
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(Color(hex: "00A896"))
                .disabled(characterCount > 150)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Avatar con opciones de edición
            VStack(spacing: 16) {
                ZStack {
                    // Imagen de perfil actual o placeholder
                    if let currentImage = currentProfileImage {
                        Image(uiImage: currentImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray.opacity(0.6))
                            )
                    }
                    
                    // Overlay para editar
                    Circle()
                        .fill(.black.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        )
                }
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "00A896").opacity(0.6),
                                    Color.white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .onTapGesture {
                    isShowingPhotoPicker = true
                }
                
                // Opciones de foto
                HStack(spacing: 24) {
                    Button(action: { isShowingPhotoPicker = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.circle")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "00A896"))
                            Text("profileEditor.change")
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    if currentProfileImage != nil || selectedPhoto != nil {
                        Button(action: { showingDeleteConfirmation = true }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red.opacity(0.8))
                                Text("profileEditor.delete")
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Pestañas de sección
    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(EditSection.allCases, id: \.self) { section in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            activeSection = section
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14))
                            Text(section.title)
                                .font(.custom("Poppins-Medium", size: 14))
                        }
                        .foregroundColor(activeSection == section ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            activeSection == section ?
                            Color(hex: "00A896").opacity(0.3) :
                            Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    activeSection == section ?
                                    Color(hex: "00A896") :
                                    Color.white.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Sección de perfil básico
    private var basicProfileSection: some View {
        VStack(spacing: 20) {
            // Nombre de usuario (solo lectura)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "at")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "00A896"))
                        .frame(width: 24)
                    
                    Text("profileEditor.username")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                HStack {
                    Text("\(username)")
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("No editable")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            // Email (solo lectura)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "envelope")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "00A896"))
                        .frame(width: 24)
                    
                    Text("profileEditor.email")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                HStack {
                    Text(email)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("No editable")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            // Sitio web (editable, pero no está en el modelo actual)
            /*
            profileInputField(
                title: "Sitio web",
                placeholder: "www.tusitio.com",
                text: $website,
                icon: "globe"
            )
            */
            
            // Editor de biografía
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "00A896"))
                        .frame(width: 24)
                    
                    Text("profileEditor.bio")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    Text("\(characterCount)/150")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(characterCount > 150 ? .red : .gray.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color(hex: "00A896").opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    
                    TextEditor(text: $newBio)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(.white)
                        .background(.clear)
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .onChange(of: newBio) { newValue in
                            characterCount = newValue.count
                        }
                    
                    if newBio.isEmpty {
                        Text("profileEditor.bio.placeholder")
                            .font(.custom("Poppins-Regular", size: 15))
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
    
    // MARK: - Sección de intereses
    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "heart.circle")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "00A896"))
                
                Text("profileEditor.interests.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Button("Editar") {
                    isShowingInterestsPicker = true
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(Color(hex: "00A896"))
            }
            
                            Text("profileEditor.interests.description")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray.opacity(0.7))
                .padding(.top, -10)
            
            // Grid de intereses seleccionados
            if selectedInterests.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("profileEditor.interests.empty.title")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("profileEditor.interests.empty.subtitle")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    Button("Añadir intereses") {
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
                .padding(.vertical, 40)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            } else {
                // Flow layout de intereses seleccionados
                ProfileFlowLayoutt(spacing: 8) {
                    ForEach(Array(selectedInterests.sorted()), id: \.self) { interest in
                        HStack(spacing: 6) {
                            Text(InterestPickerRow.interestEmoji(for: interest))
                                .font(.system(size: 14))
                            Text(interest)
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color(hex: "00A896").opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            }
        }
    }
    
    // MARK: - Componentes auxiliares
    private func profileInputField(title: String, placeholder: String, text: Binding<String>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "00A896"))
                    .frame(width: 24)
                
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            TextField(placeholder, text: text)
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(.white)
                .padding(16)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Sheet selector de intereses
    private var interestsPickerSheet: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header con contador
                    interestPickerHeader
                    
                    // Grid de intereses
                    interestPickerGrid
                }
            }
            .navigationTitle("Intereses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
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
                .padding(.horizontal, 8)
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
            errorMessage = "Usuario no autenticado"
            return
        }
        
        // Mostrar indicador de guardado
        isLoading = true
        
        // Crear un grupo de dispatch para manejar múltiples operaciones
        let saveGroup = DispatchGroup()
        var saveErrors: [Error] = []
        
        // Guardar biografía si cambió
        saveGroup.enter()
        firestoreService.updateBio(userId: userId, bio: newBio) { error in
            if let error = error {
                saveErrors.append(error)
            }
            saveGroup.leave()
        }
        
        // Guardar intereses si cambiaron
        saveGroup.enter()
        updateUserInterests(userId: userId, interests: Array(selectedInterests)) { error in
            if let error = error {
                saveErrors.append(error)
            }
            saveGroup.leave()
        }
        
        // Guardar foto si se seleccionó una nueva
        if let photo = selectedPhoto {
            saveGroup.enter()
            // Usar la función onSave para manejar la foto
            onSave(photo, newBio)
            saveGroup.leave()
        }
        
        // Cuando todas las operaciones terminen
        saveGroup.notify(queue: .main) {
            self.isLoading = false
            
            if saveErrors.isEmpty {
                // Éxito - cerrar la vista
                self.dismiss()
            } else {
                // Mostrar errores
                let errorMessages = saveErrors.map { $0.localizedDescription }.joined(separator: "\n")
                self.errorMessage = "Error al guardar: \(errorMessages)"
            }
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
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(InterestPickerRow.interestEmoji(for: interest))
                    .font(.system(size: 16))
                Text(interest)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.white)
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
                Color.white.opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ?
                        Color(hex: "00A896") :
                        Color.white.opacity(0.2),
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
        switch interest.lowercased() {
        case "música": return "🎵"
        case "cine": return "🎬"
        case "deportes": return "⚽"
        case "viajes": return "✈️"
        case "fotografía": return "📸"
        case "arte": return "🎨"
        case "tecnología": return "💻"
        case "lectura": return "📚"
        case "cocina": return "👨‍🍳"
        case "moda": return "👗"
        case "gaming": return "🎮"
        case "fitness": return "💪"
        case "naturaleza": return "🌿"
        case "animales": return "🐾"
        case "baile": return "💃"
        case "teatro": return "🎭"
        case "escritura": return "✍️"
        case "ciencia": return "🔬"
        case "historia": return "📜"
        case "idiomas": return "🗣️"
        case "anime": return "🍜"
        case "k-pop": return "🎤"
        case "streaming": return "📺"
        case "yoga": return "🧘"
        case "meditación": return "🕯️"
        case "senderismo": return "🥾"
        case "ciclismo": return "🚴"
        default: return "✨"
        }
    }
}


