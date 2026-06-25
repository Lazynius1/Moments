import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearAnimation = false

    private var features: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .attachment(.comments),
                title: NSLocalizedString("whatsNew.messaging.title", comment: ""),
                description: NSLocalizedString("whatsNew.messaging.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .attachment(.gif),
                title: NSLocalizedString("whatsNew.gif.title", comment: ""),
                description: NSLocalizedString("whatsNew.gif.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .asset("MomentsStickerTool"),
                title: NSLocalizedString("whatsNew.stickers.title", comment: ""),
                description: NSLocalizedString("whatsNew.stickers.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .attachment(.location),
                title: NSLocalizedString("whatsNew.location.title", comment: ""),
                description: NSLocalizedString("whatsNew.location.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .attachment(.liveLocation),
                title: NSLocalizedString("whatsNew.liveLocation.title", comment: ""),
                description: NSLocalizedString("whatsNew.liveLocation.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .attachment(.photos),
                title: NSLocalizedString("whatsNew.media.title", comment: ""),
                description: NSLocalizedString("whatsNew.media.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("heart.text.square.fill"),
                title: NSLocalizedString("whatsNew.reactions.title", comment: ""),
                description: NSLocalizedString("whatsNew.reactions.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("map.fill"),
                title: NSLocalizedString("whatsNew.map.title", comment: ""),
                description: NSLocalizedString("whatsNew.map.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .asset("CarouselPostIcon"),
                title: NSLocalizedString("whatsNew.feed.title", comment: ""),
                description: NSLocalizedString("whatsNew.feed.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .attachment(.bookmark),
                title: NSLocalizedString("whatsNew.profile.title", comment: ""),
                description: NSLocalizedString("whatsNew.profile.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .storyRing,
                title: NSLocalizedString("whatsNew.highlights.title", comment: ""),
                description: NSLocalizedString("whatsNew.highlights.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("sparkle.magnifyingglass"),
                title: NSLocalizedString("whatsNew.explore.title", comment: ""),
                description: NSLocalizedString("whatsNew.explore.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("person.crop.circle.badge.checkmark"),
                title: NSLocalizedString("whatsNew.onboarding.title", comment: ""),
                description: NSLocalizedString("whatsNew.onboarding.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("wand.and.stars"),
                title: NSLocalizedString("whatsNew.polish.title", comment: ""),
                description: NSLocalizedString("whatsNew.polish.description", comment: "")
            )
        ]
    }

    var body: some View {
        ScreenshotProtectedView(isProtected: true) {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header
                            .padding(.top, 22)

                        VStack(spacing: 10) {
                            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                                WhatsNewFeatureRow(feature: feature, delay: Double(index) * 0.04)
                            }
                        }

                        footerButton
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
            }
            .onAppear {
                withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) {
                    appearAnimation = true
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(colorScheme == .dark ? "LoginLogo" : "whatsnew")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("whatsNew.title", comment: ""))
                        .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("whatsNew.subtitle", comment: ""))
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .scaleEffect(appearAnimation ? 1 : 0.96)
        .opacity(appearAnimation ? 1 : 0)
    }

    private var footerButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                dismiss()
            }
        } label: {
            Text(NSLocalizedString("whatsNew.button", comment: ""))
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                Color.clear
                    .momentsChromeGlass(in: Capsule(), interactive: true)
            }
        }
        .buttonStyle(.plain)
        .offset(y: appearAnimation ? 0 : 18)
        .opacity(appearAnimation ? 1 : 0)
    }
}

private struct WhatsNewFeature {
    let icon: WhatsNewFeatureIcon
    let title: String
    let description: String
}

private enum WhatsNewFeatureIcon {
    case system(String)
    case asset(String)
    case attachment(AttachmentIcon)
    case storyRing
}

private struct WhatsNewFeatureRow: View {
    let feature: WhatsNewFeature
    let delay: Double
    @State private var appear = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(.primary)

                Text(feature.description)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .offset(y: appear ? 0 : 18)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) {
                appear = true
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        Group {
            switch feature.icon {
            case .system(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
            case .asset(let assetName):
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            case .attachment(let icon):
                AttachmentIconView(icon: icon, preset: .whatsNew, tintColor: .primary)
            case .storyRing:
                StorySegmentedRing(
                    storyCount: 3,
                    hasStory: true,
                    hasUnseenStory: true,
                    storyViewedStatus: [false, false, false],
                    storyAudiences: [nil, nil, nil],
                    isOwnStory: false,
                    colorScheme: .dark,
                    ringSize: 26,
                    lineWidth: 2.4,
                    hapticsEnabled: false
                )
                .frame(width: 26, height: 26)
            }
        }
        .foregroundColor(.primary)
        .frame(width: 38, height: 38)
        .background {
            Color.clear
                .momentsChromeGlass(in: Circle())
        }
    }
}

#Preview {
    WhatsNewView()
}
