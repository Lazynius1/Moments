import SwiftUI
import PhotosUI
import Photos
import AVFoundation

// MARK: - Presentation

enum NovaAttachmentSheetKind: Identifiable, Equatable {
    case menu
    case camera
    case photos

    var id: Self { self }
}

private enum NovaAttachmentSheetMetrics {
    /// Inset lateral como sheet medium nativo (~10pt).
    static let horizontalInset: CGFloat = 10
    static let cornerRadius: CGFloat = 24
    static let menuPopoverTitleKeys = ["nova.attach.camera", "nova.attach.photos"]
    static let menuPopoverTextExtraMargin: CGFloat = 20
    static let menuPopoverMinWidth: CGFloat = 168
    /// Separación entre el borde inferior del popover y el botón +.
    static let menuPopoverGap: CGFloat = 16
    /// Cámara / fotos (~58% pantalla).
    static let heightFraction: CGFloat = 0.58

    static func sheetHeight(for kind: NovaAttachmentSheetKind, containerHeight: CGFloat) -> CGFloat {
        containerHeight * heightFraction
    }
}

private enum NovaAttachmentMenuPopoverLayout {
    static let rowIconWidth: CGFloat = 40
    static let rowSpacing: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 12
    static let cardHorizontalPadding: CGFloat = 24
    static let cardVerticalPadding: CGFloat = 20
    static let rowVerticalPadding: CGFloat = 16
    static let rowCount: CGFloat = 2

    static var titleFont: UIFont {
        UIFont.systemFont(ofSize: legacyPoppinsSize(17), weight: .medium)
            ?? .systemFont(ofSize: 17, weight: .medium)
    }

    static var estimatedWidth: CGFloat {
        max(
            measuredWidth(for: NovaAttachmentSheetMetrics.menuPopoverTitleKeys),
            NovaAttachmentSheetMetrics.menuPopoverMinWidth
        )
    }

    static var estimatedHeight: CGFloat {
        rowCount * (rowIconWidth + rowVerticalPadding) + cardVerticalPadding
    }

    static func measuredWidth(for titleKeys: [String]) -> CGFloat {
        let maxTextWidth = titleKeys
            .map { NSLocalizedString($0, comment: "") }
            .map { ($0 as NSString).size(withAttributes: [.font: titleFont]).width }
            .max() ?? 0

        return rowHorizontalPadding
            + rowIconWidth
            + rowSpacing
            + maxTextWidth
            + NovaAttachmentSheetMetrics.menuPopoverTextExtraMargin
            + cardHorizontalPadding
    }
}

private struct NovaAttachmentMenuPopoverSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - Menú popover (anclado al +)

struct NovaAttachmentMenuPopover: View {
    @Binding var isPresented: NovaAttachmentSheetKind?
    let anchorFrame: CGRect

    @Environment(\.colorScheme) private var colorScheme
    @State private var popoverSize = CGSize(
        width: NovaAttachmentMenuPopoverLayout.estimatedWidth,
        height: NovaAttachmentMenuPopoverLayout.estimatedHeight
    )

    var body: some View {
        GeometryReader { proxy in
            let overlayOrigin = proxy.frame(in: .global).origin
            let localAnchor = CGRect(
                x: anchorFrame.minX - overlayOrigin.x,
                y: anchorFrame.minY - overlayOrigin.y,
                width: anchorFrame.width,
                height: anchorFrame.height
            )

            let popoverX = resolvedPopoverX(
                localAnchor: localAnchor,
                popoverWidth: popoverSize.width,
                containerWidth: proxy.size.width
            )
            let popoverCenterY = resolvedPopoverCenterY(
                localAnchor: localAnchor,
                popoverHeight: popoverSize.height
            )

            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.08)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissMenu()
                    }
                    .accessibilityHidden(true)

                if anchorFrame != .zero {
                    NovaAttachmentMenuPopoverCard(isPresented: $isPresented)
                        .fixedSize(horizontal: true, vertical: true)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: NovaAttachmentMenuPopoverSizeKey.self,
                                    value: geo.size
                                )
                            }
                        }
                        .position(x: popoverX, y: popoverCenterY)
                        .transition(
                            .scale(scale: 0.88, anchor: UnitPoint(x: 0.5, y: 1))
                                .combined(with: .opacity)
                        )
                }
            }
            .onPreferenceChange(NovaAttachmentMenuPopoverSizeKey.self) { size in
                guard size != .zero else { return }
                popoverSize = size
            }
        }
        .ignoresSafeArea()
    }

    private func resolvedPopoverX(
        localAnchor: CGRect,
        popoverWidth: CGFloat,
        containerWidth: CGFloat
    ) -> CGFloat {
        guard anchorFrame != .zero else { return containerWidth / 2 }

        let margin: CGFloat = 16
        let maxLeading = containerWidth - margin - popoverWidth
        let leadingX = min(max(localAnchor.minX, margin), max(0, maxLeading))
        return leadingX + popoverWidth / 2
    }

    private func resolvedPopoverCenterY(localAnchor: CGRect, popoverHeight: CGFloat) -> CGFloat {
        guard anchorFrame != .zero else { return popoverHeight / 2 }

        let popoverBottom = localAnchor.minY - NovaAttachmentSheetMetrics.menuPopoverGap
        return popoverBottom - popoverHeight / 2
    }

    private func dismissMenu() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            isPresented = nil
        }
    }
}

