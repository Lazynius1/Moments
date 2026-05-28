import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearAnimation = false

    private var features: [WhatsNewFeature] {
        [
            WhatsNewFeature(
                icon: .system("arrow.up.left.and.arrow.down.right"),
                title: NSLocalizedString("whatsNew.nova.title", comment: ""),
                description: NSLocalizedString("whatsNew.nova.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("swatchpalette.fill"),
                title: NSLocalizedString("whatsNew.account.title", comment: ""),
                description: NSLocalizedString("whatsNew.account.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .asset("MomentsStickerTool"),
                title: NSLocalizedString("whatsNew.glass.title", comment: ""),
                description: NSLocalizedString("whatsNew.glass.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("questionmark.bubble.fill"),
                title: NSLocalizedString("whatsNew.creator.title", comment: ""),
                description: NSLocalizedString("whatsNew.creator.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("eye.slash.fill"),
                title: NSLocalizedString("whatsNew.feed.title", comment: ""),
                description: NSLocalizedString("whatsNew.feed.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("play.square.stack.fill"),
                title: NSLocalizedString("whatsNew.social.title", comment: ""),
                description: NSLocalizedString("whatsNew.social.description", comment: "")
            ),
            WhatsNewFeature(
                icon: .system("checkmark.shield.fill"),
                title: NSLocalizedString("whatsNew.fixes.title", comment: ""),
                description: NSLocalizedString("whatsNew.fixes.description", comment: "")
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

                        VStack(spacing: 12) {
                            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                                WhatsNewFeatureRow(feature: feature, delay: Double(index) * 0.06)
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
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("whatsNew.subtitle", comment: ""))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.secondary)
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
                .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                Color.clear
                    .liquidGlass(in: Capsule(), interactive: true)
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
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.primary)

                Text(feature.description)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
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
                    .frame(width: 30, height: 30)
            }
        }
        .foregroundColor(.primary)
        .frame(width: 38, height: 38)
        .background {
            Color.clear
                .liquidGlass(in: Circle())
        }
    }
}

#Preview {
    WhatsNewView()
}
