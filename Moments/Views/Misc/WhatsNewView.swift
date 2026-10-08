import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearAnimation = false

    private var featuresDuo231: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("iphone.gen3"),
                title: NSLocalizedString("whatsNew.duoArrival231.title", comment: ""),
                description: NSLocalizedString("whatsNew.duoArrival231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("rectangle.split.2x1"),
                title: NSLocalizedString("whatsNew.duoFeed231.title", comment: ""),
                description: NSLocalizedString("whatsNew.duoFeed231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("bubble.left.and.bubble.right"),
                title: NSLocalizedString("whatsNew.duoChats231.title", comment: ""),
                description: NSLocalizedString("whatsNew.duoChats231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("photo.on.rectangle.angled"),
                title: NSLocalizedString("whatsNew.duoCreate231.title", comment: ""),
                description: NSLocalizedString("whatsNew.duoCreate231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("camera.viewfinder"),
                title: NSLocalizedString("whatsNew.duoViewfinder231.title", comment: ""),
                description: NSLocalizedString("whatsNew.duoViewfinder231.description", comment: "")
            ),
        ]
    }

    private var featuresChat231: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("paintpalette"),
                title: NSLocalizedString("whatsNew.chatStyle231.title", comment: ""),
                description: NSLocalizedString("whatsNew.chatStyle231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("arrowshape.turn.up.left"),
                title: NSLocalizedString("whatsNew.replies231.title", comment: ""),
                description: NSLocalizedString("whatsNew.replies231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("play.circle"),
                title: NSLocalizedString("whatsNew.viewOnce231.title", comment: ""),
                description: NSLocalizedString("whatsNew.viewOnce231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("antenna.radiowaves.left.and.right"),
                title: NSLocalizedString("whatsNew.reliable231.title", comment: ""),
                description: NSLocalizedString("whatsNew.reliable231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("lock.iphone"),
                title: NSLocalizedString("whatsNew.lockPreview231.title", comment: ""),
                description: NSLocalizedString("whatsNew.lockPreview231.description", comment: "")
            ),
        ]
    }

    private var featuresStories231: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("slider.horizontal.3"),
                title: NSLocalizedString("whatsNew.storyPublish231.title", comment: ""),
                description: NSLocalizedString("whatsNew.storyPublish231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("waveform"),
                title: NSLocalizedString("whatsNew.originalAudio231.title", comment: ""),
                description: NSLocalizedString("whatsNew.originalAudio231.description", comment: "")
            ),
        ]
    }

    private var featuresMore231: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("map"),
                title: NSLocalizedString("whatsNew.maps231.title", comment: ""),
                description: NSLocalizedString("whatsNew.maps231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("bell.badge"),
                title: NSLocalizedString("whatsNew.banner231.title", comment: ""),
                description: NSLocalizedString("whatsNew.banner231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("gearshape"),
                title: NSLocalizedString("whatsNew.settings231.title", comment: ""),
                description: NSLocalizedString("whatsNew.settings231.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("bolt"),
                title: NSLocalizedString("whatsNew.fluid231.title", comment: ""),
                description: NSLocalizedString("whatsNew.fluid231.description", comment: "")
            ),
        ]
    }

    private var sections: [WhatsNewSection] {
        [
            WhatsNewSection(
                title: NSLocalizedString("whatsNew.sectionDuo231", comment: ""),
                features: featuresDuo231
            ),
            WhatsNewSection(
                title: NSLocalizedString("whatsNew.sectionChat231", comment: ""),
                features: featuresChat231
            ),
            WhatsNewSection(
                title: NSLocalizedString("whatsNew.sectionStories231", comment: ""),
                features: featuresStories231
            ),
            WhatsNewSection(
                title: NSLocalizedString("whatsNew.sectionMore231", comment: ""),
                features: featuresMore231
            ),
        ]
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                        .padding(.top, 22)

                    VStack(spacing: 18) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                            VStack(alignment: .leading, spacing: 10) {
                                if !section.title.isEmpty {
                                    Text(section.title)
                                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .tracking(0.6)
                                        .padding(.horizontal, 4)
                                        .padding(.top, sectionIndex == 0 ? 0 : 8)
                                        .accessibilityAddTraits(.isHeader)
                                        .opacity(appearAnimation ? 1 : 0)
                                }

                                ForEach(Array(section.features.enumerated()), id: \.offset) { featureIndex, feature in
                                    let rowIndex = sections.prefix(sectionIndex).reduce(0) { $0 + $1.features.count } + featureIndex
                                    WhatsNewFeatureRow(feature: feature, delay: Double(rowIndex) * 0.04)
                                }
                            }
                        }
                    }

                    footerNote
                        .padding(.top, 10)

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
                        .foregroundStyle(.primary)

                    Text(NSLocalizedString("whatsNew.subtitle", comment: ""))
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(.secondary)
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

    private var footerNote: some View {
        Text(NSLocalizedString("whatsNew.note.closing", comment: ""))
            .font(.system(size: legacyPoppinsSize(14), weight: .medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }

    private var footerButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                dismiss()
            }
        } label: {
            Text(NSLocalizedString("whatsNew.button", comment: ""))
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
            .foregroundStyle(.primary)
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

private struct WhatsNewSection {
    let title: String
    let features: [WhatsNewFeature]
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
    case personalAndGroupStoryRings
}

private struct WhatsNewFeatureRow: View {
    let feature: WhatsNewFeature
    let delay: Double
    @Environment(\.colorScheme) private var colorScheme
    @State private var appear = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(.primary)

                Text(feature.description)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(.secondary)
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
            case .personalAndGroupStoryRings:
                WhatsNewDualStoryRingsIcon(colorScheme: colorScheme)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 38, height: 38)
        .background {
            Color.clear
                .momentsChromeGlass(in: Circle())
        }
    }
}

