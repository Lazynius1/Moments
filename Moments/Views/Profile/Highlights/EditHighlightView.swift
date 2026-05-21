import SwiftUI
import Kingfisher
import FirebaseAuth
import FirebaseFirestore

struct EditHighlightView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel: EditHighlightViewModel
    
    init(highlight: HighlightedStory) {
        _viewModel = StateObject(wrappedValue: EditHighlightViewModel(highlight: highlight))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // 1. Portada
                        VStack(spacing: 12) {
                            ZStack {
                                if let coverStory = viewModel.coverStory, let url = URL(string: coverStory.mediaItem.url) {
                                    KFImage(url)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else if let coverUrl = viewModel.highlight.coverImageUrl, let url = URL(string: coverUrl) {
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
                        .padding(.top, 20)
                        
                        // 2. Título
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
                        
                        // 3. Selección de Historias
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("highlightedStories.selectStories", comment: "Select stories"))
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, 24)
                            
                            if viewModel.isLoading && viewModel.allStories.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                                    // 1. Mostrar las historias que YA están en la destacada (Priorizadas)
                                    // Usamos allStories para mantener la consistencia visual si están cargadas
                                    let prioritized = viewModel.allStories.sorted { s1, s2 in
                                        let s1Selected = viewModel.highlight.storyIds.contains(s1.id ?? "")
                                        let s2Selected = viewModel.highlight.storyIds.contains(s2.id ?? "")
                                        if s1Selected != s2Selected {
                                            return s1Selected // True (seleccionada) va primero
                                        }
                                        return s1.timestamp > s2.timestamp // Ordenar por fecha dentro de cada grupo
                                    }
                                    
                                    ForEach(prioritized) { story in
                                        SelectableStoryCard(
                                            story: story,
                                            isSelected: viewModel.selectedStories.contains(where: { $0.id == story.id }),
                                            onTap: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    viewModel.toggleSelection(story)
                                                }
                                            }
                                        )
                                        .onAppear {
                                            if story.id == viewModel.allStories.last?.id {
                                                viewModel.loadMore()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("common.edit", comment: "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "Done")) {
                        viewModel.updateHighlight { error in
                            if error == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.title.isEmpty || viewModel.selectedStories.isEmpty || viewModel.isSaving)
                    .font(.custom("Poppins-SemiBold", size: 16))
                }
            }
            .sheet(isPresented: $viewModel.showCoverPicker) {
                CoverPickerViewForEdit(viewModel: viewModel)
            }
            .alert(NSLocalizedString("common.error", comment: "Error"), isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
            .onAppear {
                viewModel.loadStories()
            }
        }
    }
}

class EditHighlightViewModel: ObservableObject {
    let highlight: HighlightedStory
    @Published var allStories: [Story] = []
    @Published var selectedStories: [Story] = []
    @Published var title: String
    @Published var coverStory: Story?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var showCoverPicker = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var hasMore = true
    
    private let firestoreService = FirestoreService()
    private var lastDocument: DocumentSnapshot?
    
    init(highlight: HighlightedStory) {
        self.highlight = highlight
        self.title = highlight.title
    }
    
    func loadStories() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Reset state
        isLoading = true
        allStories = []
        selectedStories = []
        lastDocument = nil
        hasMore = true
        
        // 1. Cargamos el primer batch del grid de inmediato
        internalLoadMore(userId: userId)
        
        // 2. En paralelo, cargamos los objetos Story de las ya seleccionadas
        // Así estarán marcadas correctamente aunque no aparezcan en el primer batch
        firestoreService.fetchStoriesByIds(userId: userId, storyIds: highlight.storyIds) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let stories) = result {
                    self?.selectedStories = stories
                }
            }
        }
    }
    
    func loadMore() {
        guard let userId = Auth.auth().currentUser?.uid, hasMore, !isLoading else { return }
        internalLoadMore(userId: userId)
    }
    
    private func internalLoadMore(userId: String) {
        firestoreService.fetchStoriesPaginated(userId: userId, limit: 20, lastDocument: lastDocument) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let data):
                    let newStories = data.stories
                    // Evitar duplicados
                    for story in newStories {
                        if !self.allStories.contains(where: { $0.id == story.id }) {
                            self.allStories.append(story)
                        }
                    }
                    self.lastDocument = data.lastDoc
                    self.hasMore = !newStories.isEmpty && newStories.count == 20
                    
                case .failure:
                    self.hasMore = false
                }
                
                // Finalizamos la carga inicial si procede
                self.isLoading = false
            }
        }
    }
    
    func toggleSelection(_ story: Story) {
        if let index = selectedStories.firstIndex(where: { $0.id == story.id }) {
            selectedStories.remove(at: index)
            if coverStory?.id == story.id {
                coverStory = nil
            }
        } else {
            selectedStories.append(story)
        }
    }
    
    func updateHighlight(completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid, let highlightId = highlight.id else { return }
        
        isSaving = true
        let storyIds = selectedStories.map { $0.id ?? "" }
        let coverUrl = coverStory?.mediaItem.url ?? highlight.coverImageUrl
        
        firestoreService.updateHighlight(userId: userId, highlightId: highlightId, title: title, storyIds: storyIds, coverImageUrl: coverUrl) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSaving = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.showError = true
                    completion(error)
                } else {
                    completion(nil)
                }
            }
        }
    }
}

// Reuso de selector de portada para edición
struct CoverPickerViewForEdit: View {
    @ObservedObject var viewModel: EditHighlightViewModel
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
