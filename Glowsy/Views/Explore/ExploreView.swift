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
    @State private var scrollOffset: CGFloat = 0
    @State private var showTrendingView = false
    let initialSearchQuery: String?
    
    init(initialSearchQuery: String? = nil) {
        self.initialSearchQuery = initialSearchQuery
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.bottom, 12)
                        
                        searchSection
                            .padding(.horizontal, 10)
                        
                        mainContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationBarHidden(true)
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
        }
    }
    
    // MARK: - Componentes de la Vista
    
    private var backgroundGradient: some View {
        ZStack {
            if colorScheme == .dark {
                // Mismo fondo que el Feed - negro suave y elegante
                Color(hex: "0A0A0A")
                    .ignoresSafeArea()
            } else {
                // Fondo claro elegante
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(hex: "f8f9fa"),
                        Color(hex: "e9ecef"),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
    }
    
    private var headerSection: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(min(1.0, abs(scrollOffset) / 80.0))
                .ignoresSafeArea(edges: .top)
            
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Explorar")
                        .font(.custom("Poppins-Bold", size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(.leading, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                Spacer()
                
                HStack(spacing: 12) {
                    // ✅ NUEVO: Botón de Trending
                    Button(action: {
                        ExploreHapticFeedback.impact(.medium)
                        showTrendingView = true
                    }) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color.orange.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    
                    // ✅ NUEVO: Botón de refresh
                    Button(action: {
                        ExploreHapticFeedback.impact(.medium)
                        viewModel.refreshContent()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(hex: "667eea"))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "667eea").opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color(hex: "667eea").opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .scaleEffect(viewModel.isLoadingTrending ? 0.9 : 1.0)
                    .rotationEffect(.degrees(viewModel.isLoadingTrending ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.isLoadingTrending)
                }
                .padding(.trailing, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
    }
        
        private var searchSection: some View {
            SearchBarView(
                searchText: $searchText,
                onSearch: viewModel.smartSearch  // ✅ CAMBIO: era viewModel.searchUsers
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
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
                    // ✅ Solo contenido esencial - SIN trending
                    suggestedUsersSection
                    momentsSection
                    
                } else {
                    searchResultsSection
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }
        
        private var suggestedUsersSection: some View {
            SuggestedUsersSection(
                users: viewModel.suggestedUsers,
                currentUserInterests: viewModel.currentUserInterests,
                userButtonStates: viewModel.userButtonStates,
                onFollowUser: viewModel.followUser,
                onUserTap: { user in
                    selectedUser = user
                    viewModel.checkCanViewContent(for: user.id) { _ in }
                }
            )
            .padding(.horizontal, 12)
            .onAppear {
                for user in viewModel.suggestedUsers {
                    viewModel.checkUserButtonState(for: user.id)
                }
            }
        }
        
        private var momentsSection: some View {
            MomentsGridSection(
                moments: viewModel.filteredMoments,
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
                for moment in viewModel.filteredMoments {
                    viewModel.loadAuthorProfile(for: moment.authorId)
                }
            }
        }
        
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
    

// MARK: - Barra de Búsqueda
struct SearchBarView: View {
    @Binding var searchText: String
    let onSearch: (String) -> Void
    @FocusState private var isSearchFocused: Bool
    
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
                    
                    TextField("Buscar usuarios, #hashtags, ubicaciones...", text: $searchText)
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.primary)
                        .focused($isSearchFocused)
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
                Button("Cancelar") {
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
                Text("Cargando contenido...")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("Encontrando momentos únicos para ti")
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
                Text("Oops, algo salió mal")
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
                        Text("Intentar de nuevo")
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
    let currentUserInterests: [String]
    let userButtonStates: [String: FollowButtonState]
    let onFollowUser: (String) -> Void
    let onUserTap: (AppUser) -> Void
    
    var body: some View {
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personas que podrían interesarte")
                            .font(.custom("Poppins-SemiBold", size: 22))
                            .foregroundColor(.primary)
                        
                        Text("Basado en tus intereses")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Ver más") {
                        // Acción para ver más usuarios
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(Color(hex: "667eea"))
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(users) { user in
                            SuggestedUserCard(
                                user: user,
                                commonInterests: Set(user.interests).intersection(Set(currentUserInterests)).count,
                                buttonState: userButtonStates[user.id] ?? .canFollow,
                                onFollow: { onFollowUser(user.id) },
                                onTap: { onUserTap(user) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Tarjeta de Usuario Sugerido
struct SuggestedUserCard: View {
    let user: AppUser
    let commonInterests: Int
    let buttonState: FollowButtonState
    let onFollow: () -> Void
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "667eea").opacity(0.3),
                                    Color(hex: "764ba2").opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    ProfileImageeView(imagePath: user.profileImagePath, size: 72)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.6), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
            }
            
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(user.username)")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: user.id, size: 12)
                }
                
                Text("\(commonInterests) intereses en común")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(Color(hex: "667eea"))
                    .multilineTextAlignment(.center)
            }
            
            FollowButton(
                user: user,
                buttonState: buttonState,
                onTap: onFollow
            )
        }
        .frame(width: 140)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
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
                        Text("\(commonInterests) intereses en común")
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
            return "Tu perfil"
        case .blocked:
            return "Bloqueado"
        case .following:
            return "Siguiendo"
        case .canFollow:
            return "Seguir"
        case .canRequestFollow:
            return "Solicitar"
        case .requestPending:
            return "Solicitado"
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

// MARK: - Sección de Grid de Moments
struct MomentsGridSection: View {
    let moments: [Moment]
    let onMomentTap: (Moment) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Momentos destacados")
                        .font(.custom("Poppins-SemiBold", size: 22))
                        .foregroundColor(.primary)
                    
                    Text("\(moments.count) momentos únicos")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 10)
            
            if moments.isEmpty {
                EmptyMomentsView()
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(moments, id: \.id) { moment in
                        MomentCard(
                            moment: moment,
                            onTap: { onMomentTap(moment) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Tarjeta de Moment
struct MomentCard: View {
    let moment: Moment
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
            
            // Contenido del momento (imagen o video)
            momentContent
            
            // Overlay con información
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 120, height: 120)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 50) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
    
    @ViewBuilder
    private var momentContent: some View {
        if let videoUrl = moment.videoUrl, !videoUrl.isEmpty {
            // Video thumbnail
            ExploreVideoThumbnailView(videoUrl: videoUrl)
        } else if let imagePath = moment.imagePath, let url = getImageURL(from: imagePath) {
            // Imagen
            KFImage(url)
                .placeholder {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                        )
                }
                .onFailure { error in
                    print("Error loading moment image: \(error)")
                }
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            // Placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "photo.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                )
        }
    }
}

// MARK: - Video Thumbnail View
struct ExploreVideoThumbnailView: View {
    let videoUrl: String
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "667eea")))
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }
                    )
            }
            
            // Indicador de video
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(8)
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
                        print("Error loading profile image: \(error)")
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
                Text("No hay momentos disponibles")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("Sigue a más usuarios para ver sus momentos")
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
                Text("No se encontraron usuarios")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("Intenta con un término diferente")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
    }
}



// MARK: - Preference Keys y Extensiones
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ExploreViewModel ACTUALIZADO
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
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    var currentUserInterests: [String] = []
    private var currentUserId: String?
    private var blockedUsers: Set<String> = []
    private let trendingService = TrendingService.shared
    
    // MARK: - FLUJO PRINCIPAL SIMPLIFICADO
    func fetchMomentsByInterests() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }
        
        self.currentUserId = userId
        isLoading = true
        errorMessage = nil
        
        print("🔍 Iniciando carga de ExploreView para usuario: \(userId)")
        
        // 1. PASO OBLIGATORIO: Cargar perfil del usuario actual
        self.firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let currentUserProfile):
                self.currentUserInterests = currentUserProfile.interests
                self.blockedUsers = Set(currentUserProfile.blockedUsers ?? [])
                
                print("🔍 Perfil cargado. Intereses: \(self.currentUserInterests.count)")
                
                // 2. PASO PRINCIPAL: Cargar usuarios y momentos
                self.loadUsersAndMoments()
                
            case .failure(let error):
                print("❌ Error al cargar perfil: \(error.localizedDescription)")
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
        ) { result in
            defer { group.leave() }
            
            if case .success(let users) = result {
                syncQueue.async {
                    allDiscoveredUsers.formUnion(users)
                }
                print("👥 [Explore] Usuarios con intereses compartidos: \(users.count)")
            }
        }
        
        // 2. Usuarios sugeridos (algoritmo interno de Firebase)
        group.enter()
        self.firestoreService.fetchSuggestedUsers { result in
            defer { group.leave() }
            
            if case .success(let users) = result {
                syncQueue.async {
                    allDiscoveredUsers.formUnion(users.prefix(20))
                }
                print("🎯 [Explore] Usuarios sugeridos: \(users.count)")
            }
        }
        
        // 3. Usuarios populares (fallback)
        group.enter()
        self.fetchPopularUsersForExplore(excludingUserId: userId) { users in
            syncQueue.async {
                allDiscoveredUsers.formUnion(users)
            }
            print("🔥 [Explore] Usuarios populares: \(users.count)")
            group.leave()
        }
        
        group.notify(queue: .main) {
            // Filtro BÁSICO - solo bloqueos
            let filteredUsers = Array(allDiscoveredUsers).filter { user in
                !self.blockedUsers.contains(user.id) &&
                !(user.blockedUsers ?? []).contains(userId)
            }
            
            print("👥 [Explore] Total de usuarios después de filtrar: \(filteredUsers.count)")
            
            // Ordenar por relevancia (intereses comunes)
            let sortedUsers = filteredUsers.sorted { user1, user2 in
                let commonInterests1 = Set(user1.interests).intersection(self.currentUserInterests).count
                let commonInterests2 = Set(user2.interests).intersection(self.currentUserInterests).count
                return commonInterests1 > commonInterests2
            }
            
            DispatchQueue.main.async {
                self.suggestedUsers = Array(sortedUsers.prefix(15))
                print("👥 [Explore] Usuarios sugeridos finales: \(self.suggestedUsers.count)")
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
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ [Explore] Error obteniendo usuarios populares: \(error)")
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
        print("📸 [Explore] Cargando momentos de \(userIds.count) usuarios")
        
        self.firestoreService.fetchMomentsFromUsers(userIds: userIds) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let allMoments):
                print("📸 [Explore] Momentos encontrados: \(allMoments.count)")
                
                // ✅ USAR LA FUNCIÓN DE FILTRADO ESPECÍFICA PARA EXPLORE
                self.filterMomentsForExploreVisibility(moments: allMoments) { filteredMoments in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.moments = filteredMoments
                        self.filteredMoments = filteredMoments
                        print("📸 [Explore] Momentos después de filtrar: \(self.moments.count)")
                        self.loadConnectionsOptionally()
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("❌ [Explore] Error al cargar momentos: \(error.localizedDescription)")
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
        
        print("🔍 [Explore] Filtrando \(moments.count) momentos para viewer: \(currentUserId)")
        
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
            privacyService.canUserViewMomentInExplore(moment, viewerId: currentUserId) { canView in
                if canView {
                    syncQueue.sync {
                        visibleMoments.append(moment)
                    }
                    print("✅ [Explore] Momento de \(moment.authorId) visible - Audiencia: \(moment.audience ?? "everyone")")
                } else {
                    print("❌ [Explore] Momento de \(moment.authorId) filtrado - Audiencia: \(moment.audience ?? "everyone")")
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
            
            print("📊 [Explore] Filtrado completado: \(orderedVisibleMoments.count)/\(moments.count) momentos visibles")
            completion(orderedVisibleMoments)
        }
    }
    
    // MARK: - Cargar conexiones de forma opcional
    private func loadConnectionsOptionally() {
        guard let userId = currentUserId else { return }
        
        firestoreService.fetchConnections(userId: userId) { [weak self] result in
            switch result {
            case .success(let connections):
                DispatchQueue.main.async {
                    self?.followedUserIds = Set(connections.map { $0.userId })
                    print("🔗 Conexiones cargadas: \(connections.count)")
                    self?.updateButtonStatesForAllUsers()
                }
            case .failure(let error):
                print("⚠️ No se pudieron cargar las conexiones (opcional): \(error.localizedDescription)")
            }
        }
        
        firestoreService.fetchNotifications(for: userId) { [weak self] result in
            switch result {
            case .success(let notifications):
                DispatchQueue.main.async {
                    self?.pendingRequests = Set(notifications.filter {
                        $0.type == .followRequest && $0.isPending
                    }.map { $0.senderId })
                    print("📬 Solicitudes pendientes: \(self?.pendingRequests.count ?? 0)")
                    self?.updateButtonStatesForAllUsers()
                }
            case .failure(let error):
                print("⚠️ No se pudieron cargar las notificaciones (opcional): \(error.localizedDescription)")
            }
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
                case .failure(let error):
                    print("Error al cargar perfil del autor \(userId): \(error.localizedDescription)")
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
                self?.userButtonStates[userId] = state
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
                    self.firestoreService.sendFollowRequest(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = "Error al enviar solicitud: \(error.localizedDescription)"
                            } else {
                                self?.userButtonStates[userId] = .requestPending
                                self?.pendingRequests.insert(userId)
                                
                                if let index = self?.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                                    self?.suggestedUsers.remove(at: index)
                                }
                            }
                        }
                    }
                } else {
                    self.firestoreService.followUser(
                        currentUserId: currentUserId,
                        targetUserId: userId
                    ) { [weak self] error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                            } else {
                                self?.userButtonStates[userId] = .following
                                self?.followedUserIds.insert(userId)
                                
                                if let index = self?.suggestedUsers.firstIndex(where: { $0.id == userId }) {
                                    self?.suggestedUsers.remove(at: index)
                                }
                            }
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
        
        print("🔍 [DEBUG] Estado actual de ExploreView:")
        print("   - Usuario actual: \(userId)")
        print("   - Intereses: \(currentUserInterests)")
        print("   - Usuarios bloqueados: \(blockedUsers)")
        print("   - Usuarios sugeridos: \(suggestedUsers.count)")
        print("   - Momentos totales: \(moments.count)")
        print("   - Momentos filtrados: \(filteredMoments.count)")
        
        // Mostrar distribución por audiencia
        let audienceDistribution = moments.reduce(into: [String: Int]()) { counts, moment in
            let audience = moment.audience ?? "everyone"
            counts[audience, default: 0] += 1
        }
        
        print("   - Distribución por audiencia:")
        for (audience, count) in audienceDistribution {
            print("     • \(audience): \(count)")
        }
    }
    
    // ✅ FUNCIÓN PARA REFRESCAR CONTENIDO
    func refreshContent() {
        moments = []
        filteredMoments = []
        suggestedUsers = []
        searchedUsers = []
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
        
        print("🔥 [ExploreVM] Cargando contenido trending...")
        
        trendingService.fetchPersonalizedTrendingContent(for: currentUserId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingTrending = false
                
                switch result {
                case .success(let content):
                    self?.trendingContent = content
                    print("🔥 [ExploreVM] Trending cargado exitosamente")
                    print("   - Hashtags: \(content.hashtags.count)")
                    print("   - Ubicaciones: \(content.locations.count)")
                    print("   - Momentos: \(content.moments.count)")
                    
                case .failure(let error):
                    self?.trendingError = "Error cargando trending: \(error.localizedDescription)"
                    print("❌ [ExploreVM] Error: \(error)")
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
        print("🔍 [ExploreVM] Buscando por hashtag: #\(hashtag)")
        
        // Limpiar búsqueda de usuarios
        searchedUsers = []
        
        // Buscar momentos que contengan el hashtag
        let filteredByHashtag = moments.filter { moment in
            moment.content.lowercased().contains("#\(hashtag.lowercased())")
        }
        
        filteredMoments = filteredByHashtag
        print("🔍 [ExploreVM] Encontrados \(filteredByHashtag.count) momentos con #\(hashtag)")
    }
    
    // ✅ FUNCIÓN para explorar por ubicación
    func exploreByLocation(_ locationName: String) {
        print("📍 [ExploreVM] Explorando ubicación: \(locationName)")
        
        // Filtrar momentos de esa ubicación
        let filteredByLocation = moments.filter { moment in
            (moment.location ?? "").lowercased().contains(locationName.lowercased())
        }
        
        filteredMoments = filteredByLocation
        searchedUsers = []
        print("📍 [ExploreVM] Encontrados \(filteredByLocation.count) momentos en \(locationName)")
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
        print("📱 SmartSearch ejecutado con: '\(query)'")
        print("📱 Momentos totales antes de buscar: \(moments.count)")
        
        if query.isEmpty {
            // Limpiar resultados
            searchedUsers = []
            filteredMoments = self.moments
            print("📱 Query vacío - mostrando todos los momentos: \(filteredMoments.count)")
            return
        }
        
        let searchType = detectSearchType(query: query)
        print("🔍 [SmartSearch] Query: '\(query)' → Tipo: \(searchType)")
        
        switch searchType {
        case .hashtag(let hashtag):
            print("🏷️ Buscando hashtag: '\(hashtag)'")
            searchHashtags(hashtag: hashtag)
            
        case .username(let username):
            print("👤 Buscando usuario: '\(username)'")
            searchUsers(username: username)
            
        case .location(let location):
            print("📍 Buscando ubicación: '\(location)'")
            searchLocations(location: location)
            
        case .mixed(let cleanQuery):
            print("🔄 Búsqueda mixta: '\(cleanQuery)'")
            searchEverything(query: cleanQuery)
        }
        
        // ✅ NUEVO: Debug final
        print("📱 Momentos encontrados después de búsqueda: \(filteredMoments.count)")
        for (index, moment) in filteredMoments.enumerated() {
            print("  [\(index + 1)] Usuario: \(moment.username)")
            print("      Contenido: '\(moment.content)'")
            print("      Ubicación: '\(moment.location ?? "sin ubicación")'")
            print("      ----")
        }
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
        
        firestoreService.db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: username)
            .whereField("username", isLessThanOrEqualTo: username + "\u{f8ff}")
            .limit(to: 20)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error al buscar usuarios: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    DispatchQueue.main.async {
                        self.searchedUsers = []
                    }
                    return
                }
                
                let users = documents.compactMap { doc -> AppUser? in
                    try? doc.data(as: AppUser.self)
                }.filter { user in
                    // ✅ FILTROS DE PRIVACIDAD (igual que antes):
                    // 1. No debe ser tu propio usuario
                    guard user.id != self.currentUserId else { return false }
                    
                    // 2. No debe estar en tu lista de bloqueados
                    guard !self.blockedUsers.contains(user.id) else { return false }
                    
                    // 3. No debes estar en su lista de bloqueados
                    guard !(user.blockedUsers ?? []).contains(self.currentUserId ?? "") else { return false }
                    
                    return true
                }
                
                DispatchQueue.main.async {
                    self.searchedUsers = users
                    print("🔍 [SmartSearch] Usuarios '@\(username)': \(users.count) encontrados")
                }
            }
    }
    private func searchHashtags(hashtag: String) {
        print("🔍 [DEBUG] === SEARCH HASHTAGS ===")
        print("🔍 [DEBUG] Hashtag buscado: '\(hashtag)'")
        print("🔍 [DEBUG] Total momentos disponibles: \(moments.count)")
        print("🔍 [DEBUG] currentUserId: '\(currentUserId ?? "N/A")'")
        
        // Debug de cada momento
        for (index, moment) in moments.enumerated() {
            print("🔍 [DEBUG] Momento \(index + 1):")
            print("  - Autor: \(moment.authorId) (\(moment.username))")
            print("  - Contenido: '\(moment.content)'")
            print("  - Audiencia: '\(moment.audience ?? "nil")'")
            print("  - ¿Contiene #\(hashtag)? \(moment.content.lowercased().contains("#\(hashtag)"))")
        }
        
        searchedUsers = []
        
        let candidateMoments = moments.filter { moment in
            // 1. Debe contener el hashtag
            guard moment.content.lowercased().contains("#\(hashtag)") else {
                print("🔍 [DEBUG] ❌ \(moment.username): No contiene hashtag")
                return false
            }
            
            // 2. Debe ser público para explore (audience: everyone)
            guard moment.audience == "everyone" || moment.audience == nil else {
                print("🔍 [DEBUG] ❌ \(moment.username): No es público")
                return false
            }
            
            // 3. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else {
                print("🔍 [DEBUG] ❌ \(moment.username): Usuario bloqueado")
                return false
            }
            
            // 4. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else {
                print("🔍 [DEBUG] ❌ \(moment.username): Es tuyo")
                return false
            }
            
            print("🔍 [DEBUG] ✅ \(moment.username): VÁLIDO")
            return true
        }
        
        filteredMoments = candidateMoments
        print("🔍 [SmartSearch] Hashtag '#\(hashtag)': \(candidateMoments.count) momentos públicos")
    }
    
    // ✅ BUSCAR por ubicaciones CON FILTRADO DE PRIVACIDAD
    private func searchLocations(location: String) {
        searchedUsers = [] // Limpiar usuarios
        
        // ✅ FILTRAR: Solo momentos públicos + sin bloqueos + visible en explore
        let candidateMoments = moments.filter { moment in
            // 1. Debe tener ubicación que coincida
            guard let momentLocation = moment.location else { return false }
            guard momentLocation.lowercased().contains(location.lowercased()) else { return false }
            
            // 2. Debe ser público para explore (audience: everyone)
            guard moment.audience == "everyone" || moment.audience == nil else { return false }
            
            // 3. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else { return false }
            
            // 4. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else { return false }
            
            return true
        }
        
        filteredMoments = candidateMoments
        print("🔍 [SmartSearch] Ubicación '\(location)': \(candidateMoments.count) momentos públicos")
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
            // 1. Debe ser público para explore (audience: everyone)
            guard moment.audience == "everyone" || moment.audience == nil else { return false }
            
            // 2. No debe ser de usuarios bloqueados
            guard !blockedUsers.contains(moment.authorId) else { return false }
            
            // 3. No debe ser tuyo (explore es para descubrir)
            guard moment.authorId != currentUserId else { return false }
            
            return true
        }
        
        DispatchQueue.main.async {
            self.filteredMoments = candidateMoments
            print("🔍 [SmartSearch] Búsqueda mixta '\(query)': \(candidateMoments.count) momentos públicos")
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
                Text("Momentos con \(searchQuery)")
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
                Text("Momentos encontrados")
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
                        Text("Usuarios")
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
                        Text("Momentos")
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
            return "Hashtag: \(searchQuery)"
        case .users:
            return searchQuery.hasPrefix("@") ? "Usuario: \(String(searchQuery.dropFirst()))" : "Usuarios"
        case .moments:
            return "Momentos"
        case .mixed:
            return "Resultados para '\(searchQuery)'"
        case .empty:
            return "Sin resultados"
        }
    }
    
    private var headerSubtitle: String {
        switch searchType {
        case .hashtag:
            return "\(moments.count) momentos encontrados"
        case .users:
            return "\(users.count) usuarios encontrados"
        case .moments:
            return "\(moments.count) momentos encontrados"
        case .mixed:
            return "\(users.count) usuarios • \(moments.count) momentos"
        case .empty:
            return "Intenta con términos diferentes"
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
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(moments.prefix(12), id: \.id) { moment in
                MomentCard(
                    moment: moment,
                    onTap: { onMomentTap(moment) }
                )
            }
        }
        .padding(.horizontal, 24)
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
