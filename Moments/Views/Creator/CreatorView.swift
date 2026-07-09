import SwiftUI
import PhotosUI
import Kingfisher
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import TOCropViewController
import CoreLocation
import MapKit
import UIKit

// MARK: - Main Creator View
struct CreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isCreatingStory: Bool
    @Binding var showCreatorView: Bool
    let initialSticker: StickerItem? // ✅ NUEVO: Sticker inicial
    let initialMedia: [CreatorMedia]? // ✅ NUEVO: Media inicial (foto/video de fondo)
    let openInStoryMode: Bool // ✅ NUEVO: Abrir directamente en modo historia
    let startInCameraWhenOnlySticker: Bool

    @State private var currentFlow: CreatorFlow = .typeSelection
    @State private var contentType: ContentType = .moment

    init(isCreatingStory: Binding<Bool>, showCreatorView: Binding<Bool>, initialSticker: StickerItem? = nil, initialMedia: [CreatorMedia]? = nil, openInStoryMode: Bool = false, startInCameraWhenOnlySticker: Bool = false) {
        self._isCreatingStory = isCreatingStory
        self._showCreatorView = showCreatorView
        self.initialSticker = initialSticker
        self.initialMedia = initialMedia
        self.openInStoryMode = openInStoryMode
        self.startInCameraWhenOnlySticker = startInCameraWhenOnlySticker

        // ✅ Inicialización de estado sincronizada
        if initialMedia != nil {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: .storyEditing)
            _responseSticker = State(initialValue: initialSticker)
            _selectedMediaItems = State(initialValue: initialMedia ?? [])
        } else if initialSticker != nil {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: startInCameraWhenOnlySticker ? .storyCamera : .storyEditing)
            _responseSticker = State(initialValue: initialSticker)
        } else if openInStoryMode {
            _contentType = State(initialValue: .story)
            _currentFlow = State(initialValue: .storyCamera)
        }
    }
    @State private var selectedMediaItems: [CreatorMedia] = []
    @State private var captionText: String = ""
    @State private var taggedUsers: [String] = []
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var locationName: String = ""
    @State private var responseSticker: StickerItem? = nil
    @State private var storyStartsInTextMode = false

    // 🔗 NUEVO: Variables para contexto de cadena
    @State private var pendingChainId: String? = nil
    @State private var pendingChainTitle: String? = nil
    @State private var pendingChainPosition: Int? = nil

    // ✅ Geometry Effect Namespace
    @Namespace private var animation

    enum CreatorFlow {
        case typeSelection
        case mediaSelection
        case mediaEditing
        case videoEditing
        case captionAndDetails
        case storyCamera
        case storyEditing
    }

    enum ContentType {
        case moment
        case story
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch currentFlow {
            case .typeSelection:
                ContentTypeSelectionView(
                    contentType: $contentType,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    animation: animation // ✅ Pass namespace
                )
            case .mediaSelection:
                MediaSelectionView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    animation: animation // ✅ Pass namespace
                )
            case .mediaEditing:
                MediaEditingView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .videoEditing:
                SocialVideoEditorView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .captionAndDetails:
                CaptionAndDetailsView(
                    selectedMediaItems: $selectedMediaItems,
                    captionText: $captionText,
                    taggedUsers: $taggedUsers,
                    selectedLocation: $selectedLocation,
                    locationName: $locationName,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView
                )
            case .storyCamera:
                StoryCameraView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    startsInTextMode: $storyStartsInTextMode
                )
            case .storyEditing:
                StoryEditingView(
                    selectedMediaItems: $selectedMediaItems,
                    currentFlow: $currentFlow,
                    showCreatorView: $showCreatorView,
                    startInTextMode: $storyStartsInTextMode,
                    initialSticker: responseSticker,
                    initialChainId: pendingChainId,
                    initialChainTitle: pendingChainTitle,
                    initialChainPosition: pendingChainPosition
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: contentType) { _, newType in
            // ✅ SEGURIDAD CRÍTICA: No cambiar el flujo si ya estamos editando (especialmente con Stickers)
            if initialSticker != nil || responseSticker != nil {
                if currentFlow == .storyEditing { return }
            }

            // ✅ EVITAR RESET: Si ya estamos en edición o cámara story, no sobrescribir el flujo
            guard currentFlow == .typeSelection else { return }

            if newType == .story {
                // ✅ FIX: Si hay un sticker, ir al editor en lugar de la cámara
                if initialMedia != nil {
                    currentFlow = .storyEditing
                } else {
                    currentFlow = .storyCamera
                }
                isCreatingStory = true
            } else {
                currentFlow = .mediaSelection
                isCreatingStory = false
            }
        }
        .onAppear {
            setupResponseStickerListener()
            setupContinueChainListener()

            // Si llega solo un sticker de pregunta, abrimos la cámara primero y lo conservamos para el editor.
            if let sticker = initialSticker {
                if responseSticker == nil { responseSticker = sticker }

                contentType = .story
                if initialMedia != nil || !startInCameraWhenOnlySticker {
                    currentFlow = .storyEditing
                } else {
                    currentFlow = .storyCamera
                }

                isCreatingStory = true
            } else if openInStoryMode {
                isCreatingStory = true
                if currentFlow == .typeSelection {
                    contentType = .story
                    currentFlow = .storyCamera
                }
            }
        }
        .onDisappear {
            removeResponseStickerListener()
            removeContinueChainListener()

            // ✅ Limpiar video y audio cuando se cierra CreatorView
            cleanupVideoAndAudio()
        }
    }

    // MARK: - Response Sticker Handling
    private func setupResponseStickerListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddResponseStickerToCreator"),
            object: nil,
            queue: .main
        ) { notification in
            if let sticker = notification.object as? StickerItem {
                addResponseStickerToStory(sticker)
            }
        }
    }

    private func removeResponseStickerListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("AddResponseStickerToCreator"),
            object: nil
        )
    }

    // MARK: - Continue Chain Handling
    private func setupContinueChainListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ContinueStoryChain"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                continueStoryChain(chainId: chainId, chainTitle: chainTitle, chainPosition: chainPosition)
            }
        }

        // 🔗 NUEVO: Listener para configurar tipo de contenido
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetContentType"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let contentTypeString = userInfo["contentType"] as? String {
                if contentTypeString == "story" {
                    contentType = .story
                    currentFlow = .storyCamera  // ✅ MANTENER: Ir a cámara para seleccionar medios
                    isCreatingStory = true
                }
            }
        }

        // 🔗 NUEVO: Listener para guardar contexto de cadena
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetChainContext"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let chainId = userInfo["chainId"] as? String,
               let chainTitle = userInfo["chainTitle"] as? String,
               let chainPosition = userInfo["chainPosition"] as? Int {
                pendingChainId = chainId
                pendingChainTitle = chainTitle
                pendingChainPosition = chainPosition
            }
        }
    }

    private func removeContinueChainListener() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("ContinueStoryChain"),
            object: nil
        )

        // 🔗 NUEVO: Limpiar listener de tipo de contenido
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("SetContentType"),
            object: nil
        )
    }

    private func continueStoryChain(chainId: String, chainTitle: String, chainPosition: Int) {
        // Configurar para continuar cadena
        contentType = .story
        currentFlow = .storyCamera
        isCreatingStory = true

        // Pasar datos de cadena al StoryEditingView
        // Esto se manejará en el StoryEditingView cuando se abra
        NotificationCenter.default.post(
            name: NSNotification.Name("SetChainContext"),
            object: nil,
            userInfo: [
                "chainId": chainId,
                "chainTitle": chainTitle,
                "chainPosition": chainPosition
            ]
        )
    }

    private func addResponseStickerToStory(_ sticker: StickerItem) {
        // ✅ GUARDAR EL STICKER EN EL ESTADO ANTES DE ABRIR StoryEditingView
        responseSticker = sticker

        // Ir directamente a la edición de historia con el sticker
        contentType = .story
        currentFlow = .storyEditing
        isCreatingStory = true
    }
    // ✅ FUNCIÓN PARA LIMPIAR VIDEO Y AUDIO
    private func cleanupVideoAndAudio() {
        // ✅ Limpiar los media items seleccionados
        selectedMediaItems.removeAll()

        // ✅ Pausar cualquier audio que esté reproduciéndose
        try? AVAudioSession.sharedInstance().setActive(false)

        // ✅ Notificar limpieza de video
        NotificationCenter.default.post(name: NSNotification.Name("CleanupVideoPlayer"), object: nil)
    }

    // ✅ Helper to create gradient image for sticker-only stories
    private func createDefaultGradientImage() -> UIImage {
        let size = UIScreen.main.bounds.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let colors = [
                UIColor(Color(hex: "4158D0")).cgColor,
                UIColor(Color(hex: "C850C0")).cgColor,
                UIColor(Color(hex: "FFCC70")).cgColor
            ]

            let gradient = sectionGradient(colors: colors, size: size)
            gradient.render(in: context.cgContext)
        }
    }

    private func sectionGradient(colors: [CGColor], size: CGSize) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.colors = colors
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }
}

