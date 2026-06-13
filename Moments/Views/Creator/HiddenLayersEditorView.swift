import SwiftUI
import PhotosUI
import AVFoundation
import Kingfisher

struct HiddenLayerDraft: Identifiable, Equatable {
    let id: String
    var type: MomentHiddenLayer.LayerType
    var anchorX: Double
    var anchorY: Double
    var width: Double
    var height: Double
    var shape: MomentHiddenLayer.LayerShape
    var zIndex: Int
    var text: String
    var caption: String
    var imageOffsetX: Double
    var imageOffsetY: Double
    var imageScale: Double
    var imageFrameStyle: HiddenLayerImageFrameStyle
    var localImage: UIImage?
    var localAudioURL: URL?
    var duration: Double?
    var textStyle: HiddenLayerTextStyle
    var presentationStyle: HiddenLayerPresentationStyle
    var unlockMode: MomentHiddenLayer.UnlockMode
    var unlockAt: Date?
    var authorTimezoneIdentifier: String?

    init(
        id: String = UUID().uuidString,
        type: MomentHiddenLayer.LayerType,
        anchorX: Double = 0.5,
        anchorY: Double = 0.5,
        width: Double = 0.28,
        height: Double = 0.16,
        shape: MomentHiddenLayer.LayerShape = .roundedRect,
        zIndex: Int = 0,
        text: String = "",
        caption: String = "",
        imageOffsetX: Double = 0,
        imageOffsetY: Double = 0,
        imageScale: Double = 1,
        imageFrameStyle: HiddenLayerImageFrameStyle = .classic,
        localImage: UIImage? = nil,
        localAudioURL: URL? = nil,
        duration: Double? = nil,
        textStyle: HiddenLayerTextStyle = .clean,
        presentationStyle: HiddenLayerPresentationStyle = .glassCard,
        unlockMode: MomentHiddenLayer.UnlockMode = .immediate,
        unlockAt: Date? = nil,
        authorTimezoneIdentifier: String? = TimeZone.current.identifier
    ) {
        self.id = id
        self.type = type
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.width = width
        self.height = height
        self.shape = shape
        self.zIndex = zIndex
        self.text = text
        self.caption = caption
        self.imageOffsetX = imageOffsetX
        self.imageOffsetY = imageOffsetY
        self.imageScale = imageScale
        self.imageFrameStyle = imageFrameStyle
        self.localImage = localImage
        self.localAudioURL = localAudioURL
        self.duration = duration
        self.textStyle = textStyle
        self.presentationStyle = presentationStyle
        self.unlockMode = unlockMode
        self.unlockAt = unlockAt
        self.authorTimezoneIdentifier = authorTimezoneIdentifier
    }

    var isReadyToPublish: Bool {
        switch type {
        case .text:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .audio:
            return localAudioURL != nil
        case .image:
            return localImage != nil
        }
    }
}

struct HiddenLayersEditorView: View {
    let image: UIImage
    let postAspectRatio: CGFloat?
    @Binding var layers: [HiddenLayerDraft]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLayerId: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingImagePicker = false
    @StateObject private var audioRecorder = HiddenLayerAudioRecorder()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPreviewPlaying = false
    @State private var audioPlaybackProgress: Double = 0
    @State private var audioPlaybackTimer: Timer?
    @State private var adjustingImageLayerId: String?
    @State private var dragOffset: CGSize = .zero
    @State private var draggingLayerId: String?
    @State private var magnifyingLayerId: String?
    @State private var magnifyBaseSize: CGSize?
    @State private var switcherTransientOffset: CGFloat = 0
    @State private var selectedDockType: MomentHiddenLayer.LayerType = .text
    @State private var schedulePickerLayerId: String?
    @State private var pendingScheduleDate = Date()

