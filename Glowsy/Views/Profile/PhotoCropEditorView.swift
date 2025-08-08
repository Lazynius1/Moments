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
    
    private let imageManager = PHImageManager.default()
    private let cropSize: CGFloat = 360 // Área cuadrada de trabajo
    private let outputSize: CGSize = CGSize(width: 400, height: 400) // ✅ COINCIDIR CON STORAGESERVICE
    
    // ✅ TAMAÑO FINAL EN EL PERFIL
    private let profileDisplaySize: CGFloat = 110
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoadingImage {
                loadingView
            } else if let image = fullResolutionImage {
                VStack(spacing: 0) {
                    headerView
                    cropAreaView(with: image)
                    previewSection(with: image)
                    Spacer()
                }
            }
            
            if isProcessing {
                processingOverlay
            }
        }
        .onAppear {
            loadFullResolutionImage()
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
            Button("Cancelar") {
                if !isProcessing {
                    dismiss()
                }
            }
            .font(.custom("Poppins-Regular", size: 17))
            .foregroundColor(.white)
            .disabled(isProcessing)
            
            Spacer()
            
            Text("Mover y escalar")
                .font(.custom("Poppins-SemiBold", size: 17))
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Listo") {
                cropAndSaveImage()
            }
            .font(.custom("Poppins-SemiBold", size: 17))
            .foregroundColor(isProcessing ? .gray : Color(hex: "00A896"))
            .disabled(isProcessing)
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
                
                // ✅ Indicador de área de crop
                VStack(spacing: 2) {
                    Image(systemName: "crop")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                    Text("Área de crop")
                        .font(.custom("Poppins-Bold", size: 8))
                        .foregroundColor(.white)
                }
                .background(Color.black.opacity(0.7))
                .clipShape(Capsule())
                .padding(4)
                .offset(x: cropSize * 0.3, y: -cropSize * 0.3)
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
    
    // MARK: - Sección de preview circular
    private func previewSection(with image: UIImage) -> some View {
        VStack(spacing: 16) {
            Text("Vista previa")
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 30)
            
            HStack(spacing: 30) {
                // Preview pequeño
                VStack(spacing: 8) {
                    createCircularPreview(image: image, size: 40)
                    Text("Pequeño")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray)
                }
                
                // Preview mediano
                VStack(spacing: 8) {
                    createCircularPreview(image: image, size: 60)
                    Text("Mediano")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray)
                }
                
                // Preview grande - TAMAÑO REAL DEL PERFIL
                VStack(spacing: 8) {
                    ZStack {
                        createCircularPreview(image: image, size: profileDisplaySize)
                        
                        // ✅ Indicador de que este es el resultado final
                        if profileDisplaySize >= 80 {
                            VStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                Text("Final")
                                    .font(.custom("Poppins-Bold", size: 8))
                                    .foregroundColor(.green)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(4)
                        }
                    }
                    Text("Perfil (110x110)")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    // ✅ PREVIEW SIMPLIFICADO: Muestra exactamente el área del círculo
    private func createCircularPreview(image: UIImage, size: CGFloat) -> some View {
        ZStack {
            // ✅ MOSTRAR EXACTAMENTE el área del círculo de 360x360
            // Factor de escala del preview respecto al área de crop
            let previewScale = size / cropSize
            
            // Aplicar las mismas transformaciones que en el área principal
            let finalWidth = cropSize * scale * previewScale
            let finalHeight = (cropSize * scale) / (image.size.width / image.size.height) * previewScale
            let finalOffsetX = (offset.width + gestureTranslation.width) * previewScale
            let finalOffsetY = (offset.height + gestureTranslation.height) * previewScale
            
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: finalWidth, height: finalHeight)
                .offset(CGSize(width: -finalOffsetX, height: -finalOffsetY))
                .clipped()
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
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
        guard let image = fullResolutionImage else { return }
        
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
}
