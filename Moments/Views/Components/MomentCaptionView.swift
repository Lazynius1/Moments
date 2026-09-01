import SwiftUI
import Kingfisher
import UIKit

enum MomentCaptionPresentationStyle {
    case feed
    case reels
    case detail
}

/// Normalización de caption para cards (feed/reels).
enum MomentCaptionText {
    /// Estilo IG: colapsa saltos a espacios para que hashtags fluyan en líneas suaves.
    static func flowing(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"\s*\n+\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MomentCaptionView: View {
    let moment: Moment
    let style: MomentCaptionPresentationStyle
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    var isReelsCaptionExpanded: Binding<Bool> = .constant(false)

    @State private var showFullCaption = false
    @State private var limitedCaptionHeight: CGFloat = 0
    @State private var fullCaptionHeight: CGFloat = 0

    private var trimmedContent: String {
        moment.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Feed/Reels: flujo continuo (IG). Detail: respeta saltos del autor.
    private var cardContent: String {
        switch style {
        case .feed, .reels:
            return MomentCaptionText.flowing(trimmedContent)
        case .detail:
            return trimmedContent
        }
    }

    private var previewContent: String {
        cardContent
    }

    private var needsExpansion: Bool {
        fullCaptionHeight > limitedCaptionHeight + 0.5
    }

    private var baseTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : .black.opacity(0.84)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58)
    }

    private var hashtagTextColor: Color {
        colorScheme == .dark ? .white : Color(hex: "007AFF")
    }

    private var mentionTextColor: Color {
        Color(hex: "007AFF")
    }

    @ViewBuilder
    var body: some View {
        if !trimmedContent.isEmpty {
            if style == .reels {
                ReelsCaptionBody(
                    content: cardContent,
                    needsMore: reelsNeedsMore(cardContent),
                    isExpanded: isReelsCaptionExpanded,
                    baseTextColor: baseTextColor,
                    hashtagTextColor: hashtagTextColor,
                    mentionTextColor: mentionTextColor,
                    onHashtagTap: onHashtagTap
                )
            } else {
                feedOrDetailCaption
            }
        }
    }

    private func reelsNeedsMore(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count > 2 { return true }
        if lines.count == 2 { return true }
        return text.count > 72
    }

    private var feedOrDetailCaption: some View {
        MomentCaptionContextTransition(isRequested: $showFullCaption) {
            VStack(alignment: .leading, spacing: 8) {
                MomentHashtagText(
                    content: previewContent,
                    textFont: .system(size: style == .detail ? 15 : 14),
                    hashtagFont: .system(size: style == .detail ? 15 : 14, weight: .semibold),
                    baseColor: baseTextColor,
                    hashtagColor: hashtagTextColor,
                    mentionColor: mentionTextColor,
                    textAlignment: .leading,
                    shadowColor: .clear,
                    shadowRadius: 0,
                    shadowX: 0,
                    shadowY: 0,
                    lineLimit: style == .detail ? 4 : 3,
                    onHashtagTap: onHashtagTap,
                    onMentionTap: MomentMentionNavigation.openProfile(forUsername:)
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    limitedCaptionHeight = height
                }
                .background(alignment: .topLeading) {
                    MomentHashtagText(
                        content: cardContent,
                        textFont: .system(size: style == .detail ? 15 : 14),
                        hashtagFont: .system(size: style == .detail ? 15 : 14, weight: .semibold),
                        baseColor: baseTextColor,
                        hashtagColor: hashtagTextColor,
                        mentionColor: mentionTextColor,
                        textAlignment: .leading,
                        shadowColor: .clear,
                        shadowRadius: 0,
                        shadowX: 0,
                        shadowY: 0,
                        onHashtagTap: { _ in },
                        onMentionTap: nil
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        fullCaptionHeight = height
                    }
                }
                .onChange(of: cardContent) { _, _ in
                    limitedCaptionHeight = 0
                    fullCaptionHeight = 0
                }

                if needsExpansion {
                    Button {
                        requestFullCaption()
                    } label: {
                        HStack(spacing: 5) {
                            Text(NSLocalizedString("feed.seeMore", comment: "See more"))
                                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))

                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(secondaryTextColor)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .momentsChromeGlass(in: Capsule(), interactive: true)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            requestFullCaption()
                        }
                    )
                }
            }
            // Sin esto el Text usa solo su ideal width y el VStack del post (alignment .center)
            // lo deja flotando con hueco grande a la izquierda — Android ya hace fillMaxWidth().
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FeedMomentCardLayout.captionHorizontalPadding)
            .padding(.top, style == .detail ? 0 : 2)
        } destination: { close, reportContentHeight in
            MomentCaptionReaderCard(
                moment: moment,
                content: trimmedContent,
                colorScheme: colorScheme,
                onHashtagTap: onHashtagTap,
                onClose: close,
                onContentHeightChange: reportContentHeight
            )
        }
    }

    private func requestFullCaption() {
        guard !showFullCaption else { return }
        HapticManager.shared.lightImpact()
        showFullCaption = true
    }
}