    private let maxLayers = 3
    private var isDark: Bool { colorScheme == .dark }
    private var primaryTextColor: Color { isDark ? .white : .black }
    private var secondaryTextColor: Color { isDark ? .white.opacity(0.64) : .black.opacity(0.55) }
    private var tertiaryTextColor: Color { isDark ? .white.opacity(0.78) : .black.opacity(0.72) }
    private var subtleSurfaceFill: Color { isDark ? .white.opacity(0.08) : .black.opacity(0.045) }
    private var strongSurfaceFill: Color { isDark ? .white.opacity(0.12) : .black.opacity(0.07) }
    private var previewStrokeColor: Color { isDark ? .white.opacity(0.08) : .black.opacity(0.08) }
    private var hotspotFillColor: Color { isDark ? .white.opacity(0.16) : .black.opacity(0.08) }
    private var hotspotSelectedFillColor: Color { isDark ? .white.opacity(0.24) : .black.opacity(0.14) }
    private var hotspotStrokeColor: Color { isDark ? .white.opacity(0.45) : .black.opacity(0.18) }
    private var hotspotSelectedStrokeColor: Color { isDark ? .white.opacity(0.9) : .black.opacity(0.5) }
    private var sheetTintColor: Color { isDark ? .clear : .white.opacity(0.58) }
    private var displayedPostAspectRatio: CGFloat {
        HiddenLayerLayout.displayedPostAspectRatio(for: image.size, preferredAspectRatio: postAspectRatio)
    }
    private var mediaAspectRatio: CGFloat {
        let ratio = image.size.width / max(image.size.height, 1)
        return (ratio > 0 && ratio.isFinite) ? ratio : displayedPostAspectRatio
    }
    private var dockEditorLayerIndex: Int? {
        if let selectedLayerIndex, layers[selectedLayerIndex].type == selectedDockType {
            return selectedLayerIndex
        }
        return nil
    }
    private var dockHeight: CGFloat {
        if let index = dockEditorLayerIndex {
            switch layers[index].type {
            case .text, .audio, .image:
                return 272
            }
        }
        return 156
    }
    private var readyLayerCount: Int { layers.filter(\.isReadyToPublish).count }
    private var incompleteLayerCount: Int { max(0, layers.count - readyLayerCount) }
    private var layerCountSummary: String {
        if incompleteLayerCount > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("hiddenLayers.count.ready", value: "%1$d listas, %2$d incompletas", comment: "Hidden layers ready and incomplete count"),
                readyLayerCount,
                incompleteLayerCount
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("hiddenLayers.count", value: "%d capas", comment: "Hidden layers count"),
            layers.count
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 14
            let headerHeight: CGFloat = 48
            let verticalSpacing: CGFloat = 10
            let topPadding: CGFloat = 6
            let bottomPadding: CGFloat = 8
            let maxCanvasHeight = max(
                260,
                proxy.size.height - headerHeight - dockHeight - topPadding - bottomPadding - (verticalSpacing * 2)
            )
            let canvasHeight = min(
                maxCanvasHeight,
                previewCanvasHeight(for: proxy.size.width - (horizontalPadding * 2))
            )

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(sheetTintColor)
                    .ignoresSafeArea()

                VStack(spacing: verticalSpacing) {
                    headerBar
                        .frame(height: headerHeight)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, topPadding)

                    editorCanvas(height: canvasHeight)
                        .frame(height: maxCanvasHeight, alignment: .center)
                        .padding(.horizontal, horizontalPadding)

                    dockContent
                        .frame(height: dockHeight)
                        .padding(.horizontal, horizontalPadding)
                }
                .padding(.bottom, bottomPadding)
            }
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $photoPickerItem, matching: .images)
        .sheet(
            isPresented: Binding(
                get: { schedulePickerLayerId != nil },
                set: { isPresented in
                    if !isPresented {
                        schedulePickerLayerId = nil
                    }
                }
            )
        ) {
            HiddenLayerScheduleSheet(
                date: Binding(
                    get: { pendingScheduleDate },
                    set: { pendingScheduleDate = $0 }
                ),
                onCancel: {
                    schedulePickerLayerId = nil
                },
                onApply: {
                    if let layerId = schedulePickerLayerId {
                        applyPendingSchedule(to: layerId)
                        schedulePickerLayerId = nil
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: photoPickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        addImageLayer(image)
                        showingImagePicker = false
                        photoPickerItem = nil
                    }
                }
            }
        }
        .onDisappear {
            stopAudioPreview()
        }
        .onAppear {
            if let selectedLayerIndex {
                selectedDockType = layers[selectedLayerIndex].type
            } else if let lastType = layers.last?.type {
                selectedDockType = lastType
            }
        }
    }

    private var headerBar: some View {
        ZStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(primaryTextColor)
                    .padding(10)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 1) {
                Text(NSLocalizedString("hiddenLayers.editor.title", value: "Capas ocultas", comment: "Hidden layers editor title"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)

                if selectedLayerId == nil {
                    Text(layerCountSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            }

            Button(NSLocalizedString("common.done", value: "Listo", comment: "Done")) {
                dismiss()
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(primaryTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(in: Capsule(), interactive: true)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func editorCanvas(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let imageRect = editorPreviewRect(in: proxy.size)
            let presentationMode = MomentCarouselLayoutRules.presentationMode(
                for: mediaAspectRatio,
                canvasAspectRatio: displayedPostAspectRatio
            )

            ZStack {
                RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous)
                    .fill(subtleSurfaceFill)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: storyViewerCanvasCornerRadius, style: .continuous))
                    .onTapGesture {
                        selectedLayerId = nil
                    }

                if presentationMode == .fitWithBlur {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .blur(radius: 30)
                        .saturation(0.9)
                        .overlay(Color.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .allowsHitTesting(false)
                }

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: presentationMode.swiftUIContentMode)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .onTapGesture {
                        selectedLayerId = nil
                    }

                editorGhostRail(in: imageRect)

                ForEach(layers) { layer in
                    hiddenLayerHotspot(layer, imageRect: imageRect)
                        .zIndex(draggingLayerId == layer.id ? 4000 : Double(layer.zIndex))
                }
            }
            .coordinateSpace(name: "hiddenLayerCanvas")
        }
        .frame(height: height)
    }

    private func editorPreviewRect(in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let availableWidth = containerSize.width
        let availableHeight = previewCanvasHeight(for: containerSize.width)

        guard availableWidth > 0, availableHeight > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        return CGRect(
            x: 0,
            y: (containerSize.height - availableHeight) / 2,
            width: availableWidth,
            height: availableHeight
        )
    }

    private func previewCanvasHeight(for availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return 340 }

        let ratio = (displayedPostAspectRatio > 0 && displayedPostAspectRatio.isFinite) ? displayedPostAspectRatio : 1.0
        let canonicalFeedWidth = FeedMomentCardLayout.mediaContentWidth
        let canonicalFeedHeight = feedCardHeight(for: canonicalFeedWidth, ratio: ratio)
        let scaledWidth = availableWidth

        guard canonicalFeedWidth > 0, canonicalFeedHeight > 0, scaledWidth > 0 else { return 340 }

        let scale = min(scaledWidth / canonicalFeedWidth, 1.0)
        let scaledHeight = canonicalFeedHeight * scale
        return scaledHeight
    }

    private func feedCardHeight(for width: CGFloat, ratio: CGFloat) -> CGFloat {
        guard width > 0 else { return 300 }

        let safeRatio = (ratio > 0 && ratio.isFinite) ? ratio : 1.0
        let idealHeight = width / safeRatio
        let screenHeight = UIScreen.main.bounds.height
        let feedHeaderHeight: CGFloat = 88
        let feedSelectorHeight: CGFloat = 35
        let tabbarHeight: CGFloat = 50
        let availableHeight = screenHeight - feedHeaderHeight - feedSelectorHeight - tabbarHeight - 60
        let maxAllowed = availableHeight * 0.95

        return max(max(min(idealHeight, maxAllowed), 150), 200)
    }



    @ViewBuilder
    private var dockContent: some View {
        if let index = dockEditorLayerIndex {
            VStack(spacing: 10) {
                VStack(spacing: 10) {
                    ZStack {
                        HStack(spacing: 8) {
                            Button {
                                selectedLayerId = nil
                            } label: {
                                Image(systemName: "chevron.down")
                                    .foregroundColor(primaryTextColor)
                                    .padding(10)
                                    .background(strongSurfaceFill, in: Circle())
                            }

                            if layers[index].type == .image, layers.count < maxLayers {
                                Button {
                                    createLayer(for: selectedDockType)
                                } label: {
                                    Image(systemName: "plus")
                                        .foregroundColor(primaryTextColor)
                                        .padding(10)
                                        .background(strongSurfaceFill, in: Circle())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(layerTitle(layers[index]))
                            .font(.headline)
                            .foregroundColor(primaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .offset(x: layers[index].type == .image ? -12 : 0)

                        HStack(spacing: 8) {
                            if layers.count < maxLayers, layers[index].type != .image {
                                Button {
                                    createLayer(for: selectedDockType)
                                } label: {
                                    Image(systemName: "plus")
                                        .foregroundColor(primaryTextColor)
                                        .padding(10)
                                        .background(strongSurfaceFill, in: Circle())
                                }
                            }

                            if layers[index].type == .image {
                                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                                    miniSheetHeaderIconButton("photo.on.rectangle.angled")
                                }

                                Button {
                                    adjustingImageLayerId = adjustingImageLayerId == layers[index].id ? nil : layers[index].id
                                } label: {
                                    miniSheetHeaderIconButton("viewfinder", isActive: adjustingImageLayerId == layers[index].id)
                                }
                            }

                            Button(role: .destructive) {
                                let removedType = layers[index].type
                                layers.remove(at: index)
                                selectedLayerId = nil
                                selectedDockType = removedType
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(primaryTextColor)
                                    .padding(10)
                                    .background(strongSurfaceFill, in: Circle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if layers[index].type == .text {
                        TextField(NSLocalizedString("hiddenLayers.text.placeholder", value: "Escribe el secreto...", comment: "Hidden layer text placeholder"), text: limitedTextBinding(for: index))
                            .textFieldStyle(.plain)
                            .foregroundColor(primaryTextColor)
                            .padding(14)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)

                        HStack(spacing: 8) {
                            Menu {
                                ForEach(HiddenLayerPresentationStyle.allCases, id: \.self) { style in
                                    Button(style.displayName) {
                                        layers[index].presentationStyle = style
                                        resizeTextLayerToFitContent(at: index)
                                    }
                                }
                            } label: {
                                compactSelectionChip(
                                    title: NSLocalizedString("hiddenLayers.text.style", value: "Estilo", comment: "Hidden text style selector title"),
                                    value: layers[index].presentationStyle.displayName,
                                    systemImage: "square.text.square"
                                )
                            }
                            .buttonStyle(.plain)

                            Menu {
                                ForEach(HiddenLayerTextStyle.allCases, id: \.self) { style in
                                    Button(style.displayName) {
                                        layers[index].textStyle = style
                                        resizeTextLayerToFitContent(at: index)
                                    }
                                }
                            } label: {
                                compactSelectionChip(
                                    title: NSLocalizedString("hiddenLayers.text.font", value: "Fuente", comment: "Hidden text font selector title"),
                                    value: layers[index].textStyle.displayName,
                                    systemImage: "textformat"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        availabilityControls(for: index)
                    } else if layers[index].type == .audio {
                        VStack(spacing: 10) {
                            audioControls(for: index)
                            availabilityControls(for: index)
                        }
                    } else if layers[index].type == .image {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(
                                NSLocalizedString("hiddenLayers.image.caption.placeholder", value: "Añade un caption", comment: "Hidden image caption placeholder"),
                                text: limitedCaptionBinding(for: index)
                            )
                            .textFieldStyle(.plain)
                            .foregroundColor(primaryTextColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)

                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(HiddenLayerImageFrameStyle.allCases, id: \.self) { style in
                                        Button(style.displayName) {
                                            layers[index].imageFrameStyle = style
                                        }
                                    }
                                } label: {
                                    compactSelectionChip(
                                        title: NSLocalizedString("hiddenLayers.image.frame", value: "Marco", comment: "Hidden image frame selector title"),
                                        value: layers[index].imageFrameStyle.displayName,
                                        systemImage: "square.on.square"
                                    )
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    ForEach(HiddenLayerTextStyle.captionStyles, id: \.self) { style in
                                        Button(style.displayName) {
                                            layers[index].textStyle = style
                                        }
                                    }
                                } label: {
                                    compactSelectionChip(
                                        title: NSLocalizedString("hiddenLayers.image.font", value: "Fuente", comment: "Hidden image font selector title"),
                                        value: layers[index].textStyle.displayName,
                                        systemImage: "textformat"
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            availabilityControls(for: index)
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Spacer(minLength: 0)

                typeSwitcherPill
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                VStack(spacing: 3) {
                    Text(emptyStateTitle(for: selectedDockType))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)

                    Text(emptyStateSubtitle(for: selectedDockType))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Button {
                    createLayer(for: selectedDockType)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: plusActionIcon(for: selectedDockType))
                            .font(.system(size: 13, weight: .bold))

                        Text(addActionTitle(for: selectedDockType))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(primaryTextColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minWidth: 168)
                    .liquidGlass(in: Capsule(), interactive: canCreateLayer(of: selectedDockType))
                    .opacity(canCreateLayer(of: selectedDockType) ? 1 : 0.48)
                }
                .buttonStyle(.plain)
                .disabled(!canCreateLayer(of: selectedDockType))

                Spacer(minLength: 0)

                typeSwitcherPill
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var layerActions: some View {
        HStack(spacing: 8) {
            Button {
                addTextLayer()
            } label: {
                actionLabel("textformat", "hiddenLayers.add.text", "Texto")
            }
            .disabled(layers.count >= maxLayers)

            Button {
                addAudioLayer()
            } label: {
                actionLabel("waveform", "hiddenLayers.add.audio", "Audio")
            }
            .disabled(layers.count >= maxLayers)

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                actionLabel("photo", "hiddenLayers.add.image", "Imagen")
                    .opacity(layers.count >= maxLayers ? 0.45 : 1)
            }
            .disabled(layers.count >= maxLayers)
        }
    }

    private var typeSwitcherPill: some View {
        GeometryReader { proxy in
            let options = MomentHiddenLayer.LayerType.allCases
            let activeType = selectedDockType
            let innerWidth = max(proxy.size.width - 6, 0)
            let segmentWidth = innerWidth / CGFloat(options.count)

            ZStack {
                Capsule()
                    .fill(Color.clear)
                    .liquidGlass(in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(previewStrokeColor, lineWidth: 0.75)
                    )

                Capsule()
                    .fill(Color.white.opacity(isDark ? 0.055 : 0.035))
                    .frame(width: segmentWidth, height: 34)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(isDark ? 0.24 : 0.08), radius: 7, x: 0, y: 2)
                    .offset(x: switcherPillOffset(for: proxy.size.width, activeType: activeType))

                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { type in
                        Button {
                            if activeType != type {
                                HapticManager.shared.selection()
                            }
                            withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
                                selectDockType(type)
                                switcherTransientOffset = 0
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: layerIcon(type))
                                    .font(.system(size: 13, weight: .medium))

                                Text(layerPillTitle(type))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(activeType == type ? primaryTextColor : secondaryTextColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 3)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: switcherVisualIndex(for: proxy.size.width, activeType: activeType))

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    switcherTransientOffset = constrainedSwitcherTranslation(
                                        value.translation.width,
                                        width: proxy.size.width,
                                        activeType: activeType
                                    )
                                }
                            }
                            .onEnded { value in
                                settleSwitcherSelection(
                                    translation: value.translation.width,
                                    locationX: value.location.x,
                                    width: proxy.size.width,
                                    activeType: activeType
                                )
                            }
                    )
            }
        }
        .frame(height: 42)
    }

    private func hiddenLayerHotspot(_ layer: HiddenLayerDraft, imageRect: CGRect) -> some View {
        let isSelected = selectedLayerId == layer.id
        let frame = HiddenLayerLayout.frame(for: layer, in: imageRect)
        let size = frame.size
        let position = CGPoint(x: frame.midX, y: frame.midY)

        return ZStack {
            canvasPreview(for: layer, size: size, isSelected: isSelected)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            activateLayer(layer.id)
        }
        .gesture(
            DragGesture(coordinateSpace: .named("hiddenLayerCanvas"))
                .onChanged { value in
                    if adjustingImageLayerId == layer.id && layer.type == .image { return }
                    guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
                    draggingLayerId = layer.id
                    selectedLayerId = layer.id
                    let currentCenter = CGPoint(
                        x: imageRect.minX + imageRect.width * layers[index].anchorX,
                        y: imageRect.minY + imageRect.height * layers[index].anchorY
                    )
                    if dragOffset == .zero {
                        dragOffset = CGSize(
                            width: value.startLocation.x - currentCenter.x,
                            height: value.startLocation.y - currentCenter.y
                        )
                    }
                    let proposedCenter = CGPoint(
                        x: value.location.x - dragOffset.width,
                        y: value.location.y - dragOffset.height
                    )
                    let normalizedX = (proposedCenter.x - imageRect.minX) / max(imageRect.width, 1)
                    let normalizedY = (proposedCenter.y - imageRect.minY) / max(imageRect.height, 1)
                    let halfWidthRatio = min(0.5, max(0, layers[index].width / 2))
                    let halfHeightRatio: CGFloat
                    if layer.type == .image {
                        let imageHeightRatio = (layers[index].width * HiddenLayerLayout.imageAspectRatio * imageRect.width) / max(imageRect.height, 1)
                        halfHeightRatio = min(0.5, max(0, imageHeightRatio / 2))
                    } else {
                        halfHeightRatio = min(0.5, max(0, layers[index].height / 2))
                    }
                    layers[index].anchorX = min(1 - halfWidthRatio, max(halfWidthRatio, normalizedX))
                    layers[index].anchorY = min(1 - halfHeightRatio, max(halfHeightRatio, normalizedY))
                }
                .onEnded { _ in
                    dragOffset = .zero
                    draggingLayerId = nil
                    activateLayer(layer.id)
                }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if adjustingImageLayerId == layer.id && layer.type == .image { return }
                    guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
                    selectedLayerId = layer.id
                    draggingLayerId = layer.id
                    if magnifyingLayerId != layer.id || magnifyBaseSize == nil {
                        magnifyingLayerId = layer.id
                        magnifyBaseSize = CGSize(width: layers[index].width, height: layers[index].height)
                    }
                    guard let base = magnifyBaseSize else { return }
                    let ratio = max(0.7, min(2.2, value))
                    let aspect: CGFloat
                    let minWidth: CGFloat
                    let maxWidth: CGFloat
                    if layer.type == .image {
                        aspect = HiddenLayerLayout.imageAspectRatio
                        minWidth = max(0.12, 0.10 / aspect)
                        maxWidth = min(0.55, 0.42 / aspect)
                    } else if layer.type == .text {
                        aspect = HiddenLayerLayout.textAspectRatio
                        minWidth = 0.16
                        maxWidth = 0.62
                    } else {
                        aspect = max(base.height / max(base.width, 0.001), 0.25)
                        minWidth = 0.12
                        maxWidth = 0.55
                    }
                    let newWidth = min(maxWidth, max(minWidth, base.width * ratio))
                    let newHeight = layer.type == .image
                        ? (newWidth * aspect)
                        : min(0.42, max(0.10, newWidth * aspect))
                    layers[index].width = Double(newWidth)
                    layers[index].height = Double(newHeight)
                    let halfWidthRatio = min(0.5, max(0, newWidth / 2))
                    let halfHeightRatio = min(0.5, max(0, newHeight / 2))
                    layers[index].anchorX = min(1 - halfWidthRatio, max(halfWidthRatio, layers[index].anchorX))
                    layers[index].anchorY = min(1 - halfHeightRatio, max(halfHeightRatio, layers[index].anchorY))
                }
                .onEnded { _ in
                    if let magnifyingLayerId {
                        activateLayer(magnifyingLayerId)
                    }
                    magnifyingLayerId = nil
                    magnifyBaseSize = nil
                    draggingLayerId = nil
                }
        )
        .position(position)
    }

    @ViewBuilder
    private func editorGhostRail(in imageRect: CGRect) -> some View {
        let railWidth: CGFloat = min(max(imageRect.width * 0.52, 164), 214)
        let railHeight: CGFloat = 56
        let railX = imageRect.maxX - 16 - (railWidth / 2)
        let railY = imageRect.maxY - 16 - (railHeight / 2)

        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == 0 ? 0.26 : 0.14))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(index == 0 ? 0.24 : 0.10), lineWidth: 1)
                    )
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        )
        .opacity(0.5)
        .allowsHitTesting(false)
        .position(x: railX, y: railY)
    }

    @ViewBuilder
    private func canvasPreview(for layer: HiddenLayerDraft, size: CGSize, isSelected: Bool) -> some View {
        switch layer.type {
        case .text:
            textCanvasPreview(for: layer, size: size)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        case .audio:
            audioCanvasPreview(for: layer)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        case .image:
            imageCanvasPreview(for: layer, size: size, isAdjusting: adjustingImageLayerId == layer.id, isSelected: isSelected)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(adjustingImageLayerId == layer.id)
        }
    }

    private func audioControls(for index: Int) -> some View {
        VStack(spacing: 10) {
            if layers[index].localAudioURL != nil && !audioRecorder.isRecording {
                HStack {
                    circularAudioActionButton(systemName: "trash") {
                        clearAudio(for: index)
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text((layers[index].duration ?? 0).formattedDetailedDuration)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(primaryTextColor)
                            .contentTransition(.numericText())

                        Text(NSLocalizedString("hiddenLayers.audio.ready", value: "Listo para revelar", comment: "Audio ready state"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(tertiaryTextColor)

                        Button {
                            isPreviewPlaying ? stopAudioPreview() : startAudioPreview(for: index)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isPreviewPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(NSLocalizedString("hiddenLayers.audio.preview", value: "Escuchar", comment: "Listen to hidden audio"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(primaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(subtleSurfaceFill, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(previewStrokeColor, lineWidth: 1)
                            )
                        }
                    }

                    Spacer()

                    circularAudioActionButton(systemName: "arrow.counterclockwise") {
                        restartAudioRecording(for: index)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Button {
                        if audioRecorder.isRecording {
                            if let result = audioRecorder.stopRecording() {
                                layers[index].localAudioURL = result.url
                                layers[index].duration = result.duration
                                startAudioPreview(for: index)
                            }
                        } else {
                            stopAudioPreview()
                            audioRecorder.startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 58, height: 58)
                                .liquidGlass(in: Circle(), interactive: true)

                            if audioRecorder.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.red)
                                    .frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .scaleEffect(audioRecorder.isRecording ? 1.06 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: audioRecorder.isRecording)

                    VStack(spacing: 4) {
                        Text((audioRecorder.isRecording ? audioRecorder.elapsedTime : 0).formattedDetailedDuration)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(audioRecorder.isRecording ? .red : primaryTextColor)
                            .contentTransition(.numericText())

                        Text(audioRecorder.isRecording
                             ? NSLocalizedString("hiddenLayers.audio.recording", value: "Grabando...", comment: "Recording state")
                             : NSLocalizedString("hiddenLayers.audio.tapToRecord", value: "Toca para grabar", comment: "Tap to record"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(tertiaryTextColor)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func circularAudioActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle(), interactive: true)
        }
    }

    private func actionLabel(_ icon: String, _ key: String, _ fallback: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(NSLocalizedString(key, value: fallback, comment: "Hidden layer action"))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(primaryTextColor)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(strongSurfaceFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectedLayerIndex: Int? {
        guard let selectedLayerId else { return nil }
        return layers.firstIndex { $0.id == selectedLayerId }
    }

    private func addTextLayer() {
        guard layers.count < maxLayers else { return }
        let origin = nextLayerOrigin()
        let textWidth: CGFloat = 0.34
        let layer = HiddenLayerDraft(
            type: .text,
            anchorX: origin.x,
            anchorY: origin.y,
            width: Double(textWidth),
            height: Double(textWidth * HiddenLayerLayout.textAspectRatio),
            zIndex: layers.count,
            text: ""
        )
        layers.append(layer)
        if let index = layers.indices.last {
            resizeTextLayerToFitContent(at: index)
        }
        selectedLayerId = layer.id
        selectedDockType = .text
    }

    private func addAudioLayer() {
        guard layers.count < maxLayers else { return }
        let origin = nextLayerOrigin()
        let layer = HiddenLayerDraft(type: .audio, anchorX: origin.x, anchorY: origin.y, width: 0.18, height: 0.18, zIndex: layers.count, presentationStyle: .captionPill)
        layers.append(layer)
        selectedLayerId = layer.id
        selectedDockType = .audio
    }

    private func addImageLayer(_ image: UIImage) {
        if let index = selectedLayerIndex, layers[index].type == .image {
            layers[index].localImage = image
            selectedDockType = .image
            return
        }

        guard layers.count < maxLayers else {
            return
        }
        let origin = nextLayerOrigin()
        let imageWidth: CGFloat = 0.24
        let imageHeight = imageWidth * HiddenLayerLayout.imageAspectRatio
        let layer = HiddenLayerDraft(
            type: .image,
            anchorX: origin.x,
            anchorY: origin.y,
            width: Double(imageWidth),
            height: Double(imageHeight),
            zIndex: layers.count,
            localImage: image,
            presentationStyle: .paperNote
        )
        layers.append(layer)
        selectedLayerId = layer.id
        selectedDockType = .image
    }

    private func nextLayerOrigin() -> CGPoint {
        let presets: [CGPoint] = [
            CGPoint(x: 0.30, y: 0.26),
            CGPoint(x: 0.50, y: 0.56),
            CGPoint(x: 0.72, y: 0.28)
        ]
        return presets[min(layers.count, presets.count - 1)]
    }

    private func activateLayer(_ id: String) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let layerType = layers[index].type
        if index != layers.indices.last {
            let layer = layers.remove(at: index)
            layers.append(layer)
            for idx in layers.indices {
                layers[idx].zIndex = idx
            }
        }
        selectedLayerId = id
        selectedDockType = layerType
    }

    private func selectDockType(_ type: MomentHiddenLayer.LayerType) {
        selectedDockType = type
        if let existingId = layers.last(where: { $0.type == type })?.id {
            activateLayer(existingId)
        } else {
            selectedLayerId = nil
        }
    }

    private func canCreateLayer(of type: MomentHiddenLayer.LayerType) -> Bool {
        layers.count < maxLayers
    }

    private func createLayer(for type: MomentHiddenLayer.LayerType) {
        switch type {
        case .text:
            addTextLayer()
        case .audio:
            addAudioLayer()
        case .image:
            showingImagePicker = true
        }
    }

    private func switcherBaseOffset(for totalWidth: CGFloat, activeType: MomentHiddenLayer.LayerType) -> CGFloat {
        let options = MomentHiddenLayer.LayerType.allCases
        let segmentWidth = (totalWidth - 6) / CGFloat(options.count)
        let start = -((CGFloat(options.count - 1) * segmentWidth) / 2)
        let currentIndex = CGFloat(options.firstIndex(of: activeType) ?? 0)
        return start + (currentIndex * segmentWidth)
    }

    private func switcherPillOffset(for totalWidth: CGFloat, activeType: MomentHiddenLayer.LayerType) -> CGFloat {
        switcherBaseOffset(for: totalWidth, activeType: activeType) + switcherTransientOffset
    }

    private func switcherVisualIndex(for totalWidth: CGFloat, activeType: MomentHiddenLayer.LayerType) -> Int {
        let options = MomentHiddenLayer.LayerType.allCases
        let segmentWidth = (totalWidth - 6) / CGFloat(options.count)
        let start = -((CGFloat(options.count - 1) * segmentWidth) / 2)
        let raw = ((switcherPillOffset(for: totalWidth, activeType: activeType) - start) / segmentWidth).rounded()
        return min(max(Int(raw), 0), options.count - 1)
    }

    private func constrainedSwitcherTranslation(_ translation: CGFloat, width: CGFloat, activeType: MomentHiddenLayer.LayerType) -> CGFloat {
        let options = MomentHiddenLayer.LayerType.allCases
        let segmentWidth = (width - 6) / CGFloat(options.count)
        let minOffset = -((CGFloat(options.count - 1) * segmentWidth) / 2)
        let maxOffset = ((CGFloat(options.count - 1) * segmentWidth) / 2)
        let proposed = switcherBaseOffset(for: width, activeType: activeType) + translation
        let clamped = min(max(proposed, minOffset), maxOffset)
        return clamped - switcherBaseOffset(for: width, activeType: activeType)
    }

    private func settleSwitcherSelection(
        translation: CGFloat,
        locationX: CGFloat,
        width: CGFloat,
        activeType: MomentHiddenLayer.LayerType
    ) {
        let options = MomentHiddenLayer.LayerType.allCases
        let segmentWidth = (width - 6) / CGFloat(options.count)
        let proposedOffset = switcherBaseOffset(for: width, activeType: activeType) + translation
        let start = -((CGFloat(options.count - 1) * segmentWidth) / 2)
        let fractionalIndex = (proposedOffset - start) / segmentWidth

        let targetIndex: Int
        let threshold = min(segmentWidth * 0.28, 36)

        if abs(translation) > threshold && abs(translation) < segmentWidth * 0.5 {
            let currentIndex = options.firstIndex(of: activeType) ?? 0
            let direction = translation > 0 ? 1 : -1
            targetIndex = min(max(currentIndex + direction, 0), options.count - 1)
        } else if abs(translation) < 5 {
            targetIndex = min(max(Int(locationX / segmentWidth), 0), options.count - 1)
        } else {
            targetIndex = min(max(Int(fractionalIndex.rounded()), 0), options.count - 1)
        }

        let targetType = options[targetIndex]
        if targetType != activeType {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectDockType(targetType)
            switcherTransientOffset = 0
        }
    }

    private func emptyStateTitle(for type: MomentHiddenLayer.LayerType) -> String {
        switch type {
        case .text:
            return NSLocalizedString("hiddenLayers.empty.text.title", value: "Añade un texto oculto", comment: "Hidden layers empty text title")
        case .audio:
            return NSLocalizedString("hiddenLayers.empty.audio.title", value: "Añade un audio oculto", comment: "Hidden layers empty audio title")
        case .image:
            return NSLocalizedString("hiddenLayers.empty.image.title", value: "Añade una imagen oculta", comment: "Hidden layers empty image title")
        }
    }

    private func emptyStateSubtitle(for type: MomentHiddenLayer.LayerType) -> String {
        switch type {
        case .text:
            return NSLocalizedString("hiddenLayers.empty.text.subtitle", value: "Esconde un mensaje sobre el post y colócalo donde quieras.", comment: "Hidden layers empty text subtitle")
        case .audio:
            return NSLocalizedString("hiddenLayers.empty.audio.subtitle", value: "Graba un audio corto que solo aparezca cuando lo descubran.", comment: "Hidden layers empty audio subtitle")
        case .image:
            return NSLocalizedString("hiddenLayers.empty.image.subtitle", value: "Usa una polaroid oculta para esconder otra foto dentro del post.", comment: "Hidden layers empty image subtitle")
        }
    }

    private func addActionTitle(for type: MomentHiddenLayer.LayerType) -> String {
        switch type {
        case .text:
            return NSLocalizedString("hiddenLayers.add.text.cta", value: "Añadir texto", comment: "Add text hidden layer button")
        case .audio:
            return NSLocalizedString("hiddenLayers.add.audio.cta", value: "Añadir audio", comment: "Add audio hidden layer button")
        case .image:
            return NSLocalizedString("hiddenLayers.add.image.cta", value: "Añadir imagen", comment: "Add image hidden layer button")
        }
    }

    private func plusActionIcon(for type: MomentHiddenLayer.LayerType) -> String {
        switch type {
        case .text:
            return "plus.bubble"
        case .audio:
            return "waveform.badge.plus"
        case .image:
            return "photo.badge.plus"
        }
    }

    private func limitedTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { layers[index].text },
            set: { newValue in
                layers[index].text = String(newValue.prefix(120))
                resizeTextLayerToFitContent(at: index)
            }
        )
    }

    private func limitedCaptionBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { layers[index].caption },
            set: { newValue in
                layers[index].caption = String(newValue.prefix(40))
            }
        )
    }

    private func layerTitle(_ layer: HiddenLayerDraft) -> String {
        switch layer.type {
        case .text: return NSLocalizedString("hiddenLayers.type.text", value: "Texto oculto", comment: "Hidden text layer")
        case .audio: return NSLocalizedString("hiddenLayers.type.audio", value: "Audio oculto", comment: "Hidden audio layer")
        case .image: return NSLocalizedString("hiddenLayers.type.image", value: "Imagen oculta", comment: "Hidden image layer")
        }
    }

    private func layerPillTitle(_ type: MomentHiddenLayer.LayerType) -> String {
        switch type {
        case .text:
            return NSLocalizedString("hiddenLayers.add.text", value: "Texto", comment: "Hidden layer text")
        case .audio:
            return NSLocalizedString("hiddenLayers.add.audio", value: "Audio", comment: "Hidden layer audio")
        case .image:
            return NSLocalizedString("hiddenLayers.add.image", value: "Imagen", comment: "Hidden layer image")
        }
    }

    private func layerIcon(_ type: MomentHiddenLayer.LayerType) -> String {
        switch type {
        case .text: return "textformat"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }

    @ViewBuilder
    private func styleChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? strongSurfaceFill : subtleSurfaceFill)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? hotspotStrokeColor : previewStrokeColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func audioPreviewCard(for index: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<28, id: \.self) { step in
                    Capsule()
                        .fill(stepProgress(step) <= audioPlaybackProgress ? Color(red: 1.0, green: 0.42, blue: 0.34) : (isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)))
                        .frame(width: 5, height: waveformHeight(for: step))
                }
            }
            .frame(height: 42)

            Text((audioRecorder.isRecording ? audioRecorder.elapsedTime : (layers[index].duration ?? 0)).formattedDetailedDuration)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(audioRecorder.isRecording ? .red : primaryTextColor)

            Text(audioRecorder.isRecording ? NSLocalizedString("hiddenLayers.audio.recording", value: "Grabando...", comment: "Recording state") : (layers[index].localAudioURL == nil ? NSLocalizedString("hiddenLayers.audio.tapToRecord", value: "Toca para grabar", comment: "Tap to record") : NSLocalizedString("hiddenLayers.audio.ready", value: "Listo para revelar", comment: "Audio ready state")))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(secondaryTextColor)
        }
    }

    @ViewBuilder
    private func imageCanvasPreview(for layer: HiddenLayerDraft, size: CGSize, isAdjusting: Bool, isSelected: Bool) -> some View {
        if let image = layer.localImage {
            HiddenLayerPolaroidPreview(
                image: image,
                caption: layer.caption.isEmpty ? NSLocalizedString("hiddenLayers.image.caption", value: "oculto", comment: "Hidden layer image caption") : layer.caption,
                captionStyle: layer.textStyle,
                frameStyle: layer.imageFrameStyle,
                imageOffset: CGSize(width: layer.imageOffsetX, height: layer.imageOffsetY),
                imageScale: layer.imageScale,
                showsAdjustingMask: isAdjusting,
                canvasSize: size
            )
            .gesture(
                isAdjusting ? imageAdjustmentGesture(for: layer.id) : nil
            )
        }
    }

    private func imageAdjustmentGesture(for layerId: String) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return }
                    layers[index].imageOffsetX = min(48, max(-48, value.translation.width))
                    layers[index].imageOffsetY = min(48, max(-48, value.translation.height))
                },
            MagnificationGesture()
                .onChanged { scale in
                    guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return }
                    layers[index].imageScale = min(2.2, max(1.0, scale))
                }
        )
    }

    private func miniSheetHeaderIconButton(_ systemName: String, isActive: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(primaryTextColor)
            .frame(width: 40, height: 40)
            .background((isActive ? strongSurfaceFill : subtleSurfaceFill), in: Circle())
            .overlay(
                Circle()
                    .stroke(isActive ? hotspotSelectedStrokeColor : previewStrokeColor, lineWidth: 1)
            )
    }

    private func compactSelectionChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(secondaryTextColor)

                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(subtleSurfaceFill, in: Capsule())
        .overlay(
            Capsule()
                .stroke(previewStrokeColor, lineWidth: 1)
        )
    }

    private func availabilityControls(for index: Int) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button(NSLocalizedString("hiddenLayers.unlock.now", value: "Ahora", comment: "Hidden layer unlock now")) {
                    layers[index].unlockMode = .immediate
                    layers[index].unlockAt = nil
                    layers[index].authorTimezoneIdentifier = TimeZone.current.identifier
                }

                Button(NSLocalizedString("hiddenLayers.unlock.scheduled", value: "Programada", comment: "Hidden layer scheduled unlock")) {
                    if layers[index].unlockMode != .scheduled {
                        layers[index].unlockMode = .scheduled
                        layers[index].unlockAt = defaultScheduledDate()
                        layers[index].authorTimezoneIdentifier = TimeZone.current.identifier
                    }
                }
            } label: {
                compactSelectionChip(
                    title: NSLocalizedString("hiddenLayers.unlock.title", value: "Disponibilidad", comment: "Hidden layer availability title"),
                    value: unlockModeTitle(layers[index].unlockMode),
                    systemImage: "clock"
                )
            }
            .buttonStyle(.plain)

            if layers[index].unlockMode == .scheduled {
                Menu {
                    Button(NSLocalizedString("hiddenLayers.unlock.tonight", value: "Esta noche", comment: "Hidden layer unlock tonight")) {
                        layers[index].unlockAt = tonightUnlockDate()
                        layers[index].authorTimezoneIdentifier = TimeZone.current.identifier
                    }

                    Button(NSLocalizedString("hiddenLayers.unlock.tomorrow", value: "Mañana", comment: "Hidden layer unlock tomorrow")) {
                        layers[index].unlockAt = tomorrowUnlockDate()
                        layers[index].authorTimezoneIdentifier = TimeZone.current.identifier
                    }

                    Button(NSLocalizedString("hiddenLayers.unlock.pickDate", value: "Elegir fecha", comment: "Hidden layer choose date")) {
                        pendingScheduleDate = layers[index].unlockAt ?? defaultScheduledDate()
                        schedulePickerLayerId = layers[index].id
                    }
                } label: {
                    compactSelectionChip(
                        title: NSLocalizedString("hiddenLayers.unlock.opens", value: "Se abre", comment: "Hidden layer opens title"),
                        value: formattedUnlockDate(layers[index].unlockAt),
                        systemImage: "calendar"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func unlockModeTitle(_ mode: MomentHiddenLayer.UnlockMode) -> String {
        switch mode {
        case .immediate:
            return NSLocalizedString("hiddenLayers.unlock.now", value: "Ahora", comment: "Hidden layer unlock now")
        case .scheduled:
            return NSLocalizedString("hiddenLayers.unlock.scheduled", value: "Programada", comment: "Hidden layer scheduled unlock")
        }
    }

    private func formattedUnlockDate(_ date: Date?) -> String {
        guard let date else {
            return NSLocalizedString("hiddenLayers.unlock.pickDate", value: "Elegir fecha", comment: "Hidden layer choose date")
        }

        if Calendar.current.isDateInToday(date) {
            return String(
                format: NSLocalizedString("hiddenLayers.unlock.todayTime", value: "Hoy %1$@", comment: "Hidden layer unlock today with time"),
                date.formatted(date: .omitted, time: .shortened)
            )
        }

        if Calendar.current.isDateInTomorrow(date) {
            return String(
                format: NSLocalizedString("hiddenLayers.unlock.tomorrowTime", value: "Mañana %1$@", comment: "Hidden layer unlock tomorrow with time"),
                date.formatted(date: .omitted, time: .shortened)
            )
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func defaultScheduledDate() -> Date {
        tonightUnlockDate()
    }

    private func tonightUnlockDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let todayAtTen = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(60 * 60 * 2)
        if todayAtTen > now {
            return todayAtTen
        }
        return tomorrowUnlockDate()
    }

    private func tomorrowUnlockDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 22, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func applyPendingSchedule(to layerId: String) {
        guard let index = layers.firstIndex(where: { $0.id == layerId }) else { return }
        layers[index].unlockMode = .scheduled
        layers[index].unlockAt = pendingScheduleDate
        layers[index].authorTimezoneIdentifier = TimeZone.current.identifier
    }

    private func audioCanvasPreview(for layer: HiddenLayerDraft) -> some View {
        InteractiveAudioStickerView(
            audioURL: layer.localAudioURL?.absoluteString ?? "",
            duration: layer.duration ?? 15.0
        )
        .scaleEffect(max(0.7, min(2.4, layer.width / 0.18)))
    }

    private func textCanvasPreview(for layer: HiddenLayerDraft, size: CGSize) -> some View {
        let baseSize = hiddenLayerTextCardBaseSize(
            text: layer.text.isEmpty ? NSLocalizedString("hiddenLayers.text.placeholder", value: "Escribe el secreto...", comment: "Hidden layer text placeholder") : layer.text,
            textStyle: layer.textStyle
        )
        let scale = min(
            max(size.width / max(baseSize.width, 1), 0.72),
            max(size.height / max(baseSize.height, 1), 0.72)
        )

        return HiddenLayerTextCardPreview(
            text: layer.text.isEmpty ? NSLocalizedString("hiddenLayers.text.placeholder", value: "Escribe el secreto...", comment: "Hidden layer text placeholder") : layer.text,
            textStyle: layer.textStyle,
            presentationStyle: layer.presentationStyle,
            isPlaceholder: layer.text.isEmpty,
            colorScheme: colorScheme
        )
        .frame(width: baseSize.width, height: baseSize.height)
        .scaleEffect(scale)
    }

    private func resizeTextLayerToFitContent(at index: Int) {
        guard layers.indices.contains(index), layers[index].type == .text else { return }

        let measuredSize = hiddenLayerTextCardBaseSize(
            text: layers[index].text.isEmpty
                ? NSLocalizedString("hiddenLayers.text.placeholder", value: "Escribe el secreto...", comment: "Hidden layer text placeholder")
                : layers[index].text,
            textStyle: layers[index].textStyle
        )

        let referenceWidth: CGFloat = 220
        let widthRatio = min(0.62, max(0.16, 0.34 * (measuredSize.width / referenceWidth)))
        let heightRatio = min(0.32, max(0.10, widthRatio * HiddenLayerLayout.textAspectRatio))

        layers[index].width = Double(widthRatio)
        layers[index].height = Double(heightRatio)
    }

    private func startAudioPreview(for index: Int) {
        guard layers.indices.contains(index),
              let localAudioURL = layers[index].localAudioURL
        else { return }

        stopAudioPreview()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: localAudioURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPreviewPlaying = true
            audioPlaybackProgress = 0

            audioPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                guard let player = audioPlayer else { return }
                audioPlaybackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
                if !player.isPlaying {
                    stopAudioPreview()
                }
            }
        } catch {
            stopAudioPreview()
        }
    }

    private func stopAudioPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPreviewPlaying = false
        audioPlaybackProgress = 0
        audioPlaybackTimer?.invalidate()
        audioPlaybackTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func clearAudio(for index: Int) {
        guard layers.indices.contains(index) else { return }
        stopAudioPreview()
        if audioRecorder.isRecording {
            _ = audioRecorder.stopRecording()
        }
        layers[index].localAudioURL = nil
        layers[index].duration = nil
    }

    private func restartAudioRecording(for index: Int) {
        clearAudio(for: index)
    }

    private func waveformHeight(for step: Int) -> CGFloat {
        let pattern: [CGFloat] = [12, 20, 30, 18, 26, 15, 34, 18, 28, 14]
        return pattern[step % pattern.count]
    }

    private func stepProgress(_ step: Int) -> Double {
        Double(step + 1) / 28.0
    }

    private static func fixedAspectRect(aspectRatio: CGFloat, containerSize: CGSize) -> CGRect {
        HiddenLayerLayout.fixedAspectRect(aspectRatio: aspectRatio, containerSize: containerSize)
    }
}

private func hiddenLayerTextCardBaseSize(text: String, textStyle: HiddenLayerTextStyle) -> CGSize {
    let clampedText = text.isEmpty
        ? NSLocalizedString("hiddenLayers.text.placeholder", value: "Escribe el secreto...", comment: "Hidden layer text placeholder")
        : text

    let font = hiddenLayerTextUIFont(for: textStyle)
    let horizontalPadding: CGFloat = 32
    let verticalPadding: CGFloat = 24
    let minWidth: CGFloat = 132
    let maxWidth: CGFloat = 248
    let minHeight: CGFloat = 74

    let measuredWidth = ceil((clampedText as NSString).size(withAttributes: [.font: font]).width)
    let width = min(max(measuredWidth + horizontalPadding, minWidth), maxWidth)
    let height = max(minHeight, ceil(font.lineHeight + verticalPadding))

    return CGSize(width: width, height: height)
}

private func hiddenLayerTextUIFont(for textStyle: HiddenLayerTextStyle) -> UIFont {
    switch textStyle {
    case .clean:
        return .systemFont(ofSize: 17, weight: .semibold)
    case .serif:
        return .systemFont(ofSize: 18, weight: .semibold)
    case .handwritten:
        return UIFont(name: "Caveat-Medium", size: 23) ?? .systemFont(ofSize: 23, weight: .medium)
    case .mono:
        return .monospacedSystemFont(ofSize: 16, weight: .semibold)
    case .bubble:
        return .systemFont(ofSize: 18, weight: .black)
    case .editorial:
        return .systemFont(ofSize: 20, weight: .bold)
    }
}

private final class HiddenLayerAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedTime: Double = 0
    private var recorder: AVAudioRecorder?
    private var startDate: Date?
    private var timer: Timer?

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hidden_layer_audio_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.record(forDuration: 15)
        startDate = Date()
        isRecording = recorder?.isRecording == true
        elapsedTime = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.startDate else { return }
            self.elapsedTime = min(Date().timeIntervalSince(startDate), 15)
        }
    }

    func stopRecording() -> (url: URL, duration: Double)? {
        guard let recorder else { return nil }
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        isRecording = false
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let duration = min(Date().timeIntervalSince(startDate ?? Date()), 15)
        elapsedTime = duration
        return (url, duration)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
}

