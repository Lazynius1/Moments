import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Kingfisher
import AVFoundation

// MARK: - Vista Principal de Explorar
struct ExploreView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.momentsToolbarVerticalEdge) private var toolbarVerticalEdge
    @Environment(\.momentsDivisionRegions) private var divisionRegions
    /// `onHingeChange` (iOS 27.1). En iPhone no hay bisagra y se queda en `.unknown`.
    @State private var hingePose: ExploreHingePose = .unknown
    @StateObject private var viewModel = ExploreViewModel()
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var didApplyInitialQuery = false
    @State private var showPrivateProfileAlert: Bool = false
    @Namespace private var zoomNamespace
    @Namespace private var profileZoomNamespace
    @State private var zoomDestination: MomentZoomDestination?
    @State private var selectedProfileRoute: FeedProfileSheetRoute?
    @State private var showDiscoverMap = false
    /// Perfil abierto en la segunda pantalla. No empuja la navegación del mosaico.
    @State private var paneProfileRoute: FeedProfileSheetRoute?
    /// Momento abierto en la pantalla del mosaico.
    @State private var paneZoomDestination: MomentZoomDestination?
    /// Post visible en el detalle. Sobrevive a abrir y cerrar, cuando esa vista se vuelve a crear.
    @State private var paneDetailMomentId: String?

    @State private var showSuggestedUsersView = false
    /// Lista de «Ver más» en la segunda pantalla, debajo del perfil si hay uno abierto.
    @State private var paneSuggestedUsers = false
    /// Perfil que la lista empujada tenía abierto al cerrar el Duo.
    @State private var compactSuggestedProfile: FeedProfileSheetRoute?
    let initialSearchQuery: String?
    let isDismissable: Bool
    let isTabActive: Bool

    init(
        initialSearchQuery: String? = nil,
        isDismissable: Bool = false,
        isTabActive: Bool = true
    ) {
        self.initialSearchQuery = initialSearchQuery
        self.isDismissable = isDismissable
        self.isTabActive = isTabActive
    }

    var body: some View {
        exploreNavigationStack
            .momentZoomNavigationSurface(colorScheme: colorScheme)
    }

    private var exploreNavigationStack: some View {
        NavigationStack {
            exploreNavigationRoot
        }
    }

    private var exploreNavigationRoot: some View {
        exploreSearchableContent
            .tint(.primary)
            .onSubmit(of: .search) {
                viewModel.saveSearchRecord(query: searchText, type: "text")
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.smartSearch(query: newValue)
            }
            .onChange(of: isTabActive) { wasActive, active in
                guard wasActive, !active else { return }
                clearSearchSession()
            }
            .onAppear(perform: handleExploreAppear)
            .alert("explore.privateProfile.title", isPresented: $showPrivateProfileAlert) {
                Button("common.ok") { }
            } message: {
                Text("explore.privateProfile.message")
            }
            .userProfileNavigationDestination(
                item: $selectedProfileRoute,
                namespace: profileZoomNamespace
            )
            .navigationDestination(item: $zoomDestination) { destination in
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: zoomNamespace
                )
            }
            .navigationDestination(isPresented: $showDiscoverMap) {
                DiscoverMapView(isPresented: $showDiscoverMap)
            }
            .navigationDestination(isPresented: $showSuggestedUsersView) {
                SuggestedUsersView(
                    initialProfile: compactSuggestedProfile,
                    onProfileChange: { compactSuggestedProfile = $0 }
                )
            }
            .onChange(of: searchText) { _, _ in
                paneProfileRoute = nil
                paneZoomDestination = nil
                paneSuggestedUsers = false
            }
    }

    private var exploreSearchableContent: some View {
        exploreChrome
            .modifier(ExploreSearchModifier(
                isEnabled: !showsCompactDuoDetail,
                searchText: $searchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                suggestions: exploreRecentSearchSuggestions
            ))
    }

    private var exploreChrome: some View {
        mainContent
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle(showsCompactDuoDetail ? "" : NSLocalizedString("explore.title", comment: ""))
            .navigationBarTitleDisplayMode(showsCompactDuoDetail ? .inline : .large)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if !showsCompactDuoDetail {
                    if #available(iOS 27.1, *), usesDuoExploreChrome {
                        duoExploreToolbar
                    } else {
                        exploreToolbarContent
                    }
                }
            }
    }

    @ToolbarContentBuilder
    private var exploreToolbarContent: some ToolbarContent {
        if isDismissable {
            ToolbarItem(placement: .topBarLeading) {
                ProfileChromeIconButton(
                    systemName: "chevron.left",
                    foregroundColor: .primary,
                    preset: .navigationBack,
                    action: {
                        ExploreHapticFeedback.impact(.light)
                        clearSearchSession()
                        dismiss()
                    }
                )
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            exploreMapButton
        }
    }

    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    private var duoExploreToolbar: some ToolbarContent {
        if isDismissable {
            ToolbarItem(placement: .topBarLeading) {
                ProfileChromeIconButton(
                    systemName: "chevron.left",
                    foregroundColor: .primary,
                    preset: .navigationBack,
                    action: {
                        ExploreHapticFeedback.impact(.light)
                        clearSearchSession()
                        dismiss()
                    }
                )
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            exploreMapButton
        }
        .axisBehavior(.verticalPreferred)
    }

    private var exploreMapButton: some View {
        Button {
            ExploreHapticFeedback.impact(.medium)
            showDiscoverMap = true
        } label: {
            Label(NSLocalizedString("maps.discover.title", comment: ""), systemImage: "map.fill")
        }
        .tint(Color(hex: "0A84FF"))
    }

    @ViewBuilder
    private var exploreRecentSearchSuggestions: some View {
        if searchText.isEmpty && !viewModel.recentSearches.isEmpty {
            Section {
                ForEach(viewModel.recentSearches) { search in
                    ExploreRecentSearchRow(
                        search: search,
                        socialStatus: search.targetId.flatMap { viewModel.getSocialStatus(userId: $0) },
                        typeIcon: searchTypeIcon(for: search.type),
                        onSelect: {
                            searchText = search.query
                            viewModel.saveSearchRecord(
                                query: search.query,
                                type: search.type,
                                targetId: search.targetId
                            )
                            viewModel.smartSearch(query: search.query)
                        },
                        onDelete: {
                            viewModel.deleteSearch(search)
                        }
                    )
                    .searchCompletion(search.query)
                }
            } header: {
                exploreRecentSearchesHeader
            }
        }
    }

    private var exploreRecentSearchesHeader: some View {
        HStack {
            Text(NSLocalizedString("explore.recentSearches.title", comment: ""))
                .font(.system(size: legacyPoppinsSize(17), weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button(NSLocalizedString("explore.recentSearches.clearAll", comment: "")) {
                viewModel.clearAllSearches()
            }
            .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
            .foregroundStyle(.primary)
        }
        .textCase(nil)
        .padding(.vertical, 8)
    }

    private func handleExploreAppear() {
        if !didApplyInitialQuery {
            didApplyInitialQuery = true
            if let query = initialSearchQuery, !query.isEmpty { searchText = query }
        }
        if viewModel.moments.isEmpty && !viewModel.isLoading {
            viewModel.fetchMomentsByInterests()
        }
    }

    private func searchTypeIcon(for type: String) -> String {
        switch type {
        case "hashtag": return "number"
        case "location": return "mappin.and.ellipse"
        case "user": return "person.fill" // Fallback si no hay foto
        default: return "clock"
        }
    }

    private func clearSearchSession() {
        isSearchFieldFocused = false
        searchText = ""
    }

    // MARK: - Componentes de la Vista

    private var exploreCanvas: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var backgroundGradient: some View {
        ZStack {
            if colorScheme == .dark {
                Color(hex: "0B1215")
                    .ignoresSafeArea()
            } else {
                Color(hex: "FAF9F6")
                    .ignoresSafeArea()
            }
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            Group {
                if searchText.isEmpty && viewModel.isLoading && viewModel.moments.isEmpty && viewModel.errorMessage == nil {
                    LoadingStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else if let errorMessage = viewModel.errorMessage, viewModel.moments.isEmpty, searchText.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        viewModel.fetchMomentsByInterests()
                    }
                } else {
                    ZStack {
                        MomentsStableSplit(
                            usesDuo: usesDuoExploreChrome,
                            expanded: usesExpandedExplore,
                            beside: peopleAreBesideMosaic
                        ) {
                            contentScrollView
                        } secondary: {
                            expandedSecondaryPane
                                .environment(\.exploreSecondaryClose, closeExploreSecondary)
                        }
                        if showsCompactDuoDetail {
                            compactDuoDetail
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage, !viewModel.moments.isEmpty {
                AppErrorBanner(message: errorMessage) {
                    viewModel.fetchMomentsByInterests()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(ExploreHingeObserver(pose: $hingePose))
    }

    /// Duo con barra vertical, pliegue o bisagra. El iPhone no entra aquí.
    private var usesDuoExploreChrome: Bool {
        toolbarVerticalEdge != nil || !divisionRegions.isEmpty || hingePose != .unknown
    }

    /// Abierto: mosaico y personas en pantallas distintas. Cerrado e iPhone: el scroll de siempre.
    private var usesExpandedExplore: Bool {
        guard usesDuoExploreChrome else { return false }
        if hingePose == .closed { return false }
        if hingePose == .partiallyOpen || hingePose == .fullyOpen { return true }
        return !divisionRegions.isEmpty
    }

    /// Bisagra vertical: personas al lado. Si no, en la pantalla de abajo.
    private var peopleAreBesideMosaic: Bool {
        if let division = divisionRegions.first(where: { $0.width > 1 && $0.height > 1 }) {
            return division.height >= division.width
        }
        return toolbarVerticalEdge != nil
    }

    /// Cerrado con un detalle: esa pantalla ocupa el Duo. Abierto: vuelve al split con el mismo estado.
    private var showsCompactDuoDetail: Bool {
        guard usesDuoExploreChrome, !usesExpandedExplore else { return false }
        return paneZoomDestination != nil || paneProfileRoute != nil || paneSuggestedUsers
    }

    private var compactDuoDetail: some View {
        expandedSecondaryPane
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(exploreCanvas)
            .environment(\.exploreSecondaryClose, closeExploreSecondary)
    }

    private var closeExploreSecondary: () -> Void {
        {
            if paneZoomDestination != nil {
                paneZoomDestination = nil
            } else if paneProfileRoute != nil {
                paneProfileRoute = nil
            } else {
                paneSuggestedUsers = false
            }
        }
    }

    @ViewBuilder
    private var expandedSecondaryPane: some View {
        if let destination = paneZoomDestination {
            NavigationStack {
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: zoomNamespace,
                    continuityMomentId: paneDetailMomentId,
                    onVisibleMomentId: { paneDetailMomentId = $0 }
                )
                .id(destination.zoomSourceID)
                .toolbar(.visible, for: .navigationBar)
            }
        } else if let route = paneProfileRoute {
            NavigationStack {
                UserProfileView(userId: route.userId)
                    .id(route.userId)
            }
        } else if paneSuggestedUsers {
            NavigationStack {
                SuggestedUsersView(onUserTap: { userId in
                    paneZoomDestination = nil
                    paneProfileRoute = FeedProfileSheetRoute(userId: userId)
                })
            }
        } else {
            expandedPeoplePane
        }
    }

    @ViewBuilder
    private var expandedPeoplePane: some View {
        if searchText.isEmpty {
            SuggestedUsersPane(
                users: viewModel.suggestedUsers,
                onUserTap: { user in
                    openProfile(user.id)
                    viewModel.checkCanViewContent(for: user.id) { _ in }
                },
                onShowMore: openSuggestedUsers,
                profileZoomNamespace: profileZoomNamespace
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                searchResultsSection(pane: .people)
            }
            .momentsScrollEdgeChrome()
        }
    }

    private func openSuggestedUsers() {
        if usesDuoExploreChrome {
            paneZoomDestination = nil
            paneProfileRoute = nil
            paneSuggestedUsers = true
        } else {
            compactSuggestedProfile = nil
            showSuggestedUsersView = true
        }
    }

    private func openProfile(_ userId: String) {
        let route = FeedProfileSheetRoute(userId: userId)
        if usesDuoExploreChrome {
            paneZoomDestination = nil
            paneProfileRoute = route
        } else {
            selectedProfileRoute = route
        }
    }

    private var contentScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                if searchText.isEmpty {
                    if !usesExpandedExplore {
                        suggestedUsersSection
                    }

                    if !viewModel.moments.isEmpty {
                        ExploreMomentsBentoGrid(
                            moments: viewModel.moments,
                            zoomNamespace: zoomNamespace,
                            onMomentTap: handleMomentTap
                        )
                    }
                    ExplorePagingFooter(isLoading: viewModel.isLoadingMoreExplore, failed: viewModel.explorePageFailed,
                        hasMore: viewModel.hasMoreExplore, onLoadMore: viewModel.loadMoreExplore,
                        onRetry: viewModel.loadMoreExplore)
                } else {
                    searchResultsSection(pane: usesExpandedExplore ? .moments : .combined)
                }
            }
        }
        .momentRefresh {
            if searchText.isEmpty { viewModel.refreshAllContent() } else { viewModel.retrySearch() }
            // Mantener la gota visible mientras arranca la recarga.
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        .momentsScrollEdgeChrome()
    }

        private var suggestedUsersSection: some View {
            SuggestedUsersSection(
                users: viewModel.suggestedUsers,
                onUserTap: { user in
                    openProfile(user.id)
                    viewModel.checkCanViewContent(for: user.id) { _ in }
                },
                onShowMore: openSuggestedUsers,
                profileZoomNamespace: profileZoomNamespace
            )
            .onAppear {
                for user in viewModel.suggestedUsers {
                    viewModel.checkUserButtonState(for: user.id)
                }
                // ✅ Filtrar usuarios seguidos después de verificar estados
                viewModel.filterFollowedUsersFromSuggestions()
            }
        }

        // MARK: - Handlers
        private func handleMomentTap(_ moment: Moment, index: Int, sourceMoments: [Moment]) {
            viewModel.checkCanViewContent(for: moment.authorId) { canView in
                if canView {
                    openMomentZoom(
                        moment: moment,
                        index: index,
                        moments: sourceMoments,
                        presentation: .explorer,
                        zoomIDPrefix: "explore"
                    )
                } else {
                    showPrivateProfileAlert = true
                }
            }
        }

        private func openMomentZoom(
            moment: Moment,
            index: Int,
            moments: [Moment],
            presentation: MomentZoomPresentationKind,
            zoomIDPrefix: String
        ) {
            preserveSearchSessionForNavigation()
            ForYouPreferences.shared.recordOpenedMoment(moment)
            let resolvedIndex = moments.firstIndex(where: { $0.id == moment.id }) ?? index
            let destination = MomentZoomDestination(
                zoomSourceID: ProfileMomentZoomNavigation.sourceID(
                    moment: moment,
                    index: resolvedIndex,
                    prefix: zoomIDPrefix
                ),
                initialIndex: resolvedIndex,
                initialMomentId: moment.id,
                presentation: presentation
            )
            paneDetailMomentId = moment.id
            if usesDuoExploreChrome {
                paneProfileRoute = nil
                paneZoomDestination = destination
            } else {
                zoomDestination = destination
            }
            HapticManager.shared.lightImpact()
        }

        /// Al volver desde un resultado conservamos la consulta y su lista,
        /// pero no reabrimos el teclado automáticamente.
        private func preserveSearchSessionForNavigation() {
            guard !searchText.isEmpty else { return }
            isSearchFieldFocused = false
        }

        private func momentsForZoomDestination(_ destination: MomentZoomDestination) -> [Moment] {
            let pool = searchText.isEmpty ? viewModel.moments : viewModel.filteredMoments
            return MomentZoomOpener.resolvedMoments(for: destination, in: pool)
        }

        // Removed redundant momentsSection property

        private func searchResultsSection(pane: ExploreSearchPane = .combined) -> some View {
            SmartSearchResultsView(
                searchQuery: searchText,
                isLoading: viewModel.isSearching,
                failed: viewModel.searchFailed,
                hasMore: viewModel.hasMoreSearchResults,
                filter: searchText.hasPrefix("#") ? "hashtag" : searchText.hasPrefix("@") ? "username" : viewModel.searchFilter,
                onFilter: { filter in
                    if searchText.hasPrefix("#") || searchText.hasPrefix("@") { searchText = String(searchText.dropFirst()) }
                    viewModel.setSearchFilter(filter)
                },
                onLoadMore: viewModel.loadMoreSearchResults,
                onRetry: viewModel.retrySearch,
                users: viewModel.searchedUsers,
                moments: viewModel.filteredMoments,
                userButtonStates: viewModel.userButtonStates,
                currentUserInterests: viewModel.currentUserInterests,
                onFollowUser: viewModel.followUser,
                onUserTap: { user in
                    preserveSearchSessionForNavigation()
                    openProfile(user.id)
                    viewModel.checkCanViewContent(for: user.id) { _ in }
                    // ✅ Guardar en historial
                    viewModel.saveSearchRecord(query: user.username, type: "user", targetId: user.id)
                },
                zoomNamespace: zoomNamespace,
                profileZoomNamespace: profileZoomNamespace,
                onMomentTap: { moment, index, sourceMoments in
                    viewModel.checkCanViewContent(for: moment.authorId) { canView in
                        if canView {
                            openMomentZoom(
                                moment: moment,
                                index: index,
                                moments: sourceMoments,
                                presentation: .single,
                                zoomIDPrefix: "explore-search"
                            )
                        } else {
                            showPrivateProfileAlert = true
                        }
                    }
                }, pane: pane
            )
            .onAppear {
                // Cargar estados de botones para usuarios encontrados
                for user in viewModel.searchedUsers {
                    viewModel.checkUserButtonState(for: user.id)
                }

                // Cargar perfiles de autores para momentos encontrados
                for moment in viewModel.filteredMoments {
                    viewModel.loadAuthorProfile(for: moment.authorId)
                }
            }
        }
    }

// MARK: - Fila de búsqueda reciente (extraída para aligerar type-check de ExploreView)
private struct ExploreRecentSearchRow: View {
    let search: CachedSearch
    let socialStatus: String?
    let typeIcon: String
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                recentSearchLeadingIcon

                VStack(alignment: .leading, spacing: 0) {
                    Text(search.query)
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(.primary)

                    if let socialStatus {
                        Text(socialStatus)
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recentSearchLeadingIcon: some View {
        if search.type == "user", let targetId = search.targetId {
            StoryRingAvatarView(
                userId: targetId,
                size: 32,
                lineWidth: 2.0
            )
            .onTapGesture {
                guard !targetId.isEmpty else { return }
                LegacyNavigationBridge.profile(userId: targetId)
            }
        } else {
            Image(systemName: typeIcon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}

private struct ExploreSearchModifier<Suggestions: View>: ViewModifier {
    let isEnabled: Bool
    @Binding var searchText: String
    var isSearchFieldFocused: FocusState<Bool>.Binding
    let suggestions: Suggestions

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: NSLocalizedString("explore.search.placeholder", comment: "")
                )
                .searchFocused(isSearchFieldFocused)
                .searchSuggestions { suggestions }
        } else {
            content
        }
    }
}

/// En iOS 26 el toolbar nativo ya aplica Liquid Glass; añadir glass manual duplica capas.
private struct ExploreToolbarIconGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
        }
    }
}

private struct ExploreSecondaryCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Cierra el momento o el perfil incrustado en la segunda pantalla de Explorar.
    var exploreSecondaryClose: (() -> Void)? {
        get { self[ExploreSecondaryCloseKey.self] }
        set { self[ExploreSecondaryCloseKey.self] = newValue }
    }
}

private enum ExploreHingePose {
    case unknown
    case closed
    case partiallyOpen
    case fullyOpen
}

/// `onHingeChange` (SDK 27.1). Cerrada o sin bisagra: Explorar se queda en el scroll del iPhone.
private struct ExploreHingeObserver: ViewModifier {
    @Binding var pose: ExploreHingePose

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                switch context.hinge?.status {
                case .partiallyOpen:
                    pose = .partiallyOpen
                case .fullyOpen:
                    pose = .fullyOpen
                case .closed:
                    pose = .closed
                default:
                    pose = .unknown
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Previews
struct ExploreView_Previews: PreviewProvider {
    static var previews: some View {
        ExploreView()
            .preferredColorScheme(.light)

        ExploreView()
            .preferredColorScheme(.dark)
    }
}
