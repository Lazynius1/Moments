import SwiftUI

struct ModernEmptyFeedView: View {
    let feedType: FeedType
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearAnimation = false

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
                    .font(.custom("Poppins-SemiBold", size: 22))
                    .foregroundColor(primaryText)
                    .multilineTextAlignment(.center)

                Text(emptyDescription)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    Text(primaryActionTitle)
                        .font(.custom("Poppins-SemiBold", size: 15))

                    Image(systemName: primaryActionIcon)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(primaryText)
                .frame(height: 50)
                .padding(.horizontal, 22)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background {
                Color.clear
                    .liquidGlass(in: Capsule(), interactive: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .offset(y: appearAnimation ? -28 : -14)
        .opacity(appearAnimation ? 1 : 0)
        .animation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.08), value: appearAnimation)
        .onAppear {
            appearAnimation = true
        }
    }

    private var iconView: some View {
        Image(systemName: feedType == .following ? "person.2" : "sparkles")
            .font(.system(size: 31, weight: .medium))
            .foregroundColor(primaryText)
            .frame(width: 76, height: 76)
            .background {
                Color.clear
                    .liquidGlass(in: Circle())
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
