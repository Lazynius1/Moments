import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct MediaEditingView: View {
    @Binding var selectedMediaItems: [CreatorMedia]
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.momentsToolbarVerticalEdge) private var toolbarVerticalEdge
    @Environment(\.momentsDivisionRegions) private var divisionRegions
    /// `onHingeChange` (iOS 27.1). En iPhone no hay bisagra y se queda en `.unknown`.
    @State private var hingePose: EditorHingePose = .unknown
    /// Margen del borde con la barra lateral. En el iPhone es 0.
    @State private var lateralSafeInset: CGFloat = 0

    private var canvasColor: Color {
        ProfileMomentZoomNavigation.canvasBackground(for: colorScheme)
    }
    private var ink: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    private var inkMuted: Color {
        ink.opacity(colorScheme == .dark ? 0.8 : 0.62)
    }

    @State private var currentMediaIndex = 0
    @State private var bottomTab: PhotoEditTab?
    @State private var selectedTool: PhotoEditTool?
    @State private var adjustAxis: PhotoAdjustAxis = .straighten
    @State private var sourceImages: [String: UIImage] = [:]
    @State private var sourceImmersive: [String: UIImage] = [:]
    @State private var photoEdits: [String: PhotoEdits] = [:]
    @State private var currentEdits = PhotoEdits()
    @State private var previewImage: UIImage?
    @State private var filterTask: Task<Void, Never>?
    @State private var blurStartRadius: Double = 0.28
    @State private var blurStartAngle: Double = 0
    @State private var showingCarouselAspectMenu = false
    @State private var carouselUsesSquare = false
    @State private var carouselPortraitAspect: CGFloat = MomentFeedCrop.portraitMax
    @State private var reframeDragStart: MediaItemFeedCrop?
    @State private var reframeZoomStart: MediaItemFeedCrop?
    @State private var mediaStageSize: CGSize = .zero
    /// Padding lateral del stage (single y carrusel), igual que el feed.
    private let editMediaHorizontalPadding: CGFloat = FeedMomentCardLayout.listHorizontalPadding

    var body: some View {
        VStack(spacing: 0) {
            header
            adaptiveEditorContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if !usesExpandedEditor, let tab = bottomTab, currentItemIsImage {
                editSheet(tab)
                    .padding(.leading, compactLeadingInset)
                    .padding(.trailing, compactTrailingInset)
            }
        }
        .modifier(EditorHingeObserver(pose: $hingePose))
        .toolbar(.hidden, for: .navigationBar)
        .background(canvasColor.ignoresSafeArea())
        .onAppear {
            captureSources()
            rememberCarouselAspect()
            loadEdits(for: currentMediaIndex)
        }
        .onChange(of: currentMediaIndex) { oldIndex, newIndex in
            persistEdits(at: oldIndex)
            bottomTab = nil
            loadEdits(for: newIndex)
        }
        .onChange(of: currentEdits) { _, _ in
            updatePreviewTask()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            guard let edge = toolbarVerticalEdge else { return 0 }
            return edge == .leading ? proxy.safeAreaInsets.leading : proxy.safeAreaInsets.trailing
        } action: { lateralSafeInset = $0 }
    }

    /// Compacto (iPhone y Duo cerrado): la pila de siempre.
    /// Ancho regular y bisagra no cerrada: `ArrangementView` pone la foto y las herramientas.
    private var usesExpandedEditor: Bool {
        guard horizontalSizeClass == .regular else { return false }
        return hingePose != .closed
    }

    /// Bisagra vertical: herramientas al lado. Si no, debajo. El sistema coloca el hueco.
    private var expandedToolsAreBesidePhoto: Bool {
        if let division = divisionRegions.first(where: { $0.width > 1 && $0.height > 1 }) {
            return division.height >= division.width
        }
        return toolbarVerticalEdge != nil
    }

    @ViewBuilder
    private var adaptiveEditorContent: some View {
        if usesExpandedEditor, #available(iOS 27.1, *) {
            ArrangementView {
                mediaStage
                    .padding(.leading, photoLeadingInset)
                    .padding(.trailing, photoTrailingInset)
            } secondary: {
                expandedToolPane
                    .padding(.leading, toolsLeadingInset)
                    .padding(.trailing, toolsTrailingInset)
            }
            .arrangementViewStyle(.split.axes(expandedToolsAreBesidePhoto ? .horizontal : .vertical))
        } else {
            VStack(spacing: 0) {
                mediaStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomChrome
                    .padding(.leading, compactLeadingInset)
                    .padding(.trailing, compactTrailingInset)
            }
        }
    }

    private var expandedToolPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isCarousel {
                    HStack(spacing: 6) {
                        ForEach(selectedMediaItems.indices, id: \.self) { index in
                            Circle()
                                .fill(index == currentMediaIndex ? ink : ink.opacity(0.22))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 6)
                }

                if currentItemIsImage {
                    expandedEditDismissBar

                    Text(NSLocalizedString("creator.tools.filter", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(inkMuted)
                        .padding(.horizontal, 16)
                    filterPanel

                    Text(NSLocalizedString("creator.tools.edit", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(inkMuted)
                        .padding(.horizontal, 16)
                    editPanel(wrapsTools: true)
                } else {
                    bottomChrome
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(canvasColor)
    }

    private var expandedEditDismissBar: some View {
        HStack {
            if currentEdits.canReset(tab: expandedResetTab, tool: selectedTool, axis: adjustAxis) {
                Button {
                    HapticManager.shared.lightImpact()
                    currentEdits.reset(tab: expandedResetTab, tool: selectedTool, axis: adjustAxis)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("savedMoments.filters.reset"))
            }
            Spacer()
            Button {
                HapticManager.shared.lightImpact()
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTool = nil
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.done"))
        }
        .padding(.horizontal, 12)
    }

    /// Con un ajuste elegido, el reset es de ese ajuste. Si no, del filtro.
    private var expandedResetTab: PhotoEditTab {
        selectedTool == nil ? .filter : .edit
    }

    private var header: some View {
        HStack {
            Button(action: { currentFlow = .mediaSelection }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundStyle(ink)
                    .padding(10)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }

            Spacer()

            Text(NSLocalizedString("creator.edit", comment: ""))
                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                .foregroundStyle(ink)

            Spacer()

            GlowSharePill(title: "creator.next", icon: "arrow.right", isLoading: false) {
                persistEdits(at: currentMediaIndex)
                bakeAllEdits()
                currentFlow = .captionAndDetails
            }
        }
        .padding()
        .background(canvasColor)
    }

    private var isCarousel: Bool { selectedMediaItems.count > 1 }

    private var carouselNonSquareKey: String {
        carouselPortraitAspect >= 1 ? "creator.carousel.landscape" : "creator.carousel.portrait"
    }

    private var currentItemIsImage: Bool {
        guard selectedMediaItems.indices.contains(currentMediaIndex) else { return false }
        return selectedMediaItems[currentMediaIndex].type == .image
    }

    @ViewBuilder
    private var mediaStage: some View {
        GeometryReader { geo in
            let lockSwipe = selectedTool == .blur
            Group {
                if lockSwipe, selectedMediaItems.indices.contains(currentMediaIndex) {
                    mediaPage(at: currentMediaIndex)
                } else {
                    TabView(selection: $currentMediaIndex) {
                        ForEach(selectedMediaItems.indices, id: \.self) { index in
                            mediaPage(at: index)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { mediaStageSize = geo.size }
            .onChange(of: geo.size) { _, size in mediaStageSize = size }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func mediaPage(at index: Int) -> some View {
        let item = selectedMediaItems[index]
        let shown: UIImage = {
            if index == currentMediaIndex, let preview = previewImage {
                return preview
            }
            if index == currentMediaIndex, let source = sourceImages[item.id] {
                return source
            }
            return item.image
        }()
        let cardAspect = item.feedCrop?.cardAspectValue ?? item.aspectRatio.value
        let reframeSource = sourceImmersive[item.id] ?? item.immersiveImage
        let canReframe = isCarousel
            && index == currentMediaIndex
            && selectedTool == nil
            && bottomTab == nil
            && item.feedCrop != nil
            && (item.type == .video || reframeSource != nil)

        canvasColor
            .overlay {
                Group {
                    if item.type == .video, let url = item.videoURL, index == currentMediaIndex {
                        NormalizedMediaCropContainer(feedCrop: item.feedCrop) {
                            StoryVideoPlayerView(
                                videoURL: url,
                                videoGravity: .resizeAspect,
                                isMuted: true
                            )
                        }
                    } else if canReframe, let original = reframeSource, let feedCrop = item.feedCrop {
                        NormalizedMediaCropContainer(feedCrop: feedCrop) {
                            Image(uiImage: original)
                                .resizable()
                                .scaledToFit()
                        }
                    } else {
                        Image(uiImage: shown)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .aspectRatio(cardAspect, contentMode: .fit)
                .clipShape(FeedMomentCardLayout.continuousRoundedRect)
                .padding(.horizontal, editMediaHorizontalPadding)
                .contentShape(Rectangle())
                .highPriorityGesture(reframeDragGesture(at: index, enabled: canReframe))
                .simultaneousGesture(reframeZoomGesture(at: index, enabled: canReframe))
                .overlay {
                    if index == currentMediaIndex, selectedTool == .adjust {
                        adjustGridOverlay
                            .padding(.horizontal, editMediaHorizontalPadding)
                    }
                    if index == currentMediaIndex, selectedTool == .blur {
                        blurInteractionLayer
                            .padding(.horizontal, editMediaHorizontalPadding)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isCarousel, index == currentMediaIndex {
                        Button(action: removeCurrentCarouselItem) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, editMediaHorizontalPadding + 10)
                        .padding(.top, 10)
                        .accessibilityLabel(Text("creator.carousel.remove"))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isCarousel, index == currentMediaIndex {
                        carouselAspectButton
                            .padding(.leading, editMediaHorizontalPadding + 10)
                            .padding(.bottom, 10)
                    }
                }
            }
    }

    private func reframeDragGesture(at index: Int, enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard enabled, selectedMediaItems.indices.contains(index) else { return }
                var item = selectedMediaItems[index]
                let start = reframeDragStart ?? item.feedCrop ?? MediaItemFeedCrop.fullBounds(
                    cardAspect: item.aspectRatio.displayName
                )
                if reframeDragStart == nil {
                    reframeDragStart = start
                }

                let cardWidth = max(mediaStageSize.width - editMediaHorizontalPadding * 2, 1)
                let cardHeight = cardWidth / max(item.aspectRatio.value, 0.01)
                // Delta normalizado: arrastrar media a la derecha = crop a la izquierda.
                let next = MomentFeedCrop.translated(
                    start,
                    byNormalized: CGSize(
                        width: -value.translation.width * start.width / cardWidth,
                        height: -value.translation.height * start.height / cardHeight
                    )
                )
                let original = sourceImmersive[item.id] ?? item.immersiveImage
                applyReframe(next, to: &item, original: original)
                selectedMediaItems[index] = item
            }
            .onEnded { _ in
                guard enabled else { return }
                finishReframe(at: index)
            }
    }

    private func reframeZoomGesture(at index: Int, enabled: Bool) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard enabled, selectedMediaItems.indices.contains(index) else { return }
                var item = selectedMediaItems[index]
                let start = reframeZoomStart ?? item.feedCrop ?? MediaItemFeedCrop.fullBounds(
                    cardAspect: item.aspectRatio.displayName
                )
                if reframeZoomStart == nil {
                    reframeZoomStart = start
                }
                let original = sourceImmersive[item.id] ?? item.immersiveImage
                let imageSize = original?.size
                    ?? CGSize(width: 1080, height: 1080 / max(item.aspectRatio.value, 0.01))
                let next = MomentFeedCrop.scaled(start, by: value, imageSize: imageSize)
                applyReframe(next, to: &item, original: original)
                selectedMediaItems[index] = item
            }
            .onEnded { _ in
                guard enabled else { return }
                finishReframe(at: index)
            }
    }

    private func finishReframe(at index: Int) {
        reframeDragStart = nil
        reframeZoomStart = nil
        guard selectedMediaItems.indices.contains(index) else { return }
        let item = selectedMediaItems[index]
        sourceImages[item.id] = item.image
        if item.type == .image {
            previewImage = nil
            updatePreviewTask()
        }
    }

    private func applyReframe(
        _ feedCrop: MediaItemFeedCrop,
        to item: inout CreatorMedia,
        original: UIImage?
    ) {
        item.feedCrop = feedCrop
        item.aspectRatio = CreatorMedia.AspectRatio.fromFeedPostRatio(feedCrop.cardAspectValue)
        item.recommendedAspectRatio = item.aspectRatio
        item.hasEdits = true
        if let original {
            item.image = original.cropped(to: feedCrop.rect(in: original.size))
        }
    }

    private var adjustGridOverlay: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    let y = geo.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.62), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private var blurInteractionLayer: some View {
        GeometryReader { geo in
            let center = CGPoint(
                x: currentEdits.tiltShiftCenter.x * geo.size.width,
                y: currentEdits.tiltShiftCenter.y * geo.size.height
            )
            let radius = currentEdits.tiltShiftRadius * min(geo.size.width, geo.size.height)
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentEdits.tiltShiftCenter = CGPoint(
                                x: min(max(value.location.x / geo.size.width, 0), 1),
                                y: min(max(value.location.y / geo.size.height, 0), 1)
                            )
                        }
                )
                .simultaneousGesture(blurMagnifyGesture(enabled: true))
                .simultaneousGesture(blurRotationGesture(enabled: currentEdits.tiltShiftMode == .linear))
                .overlay {
                    ZStack {
                        if currentEdits.tiltShiftMode == .linear {
                            RoundedRectangle(cornerRadius: 1)
                                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                                .frame(width: geo.size.width * 2.2, height: radius * 2)
                                .rotationEffect(.radians(currentEdits.tiltShiftAngle))
                                .position(center)
                                .shadow(color: .black.opacity(0.35), radius: 1)
                        } else {
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                                .frame(width: radius * 2, height: radius * 2)
                                .position(center)
                                .shadow(color: .black.opacity(0.35), radius: 1)
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                if isCarousel {
                    ForEach(selectedMediaItems.indices, id: \.self) { index in
                        Circle()
                            .fill(index == currentMediaIndex ? ink : ink.opacity(0.22))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 36) {
                editorMiniCard(
                    tab: .filter,
                    titleKey: "creator.tools.filter",
                    systemImage: "camera.filters"
                )
                editorMiniCard(
                    tab: .edit,
                    titleKey: "creator.tools.edit",
                    systemImage: "slider.horizontal.3"
                )
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(canvasColor)
    }

    private func editSheet(_ tab: PhotoEditTab) -> some View {
        VStack(spacing: 10) {
            HStack {
                if currentEdits.canReset(tab: tab, tool: selectedTool, axis: adjustAxis) {
                    Button {
                        HapticManager.shared.lightImpact()
                        currentEdits.reset(tab: tab, tool: selectedTool, axis: adjustAxis)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ink)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("savedMoments.filters.reset"))
                }
                Spacer()
                Button {
                    HapticManager.shared.lightImpact()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        bottomTab = nil
                        selectedTool = nil
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.done"))
            }
            .padding(.horizontal, 12)

            if tab == .filter {
                filterPanel
            } else {
                editPanel()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(canvasColor)
    }

    private func editorMiniCard(tab: PhotoEditTab, titleKey: String, systemImage: String) -> some View {
        let enabled = currentItemIsImage
        return Button {
            guard enabled else { return }
            HapticManager.shared.lightImpact()
            withAnimation(.easeInOut(duration: 0.18)) {
                bottomTab = tab
                if tab == .filter {
                    selectedTool = nil
                }
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 50, height: 50)
                    .background(ink.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(NSLocalizedString(titleKey, comment: ""))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(inkMuted)
            }
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.34)
        .disabled(!enabled)
    }

    private var filterPanel: some View {
        VStack(spacing: 12) {
            if currentEdits.filter != .normal {
                editorSlider(
                    value: $currentEdits.filterIntensity,
                    range: 0...1,
                    bipolar: false
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(FilterService.FilterType.allCases, id: \.self) { filter in
                        FilterOption(
                            image: sourceImageForCurrentItem() ?? selectedMediaItems[currentMediaIndex].image,
                            filter: filter,
                            isSelected: currentEdits.filter == filter
                        ) {
                            HapticManager.shared.lightImpact()
                            currentEdits.filter = filter
                            if filter == .normal {
                                currentEdits.filterIntensity = 1.0
                            }
                        }
                        .id("\(selectedMediaItems[currentMediaIndex].id)-\(filter.rawValue)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 140)
        }
    }

    /// En horizontal el borde exterior es el de la barra (reloj). El del pliegue no se rellena.
    private var photoLeadingInset: CGFloat {
        guard toolbarVerticalEdge == .leading else { return 0 }
        return lateralSafeInset
    }

    private var photoTrailingInset: CGFloat {
        guard !expandedToolsAreBesidePhoto, toolbarVerticalEdge == .trailing else { return 0 }
        return lateralSafeInset
    }

    private var toolsLeadingInset: CGFloat {
        guard !expandedToolsAreBesidePhoto, toolbarVerticalEdge == .leading else { return 0 }
        return lateralSafeInset
    }

    private var toolsTrailingInset: CGFloat {
        guard toolbarVerticalEdge == .trailing else { return 0 }
        return lateralSafeInset
    }

    /// Cerrado: la hoja y la barra inferior no deben entrar en la barra lateral.
    private var compactLeadingInset: CGFloat {
        guard toolbarVerticalEdge == .leading else { return 0 }
        return lateralSafeInset
    }

    private var compactTrailingInset: CGFloat {
        guard toolbarVerticalEdge == .trailing else { return 0 }
        return lateralSafeInset
    }

    private func editPanel(wrapsTools: Bool = false) -> some View {
        Group {
            if wrapsTools {
                VStack(spacing: 12) {
                    selectedToolControls
                        .frame(maxWidth: .infinity)
                    wrappedEditTools
                }
            } else {
                VStack(spacing: 12) {
                    selectedToolControls
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(PhotoEditTool.allCases) { tool in
                                editToolButton(tool)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedToolControls: some View {
        if selectedTool == .adjust {
            adjustChrome
        } else if let tool = selectedTool {
            VStack(spacing: 12) {
                if tool == .color {
                    colorToolChrome
                }
                if tool == .blur {
                    blurModeChrome
                }
                if let binding = sliderBinding(for: tool) {
                    editorSlider(
                        value: binding,
                        range: tool.usesZeroToHundred ? 0...1 : -1...1,
                        bipolar: !tool.usesZeroToHundred
                    )
                }
            }
        }
    }

    /// Cuatro columnas fijas. `LazyVGrid` adaptativo se descuadra al aparecer el slider.
    private var wrappedEditTools: some View {
        let tools = Array(PhotoEditTool.allCases)
        let columnCount = 4
        let rows = stride(from: 0, to: tools.count, by: columnCount).map { start in
            Array(tools[start..<min(start + columnCount, tools.count)])
        }
        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { tool in
                        editToolButton(tool)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count < columnCount {
                        ForEach(0..<(columnCount - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var adjustChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                ForEach(PhotoAdjustAxis.allCases) { axis in
                    Button {
                        HapticManager.shared.lightImpact()
                        adjustAxis = axis
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: axis.systemImage)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(adjustAxis == axis ? ink : inkMuted)
                            Text(NSLocalizedString(axis.titleKey, comment: ""))
                                .font(.system(size: 10, weight: adjustAxis == axis ? .semibold : .regular))
                                .foregroundStyle(adjustAxis == axis ? ink : inkMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            editorSlider(
                value: adjustAxisBinding,
                range: -1...1,
                bipolar: true
            )
        }
    }

    private var adjustAxisBinding: Binding<Double> {
        switch adjustAxis {
        case .straighten: return $currentEdits.straighten
        case .vertical: return $currentEdits.verticalPerspective
        case .horizontal: return $currentEdits.horizontalPerspective
        }
    }

    private var colorToolChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                tintTargetButton(.shadows)
                tintTargetButton(.highlights)
            }
            ViewThatFits(in: .horizontal) {
                tintColorRow
                ScrollView(.horizontal, showsIndicators: false) {
                    tintColorRow
                }
            }
        }
    }

    private var tintColorRow: some View {
        HStack(spacing: 10) {
            ForEach(PhotoTintColor.allCases) { tint in
                let selected = currentTint(for: currentEdits.tintTarget) == tint
                Button {
                    HapticManager.shared.lightImpact()
                    setCurrentTint(tint)
                } label: {
                    Circle()
                        .fill(Color(uiColor: tint.uiColor))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .stroke(ink, lineWidth: selected ? 2 : 0)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var blurModeChrome: some View {
        HStack(spacing: 24) {
            blurModeButton(.radial, titleKey: "creator.adjust.radial")
            blurModeButton(.linear, titleKey: "creator.adjust.linear")
        }
    }

    private func blurModeButton(_ mode: TiltShiftMode, titleKey: String) -> some View {
        Button {
            HapticManager.shared.lightImpact()
            currentEdits.tiltShiftMode = mode
        } label: {
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(.system(size: 13, weight: currentEdits.tiltShiftMode == mode ? .semibold : .regular))
                .foregroundStyle(currentEdits.tiltShiftMode == mode ? ink : inkMuted)
        }
        .buttonStyle(.plain)
    }

    private func tintTargetButton(_ target: PhotoTintTarget) -> some View {
        Button {
            currentEdits.tintTarget = target
        } label: {
            Text(NSLocalizedString(target == .shadows ? "creator.adjust.shadows" : "creator.adjust.highlights", comment: ""))
                .font(.system(size: 13, weight: currentEdits.tintTarget == target ? .semibold : .regular))
                .foregroundStyle(currentEdits.tintTarget == target ? ink : inkMuted)
        }
        .buttonStyle(.plain)
    }

    private func editToolButton(_ tool: PhotoEditTool) -> some View {
        let selected = selectedTool == tool
        return Button {
            HapticManager.shared.lightImpact()
            if selectedTool == tool {
                selectedTool = nil
                return
            }
            selectedTool = tool
            if tool == .adjust {
                adjustAxis = .straighten
            }
            if tool == .lux, currentEdits.lux == 0 {
                currentEdits.lux = 0.5
            }
            if tool == .blur, currentEdits.tiltShiftMode == nil {
                currentEdits.tiltShiftMode = .radial
            }
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .bottom) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selected ? canvasColor : ink)
                        .frame(width: 50, height: 50)
                        .background(selected ? ink : ink.opacity(colorScheme == .dark ? 0.12 : 0.06))
                        .clipShape(Circle())
                    if currentEdits.isApplied(tool), !selected {
                        Circle()
                            .fill(inkMuted)
                            .frame(width: 4, height: 4)
                            .offset(y: 6)
                    }
                }
                Text(NSLocalizedString(tool.titleKey, comment: ""))
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? ink : inkMuted)
                    .lineLimit(1)
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
    }

    private func editorSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        bipolar: Bool,
        horizontalPadding: CGFloat = 22
    ) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: range)
                .tint(ink)
            Text(sliderLabel(value.wrappedValue, bipolar: bipolar))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(ink)
                .frame(width: 36, alignment: .trailing)
                .onTapGesture {
                    value.wrappedValue = bipolar ? 0 : (range.lowerBound == 0 && range.upperBound == 1 ? 0 : 0)
                }
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func sliderLabel(_ value: Double, bipolar: Bool) -> String {
        if bipolar {
            return "\(Int((value * 100).rounded()))"
        }
        return "\(Int((value * 100).rounded()))"
    }

    private func sliderBinding(for tool: PhotoEditTool) -> Binding<Double>? {
        switch tool {
        case .adjust: return nil
        case .lux: return $currentEdits.lux
        case .brightness: return $currentEdits.brightness
        case .contrast: return $currentEdits.contrast
        case .texture: return $currentEdits.texture
        case .warmth: return $currentEdits.warmth
        case .saturation: return $currentEdits.saturation
        case .color:
            return currentEdits.tintTarget == .shadows
                ? $currentEdits.shadowTintAmount
                : $currentEdits.highlightTintAmount
        case .fade: return $currentEdits.fade
        case .highlights: return $currentEdits.highlights
        case .shadows: return $currentEdits.shadows
        case .vignette: return $currentEdits.vignette
        case .blur: return $currentEdits.tiltShiftAmount
        case .sharpen: return $currentEdits.sharpen
        }
    }

    private func currentTint(for target: PhotoTintTarget) -> PhotoTintColor? {
        target == .shadows ? currentEdits.shadowTint : currentEdits.highlightTint
    }

    private func setCurrentTint(_ tint: PhotoTintColor) {
        if currentEdits.tintTarget == .shadows {
            currentEdits.shadowTint = currentEdits.shadowTint == tint ? nil : tint
        } else {
            currentEdits.highlightTint = currentEdits.highlightTint == tint ? nil : tint
        }
    }

    private func blurMagnifyGesture(enabled: Bool) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard enabled else { return }
                currentEdits.tiltShiftRadius = min(max(blurStartRadius * value, 0.08), 0.62)
            }
            .onEnded { _ in
                blurStartRadius = currentEdits.tiltShiftRadius
            }
    }

    private func blurRotationGesture(enabled: Bool) -> some Gesture {
        RotationGesture()
            .onChanged { value in
                guard enabled else { return }
                currentEdits.tiltShiftAngle = blurStartAngle + Double(value.radians)
            }
            .onEnded { _ in
                blurStartAngle = currentEdits.tiltShiftAngle
            }
    }

    private var carouselAspectButton: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                showingCarouselAspectMenu.toggle()
            }
        } label: {
            GridPreviewModeChipIcon(fitMode: carouselUsesSquare ? .fill : .fit)
                .frame(width: 15, height: 15)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(carouselUsesSquare ? "creator.carousel.square" : carouselNonSquareKey))
        .overlay(alignment: .bottomLeading) {
            if showingCarouselAspectMenu {
                VStack(alignment: .leading, spacing: 2) {
                    carouselAspectMenuRow(
                        titleKey: carouselNonSquareKey,
                        systemImage: carouselPortraitAspect >= 1 ? "rectangle" : "rectangle.portrait",
                        selected: !carouselUsesSquare
                    ) {
                        applyCarouselAspect(square: false)
                        showingCarouselAspectMenu = false
                    }
                    carouselAspectMenuRow(
                        titleKey: "creator.carousel.square",
                        systemImage: "square",
                        selected: carouselUsesSquare
                    ) {
                        applyCarouselAspect(square: true)
                        showingCarouselAspectMenu = false
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .fixedSize()
                .momentsChromeGlass(in: shape, interactive: true, style: .tinted)
                .offset(y: -44)
                .transition(.opacity)
            }
        }
        .zIndex(2)
    }

    private func carouselAspectMenuRow(
        titleKey: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 22)
                Text(NSLocalizedString(titleKey, comment: ""))
                    .font(.system(size: 17, weight: .regular))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(ink)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func rememberCarouselAspect() {
        guard let first = selectedMediaItems.first else { return }
        let ratio = first.aspectRatio.value
        carouselUsesSquare = abs(ratio - 1) < 0.03
        if !carouselUsesSquare {
            carouselPortraitAspect = ratio
        }
    }

    private func applyCarouselAspect(square: Bool) {
        guard square != carouselUsesSquare else { return }
        carouselUsesSquare = square
        persistEdits(at: currentMediaIndex)
        let target = square ? MomentFeedCrop.squareAspect : carouselPortraitAspect
        let cardRatio = CreatorMedia.AspectRatio.fromFeedPostRatio(target)

        for index in selectedMediaItems.indices {
            var item = selectedMediaItems[index]
            let original = sourceImmersive[item.id] ?? item.immersiveImage ?? item.image
            let currentRect = item.feedCrop?.rect(in: original.size)
                ?? CGRect(origin: .zero, size: original.size)
            let currentAspect = currentRect.width / max(currentRect.height, 1)
            let rect = target < currentAspect
                ? MomentFeedCrop.expandRect(currentRect, toAspect: target, in: original.size)
                : MomentFeedCrop.exactCropRect(currentRect, toAspect: target, in: original.size)
            let cropped = original.cropped(to: rect)
            item.image = cropped
            item.aspectRatio = cardRatio
            item.recommendedAspectRatio = cardRatio
            item.feedCrop = MomentFeedCrop.normalizedFeedCrop(
                rect,
                in: original.size,
                cardAspect: target
            )
            selectedMediaItems[index] = item
            sourceImages[item.id] = cropped
        }

        previewImage = nil
        loadEdits(for: currentMediaIndex)
    }

    private func removeCurrentCarouselItem() {
        guard selectedMediaItems.count > 1,
              selectedMediaItems.indices.contains(currentMediaIndex) else { return }
        let removed = selectedMediaItems.remove(at: currentMediaIndex)
        photoEdits[removed.id] = nil
        sourceImages[removed.id] = nil
        sourceImmersive[removed.id] = nil
        currentMediaIndex = min(currentMediaIndex, selectedMediaItems.count - 1)
        loadEdits(for: currentMediaIndex)
        HapticManager.shared.lightImpact()
    }

    private func sourceImageForCurrentItem() -> UIImage? {
        guard selectedMediaItems.indices.contains(currentMediaIndex) else { return nil }
        let item = selectedMediaItems[currentMediaIndex]
        return sourceImages[item.id] ?? item.image
    }

    private func captureSources() {
        for item in selectedMediaItems where item.type == .image {
            if sourceImages[item.id] == nil {
                sourceImages[item.id] = item.image
            }
            if let immersive = item.immersiveImage, sourceImmersive[item.id] == nil {
                sourceImmersive[item.id] = immersive
            }
        }
    }

    private func persistEdits(at index: Int) {
        guard selectedMediaItems.indices.contains(index),
              selectedMediaItems[index].type == .image else { return }
        photoEdits[selectedMediaItems[index].id] = currentEdits
    }

    private func loadEdits(for index: Int) {
        selectedTool = nil
        guard selectedMediaItems.indices.contains(index),
              selectedMediaItems[index].type == .image else {
            currentEdits = PhotoEdits()
            previewImage = nil
            return
        }
        currentEdits = photoEdits[selectedMediaItems[index].id] ?? PhotoEdits()
        updatePreviewTask()
    }

    private func bakeAllEdits() {
        for index in selectedMediaItems.indices {
            let item = selectedMediaItems[index]
            guard item.type == .image, let source = sourceImages[item.id] else { continue }
            let edits = photoEdits[item.id] ?? PhotoEdits()
            guard !edits.isIdentity else { continue }
            selectedMediaItems[index].image = FilterService.shared.applyPhotoEdits(edits, to: source)
            selectedMediaItems[index].hasEdits = true
            if let immersive = sourceImmersive[item.id] {
                selectedMediaItems[index].immersiveImage = FilterService.shared.applyPhotoEdits(edits, to: immersive)
            }
        }
    }

    private func updatePreviewTask() {
        guard currentItemIsImage,
              let source = sourceImageForCurrentItem() else {
            previewImage = nil
            return
        }

        filterTask?.cancel()
        let edits = currentEdits
        if edits.isIdentity {
            previewImage = nil
            return
        }

        filterTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 30_000_000)
            if Task.isCancelled { return }
            let rendered = FilterService.shared.applyPhotoEdits(edits, to: source)
            if !Task.isCancelled {
                await MainActor.run {
                    self.previewImage = rendered
                }
            }
        }
    }
}

private enum EditorHingePose {
    case unknown
    case closed
    case partiallyOpen
    case fullyOpen
}

/// `onHingeChange` (SDK 27.1). Cerrada o sin bisagra: no cambia el editor compacto.
private struct EditorHingeObserver: ViewModifier {
    @Binding var pose: EditorHingePose

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                switch context.hinge?.status {
                case .partiallyOpen:
                    pose = .partiallyOpen
                case .fullyOpen:
                    pose = .fullyOpen
                case .closed:
                    pose = .closed
                default:
                    pose = .unknown
                }
            }
        } else {
            content
        }
    }
}
