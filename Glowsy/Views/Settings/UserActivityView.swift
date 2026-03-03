import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseCore
import Kingfisher
import AVFoundation

struct UserActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

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

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(ActivityInteractionCategory.allCases.enumerated()), id: \.element.id) { index, category in
                                NavigationLink {
                                    ActivityInteractionDetailView(category: category)
                                } label: {
                                    ActivityInteractionCategoryRow(category: category)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if index < ActivityInteractionCategory.allCases.count - 1 {
                                    Divider()
                                        .padding(.leading, 62)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
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
        }
    }
}

private enum ActivityInteractionCategory: String, CaseIterable, Identifiable {
    case reactions
    case comments
    case tags
    case stickerReplies

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .reactions: return "userActivity.simple.item.reactions.title"
        case .comments: return "userActivity.simple.item.comments.title"
        case .tags: return "userActivity.simple.item.tags.title"
        case .stickerReplies: return "userActivity.simple.item.stickers.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .reactions: return "userActivity.simple.item.reactions.subtitle"
        case .comments: return "userActivity.simple.item.comments.subtitle"
        case .tags: return "userActivity.simple.item.tags.subtitle"
        case .stickerReplies: return "userActivity.simple.item.stickers.subtitle"
        }
    }

    var icon: String {
        switch self {
        case .reactions: return "sparkles"
        case .comments: return "bubble.right.fill"
        case .tags: return "at"
        case .stickerReplies: return "face.smiling"
        }
    }

    var emptyKey: String {
        switch self {
        case .reactions: return "userActivity.simple.empty.reactions"
        case .comments: return "userActivity.simple.empty.comments"
        case .tags: return "userActivity.simple.empty.tags"
        case .stickerReplies: return "userActivity.simple.empty.stickers"
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

private struct AnimatedReactionIcon: View {
    private let reactions = ReactionType.allCases.map { $0.icon }
    @State private var currentIndex = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        Text(reactions[currentIndex])
            .font(.system(size: 22))
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 36, height: 36)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
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

    var body: some View {
        Image(systemName: bubbles[currentIndex])
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 36, height: 36)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
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
    }
}

