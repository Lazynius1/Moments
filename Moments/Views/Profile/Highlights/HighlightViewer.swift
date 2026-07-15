import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct HighlightViewer: View {
    let highlight: HighlightedStory
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = HighlightViewerViewModel()
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            content
                .offset(y: max(0, dragOffset))
        }
        .gesture(dismissDragGesture)
        .onAppear {
            viewModel.loadStories(highlight: highlight)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)

                Text(NSLocalizedString("highlightedStories.loading", comment: "Loading stories..."))
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else if viewModel.stories.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.35))

                Text(NSLocalizedString("stories.noStoriesAvailable", comment: "No stories available"))
                    .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                Button(NSLocalizedString("common.close", comment: "Close")) {
                    dismiss()
                }
                .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                .foregroundStyle(ProfileColors.accent)
            }
        } else {
            StoriesView(
                chainStories: viewModel.stories,
                startAtIndex: 0,
                highlightTitle: highlight.title
            )
            .environmentObject(FirestoreService.shared)
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

class HighlightViewerViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var isLoading = true

    private let firestoreService = FirestoreService.shared
    private let privacyService = PrivacyService()

    func loadStories(highlight: HighlightedStory) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        isLoading = true
        firestoreService.fetchStoriesByIds(userId: highlight.authorId, storyIds: highlight.storyIds) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let allStories):
                self.filterStoriesByPrivacy(stories: allStories, viewerId: currentUserId)
            case .failure:
                DispatchQueue.main.async {
                    self.stories = []
                    self.isLoading = false
                }
            }
        }
    }

    private func filterStoriesByPrivacy(stories: [Story], viewerId: String) {
        let group = DispatchGroup()
        var filteredStories: [Story] = []
        let syncQueue = DispatchQueue(label: "highlight.privacy.sync")

        for story in stories {
            group.enter()
            privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                syncQueue.async {
                    if canView {
                        filteredStories.append(story)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: syncQueue) { [weak self] in
            DispatchQueue.main.async {
                self?.stories = stories.filter { originalStory in
                    filteredStories.contains { $0.id == originalStory.id }
                }
                self?.isLoading = false
            }
        }
    }
}