extension CreatorMedia.AspectRatio {
    // ✅ NUEVO: Inicializar desde string guardado en Firestore
    init(from string: String?) {
        switch string {
        case "1:1": self = .square
        case "4:5": self = .portrait
        case "16:9": self = .landscape
        case "9:16": self = .nineBySixteen
        default: self = .square // Default fallback
        }
    }

    // ✅ NOTA: La función fromRatio está definida dentro del enum AspectRatio (línea 78)
    // para usar la lógica mejorada de detección con tolerancia y rangos más precisos
}

private struct MomentsStoryGuideOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let guideRect = creatorMomentsAspectRect(aspectRatio: creatorMomentsCaptureAspectRatio, in: CGRect(origin: .zero, size: proxy.size))
            let topMaskHeight = max(guideRect.minY, 0)
            let bottomMaskHeight = max(proxy.size.height - guideRect.maxY, 0)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(height: topMaskHeight)

                Color.clear
                    .frame(height: guideRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    )

                Rectangle()
                    .fill(Color.black.opacity(0.34))
                    .frame(height: bottomMaskHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - StoryOverlaysView FINAL - Sin cuadrado X, con navegación funcional
struct ModernSelectionInterface: View {
    let size: CGSize
    let scale: CGFloat
    @Binding var isScaling: Bool
    @Binding var isRotating: Bool
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Angle) -> Void
    let onDelete: () -> Void

    @State private var initialScale: CGFloat = 1.0
    @State private var initialRotation: Angle = .zero
    @State private var showDeleteButton = false

    var body: some View {
        ZStack {
            // ✅ BORDE ELEGANTE - Solo líneas en las esquinas
            CornerBorders(size: size)

            // ✅ CONTROLES EN LAS ESQUINAS
            VStack {
                HStack {
                    // Botón eliminar (esquina superior izquierda)
                    DeleteButton(onDelete: onDelete)

                    Spacer()

                    // Control de rotación (esquina superior derecha)
                    RotationControl(
                        scale: scale,
                        isRotating: $isRotating,
                        onRotationChanged: { newRotation in
                            onRotationChanged(newRotation)
                        }
                    )
                }

                Spacer()

                HStack {
                    Spacer()

                    // Control de escala (esquina inferior derecha)
                    ScaleControl(
                        scale: scale,
                        isScaling: $isScaling,
                        onScaleChanged: { newScale in
                            onScaleChanged(newScale)
                        }
                    )
                }
            }
            .frame(width: size.width + 40, height: size.height + 40)
        }
        .onAppear {
            MotionPolicy.withOptionalAnimation(.easeInOut(duration: 0.2)) {
                showDeleteButton = true
            }
        }
    }
}

