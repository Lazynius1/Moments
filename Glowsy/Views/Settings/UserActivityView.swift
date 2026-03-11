import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import Kingfisher
import AVFoundation

struct UserActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var summaryVM = ActivitySummaryViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(NSLocalizedString("userActivity.simple.headline", comment: "Activity headline"))
                                .font(.custom("Poppins-Bold", size: 30))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.leading)
                            
                            Text(NSLocalizedString("userActivity.simple.subtitle", comment: "Activity subtitle"))
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 32) {
                            // SECCIÓN: INTERACCIONES
                            activitySection(
                                title: NSLocalizedString("userActivity.section.interactions", comment: "Interactions section"),
                                categories: [.reactions, .comments, .tags, .stickerReplies]
                            )
                            
                            // SECCIÓN: CONTENIDO ELIMINADO Y ARCHIVADO
                            activitySection(
                                title: NSLocalizedString("userActivity.module.content.title", comment: "Content section"),
                                categories: [.archived, .storiesArchive, .recentlyDeleted]
                            )
                            
                            // SECCIÓN: CONTENIDO COMPARTIDO
                            activitySection(
                                title: NSLocalizedString("userActivity.section.sharedContent", comment: "Shared content section"),
                                categories: [.moments, .reels, .echoes]
                            )
                            
                            // SECCIÓN: HISTORIAL
                            activitySection(
                                title: NSLocalizedString("userActivity.section.history", comment: "History section"),
                                categories: [.followers, .visits]
                            )
                            
                            // SECCIÓN: CÓMO USAS MOMENTS
                            activitySection(
                                title: NSLocalizedString("userActivity.section.usage", value: "HOW YOU USE MOMENTS", comment: "Usage section"),
                                categories: [.timeSpent, .searches, .accountHistory]
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(NSLocalizedString("userActivity.title", comment: "User activity title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .onAppear {
                summaryVM.load()
                summaryVM.autoRefresh()
            }
        }
    }

    private func activitySection(title: String, categories: [ActivityInteractionCategory]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.custom("Poppins-SemiBold", size: 12))
                .foregroundColor(.gray.opacity(0.8))
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    NavigationLink {
                        activityDestination(for: category)
                    } label: {
                        ActivityInteractionCategoryRow(
                            category: category,
                            summary: summaryVM.summaries[category]
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if index < categories.count - 1 {
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
    }

    // Removed custom timeSpentSection() method -> now using activitySection()

    @ViewBuilder
    private func activityDestination(for category: ActivityInteractionCategory) -> some View {
        switch category {
        case .archived:
            ArchivedMomentsView()
        case .storiesArchive:
            ArchiveView(embedInNavigation: false, showsCustomDismiss: false)
        case .timeSpent:
            TimeSpentDetailsView()
        case .searches:
            SearchHistoryActivityView()
        case .accountHistory:
            AccountHistoryActivityView()
        default:
            ActivityInteractionDetailView(category: category)
        }
    }
}

struct ArchivedMomentsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigateToStoriesArchive = false
    
    private var archivedMomentsHeaderTitle: String {
        NSLocalizedString("userActivity.simple.item.archived.headerTitle", comment: "Archived moments header title")
    }
    
    private var archivedStoriesHeaderTitle: String {
        NSLocalizedString("archivedStories.headerTitle", comment: "Archive Stories header title")
    }
    
    var body: some View {
        ActivityInteractionDetailView(category: .archived)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Label(archivedMomentsHeaderTitle, systemImage: "checkmark")
                        Button(archivedStoriesHeaderTitle) {
                            navigateToStoriesArchive = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(archivedMomentsHeaderTitle)
                                .font(.custom("Poppins-SemiBold", size: 17))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: ArchiveView(embedInNavigation: false, showsCustomDismiss: false),
                    isActive: $navigateToStoriesArchive
                ) {
                    EmptyView()
                }
                .hidden()
            )
    }
}

private enum ActivityInteractionCategory: String, CaseIterable, Identifiable {
    // Interactions
    case reactions
    case comments
    case tags
    case stickerReplies
    
    // Your Content
    case archived
    case storiesArchive
    case recentlyDeleted
    
    // History
    case echoes
    case followers
    case visits

    // Shared Content
    case moments
    case reels
    
    // Usage
    case timeSpent
    case searches
    case accountHistory

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .reactions: return "userActivity.simple.item.reactions.title"
        case .comments: return "userActivity.simple.item.comments.title"
        case .tags: return "userActivity.simple.item.tags.title"
        case .stickerReplies: return "userActivity.simple.item.stickers.title"
        case .archived: return "userActivity.simple.item.archived.title"
        case .storiesArchive: return "settings.sections.archivedStories"
        case .recentlyDeleted: return "userActivity.simple.item.recentlyDeleted.title"
        case .echoes: return "userActivity.simple.item.echoes.title"
        case .followers: return "userActivity.simple.item.followers.title"
        case .visits: return "userActivity.simple.item.visits.title"
        case .moments: return "userActivity.simple.item.moments"
        case .reels: return "userActivity.simple.item.reels"
        case .timeSpent: return "userActivity.timeSpent.rowTitle"
        case .searches: return "userActivity.recentSearches.title"
        case .accountHistory: return "userActivity.accountHistory.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .reactions: return "userActivity.simple.item.reactions.subtitle"
        case .comments: return "userActivity.simple.item.comments.subtitle"
        case .tags: return "userActivity.simple.item.tags.subtitle"
        case .stickerReplies: return "userActivity.simple.item.stickers.subtitle"
        case .archived: return "userActivity.simple.item.archived.subtitle"
        case .storiesArchive: return "settings.sections.archivedStories.subtitle"
        case .recentlyDeleted: return "userActivity.simple.item.recentlyDeleted.subtitle"
        case .echoes: return "userActivity.simple.item.echoes.subtitle"
        case .followers: return "userActivity.simple.item.followers.subtitle"
        case .visits: return "userActivity.simple.item.visits.subtitle"
        case .moments: return "userActivity.simple.item.moments.subtitle"
        case .reels: return "userActivity.simple.item.reels.subtitle"
        case .timeSpent: return "userActivity.timeSpent.rowSubtitle"
        case .searches: return "userActivity.recentSearches.subtitle"
        case .accountHistory: return "userActivity.accountHistory.subtitle"
        }
    }

    var icon: String {
        switch self {
        case .reactions: return "sparkles"
        case .comments: return "bubble.right.fill"
        case .tags: return "at"
        case .stickerReplies: return "face.smiling"
        case .archived: return "archivebox.fill"
        case .storiesArchive: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .recentlyDeleted: return "trash.fill"
        case .echoes: return "camera.aperture"
        case .followers: return "person.badge.plus"
        case .visits: return "eye.fill"
        case .moments: return "square.grid.2x2.fill"
        case .reels: return "play.square.stack.fill"
        case .timeSpent: return "clock.fill"
        case .searches: return "magnifyingglass"
        case .accountHistory: return "calendar.badge.clock"
        }
    }

    var emptyKey: String {
        switch self {
        case .reactions: return "userActivity.simple.empty.reactions"
        case .comments: return "userActivity.simple.empty.comments"
        case .tags: return "userActivity.simple.empty.tags"
        case .stickerReplies: return "userActivity.simple.empty.stickers"
        case .archived: return "userActivity.simple.empty.archived"
        case .storiesArchive: return "archivedStories.empty.title"
        case .recentlyDeleted: return "userActivity.simple.empty.recentlyDeleted"
        case .echoes: return "userActivity.simple.empty.echoes"
        case .followers: return "userActivity.simple.empty.followers"
        case .visits: return "userActivity.simple.empty.visits"
        case .moments: return "userActivity.simple.empty.moments"
        case .reels: return "userActivity.simple.empty.reels"
        case .searches: return "userActivity.recentSearches.empty"
        case .timeSpent, .accountHistory: return ""
        }
    }

    var accentColor: Color {
        switch self {
        case .reactions: return Color(hex: "F97316")   // naranja
        case .comments: return Color(hex: "4F46E5")   // indigo
        case .tags: return Color(hex: "8B5CF6")        // violeta
        case .stickerReplies: return Color(hex: "EC4899") // rosa
        case .archived: return Color(hex: "64748B")    // slate
        case .storiesArchive: return Color(hex: "0EA5E9") // sky
        case .recentlyDeleted: return Color(hex: "EF4444") // rojo
        case .echoes: return Color(hex: "3B82F6")      // azul
        case .followers: return Color(hex: "10B981")   // verde
        case .visits: return Color(hex: "F59E0B")      // ambar
        case .moments: return Color(hex: "0EA5E9")     // sky
        case .reels: return Color(hex: "8B5CF6")        // violeta
        case .timeSpent: return Color(hex: "8B5CF6")   // violeta
        case .searches: return Color(hex: "3B82F6")    // azul
        case .accountHistory: return Color(hex: "3B82F6")    // azul
        }
    }
}

private enum ReactionsSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .newest: return "userActivity.simple.filters.sort.newest"
        case .oldest: return "userActivity.simple.filters.sort.oldest"
        }
    }
}

private enum ReactionsDateFilter: String, CaseIterable, Identifiable {
    case all
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "userActivity.simple.filters.date.all"
        case .week: return "userActivity.simple.filters.date.week"
        case .month: return "userActivity.simple.filters.date.month"
        case .year: return "userActivity.simple.filters.date.year"
        case .custom: return "userActivity.simple.filters.date.custom"
        }
    }
}

private extension Moment {
    var hasVideoMedia: Bool {
        videoUrl != nil || mediaItems?.first?.type == .video
    }

    var parsedAspectRatioValue: Double? {
        guard let raw = aspectRatio?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        let separators = CharacterSet(charactersIn: ":/xX")
        let parts = raw.components(separatedBy: separators).filter { !$0.isEmpty }
        if parts.count == 2,
           let w = Double(parts[0]),
           let h = Double(parts[1]),
           h > 0 {
            return w / h
        }

        if let direct = Double(raw), direct > 0 {
            return direct
        }

        return nil
    }

    var isVerticalReelAspect: Bool {
        guard let ratio = parsedAspectRatioValue else { return false }
        let target = 9.0 / 16.0
        return abs(ratio - target) <= 0.05
    }

    var isReelCandidate: Bool {
        hasVideoMedia && isVerticalReelAspect
    }
}

private struct AnimatedReactionIcon: View {
    private let reactions = ReactionType.allCases.map { $0.icon }
    @State private var currentIndex = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var timer: Timer?

    var body: some View {
        Text(reactions[currentIndex])
            .font(.system(size: 22))
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 36, height: 36)
            .onAppear {
                guard timer == nil else { return }
                timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 0.6
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        currentIndex = (currentIndex + 1) % reactions.count
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            scale = 1.0
                            opacity = 1.0
                        }
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
}


private struct AnimatedCommentIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    private let bubbles = [
        "bubble.right",
        "bubble.right.fill",
        "bubble.left",
        "bubble.left.fill",
        "ellipsis.bubble",
        "ellipsis.bubble.fill",
    ]
    @State private var currentIndex = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: bubbles[currentIndex])
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 36, height: 36)
            .onAppear {
                guard timer == nil else { return }
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        scale = 0.7
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        currentIndex = (currentIndex + 1) % bubbles.count
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                            scale = 1.0
                            opacity = 1.0
                        }
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
}

private struct ActivityInteractionCategoryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: ActivityInteractionCategory
    let summary: ActivityCategorySummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                // Animated / static icon
                Group {
                    if category == .reactions {
                        AnimatedReactionIcon()
                    } else if category == .comments {
                        AnimatedCommentIcon()
                    } else {
                        Image(systemName: category.icon)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 36, height: 36)
                    }
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(NSLocalizedString(category.titleKey, comment: "Interaction category title"))
                            .font(.custom("Poppins-SemiBold", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        // Count badge
                        if let count = summary?.count, count > 0 {
                            Text("\(count)")
                                .font(.custom("Poppins-Bold", size: 11))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(category.accentColor)
                                )
                        }
                    }

                    Text(NSLocalizedString(category.subtitleKey, comment: "Interaction category subtitle"))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }

        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Strip Thumb Cell
