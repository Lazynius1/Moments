import SwiftUI
import PhotosUI
import Photos

// MARK: -  Profile Picture Editor
struct PhotoCropEditorView: View {
    @Environment(\.dismiss) var dismiss
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
    
    private let imageManager = PHImageManager.default()
    private let cropSize: CGFloat = 360 // Área cuadrada de trabajo
    private let outputSize: CGSize = CGSize(width: 400, height: 400) // ✅ COINCIDIR CON STORAGESERVICE
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoadingImage {
                loadingView
            } else if let image = fullResolutionImage {
                VStack(spacing: 0) {
                    headerView
                    cropAreaView(with: image)
                    photoGridSection()
                    Spacer()
                }
            }
            
            if isProcessing {
                processingOverlay
            }
        }
        .onAppear {
            loadFullResolutionImage()
            loadRecentPhotos()
        }
    }
    
    // MARK: - Vista de carga
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "00A896"))
            
            Text("Cargando imagen...")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.white.opacity(0.8))
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
                Text("Cancelar")
                    .font(.custom("Poppins-Regular", size: 17))
                    .foregroundColor(.white.opacity(isProcessing ? 0.4 : 0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(isProcessing ? 0.1 : 0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(isProcessing ? 0.2 : 0.3), lineWidth: 1)
                    )
            }
            .disabled(isProcessing)
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Text("Mover y escalar")
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                print("🔵 Botón 'Listo' presionado")
                // Feedback háptico para confirmar la pulsación
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                cropAndSaveImage()
            }) {
                Text("Listo")
                    .font(.custom("Poppins-SemiBold", size: 17))
                    .foregroundColor(isProcessing ? .gray : Color(hex: "00A896"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isProcessing ? Color.gray.opacity(0.3) : Color(hex: "00A896").opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isProcessing ? Color.gray.opacity(0.5) : Color(hex: "00A896").opacity(0.5), lineWidth: 1)
                    )
            }
            .disabled(isProcessing)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Área de crop cuadrada
    private func cropAreaView(with image: UIImage) -> some View {
        VStack(spacing: 0) {
            // ✅ Sin texto explicativo - el usuario ya sabe qué hacer 😄
            Spacer()
                .frame(height: 20)
            
            // Área de crop cuadrada
            ZStack {
                // Fondo oscuro
                Rectangle()
                    .fill(Color.black)
                    .frame(width: cropSize, height: cropSize)
                
                // Imagen manipulable
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: cropSize * scale,
                        height: (cropSize * scale) / (image.size.width / image.size.height)
                    )
                    .offset(CGSize(width: offset.width + gestureTranslation.width, height: offset.height + gestureTranslation.height))
                    .clipped()
                    // ✅ EFECTOS VISUALES SUTILES DURANTE GESTOS
                    .scaleEffect(isDragging || isZooming ? 1.01 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isDragging)
                    .animation(.easeInOut(duration: 0.2), value: isZooming)
                    .gesture(
                        SimultaneousGesture(
                            // ✅ DRAG GESTURE MEJORADO
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
                                        
                                        // ✅ FEEDBACK HÁPTICO SUAVE
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                        impactFeedback.impactOccurred()
                                        
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            offset = limitOffset(newOffset, imageSize: image.size)
                                        }
                                    }
                                },
                            
                            // ✅ MAGNIFICATION GESTURE MEJORADO
                            MagnificationGesture()
                                .onChanged { value in
                                    if !isProcessing {
                                        isZooming = true
                                        let newScale = lastScale * value
                                        scale = max(getMinimumScale(for: image.size), min(newScale, 4.0))
                                        offset = limitOffset(offset, imageSize: image.size)
                                    }
                                }
                                .onEnded { _ in
                                    if !isProcessing {
                                        isZooming = false
                                        lastScale = scale
                                        
                                        // ✅ FEEDBACK HÁPTICO PARA ZOOM
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                        impactFeedback.impactOccurred()
                                        
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            offset = limitOffset(offset, imageSize: image.size)
                                        }
                                    }
                                }
                        )
                    )
                    // ✅ GESTO DE DOBLE TAP PARA RESET
                    .onTapGesture(count: 2) {
                        if !isProcessing {
                            resetToInitialPosition(for: image.size)
                        }
                    }
                
                // Grid de ayuda sutil
                gridOverlay
                    .allowsHitTesting(false)
                
                // ✅ Círculo que muestra EXACTAMENTE el área de crop final
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 3)
                    .frame(width: cropSize, height: cropSize)
                    .allowsHitTesting(false)
                

                
                // ✅ Indicador de estado de gestos (sutil)
                if isDragging || isZooming {
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        .frame(width: cropSize, height: cropSize)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: cropSize, height: cropSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))
            .onAppear {
                setupInitialTransform(for: image.size)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Grid de ayuda
    private var gridOverlay: some View {
        ZStack {
            // Líneas verticales
            HStack(spacing: cropSize / 3 - 1) {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: cropSize)
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: cropSize)
            }
            
            // Líneas horizontales
            VStack(spacing: cropSize / 3 - 1) {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: cropSize, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: cropSize, height: 1)
            }
        }
    }
    
    // MARK: - Grid de fotos completo (como ProfileEditor)
    private func photoGridSection() -> some View {
        VStack(spacing: 16) {
            Text("Otras fotos")
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 30)
            
            // Grid de fotos recientes
            if isLoadingRecentPhotos {
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 70, height: 70)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                        spacing: 2
                    ) {
                        ForEach(photoAssets.indices, id: \.self) { index in
                            let asset = photoAssets[index]
                            
                            PhotoGridItem(
                                asset: asset,
                                isSelected: false, // No hay selección en el editor
                                imageManager: imageManager
                            ) {
                                selectNewPhotoFromGrid(asset)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Configuración inicial
    private func setupInitialTransform(for imageSize: CGSize) {
        let optimalScale = getMinimumScale(for: imageSize)
        let smartOffset = calculateSmartOffset(imageSize: imageSize, scale: optimalScale)
        
        withAnimation(.easeOut(duration: 0.5)) {
            scale = optimalScale
            lastScale = optimalScale
            offset = smartOffset
        }
    }
    
    // ✅ FUNCIÓN: Reset a posición inicial
    private func resetToInitialPosition(for imageSize: CGSize) {
        let optimalScale = getMinimumScale(for: imageSize)
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
        let scaleX = cropSize / imageSize.width
        let scaleY = cropSize / imageSize.height
        return max(scaleX, scaleY, 1.0)
    }
    
    private func calculateSmartOffset(imageSize: CGSize, scale: CGFloat) -> CGSize {
        let imageAspectRatio = imageSize.width / imageSize.height
        let scaledImageWidth = cropSize * scale
        let scaledImageHeight = scaledImageWidth / imageAspectRatio
        
        var smartOffsetY: CGFloat = 0
        var smartOffsetX: CGFloat = 0
        
        if imageAspectRatio < 1.0 {
            let availableMovement = (scaledImageHeight - cropSize) / 2
            smartOffsetY = availableMovement * 0.3
        }
        
        return limitOffset(
            CGSize(width: smartOffsetX, height: smartOffsetY),
            imageSize: imageSize
        )
    }
    
    private func limitOffset(_ proposedOffset: CGSize, imageSize: CGSize) -> CGSize {
        let imageAspectRatio = imageSize.width / imageSize.height
        let scaledImageWidth = cropSize * scale
        let scaledImageHeight = scaledImageWidth / imageAspectRatio
        
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
                self.fullResolutionImage = image
                self.isLoadingImage = false
            }
        }
    }
    
    // MARK: - Overlay de procesamiento
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                
                Text("Procesando...")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Función de crop final
    private func cropAndSaveImage() {
        print("🔵 cropAndSaveImage() iniciado")
        guard let image = fullResolutionImage else { 
            print("❌ No hay imagen para procesar")
            return 
        }
        
        print("🔵 Imagen encontrada, iniciando procesamiento...")
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            print("🔵 Procesando imagen en background...")
            guard let croppedImage = self.cropSquareImage(from: image) else {
                print("❌ Error al recortar imagen")
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }
            
            print("🔵 Imagen recortada exitosamente")
            DispatchQueue.main.async {
                print("🔵 Llamando onSave con imagen recortada")
                self.isProcessing = false
                self.onSave(croppedImage)
                print("🔵 Cerrando PhotoCropEditorView")
                self.dismiss()
            }
        }
    }
    
    // MARK: - Crop final - PERFECTO PARA PROFILEVIEW (110x110)
    private func cropSquareImage(from image: UIImage) -> UIImage? {
        let imageSize = image.size
        let aspectRatio = imageSize.width / imageSize.height
        
        // ✅ GENERAR IMAGEN CUADRADA DE 400x400 (sin clip circular)
        UIGraphicsBeginImageContextWithOptions(outputSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // ✅ EXACTAMENTE la misma lógica que el preview
        let scaledWidth = cropSize * scale
        let scaledHeight = scaledWidth / aspectRatio
        
        // Factor de escala del output respecto al área de crop
        let scaleFactorToFinal = outputSize.width / cropSize
        
        // Aplicar las transformaciones
        let finalWidth = scaledWidth * scaleFactorToFinal
        let finalHeight = scaledHeight * scaleFactorToFinal
        let finalOffsetX = offset.width * scaleFactorToFinal
        let finalOffsetY = offset.height * scaleFactorToFinal
        
        // ✅ CENTRAR la imagen en el área de output
        let centerX = (outputSize.width - finalWidth) / 2
        let centerY = (outputSize.height - finalHeight) / 2
        
        let drawRect = CGRect(
            x: centerX - finalOffsetX,
            y: centerY - finalOffsetY,
            width: finalWidth,
            height: finalHeight
        )
        
        image.draw(in: drawRect)
        
        // ✅ IMPORTANTE: NO aplicar clip circular aquí
        // ProfileView se encargará de mostrar la imagen a 110x110 con clip circular
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Funciones para el grid de fotos
    private func loadRecentPhotos() {
        isLoadingRecentPhotos = true
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 50 // Más fotos para el grid
        
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
                self.fullResolutionImage = image
                self.isLoadingImage = false
                
                // Resetear transformaciones para la nueva imagen
                if let image = image {
                    self.setupInitialTransform(for: image.size)
                }
            }
        }
    }
}

// MARK: - Photo Grid Item (copiado de ProfileEditor)
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
                
                // Overlay de selección (no usado en el editor, pero mantenemos la estructura)
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