/// Anillo personal (atrás, 3 audiencias) + grupo delante (1 corte con shift), cutout `reversedMask`.
private struct WhatsNewDualStoryRingsIcon: View {
    let colorScheme: ColorScheme

    private let ringSize: CGFloat = 18
    private let lineWidth: CGFloat = 2.0
    private let overlap: CGFloat = 6.5

    /// Los 3 colores de audiencia: everyone / best friends / mutuals.
    private let demoAudiences: [String?] = [nil, "bestfriends", "mutuals"]

    var body: some View {
        HStack(spacing: -overlap) {
            personalRing
                .reversedMask(alignment: .center) {
                    Circle()
                        .frame(width: ringSize + 3, height: ringSize + 3)
                        .offset(x: ringSize - overlap)
                }
                .zIndex(0)

            groupRing
                .zIndex(1)
        }
        .frame(width: ringSize * 2 - overlap, height: ringSize)
    }

    private var personalRing: some View {
        StorySegmentedRing(
            storyCount: 3,
            hasStory: true,
            hasUnseenStory: true,
            storyViewedStatus: [false, false, false],
            storyAudiences: demoAudiences,
            isOwnStory: false,
            colorScheme: colorScheme,
            ringSize: ringSize,
            lineWidth: lineWidth,
            hapticsEnabled: false
        )
        .frame(width: ringSize, height: ringSize)
    }

    private var groupRing: some View {
        ZStack {
            // 1 corte: el anillo completo hace el shift de las 3 audiencias.
            StorySegmentedRing(
                storyCount: 1,
                hasStory: true,
                hasUnseenStory: true,
                storyViewedStatus: [false],
                storyAudiences: [nil],
                nestedStoryAudiences: [demoAudiences],
                isOwnStory: false,
                colorScheme: colorScheme,
                ringSize: ringSize,
                lineWidth: lineWidth,
                hapticsEnabled: false
            )
            .mask(StoryRingLayout.ringGapMask(avatarSize: ringSize - lineWidth * 2))

            GroupChatAvatar(name: "G", image: "", size: ringSize - lineWidth * 2 - 1)
        }
        .frame(width: ringSize, height: ringSize)
    }
}

#Preview {
    WhatsNewView()
}
