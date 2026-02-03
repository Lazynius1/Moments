import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct HighlightViewer: View {
    let highlight: HighlightedStory
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = HighlightViewerViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(NSLocalizedString("highlightedStories.loading", comment: "Loading stories..."))
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if viewModel.stories.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text(NSLocalizedString("stories.noStoriesAvailable", comment: "No stories available"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Button(NSLocalizedString("archivedStories.close", comment: "Close")) {
                        dismiss()
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.blue)
                }
            } else {
                StoriesView(chainStories: viewModel.stories, startAtIndex: 0)
            }
        }
        .onAppear {
            viewModel.loadStories(highlight: highlight)
        }
    }
}

class HighlightViewerViewModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var isLoading = true
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    
    func loadStories(highlight: HighlightedStory) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        
        isLoading = true
        firestoreService.fetchStoriesByIds(userId: highlight.authorId, storyIds: highlight.storyIds) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let allStories):
                // Filtrar historias por privacidad de forma asíncrona
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
                syncQueue.async { // Ensure all operations related to filteredStories are on the serial queue
                    if canView {
                        filteredStories.append(story)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: syncQueue) { [weak self] in
            let finalSelection = filteredStories
            DispatchQueue.main.async {
                self?.stories = stories.filter { originalStory in
                    finalSelection.contains { $0.id == originalStory.id }
                }
                self?.isLoading = false
            }
        }
    }
}
