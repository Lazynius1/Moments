import SwiftUI
import Kingfisher

struct ProfileGridPreviewEditorView: View {
    let imageURL: URL
    let initialSettings: MomentGridPreviewSettings
    let onSave: (MomentGridPreviewSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var loadedImage: UIImage?
    @State private var isLoadingImage = true
    @State private var offset = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var fitMode: MomentGridPreviewFitMode = .fill
    @State private var background: MomentGridPreviewBackground = .black
    @State private var isDragging = false
    @State private var isZooming = false
    @GestureState private var gestureTranslation = CGSize.zero
    @State private var cropSide: CGFloat = UIScreen.main.bounds.width - 24

    private var liveOffset: CGSize {
        CGSize(
            width: offset.width + gestureTranslation.width,
            height: offset.height + gestureTranslation.height
        )
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()

            if isLoadingImage {
                ProgressView()
                    .tint(colorScheme == .dark ? .white : .black)
            } else if let image = loadedImage {
                GeometryReader { proxy in
                    let side = previewCropSide(in: proxy)

                    VStack(spacing: 10) {
                        headerView(cropSide: side)
                            .padding(.top, 4)

                        cropArea(with: image, cropSide: side)

                        Spacer(minLength: 0)

                        controlsView
                            .padding(.horizontal, 16)
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 10))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .onAppear {
                        cropSide = side
                    }
                    .onChange(of: proxy.size) { _, _ in
                        cropSide = previewCropSide(in: proxy)
                    }
                    .onChange(of: fitMode) { _, _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            applyInitialTransform(for: image.size, cropSide: side)
                        }
                    }
                }
            }
        }
        .onAppear {
            fitMode = initialSettings.fitMode
            background = initialSettings.background
            loadImage()
        }
    }

    private func previewCropSide(in proxy: GeometryProxy) -> CGFloat {
        let horizontalInset: CGFloat = 12
        let headerBlock: CGFloat = 48
        let controlsBlock: CGFloat = 104
        let verticalSpacing: CGFloat = 10
        let bottomInset = max(proxy.safeAreaInsets.bottom, 10)

        let widthLimit = proxy.size.width - horizontalInset * 2
        let heightLimit = proxy.size.height
            - proxy.safeAreaInsets.top
            - headerBlock
            - controlsBlock
            - verticalSpacing
            - bottomInset

        return max(220, min(widthLimit, heightLimit))
    }

    private func headerView(cropSide: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            Text(NSLocalizedString("profileGridPreview.title", comment: "Adjust preview title"))
                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()

            Button {
                HapticManager.shared.mediumImpact()
                onSave(currentSettings(cropSide: cropSide))
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var controlsView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                previewChipButton(
                    isEmphasized: true,
                    isEnabled: true,
                    action: {
                        fitMode = fitMode == .fill ? .fit : .fill
                    }
                ) {
                    GridPreviewModeChipIcon(fitMode: fitMode)
                        .frame(width: 18, height: 18)

                    modeChipTitle
                }

                previewChipButton(
                    isEmphasized: false,
                    isEnabled: fitMode == .fit,
                    action: {
                        background = background == .black ? .white : .black
                    }
                ) {
                    Circle()
                        .fill(background == .white ? Color.white : Color.black)
                        .overlay(
                            Circle()
                                .stroke(
                                    background == .white
                                        ? Color.white.opacity(0.28)
                                        : Color.white.opacity(0.18),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 14, height: 14)

                    Text(NSLocalizedString("profileGridPreview.background.label", comment: "Background label"))
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(NSLocalizedString("profileGridPreview.hint", comment: "Pinch and drag hint"))
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
                .opacity(fitMode == .fill ? 1 : 0)
                .animation(nil, value: fitMode)
        }
    }

    private var modeChipTitle: some View {
        ZStack {
            Text(NSLocalizedString("profileGridPreview.mode.fill", comment: "Fill mode"))
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .opacity(fitMode == .fill ? 1 : 0)

            Text(NSLocalizedString("profileGridPreview.mode.fit", comment: "Fit mode"))
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .opacity(fitMode == .fit ? 1 : 0)
        }
        .frame(minWidth: 72, alignment: .leading)
        .animation(nil, value: fitMode)
    }

    private func previewChipButton<Label: View>(
        isEmphasized: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let foreground = colorScheme == .dark ? Color.white : Color.black
        let foregroundOpacity: CGFloat = {
            if !isEnabled { return 0.24 }
            return isEmphasized ? 1 : 0.88
        }()
        let backgroundOpacity: CGFloat = {
            if !isEnabled {
                return colorScheme == .dark ? 0.04 : 0.02
            }
            if isEmphasized {
                return colorScheme == .dark ? 0.14 : 0.08
            }
            return colorScheme == .dark ? 0.11 : 0.06
        }()

        return Button {
            guard isEnabled else { return }
            HapticManager.shared.lightImpact()
            action()
        } label: {
            HStack(spacing: 8) {
                label()
            }
            .foregroundColor(foreground.opacity(foregroundOpacity))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        (colorScheme == .dark ? Color.white : Color.black)
                            .opacity(backgroundOpacity)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(nil, value: fitMode)
        .animation(nil, value: background)
    }

    @ViewBuilder
    private func cropArea(with image: UIImage, cropSide: CGFloat) -> some View {
        ZStack {
            Image(uiImage: image.withBlur(radius: 36))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: cropSide, height: cropSide)
                .clipped()
                .overlay((colorScheme == .dark ? Color.black : Color.white).opacity(0.12))

            if fitMode == .fit {
                (background == .black ? Color.black : Color.white)
                    .frame(width: cropSide, height: cropSide)
            }

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: fitMode == .fit ? .fit : .fill)
                .frame(
                    width: displaySize(for: image.size, cropSide: cropSide).width * scale,
                    height: displaySize(for: image.size, cropSide: cropSide).height * scale
                )
                .offset(liveOffset)
                .scaleEffect(isDragging || isZooming ? 1.005 : 1)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.9), value: isDragging)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.9), value: isZooming)

            squareMaskOverlay(cropSide: cropSide)

            if isDragging || isZooming {
                gridOverlay(cropSide: cropSide)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: cropSide, height: cropSide)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .contentShape(Rectangle())
        .gesture(editorGestures(imageSize: image.size, cropSide: cropSide))
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                resetTransform(for: image.size)
            }
        )
    }

    private func gridOverlay(cropSide: CGFloat) -> some View {
        ZStack {
            HStack(spacing: cropSide / 3 - 1) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 0.5, height: cropSide)
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 0.5, height: cropSide)
            }
            VStack(spacing: cropSide / 3 - 1) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: cropSide, height: 0.5)
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: cropSide, height: 0.5)
            }
        }
        .frame(width: cropSide, height: cropSide)
    }

    private func squareMaskOverlay(cropSide: CGFloat) -> some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(colorScheme == .dark ? 0.55 : 0.42)

            Rectangle()
                .frame(width: cropSide, height: cropSide)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func editorGestures(imageSize: CGSize, cropSide: CGFloat) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($gestureTranslation) { value, state, _ in
                    isDragging = true
                    let proposed = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                    let clamped = limitOffset(proposed, imageSize: imageSize, scale: scale, cropSide: cropSide)
                    state = CGSize(
                        width: clamped.width - offset.width,
                        height: clamped.height - offset.height
                    )
                }
                .onEnded { value in
                    isDragging = false
                    let velocity = value.velocity
                    let proposed = CGSize(
                        width: offset.width + value.translation.width + velocity.width * 0.04,
                        height: offset.height + value.translation.height + velocity.height * 0.04
                    )
                    withAnimation(.easeOut(duration: 0.22)) {
                        offset = limitOffset(proposed, imageSize: imageSize, scale: scale, cropSide: cropSide)
                    }
                    HapticManager.shared.lightImpact()
                },
            MagnificationGesture()
                .onChanged { value in
                    isZooming = true
                    let damped = pow(value, 0.9)
                    let minimum = minimumScale(for: imageSize)
                    let proposedScale = max(minimum, min(lastScale * damped, 4))
                    let scaleRatio = proposedScale / max(scale, 0.001)
                    scale = proposedScale
                    offset = limitOffset(
                        CGSize(width: offset.width * scaleRatio, height: offset.height * scaleRatio),
                        imageSize: imageSize,
                        scale: proposedScale,
                        cropSide: cropSide
                    )
                }
                .onEnded { _ in
                    isZooming = false
                    lastScale = scale
                    withAnimation(.easeOut(duration: 0.22)) {
                        offset = limitOffset(offset, imageSize: imageSize, scale: scale, cropSide: cropSide)
                    }
                    HapticManager.shared.lightImpact()
                }
        )
    }

    private func resetTransform(for imageSize: CGSize) {
        HapticManager.shared.mediumImpact()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            scale = 1
            lastScale = 1
            offset = .zero
        }
    }

    private func currentSettings(cropSide: CGFloat) -> MomentGridPreviewSettings {
        MomentGridPreviewSettings(
            scale: scale,
            offsetX: offset.width / cropSide,
            offsetY: offset.height / cropSide,
            fitMode: fitMode,
            background: background
        )
    }

    private func loadImage() {
        KingfisherManager.shared.retrieveImage(with: imageURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    loadedImage = value.image.normalized()
                    if let image = loadedImage {
                        applyInitialTransform(for: image.size, cropSide: cropSide)
                    }
                case .failure:
                    break
                }
                isLoadingImage = false
            }
        }
    }

    private func applyInitialTransform(for imageSize: CGSize, cropSide: CGFloat) {
        if initialSettings.isDefault {
            scale = 1
            lastScale = 1
            offset = .zero
            return
        }

        scale = max(minimumScale(for: imageSize), initialSettings.scale)
        lastScale = scale
        offset = limitOffset(
            CGSize(
                width: initialSettings.offsetX * cropSide,
                height: initialSettings.offsetY * cropSide
            ),
            imageSize: imageSize,
            scale: scale,
            cropSide: cropSide
        )
    }

    private func displaySize(for imageSize: CGSize, cropSide: CGFloat) -> CGSize {
        let widthScale = cropSide / imageSize.width
        let heightScale = cropSide / imageSize.height
        let appliedScale = fitMode == .fill ? max(widthScale, heightScale) : min(widthScale, heightScale)
        return CGSize(width: imageSize.width * appliedScale, height: imageSize.height * appliedScale)
    }

    private func minimumScale(for imageSize: CGSize) -> CGFloat {
        fitMode == .fill ? 1 : 0.5
    }

    private func limitOffset(
        _ proposedOffset: CGSize,
        imageSize: CGSize,
        scale: CGFloat,
        cropSide: CGFloat
    ) -> CGSize {
        let baseSize = displaySize(for: imageSize, cropSide: cropSide)
        let scaledWidth = baseSize.width * scale
        let scaledHeight = baseSize.height * scale

        let maxOffsetX = max(0, (scaledWidth - cropSide) / 2)
        let maxOffsetY = max(0, (scaledHeight - cropSide) / 2)

        return CGSize(
            width: max(-maxOffsetX, min(maxOffsetX, proposedOffset.width)),
            height: max(-maxOffsetY, min(maxOffsetY, proposedOffset.height))
        )
    }
}

