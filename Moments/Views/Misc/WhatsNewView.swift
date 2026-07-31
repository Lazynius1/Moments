import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearAnimation = false

    private var features: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("sparkles"),
                title: NSLocalizedString("whatsNew.glass.title", comment: ""),
                description: NSLocalizedString("whatsNew.glass.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("hand.raised.fill"),
                title: NSLocalizedString("whatsNew.permissions.title", comment: ""),
                description: NSLocalizedString("whatsNew.permissions.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("arrow.clockwise"),
                title: NSLocalizedString("whatsNew.refresh.title", comment: ""),
                description: NSLocalizedString("whatsNew.refresh.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("square.grid.2x2.fill"),
                title: NSLocalizedString("whatsNew.widget.title", comment: ""),
                description: NSLocalizedString("whatsNew.widget.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("camera.fill"),
                title: NSLocalizedString("whatsNew.camera.title", comment: ""),
                description: NSLocalizedString("whatsNew.camera.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("bubble.left.and.bubble.right.fill"),
                title: NSLocalizedString("whatsNew.composer.title", comment: ""),
                description: NSLocalizedString("whatsNew.composer.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("line.3.horizontal.decrease.circle.fill"),
                title: NSLocalizedString("whatsNew.activityFilters.title", comment: ""),
                description: NSLocalizedString("whatsNew.activityFilters.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("lock.fill"),
                title: NSLocalizedString("whatsNew.encryptionFix.title", comment: ""),
                description: NSLocalizedString("whatsNew.encryptionFix.description", comment: "")
            )
        ]
    }

    /// Aviso del desarrollador: no son funciones nuevas, así que va en su propio
    /// bloque separado de la lista para que se lea como lo que es.
    private var developerNote: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("pause.circle.fill"),
                title: NSLocalizedString("whatsNew.note.pause.title", comment: ""),
                description: NSLocalizedString("whatsNew.note.pause.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("books.vertical.fill"),
                title: NSLocalizedString("whatsNew.note.scale.title", comment: ""),
                description: NSLocalizedString("whatsNew.note.scale.description", comment: "")
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
                        delay: Double(features.count + index) * 0.04
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
                    colorScheme: .dark,
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
