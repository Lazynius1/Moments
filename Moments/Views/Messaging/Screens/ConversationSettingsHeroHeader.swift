import SwiftUI
import Kingfisher

/// Header colapsable de ConversationSettings.
/// Compacto = layout original (avatar 92). Grande = hero al tirar.
struct ConversationSettingsHeroHeader: View {
    @Binding var isLargeHeader: Bool
    @Binding var topInset: CGFloat

    let avatarURL: String?
    let displayName: String
    let presence: PresenceDisplay?
    let notificationsEnabled: Bool
    let onProfile: () -> Void
    let onSearch: () -> Void
    let onMuteToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private let compactAvatar: CGFloat = 92

    var body: some View {
        Group {
            if isLargeHeader {
                largeHeader
            } else {
                compactHeader
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: isLargeHeader)
    }

    // MARK: - Compacto (igual que antes del hero)

    private var compactHeader: some View {
        VStack(spacing: 14) {
            compactAvatarView

            Text(displayName)
                .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                .foregroundStyle(adaptiveColors.primary)
                .lineLimit(1)

            if let presence {
                presenceRow(
                    statusColor: presence.status.color,
                    statusText: presence.statusText,
                    supplemental: presence.supplementalText,
                    statusStyle: adaptiveColors.secondary,
                    tertiaryStyle: adaptiveColors.tertiary
                )
            }

            compactQuickActions
                .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var compactAvatarView: some View {
        if let avatarURL, let url = URL(string: avatarURL) {
            KFImage(url)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: compactAvatar, height: compactAvatar)
                .clipShape(Circle())
        } else {
            Color.clear
                .frame(width: compactAvatar, height: compactAvatar)
                .background(Color.clear.momentsChromeGlass(in: Circle()))
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(adaptiveColors.primary)
                )
        }
    }

    private var compactQuickActions: some View {
        HStack(spacing: 40) {
            compactActionButton(
                icon: "person",
                title: NSLocalizedString("conversationSettings.quickAction.profile", comment: ""),
                action: onProfile
            )
            compactActionButton(
                icon: "magnifyingglass",
                title: NSLocalizedString("conversationSettings.quickAction.search", comment: ""),
                action: onSearch
            )
            compactActionButton(
                icon: notificationsEnabled ? "bell" : "bell.slash",
                title: NSLocalizedString(
                    notificationsEnabled
                        ? "conversationSettings.quickAction.mute"
                        : "conversationSettings.quickAction.unmute",
                    comment: ""
                ),
                action: onMuteToggle
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func compactActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
            }
            .foregroundStyle(adaptiveColors.primary)
            .frame(width: 70)
        }
        .buttonStyle(.momentsPressSubtle)
    }

    // MARK: - Grande (hero)

    private var largeHeader: some View {
        VStack(spacing: 12) {
            Rectangle()
                .foregroundStyle(.clear)
                .frame(width: 100, height: 280)
                .clipShape(.circle)

            VStack(spacing: 16) {
                stickyIdentity
                largeQuickActions
                    .geometryGroup()
            }
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 15)
        .background(alignment: .top) {
            GeometryReader { proxy in
                let size = proxy.size
                let minY = proxy.frame(in: .global).minY
                let topOffset = minY

                largeAvatarHero
                    .frame(width: size.width, height: size.height + topOffset)
                    .clipped()
                    .offset(y: -topOffset)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var largeAvatarHero: some View {
        ZStack {
            if let avatarURL, let url = URL(string: avatarURL) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                adaptiveColors.surfaceBackground
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(height: 120)
                    .offset(y: -40)
            }

            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var stickyIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.system(size: legacyPoppinsSize(28), weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let presence {
                presenceRow(
                    statusColor: presence.status.color,
                    statusText: presence.statusText,
                    supplemental: presence.supplementalText,
                    statusStyle: Color.white.opacity(0.85),
                    tertiaryStyle: Color.white.opacity(0.65)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .visualEffect { content, proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let progress = max(min(minY / 50, 1), 0)
            return content
                .scaleEffect(0.78 + (0.22 * progress))
                .offset(y: minY < 0 ? -minY : 0)
        }
        .background { stickyChromeBackground }
        .zIndex(1000)
    }

    private var stickyChromeBackground: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let opacity: CGFloat = 1.0 - max(min(minY / 50, 1), 0)
            let tint = MomentsChromeGlass.canvasTint(for: colorScheme)

            ZStack {
                if #available(iOS 26.0, *) {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(
                            MomentsChromeGlass.chromeGlass(interactive: false, tint: tint),
                            in: .rect
                        )
                        .mask {
                            LinearGradient(
                                colors: [
                                    .black, .black, .black, .black,
                                    .black.opacity(0.5),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                } else {
                    Rectangle()
                        .fill(adaptiveColors.surfaceBackground)
                        .mask {
                            LinearGradient(
                                colors: [
                                    .black, .black, .black,
                                    .black.opacity(0.9),
                                    .black.opacity(0.4),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
            }
            .padding(-20)
            .padding(.bottom, -40)
            .padding(.top, -topInset)
            .offset(y: -minY)
            .opacity(opacity)
        }
        .allowsHitTesting(false)
    }

    private var largeQuickActions: some View {
        HStack(spacing: 8) {
            largeActionButton(
                icon: "person",
                title: NSLocalizedString("conversationSettings.quickAction.profile", comment: ""),
                action: onProfile
            )
            largeActionButton(
                icon: "magnifyingglass",
                title: NSLocalizedString("conversationSettings.quickAction.search", comment: ""),
                action: onSearch
            )
            largeActionButton(
                icon: notificationsEnabled ? "bell" : "bell.slash",
                title: NSLocalizedString(
                    notificationsEnabled
                        ? "conversationSettings.quickAction.mute"
                        : "conversationSettings.quickAction.unmute",
                    comment: ""
                ),
                action: onMuteToggle
            )
        }
    }

    private func largeActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 28)
                Text(title)
                    .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.clear)
                        .glassEffect(
                            MomentsChromeGlass.chromeGlass(
                                interactive: true,
                                tint: MomentsChromeGlass.canvasTint(for: colorScheme)
                            ),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.clear)
                        .momentsChromeGlass(
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous),
                            interactive: true,
                            style: .tinted
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPressSubtle)
    }

    // MARK: - Shared

    private func presenceRow(
        statusColor: Color,
        statusText: String,
        supplemental: String?,
        statusStyle: Color,
        tertiaryStyle: Color
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(statusStyle)

            if let supplemental {
                Text("• \(supplemental)")
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(tertiaryStyle)
            }
        }
    }
}
