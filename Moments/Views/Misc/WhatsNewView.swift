import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearAnimation = false

    private var features2211: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("arrowshape.turn.up.left"),
                title: NSLocalizedString("whatsNew.replyInChat.title", comment: ""),
                description: NSLocalizedString("whatsNew.replyInChat.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("photo.on.rectangle.angled"),
                title: NSLocalizedString("whatsNew.quotePreviews.title", comment: ""),
                description: NSLocalizedString("whatsNew.quotePreviews.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("clock"),
                title: NSLocalizedString("whatsNew.chatTimestamps.title", comment: ""),
                description: NSLocalizedString("whatsNew.chatTimestamps.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("mic.fill"),
                title: NSLocalizedString("whatsNew.composerVoice.title", comment: ""),
                description: NSLocalizedString("whatsNew.composerVoice.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("tray.full"),
                title: NSLocalizedString("whatsNew.messageRequestThreads.title", comment: ""),
                description: NSLocalizedString("whatsNew.messageRequestThreads.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("square.and.arrow.up"),
                title: NSLocalizedString("whatsNew.shareInChat.title", comment: ""),
                description: NSLocalizedString("whatsNew.shareInChat.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("checkmark.circle"),
                title: NSLocalizedString("whatsNew.shareConfirmation.title", comment: ""),
                description: NSLocalizedString("whatsNew.shareConfirmation.description", comment: "")
            ),
        ]
    }

    private var sections: [WhatsNewSection] {
        [
            WhatsNewSection(
                title: NSLocalizedString("whatsNew.section2211.title", comment: ""),
                features: features2211
            ),
        ]
    }

    /// Aviso del desarrollador: no son funciones nuevas, así que va en su propio
    /// bloque separado de la lista para que se lea como lo que es.
    private var developerNote: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("iphone.and.arrow.forward"),
                title: NSLocalizedString("whatsNew.note.android.title", comment: ""),
                description: NSLocalizedString("whatsNew.note.android.description", comment: "")
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
                                            .padding(.top, sectionIndex == 0 ? 0 : 4)
                                    }

                                    ForEach(Array(section.features.enumerated()), id: \.offset) { featureIndex, feature in
                                        let rowIndex = sections.prefix(sectionIndex).reduce(0) { $0 + $1.features.count } + featureIndex
                                        WhatsNewFeatureRow(feature: feature, delay: Double(rowIndex) * 0.04)
                                    }
                                }
                            }
                        }

                        noteSection
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

    private var noteSection: some View {
        VStack(spacing: 12) {
            Divider()
                .opacity(0.4)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(Array(developerNote.enumerated()), id: \.offset) { index, item in
                    WhatsNewFeatureRow(
                        feature: item,
                        delay: Double(sections.reduce(0) { $0 + $1.features.count } + index) * 0.04
                    )
                }
            }

            Text(NSLocalizedString("whatsNew.note.closing", comment: ""))
                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
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
    case storyRing
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
            case .storyRing:
                StorySegmentedRing(
                    storyCount: 3,
                    hasStory: true,
                    hasUnseenStory: true,
                    storyViewedStatus: [false, false, false],
                    storyAudiences: [nil, nil, nil],
                    isOwnStory: false,
                    colorScheme: colorScheme,
                    ringSize: 26,
                    lineWidth: 2.4,
                    hapticsEnabled: false
                )
                .frame(width: 26, height: 26)
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

#Preview {
    WhatsNewView()
}
