import SwiftUI

private let feedHighlightGradient = LinearGradient(
    colors: [Color(hex: "00A896").opacity(0.8), Color.purple.opacity(0.8)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct FloatingGlassFeedToggle: View {
    @Binding var selectedFeedType: FeedType
    @State private var isShowingBrand = !MotionPolicy.reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if isShowingBrand {
                Image("FeedWordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 96, height: 20)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.8))
                    .accessibilityHidden(true)
                    .transition(.feedBrandDeparture)
            } else {
                Menu {
                    ForEach(FeedType.allCases, id: \.self) { feedType in
                        Button {
                            guard selectedFeedType != feedType else { return }
                            selectedFeedType = feedType
                            HapticManager.shared.selection()
                        } label: {
                            if selectedFeedType == feedType {
                                Label(feedType.title, systemImage: "checkmark")
                            } else {
                                Text(feedType.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(selectedFeedType.title)
                            .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(feedHighlightGradient)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.feedOptionsArrival)
            }
        }
        .frame(minHeight: 44)
        .task {
            guard !MotionPolicy.reduceMotion else {
                isShowingBrand = false
                return
            }
            do {
                try await Task.sleep(for: .seconds(2.75))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(MotionPolicy.Spring.header) {
                isShowingBrand = false
            }
        }
    }
}

private struct FeedMorphModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat
    let scale: CGFloat
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale)
            .offset(y: verticalOffset)
    }
}

private extension AnyTransition {
    static let feedBrandDeparture = AnyTransition.modifier(
        active: FeedMorphModifier(opacity: 0, blurRadius: 8, scale: 0.9, verticalOffset: -5),
        identity: FeedMorphModifier(opacity: 1, blurRadius: 0, scale: 1, verticalOffset: 0)
    )

    static let feedOptionsArrival = AnyTransition.modifier(
        active: FeedMorphModifier(opacity: 0, blurRadius: 7, scale: 0.94, verticalOffset: 6),
        identity: FeedMorphModifier(opacity: 1, blurRadius: 0, scale: 1, verticalOffset: 0)
    )
}
