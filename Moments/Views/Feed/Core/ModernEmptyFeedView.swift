import SwiftUI

struct ModernEmptyFeedView: View {
    let feedType: FeedType
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        primaryText.opacity(colorScheme == .dark ? 0.58 : 0.52)
    }

    var body: some View {
        VStack(spacing: 22) {
            iconView

            VStack(spacing: 8) {
                Text(emptyTitle)
                    .font(.system(size: legacyPoppinsSize(22), weight: .semibold))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)

                Text(emptyDescription)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    Text(primaryActionTitle)
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))

                    Image(systemName: primaryActionIcon)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(primaryText)
                .frame(height: 50)
                .padding(.horizontal, 22)
                .contentShape(Capsule())
            }
            .buttonStyle(.momentsPress)
            .background {
                Color.clear
                    .momentsChromeGlass(in: Capsule(), interactive: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .momentsEmptyStateAppear(appearedOffsetY: -28, initialOffsetY: -14)
    }

    private var iconView: some View {
        Image(systemName: feedType == .following ? "person.2" : "sparkles")
            .font(.system(size: 31, weight: .medium))
            .foregroundStyle(primaryText)
            .frame(width: 76, height: 76)
            .background {
                Color.clear
                    .momentsChromeGlass(in: Circle())
            }
    }

    private var emptyTitle: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.following.title", comment: "Empty following feed title")
        case .forYou:
            return NSLocalizedString("feed.empty.foryou.title", comment: "Empty for you feed title")
        }
    }

    private var emptyDescription: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.following.description", comment: "Empty following feed description")
        case .forYou:
            return NSLocalizedString("feed.empty.foryou.description", comment: "Empty for you feed description")
        }
    }

    private var primaryActionTitle: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.action.findPeople", comment: "Find people")
        case .forYou:
            return NSLocalizedString("feed.empty.action.explore", comment: "Explore")
        }
    }

    private var primaryActionIcon: String {
        switch feedType {
        case .following:
            return "magnifyingglass"
        case .forYou:
            return "arrow.right"
        }
    }

    private func primaryAction() {
        switch feedType {
        case .following:
            LegacyNavigationBridge.showExplore()
        case .forYou:
            LegacyNavigationBridge.showExplore()
        }
    }
}

#Preview("Following") {
    ModernEmptyFeedView(feedType: .following)
}

#Preview("For You") {
    ModernEmptyFeedView(feedType: .forYou)
}

#Preview("Dark Mode") {
    ModernEmptyFeedView(feedType: .forYou)
        .preferredColorScheme(.dark)
}