private struct ActivityInteractionCategoryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: ActivityInteractionCategory

    var body: some View {
        HStack(spacing: 14) {
            // Icon
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
                Text(NSLocalizedString(category.titleKey, comment: "Interaction category title"))
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

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
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
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
    @State private var isDeletingSelectedReactions = false
    @State private var isDeletingSelectedComments = false

    init(category: ActivityInteractionCategory) {
        self.category = category
        _viewModel = StateObject(wrappedValue: ActivityInteractionDetailViewModel(category: category))
    }

    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView(NSLocalizedString("userActivity.loading", comment: "Loading activity"))
                    .tint(Color(hex: "4F46E5"))
            } else if let errorMessage = viewModel.errorMessage {
                let isOffline = errorMessage.localizedCaseInsensitiveContains("offline")
                    || errorMessage.localizedCaseInsensitiveContains("internet")
                    || errorMessage.localizedCaseInsensitiveContains("network")
                    || errorMessage.localizedCaseInsensitiveContains("connection")

                VStack(spacing: 16) {
                    Text(isOffline ? "📡" : "⚠️")
                        .font(.system(size: 48))

                    VStack(spacing: 6) {
                        Text(isOffline
                             ? NSLocalizedString("userActivity.error.offline.title", comment: "Offline title")
                             : NSLocalizedString("userActivity.error.generic.title", comment: "Generic error title"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .multilineTextAlignment(.center)

                        Text(isOffline
                             ? NSLocalizedString("userActivity.error.offline.subtitle", comment: "Offline subtitle")
                             : NSLocalizedString("userActivity.error.generic.subtitle", comment: "Generic error subtitle"))
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
            } else if category == .reactions {
                reactionsContent
            } else if category == .comments {
                commentsContent
            } else {
                eventsList
            }
        }
        .navigationTitle(NSLocalizedString(category.titleKey, comment: "Interaction detail title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if category == .reactions || category == .comments {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSelectionMode
                           ? NSLocalizedString("savedMoments.cancel", comment: "Cancel")
                           : NSLocalizedString("savedMoments.select", comment: "Select")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedReactionIds.removeAll()
                                selectedCommentIds.removeAll()
                            }
                        }
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                }
            }
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .onChange(of: filteredReactionItems.map(\.id)) { visibleIds in
            let validIds = Set(visibleIds)
            selectedReactionIds = Set(selectedReactionIds.filter { validIds.contains($0) })
        }
        .onChange(of: filteredCommentItems.map(\.id)) { visibleIds in
            let validIds = Set(visibleIds)
            selectedCommentIds = Set(selectedCommentIds.filter { validIds.contains($0) })
        }
        .safeAreaInset(edge: .bottom) {
            if category == .reactions, isSelectionMode {
                reactionsSelectionBar
            } else if category == .comments, isSelectionMode {
                commentsSelectionBar
            }
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

    private var reactionsGrid: some View {
        GeometryReader { geometry in
            if filteredReactionItems.isEmpty {
                emptyState(textKey: category.emptyKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                let spacing: CGFloat = 2
                let totalSpacing: CGFloat = spacing * 2
                let side = floor((geometry.size.width - 32 - totalSpacing) / 3) // 16 + 16 horizontal padding
                let columns = [
                    GridItem(.fixed(side), spacing: spacing),
                    GridItem(.fixed(side), spacing: spacing),
                    GridItem(.fixed(side), spacing: spacing)
                ]

                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(filteredReactionItems) { item in
                            Button {
                                if isSelectionMode {
                                    toggleSelection(for: item.id)
                                    return
                                }
                                guard item.canView, let moment = item.moment else { return }
                                selectedMomentForDetail = moment
                            } label: {
                                ActivityReactionMomentCard(
                                    item: item,
                                    size: side,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedReactionIds.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(width: side, height: side)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, isSelectionMode ? 88 : 12)
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
                    .padding(.horizontal, 12)
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

        let authorFiltered = filteredByDate.filter { item in
            guard let selectedAuthorId, !selectedAuthorId.isEmpty else { return true }
            return item.authorId == selectedAuthorId
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

    private var availableAuthorIds: [String] {
        let usernames = authorUsernameMap
        let sourceAuthorIds: [String] = {
            switch category {
            case .reactions:
                return viewModel.reactionItems.map { $0.authorId }
            case .comments:
                return viewModel.commentItems.map { $0.authorId }
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
        case .reactions:
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

                Button {
                    showingAuthorFilterSheet = true
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.author", comment: "Author filter title"),
                        value: selectedAuthorLabel
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
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
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var eventsList: some View {
        Group {
            if viewModel.events.isEmpty {
                emptyState(textKey: category.emptyKey)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(viewModel.events) { item in
                            ActivityEventRow(item: item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
            }
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

    private var reactionsSelectionBar: some View {
        let selectedCount = selectedReactionIds.count

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

                Text(String(format: NSLocalizedString("userActivity.simple.reactions.selectedCount", comment: "Selected reactions count"), selectedCount))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    Task {
                        await deleteSelectedReactions()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isDeletingSelectedReactions {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "heart.slash.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text(selectedCount == 1
                             ? NSLocalizedString("userActivity.simple.reactions.delete.single", comment: "Delete one reaction")
                             : NSLocalizedString("userActivity.simple.reactions.delete.multiple", comment: "Delete multiple reactions"))
                            .font(.custom("Poppins-SemiBold", size: 13))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red.opacity(selectedCount > 0 ? 0.9 : 0.45)))
                }
                .disabled(selectedCount == 0 || isDeletingSelectedReactions)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
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
            .padding(.horizontal, 14)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "4F46E5").opacity(0.13))
                    .frame(width: 32, height: 32)

                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "4F46E5"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }

                Text(item.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray.opacity(0.85))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
        )
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
        ZStack(alignment: .topLeading) {
            cardPreview
                .frame(width: size, height: size)
                .blur(radius: item.canView ? 0 : 16)
                .clipped()

            if !item.canView {
                restrictedOverlay
            }

            reactionBadge
                .padding(6)

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

    private func reactionStyle(from rawValue: String) -> (icon: String, label: String, color: Color) {
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
}

private enum ActivityCache {
    private static func minimalMoment(from p: (imagePath: String?, videoUrl: String?, thumbnailUrl: String?, content: String?, username: String?, authorId: String?, id: String)) -> Moment {
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
            audience: nil,
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
                momentAuthorId: item.moment?.authorId
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
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId))
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
                momentAuthorId: item.moment?.authorId
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
            let moment = minimalMoment(from: (p.momentImagePath, p.momentVideoUrl, p.momentThumbnailUrl, p.momentContent, p.momentUsername, p.momentAuthorId, p.momentId))
            return ActivityCommentItem(
                id: p.id, authorId: p.authorId, momentId: p.momentId,
                commentId: p.commentId, commentText: p.commentText,
                commentedAt: Date(timeIntervalSince1970: p.commentedAt),
                moment: moment, canView: p.canView
            )
        }
    }
}

private final class ActivityInteractionDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reactionItems: [ActivityReactionItem] = []
    @Published var commentItems: [ActivityCommentItem] = []
    @Published var events: [ActivityEventItem] = []

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
                let cached = ActivityCache.loadReactions(userId: userId)
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
                let cached = ActivityCache.loadComments(userId: userId)
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
        let group = DispatchGroup()
        var merged: [ActivityEventItem] = []

        group.enter()
        fetchNotifications(userId: userId) { items in
            let tags = items.compactMap { item -> ActivityEventItem? in
                let sender = item.senderUsername?.isEmpty == false ? item.senderUsername! : "@user"

                if item.type == "mention" {
                    return ActivityEventItem(
                        id: "notif_mention_\(item.id)",
                        title: String(format: NSLocalizedString("userActivity.event.mention.received", comment: "Mention received"), sender),
                        subtitle: NSLocalizedString("userActivity.event.subtitle.open", comment: "Open content"),
                        timestamp: item.timestamp,
                        icon: "at"
                    )
                }

                if item.type == "photoTag" {
                    return ActivityEventItem(
                        id: "notif_phototag_\(item.id)",
                        title: String(format: NSLocalizedString("userActivity.event.photoTag.received", comment: "Photo tag received"), sender),
                        subtitle: NSLocalizedString("userActivity.event.subtitle.open", comment: "Open content"),
                        timestamp: item.timestamp,
                        icon: "tag.fill"
                    )
                }

                return nil
            }
            merged.append(contentsOf: tags)
            group.leave()
        }

        group.enter()
        fetchInteractionEvents(userId: userId) { items in
            let tags = items.compactMap { item -> ActivityEventItem? in
                let type = item.interactionType.lowercased()
                guard type == "mention_usage" else { return nil }
                return ActivityEventItem(
                    id: "event_mention_\(item.id)",
                    title: NSLocalizedString("userActivity.event.action.mentionUsed", comment: "Mention used"),
                    subtitle: NSLocalizedString("userActivity.event.subtitle.you", comment: "Your action"),
                    timestamp: item.timestamp,
                    icon: "at"
                )
            }
            merged.append(contentsOf: tags)
            group.leave()
        }

        group.notify(queue: .main) {
            self.events = merged.sorted { $0.timestamp > $1.timestamp }
            self.reactionItems = []
            self.commentItems = []
            self.isLoading = false
        }
    }

    private func loadStickerReplies(for userId: String) {
        fetchInteractionEvents(userId: userId) { [weak self] items in
            guard let self = self else { return }

            let stickers = items.compactMap { item -> ActivityEventItem? in
                let type = item.interactionType.lowercased()
                guard type.contains("sticker") || type.contains("question") else { return nil }
                return ActivityEventItem(
                    id: "event_sticker_\(item.id)",
                    title: NSLocalizedString("userActivity.event.action.stickerReply", comment: "Sticker reply"),
                    subtitle: NSLocalizedString("userActivity.event.subtitle.you", comment: "Your action"),
                    timestamp: item.timestamp,
                    icon: "face.smiling"
                )
            }

            DispatchQueue.main.async {
                self.events = stickers.sorted { $0.timestamp > $1.timestamp }
                self.reactionItems = []
                self.commentItems = []
                self.isLoading = false
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