// MARK: - Reels (2 líneas colapsado, expandido con scroll cap ~10 líneas)

private struct ReelsCaptionBody: View {
    let content: String
    let needsMore: Bool
    @Binding var isExpanded: Bool
    let baseTextColor: Color
    let hashtagTextColor: Color
    let mentionTextColor: Color
    let onHashtagTap: (String) -> Void

    // ~10 lines of 14pt body text with ~22pt line spacing -> 220pt
    private let expandedMaxHeight: CGFloat = 220
    private let bodyFont = Font.system(size: 14)
    private let tagFont = Font.system(size: 14, weight: .semibold)
    private let boldFont = Font.system(size: 14, weight: .bold)
    private let springAnimation = Animation.spring(response: 0.38, dampingFraction: 0.85)

    @State private var contentHeight: CGFloat = 0

    private var truncatedCollapsedText: String {
        guard needsMore else { return content }
        
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        if lines.count >= 2 {
            let line1 = lines[0]
            let line2 = lines[1]
            
            if line1.count > 60 {
                return truncateString(line1, limit: 60)
            }
            
            let combined = line1 + "\n" + line2
            if combined.count > 75 {
                return line1 + "\n" + truncateString(line2, limit: max(15, 75 - line1.count))
            }
            return combined
        } else {
            return truncateString(content, limit: 75)
        }
    }
    
