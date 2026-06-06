import SwiftUI
import Kingfisher
import AVFoundation

// MARK: - Selection

struct ProfileGridMomentMenuSelection: Equatable {
    let moment: Moment
    let index: Int
}

// MARK: - Tap / long-press (UIKit — tap.require(toFail: longPress))

struct ProfileMomentThumbnailGestureOverlay: UIViewRepresentable {
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil
    let onPressingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onLongPress: onLongPress,
            onPressingChanged: onPressingChanged
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = GestureHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.coordinator = context.coordinator
        view.installGestures()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let host = uiView as? GestureHostView else { return }
        host.coordinator = context.coordinator
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onPressingChanged = onPressingChanged
    }

    final class GestureHostView: UIView {
        weak var coordinator: Coordinator?
        private var installed = false

        func installGestures() {
            guard !installed, let coordinator else { return }
            installed = true
            gestureRecognizers?.forEach { removeGestureRecognizer($0) }

            let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))

            if coordinator.onLongPress != nil {
                let longPress = UILongPressGestureRecognizer(
                    target: coordinator,
                    action: #selector(Coordinator.handleLongPress(_:))
                )
                longPress.minimumPressDuration = 0.42
                longPress.allowableMovement = 10
                tap.require(toFail: longPress)
                addGestureRecognizer(longPress)
            }

            addGestureRecognizer(tap)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installGestures()
        }
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onLongPress: (() -> Void)?
        var onPressingChanged: (Bool) -> Void
        private var didTriggerLongPress = false

        init(
            onTap: @escaping () -> Void,
            onLongPress: (() -> Void)?,
            onPressingChanged: @escaping (Bool) -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onPressingChanged = onPressingChanged
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onPressingChanged(true)
                guard !didTriggerLongPress else { return }
                didTriggerLongPress = true
                HapticManager.shared.mediumImpact()
                onLongPress?()
            case .ended, .cancelled, .failed:
                onPressingChanged(false)
                didTriggerLongPress = false
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onPressingChanged(false)
            onTap()
        }
    }
}

// MARK: - Hero sizing

private let profileGridHeroMaxWidth: CGFloat = 350

private func profileGridHeroMediaHeight(width: CGFloat, aspectRatio: String?) -> CGFloat {
    let ratio = profileGridParsedAspectRatio(aspectRatio)
    return min(width * 1.05, max(width * 0.72, width / max(ratio, 0.55)))
}

private func profileGridParsedAspectRatio(_ value: String?) -> CGFloat {
    guard let value,
          let separator = value.firstIndex(where: { $0 == ":" || $0 == "/" }) else {
        return 1
    }
    let lhs = Double(value[..<separator]) ?? 1
    let rhs = Double(value[value.index(after: separator)...]) ?? 1
    guard rhs > 0 else { return 1 }
    return CGFloat(lhs / rhs)
}

// MARK: - Hero card

private struct ProfileGridHeroCard: View {
    let moment: Moment
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    private var mediaHeight: CGFloat {
        profileGridHeroMediaHeight(width: width, aspectRatio: moment.aspectRatio)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AsyncProfileImageView(userId: moment.authorId)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(moment.username)
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(primaryTextColor)

                    if let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !location.isEmpty {
                        Text(location)
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            heroMedia
                .frame(width: width, height: mediaHeight)
                .clipped()
        }
        .frame(width: width)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var heroMedia: some View {
        if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
            if mediaItem.type == .video {
                if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty, let url = imageURL(thumbnailUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else if let thumbnail = videoThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    videoPlaceholder
                        .onAppear { loadVideoThumbnail(from: mediaItem.url) }
                }
            } else if let url = imageURL(mediaItem.url) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                textFallback
            }
        } else if let imagePath = moment.imagePath, let url = imageURL(imagePath) {
            KFImage(url)
                .resizable()
                .scaledToFill()
        } else {
            textFallback
        }
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.08)
            if isLoadingVideoThumbnail {
                ProgressView()
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var textFallback: some View {
        ZStack {
            Color.black.opacity(0.06)
            Text(moment.content)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(20)
                .lineLimit(6)
        }
    }

    private func imageURL(_ path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let base = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(base)\(encoded)?alt=media")
    }

    private func loadVideoThumbnail(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        isLoadingVideoThumbnail = true
        Task {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: width * 2, height: mediaHeight * 2)
            do {
                let (cgImage, _) = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600))
                await MainActor.run {
                    videoThumbnail = UIImage(cgImage: cgImage)
                    isLoadingVideoThumbnail = false
                }
            } catch {
                await MainActor.run { isLoadingVideoThumbnail = false }
            }
        }
    }
}

// MARK: - Menu row

private struct ProfileGridMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    private var textColor: Color {
        if isDestructive { return .red }
        return colorScheme == .dark ? .white : .black
    }

    var body: some View {
        MomentRowButton(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 15))

                Spacer(minLength: 12)
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Overlay

struct ProfileGridMomentMenuOverlay: View {
    @Binding var selection: ProfileGridMomentMenuSelection?
    @Binding var showPinConfirm: Bool
    @Binding var toastMessage: String?

    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let pinnedMomentsCount: Int
    let pinnedMomentsLimit: Int

