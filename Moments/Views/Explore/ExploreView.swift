import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Kingfisher
import AVFoundation

// MARK: - Vista Principal de Explorar
struct ExploreView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ExploreViewModel()
    @State private var searchText: String = ""
    @State private var showPrivateProfileAlert: Bool = false
    @Namespace private var zoomNamespace
    @Namespace private var profileZoomNamespace
    @State private var zoomDestination: MomentZoomDestination?
    @State private var selectedUser: AppUser?
    @State private var showDiscoverMap = false

    @State private var showSuggestedUsersView = false
    let initialSearchQuery: String?
    let isDismissable: Bool

    init(initialSearchQuery: String? = nil, isDismissable: Bool = false) {
        self.initialSearchQuery = initialSearchQuery
        self.isDismissable = isDismissable
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
            .onAppear(perform: handleExploreAppear)
            .alert(isPresented: $showPrivateProfileAlert) {
                privateProfileAlert
            }
            .fullScreenCover(item: $selectedUser) { user in
                UserProfileView(userId: user.id)
                    .userProfileZoomDestination(userId: user.id, namespace: profileZoomNamespace)
            }
            .navigationDestination(item: $zoomDestination) { destination in
                MomentZoomDetailDestination(
                    destination: destination,
                    moments: momentsForZoomDestination(destination),
                    namespace: zoomNamespace
                )
            }
            .fullScreenCover(isPresented: $showDiscoverMap) {
                DiscoverMapView(isPresented: $showDiscoverMap)
            }
            .sheet(isPresented: $showSuggestedUsersView) {
                SuggestedUsersView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
            }
    }

    private var exploreSearchableContent: some View {
        mainContent
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("explore.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { exploreToolbarContent }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: NSLocalizedString("explore.search.placeholder", comment: "")
            )
            .searchSuggestions {
                exploreRecentSearchSuggestions
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
                        dismiss()
                    }
                )
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                ExploreHapticFeedback.impact(.medium)
                showDiscoverMap = true
            } label: {
                Image(systemName: "map.fill")
                    .foregroundColor(Color(hex: "0A84FF"))
            }

            Button {
                ExploreHapticFeedback.impact(.medium)
                viewModel.refreshAllContent()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(
                        viewModel.isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isLoading
                    )
            }
        }
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
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(.primary)
            Spacer()
            Button(NSLocalizedString("explore.recentSearches.clearAll", comment: "")) {
                viewModel.clearAllSearches()
            }
            .font(.custom("Poppins-Bold", size: 14))
            .foregroundColor(.primary)
        }
        .textCase(nil)
        .padding(.vertical, 8)
    }

    private func handleExploreAppear() {
        if let query = initialSearchQuery, !query.isEmpty {
            searchText = query
            if !viewModel.moments.isEmpty {
                viewModel.smartSearch(query: query)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.smartSearch(query: query)
                }
            }
        }

        if viewModel.moments.isEmpty {
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

    // MARK: - Componentes de la Vista

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
                if viewModel.isLoading && viewModel.moments.isEmpty && viewModel.errorMessage == nil {
                    LoadingStateView()
                } else if let errorMessage = viewModel.errorMessage, viewModel.moments.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        viewModel.fetchMomentsByInterests()
                    }
                } else {
                    contentScrollView
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
    }

    private var contentScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                if searchText.isEmpty {
                    suggestedUsersSection

                    if !viewModel.moments.isEmpty {
                        ExploreMomentsBentoGrid(
                            moments: viewModel.moments,
                            zoomNamespace: zoomNamespace,
                            onMomentTap: handleMomentTap
                        )
                        .padding(.bottom, 80)
                    }
                } else {
                    searchResultsSection
                }
            }
        }
    }

        private var suggestedUsersSection: some View {
            SuggestedUsersSection(
                users: viewModel.suggestedUsers,
                moments: viewModel.moments, // ✅ Passing visible moments
                currentUserInterests: viewModel.currentUserInterests,
                userButtonStates: viewModel.userButtonStates,
                onFollowUser: viewModel.followUser,
                onUserTap: { user in
                    selectedUser = user
                    viewModel.checkCanViewContent(for: user.id) { _ in }
                },
                onShowMore: {
                    showSuggestedUsersView = true
                },
                profileZoomNamespace: profileZoomNamespace
            )
            .padding(.horizontal, 12)
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
            let resolvedIndex = moments.firstIndex(where: { $0.id == moment.id }) ?? index
            zoomDestination = MomentZoomDestination(
                zoomSourceID: ProfileMomentZoomNavigation.sourceID(
                    moment: moment,
                    index: resolvedIndex,
                    prefix: zoomIDPrefix
                ),
                initialIndex: resolvedIndex,
                initialMomentId: moment.id,
                presentation: presentation
            )
            HapticManager.shared.lightImpact()
        }

        private func momentsForZoomDestination(_ destination: MomentZoomDestination) -> [Moment] {
            let pool = searchText.isEmpty ? viewModel.moments : viewModel.filteredMoments
            return MomentZoomOpener.resolvedMoments(for: destination, in: pool)
        }

        // Removed redundant momentsSection property

        private var searchResultsSection: some View {
            SmartSearchResultsView(
                searchQuery: searchText,
                users: viewModel.searchedUsers,
                moments: viewModel.filteredMoments,
                userButtonStates: viewModel.userButtonStates,
                currentUserInterests: viewModel.currentUserInterests,
                onFollowUser: viewModel.followUser,
                onUserTap: { user in
                    selectedUser = user
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
                }
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

        private var privateProfileAlert: Alert {
            Alert(
                title: Text("explore.privateProfile.title"),
                message: Text("explore.privateProfile.message"),
                dismissButton: .default(Text("common.ok"))
            )
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
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundStyle(.primary)

                    if let socialStatus {
                        Text(socialStatus)
                            .font(.custom("Poppins-Medium", size: 12))
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

// MARK: - Previews
struct ExploreView_Previews: PreviewProvider {
    static var previews: some View {
        ExploreView()
            .preferredColorScheme(.light)

        ExploreView()
            .preferredColorScheme(.dark)
    }
}
