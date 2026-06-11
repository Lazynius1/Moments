import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum HighlightFlowMode {
    case create
    case edit(HighlightedStory)
}

enum HighlightCreateStep {
    case selectStories
    case nameAndCover
}

@Observable
final class HighlightCreateFlowViewModel {
    let mode: HighlightFlowMode

    var step: HighlightCreateStep = .selectStories
    var allStories: [Story] = []
    var selectedStories: [Story] = []
    var title = ""
    var coverStory: Story?
    var isLoading = false
    var isSaving = false
    var showCoverPicker = false
    var errorMessage: String?
    var hasMoreStories = true

    private let firestoreService = FirestoreService.shared
    private var lastDocument: DocumentSnapshot?
    private var didLoadInitialSelection = false

    var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    var editingHighlight: HighlightedStory? {
        if case .edit(let highlight) = mode { return highlight }
        return nil
    }

    var canAdvance: Bool {
        !selectedStories.isEmpty
    }

    var canSave: Bool {
        !selectedStories.isEmpty
    }

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSLocalizedString("highlightedStories.defaultTitle", comment: "")
        }
        return trimmed
    }

    var saveActionTitleKey: String {
        isEditMode ? "common.save" : "highlightedStories.add"
    }

    var sortedArchiveStories: [Story] {
        allStories.sorted { $0.timestamp > $1.timestamp }
    }

    init(mode: HighlightFlowMode) {
        self.mode = mode
        if case .edit(let highlight) = mode {
            title = highlight.title
        }
    }

    func loadIfNeeded() {
        guard allStories.isEmpty, !isLoading else { return }
        loadArchivedStories(isInitial: true)
        loadInitialSelectionIfNeeded()
    }

    private func loadInitialSelectionIfNeeded() {
        guard !didLoadInitialSelection,
              case .edit(let highlight) = mode,
              let userId = Auth.auth().currentUser?.uid else { return }

        didLoadInitialSelection = true
        firestoreService.fetchStoriesByIds(userId: userId, storyIds: highlight.storyIds) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let stories) = result {
                    self.selectedStories = stories
                    if let coverUrl = highlight.coverImageUrl,
                       let match = stories.first(where: { $0.mediaItem.url == coverUrl }) {
                        self.coverStory = match
                    } else {
                        self.coverStory = stories.first
                    }
                    self.mergeSelectedIntoArchive()
                }
            }
        }
    }

    func loadArchivedStories(isInitial: Bool = false) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        if isInitial {
            isLoading = true
            lastDocument = nil
            allStories = []
            hasMoreStories = true
            if !isEditMode {
                selectedStories = []
                coverStory = nil
            }
        } else if !hasMoreStories || isLoading {
            return
        } else {
            isLoading = true
        }

        firestoreService.fetchArchivedStoriesPaginated(
            userId: userId,
            limit: 24,
            lastDocument: lastDocument
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success(let data):
                    let newStories = data.stories.filter { story in
                        !self.allStories.contains(where: { $0.id == story.id })
                    }
                    self.allStories.append(contentsOf: newStories)
                    self.lastDocument = data.lastDoc
                    self.hasMoreStories = !data.stories.isEmpty && data.stories.count == 24
                    self.mergeSelectedIntoArchive()
                case .failure:
                    if isInitial {
                        self.allStories = []
                    }
                    self.errorMessage = NSLocalizedString("highlightedStories.loadFailed", comment: "")
                }
            }
        }
    }

    private func mergeSelectedIntoArchive() {
        let missing = selectedStories.filter { story in
            !allStories.contains(where: { $0.id == story.id })
        }
        guard !missing.isEmpty else { return }

        allStories.append(contentsOf: missing)
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

    func advanceToNameAndCover() {
        guard canAdvance else { return }
        if coverStory == nil {
            coverStory = selectedStories.first
        }
        step = .nameAndCover
    }

    func backToSelectStories() {
        step = .selectStories
    }

    func save(completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid, canSave else { return }

        isSaving = true
        errorMessage = nil
        let storyIds = selectedStories.compactMap(\.id).filter { !$0.isEmpty }
        let coverUrl = coverStory?.mediaItem.url

        switch mode {
        case .create:
            firestoreService.createHighlight(
                userId: userId,
                title: resolvedTitle,
                storyIds: storyIds,
                coverImageUrl: coverUrl
            ) { [weak self] error in
                DispatchQueue.main.async {
                    self?.isSaving = false
                    if let error {
                        self?.errorMessage = error.localizedDescription
                    }
                    completion(error)
                }
            }
        case .edit(let highlight):
            guard let highlightId = highlight.id, !highlightId.isEmpty else {
                isSaving = false
                let error = NSError(
                    domain: "HighlightCreateFlow",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("highlightedStories.invalidHighlight", comment: "")
                    ]
                )
                errorMessage = error.localizedDescription
                completion(error)
                return
            }
            firestoreService.updateHighlight(
                userId: userId,
                highlightId: highlightId,
                title: resolvedTitle,
                storyIds: storyIds,
                coverImageUrl: coverUrl ?? highlight.coverImageUrl
            ) { [weak self] error in
                DispatchQueue.main.async {
                    self?.isSaving = false
                    if let error {
                        self?.errorMessage = error.localizedDescription
                    }
                    completion(error)
                }
            }
        }
    }

    func deleteHighlight(completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid,
              let highlightId = editingHighlight?.id else { return }

        isSaving = true
        firestoreService.deleteHighlight(userId: userId, highlightId: highlightId) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSaving = false
                if let error {
                    self?.errorMessage = error.localizedDescription
                }
                completion(error)
            }
        }
    }
}
