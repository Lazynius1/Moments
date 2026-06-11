import SwiftUI

private enum FeatureDiscoveryIcon {
    case echo
    case nova
    case system(String)
}

private struct FeatureDiscoveryPage: Identifiable {
    let id = UUID()
    let icon: FeatureDiscoveryIcon
    let titleKey: String
    let subtitleKey: String
}

struct FeatureDiscoveryView: View {
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var pageIndex = 0

    private let pages: [FeatureDiscoveryPage] = [
        FeatureDiscoveryPage(
            icon: .echo,
            titleKey: "featureDiscovery.echo.title",
            subtitleKey: "featureDiscovery.echo.subtitle"
        ),
        FeatureDiscoveryPage(
            icon: .nova,
            titleKey: "featureDiscovery.nova.title",
            subtitleKey: "featureDiscovery.nova.subtitle"
        ),
        FeatureDiscoveryPage(
            icon: .system("map.fill"),
            titleKey: "featureDiscovery.map.title",
            subtitleKey: "featureDiscovery.map.subtitle"
        )
    ]

    private let heroIconSize: CGFloat = 56

    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            adaptiveColors.surfaceBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(action: finish) {
                        Text("featureDiscovery.skip")
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(adaptiveColors.secondary)
                    }
                    .accessibilityLabel(Text("featureDiscovery.skip"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 20) {
                            pageIcon(for: page.icon)
                                .padding(.bottom, 8)
                                .accessibilityHidden(true)

                            Text(LocalizedStringKey(page.titleKey))
                                .font(.custom("Poppins-SemiBold", size: 26))
                                .foregroundColor(adaptiveColors.primary)
                                .multilineTextAlignment(.center)

                            Text(LocalizedStringKey(page.subtitleKey))
                                .font(.custom("Poppins-Regular", size: 16))
                                .foregroundColor(adaptiveColors.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(action: advance) {
                    Text(pageIndex == pages.count - 1 ? "featureDiscovery.continue" : "featureDiscovery.next")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(adaptiveColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel(
                    Text(pageIndex == pages.count - 1 ? "featureDiscovery.continue" : "featureDiscovery.next")
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private func pageIcon(for icon: FeatureDiscoveryIcon) -> some View {
        switch icon {
        case .echo:
            EchoesIconView(size: heroIconSize, gradient: EchoesIconView.echoesBrandGradient)
        case .nova:
            NovaBrandIcon(size: heroIconSize, color: adaptiveColors.primary)
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: heroIconSize, weight: .semibold))
                .foregroundStyle(adaptiveColors.accent)
        }
    }

    private func advance() {
        if pageIndex < pages.count - 1 {
            withAnimation { pageIndex += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        FeatureDiscoveryStore.markSeen()
        onFinish()
    }
}

#Preview("Feature Discovery — Light") {
    FeatureDiscoveryView(onFinish: {})
}

#Preview("Feature Discovery — Dark") {
    FeatureDiscoveryView(onFinish: {})
        .preferredColorScheme(.dark)
}