    private func truncateString(_ str: String, limit: Int) -> String {
        if str.count <= limit { return str }
        let prefix = str.prefix(limit)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isExpanded {
                // Estado expandido: ScrollView con cap de ~10 líneas, "ver menos" integrado inline al final
                ScrollView(.vertical, showsIndicators: false) {
                    MomentHashtagText(
                        content: content,
                        textFont: bodyFont,
                        hashtagFont: tagFont,
                        baseColor: baseTextColor,
                        hashtagColor: hashtagTextColor,
                        mentionColor: mentionTextColor,
                        textAlignment: .leading,
                        shadowColor: .clear,
                        shadowRadius: 0,
                        shadowX: 0,
                        shadowY: 0,
                        lineLimit: nil,
                        actionText: " " + NSLocalizedString("feed.seeLess", comment: "See less"),
                        actionURL: URL(string: "action://collapse"),
                        actionFont: boldFont,
                        actionColor: baseTextColor,
                        onHashtagTap: onHashtagTap,
                        onMentionTap: MomentMentionNavigation.openProfile(forUsername:),
                        onActionTap: { _ in collapse() }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: HeightPreferenceKey.self, value: geo.size.height)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                }
                .onPreferenceChange(HeightPreferenceKey.self) { height in
                    contentHeight = height
                }
                .frame(height: min(contentHeight, expandedMaxHeight))
                // Desactivar el bounce para no competir con el scroll del pager de vídeos
                .scrollBounceBehavior(.basedOnSize)

            } else {
                // Estado colapsado: "ver más" integrado inline en el texto
                MomentHashtagText(
                    content: truncatedCollapsedText,
                    textFont: bodyFont,
                    hashtagFont: tagFont,
                    baseColor: baseTextColor,
                    hashtagColor: hashtagTextColor,
                    mentionColor: mentionTextColor,
                    textAlignment: .leading,
                    shadowColor: .clear,
                    shadowRadius: 0,
                    shadowX: 0,
                    shadowY: 0,
                    lineLimit: 2,
                    actionText: needsMore ? " … " + NSLocalizedString("feed.seeMore", comment: "See more") : nil,
                    actionURL: needsMore ? URL(string: "action://expand") : nil,
                    actionFont: boldFont,
                    actionColor: baseTextColor,
                    onHashtagTap: onHashtagTap,
                    onMentionTap: MomentMentionNavigation.openProfile(forUsername:),
                    onActionTap: { _ in expand() }
                )
                .onTapGesture {
                    if needsMore {
                        expand()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(springAnimation, value: isExpanded)
    }

    private func expand() {
        HapticManager.shared.lightImpact()
        withAnimation(springAnimation) {
            isExpanded = true
        }
    }

    private func collapse() {
        HapticManager.shared.lightImpact()
        withAnimation(springAnimation) {
            isExpanded = false
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// El caption conserva su posición espacial, pero se materializa como una
/// superficie de lectura. A diferencia del QR/estadísticas, no hay dos caras
/// físicas y por eso el movimiento evita deliberadamente la rotación 3D.
private struct MomentCaptionContextTransition<Source: View, Destination: View>: View {
    @Binding var isRequested: Bool
    @ViewBuilder let source: () -> Source
    @ViewBuilder let destination: (@escaping () -> Void, @escaping (CGFloat) -> Void) -> Destination

    @State private var sourceFrame: CGRect = .zero
    @State private var presentationSourceFrame: CGRect = .zero
    @State private var sourceImage: UIImage?
    @State private var isPresented = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        source()
            .opacity(isPresented ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                sourceFrame = frame
                if isRequested, !isPresented {
                    present()
                }
            }
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                present()
            }
            .fullScreenCover(isPresented: $isPresented, onDismiss: reset) {
                MomentCaptionContextDestination(
                    sourceFrame: presentationSourceFrame,
                    sourceImage: sourceImage,
                    destination: destination,
                    onFinish: dismiss
                )
            }
    }

    private func present() {
        guard isRequested, !isPresented else { return }
        // El vídeo puede provocar una actualización de layout justo al tocar.
        // Conservamos la petición y la completamos desde onGeometryChange.
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }

        let renderer = ImageRenderer(
            content: source()
                .environment(\.colorScheme, colorScheme)
                .frame(width: sourceFrame.width, height: sourceFrame.height)
        )
        renderer.proposedSize = ProposedViewSize(sourceFrame.size)
        renderer.scale = displayScale
        sourceImage = renderer.uiImage
        presentationSourceFrame = sourceFrame

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = true
        }
    }

    private func dismiss() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = false
        }
    }

    private func reset() {
        sourceImage = nil
        presentationSourceFrame = .zero
        isRequested = false
    }
}

private struct MomentCaptionContextDestination<Destination: View>: View {
    let sourceFrame: CGRect
    let sourceImage: UIImage?
    @ViewBuilder let destination: (@escaping () -> Void, @escaping (CGFloat) -> Void) -> Destination
    let onFinish: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isClosing = false
    @State private var destinationContentHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let destinationFrame = finalFrame(in: proxy)
            let containerFrame = proxy.frame(in: .global)
            let localSourceFrame = sourceFrame.offsetBy(
                dx: -containerFrame.minX,
                dy: -containerFrame.minY
            )

