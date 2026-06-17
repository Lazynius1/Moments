import SwiftUI
import PhotosUI
import Photos
import AVFoundation

// MARK: - Layout

enum ChatInputBarLayout {
    static let bottomPaddingWithoutKeyboard: CGFloat = 8
    static let sheetAboveInputGap: CGFloat = 12
    static let maxMediaSelectionCount = 10

    static func attachmentSheetBottomInset(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + sheetAboveInputGap
    }
}

// MARK: - Device corner radius (App Store safe heuristic)

private enum ChatDeviceCornerRadius {
    static var display: CGFloat {
        let width = UIScreen.main.bounds.width
        if width >= 430 { return 62 }
        if width >= 428 { return 53.33 }
        if width >= 402 { return 62 }
        if width >= 393 { return 55 }
        if width >= 390 { return 47.33 }
        if width >= 375 { return 39 }
        return 0
    }

    static var sheet: CGFloat {
        let displayRadius = display
        return displayRadius > 0 ? displayRadius : ChatAttachmentSheetMetrics.cornerRadius
    }
}

// MARK: - Presentation

enum ChatAttachmentSheetKind: Identifiable, Equatable {
    case menu
    case photos
    case gif
    case sticker
    case location

    var id: Self { self }
}

enum ChatAttachmentSheetMetrics {
    static let horizontalInset: CGFloat = 10
    static let cornerRadius: CGFloat = 24
    static let menuPopoverTitleKeys = ["nova.attach.camera", "nova.attach.photos", "chat.attach.gif", "chat.attach.sticker", "chat.attach.location"]
    static let menuPopoverTextExtraMargin: CGFloat = 20
    static let menuPopoverMinWidth: CGFloat = 168
    /// Clearance between popover bottom edge and the top of the + button.
    static let menuPopoverGap: CGFloat = 16
    static let heightFraction: CGFloat = 0.58

    static func sheetHeight(containerHeight: CGFloat) -> CGFloat {
        containerHeight * heightFraction
    }
}

private enum ChatAttachmentMenuPopoverLayout {
    static let rowIconWidth: CGFloat = 40
    static let rowSpacing: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 12
    static let cardHorizontalPadding: CGFloat = 24
    static let cardVerticalPadding: CGFloat = 20
    static let rowVerticalPadding: CGFloat = 16
    static let rowCount: CGFloat = 5

    static var titleFont: UIFont {
        UIFont(name: "Poppins-Medium", size: 17)
            ?? .systemFont(ofSize: 17, weight: .medium)
    }

    static var estimatedWidth: CGFloat {
        max(
            measuredWidth(for: ChatAttachmentSheetMetrics.menuPopoverTitleKeys),
            ChatAttachmentSheetMetrics.menuPopoverMinWidth
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
            + ChatAttachmentSheetMetrics.menuPopoverTextExtraMargin
            + cardHorizontalPadding
    }
}

private struct ChatAttachmentMenuPopoverSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - Plus button

struct ChatPlusButtonAnchorKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct ChatAttachmentPlusButton: View {
    let isMenuOpen: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .momentsChromeGlass(in: Circle(), interactive: true)

                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(adaptiveColors.primary)
                    .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text("chat.input.attach.accessibility"))
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isMenuOpen)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChatPlusButtonAnchorKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
    }
}

// MARK: - Menú popover