// MARK: - Bordes de esquina elegantes
struct CornerBorders: View {
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CornerBorder()
                    .rotationEffect(.degrees(Double(index * 90)))
            }
        }
        .frame(width: size.width + 20, height: size.height + 20)
    }
}

struct CornerBorder: View {
    var body: some View {
        VStack {
            HStack {
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: 12)
                    Spacer()
                }
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 12, height: 2)
                    Spacer()
                }
            }
            Spacer()
        }
        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Botón de eliminar moderno
struct DeleteButton: View {
    let onDelete: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticManager.shared.mediumImpact()
            onDelete()
        }) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .offset(x: -10, y: -10)
    }
}

// MARK: - Control de rotación
struct RotationControl: View {
    let scale: CGFloat
    @Binding var isRotating: Bool
    let onRotationChanged: (Angle) -> Void

    @State private var lastRotation: Angle = .zero
    @State private var currentRotation: Angle = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(isRotating ? .degrees(180) : .degrees(0))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isRotating), value: isRotating)
        }
        .offset(x: 10, y: -10)
        .gesture(
            RotationGesture()
                .onChanged { value in
                    if !isRotating {
                        isRotating = true
                        lastRotation = currentRotation
                    }
                    currentRotation = lastRotation + value
                    onRotationChanged(currentRotation)
                }
                .onEnded { value in
                    isRotating = false
                    lastRotation = currentRotation
                }
        )
    }
}

