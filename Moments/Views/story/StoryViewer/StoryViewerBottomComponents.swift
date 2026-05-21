import SwiftUI

struct StoryReactionsStrip: View {
    let reactions: [String]
    let showReactions: Bool
    let onReaction: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text(NSLocalizedString("storyContextMenu.scrollReactions", comment: "Scroll for more reactions"))
                    .font(.custom("Poppins-Regular", size: 10))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(reactions, id: \.self) { reaction in
                        Button(action: {
                            onReaction(reaction)
                        }) {
                            Text(reaction)
                                .font(.system(size: 32))
                                .frame(width: 52, height: 52)
                                .background(Color.white.opacity(0.001))
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                        .scaleEffect(showReactions ? 1.0 : 0.5)
                        .animation(
                            .spring(response: 0.3)
                                .delay(Double(reactions.firstIndex(of: reaction) ?? 0) * 0.03),
                            value: showReactions
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .frame(height: 70)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

struct StoryNoInteractionsNotice: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.6))

            Text("stories.noInteractions")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color.white.opacity(0.001)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
    }
}

struct StoryNavigationTouchAreas: View {
    let screenSize: CGSize
    let shouldSuppressNavigationTap: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !shouldSuppressNavigationTap else { return }
                        onPrevious()
                    }

                Spacer()

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: geometry.size.width * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !shouldSuppressNavigationTap else { return }
                        onNext()
                    }
            }
            .frame(height: geometry.size.height * 0.5)
            .offset(y: 150)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}
