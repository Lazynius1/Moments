import SwiftUI
import PhotosUI
import Photos
import AVFoundation

// MARK: - Presentation

enum NovaAttachmentSheetKind: Identifiable, Equatable {
    case camera
    case photos

    var id: Self { self }
}

private enum NovaAttachmentSheetMetrics {
    /// Inset lateral como sheet medium nativo (~10pt).
    static let horizontalInset: CGFloat = 10
    static let cornerRadius: CGFloat = 24
    /// Misma altura cámara/fotos (~58% pantalla, estilo ChatGPT medium/large).
    static let heightFraction: CGFloat = 0.58
}

// MARK: - Custom medium overlay (no sheet nativo — glass compone mal ahí)

struct NovaAttachmentSheetOverlay: View {
    @Binding var activeSheet: NovaAttachmentSheetKind?
    let onCaptured: (UIImage) -> Void
    let onAdd: (UIImage) -> Void
    let onBackToMenu: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let kind = activeSheet {
            GeometryReader { proxy in
                let bottomPadding = NovaInputBarLayout.attachmentSheetBottomInset(
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                )
                let sheetHeight = proxy.size.height * NovaAttachmentSheetMetrics.heightFraction

                ZStack(alignment: .bottom) {
                    Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismiss()
                        }

                    NovaAttachmentSheetSurface(kind: kind, height: sheetHeight) {
                        switch kind {
                        case .camera:
                            NovaAttachmentCameraSheet(
                                onCaptured: onCaptured,
                                onBack: backToAttachmentMenu
                            )
                        case .photos:
                            NovaAttachmentPhotoGridSheet(
                                onAdd: onAdd,
                                onBack: backToAttachmentMenu
                            )
                        }
                    }
                    .padding(.horizontal, NovaAttachmentSheetMetrics.horizontalInset)
                    .padding(.bottom, bottomPadding)
                    .offset(y: dragOffset)
                    .gesture(dismissDragGesture(sheetHeight: sheetHeight))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(45)
        }
    }

    private func dismissDragGesture(sheetHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > sheetHeight * 0.2
                    || value.predictedEndTranslation.height > sheetHeight * 0.35

                if shouldDismiss {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            dragOffset = 0
            activeSheet = nil
        }
    }

    private func backToAttachmentMenu() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            dragOffset = 0
            activeSheet = nil
        }
        onBackToMenu()
    }
}

private struct NovaAttachmentSheetSurface<Content: View>: View {
    let kind: NovaAttachmentSheetKind
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: NovaAttachmentSheetMetrics.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        content()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                Group {
                    switch kind {
                    case .camera:
                        Color.black
                    case .photos:
                        NovaAttachmentSheetCanvasBackground()
                    }
                }
                .clipShape(sheetShape)
            }
            .clipShape(sheetShape)
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    }
}

// MARK: - Camera sheet

struct NovaAttachmentCameraSheet: View {
    let onCaptured: (UIImage) -> Void
    let onBack: () -> Void

    @State private var flashMode: EnhancedCameraPickerView.FlashMode = .off
    @State private var cameraPosition: EnhancedCameraPickerView.CameraPosition = .back
    @State private var showsCameraTools = false
    @State private var cameraViewController: CameraViewController?
    @StateObject private var orientationManager = OrientationManager.shared

