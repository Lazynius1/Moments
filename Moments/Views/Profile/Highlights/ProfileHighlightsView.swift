import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

struct ProfileHighlightsView: View {
    let userId: String
    let isOwnProfile: Bool
    var isCompact: Bool = false
    var refreshTrigger: Int = 0

    @StateObject private var viewModel = ProfileHighlightsViewModel()
    @State private var presentation = HighlightPresentationCoordinator()
    @Namespace private var highlightZoomNamespace
    @State private var highlightZoomDestination: HighlightZoomDestination?
    @Environment(\.colorScheme) var colorScheme

    private var circleSize: CGFloat { isCompact ? 56 : 74 }
    private var horizontalSpacing: CGFloat { isCompact ? 10 : 16 }

    var body: some View {
        @Bindable var presentation = presentation

        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            if let errorMessage = viewModel.errorMessage {
                AppErrorBanner(message: errorMessage) {
                    viewModel.loadHighlights(userId: userId)
                }
                .padding(.horizontal, 20)
            }

            highlightsRail
        }
        .onAppear {
            if !userId.isEmpty {
                viewModel.loadHighlights(userId: userId)
            }
        }
        .onChange(of: userId) { _, newId in
            if !newId.isEmpty {
                viewModel.loadHighlights(userId: newId)
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            if !userId.isEmpty {
                viewModel.loadHighlights(userId: userId, forceRefresh: true)
            }
        }
        .fullScreenCover(item: $presentation.sheet) { sheet in
            Group {
                switch sheet {
                case .create:
                    HighlightCreateFlowView(mode: .create)
                case .edit(let highlight):
                    HighlightCreateFlowView(mode: .edit(highlight))
                }
            }
            .onDisappear {
                viewModel.loadHighlights(userId: userId, forceRefresh: true)
            }
        }
        .navigationDestination(item: $highlightZoomDestination) { destination in
            if let highlight = presentation.viewerHighlight {
                HighlightZoomDetailDestination(
                    destination: destination,
                    highlight: highlight,
                    namespace: highlightZoomNamespace
                )
            }
        }
        .onChange(of: highlightZoomDestination) { _, newValue in
            if newValue == nil {
                presentation.dismissViewer()
            }
        }
    }

