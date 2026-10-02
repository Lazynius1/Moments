import SwiftUI

struct HighlightSelectStoriesStep: View {
    @Bindable var viewModel: HighlightCreateFlowViewModel

    var body: some View {
        let archiveStories = viewModel.sortedArchiveStories
        let lastStoryId = archiveStories.last?.id
        ScrollView {
            if let errorMessage = viewModel.errorMessage {
                AppErrorBanner(message: errorMessage) {
                    viewModel.errorMessage = nil
                    viewModel.loadArchivedStories(isInitial: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HighlightStoryGrid(
                stories: archiveStories,
                selectedIds: Set(viewModel.selectedStories.compactMap(\.id)),
                isLoading: viewModel.isLoading,
                isEmpty: viewModel.allStories.isEmpty && !viewModel.isLoading,
                emptyMessageKey: "highlightedStories.archiveEmpty",
                onToggle: { viewModel.toggleSelection($0) },
                onStoryAppear: { story in
                    if let lastStoryId, story.id == lastStoryId {
                        viewModel.loadArchivedStories(isInitial: false)
                    }
                }
            )
            .padding(.bottom, 24)
        }
        .momentsScrollEdgeChrome()
    }
}