private struct HiddenLayerScheduleSheet: View {
    @Binding var date: Date
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(NSLocalizedString("hiddenLayers.unlock.sheet.title", value: "Programar secreto", comment: "Hidden layer schedule sheet title"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(NSLocalizedString("hiddenLayers.unlock.sheet.subtitle", value: "El contenido seguirá revelándose al tocarlo.", comment: "Hidden layer schedule sheet subtitle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            DatePicker(
                "",
                selection: $date,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack(spacing: 10) {
                Button(NSLocalizedString("common.cancel", value: "Cancelar", comment: "Cancel")) {
                    onCancel()
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule(), interactive: true)

                Button(NSLocalizedString("common.done", value: "Listo", comment: "Done")) {
                    onApply()
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlass(in: Capsule(), interactive: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .presentationBackground(.ultraThinMaterial)
    }
}

private struct HiddenLayerTextCardPreview: View {
    let text: String
    let textStyle: HiddenLayerTextStyle
    let presentationStyle: HiddenLayerPresentationStyle
    let isPlaceholder: Bool
    let colorScheme: ColorScheme

    var body: some View {
        textCardContent
            .opacity(isPlaceholder ? 0.7 : 1)
            .rotationEffect(presentationStyle == .paperNote ? .degrees(-1.2) : .degrees(0))
    }

    private var font: Font {
        switch textStyle {
        case .clean: return .system(size: 17, weight: .semibold, design: .rounded)
        case .serif: return .system(size: 18, weight: .semibold, design: .serif)
        case .handwritten: return .custom("Caveat-Medium", size: 23)
        case .mono: return .system(size: 16, weight: .semibold, design: .monospaced)
        case .bubble: return .system(size: 18, weight: .black, design: .rounded)
        case .editorial: return .system(size: 20, weight: .bold, design: .serif)
        }
    }

    private var foreground: Color {
        switch presentationStyle {
        case .paperNote, .markerLabel: return .black.opacity(0.84)
        case .minimalText: return colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.9)
        default: return colorScheme == .dark ? .white : .black.opacity(0.88)
        }
    }

    private var cornerRadius: CGFloat {
        switch presentationStyle {
        case .captionPill: return 999
        case .markerLabel: return 12
        default: return 20
        }
    }

    @ViewBuilder
    private var textCardContent: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if presentationStyle == .glassCard {
            Text(text)
                .font(font)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 74)
                .background(Color.clear)
                .liquidGlass(in: shape)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 74)
                .background(background)
                .clipShape(shape)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch presentationStyle {
        case .glassCard:
            Color.clear
        case .captionPill:
            Capsule()
                .fill(colorScheme == .dark ? Color.black.opacity(0.56) : Color.black.opacity(0.12))
        case .paperNote:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 1.0, green: 0.95, blue: 0.82))
        case .markerLabel:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.yellow.opacity(0.92))
        case .floatingQuote:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.black.opacity(0.66), .black.opacity(0.28)]
                            : [.white.opacity(0.94), .black.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .minimalText:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
        }
    }
}