    @ViewBuilder
    private var highlightsRail: some View {
        if viewModel.isLoading && viewModel.highlights.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: horizontalSpacing) {
                    if isOwnProfile {
                        PlusButtonPlaceholder(size: circleSize)
                    }
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(ProfileColors.cardBackground)
                                .frame(width: circleSize, height: circleSize)
                                .shimmering()

                            Rectangle()
                                .fill(ProfileColors.cardBackground)
                                .frame(width: 40, height: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .shimmering()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        } else if viewModel.highlights.isEmpty && !isOwnProfile {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: horizontalSpacing) {
                    if isOwnProfile {
                        Button {
                            presentation.presentCreate()
                        } label: {
                            VStack(spacing: isCompact ? 4 : 6) {
                                ZStack {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                                        .frame(width: circleSize, height: circleSize)
                                        .overlay(
                                            Circle()
                                                .stroke(ProfileColors.borderColor.opacity(0.5), lineWidth: 1)
                                        )

                                    Image(systemName: "plus")
                                        .font(.system(size: isCompact ? 16 : 20, weight: .semibold))
                                        .foregroundStyle(ProfileColors.accent)
                                }

                                if !isCompact {
                                    Text(NSLocalizedString("highlightedStories.new", comment: "New highlight"))
                                        .font(.system(size: legacyPoppinsSize(10)))
                                        .foregroundStyle(ProfileColors.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.momentsPress(scale: 0.94, haptic: .light))
                        .accessibilityLabel(Text("highlightedStories.new"))
                    }

                    ForEach(Array(viewModel.highlights.enumerated()), id: \.element.id) { index, highlight in
                        Button {
                            presentation.presentViewer(highlight)
                            highlightZoomDestination = HighlightZoomDestination(
                                zoomSourceID: ProfileMomentZoomNavigation.highlightSourceID(highlight: highlight, index: index),
                                highlightId: highlight.id ?? "highlight-\(index)"
                            )
                        } label: {
                            VStack(spacing: isCompact ? 4 : 6) {
                                HighlightIconView(highlight: highlight, size: circleSize)
                                    .modifier(HighlightZoomSourceModifier(
                                        namespace: highlightZoomNamespace,
                                        sourceID: ProfileMomentZoomNavigation.highlightSourceID(highlight: highlight, index: index),
                                        size: circleSize
                                    ))

                                Text(highlight.title)
                                    .font(.system(size: legacyPoppinsSize(isCompact ? 9 : 11), weight: .medium))
                                    .foregroundStyle(ProfileColors.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: isCompact ? 60 : 80)
                            }
                        }
                        .buttonStyle(.momentsPress(scale: 0.94, haptic: .light))
                        .accessibilityLabel(highlight.title)
                        .contextMenu {
                            if isOwnProfile {
                                Button {
                                    presentation.presentEdit(highlight)
                                } label: {
                                    Label(NSLocalizedString("common.edit", comment: "Edit"), systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    if let id = highlight.id {
                                        viewModel.deleteHighlight(userId: userId, highlightId: id)
                                    }
                                } label: {
                                    Label(NSLocalizedString("common.delete", comment: "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct PlusButtonPlaceholder: View {
    let size: CGFloat
    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(ProfileColors.materialBackground)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(ProfileColors.borderColor.opacity(0.5), lineWidth: 1))
            Spacer().frame(height: 10)
        }
    }
}

struct HighlightIconView: View {
    let highlight: HighlightedStory
    var size: CGFloat = 64
    @Environment(\.colorScheme) var colorScheme
    @State private var resolvedCoverStory: Story?

    var body: some View {
        ZStack {
            if let resolvedCoverStory {
                StoryStaticPreviewSurface(story: resolvedCoverStory)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let coverUrl = highlight.coverImageUrl, let url = URL(string: coverUrl) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(ProfileColors.materialBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "star.fill")
                            .foregroundStyle(ProfileColors.accent.opacity(0.5))
                            .font(.system(size: size * 0.3))
                    )
            }

            Circle()
                .stroke(ProfileColors.borderColor.opacity(0.5), lineWidth: 1)
                .frame(width: size, height: size)
        }
        .task(id: coverResolutionIdentity) {
            resolveCoverStory()
        }
    }

    private var coverResolutionIdentity: String {
        "\(highlight.id ?? "")-\(highlight.coverImageUrl ?? "")-\(highlight.storyIds.joined(separator: ","))"
    }

    private func resolveCoverStory() {
        guard !highlight.storyIds.isEmpty else { return }
        FirestoreService.shared.fetchStoriesByIds(
            userId: highlight.authorId,
            storyIds: highlight.storyIds
        ) { result in
            guard case .success(let stories) = result else { return }
            let coverURL = highlight.coverImageUrl
            let resolved = stories.first(where: { $0.mediaItem.url == coverURL }) ?? stories.first
            DispatchQueue.main.async {
                resolvedCoverStory = resolved
            }
        }
    }
}

class ProfileHighlightsViewModel: ObservableObject {
    @Published var highlights: [HighlightedStory] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let firestoreService = FirestoreService.shared
    private let privacyService = PrivacyService()
    private var loadTask: Task<Void, Never>?
    private var loadingKey: String?
    private var contentKey: String?
    private var requestId = UUID()
    private var reloadAfterCurrent = false

    private func isPermissionDeniedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = nsError.localizedDescription.lowercased()
        return message.contains("missing or insufficient permissions")
            || message.contains("permission denied")
            || message.contains("insufficient permissions")
    }

    func loadHighlights(userId: String, forceRefresh: Bool = false) {
        guard let viewerId = Auth.auth().currentUser?.uid else { return }
        let key = "\(viewerId)/\(userId)"
        if loadingKey == key {
            reloadAfterCurrent = reloadAfterCurrent || forceRefresh
            return
        }
        loadTask?.cancel()
        let id = UUID()
        requestId = id
        if contentKey != key { highlights = [] }
        contentKey = key
        loadingKey = key
        reloadAfterCurrent = false
        isLoading = true
        errorMessage = nil

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result: Result<[HighlightedStory], Error>
            if let response = await BackendFeedService.shared.fetchVisibleHighlights(targetUserId: userId, limit: 30) {
                result = .success(response.highlights)
            } else {
                guard !Task.isCancelled, self.requestId == id else { return }
                result = await withCheckedContinuation { continuation in
                    self.firestoreService.fetchHighlights(userId: userId) { response in
                        switch response {
                        case .success(let highlights):
                            if viewerId == userId {
                                continuation.resume(returning: .success(highlights))
                            } else {
                                self.filterAndResolveHighlights(highlights: highlights, viewerId: viewerId, userId: userId) {
                                    continuation.resume(returning: .success($0))
                                }
                            }
                        case .failure(let error):
                            continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
            guard !Task.isCancelled, self.requestId == id,
                  Auth.auth().currentUser?.uid == viewerId else { return }
            switch result {
            case .success(let highlights): self.highlights = highlights
            case .failure(let error):
                if self.isPermissionDeniedError(error) { self.highlights = [] }
                else { self.errorMessage = error.localizedDescription }
            }
            self.isLoading = false
            self.loadingKey = nil
            self.loadTask = nil
            if self.reloadAfterCurrent {
                self.reloadAfterCurrent = false
                self.loadHighlights(userId: userId)
            }
        }
    }

    private func filterAndResolveHighlights(highlights: [HighlightedStory], viewerId: String, userId: String, completion: @escaping ([HighlightedStory]) -> Void) {
        let group = DispatchGroup()
        var resolvedHighlights: [HighlightedStory] = []
        let syncQueue = DispatchQueue(label: "profile.highlights.privacy.sync")

        for highlight in highlights {
            group.enter()
            firestoreService.fetchStoriesByIds(userId: userId, storyIds: highlight.storyIds) { result in
                switch result {
                case .success(let stories):
                    let storyGroup = DispatchGroup()
                    var viewableStories: [Story] = []
                    let storySyncQueue = DispatchQueue(label: "story.p.sync")

                    for story in stories {
                        storyGroup.enter()
                        self.privacyService.canUserViewStoryEnhanced(story, viewerId: viewerId) { canView in
                            if canView {
                                storySyncQueue.sync {
                                    viewableStories.append(story)
                                }
                            }
                            storyGroup.leave()
                        }
                    }

                    storyGroup.notify(queue: .global()) {
                        if !viewableStories.isEmpty {
                            let resolvedCoverUrl: String?
                            if let originalCover = highlight.coverImageUrl,
                               viewableStories.contains(where: { $0.mediaItem.url == originalCover }) {
                                resolvedCoverUrl = originalCover
                            } else {
                                resolvedCoverUrl = viewableStories.first?.mediaItem.url
                            }

                            let resolvedHighlight = HighlightedStory(
                                id: highlight.id,
                                title: highlight.title,
                                coverImageUrl: resolvedCoverUrl,
                                storiesCount: viewableStories.count,
                                createdAt: highlight.createdAt,
                                storyIds: viewableStories.compactMap(\.id),
                                authorId: highlight.authorId
                            )

                            syncQueue.sync {
                                resolvedHighlights.append(resolvedHighlight)
                            }
                        }
                        group.leave()
                    }
                case .failure:
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let resolvedById = Dictionary(resolvedHighlights.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            completion(highlights.compactMap { resolvedById[$0.id] })
        }
    }

    func deleteHighlight(userId: String, highlightId: String) {
        firestoreService.deleteHighlight(userId: userId, highlightId: highlightId) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            } else {
                DispatchQueue.main.async {
                    InAppNotificationService.shared.showActionToast(.highlightDeleted)
                    self?.loadHighlights(userId: userId, forceRefresh: true)
                }
            }
        }
    }
}

extension View {
    @ViewBuilder
    func shimmering() -> some View {
        self.opacity(0.5)
    }
}