struct ChatAttachmentMenuPopover: View {
    @Binding var isPresented: ChatAttachmentSheetKind?
    let anchorFrame: CGRect
    let onOpenCamera: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var popoverSize = CGSize(
        width: ChatAttachmentMenuPopoverLayout.estimatedWidth,
        height: ChatAttachmentMenuPopoverLayout.estimatedHeight
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

                if anchorFrame != .zero {
                    ChatAttachmentMenuPopoverCard(
                        isPresented: $isPresented,
                        onOpenCamera: {
                            dismissMenu()
                            onOpenCamera()
                        }
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ChatAttachmentMenuPopoverSizeKey.self,
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
            .onPreferenceChange(ChatAttachmentMenuPopoverSizeKey.self) { size in
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

        let halfWidth = popoverWidth / 2
        let margin: CGFloat = 16
        return min(
            max(localAnchor.midX, halfWidth + margin),
            containerWidth - halfWidth - margin
        )
    }

    /// Places the entire popover above the + button with a small gap.
    private func resolvedPopoverCenterY(localAnchor: CGRect, popoverHeight: CGFloat) -> CGFloat {
        guard anchorFrame != .zero else { return popoverHeight / 2 }

        let popoverBottom = localAnchor.minY - ChatAttachmentSheetMetrics.menuPopoverGap
        return popoverBottom - popoverHeight / 2
    }

    private func dismissMenu() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isPresented = nil
        }
    }
}

private struct ChatAttachmentMenuPopoverCard: View {
    @Binding var isPresented: ChatAttachmentSheetKind?
    let onOpenCamera: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatAttachmentSheetMetrics.cornerRadius, style: .continuous)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var iconCircleFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(
                systemImage: "camera",
                titleKey: "nova.attach.camera",
                action: onOpenCamera
            )
            menuRow(
                systemImage: "photo.on.rectangle",
                titleKey: "nova.attach.photos",
                action: { present(.photos) }
            )
            menuRow(
                systemImage: "rectangle.stack.badge.play",
                titleKey: "chat.attach.gif",
                action: { present(.gif) }
            )
            menuRow(
                assetImage: "MomentsStickerTool",
                titleKey: "chat.attach.sticker",
                action: { present(.sticker) }
            )
            menuRow(
                systemImage: "location",
                titleKey: "chat.attach.location",
                action: { present(.location) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .momentsChromeGlass(in: cardShape, interactive: true)
        .clipShape(cardShape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 24, x: 0, y: 12)
    }

    private func present(_ kind: ChatAttachmentSheetKind) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isPresented = kind
        }
    }

    private func menuRow(systemImage: String? = nil, assetImage: String? = nil, titleKey: String, action: @escaping () -> Void) -> some View {
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
                            .frame(width: 22, height: 22)
                            .foregroundColor(primaryTextColor)
                    } else {
                        Image(systemName: systemImage ?? "questionmark")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(primaryTextColor)
                    }
                }
                .frame(width: 40, height: 40, alignment: .center)

                Text(LocalizedStringKey(titleKey))
                    .font(.custom("Poppins-Medium", size: 17))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Media sheet overlay

struct ChatAttachmentMediaSheetOverlay: View {
    @Binding var activeSheet: ChatAttachmentSheetKind?
    let accentColor: Color
    let onPickerItems: ([PhotosPickerItem]) -> Void
    let onConfirmAssets: ([PHAsset]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if activeSheet == .photos {
            GeometryReader { proxy in
                let bottomPadding = ChatInputBarLayout.attachmentSheetBottomInset(
                    safeAreaBottom: proxy.safeAreaInsets.bottom
                )
                let sheetHeight = ChatAttachmentSheetMetrics.sheetHeight(
                    containerHeight: proxy.size.height
                )

                ZStack(alignment: .bottom) {
                    Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismiss()
                        }

                    ChatAttachmentSheetSurface(height: sheetHeight) {
                        ChatAttachmentMediaGridSheet(
                            accentColor: accentColor,
                            onPickerItems: { items in
                                onPickerItems(items)
                            },
                            onConfirmAssets: { assets in
                                onConfirmAssets(assets)
                            },
                            onBack: dismiss
                        )
                    }
                    .padding(.horizontal, ChatAttachmentSheetMetrics.horizontalInset)
                    .padding(.bottom, bottomPadding)
                    .offset(y: dragOffset)
                    .gesture(dismissDragGesture(sheetHeight: sheetHeight))
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: activeSheet)
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
}

struct ChatAttachmentSheetSurface<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ChatDeviceCornerRadius.sheet,
            style: .continuous
        )
    }

    var body: some View {
        content()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                ChatAttachmentSheetCanvasBackground()
                    .clipShape(sheetShape)
            }
            .clipShape(sheetShape)
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    }
}

struct ChatAttachmentSheetCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MomentsGlassButtonTint.canvas(for: colorScheme)
            .ignoresSafeArea()
    }
}

// MARK: - Media grid (multi-select)

struct ChatAttachmentMediaGridSheet: View {
    let accentColor: Color
    let onPickerItems: ([PhotosPickerItem]) -> Void
    let onConfirmAssets: ([PHAsset]) -> Void
    let onBack: () -> Void