private struct HiddenLayerPolaroidPreview: View {
    let image: UIImage
    let caption: String?
    let captionStyle: HiddenLayerTextStyle?
    let frameStyle: HiddenLayerImageFrameStyle
    let imageOffset: CGSize
    let imageScale: Double
    let showsAdjustingMask: Bool
    let canvasSize: CGSize

    var body: some View {
        let contentWidth = max(88, canvasSize.width)
        let contentHeight = max(96, canvasSize.height)
        let imageAreaHeight = contentHeight * 0.76
        let captionAreaHeight = max(24, contentHeight - imageAreaHeight)
        let inset = framePadding

        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(imageBackground)

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(imageScale)
                    .offset(imageOffset)

            }
            .frame(width: contentWidth, height: imageAreaHeight)
            .clipped()
            .padding(inset)
            .background(frameColor)

            ZStack {
                Rectangle()
                    .fill(frameColor)
                    .frame(width: contentWidth + (inset * 2), height: captionAreaHeight)

                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(captionFont)
                        .foregroundColor(captionColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 12)
                        .rotationEffect(captionRotation)
                        .offset(y: captionVerticalOffset)
                }
            }
        }
        .background(frameColor)
        .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
    }

    private var frameColor: Color {
        switch frameStyle {
        case .classic: return .white
        case .clean: return Color.white.opacity(0.94)
        case .vintage: return Color(red: 0.97, green: 0.92, blue: 0.82)
        }
    }

    private var imageBackground: Color {
        frameStyle == .vintage ? Color(red: 0.22, green: 0.18, blue: 0.14) : .black
    }

    private var framePadding: CGFloat {
        switch frameStyle {
        case .classic: return 10
        case .clean: return 8
        case .vintage: return 12
        }
    }

    private var outerCornerRadius: CGFloat {
        switch frameStyle {
        case .classic: return 0
        case .clean: return 18
        case .vintage: return 6
        }
    }

    private var captionFont: Font {
        switch captionStyle ?? .handwritten {
        case .clean: return .system(size: 14, weight: .semibold, design: .rounded)
        case .mono: return .system(size: 13, weight: .semibold, design: .monospaced)
        case .handwritten: return .custom("Caveat-Medium", size: 17)
        default: return .custom("Caveat-Medium", size: 17)
        }
    }

    private var captionColor: Color {
        frameStyle == .vintage ? .black.opacity(0.78) : .black.opacity(0.85)
    }

    private var captionRotation: Angle {
        (captionStyle ?? .handwritten) == .handwritten ? .degrees(-1) : .degrees(0)
    }

    private var captionVerticalOffset: CGFloat {
        frameStyle == .clean ? -1 : -2
    }
}