private struct StripThumbCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let thumb: ThumbInfo
    @State private var generatedThumbnail: UIImage?
    @State private var isGenerating = false

    private let size: CGFloat = 52

    var body: some View {
        ScreenshotProtectedView(isProtected: thumb.isProtected) {
            ZStack {
                content
                    .blur(radius: thumb.canView ? 0 : 12)

                if !thumb.canView {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if !thumb.url.isEmpty, let url = URL(string: thumb.url) {
            // Static thumbnail (image or pre-generated video still)
            KFImage(url)
                .placeholder {
                    placeholder
                }
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
        } else if let videoUrl = thumb.videoUrl {
            // Video without thumbnail — generate on device
            ZStack {
                if let img = generatedThumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    placeholder
                        .onAppear { generateThumbnail(from: videoUrl) }
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(radius: 2)
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
            .frame(width: size, height: size)
    }

    private func generateThumbnail(from videoPath: String) {
        guard !isGenerating, generatedThumbnail == nil,
              let url = URL(string: videoPath) else { return }
        isGenerating = true
        DispatchQueue.global(qos: .utility).async {
            let asset = AVAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 200, height: 200)
            if let img = try? gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) {
                let ui = UIImage(cgImage: img)
                DispatchQueue.main.async {
                    generatedThumbnail = ui
                    isGenerating = false
                }
            } else {
                DispatchQueue.main.async { isGenerating = false }
            }
        }
    }
}

private struct ActivityInteractionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: ActivityInteractionCategory

    @StateObject private var viewModel: ActivityInteractionDetailViewModel
    @State private var reactionsSort: ReactionsSortOption = .newest
    @State private var reactionsDateFilter: ReactionsDateFilter = .all
    @State private var customDateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customDateTo: Date = Date()
    @State private var selectedAuthorId: String?
    @State private var showingAuthorFilterSheet = false
    @State private var selectedMomentForDetail: Moment?
    @State private var showingStories = false
    @State private var storiesUserId = ""
    @State private var selectedProfileUserIdForSheet: String?
    @State private var isSelectionMode = false
    @State private var selectedReactionIds: Set<String> = []
    @State private var selectedCommentIds: Set<String> = []
    @State private var selectedEventIds: Set<String> = []
    @State private var selectedEchoId: String?
    @State private var longPressActivatedItemId: String?
    @State private var isDeletingSelectedReactions = false
    @State private var isRemovingSelectedTags = false
    @State private var isDeletingSelectedComments = false
    @State private var isDeletingSelectedEvents = false

    init(category: ActivityInteractionCategory) {
        self.category = category
        _viewModel = StateObject(wrappedValue: ActivityInteractionDetailViewModel(category: category))
    }

    private var sectionHorizontalPadding: CGFloat { 8 }
    
    private var detailNavigationTitleKey: String {
        switch category {
        case .archived:
            return "userActivity.simple.item.archived.headerTitle"
        default:
            return category.titleKey
        }
    }
    
    private var selectionToolbarButtonTitle: String? {
        switch category {
        case .reactions, .comments, .tags, .stickerReplies, .recentlyDeleted:
            return isSelectionMode
                ? NSLocalizedString("savedMoments.cancel", comment: "Cancel")
                : NSLocalizedString("savedMoments.select", comment: "Select")
        case .archived:
            return isSelectionMode
                ? NSLocalizedString("savedMoments.cancel", comment: "Cancel")
                : nil
        default:
            return nil
        }
    }
    
    private func handleSelectionToolbarTap() {
        switch category {
        case .reactions, .comments, .tags, .stickerReplies:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedReactionIds.removeAll()
                    selectedCommentIds.removeAll()
                    selectedEventIds.removeAll()
                }
            }
        case .recentlyDeleted:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedReactionIds.removeAll()
                }
            }
        case .archived:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                isSelectionMode = false
                selectedReactionIds.removeAll()
            }
        default:
            break
        }
    }

    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()

            mainContent
        }
        .navigationTitle(NSLocalizedString(detailNavigationTitleKey, comment: "Interaction detail title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            navigationToolbar
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .onChange(of: filteredReactionItems.map(\.id)) { visibleIds in
            let validIds = Set(visibleIds)
            selectedReactionIds = Set(selectedReactionIds.filter { validIds.contains($0) })
        }
        .onChange(of: selectedReactionIds) { ids in
            if (category == .archived || category == .recentlyDeleted), isSelectionMode, ids.isEmpty {
                isSelectionMode = false
            }
        }
        .onChange(of: filteredCommentItems.map(\.id)) { visibleIds in
            let validIds = Set(visibleIds)
            selectedCommentIds = Set(selectedCommentIds.filter { validIds.contains($0) })
        }
        .onChange(of: filteredEventItems.map(\.id)) { visibleIds in
            let validIds = Set(visibleIds)
            selectedEventIds = Set(selectedEventIds.filter { validIds.contains($0) })
        }
        .safeAreaInset(edge: .bottom) {
            selectionBars
        }
        .sheet(isPresented: $showingAuthorFilterSheet) {
            AuthorFilterSheet(
                selectedAuthorId: $selectedAuthorId,
                availableAuthorIds: availableAuthorIds,
                authorUsernameMap: authorUsernameMap
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { selectedMomentForDetail != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMomentForDetail = nil
                }
            }
        )) {
            if let moment = selectedMomentForDetail {
                MomentDetailView(moment: moment)
            }
        }
        .sheet(isPresented: $showingStories) {
            StoriesView(startWithUserId: .constant(storiesUserId))
        }
        .sheet(isPresented: Binding(
            get: { selectedProfileUserIdForSheet != nil },
            set: { isPresented in
                if !isPresented {
                    selectedProfileUserIdForSheet = nil
                }
            }
        )) {
            if let userId = selectedProfileUserIdForSheet {
                UserProfileView(userId: userId)
            }
        }
        .fullScreenCover(item: Binding(
            get: { selectedEchoId.map { IdentifiableString(id: $0) } },
            set: { newVal in selectedEchoId = newVal?.id }
        )) { ident in
            EchoViewerUI(echoId: ident.id)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            ProgressView(NSLocalizedString("userActivity.loading", comment: "Loading activity"))
                .tint(Color(hex: "4F46E5"))
        } else if let errorMessage = viewModel.errorMessage {
            errorStateView(errorMessage: errorMessage)
        } else if category == .reactions || category == .tags || category == .recentlyDeleted || category == .archived {
            reactionsContent
        } else if category == .comments {
            commentsContent
        } else if category == .moments || category == .reels {
            momentsContent
        } else {
            eventsContent
        }
    }

    @ViewBuilder
    private func errorStateView(errorMessage: String) -> some View {
        let isOffline = errorMessage.localizedCaseInsensitiveContains("offline")
            || errorMessage.localizedCaseInsensitiveContains("internet")
            || errorMessage.localizedCaseInsensitiveContains("network")
            || errorMessage.localizedCaseInsensitiveContains("connection")
        let errorIcon = isOffline ? "📡" : "⚠️"
        let titleKey = isOffline
            ? "userActivity.error.offline.title"
            : "userActivity.error.generic.title"
        let subtitleKey = isOffline
            ? "userActivity.error.offline.subtitle"
            : "userActivity.error.generic.subtitle"

        VStack(spacing: 16) {
            Text(errorIcon)
                .font(.system(size: 48))

            VStack(spacing: 6) {
                Text(NSLocalizedString(titleKey, comment: "Error title"))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString(subtitleKey, comment: "Error subtitle"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { viewModel.reload() }) {
                Text(NSLocalizedString("userActivity.simple.retry", comment: "Retry activity load"))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: "007AFF")))
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        if let title = selectionToolbarButtonTitle {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(title) {
                    handleSelectionToolbarTap()
                }
                .font(.custom("Poppins-SemiBold", size: 14))
            }
        }
    }

    @ViewBuilder
    private var selectionBars: some View {
        if (category == .reactions || category == .tags), isSelectionMode {
            reactionsSelectionBar
        } else if category == .comments, isSelectionMode {
            commentsSelectionBar
        } else if category == .stickerReplies, isSelectionMode {
            eventsSelectionBar
        } else if category == .recentlyDeleted, isSelectionMode {
            recentlyDeletedSelectionBar
        } else if category == .archived, isSelectionMode {
            archivedSelectionBar
        }
    }

    private struct IdentifiableString: Identifiable {
        let id: String
    }

    private var reactionsContent: some View {
        VStack(spacing: 0) {
            reactionsFiltersBar

            if reactionsDateFilter == .custom {
                customDateRangeControls
            }

            reactionsGrid
        }
    }

    private var commentsContent: some View {
        VStack(spacing: 0) {
            reactionsFiltersBar

            if reactionsDateFilter == .custom {
                customDateRangeControls
            }

            commentsList
        }
    }

    private var momentsContent: some View {
        VStack(spacing: 0) {
            // Keep the same filters bar for consistency (Sort, and eventually Date)
            reactionsFiltersBar

            if reactionsDateFilter == .custom {
                customDateRangeControls
            }

            momentsGrid
        }
    }

    private var reactionsGrid: some View {
        GeometryReader { geometry in
            if filteredReactionItems.isEmpty {
                emptyState(textKey: category.emptyKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                let spacing: CGFloat = 2
                let totalSpacing: CGFloat = spacing * 2
                let side = floor((geometry.size.width - (sectionHorizontalPadding * 2) - totalSpacing) / 3)
                let columns = [
                    GridItem(.fixed(side), spacing: spacing),
                    GridItem(.fixed(side), spacing: spacing),
                    GridItem(.fixed(side), spacing: spacing)
                ]

                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(filteredReactionItems) { item in
                            ActivityReactionMomentCard(
                                item: item,
                                size: side,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedReactionIds.contains(item.id)
                            )
                            .frame(width: side, height: side)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                if longPressActivatedItemId == item.id {
                                    longPressActivatedItemId = nil
                                    return
                                }
                                if isSelectionMode {
                                    toggleSelection(for: item.id)
                                    return
                                }
                                guard item.canView, let moment = item.moment else { return }
                                selectedMomentForDetail = moment
                            }
                            .onLongPressGesture(minimumDuration: 0.3) {
                                guard category == .archived || category == .recentlyDeleted else { return }
                                longPressActivatedItemId = item.id
                                if !isSelectionMode {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                        isSelectionMode = true
                                    }
                                }
                                selectedReactionIds.insert(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, isSelectionMode ? 88 : 12)
                }
            }
        }
    }

    private var momentsGrid: some View {
        GeometryReader { geometry in
            if filteredMoments.isEmpty {
                emptyState(textKey: category.emptyKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                let spacing: CGFloat = 2
                let totalSpacing: CGFloat = spacing * 2
                let side = floor((geometry.size.width - (sectionHorizontalPadding * 2) - totalSpacing) / 3)
                let columns = [
                    GridItem(.fixed(side), spacing: spacing),
                    GridItem(.fixed(side), spacing: spacing),
                    GridItem(.fixed(side), spacing: spacing)
                ]

                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(filteredMoments) { moment in
                            ScreenshotProtectedView(isProtected: (moment.audience?.lowercased() ?? "") != "everyone") {
                                ModernMomentThumbnail(
                                    moment: moment,
                                    size: side,
                                    customListNamesById: viewModel.customListNamesById,
                                    onTap: {
                                        selectedMomentForDetail = moment
                                    }
                                )
                                .frame(width: side, height: side)
                            }
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var commentsList: some View {
        Group {
            if filteredCommentItems.isEmpty {
                emptyState(textKey: category.emptyKey)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredCommentItems) { item in
                            ActivityCommentItemRow(
                                item: item,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedCommentIds.contains(item.id),
                                onOpenMoment: {
                                    guard item.canView, let moment = item.moment else { return }
                                    selectedMomentForDetail = moment
                                },
                                onOpenAuthorAvatar: { hasStory in
                                    openAuthor(authorId: item.authorId, hasStory: hasStory)
                                },
                                onOpenAuthorProfile: {
                                    openAuthor(authorId: item.authorId, hasStory: false)
                                },
                                onToggleSelection: {
                                    toggleCommentSelection(for: item.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, isSelectionMode ? 88 : 16)
                }
            }
        }
    }

    private var filteredReactionItems: [ActivityReactionItem] {
        let filteredByDate = viewModel.reactionItems.filter { item in
            switch reactionsDateFilter {
            case .all:
                return true
            case .week:
                let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                return item.reactedAt >= from
            case .month:
                let from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
                return item.reactedAt >= from
            case .year:
                let from = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
                return item.reactedAt >= from
            case .custom:
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
                let endBase = max(customDateFrom, customDateTo)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase
                return item.reactedAt >= start && item.reactedAt <= end
            }
        }

        let authorFiltered: [ActivityReactionItem]
        if supportsAuthorFilter {
            authorFiltered = filteredByDate.filter { item in
                guard let selectedAuthorId, !selectedAuthorId.isEmpty else { return true }
                return item.authorId == selectedAuthorId
            }
        } else {
            authorFiltered = filteredByDate
        }

        switch reactionsSort {
        case .newest:
            return authorFiltered.sorted { $0.reactedAt > $1.reactedAt }
        case .oldest:
            return authorFiltered.sorted { $0.reactedAt < $1.reactedAt }
        }
    }

    private var filteredCommentItems: [ActivityCommentItem] {
        let filteredByDate = viewModel.commentItems.filter { item in
            switch reactionsDateFilter {
            case .all:
                return true
            case .week:
                let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                return item.commentedAt >= from
            case .month:
                let from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
                return item.commentedAt >= from
            case .year:
                let from = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
                return item.commentedAt >= from
            case .custom:
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
                let endBase = max(customDateFrom, customDateTo)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase
                return item.commentedAt >= start && item.commentedAt <= end
            }
        }

        let authorFiltered = filteredByDate.filter { item in
            guard let selectedAuthorId, !selectedAuthorId.isEmpty else { return true }
            return item.authorId == selectedAuthorId
        }

        switch reactionsSort {
        case .newest:
            return authorFiltered.sorted { $0.commentedAt > $1.commentedAt }
        case .oldest:
            return authorFiltered.sorted { $0.commentedAt < $1.commentedAt }
        }
    }

    private var filteredMoments: [Moment] {
        let filteredByDate = viewModel.moments.filter { moment in
            let date = moment.timestamp
            switch reactionsDateFilter {
            case .all:
                return true
            case .week:
                let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                return date >= from
            case .month:
                let from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
                return date >= from
            case .year:
                let from = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
                return date >= from
            case .custom:
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
                let endBase = max(customDateFrom, customDateTo)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase
                return date >= start && date <= end
            }
        }

        switch reactionsSort {
        case .newest:
            return filteredByDate.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return filteredByDate.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private var availableAuthorIds: [String] {
        let usernames = authorUsernameMap
        let sourceAuthorIds: [String] = {
            switch category {
            case .reactions, .tags:
                return viewModel.reactionItems.map { $0.authorId }
            case .comments:
                return viewModel.commentItems.map { $0.authorId }
            case .stickerReplies:
                return viewModel.events.compactMap { $0.targetAuthorId }
            default:
                return []
            }
        }()

        let set = Set(
            sourceAuthorIds
                .filter { authorId in
                    guard !authorId.isEmpty else { return false }
                    guard let username = usernames[authorId] else { return false }
                    return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        )

        return Array(set).sorted { lhs, rhs in
            let lhsName = usernames[lhs] ?? ""
            let rhsName = usernames[rhs] ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private var authorUsernameMap: [String: String] {
        var map: [String: String] = [:]
        switch category {
        case .reactions, .tags:
            for item in viewModel.reactionItems {
                if map[item.authorId] == nil,
                   let username = item.moment?.username,
                   !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    map[item.authorId] = username
                }
            }
        case .comments:
            for item in viewModel.commentItems {
                if map[item.authorId] == nil,
                   let username = item.moment?.username,
                   !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    map[item.authorId] = username
                }
            }
        case .stickerReplies:
            for item in viewModel.events {
                guard let authorId = item.targetAuthorId, !authorId.isEmpty else { continue }
                if map[authorId] == nil,
                   let username = item.targetUsername,
                   !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    map[authorId] = username
                }
            }
        default:
            break
        }
        return map
    }

    private var reactionsFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(ReactionsSortOption.allCases) { option in
                        Button {
                            reactionsSort = option
                        } label: {
                            HStack {
                                Text(NSLocalizedString(option.titleKey, comment: "Reactions sort option"))
                                if reactionsSort == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.sort", comment: "Sort filter title"),
                        value: NSLocalizedString(reactionsSort.titleKey, comment: "Selected sort option")
                    )
                }

                Menu {
                    ForEach(ReactionsDateFilter.allCases) { option in
                        Button {
                            reactionsDateFilter = option
                        } label: {
                            HStack {
                                Text(NSLocalizedString(option.titleKey, comment: "Reactions date filter option"))
                                if reactionsDateFilter == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.date", comment: "Date filter title"),
                        value: NSLocalizedString(reactionsDateFilter.titleKey, comment: "Selected date filter")
                    )
                }

                if supportsAuthorFilter {
                    Button {
                        showingAuthorFilterSheet = true
                    } label: {
                        filterChip(
                            title: NSLocalizedString("userActivity.simple.filters.author", comment: "Author filter title"),
                            value: selectedAuthorLabel
                        )
                    }
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    private var supportsAuthorFilter: Bool {
        switch category {
        case .reactions, .comments, .tags, .stickerReplies:
            return true
        default:
            return false
        }
    }

    private var selectedAuthorLabel: String {
        guard let selectedAuthorId, !selectedAuthorId.isEmpty else {
            return NSLocalizedString("userActivity.simple.filters.author", comment: "Author filter title")
        }

        if let username = authorUsernameMap[selectedAuthorId], !username.isEmpty {
            return username
        }
        return NSLocalizedString("onlineStatus.unknown", comment: "Unknown")
    }

    private func filterChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(.gray)
            Text(value)
                .font(.custom("Poppins-SemiBold", size: 12))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var customDateRangeControls: some View {
        HStack(spacing: 8) {
            DatePicker(
                NSLocalizedString("userActivity.simple.filters.from", comment: "From date"),
                selection: $customDateFrom,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            )

            DatePicker(
                NSLocalizedString("userActivity.simple.filters.to", comment: "To date"),
                selection: $customDateTo,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .padding(.bottom, 6)
    }

    private var eventsContent: some View {
        VStack(spacing: 0) {
            reactionsFiltersBar

            if reactionsDateFilter == .custom {
                customDateRangeControls
            }

            if category == .echoes {
                echoesSummaryHeader
            }

            eventsList
        }
    }

    private var eventsList: some View {
        Group {
            if filteredEventItems.isEmpty {
                emptyState(textKey: category.emptyKey)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredEventItems) { item in
                            Button {
                                if isSelectionMode {
                                    toggleEventSelection(for: item.id)
                                }
                            } label: {
                                ActivityEventRow(
                                    item: item,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedEventIds.contains(item.id),
                                    onOpenTargetProfile: {
                                        guard let authorId = item.targetAuthorId, !authorId.isEmpty else { return }
                                        openAuthor(authorId: authorId, hasStory: false)
                                    },
                                    onRowTap: {
                                        if isSelectionMode {
                                            toggleEventSelection(for: item.id)
                                        } else {
                                            handleEventTap(item)
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, isSelectionMode ? 88 : 20)
                }
            }
        }
    }

    private var filteredEventItems: [ActivityEventItem] {
        let filteredByDate = viewModel.events.filter { item in
            switch reactionsDateFilter {
            case .all:
                return true
            case .week:
                let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                return item.timestamp >= from
            case .month:
                let from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
                return item.timestamp >= from
            case .year:
                let from = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
                return item.timestamp >= from
            case .custom:
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
                let endBase = max(customDateFrom, customDateTo)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase
                return item.timestamp >= start && item.timestamp <= end
            }
        }

        let authorFiltered = filteredByDate.filter { item in
            guard let selectedAuthorId, !selectedAuthorId.isEmpty else { return true }
            return item.targetAuthorId == selectedAuthorId
        }

        switch reactionsSort {
        case .newest:
            return authorFiltered.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return authorFiltered.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private var echoesSummaryHeader: some View {
        HStack(spacing: 10) {
            echoesInfoChip(icon: "waveform.path.ecg", text: "\(viewModel.events.count) Echoes")
            echoesInfoChip(icon: "dot.radiowaves.left.and.right", text: "\(activeEchoesCount) active")
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var activeEchoesCount: Int {
        viewModel.events.filter { $0.echoStatusRaw?.lowercased() == EchoStatus.active.rawValue }.count
    }

    private func echoesInfoChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.custom("Poppins-SemiBold", size: 11))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.06))
        )
    }

    private func handleEventTap(_ item: ActivityEventItem) {
        switch item.kind {
        case "echo":
            if let echoId = item.sourceId {
                selectedEchoId = echoId
            }
        case "follower", "visit":
            if let actorId = item.actorId {
                selectedProfileUserIdForSheet = actorId
            }
        case "sticker_reply", "poll", "question":
             // Handle if needed, or default to profile
             if let actorId = item.actorId {
                 selectedProfileUserIdForSheet = actorId
             }
        default:
            break
        }
    }

    private func emptyState(textKey: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(.gray.opacity(0.7))

            Text(NSLocalizedString(textKey, comment: "Empty state text"))
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.gray)
        }
    }

    private var archivedSelectionBar: some View {
        let selectedCount = selectedReactionIds.count
        let countText = String(format: NSLocalizedString("userActivity.simple.reactions.selectedCount", comment: "Selected items count"), selectedCount)

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(countText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await viewModel.unarchiveSelection(withIds: selectedReactionIds)
                            await MainActor.run {
                                if case .success = result {
                                    selectedReactionIds.removeAll()
                                    isSelectionMode = false
                                }
                            }
                        }
                    } label: {
                        Text(NSLocalizedString("userActivity.event.archived.action.restore", comment: "Restore action"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(Color(hex: "4F46E5"))
                    }
                    .disabled(selectedCount == 0 || viewModel.isLoading)
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: -5)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var recentlyDeletedSelectionBar: some View {
        let selectedCount = selectedReactionIds.count
        let countText = String(format: NSLocalizedString("userActivity.simple.reactions.selectedCount", comment: "Selected items count"), selectedCount)

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(countText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await viewModel.restoreSelection(withIds: selectedReactionIds)
                            await MainActor.run {
                                if case .success = result {
                                    selectedReactionIds.removeAll()
                                    isSelectionMode = false
                                }
                            }
                        }
                    } label: {
                        Text(NSLocalizedString("userActivity.simple.recentlyDeleted.restore.single", comment: "Restore action"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(Color(hex: "4F46E5"))
                    }
                    .disabled(selectedCount == 0 || viewModel.isLoading)

                    Button {
                        Task {
                            let result = await viewModel.permanentlyDeleteSelection(withIds: selectedReactionIds)
                            await MainActor.run {
                                if case .success = result {
                                    selectedReactionIds.removeAll()
                                    isSelectionMode = false
                                }
                            }
                        }
                    } label: {
                        Text(NSLocalizedString("userActivity.simple.recentlyDeleted.delete.single", comment: "Delete action"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(.red)
                    }
                    .disabled(selectedCount == 0 || viewModel.isLoading)
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, y: -5)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var reactionsSelectionBar: some View {
        let selectedCount = selectedReactionIds.count
        let isTagsCategory = (category == .tags)
        let countText = isTagsCategory
            ? String(format: NSLocalizedString("userActivity.simple.tags.selectedCount", comment: "Selected tagged moments count"), selectedCount)
            : String(format: NSLocalizedString("userActivity.simple.reactions.selectedCount", comment: "Selected reactions count"), selectedCount)

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(countText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    Task {
                        if isTagsCategory {
                            await removeSelectedTags()
                        } else {
                            await deleteSelectedReactions()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isTagsCategory ? isRemovingSelectedTags : isDeletingSelectedReactions {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: isTagsCategory ? "tag.slash.fill" : "heart.slash.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text(isTagsCategory
                             ? (selectedCount == 1
                                ? NSLocalizedString("userActivity.simple.tags.remove.single", comment: "Remove one tag")
                                : NSLocalizedString("userActivity.simple.tags.remove.multiple", comment: "Remove multiple tags"))
                             : (selectedCount == 1
                                ? NSLocalizedString("userActivity.simple.reactions.delete.single", comment: "Delete one reaction")
                                : NSLocalizedString("userActivity.simple.reactions.delete.multiple", comment: "Delete multiple reactions")))
                            .font(.custom("Poppins-SemiBold", size: 13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red.opacity(selectedCount > 0 ? 0.9 : 0.45)))
                }
                .disabled(selectedCount == 0 || (isTagsCategory ? isRemovingSelectedTags : isDeletingSelectedReactions))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var commentsSelectionBar: some View {
        let selectedCount = selectedCommentIds.count

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(String(format: NSLocalizedString("userActivity.simple.comments.selectedCount", comment: "Selected comments count"), selectedCount))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    Task {
                        await deleteSelectedComments()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isDeletingSelectedComments {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text(selectedCount == 1
                             ? NSLocalizedString("userActivity.simple.comments.delete.single", comment: "Delete one comment")
                             : NSLocalizedString("userActivity.simple.comments.delete.multiple", comment: "Delete multiple comments"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red.opacity(selectedCount > 0 ? 0.9 : 0.45)))
                }
                .disabled(selectedCount == 0 || isDeletingSelectedComments)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var eventsSelectionBar: some View {
        let selectedCount = selectedEventIds.count

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.custom("Poppins-Bold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(String(format: NSLocalizedString("userActivity.simple.stickers.selectedCount", comment: "Selected sticker replies count"), selectedCount))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    Task { await deleteSelectedEvents() }
                } label: {
                    HStack(spacing: 6) {
                        if isDeletingSelectedEvents {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text(selectedCount == 1
                             ? NSLocalizedString("userActivity.simple.stickers.delete.single", comment: "Delete one sticker reply")
                             : NSLocalizedString("userActivity.simple.stickers.delete.multiple", comment: "Delete multiple sticker replies"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red.opacity(selectedCount > 0 ? 0.9 : 0.45)))
                }
                .disabled(selectedCount == 0 || isDeletingSelectedEvents)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func toggleSelection(for reactionId: String) {
        if selectedReactionIds.contains(reactionId) {
            selectedReactionIds.remove(reactionId)
        } else {
            selectedReactionIds.insert(reactionId)
        }
    }

    private func toggleCommentSelection(for commentId: String) {
        if selectedCommentIds.contains(commentId) {
            selectedCommentIds.remove(commentId)
        } else {
            selectedCommentIds.insert(commentId)
        }
    }

    private func toggleEventSelection(for eventId: String) {
        if selectedEventIds.contains(eventId) {
            selectedEventIds.remove(eventId)
        } else {
            selectedEventIds.insert(eventId)
        }
    }

    private func openAuthor(authorId: String, hasStory: Bool) {
        guard !authorId.isEmpty else { return }
        if hasStory {
            storiesUserId = authorId
            showingStories = true
        } else {
            selectedProfileUserIdForSheet = authorId
        }
    }

    private func deleteSelectedReactions() async {
        guard !selectedReactionIds.isEmpty else { return }
        isDeletingSelectedReactions = true
        let idsToDelete = selectedReactionIds

        let result = await viewModel.removeReactions(withIds: idsToDelete)

        await MainActor.run {
            isDeletingSelectedReactions = false
            switch result {
            case .success:
                selectedReactionIds.removeAll()
                isSelectionMode = false
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func removeSelectedTags() async {
        guard !selectedReactionIds.isEmpty else { return }
        isRemovingSelectedTags = true
        let idsToRemove = selectedReactionIds

        let result = await viewModel.removeTags(withIds: idsToRemove)

        await MainActor.run {
            isRemovingSelectedTags = false
            switch result {
            case .success:
                selectedReactionIds.removeAll()
                isSelectionMode = false
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelectedComments() async {
        guard !selectedCommentIds.isEmpty else { return }
        isDeletingSelectedComments = true
        let idsToDelete = selectedCommentIds

        let result = await viewModel.removeComments(withIds: idsToDelete)

        await MainActor.run {
            isDeletingSelectedComments = false
            switch result {
            case .success:
                selectedCommentIds.removeAll()
                isSelectionMode = false
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelectedEvents() async {
        guard !selectedEventIds.isEmpty else { return }
        isDeletingSelectedEvents = true
        let idsToDelete = selectedEventIds

        let result = await viewModel.removeStickerReplies(withIds: idsToDelete)

        await MainActor.run {
            isDeletingSelectedEvents = false
            switch result {
            case .success:
                selectedEventIds.removeAll()
                isSelectionMode = false
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AuthorFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedAuthorId: String?
    let availableAuthorIds: [String]
    let authorUsernameMap: [String: String]
    @State private var searchText: String = ""

    private var filteredAuthorIds: [String] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return availableAuthorIds }

        return availableAuthorIds.filter { authorId in
            if let username = authorUsernameMap[authorId], username.lowercased().contains(term) {
                return true
            }
            return false
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredAuthorIds, id: \.self) { authorId in
                    Button {
                        selectedAuthorId = (selectedAuthorId == authorId) ? nil : authorId
                        dismiss()
                    } label: {
                        HStack {
                            StoryRingAvatarView(userId: authorId, size: 36, lineWidth: 2.3)

                            Text(authorUsernameMap[authorId] ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Spacer()
                            if selectedAuthorId == authorId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "4F46E5"))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("userActivity.simple.filters.author.sheet.title", comment: "Author filter sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("userActivity.simple.filters.author.search", comment: "Search author filter")
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.close", comment: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ActivityCommentItemRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityCommentItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onOpenMoment: () -> Void
    let onOpenAuthorAvatar: (Bool) -> Void
    let onOpenAuthorProfile: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isSelectionMode {
                    ActivityCommentMomentPreview(moment: item.moment, canView: item.canView, size: 84)
                } else {
                    Button(action: onOpenMoment) {
                        ActivityCommentMomentPreview(moment: item.moment, canView: item.canView, size: 84)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isSelectionMode {
                        Text(item.moment?.username ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                    } else {
                        Button(action: onOpenAuthorProfile) {
                            Text(item.moment?.username ?? NSLocalizedString("onlineStatus.unknown", comment: "Unknown"))
                                .font(.custom("Poppins-SemiBold", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }

                    if !item.canView {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if isSelectionMode {
                        StoryRingAvatarView(
                            userId: item.authorId,
                            size: 30,
                            lineWidth: 2.2
                        )
                    } else {
                        StoryRingAvatarView(
                            userId: item.authorId,
                            size: 30,
                            lineWidth: 2.2,
                            onTap: { hasStory in
                                onOpenAuthorAvatar(hasStory)
                            }
                        )
                    }
                }

                Text(item.moment?.content.isEmpty == false
                     ? (item.moment?.content ?? "")
                     : NSLocalizedString("userActivity.simple.comments.momentNoContent", comment: "Moment without content"))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(2)

                Text(NSLocalizedString("userActivity.simple.comments.yourComment", comment: "Your comment label"))
                    .font(.custom("Poppins-SemiBold", size: 11))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.82))

                Text(item.commentText.isEmpty
                     ? NSLocalizedString("userActivity.simple.comments.emptyComment", comment: "Empty comment fallback")
                     : item.commentText)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(3)

                Text(item.commentedAt.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray.opacity(0.85))
            }

            Spacer(minLength: 0)

            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color(hex: "2563EB") : Color.clear, lineWidth: 1.6)
                )
        )
    }
}

private struct ActivityCommentMomentPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let moment: Moment?
    let canView: Bool
    let size: CGFloat
    @State private var generatedVideoThumbnail: UIImage?
    @State private var isGeneratingThumbnail = false

    var body: some View {
        ScreenshotProtectedView(isProtected: isProtectedMoment(moment)) {
            ZStack {
                if let moment {
                    preview(for: moment)
                } else {
                    placeholder
                }

                if !canView {
                    restrictedOverlay
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func isProtectedMoment(_ moment: Moment?) -> Bool {
        guard let audience = moment?.audience?.lowercased() else { return false }
        return audience != "everyone"
    }

    @ViewBuilder
    private func preview(for moment: Moment) -> some View {
        if let media = moment.mediaItems?.first {
            if media.type == .image {
                mediaImage(urlString: media.url)
            } else {
                mediaVideoPreview(videoURL: media.url, thumbnailURL: media.thumbnailUrl ?? moment.thumbnailUrl)
            }
        } else if let imagePath = moment.imagePath, !imagePath.isEmpty {
            mediaImage(urlString: imagePath)
        } else if let video = moment.videoUrl, !video.isEmpty {
            mediaVideoPreview(videoURL: video, thumbnailURL: moment.thumbnailUrl)
        } else {
            placeholder
        }
    }

    private func mediaImage(urlString: String) -> some View {
        KFImage(URL(string: urlString))
            .placeholder { placeholder }
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }

    private func mediaVideoPreview(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, !thumb.isEmpty {
                KFImage(URL(string: thumb))
                    .placeholder { placeholder }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else if let generatedVideoThumbnail {
                Image(uiImage: generatedVideoThumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                placeholder
                    .onAppear {
                        generateThumbnail(for: videoURL)
                    }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .shadow(radius: 3)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.gray)
        }
    }

    private var restrictedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                )

            VStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(NSLocalizedString("savedMoments.restricted.title", comment: "Saved moment restricted title"))
                    .font(.custom("Poppins-SemiBold", size: 8))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("savedMoments.restricted.subtitle", comment: "Saved moment restricted subtitle"))
                    .font(.custom("Poppins-Regular", size: 7))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
        }
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil, let videoURL = URL(string: videoPath) else { return }
        isGeneratingThumbnail = true

        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 500, height: 500)

            do {
                let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.8, preferredTimescale: 600), actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.generatedVideoThumbnail = thumbnail
                    self.isGeneratingThumbnail = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGeneratingThumbnail = false
                }
            }
        }
    }
}

private struct ActivityEventRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityEventItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onOpenTargetProfile: () -> Void
    let onRowTap: (() -> Void)?

    var body: some View {
        Group {
            if item.kind?.lowercased() == "echo" {
                echoCardContent
            } else {
                HStack(alignment: .top, spacing: 12) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        if let actionText = item.actionText, !actionText.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(item.title)
                                    .font(.custom("Poppins-SemiBold", size: 15))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                                Text(actionText)
                                    .font(.custom("Poppins-Regular", size: 12))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(item.title)
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        HStack(spacing: 6) {
                            Text(item.timestamp.timeAgoDisplay())
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(.gray.opacity(0.85))

                            if hasContext {
                                Text("•")
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.gray.opacity(0.7))

                                if let username = item.targetUsername,
                                   !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(contextPrefix)
                                        .font(.custom("Poppins-Regular", size: 11))
                                        .foregroundColor(.gray.opacity(0.85))

                                    Button {
                                        onOpenTargetProfile()
                                    } label: {
                                        Text(username)
                                            .font(.custom("Poppins-SemiBold", size: 11))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                } else if let context = item.contextText, !context.isEmpty {
                                    Text(context)
                                        .font(.custom("Poppins-Regular", size: 11))
                                        .foregroundColor(.gray.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    if let thumbUrl = item.thumbnailUrl, !thumbUrl.isEmpty {
                        KFImage(URL(string: thumbUrl))
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.trailing, 4)
                    }

                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? Color(hex: "2563EB") : .gray.opacity(0.8))
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onRowTap?()
            } else {
                onRowTap?()
            }
        }
    }

    private var echoCardContent: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumbUrl = item.thumbnailUrl,
                   !thumbUrl.isEmpty,
                   let url = URL(string: thumbUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .frame(width: 56, height: 56)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(participantsText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(expiresLabel)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.14), Color.white.opacity(0.06)]
                            : [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .padding(.vertical, 1)
    }

    private var statusColor: Color {
        switch item.echoStatusRaw?.lowercased() {
        case EchoStatus.pending.rawValue:
            return .orange
        case EchoStatus.active.rawValue:
            return .green
        case EchoStatus.completed.rawValue:
            return .purple
        default:
            return .gray
        }
    }

    private var statusText: String {
        switch item.echoStatusRaw?.lowercased() {
        case EchoStatus.pending.rawValue:
            return NSLocalizedString("echo.status.pending", comment: "")
        case EchoStatus.active.rawValue:
            return NSLocalizedString("echo.status.active", comment: "")
        case EchoStatus.completed.rawValue:
            return NSLocalizedString("echo.status.completed", comment: "")
        default:
            return NSLocalizedString("echo.status.expired", comment: "")
        }
    }

    private var participantsText: String {
        let count = max(item.echoParticipantsCount ?? 0, 0)
        let format = count == 1 ? "echo.participants.singular" : "echo.participants.plural"
        return String(format: NSLocalizedString(format, comment: ""), count)
    }

    private var expiresLabel: String {
        guard let expiresAt = item.echoExpiresAt else {
            return item.timestamp.timeAgoDisplay()
        }

        if expiresAt <= Date() {
            return NSLocalizedString("echo.status.expired", comment: "")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: expiresAt, relativeTo: Date())
    }

    private var hasContext: Bool {
        if let username = item.targetUsername, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let context = item.contextText, !context.isEmpty {
            return true
        }
        return false
    }

    private var contextPrefix: String {
        switch item.kind?.lowercased() {
        case "poll":
            return NSLocalizedString("userActivity.simple.stickers.poll.contextPrefix", comment: "Poll context prefix")
        case "question":
            return NSLocalizedString("userActivity.simple.stickers.question.contextPrefix", comment: "Question context prefix")
        default:
            return ""
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let path = item.actorProfileImagePath,
           !path.isEmpty,
           let url = URL(string: path) {
            KFImage(url)
                .placeholder {
                    fallbackAvatar
                }
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else if let userId = item.actorId, !userId.isEmpty {
            AsyncProfileImageView(userId: userId)
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "4F46E5").opacity(0.13))
                .frame(width: 34, height: 34)

            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "4F46E5"))
        }
    }
}

private struct ActivityReactionMomentCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ActivityReactionItem
    let size: CGFloat
    let isSelectionMode: Bool
    let isSelected: Bool
    @State private var generatedVideoThumbnail: UIImage?
    @State private var isGeneratingThumbnail = false

    var body: some View {
        ScreenshotProtectedView(isProtected: isProtectedMoment(item.moment)) {
            ZStack(alignment: .topLeading) {
                cardPreview
                    .frame(width: size, height: size)
                    .blur(radius: item.canView ? 0 : 16)
                    .clipped()

                if !item.canView {
                    restrictedOverlay
                }

                if item.reactionType == "moment" || item.reactionType == "reel" || item.reactionType == "archived" || item.reactionType == "recentlyDeleted" {
                    audienceBadge
                        .padding(6)
                } else {
                    reactionBadge
                        .padding(6)
                }

                if isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(isSelected ? Color(hex: "2563EB") : .white.opacity(0.92))
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func isProtectedMoment(_ moment: Moment?) -> Bool {
        guard let audience = moment?.audience?.lowercased() else { return false }
        return audience != "everyone"
    }

    @ViewBuilder
    private var cardPreview: some View {
        if let moment = item.moment {
            preview(for: moment)
        } else {
            ZStack {
                Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.gray)
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func preview(for moment: Moment) -> some View {
        if let media = moment.mediaItems?.first {
            if media.type == .image {
                mediaImage(urlString: media.url)
            } else {
                mediaVideoPreview(videoURL: media.url, thumbnailURL: media.thumbnailUrl ?? moment.thumbnailUrl)
            }
        } else if let imagePath = moment.imagePath, !imagePath.isEmpty {
            mediaImage(urlString: imagePath)
        } else if let video = moment.videoUrl, !video.isEmpty {
            mediaVideoPreview(videoURL: video, thumbnailURL: moment.thumbnailUrl)
        } else {
            videoPlaceholder
        }
    }

    private func mediaImage(urlString: String) -> some View {
        KFImage(URL(string: urlString))
            .placeholder {
                Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            }
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }

    private func mediaVideoPreview(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, !thumb.isEmpty {
                KFImage(URL(string: thumb))
                    .placeholder {
                        Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else if let generatedVideoThumbnail {
                Image(uiImage: generatedVideoThumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                videoPlaceholder
                    .onAppear {
                        generateThumbnail(for: videoURL)
                    }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 3)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var videoPlaceholder: some View {
        ZStack {
            Color(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08))
            Image(systemName: "video")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.gray)
        }
        .frame(width: size, height: size)
    }

    private func generateThumbnail(for videoPath: String) {
        guard !isGeneratingThumbnail, generatedVideoThumbnail == nil, let videoURL = URL(string: videoPath) else { return }
        isGeneratingThumbnail = true

        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 700, height: 700)

            do {
                let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.8, preferredTimescale: 600), actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.generatedVideoThumbnail = thumbnail
                    self.isGeneratingThumbnail = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isGeneratingThumbnail = false
                }
            }
        }
    }

    private var reactionBadge: some View {
        let style = reactionStyle(from: item.reactionType)

        return HStack(spacing: 4) {
            Text(style.icon)
                .font(.system(size: 13))

            Text(style.label)
                .font(.custom("Poppins-SemiBold", size: 10))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(style.color.opacity(0.88))
        )
    }

    private var restrictedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                )

            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(NSLocalizedString("savedMoments.restricted.title", comment: "Saved moment restricted title"))
                    .font(.custom("Poppins-SemiBold", size: 10))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("savedMoments.restricted.subtitle", comment: "Saved moment restricted subtitle"))
                    .font(.custom("Poppins-Regular", size: 9))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var audienceBadge: some View {
        guard let moment = item.moment else { return AnyView(EmptyView()) }
        
        let normalizedAudience = moment.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? "everyone"
            
        let icon: String
        let title: String
        let background: Color
        
        switch normalizedAudience {
        case "bestfriends", "bestfriend":
            icon = "heart.fill"
            title = NSLocalizedString("audience.type.bestFriends", comment: "")
            background = Color(hex: "24C26A").opacity(0.92)
        case "connections", "connection", "mutuals", "mutual":
            icon = "person.2.fill"
            title = NSLocalizedString("audience.type.connections", comment: "")
            background = Color(hex: "00B4D8").opacity(0.92)
        case "onlyme":
            icon = "lock.fill"
            title = NSLocalizedString("audience.type.onlyMe", comment: "")
            background = Color.black.opacity(0.78)
        default:
            icon = "globe"
            title = NSLocalizedString("audience.type.everyone", comment: "")
            background = Color(hex: "0EA5A3").opacity(0.9)
        }
        
        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 8))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
        )
    }

    private func reactionStyle(from rawValue: String) -> (icon: String, label: String, color: Color) {
        if rawValue.lowercased() == "tagged" {
            return ("🏷️", NSLocalizedString("profile.tab.tagged", comment: "Tagged tab"), Color(hex: "F59E0B"))
        }
        if let type = ReactionType(rawValue: rawValue) {
            return (type.icon, type.displayName, type.color)
        }

        let fallback = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            return ("✨", NSLocalizedString("userActivity.simple.reaction.unknown", comment: "Unknown reaction"), Color(hex: "4F46E5"))
        }

        return ("✨", fallback.capitalized, Color(hex: "4F46E5"))
    }
}

private struct ActivityReactionItem: Identifiable {
    let id: String
    let authorId: String
    let momentId: String
    let reactionType: String
    let reactedAt: Date
    let moment: Moment?
    let canView: Bool
}

private struct ActivityCommentItem: Identifiable {
    let id: String
    let authorId: String
    let momentId: String
    let commentId: String
    let commentText: String
    let commentedAt: Date
    let moment: Moment?
    let canView: Bool
}

private struct ActivityEventItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let timestamp: Date
    let icon: String
    let actorId: String?
    let actorUsername: String?
    let actorProfileImagePath: String?
    let actionText: String?
    let kind: String?
    let targetAuthorId: String?
    let targetUsername: String?
    let storyId: String?
    let sourceId: String?
    let contextText: String?
    let thumbnailUrl: String?
    let echoStatusRaw: String?
    let echoParticipantsCount: Int?
    let echoExpiresAt: Date?

    init(
        id: String,
        title: String,
        subtitle: String,
        timestamp: Date,
        icon: String,
        actorId: String? = nil,
        actorUsername: String? = nil,
        actorProfileImagePath: String? = nil,
        actionText: String? = nil,
        kind: String? = nil,
        targetAuthorId: String? = nil,
        targetUsername: String? = nil,
        storyId: String? = nil,
        sourceId: String? = nil,
        contextText: String? = nil,
        thumbnailUrl: String? = nil,
        echoStatusRaw: String? = nil,
        echoParticipantsCount: Int? = nil,
        echoExpiresAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.icon = icon
        self.actorId = actorId
        self.actorUsername = actorUsername
        self.actorProfileImagePath = actorProfileImagePath
        self.actionText = actionText
        self.kind = kind
        self.targetAuthorId = targetAuthorId
        self.targetUsername = targetUsername
        self.storyId = storyId
        self.sourceId = sourceId
        self.contextText = contextText
        self.thumbnailUrl = thumbnailUrl
        self.echoStatusRaw = echoStatusRaw
        self.echoParticipantsCount = echoParticipantsCount
        self.echoExpiresAt = echoExpiresAt
    }
}

// MARK: - Activity Cache (UserDefaults)

private struct CachedReactionPayload: Codable {
    let id: String
    let authorId: String
    let momentId: String
    let reactionType: String
    let reactedAt: Double
    let canView: Bool
    // Moment thumbnail fields
    var momentImagePath: String?
    var momentVideoUrl: String?
    var momentThumbnailUrl: String?
    var momentContent: String?
    var momentUsername: String?
    var momentAuthorId: String?
    var momentAudience: String?
}

private struct CachedCommentPayload: Codable {
    let id: String
    let authorId: String
    let momentId: String
    let commentId: String
    let commentText: String
    let commentedAt: Double
    let canView: Bool
    // Moment thumbnail fields
    var momentImagePath: String?
    var momentVideoUrl: String?
    var momentThumbnailUrl: String?
    var momentContent: String?
    var momentUsername: String?
    var momentAuthorId: String?
    var momentAudience: String?
}

private enum ActivityCache {
    private static func minimalMoment(from p: (imagePath: String?, videoUrl: String?, thumbnailUrl: String?, content: String?, username: String?, authorId: String?, id: String, audience: String?)) -> Moment {
        Moment(
            id: p.id,
            authorId: p.authorId ?? "",
            username: p.username ?? "",
            content: p.content ?? "",
            imagePath: p.imagePath,
            videoUrl: p.videoUrl,
            timestamp: Date(),
            reactions: [:],
            commentCount: 0,
            profileImagePath: nil,
            taggedUsers: nil,
            location: nil,
            audience: p.audience,
            mediaItems: nil,
            aspectRatio: nil,
            customListId: nil,
            thumbnailUrl: p.thumbnailUrl,
            videoDuration: nil,
            videoFileSize: nil,
            videoResolution: nil,
            disableComments: false,
            hideLikeCounts: false,
            allowSharing: true
        )
    }

    static func saveReactions(_ items: [ActivityReactionItem], userId: String) {
        let payloads = items.map { item -> CachedReactionPayload in
            CachedReactionPayload(
                id: item.id, authorId: item.authorId, momentId: item.momentId,
                reactionType: item.reactionType, reactedAt: item.reactedAt.timeIntervalSince1970,
                canView: item.canView,
                momentImagePath: item.moment?.imagePath,
                momentVideoUrl: item.moment?.videoUrl,
                momentThumbnailUrl: item.moment?.thumbnailUrl,
                momentContent: item.moment?.content,
                momentUsername: item.moment?.username,
                momentAuthorId: item.moment?.authorId,
                momentAudience: item.moment?.audience
            )
        }
        if let data = try? JSONEncoder().encode(payloads) {
            UserDefaults.standard.set(data, forKey: "activityCache_reactions_\(userId)")
        }
    }

    static func loadReactions(userId: String) -> [ActivityReactionItem] {
        guard let data = UserDefaults.standard.data(forKey: "activityCache_reactions_\(userId)"),
              let payloads = try? JSONDecoder().decode([CachedReactionPayload].self, from: data)
        else { return [] }
        return payloads.map { p in
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId, p.momentAudience))
            return ActivityReactionItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                reactionType: p.reactionType, reactedAt: Date(timeIntervalSince1970: p.reactedAt),
                moment: moment, canView: p.canView
            )
        }
    }

    static func saveComments(_ items: [ActivityCommentItem], userId: String) {
        let payloads = items.map { item -> CachedCommentPayload in
            CachedCommentPayload(
                id: item.id, authorId: item.authorId, momentId: item.momentId,
                commentId: item.commentId, commentText: item.commentText,
                commentedAt: item.commentedAt.timeIntervalSince1970, canView: item.canView,
                momentImagePath: item.moment?.imagePath,
                momentVideoUrl: item.moment?.videoUrl,
                momentThumbnailUrl: item.moment?.thumbnailUrl,
                momentContent: item.moment?.content,
                momentUsername: item.moment?.username,
                momentAuthorId: item.moment?.authorId,
                momentAudience: item.moment?.audience
            )
        }
        if let data = try? JSONEncoder().encode(payloads) {
            UserDefaults.standard.set(data, forKey: "activityCache_comments_\(userId)")
        }
    }

    static func loadComments(userId: String) -> [ActivityCommentItem] {
        guard let data = UserDefaults.standard.data(forKey: "activityCache_comments_\(userId)"),
              let payloads = try? JSONDecoder().decode([CachedCommentPayload].self, from: data)
        else { return [] }
        return payloads.map { p in
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId, p.momentAudience))
            return ActivityCommentItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                commentId: p.commentId, commentText: p.commentText,
                commentedAt: Date(timeIntervalSince1970: p.commentedAt),
                moment: moment, canView: p.canView
            )
        }
    }

    // MARK: Tags cache (same payload shape as reactions, separate key)
    static func saveRecentlyDeletedCount(_ count: Int, userId: String) {
        UserDefaults.standard.set(max(0, count), forKey: "activityCache_recentlyDeletedCount_\(userId)")
    }

    static func loadRecentlyDeletedCount(userId: String) -> Int {
        UserDefaults.standard.integer(forKey: "activityCache_recentlyDeletedCount_\(userId)")
    }

    static func saveTagged(_ items: [ActivityReactionItem], userId: String) {
        let payloads = items.map { item -> CachedReactionPayload in
            CachedReactionPayload(
                id: item.id, authorId: item.authorId, momentId: item.momentId,
                reactionType: item.reactionType, reactedAt: item.reactedAt.timeIntervalSince1970,
                canView: item.canView,
                momentImagePath: item.moment?.imagePath,
                momentVideoUrl: item.moment?.videoUrl,
                momentThumbnailUrl: item.moment?.thumbnailUrl,
                momentContent: item.moment?.content,
                momentUsername: item.moment?.username,
                momentAuthorId: item.moment?.authorId,
                momentAudience: item.moment?.audience
            )
        }
        if let data = try? JSONEncoder().encode(payloads) {
            UserDefaults.standard.set(data, forKey: "activityCache_tags_\(userId)")
        }
    }

    static func loadTagged(userId: String) -> [ActivityReactionItem] {
        guard let data = UserDefaults.standard.data(forKey: "activityCache_tags_\(userId)"),
              let payloads = try? JSONDecoder().decode([CachedReactionPayload].self, from: data)
        else { return [] }
        return payloads.map { p in
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId, p.momentAudience))
            return ActivityReactionItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                reactionType: p.reactionType, reactedAt: Date(timeIntervalSince1970: p.reactedAt),
                moment: moment, canView: p.canView
            )
        }
    }

    // MARK: Sticker replies summary cache (counter only)
    static func saveStickerReplyCount(_ count: Int, userId: String) {
        UserDefaults.standard.set(max(0, count), forKey: "activityCache_stickerCount_\(userId)")
    }

    static func loadStickerReplyCount(userId: String) -> Int {
        UserDefaults.standard.integer(forKey: "activityCache_stickerCount_\(userId)")
    }
}

// MARK: - Activity Summary (counters + previews for the main screen)

private struct ThumbInfo: Identifiable {
    let id: String           // thumbnail url (or videoUrl) used as id
    let url: String          // static thumbnail URL (image or video still)
    let videoUrl: String?    // set only for video moments without a static thumbnail
    let isProtected: Bool    // audience != "everyone" → ScreenshotProtectedView
    let canView: Bool        // false → blur + lock icon
}

private struct ActivityCategorySummary {
    let count: Int
    let thumbnails: [ThumbInfo]
}

private final class ActivitySummaryViewModel: ObservableObject {
    @Published var summaries: [ActivityInteractionCategory: ActivityCategorySummary] = [:]
    private var dummyVMs: [ActivityInteractionDetailViewModel] = []
    private var isRefreshing = false

    func autoRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        // Retain dummy ViewModels so their internal Tasks don't fail immediately due to [weak self] deallocation
        dummyVMs = [
            ActivityInteractionDetailViewModel(category: .reactions),
            ActivityInteractionDetailViewModel(category: .comments),
            ActivityInteractionDetailViewModel(category: .tags),
            ActivityInteractionDetailViewModel(category: .stickerReplies),
            ActivityInteractionDetailViewModel(category: .archived),
            ActivityInteractionDetailViewModel(category: .recentlyDeleted),
            ActivityInteractionDetailViewModel(category: .echoes),
            ActivityInteractionDetailViewModel(category: .followers),
            ActivityInteractionDetailViewModel(category: .visits),
            ActivityInteractionDetailViewModel(category: .moments),
            ActivityInteractionDetailViewModel(category: .reels)
        ]
        
        for vm in dummyVMs {
            vm.reload()
        }
        
        // Poll cache a couple of times as network requests complete, then clean up.
        // Keeps UI fresh without overloading reads.
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.load()
            self.load()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.load()
            DispatchQueue.main.async {
                self.dummyVMs = []
                self.isRefreshing = false
            }
        }
    }

    func load() {
        guard let userId = FirebaseAuth.Auth.auth().currentUser?.uid, !userId.isEmpty else { return }
        Task {
            let reactions = ActivityCache.loadReactions(userId: userId)
            let comments  = ActivityCache.loadComments(userId: userId)
            let tagged    = ActivityCache.loadTagged(userId: userId)
            let stickerRepliesCount = ActivityCache.loadStickerReplyCount(userId: userId)
            let db = Firestore.firestore()


            // ✅ NUEVA: Cargar conteos reales para categorías de historial
            async let echoesCount = await withCheckedContinuation { continuation in
                EchoService.shared.fetchEchoHistory(userId: userId) { echoes in
                    continuation.resume(returning: echoes.count)
                }
            }
            async let archivedCount = await withCheckedContinuation { continuation in
                FirestoreService.shared.fetchArchivedMoments(userId: userId) { result in
                    switch result {
                    case .success(let moments):
                        continuation.resume(returning: moments.count)
                    case .failure:
                        continuation.resume(returning: 0)
                    }
                }
            }
            async let followersCount = try? await db.collection("users").document(userId).collection("followers").getDocuments().count
            async let visitsCount = try? await db.collection("users").document(userId).collection("visits").getDocuments().count
            async let storiesArchiveCount = try? await db.collection("users")
                .document(userId)
                .collection("stories")
                .whereField("expirationDate", isLessThan: Date())
                .getDocuments()
                .count

            async let allMomentsResult = await withCheckedContinuation { (continuation: CheckedContinuation<[Moment], Never>) in
                FirestoreService.shared.fetchMoments(for: userId) { result in
                    switch result {
                    case .success(let moments):
                        continuation.resume(returning: moments)
                    case .failure:
                        continuation.resume(returning: [])
                    }
                }
            }
            
            let allMoments = await allMomentsResult
            let momentsCount = allMoments.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && !isReel
            }.count
            
            let reelsCount = allMoments.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && isReel
            }.count

            let result: [ActivityInteractionCategory: ActivityCategorySummary] = [
                .reactions: ActivityCategorySummary(count: reactions.count, thumbnails: []),
                .comments:  ActivityCategorySummary(count: comments.count,  thumbnails: []),
                .tags:      ActivityCategorySummary(count: tagged.count,    thumbnails: []),
                .stickerReplies: ActivityCategorySummary(count: stickerRepliesCount, thumbnails: []),
                .recentlyDeleted: ActivityCategorySummary(count: ActivityCache.loadRecentlyDeletedCount(userId: userId), thumbnails: []),
                .archived: ActivityCategorySummary(count: await archivedCount, thumbnails: []),
                .storiesArchive: ActivityCategorySummary(count: (await storiesArchiveCount) ?? 0, thumbnails: []),
                .echoes: ActivityCategorySummary(count: await echoesCount, thumbnails: []),
                .followers: ActivityCategorySummary(count: (try? await followersCount) ?? 0, thumbnails: []),
                .visits: ActivityCategorySummary(count: (try? await visitsCount) ?? 0, thumbnails: []),
                .moments: ActivityCategorySummary(count: momentsCount, thumbnails: []),
                .reels: ActivityCategorySummary(count: reelsCount, thumbnails: [])
            ]

            await MainActor.run {
                self.summaries = result
            }
        }
    }
}

private final class ActivityInteractionDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reactionItems: [ActivityReactionItem] = []
    @Published var commentItems: [ActivityCommentItem] = []
    @Published var events: [ActivityEventItem] = []
    @Published var moments: [Moment] = [] // ✅ NUEVO: Para Moments y Reels (estilo ProfileView)
    @Published var customListNamesById: [String: String] = [:] // ✅ NUEVO: Para resolver audiencias custom

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let category: ActivityInteractionCategory
    private let db = Firestore.firestore()
    private var didLoadOnce = false
    private var reactionsNextCursor: BackendReactionsCursor?
    private var commentsNextCursor: BackendCommentsCursor?

    init(category: ActivityInteractionCategory) {
        self.category = category
    }

    func loadIfNeeded() {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        reload()
    }

    func reload() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")
            return
        }

        isLoading = true
        errorMessage = nil

        switch category {
        case .reactions:
            loadReactions(for: userId)
        case .comments:
            loadComments(for: userId)
        case .tags:
            loadTags(for: userId)
        case .stickerReplies:
            loadStickerReplies(for: userId)
        case .archived:
            loadArchived(for: userId)
        case .storiesArchive:
            self.reactionItems = []
            self.commentItems = []
            self.events = []
            self.isLoading = false
        case .recentlyDeleted:
            loadRecentlyDeleted(for: userId)
        case .moments:
            fetchCustomAudienceListNames(userId: userId) { [weak self] in
                self?.loadMoments(for: userId)
            }
        case .reels:
            fetchCustomAudienceListNames(userId: userId) { [weak self] in
                self?.loadReels(for: userId)
            }
        case .echoes:
            loadEchoes(for: userId)
        case .followers:
            loadFollowers(for: userId)
        case .visits:
            loadVisits(for: userId)
        case .timeSpent, .searches, .accountHistory:
            self.isLoading = false
        }
    }

    func removeReactions(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = reactionItems.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return .success(()) }

        let batch = db.batch()
        for item in targets {
            let ref = db.collection("users")
                .document(item.authorId)
                .collection("moments")
                .document(item.momentId)
                .collection("reactions")
                .document(currentUserId)
            batch.deleteDocument(ref)
        }

        do {
            try await batch.commit()

            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeComments(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard Auth.auth().currentUser?.uid != nil else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = commentItems.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return .success(()) }

        do {
            try await deleteCommentsBatch(targets)
            await MainActor.run {
                self.commentItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeTags(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let currentUser = Auth.auth().currentUser else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = reactionItems
            .filter { ids.contains($0.id) }
            .map { ["authorId": $0.authorId, "momentId": $0.momentId] }
        guard !targets.isEmpty else { return .success(()) }

        do {
            let idToken = try await currentUser.getIDToken()
            guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"]))
            }

            guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/removeMyTagsBatch") else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"]))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["moments": targets])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"]))
            }
            guard http.statusCode == 200 else {
                return .failure(NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"]))
            }

            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func removeStickerReplies(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        let targets = events.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return .success(()) }

        let payload = targets.compactMap { item -> [String: String]? in
            guard let kind = item.kind, !kind.isEmpty,
                  let authorId = item.targetAuthorId, !authorId.isEmpty,
                  let storyId = item.storyId, !storyId.isEmpty else {
                return nil
            }
            var map: [String: String] = [
                "kind": kind,
                "authorId": authorId,
                "storyId": storyId
            ]
            if let sourceId = item.sourceId, !sourceId.isEmpty {
                map["sourceId"] = sourceId
            }
            return map
        }

        guard !payload.isEmpty else { return .success(()) }

        do {
            guard let currentUser = Auth.auth().currentUser else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
            }
            let idToken = try await currentUser.getIDToken()
            guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"]))
            }
            guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/removeMyStickerRepliesBatch") else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"]))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["replies": payload])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"]))
            }
            guard http.statusCode == 200 else {
                return .failure(NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"]))
            }

            await MainActor.run {
                self.events.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func restoreSelection(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let userId = Auth.auth().currentUser?.uid else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        do {
            for id in ids {
                try await FirestoreService.shared.restoreMoment(momentId: id, userId: userId)
            }
            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
                ActivityCache.saveRecentlyDeletedCount(self.reactionItems.count, userId: userId)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func permanentlyDeleteSelection(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let userId = Auth.auth().currentUser?.uid else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        do {
            for id in ids {
                try await FirestoreService.shared.permanentlyDeleteMoment(momentId: id, userId: userId)
            }
            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
                if category == .recentlyDeleted {
                    ActivityCache.saveRecentlyDeletedCount(self.reactionItems.count, userId: userId)
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func unarchiveSelection(withIds ids: Set<String>) async -> Result<Void, Error> {
        guard !ids.isEmpty else { return .success(()) }
        guard let userId = Auth.auth().currentUser?.uid else {
            return .failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")]))
        }

        do {
            for id in ids {
                try await FirestoreService.shared.unarchiveMoment(momentId: id, userId: userId)
            }
            await MainActor.run {
                self.reactionItems.removeAll { ids.contains($0.id) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }


    private func loadReactions(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let page = try await self.fetchReactedMomentsPage(limit: 36, cursor: nil)
                let sorted = page.items.sorted { $0.reactedAt > $1.reactedAt }
                ActivityCache.saveReactions(sorted, userId: userId)
                DispatchQueue.main.async {
                    self.reactionItems = sorted
                    self.reactionsNextCursor = page.nextCursor
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                let cached = ActivityCache.loadReactions(userId: userId).filter { $0.moment?.isArchived != true }
                DispatchQueue.main.async {
                    if !cached.isEmpty {
                        self.reactionItems = cached
                        self.commentItems = []
                        self.events = []
                        self.isLoading = false
                    } else {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func loadComments(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let page = try await self.fetchCommentedMomentsPage(limit: 36, cursor: nil)
                let sorted = page.items.sorted { $0.commentedAt > $1.commentedAt }
                ActivityCache.saveComments(sorted, userId: userId)
                DispatchQueue.main.async {
                    self.commentItems = sorted
                    self.commentsNextCursor = page.nextCursor
                    self.reactionItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                let cached = ActivityCache.loadComments(userId: userId).filter { $0.moment?.isArchived != true }
                DispatchQueue.main.async {
                    if !cached.isEmpty {
                        self.commentItems = cached
                        self.reactionItems = []
                        self.events = []
                        self.isLoading = false
                    } else {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func loadTags(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let page = try await self.fetchTaggedMomentsPage(limit: 60, cursor: nil)
                let mapped: [ActivityReactionItem] = page.items.compactMap { item in
                    let moment = item.moment.toMoment()
                    guard moment.isArchived != true else { return nil }
                    let timestamp = item.taggedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? moment.timestamp
                    let authorId = item.authorId ?? moment.authorId
                    guard let momentId = item.momentId ?? moment.id,
                          !authorId.isEmpty, !momentId.isEmpty else { return nil }
                    return ActivityReactionItem(
                        id: "\(authorId)_\(momentId)",
                        authorId: authorId,
                        momentId: momentId,
                        reactionType: "tagged",
                        reactedAt: timestamp,
                        moment: moment,
                        canView: true
                    )
                }
                DispatchQueue.main.async {
                    let sorted = mapped.sorted { $0.reactedAt > $1.reactedAt }
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveTagged(sorted, userId: uid)
                    }
                    self.reactionItems = sorted
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                self.loadTagsLegacy(for: userId)
            }
        }
    }

    private func loadTagsLegacy(for userId: String) {
        db.collectionGroup("moments")
            .whereField("taggedUsers", arrayContains: userId)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let _ = error {
                    DispatchQueue.main.async {
                        self.reactionItems = []
                        self.commentItems = []
                        self.events = []
                        self.isLoading = false
                    }
                    return
                }

                let mapped: [ActivityReactionItem] = snapshot?.documents.compactMap { doc in
                    guard let moment = try? doc.data(as: Moment.self) else { return nil }
                    guard moment.isArchived != true else { return nil }
                    let authorId = moment.authorId
                    guard let momentId = moment.id, !authorId.isEmpty, !momentId.isEmpty else { return nil }
                    return ActivityReactionItem(
                        id: "\(authorId)_\(momentId)",
                        authorId: authorId,
                        momentId: momentId,
                        reactionType: "tagged",
                        reactedAt: moment.timestamp,
                        moment: moment,
                        canView: true
                    )
                } ?? []

                DispatchQueue.main.async {
                    let sorted = mapped.sorted { $0.reactedAt > $1.reactedAt }
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveTagged(sorted, userId: uid)
                    }
                    self.reactionItems = sorted
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
        }
    }

    private func loadRecentlyDeleted(for userId: String) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let snapshot = try await db.collection("users").document(userId).collection("recentlyDeleted")
                    .order(by: "deletedAt", descending: true)
                    .limit(to: 50)
                    .getDocuments()
                
                let mapped: [ActivityReactionItem] = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    let timestamp = (data["deletedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    if let moment = try? doc.data(as: Moment.self) {
                        return ActivityReactionItem(
                            id: doc.documentID,
                            authorId: userId,
                            momentId: doc.documentID,
                            reactionType: "deleted_moment",
                            reactedAt: timestamp,
                            moment: moment,
                            canView: true
                        )
                    }
                    return nil
                }

                DispatchQueue.main.async {
                    self.reactionItems = mapped
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadArchived(for userId: String) {
        FirestoreService.shared.fetchArchivedMoments(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                let mapped: [ActivityReactionItem] = moments.compactMap { moment in
                    guard let id = moment.id else { return nil }
                    return ActivityReactionItem(
                        id: id,
                        authorId: moment.authorId,
                        momentId: id,
                        reactionType: "archived",
                        reactedAt: moment.archivedAt ?? moment.timestamp,
                        moment: moment,
                        canView: true
                    )
                }
                DispatchQueue.main.async {
                    self.reactionItems = mapped
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    if self.moments.isEmpty {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }

    private func fetchCustomAudienceListNames(userId: String, completion: (() -> Void)? = nil) {
        FirestoreService.shared.fetchCustomLists(for: userId) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            guard case .success(let lists) = result else {
                completion?()
                return
            }

            let map = lists.reduce(into: [String: String]()) { partialResult, list in
                guard let id = list.id else { return }
                partialResult[id] = list.name
            }

            DispatchQueue.main.async {
                self.customListNamesById = map
                completion?()
            }
        }
    }

    private func loadMoments(for userId: String) {
        // 1. Load from local cache for immediate UI
        Task { @MainActor in
            let cached = LocalPersistenceService.shared.loadProfileMoments(userId: userId)
            let filtered = cached.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && !isReel
            }
            
            await MainActor.run {
                if !filtered.isEmpty {
                    self.moments = filtered
                    self.isLoading = false
                }
            }
        }

        // 2. Fetch from Firestore
        FirestoreService.shared.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                Task { @MainActor in
                    LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
                }

                let filtered = moments.filter { moment in
                    let isArchived = moment.isArchived ?? false
                    let isReel = moment.isReelCandidate
                    return !isArchived && !isReel
                }
                
                DispatchQueue.main.async {
                    self.moments = filtered
                    self.reactionItems = []
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    if self.moments.isEmpty {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = nil
                    }
                }
            }
        }
    }

    private func loadReels(for userId: String) {
        // 1. Load from local cache
        Task { @MainActor in
            let cached = LocalPersistenceService.shared.loadProfileMoments(userId: userId)
            let filtered = cached.filter { moment in
                let isArchived = moment.isArchived ?? false
                let isReel = moment.isReelCandidate
                return !isArchived && isReel
            }
            
            await MainActor.run {
                if !filtered.isEmpty {
                    self.moments = filtered
                    self.isLoading = false
                }
            }
        }

        // 2. Fetch from Firestore
        FirestoreService.shared.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                Task { @MainActor in
                    LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
                }

                let filtered = moments.filter { moment in
                    let isArchived = moment.isArchived ?? false
                    let isReel = moment.isReelCandidate
                    return !isArchived && isReel
                }
                
                DispatchQueue.main.async {
                    self.moments = filtered
                    self.reactionItems = []
                    self.commentItems = []
                    self.events = []
                    self.isLoading = false
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func mapMomentsToReactionItems(_ moments: [Moment], type: String) -> [ActivityReactionItem] {
        moments.compactMap { moment in
            guard let id = moment.id else { return nil }
            return ActivityReactionItem(
                id: id,
                authorId: moment.authorId,
                momentId: id,
                reactionType: type,
                reactedAt: moment.timestamp,
                moment: moment,
                canView: true
            )
        }
    }

    private func loadEchoes(for userId: String) {
        EchoService.shared.fetchEchoHistory(userId: userId) { [weak self] echoes in
            guard let self = self else { return }

            let mapped: [ActivityEventItem] = echoes.compactMap { (echo: Echo) -> ActivityEventItem? in
                guard let id = echo.id else { return nil }

                let participantsCount = echo.participants.count
                let locationName = echo.locationName ?? NSLocalizedString("echo.unknownLocation", comment: "Unknown location")
                let title = locationName

                let thumbnailUrl = echo.moments.last?.thumbnailUrl ?? echo.moments.last?.mediaUrl

                return ActivityEventItem(
                    id: id,
                    title: title,
                    subtitle: "",
                    timestamp: echo.createdAt,
                    icon: "waveform.and.mic",
                    kind: "echo",
                    sourceId: id,
                    thumbnailUrl: thumbnailUrl,
                    echoStatusRaw: echo.status.rawValue,
                    echoParticipantsCount: participantsCount,
                    echoExpiresAt: echo.expiresAt
                )
            }.sorted { $0.timestamp > $1.timestamp }
            
            DispatchQueue.main.async {
                self.events = mapped
                self.isLoading = false
            }
        }
    }

    private func loadFollowers(for userId: String) {
        Task {
            do {
                let items = try await FirestoreService.shared.fetchFollowersWithTimestamps(userId: userId)
                let mapped: [ActivityEventItem] = items.map { item in
                    let dateString = self.dateFormatter.string(from: item.timestamp)
                    let subtitle = String(format: NSLocalizedString("userActivity.event.follow.subtitle", comment: ""), dateString)
                    
                    return ActivityEventItem(
                        id: item.user.id,
                        title: item.user.username,
                        subtitle: subtitle,
                        timestamp: item.timestamp,
                        icon: "person.badge.plus",
                        actorId: item.user.id,
                        actorUsername: item.user.username,
                        actorProfileImagePath: item.user.profileImagePath,
                        actionText: NSLocalizedString("userActivity.event.action.viewProfile", comment: "View profile"),
                        kind: "follower"
                    )
                }
                
                await MainActor.run {
                    self.events = mapped
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Error loading followers for activity: \(error)")
                }
            }
        }
    }

    private func loadVisits(for userId: String) {
        Task {
            do {
                let items = try await FirestoreService.shared.fetchVisitsWithUsers(userId: userId)
                // Deduplicate visits by user, keeping the latest one
                var latestVisits: [String: ActivityEventItem] = [:]
                
                for item in items {
                    let actorId = item.user.id
                    let dateString = self.dateFormatter.string(from: item.visit.timestamp)
                    let subtitle = String(format: NSLocalizedString("userActivity.event.visit.subtitle", comment: ""), dateString)
                    
                    let event = ActivityEventItem(
                        id: item.visit.id ?? UUID().uuidString,
                        title: item.user.username,
                        subtitle: subtitle,
                        timestamp: item.visit.timestamp,
                        icon: "eye",
                        actorId: actorId,
                        actorUsername: item.user.username,
                        actorProfileImagePath: item.user.profileImagePath,
                        actionText: NSLocalizedString("userActivity.event.action.viewProfile", comment: "View profile"),
                        kind: "visit"
                    )
                    
                    if let existing = latestVisits[actorId] {
                        if event.timestamp > existing.timestamp {
                            latestVisits[actorId] = event
                        }
                    } else {
                        latestVisits[actorId] = event
                    }
                }
                
                let sortedEvents = latestVisits.values.sorted { $0.timestamp > $1.timestamp }
                
                await MainActor.run {
                    self.events = sortedEvents
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Error loading visits for activity: \(error)")
                }
            }
        }
    }

    private func loadStickerReplies(for _: String) {
        Task {
            do {
                let page = try await self.fetchStickerRepliesPage(limit: 80, cursor: nil)
                let mapped: [ActivityEventItem] = page.items.compactMap { item in
                    let timestamp = item.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
                    let kind = item.kind.lowercased()
                    let actorName = (item.actorUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName = actorName.isEmpty
                        ? NSLocalizedString("userActivity.simple.stickers.actorFallback", comment: "Sticker actor fallback")
                        : actorName

                    if kind == "poll" {
                        let optionText = (item.pollOptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let optionFallback: String
                        if let option = item.pollOption {
                            optionFallback = String(
                                format: NSLocalizedString("userActivity.simple.stickers.poll.optionFallback", comment: "Poll option fallback"),
                                option + 1
                            )
                        } else {
                            optionFallback = ""
                        }
                        let resolvedOptionText = optionText.isEmpty ? optionFallback : optionText
                        let subtitle = resolvedOptionText.isEmpty
                            ? NSLocalizedString("userActivity.simple.stickers.poll.subtitleFallback", comment: "Poll response fallback")
                            : String(format: NSLocalizedString("userActivity.simple.stickers.poll.subtitle", comment: "Poll response subtitle"), resolvedOptionText)
                        return ActivityEventItem(
                            id: "event_poll_\(item.id)",
                            title: displayName,
                            subtitle: subtitle,
                            timestamp: timestamp,
                            icon: "checkmark.circle.fill",
                            actorId: item.actorId,
                            actorUsername: item.actorUsername,
                            actorProfileImagePath: item.actorProfileImagePath,
                            actionText: NSLocalizedString("userActivity.simple.stickers.poll.action", comment: "Poll response action"),
                            kind: "poll",
                            targetAuthorId: item.authorId,
                            targetUsername: item.targetUsername,
                            storyId: item.storyId,
                            sourceId: item.sourceId,
                            contextText: String(
                                format: NSLocalizedString("userActivity.simple.stickers.poll.context", comment: "Poll context"),
                                (item.targetUsername ?? "").isEmpty
                                    ? NSLocalizedString("onlineStatus.unknown", comment: "Unknown")
                                    : (item.targetUsername ?? "")
                            )
                        )
                    }

                    if kind == "question" {
                        let questionText = (item.questionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let responseText = (item.responseText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let subtitle: String
                        if !responseText.isEmpty {
                            subtitle = responseText
                        } else if !questionText.isEmpty {
                            subtitle = questionText
                        } else {
                            subtitle = NSLocalizedString("userActivity.simple.stickers.question.subtitleFallback", comment: "Question response fallback")
                        }
                        return ActivityEventItem(
                            id: "event_question_\(item.id)",
                            title: displayName,
                            subtitle: subtitle,
                            timestamp: timestamp,
                            icon: "questionmark.bubble.fill",
                            actorId: item.actorId,
                            actorUsername: item.actorUsername,
                            actorProfileImagePath: item.actorProfileImagePath,
                            actionText: NSLocalizedString("userActivity.simple.stickers.question.action", comment: "Question response action"),
                            kind: "question",
                            targetAuthorId: item.authorId,
                            targetUsername: item.targetUsername,
                            storyId: item.storyId,
                            sourceId: item.sourceId,
                            contextText: String(
                                format: NSLocalizedString("userActivity.simple.stickers.question.context", comment: "Question context"),
                                (item.targetUsername ?? "").isEmpty
                                    ? NSLocalizedString("onlineStatus.unknown", comment: "Unknown")
                                    : (item.targetUsername ?? "")
                            )
                        )
                    }

                    return nil
                }

                DispatchQueue.main.async {
                    let sorted = mapped.sorted { $0.timestamp > $1.timestamp }
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveStickerReplyCount(sorted.count, userId: uid)
                    }
                    self.events = sorted
                    self.reactionItems = []
                    self.commentItems = []
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    if let uid = FirebaseAuth.Auth.auth().currentUser?.uid {
                        ActivityCache.saveStickerReplyCount(0, userId: uid)
                    }
                    self.events = []
                    self.reactionItems = []
                    self.commentItems = []
                    self.isLoading = false
                    self.errorMessage = NSLocalizedString("userActivity.simple.empty.stickers", comment: "No sticker replies")
                }
            }
        }
    }

    private struct BackendReactionsCursor: Codable {
        let timestamp: Double
    }

    private struct BackendReactionsItem: Codable {
        let moment: BackendMoment
        let reactionType: String
        let reactedAt: Double?
        let authorId: String?
        let momentId: String?
        let canView: Bool?
    }

    private struct BackendReactionsResponse: Codable {
        let items: [BackendReactionsItem]
        let nextCursor: BackendReactionsCursor?
        let source: String
        let totalCandidates: Int
    }

    private struct BackendCommentsCursor: Codable {
        let timestamp: Double
    }

    private struct BackendCommentPayload: Codable {
        let id: String?
        let content: String?
        let timestamp: Double?
        let parentCommentId: String?
    }

    private struct BackendCommentedItem: Codable {
        let moment: BackendMoment
        let comment: BackendCommentPayload?
        let commentedAt: Double?
        let authorId: String?
        let momentId: String?
        let commentId: String?
        let canView: Bool?
    }

    private struct BackendCommentsResponse: Codable {
        let items: [BackendCommentedItem]
        let nextCursor: BackendCommentsCursor?
        let source: String
        let totalCandidates: Int
    }

    private struct BackendTagsCursor: Codable {
        let timestamp: Double
    }

    private struct BackendTaggedItem: Codable {
        let moment: BackendMoment
        let taggedAt: Double?
        let authorId: String?
        let momentId: String?
        let canView: Bool?
    }

    private struct BackendTagsResponse: Codable {
        let items: [BackendTaggedItem]
        let nextCursor: BackendTagsCursor?
        let source: String
        let totalCandidates: Int
    }

    private struct BackendStickerRepliesCursor: Codable {
        let timestamp: Double
    }

    private struct BackendStickerReplyItem: Codable {
        let id: String
        let sourceId: String?
        let kind: String
        let authorId: String?
        let storyId: String?
        let targetUsername: String?
        let actorId: String?
        let actorUsername: String?
        let actorProfileImagePath: String?
        let timestamp: Double?
        let questionText: String?
        let responseText: String?
        let pollOption: Int?
        let pollOptionText: String?
    }

    private struct BackendStickerRepliesResponse: Codable {
        let items: [BackendStickerReplyItem]
        let nextCursor: BackendStickerRepliesCursor?
        let source: String
        let totalCandidates: Int
    }

    private struct DeleteCommentsTarget: Codable {
        let authorId: String
        let momentId: String
        let commentId: String
    }

    private struct DeleteCommentsBatchResponse: Codable {
        let deleted: Int
        let skipped: Int
        let cascadedReplies: Int?
    }

    private func fetchReactedMomentsPage(limit: Int, cursor: BackendReactionsCursor?) async throws -> (items: [ActivityReactionItem], nextCursor: BackendReactionsCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getReactedMomentsPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendReactionsResponse.self, from: data)
        let mapped: [ActivityReactionItem] = decoded.items.compactMap { item in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty else { return nil }

            let reactedAtDate = item.reactedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? moment.timestamp

            return ActivityReactionItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                reactionType: item.reactionType,
                reactedAt: reactedAtDate,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        return (mapped, decoded.nextCursor)
    }

    private func fetchCommentedMomentsPage(limit: Int, cursor: BackendCommentsCursor?) async throws -> (items: [ActivityCommentItem], nextCursor: BackendCommentsCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getCommentedMomentsPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendCommentsResponse.self, from: data)
        let mapped: [ActivityCommentItem] = decoded.items.compactMap { item in
            let moment = item.moment.toMoment()
            guard moment.isArchived != true else { return nil }
            let resolvedAuthorId = item.authorId ?? moment.authorId
            let resolvedMomentId = item.momentId ?? moment.id
            let resolvedCommentId = item.commentId ?? item.comment?.id
            guard let resolvedMomentId, !resolvedMomentId.isEmpty,
                  let resolvedCommentId, !resolvedCommentId.isEmpty else { return nil }

            let commentText = item.comment?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let commentedAtDate = item.commentedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? item.comment?.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? moment.timestamp

            return ActivityCommentItem(
                id: "\(resolvedAuthorId)_\(resolvedMomentId)_\(resolvedCommentId)",
                authorId: resolvedAuthorId,
                momentId: resolvedMomentId,
                commentId: resolvedCommentId,
                commentText: commentText,
                commentedAt: commentedAtDate,
                moment: moment,
                canView: item.canView ?? true
            )
        }

        return (mapped, decoded.nextCursor)
    }

    private func fetchTaggedMomentsPage(limit: Int, cursor: BackendTagsCursor?) async throws -> (items: [BackendTaggedItem], nextCursor: BackendTagsCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getTaggedMomentsPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendTagsResponse.self, from: data)
        return (decoded.items, decoded.nextCursor)
    }

    private func fetchStickerRepliesPage(limit: Int, cursor: BackendStickerRepliesCursor?) async throws -> (items: [BackendStickerReplyItem], nextCursor: BackendStickerRepliesCursor?) {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/getStickerRepliesPage") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        var payload: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            payload["cursor"] = ["timestamp": cursor.timestamp]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(BackendStickerRepliesResponse.self, from: data)
        return (decoded.items, decoded.nextCursor)
    }

    private func deleteCommentsBatch(_ items: [ActivityCommentItem]) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("messaging.error.notAuthenticated", comment: "Not authenticated")])
        }

        let idToken = try await currentUser.getIDToken()
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Firebase project ID"])
        }

        guard let url = URL(string: "https://europe-southwest1-\(projectId).cloudfunctions.net/deleteMyCommentsBatch") else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])
        }

        let payloadItems = items.map { item in
            DeleteCommentsTarget(authorId: item.authorId, momentId: item.momentId, commentId: item.commentId)
        }
        let payload: [String: Any] = [
            "comments": payloadItems.map { ["authorId": $0.authorId, "momentId": $0.momentId, "commentId": $0.commentId] }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid backend response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend error \(http.statusCode)"])
        }

        _ = try? JSONDecoder().decode(DeleteCommentsBatchResponse.self, from: data)
    }

    private struct NotificationRecord {
        let id: String
        let type: String
        let senderUsername: String?
        let reaction: String?
        let timestamp: Date
    }

    private func fetchNotifications(userId: String, completion: @escaping ([NotificationRecord]) -> Void) {
        db.collection("users")
            .document(userId)
            .collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: 300)
            .getDocuments { snapshot, _ in
                let records = snapshot?.documents.compactMap { doc -> NotificationRecord? in
                    let data = doc.data()
                    guard let type = data["type"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }

                    return NotificationRecord(
                        id: doc.documentID,
                        type: type,
                        senderUsername: data["senderUsername"] as? String,
                        reaction: data["reaction"] as? String,
                        timestamp: timestamp
                    )
                } ?? []

                completion(records)
            }
    }

    private struct InteractionEventRecord {
        let id: String
        let interactionType: String
        let timestamp: Date
    }

    private func fetchInteractionEvents(userId: String, completion: @escaping ([InteractionEventRecord]) -> Void) {
        db.collection("users")
            .document(userId)
            .collection("events")
            .whereField("eventType", isEqualTo: "interaction")
            .order(by: "timestamp", descending: true)
            .limit(to: 400)
            .getDocuments { snapshot, _ in
                let records = snapshot?.documents.compactMap { doc -> InteractionEventRecord? in
                    let data = doc.data()
                    guard let interactionType = data["interactionType"] as? String,
                          let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                        return nil
                    }

                    return InteractionEventRecord(
                        id: doc.documentID,
                        interactionType: interactionType,
                        timestamp: timestamp
                    )
                } ?? []

                completion(records)
            }
    }
}

// MARK: - Compatibility Type (used by AnalyticsService)
enum ActivityTimeRange: String, CaseIterable {
    case week = "week"
    case month = "month"
    case year = "year"

    var title: String {
        switch self {
        case .week:
            return NSLocalizedString("userActivity.range.week", comment: "7 days range")
        case .month:
            return NSLocalizedString("userActivity.range.month", comment: "30 days range")
        case .year:
            return NSLocalizedString("userActivity.range.year", comment: "1 year range")
        }
    }
}
