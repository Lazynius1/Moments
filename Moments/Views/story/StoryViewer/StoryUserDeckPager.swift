import SwiftUI

// MARK: - Deck Pass (carrusel entre usuarios)

enum StoryDeckPageRole {
    case leading
    case center
    case trailing
}

/// Pager horizontal entre usuarios del story ring con preview, escala y blur (Deck Pass).
struct StoryUserDeckPager<Content: View>: View {
    let userIds: [String]
    @Binding var currentUserIndex: Int
    var onUserChanged: ((Int) -> Void)?
    @ViewBuilder let content: (String, StoryDeckPageRole, Bool) -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingDeck = false
    @Environment(\.colorScheme) private var colorScheme

    private let commitThreshold: CGFloat = 0.28
    private let flickVelocity: CGFloat = 420

    private var deckBackground: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let visibleIndices = visibleUserIndices()
            let stackOffset = stackBaseOffset(
                width: width,
                visibleIndices: visibleIndices
            )

            ZStack {
                deckBackground.ignoresSafeArea()

                HStack(spacing: 0) {
                    ForEach(visibleIndices, id: \.self) { index in
                        let userId = userIds[index]
                        let role = role(for: index)
                        let pageProgress = pageProgress(for: index, width: width)

                        content(userId, role, isDraggingDeck)
                            .id(userId)
                            .frame(width: width, height: geometry.size.height)
                            .allowsHitTesting(role == .center)
                            .zIndex(role == .center ? 1 : 0)
                            .modifier(DeckPassPageModifier(progress: pageProgress))
                    }
                }
                .offset(x: stackOffset + dragOffset)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(deckDragGesture(width: width))
        }
        .ignoresSafeArea()
    }

    // MARK: - Layout

    private func visibleUserIndices() -> [Int] {
        guard !userIds.isEmpty else { return [] }
        let lower = max(0, currentUserIndex - 1)
        let upper = min(userIds.count - 1, currentUserIndex + 1)
        return Array(lower...upper)
    }

    private func stackBaseOffset(width: CGFloat, visibleIndices: [Int]) -> CGFloat {
        guard let position = visibleIndices.firstIndex(of: currentUserIndex) else {
            return 0
        }
        let centerOfCurrent = CGFloat(position) * width + width / 2
        return width / 2 - centerOfCurrent
    }

    private func role(for index: Int) -> StoryDeckPageRole {
        if index < currentUserIndex { return .leading }
        if index > currentUserIndex { return .trailing }
        return .center
    }

    private func pageProgress(for index: Int, width: CGFloat) -> CGFloat {
        CGFloat(index - currentUserIndex) + dragOffset / width
    }

    // MARK: - Gesture

    private func deckDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard userIds.count > 1 else { return }

                let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.35
                guard isHorizontal else { return }

                if !isDraggingDeck {
                    isDraggingDeck = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                let raw = value.translation.width
                // Instagram: izquierda → siguiente usuario | derecha → anterior
                if raw > 0 {
                    dragOffset = currentUserIndex > 0 ? raw : raw * 0.22
                } else {
                    dragOffset = currentUserIndex < userIds.count - 1 ? raw : raw * 0.22
                }
            }
            .onEnded { value in
                guard userIds.count > 1 else {
                    resetDrag(animated: true)
                    return
                }

                let translationX = value.translation.width
                let velocityX = value.velocity.width
                let isHorizontal = abs(translationX) > abs(value.translation.height) * 1.2

                guard isHorizontal, isDraggingDeck || dragOffset != 0 else {
                    resetDrag(animated: true)
                    return
                }

                let goToPrevious = translationX > 0
                let canNavigate = goToPrevious
                    ? currentUserIndex > 0
                    : currentUserIndex < userIds.count - 1

                let crossedThreshold = abs(translationX) > width * commitThreshold
                let flickedPrevious = velocityX > flickVelocity && translationX >= 0
                let flickedNext = velocityX < -flickVelocity && translationX <= 0
                let shouldCommit = canNavigate && (
                    crossedThreshold || (goToPrevious && flickedPrevious) || (!goToPrevious && flickedNext)
                )

                if shouldCommit {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let exitOffset: CGFloat = goToPrevious ? width : -width

                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        dragOffset = exitOffset
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        var nextIndex = currentUserIndex
                        if goToPrevious {
                            nextIndex = max(0, currentUserIndex - 1)
                        } else {
                            nextIndex = min(userIds.count - 1, currentUserIndex + 1)
                        }

                        if nextIndex != currentUserIndex {
                            currentUserIndex = nextIndex
                            onUserChanged?(nextIndex)
                        }

                        dragOffset = 0
                        isDraggingDeck = false
                    }
                } else {
                    resetDrag(animated: true)
                }
            }
    }

    private func resetDrag(animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                dragOffset = 0
            }
        } else {
            dragOffset = 0
        }
        isDraggingDeck = false
    }
}

// MARK: - Deck Pass visual

private struct DeckPassPageModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        let magnitude = min(abs(progress), 1)
        let scale = max(0.94, 1 - magnitude * 0.06)
        let opacity = max(0.52, 1 - magnitude * 0.48)
        let blurRadius = magnitude > 0.04 && magnitude < 0.98 ? 5 * min(1, magnitude) : 0

        content
            .scaleEffect(scale, anchor: .center)
            .opacity(opacity)
            .blur(radius: blurRadius)
    }
}