struct HiddenLayerRemotePolaroidPreview: View {
    let url: URL
    let caption: String?
    let captionStyle: HiddenLayerTextStyle?
    let frameStyle: HiddenLayerImageFrameStyle
    let imageOffset: CGSize
    let imageScale: Double
    let canvasSize: CGSize

    @State private var developingProgress: Double = 0

    var body: some View {
        let contentWidth = max(88, canvasSize.width)
        let contentHeight = max(96, canvasSize.height)
        let imageAreaHeight = contentHeight * 0.76
        let captionAreaHeight = max(24, contentHeight - imageAreaHeight)
        let inset = framePadding

        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(imageBackground)

                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(imageScale)
                    .offset(imageOffset)
                    .brightness(0.6 * (1.0 - developingProgress))
                    .contrast(0.4 + (0.6 * developingProgress))
                    .overlay {
                        // Micro-granulado mágico temporal
                        Canvas { context, size in
                            guard developingProgress < 1 else { return }
                            for _ in 0..<200 {
                                let rect = CGRect(
                                    x: CGFloat.random(in: 0...size.width),
                                    y: CGFloat.random(in: 0...size.height),
                                    width: 1.2, height: 1.2
                                )
                                context.fill(Path(rect), with: .color(.white.opacity(Double.random(in: 0.1...0.3))))
                            }
                        }
                        .opacity(1.0 - developingProgress)
                    }
            }
            .frame(width: contentWidth, height: imageAreaHeight)
            .clipped()
            .padding(inset)
            .background(frameColor)