// MARK: - Control de escala
struct ScaleControl: View {
    let scale: CGFloat
    @Binding var isScaling: Bool
    let onScaleChanged: (CGFloat) -> Void

    @State private var lastScale: CGFloat = 1.0
    @State private var currentScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .scaleEffect(isScaling ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isScaling)
        }
        .offset(x: 10, y: 10)
        .onAppear {
            lastScale = scale
            currentScale = scale
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    if !isScaling {
                        isScaling = true
                    }
                    let newScale = lastScale * value
                    currentScale = min(max(newScale, 0.3), 4.0)
                    onScaleChanged(currentScale)
                }
                .onEnded { value in
                    isScaling = false
                    lastScale = currentScale
                }
        )
    }
}



// MARK: - Additional Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview Provider

struct CreatorView_Previews: PreviewProvider {
    static var previews: some View {
        CreatorView(
            isCreatingStory: .constant(false),
            showCreatorView: .constant(true),
            initialSticker: nil
        )
    }
}

// MARK: - 🎨 COMPONENTES PREMIUM COMPARTIDOS (The Cinematic Handoff)

// GlowSharePill moved to CreatorSharedModels.swift

// MARK: - ✨ REVEAL STICKER EDITOR

struct RevealStickerEditorView: View {
    @Binding var stickers: [StickerItem]
    @Binding var editingId: String?
    private var currentStickerIndex: Int? {
        stickers.firstIndex(where: { $0.id == editingId })
    }

    private var canvasCornerRadius: CGFloat { storyViewerCanvasCornerRadius }

    var body: some View {
        ZStack {
            if let index = currentStickerIndex {
                RevealSurfaceView(
                    type: stickers[index].interactionData?.revealType,
                    pattern: stickers[index].interactionData?.revealPattern,
                    primaryColor: stickers[index].interactionData?.revealPrimaryColor,
                    secondaryColor: stickers[index].interactionData?.revealSecondaryColor,
                    effectColor: stickers[index].interactionData?.revealEffectColor
                )
                .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous))
            }