private struct NovaAttachmentMenuPopoverCard: View {
    @Binding var isPresented: NovaAttachmentSheetKind?
    @Environment(\.colorScheme) private var colorScheme

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NovaAttachmentSheetMetrics.cornerRadius, style: .continuous)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : NovaColors.textPrimary
    }

    private var iconCircleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(
                assetImage: AttachmentIcon.camera.rawValue,
                titleKey: "nova.attach.camera",
                action: {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
                        isPresented = .camera
                    }
                }
            )
            menuRow(
                assetImage: AttachmentIcon.photos.rawValue,
                titleKey: "nova.attach.photos",
                action: {
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
                        isPresented = .photos
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .momentsChromeGlass(in: cardShape, interactive: true)
        .clipShape(cardShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
    }

    private func menuRow(assetImage: String? = nil, systemImage: String? = nil, titleKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconCircleFill)
                        .frame(width: 40, height: 40)

                    if let assetImage {
                        Image(assetImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: AttachmentIconMetrics.attachmentMenu, height: AttachmentIconMetrics.attachmentMenu)
                            .foregroundStyle(primaryTextColor)
                    } else {
                        Image(systemName: systemImage ?? "questionmark")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(primaryTextColor)
                    }
                }
                .frame(width: 40, height: 40, alignment: .center)

                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: legacyPoppinsSize(17), weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsMenuRow)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Custom medium overlay (cámara / fotos)