            ZStack {
                Rectangle()
                    .fill(frameColor)
                    .frame(width: contentWidth + (inset * 2), height: captionAreaHeight)

                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(captionFont)
                        .foregroundColor(captionColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 12)
                        .rotationEffect(captionRotation)
                        .offset(y: captionVerticalOffset)
                        .opacity(developingProgress)
                }
            }
        }
        .background(frameColor)
        .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .onAppear {
            withAnimation(.easeIn(duration: 1.2).delay(0.2)) {
                developingProgress = 1.0
            }
        }
    }

    private var frameColor: Color {
        switch frameStyle {
        case .classic: return .white
        case .clean: return Color.white.opacity(0.94)
        case .vintage: return Color(red: 0.97, green: 0.92, blue: 0.82)
        }
    }

    private var imageBackground: Color {
        frameStyle == .vintage ? Color(red: 0.22, green: 0.18, blue: 0.14) : .black
    }

    private var framePadding: CGFloat {
        switch frameStyle {
        case .classic: return 10
        case .clean: return 8
        case .vintage: return 12
        }
    }

    private var outerCornerRadius: CGFloat {
        switch frameStyle {
        case .classic: return 0
        case .clean: return 18
        case .vintage: return 6
        }
    }

    private var captionFont: Font {
        switch captionStyle ?? .handwritten {
        case .clean: return .system(size: 14, weight: .semibold, design: .rounded)
        case .mono: return .system(size: 13, weight: .semibold, design: .monospaced)
        case .handwritten: return .custom("Caveat-Medium", size: 17)
        default: return .custom("Caveat-Medium", size: 17)
        }
    }

    private var captionColor: Color {
        frameStyle == .vintage ? .black.opacity(0.78) : .black.opacity(0.85)
    }

    private var captionRotation: Angle {
        (captionStyle ?? .handwritten) == .handwritten ? .degrees(-1) : .degrees(0)
    }

    private var captionVerticalOffset: CGFloat {
        frameStyle == .clean ? -1 : -2
    }
}

private extension HiddenLayerTextStyle {
    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .serif: return "Serif"
        case .handwritten: return "Hand"
        case .mono: return "Mono"
        case .bubble: return "Bubble"
        case .editorial: return "Edit"
        }
    }

    static var captionStyles: [HiddenLayerTextStyle] {
        [.clean, .handwritten, .mono]
    }
}

private extension HiddenLayerPresentationStyle {
    var displayName: String {
        switch self {
        case .glassCard: return "Glass"
        case .captionPill: return "Pill"
        case .paperNote: return "Paper"
        case .markerLabel: return "Marker"
        case .floatingQuote: return "Quote"
        case .minimalText: return "Minimal"
        }
    }
}

private extension HiddenLayerImageFrameStyle {
    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .clean: return "Clean"
        case .vintage: return "Vintage"
        }
    }
}

private extension Double {
    var formattedDuration: String {
        let seconds = max(0, Int(self.rounded()))
        return "0:\(String(format: "%02d", seconds))"
    }

    var formattedDetailedDuration: String {
        let seconds = Int(self)
        let tenths = Int((self - Double(seconds)) * 10)
        return String(format: "00:%02d.%d", seconds, max(0, tenths))
    }
}