            VStack(spacing: 0) {
                headerView

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: canvasCornerRadius, style: .continuous))
    }

    private var headerView: some View {
        HStack {
            Button(action: { editingId = nil }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .momentsChromeGlass(in: Circle())
            }

            Spacer()

            Text(NSLocalizedString("revealEditor.title", comment: "Customize Reveal"))
                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                .foregroundColor(.white)
                .shadow(radius: 4)

            Spacer()

            Button(action: { editingId = nil }) {
                Text(NSLocalizedString("common.done", comment: "Done"))
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .momentsChromeGlass(in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

struct RevealStickerBottomControlsInset: View {
    @Binding var stickers: [StickerItem]
    @Binding var editingId: String?
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.86)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : Color.black.opacity(0.72)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Text(NSLocalizedString("revealEditor.title", comment: "Customize Reveal"))
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundColor(primaryTextColor)

                Spacer(minLength: 0)
            }

            RevealStickerControlsContent(
                stickers: $stickers,
                editingId: $editingId,
                presetPreviewSize: CGSize(width: 86, height: 126),
                presetsHeight: 156
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.clear)
                .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.75)
                )
        )
    }
}

private struct RevealStickerControlsContent: View {
    @Binding var stickers: [StickerItem]
    @Binding var editingId: String?
    @Environment(\.colorScheme) private var colorScheme

    let presetPreviewSize: CGSize
    let presetsHeight: CGFloat

