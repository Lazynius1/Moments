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
    @State private var selectedMoment: Moment?
    @State private var selectedUser: AppUser?
    @State private var showTrendingView = false

    @State private var showSuggestedUsersView = false
    let initialSearchQuery: String?
    let isDismissable: Bool

    init(initialSearchQuery: String? = nil, isDismissable: Bool = false) {
        self.initialSearchQuery = initialSearchQuery
        self.isDismissable = isDismissable
    }

    var body: some View {
        NavigationStack {
            mainContent
                .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("explore.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            ExploreHapticFeedback.impact(.light)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.clear.liquidGlass(in: Circle(), interactive: true))
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        ExploreHapticFeedback.impact(.medium)
                        showTrendingView = true
                    } label: {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                    }

                    Button {
                        ExploreHapticFeedback.impact(.medium)
                        viewModel.refreshContent()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(viewModel.isLoadingTrending ? 360 : 0))
                            .animation(
                                viewModel.isLoadingTrending
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                                value: viewModel.isLoadingTrending
                            )
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: NSLocalizedString("explore.search.placeholder", comment: "")
            )
            .searchSuggestions {
                if searchText.isEmpty && !viewModel.recentSearches.isEmpty {
                    Section {
                        ForEach(viewModel.recentSearches) { search in
                            HStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    if search.type == "user", let targetId = search.targetId {
                                        StoryRingAvatarView(
                                            userId: targetId,
                                            size: 32,
                                            lineWidth: 2.0
                                        )
                                        .onTapGesture {
                                            guard !targetId.isEmpty else { return }
                                            NotificationCenter.default.post(
                                                name: NSNotification.Name("NavigateToProfile"),
                                                object: targetId
                                            )
                                        }
                                    } else {
                                        Image(systemName: searchTypeIcon(for: search.type))
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                    }

                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(search.query)
                                            .font(.custom("Poppins-SemiBold", size: 16))
                                            .foregroundStyle(.primary)

                                        if let targetId = search.targetId,
                                           let status = viewModel.getSocialStatus(userId: targetId) {
                                            Text(status)
                                                .font(.custom("Poppins-Medium", size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    searchText = search.query
                                    viewModel.saveSearchRecord(query: search.query, type: search.type, targetId: search.targetId)
                                    viewModel.smartSearch(query: search.query)
                                }

                                Spacer()

                                Button {
                                    viewModel.deleteSearch(search)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .searchCompletion(search.query)
                        }
                    } header: {
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
                }
            }
            .tint(.primary)
            .onSubmit(of: .search) {
                viewModel.saveSearchRecord(query: searchText, type: "text")
                // El tipo se detectará automáticamente en saveSearchRecord si es necesario,
                // o podemos ser más específicos aquí.
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.smartSearch(query: newValue)
            }
            .onAppear {
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
            .alert(isPresented: $showPrivateProfileAlert) {
                privateProfileAlert
            }
            .fullScreenCover(item: $selectedUser) { user in
                UserProfileView(userId: user.id)
            }
            .sheet(item: $selectedMoment) { moment in
                MomentDetailView(moment: moment)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showTrendingView) {
                TrendingView()
            }
            .sheet(isPresented: $showSuggestedUsersView) {
                SuggestedUsersView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
            }
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
        Group {
            if viewModel.isLoading {
                LoadingStateView()
            } else if let errorMessage = viewModel.errorMessage {
                ErrorStateView(message: errorMessage) {
                    viewModel.fetchMomentsByInterests()
                }
            } else {
                contentScrollView
            }
        }
    }

    private var contentScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 24) {
                if searchText.isEmpty {
                    suggestedUsersSection

                    if !viewModel.moments.isEmpty {
                        DynamicMomentsGrid(moments: viewModel.moments, onMomentTap: handleMomentTap)
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
                }
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
        private func handleMomentTap(_ moment: Moment) {
            viewModel.checkCanViewContent(for: moment.authorId) { canView in
                if canView {
                    selectedMoment = moment
                } else {
                    showPrivateProfileAlert = true
                }
            }
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

                onMomentTap: { moment in
                    viewModel.checkCanViewContent(for: moment.authorId) { canView in
                        if canView {
                            selectedMoment = moment
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

// MARK: - Previews
struct ExploreView_Previews: PreviewProvider {
    static var previews: some View {
        ExploreView()
            .preferredColorScheme(.light)

        ExploreView()
            .preferredColorScheme(.dark)
    }
}