            ZStack {
                Color.black
                    .opacity(0.34 * progress)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                if reduceMotion {
                    destinationCard(frame: destinationFrame)
                        .position(x: destinationFrame.midX, y: destinationFrame.midY)
                        .opacity(progress)
                } else {
                    morphingCard(from: localSourceFrame, to: destinationFrame)
                }
            }
        }
        .presentationBackground(.clear)
        .interactiveDismissDisabled()
        .onAppear {
            open()
        }
    }

    private func morphingCard(from sourceFrame: CGRect, to destinationFrame: CGRect) -> some View {
        let frame = interpolatedFrame(from: sourceFrame, to: destinationFrame, progress: progress)
        let cornerRadius = mix(16, 28, progress)
        let sourceOpacity = max(0, 1 - (progress / 0.44))
        let destinationOpacity = min(max((progress - 0.16) / 0.42, 0), 1)
        let surface = colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(surface)
                .frame(width: frame.width, height: frame.height)
                .shadow(color: .black.opacity(0.25 * progress), radius: 24 * progress, y: 11 * progress)
                .position(x: frame.midX, y: frame.midY)

            if let sourceImage {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .opacity(sourceOpacity)
                    .position(x: frame.midX, y: frame.midY)
            }

            destinationCard(frame: destinationFrame)
                .scaleEffect(
                    x: frame.width / max(destinationFrame.width, 1),
                    y: frame.height / max(destinationFrame.height, 1)
                )
                .opacity(destinationOpacity)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private func destinationCard(frame: CGRect) -> some View {
        destination(close, updateDestinationContentHeight)
            .frame(width: frame.width, height: frame.height)
            .background(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func finalFrame(in proxy: GeometryProxy) -> CGRect {
        let horizontalInset: CGFloat = 12
        let topInset = max(proxy.safeAreaInsets.top + 10, 16)
        let bottomInset = max(proxy.safeAreaInsets.bottom + 10, 16)
        let availableHeight = max(proxy.size.height - topInset - bottomInset, 1)
        let maximumHeight = min(560, availableHeight * 0.50)
        let measuredHeight = destinationContentHeight > 0 ? destinationContentHeight : 260
        let height = min(max(measuredHeight, 220), maximumHeight)

        return CGRect(
            x: horizontalInset,
            y: topInset + ((availableHeight - height) / 2),
            width: max(proxy.size.width - (horizontalInset * 2), 1),
            height: height
        )
    }

    private func open() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.42, extraBounce: 0)) {
            progress = 1
        }
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(
            reduceMotion ? .easeIn(duration: 0.16) : .smooth(duration: 0.38, extraBounce: 0),
            completionCriteria: .logicallyComplete
        ) {
            progress = 0
        } completion: {
            onFinish()
        }
    }

    private func interpolatedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: mix(start.minX, end.minX, progress),
            y: mix(start.minY, end.minY, progress),
            width: mix(start.width, end.width, progress),
            height: mix(start.height, end.height, progress)
        )
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }

    private func updateDestinationContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0, abs(destinationContentHeight - height) > 0.5 else { return }
        destinationContentHeight = height
    }
}

private struct MomentCaptionReaderCard: View {
    let moment: Moment
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void
    let onClose: () -> Void
    let onContentHeightChange: (CGFloat) -> Void

    private var baseTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.86)
    }

    private var hashtagTextColor: Color {
        colorScheme == .dark ? .white : Color(hex: "007AFF")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                MomentCaptionReaderHeader(
                    moment: moment,
                    colorScheme: colorScheme,
                    onClose: onClose
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("editMoment.description", comment: "Description"))
                        .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                        .foregroundStyle(baseTextColor)

                    MomentHashtagText(
                        content: content,
                        textFont: .system(size: 16),
                        hashtagFont: .system(size: 16, weight: .semibold),
                        baseColor: baseTextColor,
                        hashtagColor: hashtagTextColor,
                        mentionColor: Color(hex: "007AFF"),
                        textAlignment: .leading,
                        shadowColor: .clear,
                        shadowRadius: 0,
                        shadowX: 0,
                        shadowY: 0,
                        onHashtagTap: onHashtagTap,
                        onMentionTap: MomentMentionNavigation.openProfile(forUsername:)
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 14)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                onContentHeightChange(height)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct MomentCaptionReaderHeader: View {
    let moment: Moment
    let colorScheme: ColorScheme
    let onClose: () -> Void

    private var mediaURL: String? {
        if let image = moment.previewImageURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !image.isEmpty {
            return image
        }
        if let thumbnail = moment.thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !thumbnail.isEmpty {
            return thumbnail
        }
        return nil
    }

    private var isVideo: Bool {
        moment.primaryVisibleMediaItem?.type == .video || moment.previewVideoURLString != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ScreenshotProtectedView(isProtected: (moment.audience?.lowercased() ?? "") != "everyone") {
                ZStack {
                    if let mediaURL, let url = URL(string: mediaURL) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.10), Color.white.opacity(0.04)]
                                : [Color.black.opacity(0.08), Color.black.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }

                    if isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 3)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }

            VStack(alignment: .leading) {
                LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.close"))
        }
        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.86))
    }
}
