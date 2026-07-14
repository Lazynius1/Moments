import SwiftUI
import Kingfisher
import AVFoundation

struct ActivityInteractionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let category: ActivityInteractionCategory
    let recentlyDeletedKind: RecentlyDeletedContentKind
    let suppressInlineNavigationTitle: Bool

    @StateObject private var viewModel: ActivityInteractionDetailViewModel
    @State private var reactionsSort: ReactionsSortOption = .newest
    @State private var reactionsDateFilter: ReactionsDateFilter = .all
    @State private var customDateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customDateTo: Date = Date()
    @State private var selectedAuthorId: String?
    @State private var showingAuthorFilterSheet = false
    @Namespace private var zoomNamespace
    @Namespace private var profileZoomNamespace
    @State private var zoomDestination: MomentZoomDestination?
    @State private var zoomActivityMomentsPool: [Moment] = []
    @State private var reelsPresentation: ActivityReelsPresentation?
    @State private var recentlyDeletedStoryPresentation: RecentlyDeletedStoriesPresentation?
    @State private var storyRoute: IdentifiableString?
    @State private var profileRoute: FeedProfileSheetRoute?
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
    @State private var gridSelectionDragMode: SelectionDragMode?
    @State private var pendingActivitySelectionConfirmation: ActivitySelectionConfirmationAction?
    @State private var recentlyDeletedInFlightAction: RecentlyDeletedConfirmationAction?
    @State private var isRestoringArchivedSelection = false
    @State private var activitySelectionSuccessBannerKey: String?
    @State private var recentlyDeletedSuccessBannerKey: String?
    @State private var recentlyDeletedAutoScrollDirection: RecentlyDeletedAutoScrollDirection?
    @State private var recentlyDeletedAutoScrollTask: Task<Void, Never>?
    @State private var recentlyDeletedDragCurrentId: String?

    init(
        category: ActivityInteractionCategory,
        recentlyDeletedKind: RecentlyDeletedContentKind = .moments,
        suppressInlineNavigationTitle: Bool = false
    ) {
        self.category = category
        self.recentlyDeletedKind = recentlyDeletedKind
        self.suppressInlineNavigationTitle = suppressInlineNavigationTitle
        _viewModel = StateObject(wrappedValue: ActivityInteractionDetailViewModel(category: category, recentlyDeletedKind: recentlyDeletedKind))
    }

    private var sectionHorizontalPadding: CGFloat { 8 }

    private var activityGridSpacing: CGFloat { 1 }

    private var reactionCardOverlayBadge: ActivityOverlayBadgeStyle {
        switch category {
        case .reactions, .tags:
            return .reactionDiscreet
        case .archived:
            return .audience
        case .recentlyDeleted:
            return .none
        default:
            return .none
        }
    }

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
        activityDetailPresentedView
    }

    private var activityDetailPresentedView: some View {
        activityDetailLifecycleView
            .sheet(isPresented: $showingAuthorFilterSheet) {
                AuthorFilterSheet(
                    selectedAuthorId: $selectedAuthorId,
                    availableAuthorIds: availableAuthorIds,
                    authorUsernameMap: authorUsernameMap
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .navigationDestination(item: $zoomDestination) { destination in
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: zoomNamespace
                )
            }
            .onChange(of: zoomDestination) { _, newValue in
                if newValue == nil {
                    zoomActivityMomentsPool = []
                }
            }
            .fullScreenCover(item: $reelsPresentation) { presentation in
                ReelsViewer(
                    videos: presentation.videos,
                    startIndex: presentation.startIndex
                )
                .environmentObject(FirestoreService.shared)
            }
            .fullScreenCover(item: $recentlyDeletedStoryPresentation) { presentation in
                ArchiveDayStoriesViewer(
                    stories: presentation.stories,
                    initialIndex: presentation.initialIndex
                )
            }
            .fullScreenCover(item: $storyRoute) { route in
                StoriesView(startWithUserId: .constant(route.id))
            }
            .userProfileNavigationDestination(item: $profileRoute, namespace: profileZoomNamespace)
            .fullScreenCover(item: selectedEchoPresentation) { ident in
                EchoViewerUI(echoId: ident.id)
            }
    }

    private var selectedEchoPresentation: Binding<IdentifiableString?> {
        Binding(
            get: { selectedEchoId.map { IdentifiableString(id: $0) } },
            set: { newValue in selectedEchoId = newValue?.id }
        )
    }

    private var activityDetailLifecycleView: some View {
        activityDetailChromeView
            .alert(item: $pendingActivitySelectionConfirmation) { action in
                activitySelectionConfirmationAlert(for: action)
            }
            .onAppear {
                viewModel.loadIfNeeded()
            }
            .onChange(of: filteredReactionItems.map(\.id)) {
                let validIds = Set(filteredReactionItems.map(\.id))
                selectedReactionIds = Set(selectedReactionIds.filter { validIds.contains($0) })
            }
            .onChange(of: selectedReactionIds) {
                if (category == .archived || category == .recentlyDeleted), isSelectionMode, selectedReactionIds.isEmpty {
                    isSelectionMode = false
                }
            }
            .onChange(of: isSelectionMode) {
                if !isSelectionMode {
                    stopRecentlyDeletedAutoScroll()
                }
            }
            .onChange(of: filteredCommentItems.map(\.id)) {
                let validIds = Set(filteredCommentItems.map(\.id))
                selectedCommentIds = Set(selectedCommentIds.filter { validIds.contains($0) })
            }
            .onChange(of: filteredEventItems.map(\.id)) {
                let validIds = Set(filteredEventItems.map(\.id))
                selectedEventIds = Set(selectedEventIds.filter { validIds.contains($0) })
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                selectionBars
            }
            .overlay(alignment: .top) {
                activityDetailBannerOverlay
            }
            .onDisappear {
                stopRecentlyDeletedAutoScroll()
            }
    }

    @ViewBuilder
    private var activityDetailBannerOverlay: some View {
        if let successKey = activitySelectionSuccessBannerKey {
            selectionSuccessBanner(textKey: successKey)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let successKey = recentlyDeletedSuccessBannerKey {
            selectionSuccessBanner(textKey: successKey)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        if let action = recentlyDeletedInFlightAction {
            processingBanner(
                titleKey: recentlyDeletedProcessingTitleKey(for: action),
                subtitleKey: "userActivity.simple.recentlyDeleted.processing.subtitle"
            )
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if isRestoringArchivedSelection {
            processingBanner(
                titleKey: "userActivity.event.archived.processing.restore",
                subtitleKey: "userActivity.simple.recentlyDeleted.processing.subtitle"
            )
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var activityDetailChromeView: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .modifier(InlineNavigationTitleModifier(
            titleKey: detailNavigationTitleKey,
            isSuppressed: suppressInlineNavigationTitle
        ))
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if !suppressInlineNavigationTitle {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsToolbarBackButton(action: { dismiss() })
                }
            }
            navigationToolbar
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            ProgressView(NSLocalizedString("userActivity.loading", comment: "Loading activity"))
                .tint(SettingsProfileColors.accent(colorScheme))
        } else if let errorMessage = viewModel.errorMessage {
            errorStateView(errorMessage: errorMessage)
        } else if category == .recentlyDeleted, recentlyDeletedKind == .stories {
            recentlyDeletedStoriesContent
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString(subtitleKey, comment: "Error subtitle"))
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: { viewModel.reload() }) {
                Text(NSLocalizedString("userActivity.simple.retry", comment: "Retry activity load"))
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
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
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            }
        }
    }

    private func performActivityRefresh() async {
        viewModel.reload()
        while viewModel.isLoading {
            try? await Task.sleep(nanoseconds: 100_000_000)
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

    private struct RecentlyDeletedStoriesPresentation: Identifiable {
        let id = UUID()
        let stories: [Story]
        let initialIndex: Int
    }

    private struct ActivityReelsPresentation: Identifiable {
        let id = UUID()
        let videos: [VideoMoment]
        let startIndex: Int
    }

    private func openActivityReels(moment: Moment, moments: [Moment]) {
        let videos = moments.videoMoments
        guard !videos.isEmpty else { return }
        let startIndex = videos.firstIndex(where: { $0.moment.id == moment.id }) ?? 0
        reelsPresentation = ActivityReelsPresentation(videos: videos, startIndex: startIndex)
        HapticManager.shared.lightImpact()
    }

    /// Tu actividad abre siempre el detalle single del momento tocado.
    private func openActivityMomentZoom(moment: Moment) {
        zoomActivityMomentsPool = [moment]
        MomentZoomOpener.open(
            moment: moment,
            moments: [moment],
            initialIndex: 0,
            presentation: .single,
            destination: &zoomDestination,
            zoomIDPrefix: "activity",
            chromeTitle: NSLocalizedString(detailNavigationTitleKey, comment: "Interaction detail title")
        )
    }

    private func momentsForZoomDestination(_ destination: MomentZoomDestination) -> [Moment] {
        MomentZoomOpener.resolvedMoments(for: destination, in: zoomActivityMomentsPool)
    }

    private func openRecentlyDeletedStory(_ item: ActivityDeletedStoryItem) {
        let items = filteredDeletedStoryItems
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        recentlyDeletedStoryPresentation = RecentlyDeletedStoriesPresentation(
            stories: items.map(\.story),
            initialIndex: index
        )
    }

    private var reactionsContent: some View {
        activityFilteredScroll { proxy in
            reactionsGridBody(scrollProxy: proxy)
        }
    }

    private var recentlyDeletedStoriesContent: some View {
        activityFilteredScroll { proxy in
            recentlyDeletedStoriesGridBody(scrollProxy: proxy)
        }
    }

    private var commentsContent: some View {
        activityFilteredScroll { _ in
            commentsListBody
        }
    }

    private var momentsContent: some View {
        activityFilteredScroll { _ in
            momentsGridBody
        }
    }

    private var eventsContent: some View {
        activityFilteredScroll { _ in
            eventsListBody
        }
    }

    private func activityFilteredScroll<Content: View>(
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) -> some View {
        ActivityCollapsibleFilterScroll(
            onRefresh: { await performActivityRefresh() },
            header: { activityFiltersHeader },
            content: content
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var activityFiltersHeader: some View {
        VStack(spacing: 0) {
            reactionsFiltersHeader
            if reactionsDateFilter == .custom {
                customDateRangeControls
            }
            if category == .echoes {
                echoesSummaryHeader
            }
        }
    }

    private var activityGridViewportHeight: CGFloat {
        UIScreen.main.bounds.height * 0.62
    }

    private func activityGridColumnSide(containerWidth: CGFloat = UIScreen.main.bounds.width) -> CGFloat {
        let spacing = activityGridSpacing
        return floor((containerWidth - spacing * 2) / 3)
    }

    @ViewBuilder
    private func reactionsGridBody(scrollProxy: ScrollViewProxy) -> some View {
        if filteredReactionItems.isEmpty {
            emptyState(textKey: category.emptyKey)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
        } else {
            let spacing = activityGridSpacing
            let side = activityGridColumnSide()
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(filteredReactionItems.enumerated()), id: \.element.id) { index, item in
                    ActivityReactionMomentCard(
                        item: item,
                        size: side,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedReactionIds.contains(item.id),
                        overlayBadge: reactionCardOverlayBadge
                    )
                    .contentShape(Rectangle())
                    .modifier(ProfileMomentZoomSourceModifier(
                        namespace: item.moment == nil ? nil : zoomNamespace,
                        sourceID: item.moment.map {
                            ProfileMomentZoomNavigation.sourceID(moment: $0, index: index, prefix: "activity-reaction")
                        },
                        cornerRadius: 4
                    ))
                    .id(item.id)
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
                        openActivityMomentZoom(moment: moment)
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
            .padding(.top, 8)
            .padding(.bottom, isSelectionMode ? 88 : 12)
            .modifier(ActivityGridDragSelectionModifier(
                isEnabled: category == .recentlyDeleted && isSelectionMode,
                gesture: recentlyDeletedDragSelectionGesture(
                    items: filteredReactionItems.map(\.id),
                    side: side,
                    spacing: spacing,
                    viewportHeight: activityGridViewportHeight,
                    scrollProxy: scrollProxy,
                    horizontalInset: 0
                )
            ))
        }
    }

    @ViewBuilder
    private func recentlyDeletedStoriesGridBody(scrollProxy: ScrollViewProxy) -> some View {
        if filteredDeletedStoryItems.isEmpty {
            emptyState(textKey: category.emptyKey)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
        } else {
            let spacing: CGFloat = 1
            let side = activityGridColumnSide()
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(filteredDeletedStoryItems.enumerated()), id: \.element.id) { _, item in
                    ActivityDeletedStoryCard(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedReactionIds.contains(item.id)
                    )
                    .contentShape(Rectangle())
                    .id(item.id)
                    .onTapGesture {
                        if longPressActivatedItemId == item.id {
                            longPressActivatedItemId = nil
                            return
                        }
                        if isSelectionMode {
                            toggleSelection(for: item.id)
                            return
                        }
                        openRecentlyDeletedStory(item)
                    }
                    .onLongPressGesture(minimumDuration: 0.3) {
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
            .padding(.top, 8)
            .padding(.bottom, isSelectionMode ? 88 : 12)
            .modifier(ActivityGridDragSelectionModifier(
                isEnabled: isSelectionMode,
                gesture: recentlyDeletedDragSelectionGesture(
                    items: filteredDeletedStoryItems.map(\.id),
                    side: side,
                    spacing: spacing,
                    viewportHeight: activityGridViewportHeight,
                    scrollProxy: scrollProxy,
                    horizontalInset: 0,
                    usesPortraitStoryCells: true
                )
            ))
        }
    }

    @ViewBuilder
    private var momentsGridBody: some View {
        if filteredMoments.isEmpty {
            emptyState(textKey: category.emptyKey)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
        } else {
            let spacing = activityGridSpacing
            let columnWidth = activityGridColumnSide()
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
            let isReelsCategory = category == .reels

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(filteredMoments.enumerated()), id: \.element.id) { index, moment in
                    if isReelsCategory {
                        ActivityPortraitMomentCard(moment: moment)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openActivityReels(moment: moment, moments: filteredMoments)
                            }
                    } else {
                        ScreenshotProtectedView(isProtected: (moment.audience?.lowercased() ?? "") != "everyone") {
                            ModernMomentThumbnail(
                                moment: moment,
                                size: columnWidth,
                                customListNamesById: viewModel.customListNamesById,
                                zoomNamespace: zoomNamespace,
                                zoomSourceID: ProfileMomentZoomNavigation.sourceID(moment: moment, index: index, prefix: "activity"),
                                onTap: {
                                    openActivityMomentZoom(moment: moment)
                                },
                                usesDiscreetAudienceIcon: true
                            )
                            .frame(width: columnWidth, height: columnWidth)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var commentsListBody: some View {
        if filteredCommentItems.isEmpty {
            emptyState(textKey: category.emptyKey)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
        } else {
            VStack(spacing: 10) {
                ForEach(filteredCommentItems) { item in
                    ActivityCommentItemRow(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedCommentIds.contains(item.id),
                        onOpenMoment: {
                            guard item.canView, let moment = item.moment else { return }
                            openActivityMomentZoom(moment: moment)
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

    @ViewBuilder
    private var eventsListBody: some View {
        if filteredEventItems.isEmpty {
            emptyState(textKey: category.emptyKey)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
        } else {
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

    private var filteredDeletedStoryItems: [ActivityDeletedStoryItem] {
        let filteredByDate = viewModel.deletedStoryItems.filter { item in
            switch reactionsDateFilter {
            case .all:
                return true
            case .week:
                let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                return item.deletedAt >= from
            case .month:
                let from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
                return item.deletedAt >= from
            case .year:
                let from = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
                return item.deletedAt >= from
            case .custom:
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
                let endBase = max(customDateFrom, customDateTo)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase
                return item.deletedAt >= start && item.deletedAt <= end
            }
        }

        switch reactionsSort {
        case .newest:
            return filteredByDate.sorted { $0.deletedAt > $1.deletedAt }
        case .oldest:
            return filteredByDate.sorted { $0.deletedAt < $1.deletedAt }
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

    private var reactionsFiltersHeader: some View {
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
                .font(.system(size: legacyPoppinsSize(11), weight: .medium))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.clear.momentsChromeGlass(in: Capsule(), interactive: true)
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
                .font(.system(size: legacyPoppinsSize(11), weight: .semibold))
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
                profileRoute = FeedProfileSheetRoute(userId: actorId)
            }
        case "sticker_reply", "poll", "question":
             // Handle if needed, or default to profile
             if let actorId = item.actorId {
                 profileRoute = FeedProfileSheetRoute(userId: actorId)
             }
        default:
            break
        }
    }

    private var emptyStateSubtitle: String {
        switch category {
        case .reactions:
            return NSLocalizedString("userActivity.simple.empty.reactions.subtitle", value: "Interactions and reactions you leave on other moments will appear here.", comment: "")
        case .comments:
            return NSLocalizedString("userActivity.simple.empty.comments.subtitle", value: "Your conversations, comment replies, and reviews will show up in this space.", comment: "")
        case .tags:
            return NSLocalizedString("userActivity.simple.empty.tags.subtitle", value: "When friends mention or tag you in their moments, they will be listed here.", comment: "")
        case .stickerReplies:
            return NSLocalizedString("userActivity.simple.empty.stickers.subtitle", value: "View interactive questions and poll answers you've responded to.", comment: "")
        case .archived:
            return NSLocalizedString("userActivity.simple.empty.archived.subtitle", value: "Your private, archived moments are safely stored here out of public view.", comment: "")
        case .storiesArchive:
            return NSLocalizedString("archivedStories.empty.subtitle", value: "Your expired stories live here as beautiful memories.", comment: "")
        case .recentlyDeleted:
            return NSLocalizedString("userActivity.simple.empty.recentlyDeleted.subtitle", value: "Items you delete are kept here for 30 days before permanent deletion.", comment: "")
        case .echoes:
            return NSLocalizedString("userActivity.simple.empty.echoes.subtitle", value: "Echoes connect you with mutual friends nearby. Capture a moment to start echoing!", comment: "")
        case .followers:
            return NSLocalizedString("userActivity.simple.empty.followers.subtitle", value: "Track recent follow requests, mutual friends, and profile connections.", comment: "")
        case .visits:
            return NSLocalizedString("userActivity.simple.empty.visits.subtitle", value: "See the friends and followers who checked out your profile recently.", comment: "")
        case .moments:
            return NSLocalizedString("userActivity.simple.empty.moments.subtitle", value: "Your shared grid posts and daily captures will appear here.", comment: "")
        case .reels:
            return NSLocalizedString("userActivity.simple.empty.reels.subtitle", value: "Your immersive video reels and short clips will be saved in this tab.", comment: "")
        case .searches:
            return NSLocalizedString("userActivity.recentSearches.empty.subtitle", value: "Your search history is empty. Start finding friends and trends!", comment: "")
        default:
            return ""
        }
    }

    private func emptyState(textKey: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 20)
            
            if category == .echoes {
                EchoesIconView(
                    size: EchoesIconMetrics.emptyState,
                    gradient: EchoesIconView.echoesBrandGradient
                )
            } else if category == .recentlyDeleted {
                Image(systemName: "trash")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.secondary.opacity(0.55))
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [category.accentColor.opacity(0.12), category.accentColor.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 86, height: 86)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [category.accentColor.opacity(0.25), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: category.accentColor.opacity(0.08), radius: 8, x: 0, y: 4)

                    if category == .reactions {
                        AnimatedReactionIcon()
                            .scaleEffect(1.25)
                    } else if category == .comments {
                        AnimatedCommentIcon()
                            .scaleEffect(1.25)
                    } else if category == .tags {
                        AttachmentIconView(
                            icon: .tagged,
                            preset: .activityEmptyState,
                            tintColor: category.accentColor
                        )
                    } else {
                        Image(systemName: category.icon)
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(category.accentColor)
                    }
                }
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString(textKey, comment: "Empty state text"))
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if !emptyStateSubtitle.isEmpty {
                    Text(emptyStateSubtitle)
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .opacity(0.7)
                }
            }
            
            Spacer()
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var archivedSelectionBar: some View {
        let selectedCount = selectedReactionIds.count
        let countText = String(format: NSLocalizedString("userActivity.simple.reactions.selectedCount", comment: "Selected items count"), selectedCount)

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(countText)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(.gray)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        pendingActivitySelectionConfirmation = .archivedRestore(ids: selectedReactionIds)
                    } label: {
                        Group {
                            if isRestoringArchivedSelection {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(SettingsProfileColors.accent(colorScheme))
                                    Text(NSLocalizedString("userActivity.event.archived.processingButton.restore", comment: "Restoring archived action"))
                                }
                            } else {
                                Text(NSLocalizedString("userActivity.event.archived.action.restore", comment: "Restore action"))
                            }
                        }
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .foregroundColor(SettingsProfileColors.accent(colorScheme))
                    }
                    .disabled(selectedCount == 0 || viewModel.isLoading || isRestoringArchivedSelection)
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var recentlyDeletedSelectionBar: some View {
        let selectedCount = selectedReactionIds.count
        let countText = String(format: NSLocalizedString("userActivity.simple.reactions.selectedCount", comment: "Selected items count"), selectedCount)
        let isProcessing = recentlyDeletedInFlightAction != nil

        return VStack(spacing: 10) {
            Divider()
                .opacity(0.15)

            HStack(spacing: 10) {
                Text("\(selectedCount)")
                    .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(countText)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(.gray)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        toggleAllVisibleRecentlyDeletedSelection()
                    } label: {
                        Text(NSLocalizedString(allVisibleRecentlyDeletedSelected ? "common.clear" : "common.selectAll", comment: "Select all visible deleted content"))
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.78))
                    }
                    .disabled(visibleRecentlyDeletedIds.isEmpty || viewModel.isLoading || isProcessing)

                    Button {
                        pendingActivitySelectionConfirmation = .recentlyDeletedRestore
                    } label: {
                        Group {
                            if recentlyDeletedInFlightAction == .restore {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(colorScheme == .dark ? .white : .black)
                                    Text(NSLocalizedString("userActivity.simple.recentlyDeleted.processingButton.restore", comment: "Restoring action"))
                                }
                            } else {
                                Text(NSLocalizedString("userActivity.simple.recentlyDeleted.restore.single", comment: "Restore action"))
                            }
                        }
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .disabled(selectedCount == 0 || viewModel.isLoading || isProcessing)

                    Button {
                        pendingActivitySelectionConfirmation = .recentlyDeletedDelete
                    } label: {
                        Group {
                            if recentlyDeletedInFlightAction == .permanentlyDelete {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(colorScheme == .dark ? .white : .black)
                                    Text(NSLocalizedString("userActivity.simple.recentlyDeleted.processingButton.delete", comment: "Deleting action"))
                                }
                            } else {
                                Text(NSLocalizedString("userActivity.simple.recentlyDeleted.delete.single", comment: "Delete action"))
                            }
                        }
                        .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                        .foregroundColor(.red)
                    }
                    .disabled(selectedCount == 0 || viewModel.isLoading || isProcessing)
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
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
                    .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(countText)
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    pendingActivitySelectionConfirmation = isTagsCategory ? .tagsRemove : .reactionsDelete
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
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
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
                    .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(String(format: NSLocalizedString("userActivity.simple.comments.selectedCount", comment: "Selected comments count"), selectedCount))
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    pendingActivitySelectionConfirmation = .commentsDelete
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
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
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
                    .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(colorScheme == .dark ? .white : .black).opacity(0.08)))

                Text(String(format: NSLocalizedString("userActivity.simple.stickers.selectedCount", comment: "Selected sticker replies count"), selectedCount))
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundColor(.gray)

                Spacer()

                Button {
                    pendingActivitySelectionConfirmation = .stickerRepliesDelete
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
                            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
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

    private func recentlyDeletedDragSelectionGesture(
        items: [String],
        side: CGFloat,
        spacing: CGFloat,
        viewportHeight: CGFloat,
        scrollProxy: ScrollViewProxy,
        horizontalInset: CGFloat? = nil,
        usesPortraitStoryCells: Bool = false
    ) -> some Gesture {
        let resolvedHorizontalInset = horizontalInset ?? sectionHorizontalPadding

        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard category == .recentlyDeleted, isSelectionMode else { return }

                updateRecentlyDeletedAutoScroll(
                    for: value.location.y,
                    viewportHeight: viewportHeight,
                    items: items,
                    scrollProxy: scrollProxy
                )

                guard let id = recentlyDeletedItemId(
                    at: value.location,
                    items: items,
                    side: side,
                    spacing: spacing,
                    horizontalInset: resolvedHorizontalInset,
                    usesPortraitStoryCells: usesPortraitStoryCells
                ),
                let currentIndex = items.firstIndex(of: id) else { return }

                if gridSelectionDragMode == nil {
                    gridSelectionDragMode = selectedReactionIds.contains(id) ? .deselecting : .selecting
                    applyRecentlyDeletedDragSelection(to: id)
                    recentlyDeletedDragCurrentId = id
                    return
                }

                if let lastId = recentlyDeletedDragCurrentId,
                   let lastIndex = items.firstIndex(of: lastId),
                   lastIndex != currentIndex {
                    let indices = recentlyDeletedGridIndicesBetween(
                        from: lastIndex,
                        to: currentIndex,
                        itemCount: items.count
                    )
                    for index in indices {
                        applyRecentlyDeletedDragSelection(to: items[index])
                    }
                } else {
                    applyRecentlyDeletedDragSelection(to: id)
                }

                recentlyDeletedDragCurrentId = id
            }
            .onEnded { _ in
                stopRecentlyDeletedAutoScroll()
            }
    }

    private func recentlyDeletedGridIndicesBetween(
        from startIndex: Int,
        to endIndex: Int,
        itemCount: Int,
        columns: Int = 3
    ) -> [Int] {
        let startRow = startIndex / columns
        let startCol = startIndex % columns
        let endRow = endIndex / columns
        let endCol = endIndex % columns
        let minRow = min(startRow, endRow)
        let maxRow = max(startRow, endRow)
        let minCol = min(startCol, endCol)
        let maxCol = max(startCol, endCol)

        var indices: [Int] = []
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                let index = row * columns + col
                if index < itemCount {
                    indices.append(index)
                }
            }
        }
        return indices
    }

    private func recentlyDeletedItemId(
        at location: CGPoint,
        items: [String],
        side: CGFloat,
        spacing: CGFloat,
        horizontalInset: CGFloat,
        usesPortraitStoryCells: Bool = false
    ) -> String? {
        let x = location.x - horizontalInset
        let y = location.y - 8
        guard x >= 0, y >= 0 else { return nil }

        let columnWidth = side + spacing
        let cellHeight = usesPortraitStoryCells ? (side * 16.0 / 9.0) : side
        let rowHeight = cellHeight + spacing
        guard columnWidth > 0, rowHeight > 0 else { return nil }

        let column = Int(x / columnWidth)
        let row = Int(y / rowHeight)
        guard (0..<3).contains(column) else { return nil }

        let columnRemainder = x.truncatingRemainder(dividingBy: columnWidth)
        let rowRemainder = y.truncatingRemainder(dividingBy: rowHeight)
        guard columnRemainder <= side, rowRemainder <= cellHeight else { return nil }

        let index = row * 3 + column
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func applyRecentlyDeletedDragSelection(to id: String) {
        switch gridSelectionDragMode {
        case .selecting:
            selectedReactionIds.insert(id)
        case .deselecting:
            selectedReactionIds.remove(id)
        case .none:
            break
        }
    }

    private func updateRecentlyDeletedAutoScroll(
        for locationY: CGFloat,
        viewportHeight: CGFloat,
        items: [String],
        scrollProxy: ScrollViewProxy
    ) {
        let edgeThreshold: CGFloat = 96
        let direction: RecentlyDeletedAutoScrollDirection?
        if locationY <= edgeThreshold {
            direction = .up
        } else if locationY >= (viewportHeight - edgeThreshold) {
            direction = .down
        } else {
            direction = nil
        }

        guard direction != recentlyDeletedAutoScrollDirection else { return }
        if let direction {
            startRecentlyDeletedAutoScroll(direction: direction, items: items, scrollProxy: scrollProxy)
        } else {
            stopRecentlyDeletedAutoScroll()
        }
    }

    private func startRecentlyDeletedAutoScroll(
        direction: RecentlyDeletedAutoScrollDirection,
        items: [String],
        scrollProxy: ScrollViewProxy
    ) {
        stopRecentlyDeletedAutoScroll(resetSelectionState: false)
        recentlyDeletedAutoScrollDirection = direction

        recentlyDeletedAutoScrollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000)
                await MainActor.run {
                    advanceRecentlyDeletedAutoScroll(direction: direction, items: items, scrollProxy: scrollProxy)
                }
            }
        }
    }

    private func advanceRecentlyDeletedAutoScroll(
        direction: RecentlyDeletedAutoScrollDirection,
        items: [String],
        scrollProxy: ScrollViewProxy
    ) {
        guard category == .recentlyDeleted, isSelectionMode else {
            stopRecentlyDeletedAutoScroll()
            return
        }
        guard !items.isEmpty else { return }
        guard let currentId = recentlyDeletedDragCurrentId,
              let currentIndex = items.firstIndex(of: currentId) else { return }

        let proposedIndex = direction == .down ? currentIndex + 1 : currentIndex - 1
        let targetIndex = min(max(proposedIndex, 0), items.count - 1)
        guard targetIndex != currentIndex else { return }

        let indices = recentlyDeletedGridIndicesBetween(
            from: currentIndex,
            to: targetIndex,
            itemCount: items.count
        )
        for index in indices {
            applyRecentlyDeletedDragSelection(to: items[index])
        }

        recentlyDeletedDragCurrentId = items[targetIndex]
        withAnimation(.linear(duration: 0.08)) {
            scrollProxy.scrollTo(items[targetIndex], anchor: .center)
        }
    }

    private func stopRecentlyDeletedAutoScroll(resetSelectionState: Bool = true) {
        recentlyDeletedAutoScrollTask?.cancel()
        recentlyDeletedAutoScrollTask = nil
        recentlyDeletedAutoScrollDirection = nil
        if resetSelectionState {
            gridSelectionDragMode = nil
            recentlyDeletedDragCurrentId = nil
        }
    }

    private var visibleRecentlyDeletedIds: [String] {
        if category == .recentlyDeleted, recentlyDeletedKind == .stories {
            return filteredDeletedStoryItems.map(\.id)
        }
        return filteredReactionItems.map(\.id)
    }

    private var allVisibleRecentlyDeletedSelected: Bool {
        let ids = visibleRecentlyDeletedIds
        return !ids.isEmpty && Set(ids).isSubset(of: selectedReactionIds)
    }

    private func toggleAllVisibleRecentlyDeletedSelection() {
        let ids = visibleRecentlyDeletedIds
        guard !ids.isEmpty else { return }

        if allVisibleRecentlyDeletedSelected {
            selectedReactionIds.subtract(ids)
        } else {
            selectedReactionIds.formUnion(ids)
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

    private func selectionSuccessBanner(textKey: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "22C55E"))

            Text(NSLocalizedString(textKey, comment: "Selection success banner"))
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 16, y: 6)
    }

    private func processingBanner(titleKey: String, subtitleKey: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(colorScheme == .dark ? .white : .black)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(titleKey, comment: "Processing title"))
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text(NSLocalizedString(subtitleKey, comment: "Processing subtitle"))
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundColor(.gray)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 16, y: 6)
    }

    private func recentlyDeletedProcessingTitleKey(for action: RecentlyDeletedConfirmationAction) -> String {
        switch action {
        case .restore:
            return "userActivity.simple.recentlyDeleted.processing.restore"
        case .permanentlyDelete:
            return "userActivity.simple.recentlyDeleted.processing.delete"
        }
    }

    private func activitySelectionConfirmationAlert(for action: ActivitySelectionConfirmationAction) -> Alert {
        switch action {
        case .archivedRestore(let ids):
            return Alert(
                title: Text(NSLocalizedString("userActivity.event.archived.confirm.restore.title", comment: "Archived restore confirmation title")),
                message: Text(NSLocalizedString("userActivity.event.archived.confirm.restore.message", comment: "Archived restore confirmation message")),
                primaryButton: .default(
                    Text(NSLocalizedString("userActivity.event.archived.action.restore", comment: "Restore action")),
                    action: {
                        Task { await performArchivedRestore(ids: ids) }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .recentlyDeletedRestore:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.recentlyDeleted.confirm.restore.title", comment: "Restore recently deleted confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.recentlyDeleted.confirm.restore.message", comment: "Restore recently deleted confirmation message")),
                primaryButton: .default(
                    Text(NSLocalizedString("userActivity.simple.recentlyDeleted.restore.single", comment: "Restore action")),
                    action: {
                        Task { await performRecentlyDeletedRestore() }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .recentlyDeletedDelete:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.recentlyDeleted.confirm.delete.title", comment: "Delete recently deleted confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.recentlyDeleted.confirm.delete.message", comment: "Delete recently deleted confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.recentlyDeleted.delete.single", comment: "Delete action")),
                    action: {
                        Task { await performRecentlyDeletedPermanentDelete() }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .reactionsDelete:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.reactions.confirm.delete.title", comment: "Reactions delete confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.reactions.confirm.delete.message", comment: "Reactions delete confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.reactions.delete.single", comment: "Delete reaction")),
                    action: {
                        Task { await deleteSelectedReactions() }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .tagsRemove:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.tags.confirm.remove.title", comment: "Tags remove confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.tags.confirm.remove.message", comment: "Tags remove confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.tags.remove.single", comment: "Remove tag")),
                    action: {
                        Task { await removeSelectedTags() }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .commentsDelete:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.comments.confirm.delete.title", comment: "Comments delete confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.comments.confirm.delete.message", comment: "Comments delete confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.comments.delete.single", comment: "Delete comment")),
                    action: {
                        Task { await deleteSelectedComments() }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        case .stickerRepliesDelete:
            return Alert(
                title: Text(NSLocalizedString("userActivity.simple.stickers.confirm.delete.title", comment: "Sticker replies delete confirmation title")),
                message: Text(NSLocalizedString("userActivity.simple.stickers.confirm.delete.message", comment: "Sticker replies delete confirmation message")),
                primaryButton: .destructive(
                    Text(NSLocalizedString("userActivity.simple.stickers.delete.single", comment: "Delete sticker reply")),
                    action: {
                        Task { await deleteSelectedEvents() }
                    }
                ),
                secondaryButton: .cancel(Text(NSLocalizedString("common.cancel", comment: "Cancel")))
            )
        }
    }

    private func performArchivedRestore(ids: Set<String>) async {
        guard !ids.isEmpty else { return }

        await MainActor.run {
            isRestoringArchivedSelection = true
        }

        let result = await viewModel.unarchiveSelection(withIds: ids)
        await MainActor.run {
            isRestoringArchivedSelection = false
            switch result {
            case .success:
                selectedReactionIds.subtract(ids)
                if selectedReactionIds.isEmpty {
                    isSelectionMode = false
                }
                showActivitySelectionSuccessBanner("userActivity.event.archived.success.restore")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func performRecentlyDeletedRestore() async {
        await MainActor.run {
            recentlyDeletedInFlightAction = .restore
        }
        let result = await viewModel.restoreSelection(withIds: selectedReactionIds)
        await MainActor.run {
            recentlyDeletedInFlightAction = nil
            switch result {
            case .success:
                selectedReactionIds.removeAll()
                isSelectionMode = false
                showRecentlyDeletedSuccessBanner("userActivity.simple.recentlyDeleted.success.restore")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func performRecentlyDeletedPermanentDelete() async {
        await MainActor.run {
            recentlyDeletedInFlightAction = .permanentlyDelete
        }
        let result = await viewModel.permanentlyDeleteSelection(withIds: selectedReactionIds)
        await MainActor.run {
            recentlyDeletedInFlightAction = nil
            switch result {
            case .success:
                selectedReactionIds.removeAll()
                isSelectionMode = false
                showRecentlyDeletedSuccessBanner("userActivity.simple.recentlyDeleted.success.delete")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func showRecentlyDeletedSuccessBanner(_ textKey: String) {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
            recentlyDeletedSuccessBannerKey = textKey
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard recentlyDeletedSuccessBannerKey == textKey else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    recentlyDeletedSuccessBannerKey = nil
                }
            }
        }
    }

    private func showActivitySelectionSuccessBanner(_ textKey: String) {
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.header) {
            activitySelectionSuccessBannerKey = textKey
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard activitySelectionSuccessBannerKey == textKey else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    activitySelectionSuccessBannerKey = nil
                }
            }
        }
    }

    private func openAuthor(authorId: String, hasStory: Bool) {
        guard !authorId.isEmpty else { return }
        if hasStory {
            storyRoute = IdentifiableString(id: authorId)
        } else {
            profileRoute = FeedProfileSheetRoute(userId: authorId)
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
                showActivitySelectionSuccessBanner("userActivity.simple.reactions.success.delete")
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
                showActivitySelectionSuccessBanner("userActivity.simple.tags.success.remove")
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
                showActivitySelectionSuccessBanner("userActivity.simple.comments.success.delete")
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
                showActivitySelectionSuccessBanner("userActivity.simple.stickers.success.delete")
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ActivityGridDragSelectionModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

private struct InlineNavigationTitleModifier: ViewModifier {
    let titleKey: String
    let isSuppressed: Bool

    func body(content: Content) -> some View {
        if isSuppressed {
            content
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
                .navigationTitle(NSLocalizedString(titleKey, comment: "Interaction detail title"))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
