import SwiftUI

/// Viewer de stories filtradas por lugar (varios autores en el mismo cluster).
struct MapPlaceStoryDeckView: View {
    let previews: [MapStoryPreview]
    let initialPreviewId: String?
    let onClose: () -> Void

    @StateObject private var storyViewModel = StoryViewModel()
    @State private var stories: [Story] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let story = stories[safe: currentIndex] {
                StoryViewerScreen(
                    story: story,
                    storyCount: stories.count,
                    storyIndex: currentIndex,
                    screenSize: UIScreen.main.bounds.size,
                    storyViewModel: storyViewModel,
                    showingReportSheet: $showingReportSheet,
                    showingBlockConfirmation: $showingBlockConfirmation,
                    onReportStory: { },
                    onBlockUser: { },
                    onNext: advanceStory,
                    onPrevious: retreatStory,
                    onClose: onClose,
                    onProfileTap: { }
                )
            } else {
                Color.black
                    .onAppear(perform: onClose)
            }
        }
        .onAppear {
            loadStories()
        }
    }

    private func advanceStory() {
        if currentIndex < stories.count - 1 {
            currentIndex += 1
        } else {
            onClose()
        }
    }

    private func retreatStory() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    private func loadStories() {
        MapPlaceStoryFetcher.fetchStories(from: previews) { fetched in
            stories = fetched
            isLoading = false

            if let initialPreviewId,
               let index = fetched.firstIndex(where: { $0.id == initialPreviewId }) {
                currentIndex = index
            } else {
                currentIndex = 0
            }
        }
    }
}

enum MapPlaceStoryFetcher {
    static func fetchStories(
        from previews: [MapStoryPreview],
        completion: @escaping ([Story]) -> Void
    ) {
        guard !previews.isEmpty else {
            completion([])
            return
        }

        let sortedPreviews = previews.sorted { $0.timestamp > $1.timestamp }
        let grouped = Dictionary(grouping: sortedPreviews, by: \.authorId)
        let group = DispatchGroup()
        var fetchedByKey: [String: Story] = [:]
        let lock = NSLock()

        for (authorId, authorPreviews) in grouped {
            group.enter()
            let storyIds = authorPreviews.map(\.id)
            FirestoreService.shared.fetchStoriesByIds(userId: authorId, storyIds: storyIds) { result in
                if case .success(let stories) = result {
                    lock.lock()
                    for story in stories {
                        if let id = story.id {
                            fetchedByKey["\(authorId):\(id)"] = story
                        }
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let ordered = sortedPreviews.compactMap { preview in
                fetchedByKey["\(preview.authorId):\(preview.id)"]
            }
            completion(ordered)
        }
    }
}