    let onEdit: (Moment) -> Void
    let onDelete: (Moment) -> Void
    let onArchive: (Moment) -> Void
    let onPin: (Moment, Bool, Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let menuWidth: CGFloat = 240
    private let horizontalMargin: CGFloat = 16

    var body: some View {
        ZStack {
            if selection != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: containerSize.width, height: containerSize.height)
                    .onTapGesture { dismissMenu() }
            }

            if let selection {
                heroStack(for: selection)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(1)
            }

            if let toastMessage {
                VStack {
                    Spacer()
                    profileToast(message: toastMessage)
                        .padding(.bottom, safeAreaInsets.bottom + 96)
                }
                .frame(width: containerSize.width, height: containerSize.height)
                .zIndex(3)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selection?.moment.id)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showPinConfirm)
        .onChange(of: toastMessage) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if toastMessage == newValue {
                    toastMessage = nil
                }
            }
        }
    }

    @ViewBuilder
    private func heroStack(for selection: ProfileGridMomentMenuSelection) -> some View {
        let column = selection.index % 3
        let menuAlignment: HorizontalAlignment = column == 2 ? .leading : .trailing
        let cardWidth = min(containerSize.width - 32, profileGridHeroMaxWidth)

        let stack = VStack(alignment: menuAlignment, spacing: 14) {
            ProfileGridHeroCard(moment: selection.moment, width: cardWidth)

            if showPinConfirm {
                pinConfirmPanel
            } else {
                actionsMenu(for: selection.moment)
            }
        }
        .frame(width: cardWidth)

        let xCenter = containerSize.width / 2
        let transitionAnchor: UnitPoint = {
            switch column {
            case 0:  return .topLeading
            case 2:  return .topTrailing
            default: return .top
            }
        }()

        stack
            .transition(.scale(scale: 0.92, anchor: transitionAnchor).combined(with: .opacity))
            .position(
                x: xCenter,
                y: heroStackCenterY(cardWidth: cardWidth, moment: selection.moment)
            )
    }

    @ViewBuilder
    private func actionsMenu(for moment: Moment) -> some View {
        VStack(spacing: 0) {
            ProfileGridMenuRow(
                icon: moment.isPinned == true ? "pin.slash" : "pin",
                title: NSLocalizedString(
                    moment.isPinned == true ? "contextMenu.unpinMoment" : "contextMenu.pinMoment",
                    comment: "Pin or unpin moment"
                ),
                action: { handlePin(moment) }
            )

            ProfileGridMenuRow(
                icon: "archivebox",
                title: NSLocalizedString("contextMenu.archiveMoment", comment: "Archive moment"),
                action: {
                    dismissMenu()
                    onArchive(moment)
                }
            )

            ProfileGridMenuRow(
                icon: "pencil",
                title: NSLocalizedString("contextMenu.editMoment", comment: "Edit moment"),
                action: {
                    dismissMenu()
                    onEdit(moment)
                }
            )

            ProfileGridMenuRow(
                icon: "trash",
                title: NSLocalizedString("contextMenu.deleteMoment", comment: "Delete moment"),
                isDestructive: true,
                action: {
                    dismissMenu()
                    onDelete(moment)
                }
            )
        }
        .frame(width: menuWidth)
        .fixedSize(horizontal: true, vertical: true)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pinConfirmPanel: some View {
        let panelWidth = min(containerSize.width - horizontalMargin * 2, 320)

        return VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(NSLocalizedString("contextMenu.pinLimit.confirm.title", comment: "Pinned limit confirm title"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("contextMenu.pinLimit.confirm.message", comment: "Pinned limit confirm message"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.68))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            menuDivider

            MomentRowButton(action: {
                guard let moment = selection?.moment else { return }
                onPin(moment, true, true)
                toastMessage = NSLocalizedString("contextMenu.pinMoment.toast.pinned", comment: "Pinned toast")
                dismissMenu()
            }) {
                Text(NSLocalizedString("contextMenu.pinLimit.confirm", comment: "Confirm pin replacement"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(Color(hex: "007AFF"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }

            menuDivider

            MomentRowButton(action: {
                showPinConfirm = false
            }) {
                Text(NSLocalizedString("contextMenu.pinLimit.cancel", comment: "Cancel pin replacement"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: true, vertical: true)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func profileToast(message: String) -> some View {
        Text(message)
            .font(.custom("Poppins-SemiBold", size: 14))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
    }

    private var menuDivider: some View {
        Divider()
            .opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private func heroStackCenterY(cardWidth: CGFloat, moment: Moment) -> CGFloat {
        let mediaHeight = profileGridHeroMediaHeight(width: cardWidth, aspectRatio: moment.aspectRatio)
        let menuHeight: CGFloat = showPinConfirm ? 220 : CGFloat(46 * 4)
        let stackHeight = 46 + mediaHeight + 14 + menuHeight
        let minCenter = safeAreaInsets.top + 20 + (stackHeight / 2)
        let maxCenter = containerSize.height - safeAreaInsets.bottom - 20 - (stackHeight / 2)
        let preferred = containerSize.height / 2
        if minCenter > maxCenter {
            return containerSize.height / 2
        }
        return max(minCenter, min(preferred, maxCenter))
    }

    private func handlePin(_ moment: Moment) {
        if moment.isPinned == true {
            onPin(moment, false, false)
            toastMessage = NSLocalizedString("contextMenu.pinMoment.toast.unpinned", comment: "Unpinned toast")
            dismissMenu()
            return
        }

        if pinnedMomentsCount >= pinnedMomentsLimit {
            showPinConfirm = true
            return
        }

        onPin(moment, true, false)
        toastMessage = NSLocalizedString("contextMenu.pinMoment.toast.pinned", comment: "Pinned toast")
        dismissMenu()
    }

    private func dismissMenu() {
        selection = nil
        showPinConfirm = false
    }
}