    @State private var selectedTab: EditorTab = .presets
    @State private var selectedPresetId: String = "classic"
    @State private var tabTransientOffset: CGFloat = 0
    @State private var customType: String = "solid"
    @State private var customPattern: String = "dots"
    @State private var customPrimary: Color = .black
    @State private var customSecondary: Color = .black
    @State private var customEffect: Color = .white

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : Color.black.opacity(0.62)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.55) : Color.black.opacity(0.48)
    }

    private var tabInactiveTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color.black.opacity(0.54)
    }

    private var tabActiveTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color.black.opacity(0.86)
    }

    private var chipBackgroundColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var chipInactiveBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var chipActiveTextColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var circleButtonBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    enum EditorTab: CaseIterable, Hashable {
        case presets
        case custom
    }

    private var currentStickerIndex: Int? {
        stickers.firstIndex(where: { $0.id == editingId })
    }

    var body: some View {
        VStack(spacing: 16) {
            tabSelector

            if selectedTab == .presets {
                presetsGrid
            } else {
                customControls
            }
        }
        .onAppear(perform: loadCurrentState)
        .onChange(of: editingId) { _, _ in
            loadCurrentState()
        }
    }

    private var tabSelector: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color.clear)
                    .momentsChromeGlass(in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    )

                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: tabSegmentWidth(for: proxy.size.width), height: 34)
                    .momentsChromeGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.24), radius: 7, x: 0, y: 2)
                    .offset(x: tabPillOffset(for: proxy.size.width))

                HStack(spacing: 0) {
                    ForEach(Array(EditorTab.allCases.enumerated()), id: \.element) { index, tab in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: tab))
                                .font(.system(size: 13, weight: .semibold))

                            Text(title(for: tab))
                                .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                        }
                        .foregroundColor(tabLabelColor(for: index, width: proxy.size.width))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 3)
                .animation(MotionPolicy.animation(.smooth(duration: 0.18, extraBounce: 0.01), value: tabVisualIndex(for: proxy.size.width)), value: tabVisualIndex(for: proxy.size.width))

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    tabTransientOffset = constrainedTabTranslation(value.translation.width, width: proxy.size.width)
                                }
                            }
                            .onEnded { value in
                                settleTabSelection(
                                    translation: value.translation.width,
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            }
                    )
            }
        }
        .frame(height: 42)
    }

    private var presetsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(revealPresets) { preset in
                    Button(action: { applyPreset(preset) }) {
                        VStack(spacing: 8) {
                            RevealSurfaceView(
                                type: preset.type,
                                pattern: preset.pattern,
                                primaryColor: preset.primary,
                                secondaryColor: preset.secondary,
                                effectColor: preset.effect
                            )
                            .frame(width: presetPreviewSize.width, height: presetPreviewSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedPresetId == preset.id ? Color.white : Color.white.opacity(0.2), lineWidth: 2)
                            )

                            Text(NSLocalizedString("revealEditor.preset.\(preset.id)", comment: ""))
                                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                                .foregroundColor(primaryTextColor)
                        }
                    }
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: presetsHeight)
    }

    private var customControls: some View {
        VStack(spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["none", "dots", "noise", "static", "scanlines", "grid", "lines", "waves", "matrix", "holographic"], id: \.self) { p in
                        Button(action: { updateCustomPattern(p) }) {
                            Text(NSLocalizedString("revealEditor.pattern.\(p)", comment: ""))
                                .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(customPattern == p ? chipBackgroundColor : chipInactiveBackgroundColor)
                                .foregroundColor(customPattern == p ? chipActiveTextColor : primaryTextColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                revealColorPicker(
                    color: $customPrimary,
                    labelKey: customType == "solid" ? "revealEditor.color.background" : "revealEditor.color1"
                )
                .onChange(of: customPrimary) { _, _ in
                    ensureContrastingEffectColorIfNeeded()
                    updateCustomColors()
                }

                if customType == "gradient" {
                    revealColorPicker(color: $customSecondary, labelKey: "revealEditor.color2")
                        .onChange(of: customSecondary) { _, _ in
                            updateCustomColors()
                        }
                }

                if customPattern != "none" {
                    revealColorPicker(color: $customEffect, labelKey: "revealEditor.color.effect")
                        .onChange(of: customEffect) { _, _ in
                            updateCustomColors()
                        }
                }

                Button(action: toggleType) {
                    VStack(spacing: 6) {
                        Image(systemName: customType == "solid" ? "plus" : "minus")
                            .font(.system(size: 18, weight: .bold))

                        Text(customType == "solid" ? "2" : "1")
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    }
                    .foregroundColor(primaryTextColor)
                    .frame(width: 50, height: 50)
                    .background(circleButtonBackgroundColor)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(customType == "solid"
                        ? NSLocalizedString("revealEditor.color.background", comment: "")
                        : NSLocalizedString("revealEditor.color1", comment: ""))
                        .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                        .foregroundColor(primaryTextColor)
                    Text(customType == "solid"
                        ? NSLocalizedString("revealEditor.tab.custom", comment: "Custom")
                        : NSLocalizedString("revealEditor.color2", comment: ""))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(tertiaryTextColor)
                }
            }
            .padding(.horizontal, 2)
            }
        }
    }

    private func revealColorPicker(color: Binding<Color>, labelKey: String) -> some View {
        VStack(spacing: 4) {
            ColorPicker(selection: color, supportsOpacity: false) {
                Circle()
                    .fill(color.wrappedValue)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
            .labelsHidden()

            Text(NSLocalizedString(labelKey, comment: ""))
                .font(.caption2)
                .foregroundColor(secondaryTextColor)
        }
    }

    private var currentTabIndex: Int {
        EditorTab.allCases.firstIndex(of: selectedTab) ?? 0
    }

    private func title(for tab: EditorTab) -> String {
        switch tab {
        case .presets:
            return NSLocalizedString("revealEditor.tab.presets", comment: "Presets")
        case .custom:
            return NSLocalizedString("revealEditor.tab.custom", comment: "Custom")
        }
    }

    private func icon(for tab: EditorTab) -> String {
        switch tab {
        case .presets:
            return "sparkles"
        case .custom:
            return "slider.horizontal.3"
        }
    }

    private func tabSegmentWidth(for totalWidth: CGFloat) -> CGFloat {
        let innerWidth = totalWidth - 6
        return innerWidth / CGFloat(EditorTab.allCases.count)
    }

    private func tabBaseOffset(for totalWidth: CGFloat) -> CGFloat {
        let segmentWidth = tabSegmentWidth(for: totalWidth)
        let start = -((CGFloat(EditorTab.allCases.count - 1) * segmentWidth) / 2)
        return start + (CGFloat(currentTabIndex) * segmentWidth)
    }

    private func tabPillOffset(for totalWidth: CGFloat) -> CGFloat {
        tabBaseOffset(for: totalWidth) + tabTransientOffset
    }

    private func tabVisualIndex(for totalWidth: CGFloat) -> Int {
        let width = tabSegmentWidth(for: totalWidth)
        let start = -((CGFloat(EditorTab.allCases.count - 1) * width) / 2)
        let raw = ((tabPillOffset(for: totalWidth) - start) / width).rounded()
        return min(max(Int(raw), 0), EditorTab.allCases.count - 1)
    }

    private func tabLabelColor(for index: Int, width: CGFloat) -> Color {
        tabVisualIndex(for: width) == index ? tabActiveTextColor : tabInactiveTextColor
    }

    private func constrainedTabTranslation(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let segment = tabSegmentWidth(for: width)
        let minOffset = -((CGFloat(EditorTab.allCases.count - 1) * segment) / 2)
        let maxOffset = ((CGFloat(EditorTab.allCases.count - 1) * segment) / 2)
        let proposed = tabBaseOffset(for: width) + translation
        let clamped = min(max(proposed, minOffset), maxOffset)
        return clamped - tabBaseOffset(for: width)
    }

    private func settleTabSelection(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let segment = tabSegmentWidth(for: width)
        let proposedOffset = tabBaseOffset(for: width) + translation
        let start = -((CGFloat(EditorTab.allCases.count - 1) * segment) / 2)
        let fractionalIndex = (proposedOffset - start) / segment
        let threshold = min(segment * 0.28, 36)

        let targetIndex: Int
        if abs(translation) > threshold && abs(translation) < segment * 0.5 {
            let direction = translation > 0 ? 1 : -1
            targetIndex = min(max(currentTabIndex + direction, 0), EditorTab.allCases.count - 1)
        } else if abs(translation) < 5 {
            targetIndex = min(max(Int(locationX / segment), 0), EditorTab.allCases.count - 1)
        } else {
            targetIndex = min(max(Int(fractionalIndex.rounded()), 0), EditorTab.allCases.count - 1)
        }

        let targetTab = EditorTab.allCases[targetIndex]
        if targetTab != selectedTab {
            HapticManager.shared.selection()
        }

        MotionPolicy.withOptionalAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedTab = targetTab
            tabTransientOffset = 0
        }
    }


    // MARK: - Logic

    private func loadCurrentState() {
        guard let index = currentStickerIndex else { return }
        let data = stickers[index].interactionData

        customType = data?.revealType ?? "solid"
        customPattern = data?.revealPattern ?? "dots"
        customPrimary = Color(hex: data?.revealPrimaryColor ?? "#000000")
        customSecondary = Color(hex: data?.revealSecondaryColor ?? "#000000")
        if let effectHex = data?.revealEffectColor, !effectHex.isEmpty {
            customEffect = Color(hex: effectHex)
        } else {
            customEffect = resolvedLegacyEffectColor(from: data)
        }
        ensureContrastingEffectColorIfNeeded()

        // Try to match preset
        if let preset = revealPresets.first(where: {
            $0.type == customType &&
            $0.pattern == customPattern &&
            $0.primary.lowercased() == data?.revealPrimaryColor?.lowercased()
        }) {
            selectedPresetId = preset.id
            selectedTab = .presets
            tabTransientOffset = 0
        } else {
            selectedTab = .custom
            tabTransientOffset = 0
        }
    }

    private func applyPreset(_ preset: RevealPreset) {
        selectedPresetId = preset.id
        customPrimary = Color(hex: preset.primary)
        customSecondary = Color(hex: preset.secondary)
        customEffect = Color(hex: preset.effect)
        updateSticker(
            type: preset.type,
            pattern: preset.pattern,
            primary: preset.primary,
            secondary: preset.secondary,
            effect: preset.effect
        )
        HapticManager.shared.lightImpact()
    }

    private func updateCustomPattern(_ p: String) {
        customPattern = p
        ensureContrastingEffectColorIfNeeded()
        updateCustomColors()
    }

    private func resolvedLegacyEffectColor(from data: StickerItem.StickerInteractionData?) -> Color {
        if let secondary = data?.revealSecondaryColor,
           let primary = data?.revealPrimaryColor,
           !secondary.isEmpty,
           secondary.lowercased() != primary.lowercased() {
            return Color(hex: secondary)
        }
        return customPrimary.revealContrastingEffectColor()
    }

    private func ensureContrastingEffectColorIfNeeded() {
        guard customPattern != "none" else { return }
        if customPrimary.toHex().lowercased() == customEffect.toHex().lowercased() {
            customEffect = customPrimary.revealContrastingEffectColor()
        }
    }

    private func updateCustomColors() {
        updateSticker(
            type: customType,
            pattern: customPattern,
            primary: customPrimary.toHex(),
            secondary: customSecondary.toHex(),
            effect: customPattern == "none" ? nil : customEffect.toHex()
        )
    }

    private func toggleType() {
        withAnimation {
            customType = customType == "solid" ? "gradient" : "solid"
        }
        ensureContrastingEffectColorIfNeeded()
        updateCustomColors()
    }

    private func updateSticker(type: String, pattern: String, primary: String, secondary: String, effect: String?) {
        guard let index = currentStickerIndex else { return }
        var data = stickers[index].interactionData ?? StickerItem.StickerInteractionData()

        data.revealType = type
        data.revealPattern = pattern
        data.revealPrimaryColor = primary
        data.revealSecondaryColor = secondary
        data.revealEffectColor = effect

        stickers[index].interactionData = data
    }
}