// MARK: - Icono del botón modo (esquinas IG: 2 en Rellenar, 4 en Ajustar)

private struct GridPreviewModeChipIcon: View {
    let fitMode: MomentGridPreviewFitMode

    var body: some View {
        GridPreviewModeChipIconShape(fitMode: fitMode)
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .animation(nil, value: fitMode)
    }
}

private struct GridPreviewModeChipIconShape: Shape {
    let fitMode: MomentGridPreviewFitMode

    private let leg: CGFloat = 5.5

    func path(in rect: CGRect) -> Path {
        let corners: [UnitPoint] = {
            switch fitMode {
            case .fill:
                return [.topTrailing, .bottomLeading]
            case .fit:
                return [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
            }
        }()

        var path = Path()

        for corner in corners {
            let origin = CGPoint(x: corner.x * rect.width, y: corner.y * rect.height)

            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: origin.x, y: origin.y + leg))
                path.addLine(to: origin)
                path.addLine(to: CGPoint(x: origin.x + leg, y: origin.y))
            case .topTrailing:
                path.move(to: CGPoint(x: origin.x - leg, y: origin.y))
                path.addLine(to: origin)
                path.addLine(to: CGPoint(x: origin.x, y: origin.y + leg))
            case .bottomLeading:
                path.move(to: CGPoint(x: origin.x, y: origin.y - leg))
                path.addLine(to: origin)
                path.addLine(to: CGPoint(x: origin.x + leg, y: origin.y))
            case .bottomTrailing:
                path.move(to: CGPoint(x: origin.x - leg, y: origin.y))
                path.addLine(to: origin)
                path.addLine(to: CGPoint(x: origin.x, y: origin.y - leg))
            default:
                break
            }
        }

        return path
    }
}
