import SwiftUI
import Kingfisher
import FirebaseAuth
import FirebaseFirestore

struct CreateHighlightView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = CreateHighlightViewModel()
    
    @State private var step: CreationStep = .selectStories
    
    enum CreationStep {
        case selectStories
        case details
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if step == .selectStories {
                    StorySelectionView(viewModel: viewModel)
                } else {
                    HighlightDetailsView(viewModel: viewModel)
                }
            }
            .navigationTitle(step == .selectStories ? NSLocalizedString("highlightedStories.selectStories", comment: "Select stories") : NSLocalizedString("highlightedStories.newHighlight", comment: "New Highlight"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if step == .selectStories {
                        Button(NSLocalizedString("common.next", comment: "Next")) {
                            withAnimation {
                                step = .details
                            }
                        }
                        .disabled(viewModel.selectedStories.isEmpty)
                    } else {
                        Button(NSLocalizedString("common.done", comment: "Done")) {
                            viewModel.saveHighlight { error in
                                if error == nil {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.title.isEmpty || viewModel.isSaving)
                    }
                }
            }
            .alert(NSLocalizedString("common.error", comment: "Error"), isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
        }
    }
}

// MARK: - Story Selection View
struct StorySelectionView: View {
    @ObservedObject var viewModel: CreateHighlightViewModel
    @Environment(\.colorScheme) var colorScheme
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                VStack {
                    ProgressView()
                        .padding(.top, 50)
                    Text(NSLocalizedString("common.loading", comment: "Loading"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.allStories.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.3))
                    Text(NSLocalizedString("highlightedStories.noStoriesToSelect", comment: "No stories to select"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.gray)
                }
                .padding(.top, 100)
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.groupedStoriesKeys, id: \.self) { date in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(date)
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(viewModel.groupedStories[date] ?? []) { story in
                                    SelectableStoryCard(
                                        story: story,
                                        isSelected: viewModel.selectedStories.contains(where: { $0.id == story.id }),
                                        onTap: {
                                            viewModel.toggleSelection(story)
                                        }
                                    )
                                    .onAppear {
                                        // Cargar más cuando llegamos al final
                                        if story.id == viewModel.allStories.last?.id {
                                            viewModel.loadStories(isInitial: false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            viewModel.loadStories()
        }
    }
}

// MARK: - Highlight Details View
struct HighlightDetailsView: View {
    @ObservedObject var viewModel: CreateHighlightViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 34) {
            // Cover Selection
            VStack(spacing: 16) {
                ZStack {
                    if let coverStory = viewModel.coverStory, let url = URL(string: coverStory.mediaItem.url) {
                        KFImage(url)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                    }
                    
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        .frame(width: 100, height: 100)
                }
                
                Button(NSLocalizedString("highlightedStories.editCover", comment: "Edit Cover")) {
                    viewModel.showCoverPicker = true
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(.blue)
            }
            .padding(.top, 40)
            .sheet(isPresented: $viewModel.showCoverPicker) {
                CoverPickerView(viewModel: viewModel)
            }
            
            // Title Input
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("highlightedStories.titleLabel", comment: "Title"))
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.gray)
                
                TextField(NSLocalizedString("highlightedStories.titlePlaceholder", comment: "Title Placeholder"), text: $viewModel.title)
                    .font(.custom("Poppins-Regular", size: 16))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            if viewModel.isSaving {
                ProgressView()
                    .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - ViewModel
class CreateHighlightViewModel: ObservableObject {
    @Published var allStories: [Story] = []
    @Published var selectedStories: [Story] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var title = ""
    @Published var coverStory: Story?
    @Published var showCoverPicker = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let firestoreService = FirestoreService()
    private var lastDocument: DocumentSnapshot? // Para paginación
    @Published var hasMoreStories = true
    var groupedStories: [String: [Story]] = [:]
    var groupedStoriesKeys: [String] = []
    
    func loadStories(isInitial: Bool = true) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        if isInitial {
            isLoading = true
            lastDocument = nil
            allStories = []
            groupedStories = [:]
            groupedStoriesKeys = []
            hasMoreStories = true
        } else if !hasMoreStories || isLoading {
            return
        }
        
        firestoreService.fetchStoriesPaginated(userId: userId, limit: 20, lastDocument: lastDocument) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let data):
                    self.allStories.append(contentsOf: data.stories)
                    self.lastDocument = data.lastDoc
                    self.hasMoreStories = !data.stories.isEmpty && data.stories.count == 20
                    self.updateGroupedStories(data.stories)
                case .failure:
                    if isInitial {
                        self.allStories = []
                        self.groupedStories = [:]
                        self.groupedStoriesKeys = []
                    }
                }
            }
        }
    }
    
    private func updateGroupedStories(_ newStories: [Story]) {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "es")
        
        for story in newStories {
            let dateKey = formatter.string(from: story.expirationDate.addingTimeInterval(-24*3600))
            if groupedStories[dateKey] == nil {
                groupedStories[dateKey] = []
                groupedStoriesKeys.append(dateKey)
            }
            groupedStories[dateKey]?.append(story)
        }
    }
    
    func toggleSelection(_ story: Story) {
        if let index = selectedStories.firstIndex(where: { $0.id == story.id }) {
            selectedStories.remove(at: index)
            if coverStory?.id == story.id {
                coverStory = selectedStories.first
            }
        } else {
            selectedStories.append(story)
            if coverStory == nil {
                coverStory = story
            }
        }
    }
    
    func saveHighlight(completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid, !selectedStories.isEmpty else { return }
        
        isSaving = true
        let storyIds = selectedStories.map { $0.id ?? "" }.filter { !$0.isEmpty }
        let coverUrl = coverStory?.mediaItem.url
        
        firestoreService.createHighlight(userId: userId, title: title, storyIds: storyIds, coverImageUrl: coverUrl) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSaving = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.showError = true
                    completion(error)
                } else {
                    print("✅ Highlight created successfully")
                    completion(nil)
                }
            }
        }
    }
}

// MARK: - Cover Picker View
struct CoverPickerView: View {
    @ObservedObject var viewModel: CreateHighlightViewModel
    @Environment(\.dismiss) var dismiss
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.selectedStories) { story in
                        Button(action: {
                            viewModel.coverStory = story
                            dismiss()
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                let urlString = story.mediaItem.thumbnailUrl ?? story.mediaItem.url
                                if let url = URL(string: urlString) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: (UIScreen.main.bounds.width - 4) / 3, height: (UIScreen.main.bounds.width - 4) / 3)
                                        .clipped()
                                }
                                
                                if viewModel.coverStory?.id == story.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .background(Circle().fill(Color.white))
                                        .padding(8)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .navigationTitle(NSLocalizedString("highlightedStories.selectCover", comment: "Select Cover"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
