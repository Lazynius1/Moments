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
    
    init(initialSearchQuery: String? = nil) {
        self.initialSearchQuery = initialSearchQuery
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("explore.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
            .onChange(of: searchText) { newValue in
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
                title: Text("Perfil privado"),
                message: Text("Este perfil es privado. Envía una solicitud de seguimiento para ver su contenido."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isSearchFocused: Bool // ✅ Cambiar a Simple Binding para sincronizar
    let onSearch: (String) -> Void
    @FocusState private var internalFocus: Bool // ✅ FocusState interno
    
    var body: some View {


        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: isSearchFocused ?
                                        [Color(hex: "667eea").opacity(0.6), Color(hex: "764ba2").opacity(0.4)] :
                                        [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .background(
                        IntelligentGlow(
                            isFocused: isSearchFocused,
                            cornerRadius: 10,
                            colors: [
                                Color(hex: "667eea"),
                                Color(hex: "764ba2"),
                                Color(hex: "6B73FF")
                            ]
                        )
                    )
                    .shadow(
                        color: isSearchFocused ? Color(hex: "667eea").opacity(0.2) : .black.opacity(0.05),
                        radius: isSearchFocused ? 6 : 4,
                        x: 0,
                        y: isSearchFocused ? 3 : 2
                    )
                
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isSearchFocused ? Color(hex: "667eea") : .secondary)
                        .animation(.easeInOut(duration: 0.3), value: isSearchFocused)
                    
                    TextField("explore.search.placeholder", text: $searchText)
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.primary)
                        .focused($internalFocus)
                        .onChange(of: internalFocus) { newValue in
                            isSearchFocused = newValue
                        }
                        .onChange(of: searchText) { newValue in
                             onSearch(newValue)
                        }

                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            onSearch("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 40)
            
            if isSearchFocused {
                Button(NSLocalizedString("explore.search.cancel", comment: "")) {
                    searchText = ""
                    onSearch("")
                    isSearchFocused = false
                }
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(Color(hex: "667eea"))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchFocused)
    }
}

// MARK: - Estados de Carga y Error
struct LoadingStateView: View {
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotationAngle))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotationAngle)
            }
            
            VStack(spacing: 8) {
                Text("explore.loading")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("explore.loading.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 80)
        .onAppear { rotationAngle = 360 }
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 12) {
                Text("explore.error.title")
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("explore.error.retry")
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "667eea").opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - Sección de Usuarios Sugeridos
struct SuggestedUsersSection: View {
    let users: [AppUser]
    let moments: [Moment] // ✅ Recibimos momentos ya filtrados
    let currentUserInterests: [String]
    let userButtonStates: [String: FollowButtonState]
    let onFollowUser: (String) -> Void
    let onUserTap: (AppUser) -> Void
    let onShowMore: () -> Void
    
    var body: some View {
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("explore.suggestedUsers.title")
                            .font(.custom("Poppins-SemiBold", size: 22))
                            .foregroundColor(.primary)
                        
                        Text("explore.suggestedUsers.subtitle")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("explore.suggestedUsers.seeMore") {
                        onShowMore()
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "667eea"))
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(users) { user in
                            // ✅ Buscar el último momento visible de este usuario
                            let latestMoment = moments.first(where: { $0.authorId == user.id })
                            
                            SuggestedUserCard(
                                user: user,
                                backgroundMoment: latestMoment,
                                commonInterests: Set(user.interests).intersection(Set(currentUserInterests)).count,
                                buttonState: userButtonStates[user.id] ?? .canFollow,
                                onFollow: { onFollowUser(user.id) },
                                onTap: { onUserTap(user) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}

// MARK: - Tarjeta de Usuario Sugerido
struct SuggestedUserCard: View {
    let user: AppUser
    let backgroundMoment: Moment? // ✅ Momento para el fondo
    let commonInterests: Int
    let buttonState: FollowButtonState
    let onFollow: () -> Void
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // ✅ FONDO: Imagen del momento o Gradiente
            GeometryReader { geometry in
                // ✅ NUEVO: Priorizar thumbnailUrl (video) o imagePath (imagen) para el fondo
                let url = backgroundMoment?.previewImageURLString.flatMap { getImageURL(from: $0) }
                
                if let bgUrl = url {
                    KFImage(bgUrl)
                        .placeholder {
                            defaultBackground
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 220)
                        .clipped()
                        .blur(radius: 8)
                        .overlay(
                            // Overlay oscuro para legibilidad
                            LinearGradient(
                                colors: [.black.opacity(0.7), .black.opacity(0.3)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                } else {
                    defaultBackground
                }
            }
            
            // ✅ CONTENIDO
            VStack(spacing: 12) {
                Spacer()
                
                // Profile Image with Glow
                ZStack {
                    Circle()
                        .fill(Color(hex: "667eea").opacity(0.3))
                        .frame(width: 68, height: 68)
                        .blur(radius: 8)
                    
                    ProfileImageeView(imagePath: user.profileImagePath, size: 60)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text(user.username)
                            .font(.custom("Poppins-SemiBold", size: 15))
                            .foregroundColor(.white) // ✅ Texto blanco siempre
                            .lineLimit(1)
                            .shadow(radius: 2)
                        
                        VerifiedBadgeView(userId: user.id, size: 12)
                    }
                    
                    if commonInterests > 0 {
                        Text(String(format: NSLocalizedString("explore.commonInterests", comment: "Common interests"), commonInterests))
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    } else {
                        Text(NSLocalizedString("explore.suggestedUsers.suggestedForYou", comment: ""))
                             .font(.custom("Poppins-Medium", size: 11))
                             .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                Button(action: onFollow) {
                    Text(buttonState == .following ? "Following" : (buttonState == .requestPending ? "Requested" : "Follow"))
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(buttonState.isActionable ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if buttonState.isActionable {
                                    LinearGradient(
                                        colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                } else {
                                    Color.white // Botón blanco para "Following"
                                        .opacity(0.9)
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
                .disabled(!buttonState.isActionable)
            }
            .padding(12)
            .padding(.bottom, 12)
        }
        .frame(width: 160, height: 220)
        .background(Color.black) // Fallback color
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
            isPressed = isPressing
        }, perform: {})
    }
    
    private var defaultBackground: some View {
        LinearGradient(
            colors: [Color(hex: "667eea").opacity(0.2), Color(hex: "764ba2").opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            // Patrón sutil o efecto glass
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Tarjeta de Resultado de Búsqueda
struct SearchResultCard: View {
    let user: AppUser
    let buttonState: FollowButtonState
    let commonInterests: Int
    let onFollow: () -> Void
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
            
            HStack(spacing: 16) {
                ProfileImageeView(imagePath: user.profileImagePath, size: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("@\(user.username)")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.primary)
                        
                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: user.id, size: 14)
                    }
                    
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if commonInterests > 0 {
                        Text(String(format: NSLocalizedString("explore.commonInterests", comment: "Common interests"), commonInterests))
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(Color(hex: "667eea"))
                    }
                }
                
                Spacer()
                
                if buttonState.isActionable {
                    FollowButton(
                        user: user,
                        buttonState: buttonState,
                        onTap: onFollow
                    )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: buttonState == .following ? "checkmark" :
                              buttonState == .requestPending ? "clock" : "xmark")
                        Text(buttonState.buttonText)
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
            .padding(20)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
}

// MARK: - Botón de Seguir
struct FollowButton: View {
    let user: AppUser
    let buttonState: FollowButtonState
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                Text(buttonText)
            }
            .font(.custom("Poppins-SemiBold", size: 14))
            .foregroundColor(buttonState.isActionable ? .white : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(buttonBackground)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(
                color: buttonState.isActionable ? Color(hex: "667eea").opacity(0.3) : .clear,
                radius: buttonState.isActionable ? 8 : 0,
                x: 0,
                y: buttonState.isActionable ? 4 : 0
            )
        }
        .disabled(!buttonState.isActionable)
    }
    
    private var buttonText: String {
        switch buttonState {
        case .ownProfile:
            return NSLocalizedString("explore.button.ownProfile", comment: "Your profile")
        case .blocked:
            return NSLocalizedString("explore.button.blocked", comment: "Blocked")
        case .following:
            return NSLocalizedString("explore.button.following", comment: "Following")
        case .canFollow:
            return NSLocalizedString("explore.button.follow", comment: "Follow")
        case .canRequestFollow:
            return NSLocalizedString("explore.button.request", comment: "Request")
        case .requestPending:
            return NSLocalizedString("explore.button.requested", comment: "Requested")
        }
    }
    
    private var buttonIcon: String {
        switch buttonState {
        case .following:
            return "checkmark"
        case .canFollow, .canRequestFollow:
            return "plus"
        case .requestPending:
            return "clock"
        case .blocked:
            return "xmark"
        case .ownProfile:
            return "person"
        }
    }
    
    private var buttonBackground: some View {
        Group {
            switch buttonState {
            case .canFollow, .canRequestFollow:
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            default:
                RoundedRectangle(cornerRadius: 25)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Grid Dinámico (Quilt Pattern)
struct DynamicMomentsGrid: View {
    let moments: [Moment]
    let onMomentTap: (Moment) -> Void
    
    // El patrón se repite cada 12 items: 3, 3, 3(1L+2S), 3, 3(2S+1R) NO, CORRECCIÓN:
    // Mejor ciclo: Row(3) -> BigLeft(3 consumidos) -> Row(3) -> BigRight(3 consumidos). Total 12 items.
    
    var body: some View {
        VStack(spacing: 2) { // Spacing vertical del grid = 2
            let chunked = moments.chunked(into: 12)
            
            ForEach(0..<chunked.count, id: \.self) { index in
                let chunk = chunked[index]
                let items = Array(chunk)
                
                // Renderizar el bloque de 12 (o menos si es el final)
                DynamicGridBlock(items: items, onMomentTap: onMomentTap)
            }
        }
    }
}

struct DynamicGridBlock: View {
    let items: [Moment] // Up to 12 items
    let onMomentTap: (Moment) -> Void
    
    var body: some View {
        // Calcular filas basados en disponibilidad
        // Fila 1: 0,1,2 (3 items)
        if items.count >= 3 {
             MomentsRowView(moments: Array(items[0..<3]), onTap: onMomentTap)
        } else {
             MomentsRowView(moments: items, onTap: onMomentTap)
        }
        
        // Bloque Big Left: 3,4,5 (3 items) -> Index 3 es Big
        if items.count >= 6 {
            BigLeftRowView(moments: Array(items[3..<6]), onTap: onMomentTap)
        } else if items.count > 3 {
            // Remainder row
            MomentsRowView(moments: Array(items[3..<items.count]), onTap: onMomentTap)
        }
        
        // Fila 3: 6,7,8 (3 items)
        if items.count >= 9 {
             MomentsRowView(moments: Array(items[6..<9]), onTap: onMomentTap)
        } else if items.count > 6 {
             MomentsRowView(moments: Array(items[6..<items.count]), onTap: onMomentTap)
        }
        
        // Bloque Big Right: 9,10,11 (3 items) -> Index 11 es Big
        if items.count >= 12 {
            BigRightRowView(moments: Array(items[9..<12]), onTap: onMomentTap)
        } else if items.count > 9 {
            // Remainder row
            MomentsRowView(moments: Array(items[9..<items.count]), onTap: onMomentTap)
        }
    }
}

// Fila Standard de 3 items
struct MomentsRowView: View {
    let moments: [Moment]
    let onTap: (Moment) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let width = (geo.size.width - 4) / 3 // 2 gaps of 2px
            HStack(spacing: 2) {
                ForEach(moments) { moment in
                    MomentCard(moment: moment, onTap: { onTap(moment) })
                        .frame(width: width, height: width)
                        .clipped()
                }
                // Spacer si hay menos de 3 para alinear a la izquierda
                if moments.count < 3 {
                    Spacer()
                }
            }
        }
        .aspectRatio(3.0/1.0, contentMode: .fit) // Si son 3 cuadrados, ratio 3:1. Si menos, se ajusta el HStack
        .frame(height: UIScreen.main.bounds.width / 3) // Altura aproximada para layout
    }
}

// Bloque Grande Izquierda: [ Big(2x2) ] [ Small / Small ]
struct BigLeftRowView: View {
    let moments: [Moment] // Expects 3 items: [Big, Small, Small]
    let onTap: (Moment) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let oneUnit = (geo.size.width - 4) / 3
            let twoUnits = oneUnit * 2 + 2
            
            HStack(alignment: .top, spacing: 2) {
                // Item 0: Grande
                if moments.indices.contains(0) {
                    MomentCard(moment: moments[0], onTap: { onTap(moments[0]) })
                        .frame(width: twoUnits, height: twoUnits)
                        .clipped()
                }
                
                // Stack Derecha: Items 1, 2
                VStack(spacing: 2) {
                    if moments.indices.contains(1) {
                        MomentCard(moment: moments[1], onTap: { onTap(moments[1]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                    if moments.indices.contains(2) {
                        MomentCard(moment: moments[2], onTap: { onTap(moments[2]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                }
            }
        }
        .frame(height: (UIScreen.main.bounds.width / 3) * 2 + 2)
    }
}

// Bloque Grande Derecha: [ Small / Small ] [ Big(2x2) ]
struct BigRightRowView: View {
    let moments: [Moment] // Expects 3 items: [Small, Small, Big]
    let onTap: (Moment) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let oneUnit = (geo.size.width - 4) / 3
            let twoUnits = oneUnit * 2 + 2
            
            HStack(alignment: .top, spacing: 2) {
                // Stack Izquierda: Items 0, 1
                VStack(spacing: 2) {
                    if moments.indices.contains(0) {
                        MomentCard(moment: moments[0], onTap: { onTap(moments[0]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                    if moments.indices.contains(1) {
                        MomentCard(moment: moments[1], onTap: { onTap(moments[1]) })
                            .frame(width: oneUnit, height: oneUnit)
                            .clipped()
                    }
                }
                
                // Item 2: Grande
                if moments.indices.contains(2) {
                    MomentCard(moment: moments[2], onTap: { onTap(moments[2]) })
                        .frame(width: twoUnits, height: twoUnits)
                        .clipped()
                }
            }
        }
        .frame(height: (UIScreen.main.bounds.width / 3) * 2 + 2)
    }
}

// MARK: - Tarjeta de Moment
struct MomentCard: View {
    let moment: Moment
    let onTap: () -> Void
    
    var body: some View {
        ScreenshotProtectedView(
            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
        ) {
            Button(action: onTap) {
                GeometryReader { geometry in
                    ZStack {
                        Color.gray.opacity(0.1)
                        
                        if let mediaItem = moment.primaryVisibleMediaItem, mediaItem.type == .video {
                            ExploreVideoThumbnailView(videoUrl: mediaItem.url, thumbnailUrl: mediaItem.thumbnailUrl ?? moment.thumbnailUrl)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                                .overlay(
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 24, height: 24)
                                        
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                    }
                                    .padding(8),
                                    alignment: .bottomTrailing
                                )
                        } else if let imagePath = moment.previewImageURLString, let url = getImageURL(from: imagePath) {
                            KFImage(url)
                                .placeholder {
                                    Color.gray.opacity(0.2)
                                }
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit) 
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private var momentContent: some View {
        EmptyView() // Not used in this simplified version
    }
}



// MARK: - Video Thumbnail View
struct ExploreVideoThumbnailView: View {
    let videoUrl: String
    let thumbnailUrl: String? // ✅ Nuevo
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let thumbUrl = thumbnailUrl, let url = URL(string: thumbUrl) {
                // ✅ NUEVO: Usar miniatura pre-generada
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.1)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        guard let url = URL(string: videoUrl) else {
            isLoading = false
            return
        }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 240, height: 240) // 2x para retina
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 1))]) { _, cgImage, _, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let cgImage = cgImage {
                    self.thumbnailImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}

// MARK: - Componentes Auxiliares
struct ProfileImageeView: View {
    let imagePath: String?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let imagePath = imagePath, let url = getImageURL(from: imagePath) {
                KFImage(url)
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                            )
                    }
                    .onFailure { error in
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

struct EmptyMomentsView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: "photo.stack")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Text("explore.noMoments")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("explore.noMoments.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
    }
}

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Text("explore.noUsers")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("explore.noUsers.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
    }
}




// MARK: - ExploreViewModel ACTUALIZADO
@MainActor
class ExploreViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var filteredMoments: [Moment] = []
    @Published var searchedUsers: [AppUser] = []
    @Published var suggestedUsers: [AppUser] = []
    @Published var followedUserIds: Set<String> = []
    @Published var pendingRequests: Set<String> = []
    @Published var authorProfiles: [String: AppUser] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var userButtonStates: [String: FollowButtonState] = [:]
    @Published var trendingContent: TrendingService.PersonalizedTrendingContent?
    @Published var isLoadingTrending: Bool = false
    @Published var trendingError: String?
    
    // ✅ HISTORIAL DE BÚSQUEDA
    @Published var recentSearches: [CachedSearch] = []
    @Published var followerUserIds: Set<String> = []

    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    var currentUserInterests: [String] = []
    private var currentUserId: String?
    private var blockedUsers: Set<String> = []
    private let trendingService = TrendingService.shared
    
    init() {
        loadRecentSearches()
    }

    
    // MARK: - FLUJO PRINCIPAL SIMPLIFICADO
    func fetchMomentsByInterests() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }
        
        self.currentUserId = userId
        isLoading = true
        errorMessage = nil
        
        // ✅ SwiftData: Cargar del caché local inmediatamente
        let cachedMoments = LocalPersistenceService.shared.loadExploreMoments()
        if !cachedMoments.isEmpty && self.moments.isEmpty {
            self.moments = cachedMoments
            self.filteredMoments = cachedMoments
            self.isLoading = false // UI instantánea con datos cacheados
        }

        
        // 1. PASO OBLIGATORIO: Cargar perfil del usuario actual
        self.firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let currentUserProfile):
                self.currentUserInterests = currentUserProfile.interests
                self.blockedUsers = Set(currentUserProfile.blockedUsers ?? [])
                
                // 2. Cargar conexiones (usuarios seguidos) primero
                self.loadConnectionsFirst { [weak self] in
                    guard let self = self else { return }
                    // 3. PASO PRINCIPAL: Cargar usuarios y momentos (ya con conexiones cargadas)
                    self.loadUsersAndMoments()
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error al cargar tu perfil: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - ✅ FUNCIÓN ACTUALIZADA: Cargar usuarios y momentos con estrategia mejorada
    private func loadUsersAndMoments() {
        guard let userId = currentUserId else { return }
        
        // ✅ ESTRATEGIA PARA EXPLORE: Obtener una mezcla diversa de usuarios
        let group = DispatchGroup()
        var allDiscoveredUsers: Set<AppUser> = []
        let syncQueue = DispatchQueue(label: "explore.users.discovery")
        
        // 1. Usuarios con intereses compartidos
        group.enter()
        self.firestoreService.fetchUsersWithSharedInterests(
            interests: self.currentUserInterests,
            excludingUserId: userId
        ) { [weak self] result in
            defer { group.leave() }
            
            if case .success(let users) = result {
                syncQueue.async {
                    allDiscoveredUsers.formUnion(users)
                }
            }
        }
        
        // 2. Usuarios sugeridos (algoritmo interno de Firebase)
        group.enter()
        self.firestoreService.fetchSuggestedUsers { [weak self] result in
            defer { group.leave() }
            
            if case .success(let users) = result {
                syncQueue.async {
                    allDiscoveredUsers.formUnion(users.prefix(20))
                }
            }
        }
        
        // 3. Usuarios populares (fallback)
        group.enter()
        self.fetchPopularUsersForExplore(excludingUserId: userId) { [weak self] users in
            syncQueue.async {
                allDiscoveredUsers.formUnion(users)
            }
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // ✅ Capturar followedUserIds en este momento para asegurar que esté actualizado
            let currentFollowedUserIds = self.followedUserIds
            
            // ✅ LECTURA SINCRONIZADA: Asegurar que todas las escrituras hayan terminado
            let finalUsers = syncQueue.sync {
                return allDiscoveredUsers
            }
            
            // Filtro COMPLETO - bloqueos Y usuarios ya seguidos
            let filteredUsers = Array(finalUsers).filter { user in
                !self.blockedUsers.contains(user.id) &&
                !(user.blockedUsers ?? []).contains(userId) &&
                !currentFollowedUserIds.contains(user.id) // ✅ Usar la copia capturada
            }
            
    
            
            // Ordenar por relevancia (intereses comunes)
            let sortedUsers = filteredUsers.sorted { user1, user2 in
                let commonInterests1 = Set(user1.interests).intersection(self.currentUserInterests).count
                let commonInterests2 = Set(user2.interests).intersection(self.currentUserInterests).count
                return commonInterests1 > commonInterests2
            }
            
            DispatchQueue.main.async {
                self.suggestedUsers = Array(sortedUsers.prefix(10))
                // ✅ Filtrar usuarios seguidos después de asignar la lista (por si acaso)
                self.filterFollowedUsersFromSuggestions()
            }
            
            // Cargar momentos de una muestra diversa de usuarios
            let userIds = Array(sortedUsers.prefix(100).map { $0.id })
            self.loadMomentsFromUsers(userIds: userIds)
        }
    }
    
    // MARK: - ✅ NUEVA FUNCIÓN: Obtener usuarios populares para Explore
    private func fetchPopularUsersForExplore(excludingUserId: String, completion: @escaping ([AppUser]) -> Void) {
        firestoreService.db.collection("users")
            .whereField("isPrivate", isEqualTo: false) // Solo perfiles públicos para Explore
            .limit(to: 30)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion([])
                    return
                }
                
                let users = snapshot?.documents.compactMap { doc -> AppUser? in
                    do {
                        let user = try doc.data(as: AppUser.self)
                        return user.id != excludingUserId ? user : nil
                    } catch {
                        return nil
                    }
                } ?? []
                
                completion(users)
            }
    }
    
    // MARK: - ✅ FUNCIÓN ACTUALIZADA: Cargar momentos con filtrado específico para Explore
    private func loadMomentsFromUsers(userIds: [String]) {

        
        self.firestoreService.fetchMomentsFromUsers(userIds: userIds) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let allMoments):
        
                
                // ✅ USAR LA FUNCIÓN DE FILTRADO ESPECÍFICA PARA EXPLORE
                self.filterMomentsForExploreVisibility(moments: allMoments) { filteredMoments in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.moments = filteredMoments
                        self.filteredMoments = filteredMoments
                        
                        // ✅ SwiftData: Guardar en caché local para offline
                        Task { @MainActor in
                            // Usamos sync: true para purgar momentos que ya no son tendencia/interés
                            LocalPersistenceService.shared.saveExploreMoments(filteredMoments, sync: true)
                        }
                
                        // ✅ Ya no necesitamos llamar a loadConnectionsOptionally aquí
                        // porque se cargan en paralelo al inicio de la vista
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error al cargar momentos: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - ✅ FUNCIÓN DE FILTRADO ESPECÍFICA PARA EXPLORE
    private func filterMomentsForExploreVisibility(moments: [Moment], completion: @escaping ([Moment]) -> Void) {
        guard let currentUserId = self.currentUserId else {
            completion([])
            return
        }
        
        let group = DispatchGroup()
        var visibleMoments: [Moment] = []
        let syncQueue = DispatchQueue(label: "explore.moments.filter", attributes: .concurrent)
        

        
        for moment in moments {
            // Excluir momentos del propio usuario (Explore es para descubrir contenido de otros)
            guard moment.authorId != currentUserId else {
                continue
            }
            
            // Excluir usuarios bloqueados (filtro básico)
            guard !blockedUsers.contains(moment.authorId) else {
                continue
            }
            
            group.enter()
            
            // ✅ USAR LA NUEVA FUNCIÓN ESPECÍFICA PARA EXPLORE
            privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { [weak self] canView in
                if canView {
                    syncQueue.sync {
                        visibleMoments.append(moment)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // ✅ SEGURO: Obtener la lista final de manera thread-safe
            let finalVisibleMoments = syncQueue.sync {
                visibleMoments
            }
            
            // Mantener el orden original por timestamp
            let orderedVisibleMoments = moments.filter { moment in
                finalVisibleMoments.contains { $0.id == moment.id }
            }
            
    
            completion(orderedVisibleMoments)
        }
    }
    
    // MARK: - Cargar conexiones PRIMERO (antes de mostrar usuarios sugeridos)
    private func loadConnectionsFirst(completion: @escaping () -> Void) {
        guard let userId = currentUserId else {
            completion()
            return
        }
        
        let group = DispatchGroup()
        var loadedFollowing: [AppUser] = [] // ✅ Usamos AppUser (colección 'following') en lugar de Connection
        var loadedNotifications: [Notification] = []
        var loadedFollowers: [AppUser] = []
        
        // Cargar usuarios seguidos (Colección 'following' correcta)
        group.enter()
        firestoreService.fetchFollowing(userId: userId) { [weak self] result in
            defer { group.leave() }
            if case .success(let users) = result {
                loadedFollowing = users
            }
        }
        
        // Cargar seguidores (para Social Status)
        group.enter()
        firestoreService.fetchFollowers(userId: userId) { [weak self] result in
            defer { group.leave() }
            if case .success(let followers) = result {
                loadedFollowers = followers
            }
        }
        
        // Cargar solicitudes pendientes
        group.enter()
        NotificationService.shared.fetchNotificationsOnce(userId: userId) { [weak self] result in
            defer { group.leave() }
            switch result {
            case .success(let notifications):
                loadedNotifications = notifications
            case .failure(_):
                break
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            // ✅ Actualizar en el hilo principal después de que todo haya cargado
            // Nota: fetchFollowing devuelve AppUser, así que usamos .id
            let loadedFollowedIds = Set(loadedFollowing.map { $0.id })
            
            self.followedUserIds = loadedFollowedIds
            self.followerUserIds = Set(loadedFollowers.map { $0.id })
            
            self.pendingRequests = Set(loadedNotifications.filter {
                $0.type == .followRequest && $0.isPending
            }.map { $0.senderId })
            
            // ✅ Filtrar usuarios seguidos de la lista actual si ya hay usuarios cargados
            self.suggestedUsers = self.suggestedUsers.filter { user in
                !loadedFollowedIds.contains(user.id)
            }
            
            // ✅ Actualizar estados de botones para sugerencias y perfiles buscados
            self.updateButtonStatesForAllUsers()
            
            completion()
        }
    }
    
    // MARK: - Actualizar estados de botones
    private func updateButtonStatesForAllUsers() {
        for user in suggestedUsers {
            checkUserButtonState(for: user.id)
        }
        for user in searchedUsers {
            checkUserButtonState(for: user.id)
        }
        
        // ✅ Filtrar usuarios seguidos de la lista después de actualizar estados
        filterFollowedUsersFromSuggestions()
    }
    
    // ✅ NUEVO: Filtrar usuarios seguidos de las sugerencias
    func filterFollowedUsersFromSuggestions() {
        suggestedUsers = suggestedUsers.filter { user in
            !followedUserIds.contains(user.id)
        }
    }
    
    
    // MARK: - Cargar perfil de autor
    func loadAuthorProfile(for userId: String) {
        if authorProfiles[userId] == nil {
            firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
                switch result {
                case .success(let userProfile):
                    DispatchQueue.main.async {
                        self?.authorProfiles[userId] = userProfile
                    }
                case .failure(_):
                    break
                }
            }
        }
    }
    
    // MARK: - Verificar si puede ver contenido
    func checkCanViewContent(for userId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = self.currentUserId else {
            completion(false)
            return
        }
        
        privacyService.canViewUserContent(
            viewerId: currentUserId,
            targetUserId: userId
        ) { canView in
            DispatchQueue.main.async {
                completion(canView)
            }
        }
    }
    
    // MARK: - Verificar estado del botón de usuario
    func checkUserButtonState(for userId: String) {
        guard let currentUserId = self.currentUserId else { return }
        
        privacyService.getFollowButtonState(
            viewerId: currentUserId,
            targetUserId: userId
        ) { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.userButtonStates[userId] = state
                
                // ✅ Si el estado es "siguiendo", agregar a followedUserIds y eliminar de sugerencias
                if state == .following {
                    self.followedUserIds.insert(userId)
                    // Eliminar de la lista de sugerencias
                    if let index = self.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                        self.suggestedUsers.remove(at: index)
                    }
                }
            }
        }
    }
    
    // MARK: - Seguir usuario
    func followUser(userId: String) {
        guard let currentUserId = self.currentUserId else {
            return
        }
        
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let userProfile):
                if userProfile.isPrivate {
                    // ✅ Eliminar inmediatamente de la lista antes de enviar solicitud
                    DispatchQueue.main.async {
                        if let index = self.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                            self.suggestedUsers.remove(at: index)
                        }
                        self.pendingRequests.insert(userId)
                        self.userButtonStates[userId] = .requestPending
                    }
                    
                    self.firestoreService.sendFollowRequest(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = "Error al enviar solicitud: \(error.localizedDescription)"
                                // Si hay error, revertir el estado del botón
                                self?.userButtonStates[userId] = .canRequestFollow
                                self?.pendingRequests.remove(userId)
                            }
                            // Si no hay error, el usuario ya fue eliminado de la lista arriba
                        }
                    }
                } else {
                    // ✅ Eliminar inmediatamente de la lista antes de seguir
                    DispatchQueue.main.async {
                        if let index = self.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                            self.suggestedUsers.remove(at: index)
                        }
                        self.followedUserIds.insert(userId)
                        self.userButtonStates[userId] = .following
                    }
                    
                    self.firestoreService.followUser(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                                // Si hay error, revertir el estado del botón
                                self?.userButtonStates[userId] = .canFollow
                                self?.followedUserIds.remove(userId)
                            }
                            // Si no hay error, el usuario ya fue eliminado de la lista arriba
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = "Error al obtener perfil: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Obtener estado del botón
    func getButtonState(for userId: String) -> FollowButtonState {
        return userButtonStates[userId] ?? .canFollow
    }
}

// MARK: - EXTENSIÓN: Funciones específicas para Explore

extension ExploreViewModel {
    
    // ✅ FUNCIÓN DE DEBUG: Verificar contenido visible
    func debugVisibleContent() {
        guard let userId = currentUserId else { return }

        // Mostrar distribución por audiencia
        let audienceDistribution = moments.reduce(into: [String: Int]()) { counts, moment in
            let audience = moment.audience ?? "everyone"
            counts[audience, default: 0] += 1
        }
        
        for (audience, count) in audienceDistribution {

        }
    }
    
    // ✅ FUNCIÓN PARA REFRESCAR CONTENIDO
    func refreshContent() {
        moments = []
        filteredMoments = []
        suggestedUsers = []
        searchedUsers = []
        followedUserIds = [] // ✅ Limpiar usuarios seguidos para recargarlos
        pendingRequests = [] // ✅ Limpiar solicitudes pendientes para recargarlas
        fetchMomentsByInterests()
    }
    
    // ✅ FUNCIÓN PARA LIMPIAR DATOS
    func clearData() {
        moments = []
        filteredMoments = []
        searchedUsers = []
        suggestedUsers = []
        authorProfiles = [:]
        userButtonStates = [:]
        errorMessage = nil
        isLoading = false
    }
    
    // MARK: - HISTORIAL DE BÚSQUEDA (SwiftData)
    func loadRecentSearches() {
        self.recentSearches = LocalPersistenceService.shared.loadRecentSearches()
    }
    
    func saveSearchRecord(query: String, type: String, targetId: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        // Si el tipo es genérico "text", intentamos detectar si es hashtag o usuario
        var finalType = type
        var finalQuery = trimmed
        
        if type == "text" {
            let detected = detectSearchType(query: trimmed)
            switch detected {
            case .hashtag(let h):
                finalType = "hashtag"
                finalQuery = "#\(h)"
            case .username(let u):
                finalType = "user"
                finalQuery = "@\(u)"
            case .location(let l):
                finalType = "location"
                finalQuery = l
            default:
                finalType = "text"
            }
        }
        
        LocalPersistenceService.shared.saveSearch(query: finalQuery, type: finalType, targetId: targetId)
        loadRecentSearches()
    }
    
    func deleteSearch(_ search: CachedSearch) {
        LocalPersistenceService.shared.deleteSearch(id: search.id)
        loadRecentSearches()
    }
    
    func clearAllSearches() {
        LocalPersistenceService.shared.clearSearchHistory()
        self.recentSearches = []
    }
    
    // MARK: - SOCIAL STATUS HELPER
    func getSocialStatus(userId: String) -> String? {
        let isFollowing = followedUserIds.contains(userId)
        let isFollower = followerUserIds.contains(userId)
        
        if isFollowing && isFollower {
            return NSLocalizedString("social.mutual", comment: "Mutual connection status")
        } else if isFollower {
            return NSLocalizedString("social.followsYou", comment: "User follows current user status")
        } else if isFollowing {
            return NSLocalizedString("social.following", comment: "Current user follows user status")
        }
        return nil
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

extension ExploreViewModel {
    
    // ✅ NUEVA FUNCIÓN: Cargar contenido trending
    func fetchTrendingContent() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isLoadingTrending = true
        trendingError = nil
        

        
        trendingService.fetchPersonalizedTrendingContent(for: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingTrending = false
                
                switch result {
                case .success(let content):
                    self?.trendingContent = content
                    
                    
                case .failure(let error):
                    self?.trendingError = "Error cargando trending: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // ✅ ACTUALIZAR la función principal para incluir trending
    func fetchMomentsByInterestsWithTrending(completion: (() -> Void)? = nil) {
        // Cargar contenido normal
        fetchMomentsByInterests()
        
        // Cargar trending en paralelo
        fetchTrendingContent()
        
        // ✅ NUEVO: Llamar completion cuando termine
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            completion?()
        }
    }
    
    // ✅ FUNCIÓN para buscar por hashtag
    func searchByHashtag(_ hashtag: String) {

        
        // Limpiar búsqueda de usuarios
        searchedUsers = []
        
        // Buscar momentos que contengan el hashtag
        let filteredByHashtag = moments.filter { moment in
            moment.content.lowercased().contains("#\(hashtag.lowercased())")
        }
        
        filteredMoments = filteredByHashtag

    }
    
    // ✅ FUNCIÓN para explorar por ubicación
    func exploreByLocation(_ locationName: String) {

        
        // Filtrar momentos de esa ubicación
        let filteredByLocation = moments.filter { moment in
            (moment.location ?? "").lowercased().contains(locationName.lowercased())
        }
        
        filteredMoments = filteredByLocation
        searchedUsers = []

    }
    
    // ✅ FUNCIÓN para refrescar todo
    func refreshAllContent() {
        clearData()
        fetchMomentsByInterestsWithTrending()
    }
}

// ✅ UTILIDAD: Haptic Feedback (agregar a tu proyecto)
struct ExploreHapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let feedback = UIImpactFeedbackGenerator(style: style)
        feedback.impactOccurred()
    }
    
    static func success() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
    }
    
    static func error() {
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.error)
    }
}

extension ExploreViewModel {
    
    // ✅ NUEVA FUNCIÓN: Búsqueda inteligente que reemplaza searchUsers
    func smartSearch(query: String) {

        
        if query.isEmpty {
            // Limpiar resultados
            searchedUsers = []
            filteredMoments = self.moments

            return
        }
        
        let searchType = detectSearchType(query: query)

        
        switch searchType {
        case .hashtag(let hashtag):

            searchHashtags(hashtag: hashtag)
            
        case .username(let username):

            searchUsers(username: username)
            
        case .location(let location):

            searchLocations(location: location)
            
        case .mixed(let cleanQuery):

            searchEverything(query: cleanQuery)
        }
        // NOTA: El historial se guarda explícitamente en .onSubmit o al tocar un resultado
        // para evitar que cada pulsación de tecla genere una entrada en el historial.
        
        // ✅ NUEVO: Debug final

    }
    
    // ✅ DETECTAR tipo de búsqueda
    private func detectSearchType(query: String) -> SearchType {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Hashtag: empieza con #
        if trimmedQuery.hasPrefix("#") {
            let hashtag = String(trimmedQuery.dropFirst()).lowercased()
            return .hashtag(hashtag)
        }
        
        // 2. Usuario: empieza con @
        if trimmedQuery.hasPrefix("@") {
            let username = String(trimmedQuery.dropFirst()).lowercased()
            return .username(username)
        }
        
        // 3. Ubicación: contiene palabras clave
        let locationKeywords = ["en ", "lugar ", "city ", "ciudad ", "beach ", "playa ", "restaurant ", "cafe "]
        if locationKeywords.contains(where: { trimmedQuery.lowercased().contains($0) }) {
            return .location(trimmedQuery)
        }
        
        // 4. Mixto: buscar en todo
        return .mixed(trimmedQuery)
    }
    
    // ✅ BUSCAR usuarios (función original mejorada CON FILTRADO COMPLETO)
    private func searchUsers(username: String) {
        filteredMoments = [] // Limpiar momentos
        let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else {
            searchedUsers = []
            return
        }

        firestoreService.searchUsers(query: cleanUsername, limit: 20) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = "Error al buscar usuarios: \(error.localizedDescription)"
                }
            case .success(let users):
                let currentUserId = self.currentUserId ?? ""
                let filteredUsers = users.filter { user in
                    guard user.id != currentUserId else { return false }
                    guard !self.blockedUsers.contains(user.id) else { return false }
                    guard !(user.blockedUsers ?? []).contains(currentUserId) else { return false }
                    return true
                }

                DispatchQueue.main.async {
                    self.searchedUsers = filteredUsers
                }
            }
        }
    }
    private func searchHashtags(hashtag: String) {
        
        
        // Debug de cada momento
        for (index, moment) in moments.enumerated() {
            

        }
        
        searchedUsers = []
        
        let candidateMoments = moments.filter { moment in
            // 1. Debe contener el hashtag
            guard moment.content.lowercased().contains("#\(hashtag)") else {

                return false
            }
            
            // 2. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else {

                return false
            }
            
            // 3. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else {

                return false
            }
            
            
            return true
        }
        
        filteredMoments = candidateMoments

    }
    
    // ✅ BUSCAR por ubicaciones CON FILTRADO DE PRIVACIDAD
    private func searchLocations(location: String) {
        searchedUsers = [] // Limpiar usuarios
        
        // ✅ FILTRAR: momentos visibles en la lista cargada + sin bloqueos
        let candidateMoments = moments.filter { moment in
            // 1. Debe tener ubicación que coincida
            guard let momentLocation = moment.location else { return false }
            guard momentLocation.lowercased().contains(location.lowercased()) else { return false }
            
            // 2. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else { return false }
            
            // 3. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else { return false }
            
            return true
        }
        
        filteredMoments = candidateMoments

    }
    
    // ✅ BÚSQUEDA MIXTA: usuarios + hashtags + ubicaciones CON FILTRADO
    private func searchEverything(query: String) {
        let lowercaseQuery = query.lowercased()
        
        // 1. Buscar usuarios (ya tiene filtrado correcto)
        searchUsers(username: lowercaseQuery)
        
        // 2. Buscar momentos CON FILTRADO DE PRIVACIDAD
        let candidateMoments = moments.filter { moment in
            // Verificar coincidencias
            let contentMatch = moment.content.lowercased().contains(lowercaseQuery)
            let locationMatch = (moment.location ?? "").lowercased().contains(lowercaseQuery)
            let usernameMatch = moment.username.lowercased().contains(lowercaseQuery)
            
            // Debe tener alguna coincidencia
            guard contentMatch || locationMatch || usernameMatch else { return false }
            
            // ✅ FILTROS DE PRIVACIDAD:
            // 1. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else { return false }
            
            // 2. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else { return false }
            
            return true
        }
        
        DispatchQueue.main.async {
            self.filteredMoments = candidateMoments
    
        }
    }
}

// MARK: - 🎯 Tipos de búsqueda
enum SearchType {
    case hashtag(String)     // #viaje
    case username(String)    // @juan
    case location(String)    // Madrid, playa, etc.
    case mixed(String)       // búsqueda general
}

// MARK: - 🎨 Componente de resultados de búsqueda mejorado
struct SmartSearchResultsView: View {
    let searchQuery: String
    let users: [AppUser]
    let moments: [Moment]
    let userButtonStates: [String: FollowButtonState]
    let currentUserInterests: [String]
    let onFollowUser: (String) -> Void
    let onUserTap: (AppUser) -> Void
    let onMomentTap: (Moment) -> Void
    
    var searchType: SearchDisplayType {
        if searchQuery.hasPrefix("#") {
            return .hashtag
        } else if searchQuery.hasPrefix("@") {
            return .users
        } else if !users.isEmpty && !moments.isEmpty {
            return .mixed
        } else if !users.isEmpty {
            return .users
        } else if !moments.isEmpty {
            return .moments
        } else {
            return .empty
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header con tipo de búsqueda
            searchHeader
            
            // Resultados según el tipo
            switch searchType {
            case .hashtag:
                hashtagResultsView
                
            case .users:
                usersResultsView
                
            case .moments:
                momentsResultsView
                
            case .mixed:
                mixedResultsView
                
            case .empty:
                EmptySearchView()
            }
        }
    }
    
    // ✅ Header inteligente
    private var searchHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(.primary)
                
                Text(headerSubtitle)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Icono según tipo de búsqueda
            Image(systemName: headerIcon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "667eea"))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .padding(.horizontal, 24)
    }
    
    // ✅ Resultados de hashtags
    private var hashtagResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(format: NSLocalizedString("explore.search.moments", comment: "Search moments"), searchQuery))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(moments.count)")
                    .font(.custom("Poppins-Bold", size: 16))
                    .foregroundColor(Color(hex: "667eea"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "667eea").opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            
            // Grid de momentos
            MomentsSearchGrid(moments: moments, onMomentTap: onMomentTap)
        }
    }
    
    // ✅ Resultados de usuarios
    private var usersResultsView: some View {
        VStack(spacing: 16) {
            LazyVStack(spacing: 12) {
                ForEach(users) { user in
                    SearchResultCard(
                        user: user,
                        buttonState: userButtonStates[user.id] ?? .canFollow,
                        commonInterests: Set(user.interests).intersection(Set(currentUserInterests)).count,
                        onFollow: { onFollowUser(user.id) },
                        onTap: { onUserTap(user) }
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }
    
    // ✅ Resultados de momentos
    private var momentsResultsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("explore.search.results")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(moments.count)")
                    .font(.custom("Poppins-Bold", size: 16))
                    .foregroundColor(Color(hex: "667eea"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "667eea").opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            
            MomentsSearchGrid(moments: moments, onMomentTap: onMomentTap)
        }
    }
    
    // ✅ Resultados mixtos
    private var mixedResultsView: some View {
        VStack(spacing: 24) {
            // Usuarios encontrados
            if !users.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("explore.search.users")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(users.count)")
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(users.prefix(5)) { user in
                                MiniUserCard(
                                    user: user,
                                    onTap: { onUserTap(user) }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            
            // Momentos encontrados
            if !moments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("explore.search.moments.tab")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(moments.count)")
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    
                    MomentsSearchGrid(moments: moments, onMomentTap: onMomentTap)
                }
            }
        }
    }
    
    // ✅ Propiedades computadas para el header
    private var headerTitle: String {
        switch searchType {
        case .hashtag:
            return String(format: NSLocalizedString("explore.search.hashtag.title", comment: ""), searchQuery)
        case .users:
            return searchQuery.hasPrefix("@") ? String(format: NSLocalizedString("explore.search.user.title", comment: ""), String(searchQuery.dropFirst())) : NSLocalizedString("explore.search.users.title", comment: "")
        case .moments:
            return NSLocalizedString("explore.search.moments.title", comment: "")
        case .mixed:
            return String(format: NSLocalizedString("explore.search.results.title", comment: ""), searchQuery)
        case .empty:
            return NSLocalizedString("explore.search.empty.title", comment: "")
        }
    }
    
    private var headerSubtitle: String {
        switch searchType {
        case .hashtag:
            return String(format: NSLocalizedString("explore.search.moments.found", comment: ""), moments.count)
        case .users:
            return String(format: NSLocalizedString("explore.search.users.found", comment: ""), users.count)
        case .moments:
            return String(format: NSLocalizedString("explore.search.moments.found", comment: ""), moments.count)
        case .mixed:
            return String(format: NSLocalizedString("explore.search.mixed.found", comment: ""), users.count, moments.count)
        case .empty:
            return NSLocalizedString("explore.search.empty.subtitle", comment: "")
        }
    }
    
    private var headerIcon: String {
        switch searchType {
        case .hashtag:
            return "number"
        case .users:
            return "person.2"
        case .moments:
            return "photo.stack"
        case .mixed:
            return "magnifyingglass"
        case .empty:
            return "questionmark"
        }
    }
}

// MARK: - 📱 Componentes auxiliares
enum SearchDisplayType {
    case hashtag, users, moments, mixed, empty
}

struct MomentsSearchGrid: View {
    let moments: [Moment]
    let onMomentTap: (Moment) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(moments.prefix(12), id: \.id) { moment in
                MomentCard(
                    moment: moment,
                    onTap: { onMomentTap(moment) }
                )
            }
        }
        .padding(.horizontal, 0)
    }
}

struct MiniUserCard: View {
    let user: AppUser
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ProfileImageeView(imagePath: user.profileImagePath, size: 60)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                
                HStack(spacing: 2) {
                    Text("@\(user.username)")
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: user.id, size: 8)
                }
            }
        }
        .frame(width: 80)
    }
}