    private var deviceOrientation: UIDeviceOrientation {
        orientationManager.orientation
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CameraView(
                    captureMode: .photo,
                    cameraPosition: cameraPosition,
                    flashMode: flashMode,
                    isEphemeralMode: false,
                    showGridLines: false,
                    onMediaCaptured: { data, mediaType, _ in
                        guard mediaType == .image, let image = UIImage(data: data) else { return }
                        onCaptured(image)
                    },
                    onVideoRecordingStateChange: { _ in },
                    deviceOrientation: deviceOrientation,
                    cameraViewController: $cameraViewController
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    cameraBottomBar
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(Color.black)
        .onAppear {
            orientationManager.startTracking()
        }
        .onDisappear {
            orientationManager.stopTracking()
            showsCameraTools = false
            flashMode = .off
            cameraPosition = .back
        }
    }

    private var cameraBottomBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            NovaStoryRoundButton(
                systemImage: "chevron.left",
                forceLightChrome: true,
                accessibilityKey: "nova.attach.back.accessibility",
                action: dismissSheet
            )
            .frame(width: 42, alignment: .center)

            Spacer(minLength: 0)

            CaptureButton(
                isRecording: .constant(false),
                glassVariant: .clear,
                onTap: { cameraViewController?.capturePhoto() },
                onLongPressStart: {},
                onLongPressEnd: {}
            )
            .accessibilityLabel(Text("nova.attach.capture.accessibility"))

            Spacer(minLength: 0)

            cameraTrailingControls
                .frame(width: 42, alignment: .center)
        }
    }

    private var cameraTrailingControls: some View {
        VStack(spacing: 12) {
            if showsCameraTools {
                cameraToolsStack
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }

            NovaStoryRoundButton(
                systemImage: showsCameraTools ? "xmark" : "ellipsis",
                forceLightChrome: true,
                accessibilityKey: showsCameraTools ? "common.close" : "nova.attach.more.accessibility",
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        showsCameraTools.toggle()
                    }
                }
            )
        }
    }

    private var cameraToolsStack: some View {
        NovaAttachmentGlassStack(axis: .vertical, spacing: 12) {
            if cameraPosition == .back {
                NovaStoryRoundButton(
                    systemImage: flashMode.icon,
                    forceLightChrome: true,
                    accessibilityKey: "nova.attach.flash.accessibility",
                    action: cycleFlash
                )
            }

            NovaStoryRoundButton(
                systemImage: "arrow.triangle.2.circlepath.camera",
                forceLightChrome: true,
                accessibilityKey: "nova.attach.flip.accessibility",
                action: flipCamera
            )
        }
    }

    private func dismissSheet() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showsCameraTools = false
            onBack()
        }
    }

    private func cycleFlash() {
        guard cameraPosition == .back else { return }
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        }
    }

    private func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        if cameraPosition == .front {
            flashMode = .off
        }
    }
}

// MARK: - Photos sheet

struct NovaAttachmentPhotoGridSheet: View {
    let onAdd: (UIImage) -> Void
    let onBack: () -> Void

    @State private var photoAssets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedAssetID: String?
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    @State private var nativePickerItem: PhotosPickerItem?
    @State private var showNativePhotoPicker = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let imageManager = PHImageManager.default()
    private let thumbnailSize = CGSize(width: 300, height: 300)

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(NovaColors.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                    NovaAttachmentPermissionPrompt(messageKey: "nova.attach.photos.permission")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(photoAssets, id: \.localIdentifier) { asset in
                                NovaAttachmentPhotoCell(
                                    thumbnail: thumbnails[asset.localIdentifier],
                                    isSelected: selectedAssetID == asset.localIdentifier,
                                    onTap: {
                                        selectedAssetID = asset.localIdentifier
                                    },
                                    onAppear: {
                                        loadThumbnailIfNeeded(for: asset)
                                    }
                                )
                            }
                        }
                        .padding(.bottom, 88)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                NovaAttachmentSheetCanvasBackground()
            }

            footerBar
        }
        .photosPicker(isPresented: $showNativePhotoPicker, selection: $nativePickerItem, matching: .images)
        .onChange(of: nativePickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        nativePickerItem = nil
                        onAdd(image)
                    }
                }
            }
        }
        .onAppear {
            requestPhotoLibraryAccess()
        }
    }

    private var footerBar: some View {
        footerBarContent
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 4)
    }

    private var footerBarContent: some View {
        NovaAttachmentGlassStack(axis: .horizontal, spacing: 10) {
            NovaStoryRoundButton(
                systemImage: "chevron.left",
                accessibilityKey: "nova.attach.back.accessibility",
                action: dismissSheet
            )

            Spacer(minLength: 8)

            if selectedAssetID == nil {
                NovaStoryPillButton(
                    titleKey: "nova.attach.allPhotos",
                    action: { showNativePhotoPicker = true }
                )
            } else {
                NovaStoryPillButton(
                    titleKey: "nova.attach.addToNova",
                    tint: Color(hex: "007AFF"),
                    action: confirmSelection
                )
            }
        }
    }

    private func dismissSheet() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedAssetID = nil
            onBack()
        }
    }

    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                    loadPhotosIfAllowed()
                }
            }
        } else {
            loadPhotosIfAllowed()
        }
    }

    private func loadPhotosIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            isLoading = false
            return
        }

        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 300
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                photoAssets = assets
                isLoading = false
            }
        }
    }

    private func loadThumbnailIfNeeded(for asset: PHAsset) {
        guard thumbnails[asset.localIdentifier] == nil else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                thumbnails[asset.localIdentifier] = image
            }
        }
    }

    private func confirmSelection() {
        guard let selectedAssetID,
              let asset = photoAssets.first(where: { $0.localIdentifier == selectedAssetID }) else {
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                onAdd(image)
            }
        }
    }
}

