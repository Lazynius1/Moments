import AVFoundation
import Photos
import SwiftUI
import UIKit

struct ContentTypeSelectionView: View {
    @Binding var contentType: CreatorView.ContentType
    @Binding var currentFlow: CreatorView.CreatorFlow
    @Binding var showCreatorView: Bool
    var animation: Namespace.ID
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedMode: CreatorView.ContentType = .moment
    @State private var recentImages: [UIImage] = []
    @State private var shutterScale: CGFloat = 1.0
    @State private var isBreathing: Bool = false
    @State private var hasCameraPermission: Bool = false
    @State private var dialTransientOffset: CGFloat = 0
    @State private var storyRingRotation: Double = 0
    @StateObject private var photosGate = PermissionPrimerGate(.photos)

    private let dialModes: [CreatorView.ContentType] = [.moment, .story]
    private let dialControlWidth: CGFloat = 170
    private let dialControlHeight: CGFloat = 44
    private let dialInnerPadding: CGFloat = 4
    private let dialPillWidth: CGFloat = 84
    private let dialPillHeight: CGFloat = 36

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topToolbar

                Spacer()

                shutterButton
                    .padding(.bottom, 28)

                dialSelector
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            checkCameraPermission()
            loadRecentPhotos()
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .permissionPrimerGate(photosGate)
    }

    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if selectedMode == .moment {
                if !recentImages.isEmpty {
                    ZStack {
                        ForEach(0..<recentImages.count, id: \.self) { index in
                            FloatingImageView(image: recentImages[index], index: index)
                        }
                    }
                    .ignoresSafeArea()
                    .blur(radius: 8)
                    .overlay(Color.black.opacity(0.15))
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .center)
                            .ignoresSafeArea()
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                } else {
                    Color.gray.opacity(0.1)
                        .ignoresSafeArea()
                }
            } else {
                if hasCameraPermission {
                    BackgroundCameraView()
                        .ignoresSafeArea()
                        .blur(radius: 10)
                        .overlay(Color.black.opacity(0.1))
                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                } else {
                    LinearGradient(
                        colors: [Color.black, Color.purple.opacity(0.2), Color.pink.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: selectedMode)
    }

    private struct FloatingImageView: View {
        let image: UIImage
        let index: Int

        @State private var offset: CGSize = .zero
        @State private var scale: CGFloat = 1.0
        @State private var rotation: Double = 0

        var body: some View {
            GeometryReader { geometry in
                let quadrantX = index % 2 == 0 ? geometry.size.width * 0.25 : geometry.size.width * 0.75
                let quadrantY = index < 2 ? geometry.size.height * 0.25 : geometry.size.height * 0.75

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.6)
                    .position(
                        x: quadrantX + CGFloat.random(in: -30...30),
                        y: quadrantY + CGFloat.random(in: -30...30)
                    )
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
                    .offset(offset)
                    .opacity(0.8)
                    .onAppear {
                        let duration = Double.random(in: 15...25)
                        let delay = Double.random(in: 0...5)

                        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)) {
                            offset = CGSize(
                                width: CGFloat.random(in: -100...100),
                                height: CGFloat.random(in: -100...100)
                            )
                            scale = CGFloat.random(in: 1.1...1.4)
                            rotation = Double.random(in: -10...10)
                        }
                    }
            }
        }
    }

    private var topToolbar: some View {
        HStack {
            Button(action: {
                withAnimation { showCreatorView = false }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
            .padding(.leading)

            Spacer()
        }
        .padding(.top, 10)
    }

    private var shutterButton: some View {
        Button(action: {
            confirmSelection()
        }) {
            ZStack {
                if selectedMode == .moment {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(-10))
                            .offset(x: -5, y: 0)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 60, height: 60)
                            .rotationEffect(.degrees(5))
                            .offset(x: 5, y: -2)

                        Group {
                            if let topImage = recentImages.first {
                                Image(uiImage: topImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 65, height: 65)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .frame(width: 65, height: 65)
                                    .overlay(
                                        Image(systemName: "photo.stack.fill")
                                            .foregroundStyle(.black)
                                    )
                            }
                        }
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .frame(width: 80, height: 80)
                    .matchedGeometryEffect(id: "momentSource", in: animation)
                } else {
                    storyShutterButton
                }
            }
        }
        .scaleEffect(shutterScale)
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.1, perform: {}, onPressingChanged: { pressing in
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                shutterScale = pressing ? 0.9 : 1.0
            }
        })
    }

    private var storyRingGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                .blue, .purple, .pink, .purple, .blue
            ]),
            center: .center
        )
    }

    private var storyShutterButton: some View {
        Circle()
            .fill(.clear)
            .frame(width: 88, height: 88)
            .background {
                StoryRingShape(lineWidth: 7)
                    .fill(storyRingGradient)
                    .frame(width: 81, height: 81)
                    .rotationEffect(.degrees(storyRingRotation))
            }
            .momentsChromeGlass(in: Circle(), interactive: true, style: .native)
            .contentShape(Circle())
            .scaleEffect(isBreathing ? 1.035 : 1.0)
            .onAppear {
                storyRingRotation = 0
                withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                    storyRingRotation = 360
                }
            }
    }

    private struct StoryRingShape: Shape {
        let lineWidth: CGFloat

        func path(in rect: CGRect) -> Path {
            Circle().path(in: rect).strokedPath(StrokeStyle(lineWidth: lineWidth))
        }
    }

    private var dialSelector: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: dialPillWidth, height: dialPillHeight)
                    .momentsChromeGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(0.26), radius: 7, x: 0, y: 2)
                    .offset(x: dialPillOffset)

                HStack(spacing: 0) {
                    ForEach(dialModes, id: \.self) { mode in
                        Text(titleFor(mode))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundStyle(dialLabelColor(for: mode))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, dialInnerPadding)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: dialVisualMode)

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    dialTransientOffset = constrainedDialTranslation(value.translation.width)
                                }
                            }
                            .onEnded { value in
                                settleDial(
                                    translation: value.translation.width,
                                    locationX: value.location.x,
                                    width: proxy.size.width
                                )
                            }
                    )
            }
        }
        .frame(width: dialControlWidth, height: dialControlHeight)
    }

    private var dialTravel: CGFloat {
        ((dialControlWidth - (dialInnerPadding * 2)) - dialPillWidth) / 2
    }

    private var dialBaseOffset: CGFloat {
        selectedMode == .moment ? -dialTravel : dialTravel
    }

    private var dialPillOffset: CGFloat {
        dialBaseOffset + dialTransientOffset
    }

    private var dialVisualMode: CreatorView.ContentType {
        dialPillOffset <= 0 ? .moment : .story
    }

    private func dialLabelColor(for mode: CreatorView.ContentType) -> Color {
        let isActive = dialVisualMode == mode
        return isActive ? .white.opacity(0.96) : .white.opacity(0.58)
    }

    private func constrainedDialTranslation(_ translation: CGFloat) -> CGFloat {
        let proposedOffset = dialBaseOffset + translation
        let clampedOffset = min(max(proposedOffset, -dialTravel), dialTravel)
        return clampedOffset - dialBaseOffset
    }

    private func settleDial(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let threshold = min(width * 0.16, dialTravel * 0.7)
        let targetMode: CreatorView.ContentType

        if translation < -threshold {
            targetMode = .moment
        } else if translation > threshold {
            targetMode = .story
        } else {
            targetMode = locationX < width / 2 ? .moment : .story
        }

        if targetMode != selectedMode {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedMode = targetMode
            dialTransientOffset = 0
        }
    }

    private func titleFor(_ mode: CreatorView.ContentType) -> String {
        switch mode {
        case .moment: return NSLocalizedString("creator.moment.title", comment: "Moment")
        case .story: return NSLocalizedString("creator.story.title", comment: "Story")
        }
    }

    private func confirmSelection() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation {
            contentType = selectedMode
            switch selectedMode {
            case .moment:
                currentFlow = .mediaSelection
            case .story:
                enterStoryCameraFlow()
            }
        }
    }

    private func enterStoryCameraFlow() {
        NotificationCenter.default.post(name: NSNotification.Name("StopBackgroundCameraSession"), object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            currentFlow = .storyCamera
        }
    }

    private func loadRecentPhotos() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            fetchRecentPhotos()
        case .notDetermined:
            photosGate.requestAccess { fetchRecentPhotos() }
        default:
            break
        }
    }

    private func fetchRecentPhotos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 4

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast

        var loadedImages: [UIImage] = []
        let processingGroup = DispatchGroup()

        assets.enumerateObjects { asset, _, _ in
            processingGroup.enter()
            manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { image, info in
                if let image = image {
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if !isDegraded {
                        loadedImages.append(image)
                    }
                }
                processingGroup.leave()
            }
        }

        processingGroup.notify(queue: .main) {
            withAnimation {
                self.recentImages = loadedImages
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            hasCameraPermission = false
        default:
            hasCameraPermission = false
        }
    }
}