    @State private var mediaAssets: [PHAsset] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedAssetIDs: [String] = []
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoading = true
    @State private var isConfirming = false
    @State private var nativePickerItems: [PhotosPickerItem] = []
    @State private var showNativePhotoPicker = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let imageManager = PHImageManager.default()
    private let thumbnailSize = CGSize(width: 300, height: 300)

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                    ChatAttachmentPermissionPrompt(messageKey: "nova.attach.photos.permission")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(mediaAssets, id: \.localIdentifier) { asset in
                                ChatAttachmentMediaCell(
                                    thumbnail: thumbnails[asset.localIdentifier],
                                    isVideo: asset.mediaType == .video,
                                    duration: asset.duration,
                                    selectionIndex: selectionIndex(for: asset.localIdentifier),
                                    onTap: {
                                        toggleSelection(for: asset)
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
                ChatAttachmentSheetCanvasBackground()
            }

            footerBar
        }
        .photosPicker(
            isPresented: $showNativePhotoPicker,
            selection: $nativePickerItems,
            maxSelectionCount: ChatInputBarLayout.maxMediaSelectionCount,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: nativePickerItems) { _, items in
            guard !items.isEmpty else { return }
            onPickerItems(items)
            nativePickerItems = []
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
        ChatAttachmentGlassStack(axis: .horizontal, spacing: 10) {
            ChatAttachmentRoundButton(
                systemImage: "chevron.left",
                accessibilityKey: "nova.attach.back.accessibility",
                action: dismissSheet
            )

            Spacer(minLength: 8)

            if selectedAssetIDs.isEmpty {
                ChatAttachmentPillButton(
                    titleKey: "nova.attach.allPhotos",
                    action: { showNativePhotoPicker = true }
                )
            } else {
                ChatAttachmentPillButton(
                    title: sendButtonTitle,
                    tint: accentColor,
                    disabled: isConfirming,
                    action: confirmSelection
                )
            }
        }
    }

    private var sendButtonTitle: String {
        let count = selectedAssetIDs.count
        if count == 1 {
            return NSLocalizedString("chat.attach.sendMedia.one", comment: "Send one media item")
        }
        return String(
            format: NSLocalizedString("chat.attach.sendMedia.many", comment: "Send N media items"),
            count
        )
    }

    private func selectionIndex(for assetID: String) -> Int? {
        guard let index = selectedAssetIDs.firstIndex(of: assetID) else { return nil }
        return index + 1
    }

    private func toggleSelection(for asset: PHAsset) {
        let id = asset.localIdentifier
        if let index = selectedAssetIDs.firstIndex(of: id) {
            selectedAssetIDs.remove(at: index)
        } else if selectedAssetIDs.count < ChatInputBarLayout.maxMediaSelectionCount {
            selectedAssetIDs.append(id)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func dismissSheet() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedAssetIDs = []
            onBack()
        }
    }

    private func confirmSelection() {
        guard !selectedAssetIDs.isEmpty, !isConfirming else { return }
        isConfirming = true

        let orderedAssets = selectedAssetIDs.compactMap { id in
            mediaAssets.first(where: { $0.localIdentifier == id })
        }

        onConfirmAssets(orderedAssets)
    }

    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        if authorizationStatus == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    authorizationStatus = status
                    loadMediaIfAllowed()
                }
            }
        } else {
            loadMediaIfAllowed()
        }
    }

    private func loadMediaIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            isLoading = false
            return
        }

        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 300
            options.predicate = NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue
            )

            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                mediaAssets = assets
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
}

// MARK: - Grid cell

private struct ChatAttachmentMediaCell: View {
    let thumbnail: UIImage?
    let isVideo: Bool
    let duration: TimeInterval
    let selectionIndex: Int?
    let onTap: () -> Void
    let onAppear: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                .overlay { ProgressView() }
                        }
                    }
                }
                .overlay {
                    if selectionIndex != nil {
                        Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isVideo {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(formatDuration(duration))
                                .font(.custom("Poppins-Medium", size: 11))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let selectionIndex {
                        Circle()
                            .fill(Color(hex: "007AFF"))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text("\(selectionIndex)")
                                    .font(.custom("Poppins-SemiBold", size: 12))
                                    .foregroundColor(.white)
                            }
                            .padding(8)
                    }
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear(perform: onAppear)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ChatAttachmentPermissionPrompt: View {
    let messageKey: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(LocalizedStringKey(messageKey))
            .font(.custom("Poppins-Regular", size: 15))
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer chrome

struct ChatAttachmentGlassStack<Content: View>: View {
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

struct ChatAttachmentRoundButton: View {
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
                .foregroundColor(StoryEditorChromeColor.icon(colorScheme))
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

struct ChatAttachmentPillButton: View {
    @Environment(\.colorScheme) private var colorScheme

    var titleKey: String? = nil
    var title: String? = nil
    var tint: Color? = nil
    var disabled: Bool = false
    let action: () -> Void

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var label: Text {
        if let title {
            return Text(title)
        }
        return Text(LocalizedStringKey(titleKey ?? ""))
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.custom(tint == nil ? "Poppins-Medium" : "Poppins-SemiBold", size: 14))
                .foregroundColor(tint == nil ? StoryEditorChromeColor.icon(colorScheme) : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .momentsChromeGlass(
                    in: Capsule(),
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
