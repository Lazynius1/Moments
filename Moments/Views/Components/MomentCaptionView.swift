import SwiftUI
import Kingfisher

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

    private var maxCharacters: Int {
        switch style {
        case .feed: return 120
        case .reels: return 90
        case .detail: return 180
        }
    }

    private var previewContent: String {
        guard needsExpansion else { return cardContent }
        guard cardContent.count > maxCharacters else { return cardContent }
        return String(cardContent.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private var needsExpansion: Bool {
        cardContent.count > maxCharacters || trimmedContent.filter { $0 == "\n" }.count > 1
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
                onHashtagTap: onHashtagTap,
                onMentionTap: MomentMentionNavigation.openProfile(forUsername:)
            )
            .lineLimit(style == .detail ? 4 : 3)

            if needsExpansion {
                Button {
                    HapticManager.shared.lightImpact()
                    showFullCaption = true
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
                }
                .buttonStyle(.plain)
            }
        }
        // Sin esto el Text usa solo su ideal width y el VStack del post (alignment .center)
        // lo deja flotando con hueco grande a la izquierda — Android ya hace fillMaxWidth().
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FeedMomentCardLayout.captionHorizontalPadding)
        .padding(.top, style == .detail ? 0 : 2)
        .sheet(isPresented: $showFullCaption) {
            MomentCaptionReaderSheet(
                moment: moment,
                content: trimmedContent,
                colorScheme: colorScheme,
                onHashtagTap: onHashtagTap
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
        }
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

private struct MomentCaptionReaderSheet: View {
    let moment: Moment
    let content: String
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void

    private var baseTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.94) : .black.opacity(0.86)
    }

    private var hashtagTextColor: Color {
        colorScheme == .dark ? .white : Color(hex: "007AFF")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.22))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                MomentCaptionMediaPreview(moment: moment, colorScheme: colorScheme)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(NSLocalizedString("editMoment.description", comment: "Description"))
                            .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                            .foregroundStyle(baseTextColor)

                        Spacer()
                    }

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
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 34)
        }
    }
}

private struct MomentCaptionMediaPreview: View {
    let moment: Moment
    let colorScheme: ColorScheme

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
        ScreenshotProtectedView(isProtected: (moment.audience?.lowercased() ?? "") != "everyone") {
            ZStack(alignment: .bottomLeading) {
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

                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 8) {
                    if isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                    }

                    LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .momentsChromeGlass(in: Capsule(), interactive: false)
                .padding(12)
            }
            .frame(height: 230)
            .clipShape(FeedMomentCardLayout.continuousRoundedRect)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 18, y: 10)
        }
    }
}
