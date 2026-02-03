import SwiftUI
import PhotosUI
import Photos

// MARK: - Extensión para normalizar orientación de imagen
extension UIImage {
    func normalized() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
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
    
    private let imageManager = PHImageManager.default()
    private let cropSize: CGFloat = 400 // ✅ Área circular de trabajo (mismo tamaño que outputSize)
    private let outputSize: CGSize = CGSize(width: 400, height: 400) // ✅ COINCIDIR CON STORAGESERVICE
    
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
                        VStack(spacing: 24) {
                            // Área de Crop
                            cropAreaView(with: image)
                                .padding(.top, 20)
                            
                            // Sección de Galería (Estilo Glass)
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
            loadRecentPhotos()
        }
    }
    
    // MARK: - Vista de carga
    private var immersiveBackground: some View {
        ZStack {
            // Capa 1: Fondo Adaptativo
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            // Capa 2: Imagen desenfocada
            if let image = fullResolutionImage {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped() // ✅ IMPORTANTE: Evitar que la imagen horizontal expanda el layout
                }
                .blur(radius: 60)
                .opacity(colorScheme == .dark ? 0.4 : 0.2)
                .ignoresSafeArea()
            }
            
            // Capa 3: Overlay gradiente para profundidad
            LinearGradient(
                colors: [
                    (colorScheme == .dark ? Color.black : Color.white).opacity(0.6),
                    .clear,
                    (colorScheme == .dark ? Color.black : Color.white).opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(colorScheme == .dark ? .white : .black)
            
            Text(NSLocalizedString("profileEditor.crop.loadingImage", comment: ""))
                .font(.custom("Poppins-Medium", size: 16))
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
                .font(.custom("Poppins-SemiBold", size: 17))
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
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(isProcessing ? Color.gray.opacity(0.5) : Color(hex: "00A896"))
                    )
                    .shadow(radius: 5)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }
            .disabled(isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Área de crop cuadrada
    private func cropAreaView(with image: UIImage) -> some View {
        VStack(spacing: 16) {
            // MARK: - Crop Base
            ZStack {
                // Sombra de Profundidad
                Circle()
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1))
                    .frame(width: cropSize + 10, height: cropSize + 10)
                    .blur(radius: 20)
                
                // Imagen manipulable
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cropSize, height: cropSize)
                    .scaleEffect(scale)
                    .offset(CGSize(width: offset.width + gestureTranslation.width, height: offset.height + gestureTranslation.height))
                    .clipped() // ✅ VOLVER A AÑADIR: Evitar que la imagen se vea fuera del círculo
                    .scaleEffect(isDragging || isZooming ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
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
                
                // Grid de ayuda elegante
                if isDragging || isZooming {
                    gridOverlay
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                // Máscara Circular Premium
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                (colorScheme == .dark ? Color.white : Color.primary).opacity(0.8),
                                (colorScheme == .dark ? Color.white : Color.primary).opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: cropSize, height: cropSize)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                            .padding(-1)
                    )
                    .allowsHitTesting(false)
            }
            .frame(width: cropSize, height: cropSize)
            .clipShape(Circle())
            .overlay(
                // Guía visual de "área segura"
                Circle()
                    .stroke((colorScheme == .dark ? Color.white : Color.primary).opacity(0.1), lineWidth: 20)
                    .frame(width: cropSize + 22, height: cropSize + 22)
                    .blur(radius: 5)
            )
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
    }
    
    // MARK: - Grid de fotos completo (como ProfileEditor)
    private func photoGridSection() -> some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "00A896"))
                
                Text(NSLocalizedString("profileEditor.crop.otherPhotos", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            
            // Contenedor Glass para el Grid
            ZStack {
                if isLoadingRecentPhotos {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                        spacing: 4
                    ) {
                        ForEach(photoAssets.prefix(12).indices, id: \.self) { index in
                            let asset = photoAssets[index]
                            
                            PhotoGridItem(
                                asset: asset,
                                isSelected: false,
                                imageManager: imageManager
                            ) {
                                selectNewPhotoFromGrid(asset)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
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
        
        // ✅ Para cubrir el círculo, necesitamos la escala que cubra el lado más corto (aspect fill)
        let minScale = max(scaleX, scaleY) 
        return max(minScale, 0.5)
    }
    
    private func calculateSmartOffset(imageSize: CGSize, scale: CGFloat) -> CGSize {
        // ✅ CENTRAR PERFECTAMENTE la imagen en el área de crop
        // No aplicar offsets automáticos que causen desalineación
        return CGSize.zero
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
                    .font(.custom("Poppins-Medium", size: 16))
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
        let aspectRatio = imageSize.width / imageSize.height
        
        // ✅ GENERAR IMAGEN DE 400x400 (mismo tamaño que cropSize)
        UIGraphicsBeginImageContextWithOptions(outputSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // ✅ CÁLCULO LIBRE: Sin límites restrictivos
        let scaledWidth = cropSize * scale
        let scaledHeight = scaledWidth / aspectRatio
        
        // ✅ CENTRAR la imagen en el área de output
        let centerX = (outputSize.width - scaledWidth) / 2
        let centerY = (outputSize.height - scaledHeight) / 2
        
        // ✅ APLICAR OFFSET LIBREMENTE: Sin restricciones
        let finalX = centerX + offset.width
        let finalY = centerY + offset.height
        
        // ✅ PRIMERO: Dibujar fondo blur de la imagen completa
        let blurImage = image.withBlur(radius: 25) // ✅ BLUR INTENSO para fondo real
        let backgroundRect = CGRect(origin: .zero, size: outputSize)
        blurImage.draw(in: backgroundRect)
        
        // ✅ SEGUNDO: Agregar overlay oscuro sobre el blur para fondo real
        let overlayColor = UIColor.black.withAlphaComponent(0.3)
        overlayColor.setFill()
        context.fill(backgroundRect)
        
        // ✅ TERCERO: Dibujar la imagen principal en la posición elegida por el usuario
        let drawRect = CGRect(
            x: finalX,
            y: finalY,
            width: scaledWidth,
            height: scaledHeight
        )
        image.draw(in: drawRect)
        
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        
        return resultImage
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
                self.fullResolutionImage = image?.normalized()
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
    @Environment(\.colorScheme) var colorScheme
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
                                .tint(colorScheme == .dark ? .white : .black)
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
                                        .background(Circle().fill(colorScheme == .dark ? .black : .white))
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
