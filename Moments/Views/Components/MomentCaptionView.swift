import SwiftUI
import Kingfisher

enum MomentCaptionPresentationStyle {
    case feed
    case reels
    case detail
}

struct MomentCaptionView: View {
    let moment: Moment
    let style: MomentCaptionPresentationStyle
    let colorScheme: ColorScheme
    let onHashtagTap: (String) -> Void

    @State private var showFullCaption = false

    private var trimmedContent: String {
        moment.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var maxCharacters: Int {
        switch style {
        case .feed: return 120
        case .reels: return 90
        case .detail: return 180
        }
    }

    private var previewContent: String {
        guard needsExpansion else { return trimmedContent }
        return String(trimmedContent.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private var needsExpansion: Bool {
        trimmedContent.count > maxCharacters || trimmedContent.filter { $0 == "\n" }.count > 1
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

    var body: some View {
        if !trimmedContent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MomentHashtagText(
                    content: previewContent,
                    textFont: .custom("Poppins-Regular", size: style == .detail ? 15 : 14),
                    hashtagFont: .custom("Poppins-SemiBold", size: style == .detail ? 15 : 14),
                    baseColor: baseTextColor,
                    hashtagColor: hashtagTextColor,
                    textAlignment: .leading,
                    shadowColor: .clear,
                    shadowRadius: 0,
                    shadowX: 0,
                    shadowY: 0,
                    onHashtagTap: onHashtagTap
                )
                .lineLimit(style == .detail ? 4 : 3)

                if needsExpansion {
                    Button {
                        HapticManager.shared.lightImpact()
                        showFullCaption = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(NSLocalizedString("feed.seeMore", comment: "See more"))
                                .font(.custom("Poppins-SemiBold", size: 12))

                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(secondaryTextColor)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .liquidGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, style == .detail ? 4 : 12)
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
                            .font(.custom("Poppins-SemiBold", size: 17))
                            .foregroundColor(baseTextColor)

                        Spacer()
                    }

                    MomentHashtagText(
                        content: content,
                        textFont: .custom("Poppins-Regular", size: 16),
                        hashtagFont: .custom("Poppins-SemiBold", size: 16),
                        baseColor: baseTextColor,
                        hashtagColor: hashtagTextColor,
                        textAlignment: .leading,
                        shadowColor: .clear,
                        shadowRadius: 0,
                        shadowX: 0,
                        shadowY: 0,
                        onHashtagTap: onHashtagTap
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
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .liquidGlass(in: Capsule(), interactive: false)
                .padding(12)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 18, y: 10)
        }
    }
}
