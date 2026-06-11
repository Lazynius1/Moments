import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

struct ProfileHighlightsView: View {
    let userId: String
    let isOwnProfile: Bool
    var isCompact: Bool = false

    @StateObject private var viewModel = ProfileHighlightsViewModel()
    @State private var presentation = HighlightPresentationCoordinator()
    @Environment(\.colorScheme) var colorScheme

    private var circleSize: CGFloat { isCompact ? 58 : 64 }
    private var horizontalSpacing: CGFloat { isCompact ? 12 : 16 }

    var body: some View {
        @Bindable var presentation = presentation

        VStack(alignment: .leading, spacing: 8) {
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
                viewModel.loadHighlights(userId: userId)
            }
        }
        .fullScreenCover(item: $presentation.viewerHighlight) { highlight in
            HighlightViewer(highlight: highlight)
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
                                .cornerRadius(4)
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
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                                        .frame(width: circleSize, height: circleSize)
                                        .overlay(
                                            Circle()
                                                .stroke(ProfileColors.borderColor.opacity(0.5), lineWidth: 1)
                                        )

                                    Image(systemName: "plus")
                                        .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
                                        .foregroundColor(ProfileColors.accent)
                                }

                                if !isCompact {
                                    Text(NSLocalizedString("highlightedStories.new", comment: "New highlight"))
                                        .font(.custom("Poppins-Regular", size: 10))
                                        .foregroundColor(ProfileColors.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.momentsPress(scale: 0.94, haptic: .light))
                        .accessibilityLabel(Text("highlightedStories.new"))
                    }

                    ForEach(viewModel.highlights) { highlight in
                        Button {
                            presentation.presentViewer(highlight)
                        } label: {
                            VStack(spacing: 6) {
                                HighlightIconView(highlight: highlight, size: circleSize)

                                Text(highlight.title)
                                    .font(.custom("Poppins-Medium", size: isCompact ? 10 : 11))
                                    .foregroundColor(ProfileColors.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: isCompact ? 60 : 70)
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

    var body: some View {
        ZStack {
            if let coverUrl = highlight.coverImageUrl, let url = URL(string: coverUrl) {
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
                            .foregroundColor(ProfileColors.accent.opacity(0.5))
                            .font(.system(size: size * 0.3))
                    )
            }

            Circle()
                .stroke(ProfileColors.borderColor.opacity(0.5), lineWidth: 1)
                .frame(width: size, height: size)
        }
    }
}

class ProfileHighlightsViewModel: ObservableObject {
    @Published var highlights: [HighlightedStory] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let firestoreService = FirestoreService.shared
    private let privacyService = PrivacyService()

    func loadHighlights(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        errorMessage = nil
        firestoreService.fetchHighlights(userId: userId) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let allHighlights):
                if userId == currentUserId {
                    DispatchQueue.main.async {
                        self.highlights = allHighlights
                        self.isLoading = false
                    }
                } else {
                    self.filterAndResolveHighlights(highlights: allHighlights, viewerId: currentUserId, userId: userId)
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.highlights = []
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func filterAndResolveHighlights(highlights: [HighlightedStory], viewerId: String, userId: String) {
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
            self.highlights = highlights.compactMap { original in
                resolvedHighlights.first { $0.id == original.id }
            }
            self.isLoading = false
        }
    }

    func deleteHighlight(userId: String, highlightId: String) {
        firestoreService.deleteHighlight(userId: userId, highlightId: highlightId) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            } else {
                self?.loadHighlights(userId: userId)
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