struct RevealPreset: Identifiable {
    let id: String
    let name: String
    let type: String
    let pattern: String
    let primary: String
    let secondary: String
    let effect: String
}

let revealPresets: [RevealPreset] = [
    RevealPreset(id: "classic", name: "Classic", type: "solid", pattern: "dots", primary: "#000000", secondary: "#000000", effect: "#FFFFFF"),
    RevealPreset(id: "midnight", name: "Midnight", type: "solid", pattern: "grid", primary: "#0B1215", secondary: "#0B1215", effect: "#7EC8FF"),
    RevealPreset(id: "golden", name: "Golden", type: "gradient", pattern: "noise", primary: "#BF953F", secondary: "#8E6E2D", effect: "#FFF4D6"),
    RevealPreset(id: "neon", name: "Neon Glow", type: "gradient", pattern: "lines", primary: "#430089", secondary: "#82009F", effect: "#FF8AF8"),
    RevealPreset(id: "silver", name: "Silver", type: "gradient", pattern: "dots", primary: "#C0C0C0", secondary: "#708090", effect: "#FFFFFF"),
    RevealPreset(id: "retro", name: "Old TV", type: "solid", pattern: "static", primary: "#FFFFFF", secondary: "#FFFFFF", effect: "#2B2B2B"),
    RevealPreset(id: "matrix", name: "Matrix", type: "solid", pattern: "matrix", primary: "#000000", secondary: "#000000", effect: "#00FF41"),
    RevealPreset(id: "blueprint", name: "Blueprint", type: "solid", pattern: "grid", primary: "#003366", secondary: "#003366", effect: "#8FD3FF"),
    RevealPreset(id: "magic", name: "Magic", type: "solid", pattern: "holographic", primary: "#C8C8C8", secondary: "#C8C8C8", effect: "#FF6AD5")
]