struct NovaAttachmentSheetOverlay: View {
    @Binding var activeSheet: NovaAttachmentSheetKind?
    let onCaptured: (UIImage) -> Void
    let onAdd: (UIImage) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let kind = activeSheet, kind != .menu {
            GeometryReader { proxy in
                let bottomPadding = NovaInputBarLayout.attachmentSheetBottomInset(
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                )
                let sheetHeight = NovaAttachmentSheetMetrics.sheetHeight(
                    for: kind,
                    containerHeight: proxy.size.height
                )

                ZStack(alignment: .bottom) {
                    Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismiss()
                        }
                        .accessibilityHidden(true)

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
                        case .menu:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, NovaAttachmentSheetMetrics.horizontalInset)
                    .padding(.bottom, bottomPadding)
                    .offset(y: dragOffset)
                    .gesture(dismissDragGesture(sheetHeight: sheetHeight))
                }
                .animation(MotionPolicy.animation(MotionPolicy.Spring.sheet, value: kind), value: kind)
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
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            dragOffset = 0
            activeSheet = nil
        }
    }

    private func backToAttachmentMenu() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            dragOffset = 0
            activeSheet = .menu
        }
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
                    case .menu, .photos:
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
    @State private var zoomLevel: CGFloat = 1.0
    @State private var lensPresets: [CGFloat] = [1.0]
    @State private var pinchAnchorZoom: CGFloat = 1.0
    @State private var isPinchActive = false
    @StateObject private var orientationManager = OrientationManager.shared

    private var deviceOrientation: UIDeviceOrientation {
        orientationManager.orientation
    }

    var body: some View {
        CameraAccessBoundary(onCancel: onBack) {
            cameraContent
        }
    }

    private var cameraContent: some View {
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
                    cameraViewController: $cameraViewController,
                    zoomFactor: $zoomLevel,
                    lensPresets: $lensPresets,
                    enablesPinchToZoom: false
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(0)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(cameraPinchGesture)
                    .zIndex(1)

                VStack {
                    Spacer()

                    if cameraPosition == .back && lensPresets.count > 1 {
                        cameraLensSelector
                            .padding(.bottom, 10)
                    }

                    cameraBottomBar
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }
                .zIndex(20)
                .allowsHitTesting(true)
            }
        }
        .background(Color.black)
        .onAppear {
            orientationManager.startTracking()
        }
        .onChange(of: cameraViewController) { _, controller in
            guard let controller else { return }
            lensPresets = controller.lensPresetFactors
            zoomLevel = controller.currentZoomFactor
            pinchAnchorZoom = controller.currentZoomFactor
        }
        .onDisappear {
            orientationManager.stopTracking()
            showsCameraTools = false
            flashMode = .off
            cameraPosition = .back
            zoomLevel = 1.0
            pinchAnchorZoom = 1.0
            isPinchActive = false
            lensPresets = [1.0]
        }
    }

    private var cameraPinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinchActive {
                    pinchAnchorZoom = zoomLevel
                    isPinchActive = true
                }

                let minZoom = cameraViewController?.minDisplayZoomFactor ?? 0.5
                let maxZoom = cameraViewController?.maxDisplayZoomFactor ?? CameraViewController.photoModeMaxDisplayZoom
                let target = CameraViewController.displayZoomFromPinch(
                    base: pinchAnchorZoom,
                    magnification: value.magnification
                )
                let clamped = min(max(target, minZoom), maxZoom)
                zoomLevel = clamped
                cameraViewController?.setZoomFactor(clamped, animated: false)
            }
            .onEnded { _ in
                isPinchActive = false
            }
    }

    private var cameraLensSelector: some View {
        VStack(spacing: 8) {
            if showsContinuousZoomLabel {
                Text(cameraLensLabel(for: zoomLevel))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            HStack(spacing: 10) {
                ForEach(lensPresets, id: \.self) { preset in
                    let isSelected = isLensPresetSelected(preset)

                    Button {
                        isPinchActive = false
                        pinchAnchorZoom = preset
                        zoomLevel = preset
                        cameraViewController?.setZoomFactor(preset, animated: true)
                    } label: {
                        Text(cameraLensLabel(for: preset))
                            .font(.system(size: isSelected ? 15 : 13, weight: .semibold))
                            .foregroundStyle(isSelected ? Color(hex: "FFD60A") : .white.opacity(0.78))
                            .frame(minWidth: 40, minHeight: 44)
                            .background {
                                if isSelected {
                                    Circle()
                                        .fill(Color.white.opacity(0.16))
                                }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: zoomLevel)
    }

    private var selectedLensPreset: CGFloat? {
        lensPresets.min { abs($0 - zoomLevel) < abs($1 - zoomLevel) }
    }

    private var showsContinuousZoomLabel: Bool {
        guard let selected = selectedLensPreset else { return false }
        return abs(zoomLevel - selected) > 0.08
    }

    private func isLensPresetSelected(_ preset: CGFloat) -> Bool {
        guard let selected = selectedLensPreset else { return false }
        return selected == preset && !showsContinuousZoomLabel
    }

    private func cameraLensLabel(for factor: CGFloat) -> String {
        if factor >= 10, abs(factor.rounded() - factor) < 0.05 {
            return String(format: "%.0f×", factor)
        }
        if factor < 1 {
            return String(format: "%.1f×", factor)
        }
        if abs(factor.rounded() - factor) < 0.05 {
            return String(format: "%.0f×", factor)
        }
        return String(format: "%.1f×", factor)
    }

    private var cameraBottomBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            NovaStoryRoundButton(
                systemImage: "chevron.left",
                accessibilityKey: "nova.attach.back.accessibility",
                action: dismissSheet
            )
            .frame(width: 42, alignment: .center)

            Spacer(minLength: 0)

            CaptureButton(
                isRecording: .constant(false),
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
                    accessibilityKey: "nova.attach.flash.accessibility",
                    action: cycleFlash
                )
            }

            NovaStoryRoundButton(
                systemImage: "arrow.triangle.2.circlepath.camera",
                accessibilityKey: "nova.attach.flip.accessibility",
                action: flipCamera
            )
        }
    }

    private func dismissSheet() {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
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
            isPinchActive = false
            zoomLevel = 1.0
            pinchAnchorZoom = 1.0
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
    @StateObject private var photosGate = PermissionPrimerGate(.photos)

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
        .permissionPrimerGate(photosGate)
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
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.sheet) {
            selectedAssetID = nil
            onBack()
        }
    }

    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if authorizationStatus == .notDetermined {
            photosGate.requestAccess {
                authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                loadPhotosIfAllowed()
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
                                    .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                                    .foregroundStyle(.white)
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
            AttachmentIconView(icon: .photos, preset: .permissionPromptMedium, tintColor: NovaColors.textSecondary)

            Text(LocalizedStringKey(messageKey))
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(NovaColors.textSecondary)
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
    let accessibilityKey: String
    let action: () -> Void

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StoryEditorChromeColor.icon(colorScheme))
                .frame(width: size, height: size)
                .momentsChromeGlass(in: Circle(), interactive: true)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.1 : 0.08),
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

/// Pills con `.momentsChromeGlass(..., interactive: true)`.
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
                .font(.system(size: legacyPoppinsSize(14), weight: tint == nil ? .medium : .semibold))
                .foregroundStyle(tint == nil ? StoryEditorChromeColor.icon(colorScheme) : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .momentsChromeGlass(in: Capsule(), interactive: !disabled,
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