// MARK: - Shared components

private struct NovaAttachmentPhotoCell: View {
    let thumbnail: UIImage?
    let isSelected: Bool
    let onTap: () -> Void
    let onAppear: () -> Void

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(NovaColors.materialBackground)
                                .overlay {
                                    ProgressView()
                                        .tint(NovaColors.primary)
                                }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.width)
                    .clipped()

                    if isSelected {
                        Circle()
                            .fill(Color(hex: "007AFF"))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text("1")
                                    .font(.custom("Poppins-SemiBold", size: 12))
                                    .foregroundColor(.white)
                            }
                            .padding(8)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .onAppear(perform: onAppear)
    }
}

private struct NovaAttachmentPermissionPrompt: View {
    let messageKey: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundColor(NovaColors.textSecondary)

            Text(LocalizedStringKey(messageKey))
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(NovaColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Story-style chrome (EditingToolIcon + StoryInteractionSettingsView)

private struct NovaAttachmentSheetCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MomentsGlassButtonTint.canvas(for: colorScheme)
            .ignoresSafeArea()
    }
}

/// Agrupa controles glass adyacentes como en `FeedTypeSelector` / `ProfileChromeControlsCluster`.
private struct NovaAttachmentGlassStack<Content: View>: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    stack
                }
            } else {
                stack
            }
        }
    }

    @ViewBuilder
    private var stack: some View {
        switch axis {
        case .horizontal:
            HStack(spacing: spacing, content: content)
        case .vertical:
            VStack(spacing: spacing, content: content)
        }
    }
}

/// Mismo patrón que `EditingToolIcon` y `StoryInteractionSettingsView` (glass directo en el frame).
private struct NovaStoryRoundButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    var size: CGFloat = 42
    var forceLightChrome: Bool = false
    let accessibilityKey: String
    let action: () -> Void

    private var foregroundColor: Color {
        forceLightChrome ? .white : StoryEditorChromeColor.icon(colorScheme)
    }

    private var strokeColor: Color {
        if forceLightChrome {
            return Color.white.opacity(0.12)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .liquidGlass(in: Circle(), variant: .clear, interactive: true)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(forceLightChrome ? 0 : (colorScheme == .dark ? 0.1 : 0.08)),
                    radius: 4,
                    x: 0,
                    y: 2
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(accessibilityKey)))
    }
}

/// Pills con `.liquidGlass(..., variant: .clear, interactive: true)`.
private struct NovaStoryPillButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let titleKey: String
    var tint: Color? = nil
    var disabled: Bool = false
    let action: () -> Void

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(titleKey))
                .font(.custom(tint == nil ? "Poppins-Medium" : "Poppins-SemiBold", size: 14))
                .foregroundColor(tint == nil ? StoryEditorChromeColor.icon(colorScheme) : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .liquidGlass(
                    in: Capsule(),
                    variant: .clear,
                    interactive: !disabled,
                    tint: tint.map { $0.opacity(disabled ? 0.35 : 0.92) }
                )
                .overlay(
                    Capsule()
                        .stroke(strokeColor, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