// MARK: - Componente de Búsquedas Recientes
struct RecentSearchesView: View {
    let searches: [CachedSearch]
    let onSearchSelected: (CachedSearch) -> Void
    let onClearAll: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("explore.recentSearches.title", comment: ""))
                    .font(.custom("Poppins-Bold", size: 28))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !searches.isEmpty {
                    Button(action: onClearAll) {
                        Text(NSLocalizedString("explore.recentSearches.clearAll", comment: ""))
                            .font(.custom("Poppins-Bold", size: 14))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            if searches.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(NSLocalizedString("explore.recentSearches.empty", comment: ""))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 8) {
                    ForEach(searches) { search in
                        Button(action: { onSearchSelected(search) }) {
                            HStack(spacing: 16) {
                                Image(systemName: searchIcon(for: search.type))
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(search.query)
                                        .font(.custom("Poppins-Medium", size: 16))
                                        .foregroundColor(.primary)
                                    
                                    Text(searchTypeLabel(for: search.type))
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 10)
    }
    
    private func searchIcon(for type: String) -> String {
        switch type {
        case "user": return "person.fill"
        case "hashtag": return "number"
        default: return "magnifyingglass"
        }
    }
    
    private func searchTypeLabel(for type: String) -> String {
        switch type {
        case "user": return NSLocalizedString("search.type.user", comment: "")
        case "hashtag": return NSLocalizedString("search.type.hashtag", comment: "")
        default: return NSLocalizedString("search.type.recent", comment: "")
        }
    }
}
