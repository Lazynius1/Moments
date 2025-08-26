import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import Kingfisher
import CoreMotion
import AVFoundation

struct ProfileColors {
    static var background: Color {
        Color(UIColor.systemBackground)
    }
    
    static var secondaryBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }
    
    static var cardBackground: Color {
        Color(UIColor.systemBackground).opacity(0.8)
    }
    
    static var materialBackground: Color {
        Color(UIColor.systemBackground).opacity(0.95)
    }
    
    static var textPrimary: Color {
        Color(UIColor.label)
    }
    
    static var textSecondary: Color {
        Color(UIColor.secondaryLabel)
    }
    
    static var textTertiary: Color {
        Color(UIColor.tertiaryLabel)
    }
    
    static var borderColor: Color {
        Color(UIColor.separator)
    }
    
    static var shadowColor: Color {
        Color(UIColor.label).opacity(0.1)
    }
    
    // Colores específicos que se mantienen
    static let accent = Color(hex: "00A896")
    static let purple = Color(hex: "9B59B6")
    static let blue = Color(hex: "6B73FF")
}


struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = ProfileViewModel()
    @Binding var selectedTab: Int
    @StateObject private var storyViewModel = StoryViewModel()
    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var newBio: String = ""
    @State private var showingUserList: UserListType?
    @State private var errorMessage: String?
    @State private var showStoryViewer: Bool = false
    @State private var selectedStoryIndex: Int = 0
    @State private var showCircularMenu: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showMomentDetail = false
    @State private var selectedMomentIndex = 0
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false
    @State private var showingThemeSelector = false
    

    enum UserListType: Identifiable {
        case visits
        case admirers
        case connections
        case mutualConnections

        var id: String {
            switch self {
            case .visits: return "visits"
            case .admirers: return "admirers"
            case .connections: return "connections"
            case .mutualConnections: return "mutualConnections"
            }
        }

        var title: String {
            switch self {
            case .visits: return NSLocalizedString("profile.userList.visits", comment: "Visits")
            case .admirers: return NSLocalizedString("profile.userList.admirers", comment: "Admirers")
            case .connections: return NSLocalizedString("profile.userList.connections", comment: "Connections")
            case .mutualConnections: return NSLocalizedString("profile.userList.mutuals", comment: "Mutual connections")
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom

            NavigationView {
                ZStack {
                    // Fondo dinámico mejorado con efectos (FULLSCREEN)
                    EnhancedProfileBackground(
                        profileImagePath: viewModel.userProfile?.profileImagePath,
                        scrollOffset: scrollOffset,
                        profileTheme: viewModel.userProfile?.currentProfileTheme ?? .default,
                        user: viewModel.userProfile
                    )
                    .ignoresSafeArea(.all, edges: .all)

                    ModernProfileContentView(
                        viewModel: viewModel,
                        storyViewModel: storyViewModel,
                        safeAreaTop: safeAreaTop,
                        safeAreaBottom: safeAreaBottom,
                        isShowingSettings: $isShowingSettings,
                        isShowingEditProfile: $isShowingEditProfile,
                        newBio: $newBio,
                        showingUserList: $showingUserList,
                        showStoryViewer: $showStoryViewer,
                        selectedStoryIndex: $selectedStoryIndex,
                        showCircularMenu: $showCircularMenu,
                        selectedPhoto: $selectedPhoto,
                        scrollOffset: $scrollOffset,
                        showMomentDetail: $showMomentDetail,
                        selectedMomentIndex: $selectedMomentIndex,
                        showingThemeSelector: $showingThemeSelector
                    )

                    if showCircularMenu {
                        CircularMenuView(userId: Auth.auth().currentUser?.uid ?? "", isShowing: $showCircularMenu)
                    }
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.all, edges: .all)
                .fullScreenCover(isPresented: $isShowingSettings) {
                    SettingsView()
                }
                .fullScreenCover(isPresented: $isShowingEditProfile) {
                    ModernEditProfileView(
                        selectedPhoto: $selectedPhoto,
                        newBio: $newBio,
                        onSave: { photo, bio in
                            if let photo = photo {
                                viewModel.uploadProfilePicture(item: photo)
                            }
                            viewModel.updateBio(newBio: bio)
                        }
                    )
                }
                .sheet(isPresented: $showingThemeSelector) {
                    if let currentUser = authService.currentUser {
                        ProfileThemeSelector(user: currentUser)
                    }
                }
                
                .fullScreenCover(isPresented: $showMomentDetail) {
                    ModernMomentDetailView(
                        moments: viewModel.moments,
                        initialIndex: selectedMomentIndex,
                        onDismiss: {
                            showMomentDetail = false
                        }
                    )
                }
                .sheet(item: $showingUserList) { listType in
                    switch listType {
                    case .visits:
                        VisitsView()
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.hidden)
                            .interactiveDismissDisabled(false)
                            .presentationBackground(.clear)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    case .admirers, .connections, .mutualConnections:
                        UserListView(
                            title: listType.title,
                            users: usersForList(type: listType),
                            visitTimestamps: [:],
                            viewModel: viewModel,
                            onDismiss: { showingUserList = nil }
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                        .interactiveDismissDisabled(false)
                        .presentationBackground(.clear)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .fullScreenCover(isPresented: $showStoryViewer) {
                    if let userId = Auth.auth().currentUser?.uid,
                       let stories = storyViewModel.stories[userId], !stories.isEmpty {
                        GlassmorphicStoryViewer(
                            story: stories[selectedStoryIndex],
                            storyCount: stories.count,
                            storyIndex: selectedStoryIndex,
                            screenSize: UIScreen.main.bounds.size,
                            storyViewModel: storyViewModel,
                            // ✅ AGREGAR: Pasar los bindings
                            showingReportSheet: $showingReportSheet,
                            showingBlockConfirmation: $showingBlockConfirmation,
                            onReportStory: {
                                // Para historias propias, no aplica reporte
                            },
                            onBlockUser: {
                                // Para historias propias, no aplica bloqueo
                            },
                            onNext: {
                                if selectedStoryIndex + 1 < stories.count {
                                    selectedStoryIndex += 1
                                } else {
                                    showStoryViewer = false
                                }
                            },
                            onPrevious: {
                                if selectedStoryIndex > 0 {
                                    selectedStoryIndex -= 1
                                }
                            },
                            onClose: { showStoryViewer = false },
                            onProfileTap: {
                                // Para historias propias, no aplica navegación de perfil
                            }
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showingUserList)
                .onChange(of: selectedTab) { newTab in
                    if newTab == 4 {
                        isShowingSettings = false
                        isShowingEditProfile = false
                    }
                }
                .onAppear {
                    Auth.auth().addStateDidChangeListener { auth, user in
                        if let userId = user?.uid {
                            viewModel.fetchProfile(userId: userId)
                            storyViewModel.fetchStories(for: userId, includeConnections: false)
                            storyViewModel.checkActiveStories(userId: userId)
                        } else {
                            viewModel.isLoading = false
                            viewModel.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
                        }
                    }
                }
            }
        }
    }

    private func usersForList(type: UserListType) -> [AppUser] {
        switch type {
        case .visits: return viewModel.visits
        case .admirers: return viewModel.admirers
        case .connections: return viewModel.connections
        case .mutualConnections: return viewModel.mutualConnections
        }
    }
    
    // Función auxiliar para calcular altura del grid
    private func calculateGridHeight(itemCount: Int) -> CGFloat {
        let columns = 3
        let rows = ceil(Double(itemCount) / Double(columns))
        let spacing: CGFloat = 4
        let itemWidth = (UIScreen.main.bounds.width - 16 - (spacing * 2)) / 3
        return CGFloat(rows) * itemWidth + (CGFloat(rows - 1) * spacing)
    }
}

// MARK: - Fondo dinámico con temas
struct ModernBackgroundView: View {
    let profileImagePath: String?
    let scrollOffset: CGFloat
    let profileTheme: ProfileTheme
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Gradiente base basado en el tema del perfil
            if colorScheme == .dark {
                profileTheme.darkBackgroundGradient
            } else {
                profileTheme.backgroundGradient
            }
            
            // Imagen de perfil como fondo adaptativo
            if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                GeometryReader { geometry in
                    KFImage(url)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 30)
                        .opacity(colorScheme == .dark ? 0.15 : 0.08)
                        .scaleEffect(1.2)
                        .offset(y: scrollOffset * 0.2)
                        .ignoresSafeArea()
                }
            }
            
            // Overlay adaptativo para legibilidad
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: colorScheme == .dark ? [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.5),
                            Color.black.opacity(0.7)
                        ] : [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.6)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
            
            // Overlay de glassmorphism adaptativo
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.03)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

// MARK: - ModernProfileContentView (Actualizada con refresh)
struct ModernProfileContentView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    @Binding var isShowingSettings: Bool
    @Binding var isShowingEditProfile: Bool
    @Binding var newBio: String
    @Binding var showingUserList: ProfileView.UserListType?
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var showCircularMenu: Bool
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var scrollOffset: CGFloat
    @Binding var showMomentDetail: Bool
    @Binding var selectedMomentIndex: Int
    @Binding var showingThemeSelector: Bool

    var body: some View {
        if viewModel.isLoading {
            ModernLoadingView()
        } else if let errorMessage = viewModel.errorMessage {
            ModernErrorView(errorMessage: errorMessage, onRetry: {
                if let userId = Auth.auth().currentUser?.uid {
                    viewModel.fetchProfile(userId: userId)
                }
            })
        } else {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ModernProfileHeader(
                            viewModel: viewModel,
                            storyViewModel: storyViewModel,
                            isShowingSettings: $isShowingSettings,
                            isShowingEditProfile: $isShowingEditProfile,
                            newBio: $newBio,
                            showStoryViewer: $showStoryViewer,
                            selectedStoryIndex: $selectedStoryIndex,
                            showCircularMenu: $showCircularMenu,
                            showingThemeSelector: $showingThemeSelector
                        )
                        .padding(.top, safeAreaTop + 10)
                        .padding(.bottom, 20)
                        
                        if viewModel.isRefreshing {
                            ModernRefreshIndicator()
                                .padding(.bottom, 16)
                        }
                        
                        ModernStatsSection(
                            viewModel: viewModel,
                            showingUserList: $showingUserList
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 25)
                        
                        if let interests = viewModel.userProfile?.interests, !interests.isEmpty {
                            ModernInterestsView(interests: interests)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 30)
                                .frame(maxWidth: UIScreen.main.bounds.width)
                        }
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text("profile.moments.title")
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(ProfileColors.textPrimary) // <- CAMBIO AQUÍ
                                
                                Spacer()
                                
                                Text("\(viewModel.moments.count)")
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(ProfileColors.textSecondary) // <- CAMBIO AQUÍ
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(ProfileColors.cardBackground) // <- CAMBIO AQUÍ
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(ProfileColors.borderColor, lineWidth: 0.5) // <- CAMBIO AQUÍ
                                    )
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .frame(maxWidth: UIScreen.main.bounds.width)
                            
                            if viewModel.moments.isEmpty {
                                ModernEmptyMomentsView()
                                    .padding(.horizontal, 20)
                                    .frame(maxWidth: UIScreen.main.bounds.width - 40)
                            } else {
                                GeometryReader { geometry in
                                    let spacing: CGFloat = 4
                                    let columns = 3
                                    let totalSpacing = spacing * CGFloat(columns - 1) + 16
                                    let itemWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columns), spacing: spacing) {
                                        // ✅ CORREGIDO: Usar enumerated para obtener índices
                                        ForEach(Array(viewModel.moments.enumerated()), id: \.offset) { index, moment in
                                            ModernMomentThumbnail(
                                                moment: moment,
                                                size: itemWidth,
                                                onTap: {
                                                    // ✅ NUEVO: Al tocar abrir vista detallada con scroll
                                                    selectedMomentIndex = index
                                                    showMomentDetail = true
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                }
                                .frame(height: calculateGridHeight(itemCount: viewModel.moments.count))
                            }
                        }
                        .frame(maxWidth: UIScreen.main.bounds.width)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                        }
                    )
                    .padding(.bottom, safeAreaBottom + 100)
                }
                .coordinateSpace(name: "scroll")
                .refreshable {
                    await withCheckedContinuation { continuation in
                        viewModel.refreshProfile()
                        
                        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            if !viewModel.isRefreshing {
                                timer.invalidate()
                                continuation.resume()
                            }
                        }
                    }
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
        }
    }
    
    // Moved calculateGridHeight to this scope
    private func calculateGridHeight(itemCount: Int) -> CGFloat {
        let columns = 3
        let rows = ceil(Double(itemCount) / Double(columns))
        let spacing: CGFloat = 4
        let itemWidth = (UIScreen.main.bounds.width - 16 - (spacing * 2)) / 3
        return CGFloat(rows) * itemWidth + (CGFloat(rows - 1) * spacing)
    }
}

// MARK: -  Indicador de refresh
struct ModernRefreshIndicator: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ProfileColors.materialBackground)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ProfileColors.accent.opacity(0.6),
                                        ProfileColors.borderColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ProfileColors.accent, ProfileColors.textSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .scaleEffect(pulseScale)
            }
            
                            Text("profile.updating")
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(ProfileColors.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ProfileColors.materialBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            ProfileColors.borderColor,
                            ProfileColors.accent.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: ProfileColors.shadowColor, radius: 8, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
}

// Header adaptativo

struct ModernProfileHeader: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var storyViewModel: StoryViewModel
    @EnvironmentObject var authService: AuthService
    @Binding var isShowingSettings: Bool
    @Binding var isShowingEditProfile: Bool
    @Binding var newBio: String
    @Binding var showStoryViewer: Bool
    @Binding var selectedStoryIndex: Int
    @Binding var showCircularMenu: Bool
    @Binding var showingThemeSelector: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var profileImage: UIImage?
    @State private var isLoadingImage = false

    var body: some View {
        VStack(spacing: 24) {
            // Avatar hero con efectos adaptativos
            ZStack {
                // Círculo de fondo con gradiente adaptativo
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                ProfileColors.accent.opacity(colorScheme == .dark ? 0.2 : 0.15),
                                ProfileColors.purple.opacity(colorScheme == .dark ? 0.1 : 0.08),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 40,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: 15)
                
                // Avatar principal
                Group {
                    if let profileImage = profileImage {
                        // Imagen de perfil cargada
                        Image(uiImage: profileImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                            .contentShape(Circle())
                    } else if isLoadingImage {
                        // Estado de carga
                        Circle()
                            .fill(ProfileColors.materialBackground)
                            .frame(width: 110, height: 110)
                            .overlay(
                                ProgressView()
                                    .tint(ProfileColors.accent)
                                    .scaleEffect(1.2)
                            )
                    } else {
                        // Placeholder cuando no hay imagen
                        Circle()
                            .fill(ProfileColors.materialBackground)
                            .frame(width: 110, height: 110)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(ProfileColors.textTertiary)
                            )
                    }
                }
                .overlay(avatarBorderOverlay())
                .shadow(color: ProfileColors.shadowColor, radius: 15, x: 0, y: 8)
                
                // Badges adaptativos
                if let currentUser = authService.currentUser,
                   let primaryBadge = currentUser.primaryBadge {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: primaryBadge.swiftUIColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Text(primaryBadge.emoji)
                            .font(.system(size: 18))
                    }
                    .offset(x: 45, y: -45)
                    .shadow(color: ProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
                
                // Corona Plus adaptativa (se oculta si hay tema activo o si está desactivado)
                if let currentUser = authService.currentUser,
                   currentUser.isPlusSubscriber,
                   currentUser.showPlusBadge,
                   currentUser.selectedProfileTheme == nil || currentUser.selectedProfileTheme == "default" {
                    ZStack {
                        Circle()
                            .fill(ProfileColors.cardBackground)
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "FFD700"))
                    }
                    .offset(x: -45, y: -45)
                    .shadow(color: ProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
                
                // Indicador de nivel supporter - OCULTO
                // if let currentUser = authService.currentUser,
                //    currentUser.isSupporter && currentUser.supporterLevel != .none {
                //     SupporterLevelIndicator(level: currentUser.supporterLevel)
                //         .offset(x: 0, y: 65)
                //         .shadow(color: ProfileColors.shadowColor, radius: 4, x: 0, y: 2)
                // }
            }
            .onTapGesture {
                if storyViewModel.hasActiveStory, let userId = Auth.auth().currentUser?.uid {
                    showStoryViewer = true
                    selectedStoryIndex = 0
                } else {
                    showCircularMenu.toggle()
                }
            }
            
            // Información del usuario adaptativa
            VStack(spacing: 10) {
                VStack(spacing: 8) {
                    VerifiedUsernameGradientView(
                        username: viewModel.userProfile?.username ?? "Usuario",
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        badgeSize: 20,
                        spacing: 6,
                        gradient: LinearGradient(
                            colors: [Color(hex: "00A896"), Color(hex: "6B73FF")], // ✅ MISMO GRADIENTE QUE USERPROFILEVIEW
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.custom("Poppins-Bold", size: 26))
                    
                    // Badges horizontales adaptativos
                    if let currentUser = authService.currentUser,
                       (currentUser.isPlusSubscriber || currentUser.isSupporter) {
                        HStack(spacing: 8) {
                            if currentUser.isPlusSubscriber,
                               currentUser.showPlusBadge,
                               currentUser.selectedProfileTheme == nil || currentUser.selectedProfileTheme == "default" {
                                PlusBadgeInline()
                            }
                            
                            if let primaryBadge = currentUser.primaryBadge {
                                SupportBadgeInline(badge: primaryBadge)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: currentUser.isPlusSubscriber)
                        .animation(.easeInOut(duration: 0.3), value: currentUser.primaryBadge?.id)
                    }
                }
                
                // Bio expandible adaptativa
                VStack(spacing: 8) {
                    ExpandableBioView(bio: viewModel.userProfile?.bio ?? "Añade una biografía")
                }
            }
            
            // Botones de acción adaptativos
            HStack(spacing: 16) {
                Button(action: {
                    newBio = viewModel.userProfile?.bio ?? ""
                    isShowingEditProfile = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 16))
                        Text("profile.editButton")
                            .font(.custom("Poppins-SemiBold", size: 14))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(ProfileColors.materialBackground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [ProfileColors.accent.opacity(0.6), ProfileColors.borderColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: ProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
                
                // ✅ TEMPORALMENTE OCULTO: Botón de tema del perfil (solo si tiene badges)
                // if let currentUser = authService.currentUser, currentUser.canChangeProfileTheme {
                //     Button(action: {
                //         showingThemeSelector = true
                //     }) {
                //         Image(systemName: "paintbrush.fill")
                //         .font(.system(size: 18))
                //         .foregroundColor(ProfileColors.textPrimary)
                //         .frame(width: 44, height: 44)
                //         .background(ProfileColors.materialBackground)
                //         .clipShape(Circle())
                //         .overlay(
                //         Circle()
                //         .stroke(ProfileColors.borderColor, lineWidth: 1)
                //         )
                //         .shadow(color: ProfileColors.shadowColor, radius: 4, x: 0, y: 2)
                //     }
                // }
                
                Button(action: { isShowingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(ProfileColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(ProfileColors.materialBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(ProfileColors.borderColor, lineWidth: 1)
                        )
                        .shadow(color: ProfileColors.shadowColor, radius: 4, x: 0, y: 2)
                }
            }
        }
        .padding(.horizontal, 24)
        .onAppear {
            loadProfileImage()
        }
        .onChange(of: viewModel.userProfile?.profileImagePath) { _ in
            loadProfileImage()
        }
    }
    
    // MARK: - Cargar imagen de perfil
    private func loadProfileImage() {
        guard let profileImagePath = viewModel.userProfile?.profileImagePath,
              let url = URL(string: profileImagePath) else {
            profileImage = nil
            return
        }
        
        isLoadingImage = true
        
        // Usar URLSession para cargar la imagen
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingImage = false
                
                if let data = data, let uiImage = UIImage(data: data) {
                    profileImage = uiImage
                } else {
                    profileImage = nil
                }
            }
        }.resume()
    }
    
    // Border inteligente del avatar adaptativo (SIN BORDE VERDE)
    @ViewBuilder
    private func avatarBorderOverlay() -> some View {
        let currentUser = authService.currentUser
        
        Circle()
            .stroke(
                LinearGradient(
                    gradient: storyViewModel.hasActiveStory ?
                    Gradient(colors: [.red, .purple, .blue, .pink]) :
                    (currentUser?.isPlusSubscriber == true && currentUser?.showPlusBadge == true ?
                     Gradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")]) :
                     Gradient(colors: [Color.clear, Color.clear])), // ✅ QUITADO: Borde verde
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: storyViewModel.hasActiveStory ? 3 : (currentUser?.isPlusSubscriber == true && currentUser?.showPlusBadge == true ? 3 : 0) // ✅ QUITADO: Borde cuando no hay story o Plus
            )
    }
}

// ✅ NUEVO: Plus Badge Inline
struct PlusBadgeInline: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            
                            Text("profile.plus")
                .font(.custom("Poppins-Bold", size: 9))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 3, x: 0, y: 1)
    }
}

// ✅ NUEVO: Support Badge Inline
struct SupportBadgeInline: View {
    let badge: UserBadge
    
    var body: some View {
        HStack(spacing: 4) {
            Text(badge.emoji)
                .font(.system(size: 10))
            
            Text(badge.name.uppercased())
                .font(.custom("Poppins-Bold", size: 8))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: badge.swiftUIColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: badge.swiftUIColors.first?.opacity(0.3) ?? .clear, radius: 3, x: 0, y: 1)
    }
}


// MARK: - Sección de estadísticas moderna (ARREGLADA)
struct ModernStatsSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var showingUserList: ProfileView.UserListType?
    @Environment(\.colorScheme) var colorScheme
    
    private var computedStats: [(String, Int, ProfileView.UserListType)] {
        [
            (NSLocalizedString("profile.stats.visits", comment: "Visits"), viewModel.visits.count, .visits),
            (NSLocalizedString("profile.stats.admirers", comment: "Admirers"), viewModel.admirers.count, .admirers),
            (NSLocalizedString("profile.stats.connections", comment: "Connections"), viewModel.connections.count, .connections),
            (NSLocalizedString("profile.stats.mutuals", comment: "Mutuals"), viewModel.mutualConnections.count, .mutualConnections)
        ]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(computedStats.enumerated()), id: \.offset) { index, stat in
                Button(action: {
                    showingUserList = stat.2
                }) {
                    VStack(spacing: 6) {
                        Text("\(stat.1)")
                            .font(.custom("Poppins-Bold", size: 18))
                            .foregroundColor(ProfileColors.textPrimary)
                        
                        Text(stat.0)
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(ProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ProfileColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ProfileColors.borderColor,
                                        ProfileColors.accent.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: ProfileColors.shadowColor, radius: 6, x: 0, y: 3)
                }
                .scaleEffect(1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingUserList)
            }
        }
    }
}

// MARK: - Vista de intereses
struct ModernInterestsView: View {
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
                            Text("profile.interests.title")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(ProfileColors.textPrimary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(interests, id: \.self) { interest in
                        let emoji = interestEmoji(for: interest)
                        
                        HStack(spacing: 6) {
                            Text(emoji)
                                .font(.system(size: 16))
                            Text(interest)
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(ProfileColors.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ProfileColors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            ProfileColors.borderColor,
                                            ProfileColors.accent.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: ProfileColors.shadowColor, radius: 4, x: 0, y: 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interestEmoji(for interest: String) -> String {
        switch interest.lowercased() {
        case "gamer": return "🎮"
        case "league of legends": return "🏹"
        case "bcn": return "🏠"
        case "kpop": return "🎵"
        case "fotografía": return "📸"
        case "cine": return "🎬"
        case "música": return "🎶"
        case "tecnología": return "💻"
        case "moda": return "👗"
        case "arte": return "🎨"
        case "deportes": return "⚽"
        case "viajes": return "✈️"
        case "cocina": return "👨‍🍳"
        case "lectura": return "📚"
        case "anime": return "🍜"
        default: return "✨"
        }
    }
}

// MARK: - Thumbnail de momento moderno (OPTIMIZADO)
// Reemplaza solo el contenido del body en tu ModernMomentThumbnail

struct ModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let onTap: (() -> Void)? // ✅ MANTENER: Callback opcional
    @State private var isPressed = false
    
    // ✅ NUEVOS: Estados para thumbnails de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    var body: some View {
        Button(action: {
            onTap?() // ✅ MANTENER: Ejecutar callback si existe
        }) {
            ZStack(alignment: .bottomTrailing) {
                // ✅ NUEVO: Lógica actualizada para manejar videos y imágenes
                if let mediaItem = moment.mediaItems?.first, !mediaItem.url.isEmpty {
                    // Es un momento nuevo con mediaItems
                    if mediaItem.type == .video {
                        // ✅ NUEVO: Mostrar thumbnail de video
                        videoThumbnailView(videoURL: mediaItem.url)
                    } else {
                        // ✅ NUEVO: Mostrar imagen desde mediaItems
                        imageView(imageURL: mediaItem.url)
                    }
                } else if let imagePath = moment.imagePath, let url = getImageURL(from: imagePath) {
                    // ✅ MANTENER: Fallback para momentos legacy con imagePath
                    KFImage(url)
                        .placeholder {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                        .foregroundColor(.gray.opacity(0.6))
                                )
                                .overlay(ProgressView().tint(Color(hex: "00A896")))
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(borderOverlay())
                        .clipped()
                } else {
                    // ✅ MANTENER: Placeholder para sin contenido
                    emptyContentView()
                }
                
                // ✅ NUEVO: Indicador de video
                if let mediaItem = moment.mediaItems?.first, mediaItem.type == .video {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .padding(6)
                        }
                        Spacer()
                    }
                }
                
                // ✅ MANTENER: Contador de likes
                if let likeCount = moment.reactions["heart"]?.count, likeCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 9))
                        Text("\(likeCount)")
                            .font(.custom("Poppins-Medium", size: 9))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(4)
                }
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { isPressed = $0 }, perform: {})
    }
    
    // ✅ NUEVA: Vista para thumbnails de video
    @ViewBuilder
    private func videoThumbnailView(videoURL: String) -> some View {
        ZStack {
            if let thumbnail = videoThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(borderOverlay())
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                    .overlay(
                        Group {
                            if isLoadingVideoThumbnail {
                                VStack(spacing: 6) {
                                    ProgressView()
                                        .tint(Color(hex: "00A896"))
                                        .scaleEffect(0.8)
                                    Text("profile.video.uploading")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                        .foregroundColor(.gray.opacity(0.6))
                                    Text("profile.video")
                                        .font(.custom("Poppins-Regular", size: 8))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                    )
                    .overlay(borderOverlay())
            }
        }
        .onAppear {
            loadVideoThumbnail(from: videoURL)
        }
    }
    
    // ✅ NUEVA: Vista para imágenes desde mediaItems
    @ViewBuilder
    private func imageView(imageURL: String) -> some View {
        if let url = getImageURL(from: imageURL) {
            KFImage(url)
                .placeholder {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            VStack(spacing: 6) {
                                ProgressView()
                                    .tint(Color(hex: "00A896"))
                                    .scaleEffect(0.8)
                                Text("profile.image.uploading")
                                    .font(.custom("Poppins-Regular", size: 8))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        )
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .overlay(borderOverlay())
                .clipped()
        } else {
            emptyContentView()
        }
    }
    
    // ✅ NUEVA: Vista para contenido vacío
    @ViewBuilder
    private func emptyContentView() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .frame(width: size, height: size)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 16))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text(moment.content.isEmpty ? NSLocalizedString("profile.content.empty", comment: "No content text") : String(moment.content.prefix(12)))
                        .font(.custom("Poppins-Regular", size: 8))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 3)
                }
            )
            .overlay(borderOverlay())
    }
    
    // ✅ NUEVA: Overlay de borde reutilizable
    @ViewBuilder
    private func borderOverlay() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.3),
                        Color(hex: "00A896").opacity(0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    // ✅ NUEVA: Función para cargar thumbnail de video
    private func loadVideoThumbnail(from urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        
        isLoadingVideoThumbnail = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: size * 2, height: size * 2) // Retina
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                
                DispatchQueue.main.async {
                    self.videoThumbnail = uiImage
                    self.isLoadingVideoThumbnail = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingVideoThumbnail = false
                }
            }
        }
    }
    
    // ✅ MANTENER: Función existente
    private func getImageURL(from path: String) -> URL? {
        if path.hasPrefix("https://") {
            return URL(string: path)
        }
        let baseURLString = "https://firebasestorage.googleapis.com/v0/b/glowsy-6a40e/o/"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(baseURLString)\(encodedPath)?alt=media")
    }
    
    // ✅ MANTENER: Inicializador existente
    init(moment: Moment, size: CGFloat, onTap: (() -> Void)? = nil) {
        self.moment = moment
        self.size = size
        self.onTap = onTap
    }
}


// MARK: - Estado vacío para momentos
struct ModernEmptyMomentsView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(ProfileColors.materialBackground)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        ProfileColors.accent.opacity(0.4),
                                        ProfileColors.borderColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "camera.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ProfileColors.accent, ProfileColors.textSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("profile.moments.empty.title")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(ProfileColors.textPrimary)
                
                Text("profile.moments.empty.subtitle")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .background(ProfileColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            ProfileColors.borderColor,
                            ProfileColors.accent.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
// MARK: - Vista de carga
struct ModernLoadingView: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(ProfileColors.accent.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [ProfileColors.accent, ProfileColors.textPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
            
                            Text("profile.loading")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(ProfileColors.textSecondary)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Vista de error
struct ModernErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(ProfileColors.materialBackground)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    )
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 35))
                    .foregroundColor(.red.opacity(0.8))
            }
            
            VStack(spacing: 12) {
                Text("profile.error.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(ProfileColors.textPrimary)
                
                Text(errorMessage)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                    Text("profile.error.retryButton")
                        .font(.custom("Poppins-SemiBold", size: 14))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(ProfileColors.accent)
                .clipShape(Capsule())
                .shadow(color: ProfileColors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 40)
    }
}

struct ExpandableBioView: View {
    let bio: String
    @State private var isExpanded: Bool = false
    @State private var needsExpansion: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Text(bio)
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(ProfileColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(isExpanded ? nil : 3)
                .background(
                    Text(bio)
                        .font(.custom("Poppins-Regular", size: 15))
                        .lineLimit(3)
                        .background(GeometryReader { geometry in
                            Color.clear.onAppear {
                                let limitedHeight = geometry.size.height
                                
                                DispatchQueue.main.async {
                                    needsExpansion = bio.count > 100
                                }
                            }
                        })
                        .hidden()
                )
                .padding(.horizontal, 40)
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
            
            if needsExpansion {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Text(isExpanded ? NSLocalizedString("profile.content.seeLess", comment: "See less text") : NSLocalizedString("profile.content.seeMore", comment: "See more text"))
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(ProfileColors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(ProfileColors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Flow Layout para intereses
struct ProfileFlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size = CGSize.zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentX + subviewSize.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: subviewSize.width, height: subviewSize.height))
                
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
            }
            
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Preference Key para scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ProfileViewModel
class ProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var visits: [AppUser] = []
    @Published var visitTimestamps: [String: [Date]] = [:]
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []
    @Published var admirers: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    @Published var profileImagePath: String?
    @Published var isRefreshing: Bool = false

    private let firestoreService = FirestoreService()
    private let storageService = StorageService()
    
    // ✅ NUEVO: Cache local para tracking de unfollows recientes
    private var recentUnfollows: Set<String> = []
    private var lastUnfollowTime: [String: Date] = [:]

    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        if userIds.isEmpty {
            completion([])
            return
        }

        let batchSize = 10
        var allUsers: [AppUser] = []
        let batches = stride(from: 0, to: userIds.count, by: batchSize).map {
            Array(userIds[$0..<min($0 + batchSize, userIds.count)])
        }

        let batchGroup = DispatchGroup()

        for batch in batches {
            batchGroup.enter()
            firestoreService.fetchUsers(userIds: batch) { result in
                defer { batchGroup.leave() }
                switch result {
                case .success(let users):
                    allUsers.append(contentsOf: users)
                case .failure(_):
                    break
                }
            }
        }

        batchGroup.notify(queue: .main) {
            completion(allUsers)
        }
    }

    func fetchProfile(userId: String) {
        self.isLoading = true
        self.errorMessage = nil

        self.firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                self.userProfile = profile
                self.profileImagePath = profile.profileImagePath

                self.fetchConnections(userId: userId)
                self.fetchVisits(userId: userId)
                self.fetchMoments(userId: userId)
                
            case .failure(let error):
                self.errorMessage = "Error al cargar el perfil: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Fetch conexiones con verificación directa
    private func fetchConnections(userId: String) {
        
        // Primero obtener following directamente de Firestore
        firestoreService.db.collection("users").document(userId).collection("following")
            .getDocuments { [weak self] followingSnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = "Error al cargar conexiones: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                
                let followingIds = followingSnapshot?.documents.compactMap { doc in
                    doc.data()["userId"] as? String
                } ?? []
                
                
                // Filtrar unfollows recientes
                let filteredFollowingIds = followingIds.filter { userId in
                    if let unfollowTime = self.lastUnfollowTime[userId] {
                        // Si el unfollow fue hace menos de 5 segundos, no incluir
                        let timeSinceUnfollow = Date().timeIntervalSince(unfollowTime)
                        if timeSinceUnfollow < 5.0 {
                            return false
                        } else {
                            // Limpiar el cache después de 5 segundos
                            self.lastUnfollowTime.removeValue(forKey: userId)
                            self.recentUnfollows.remove(userId)
                        }
                    }
                    return true
                }
                
                
                // Luego obtener followers
                self.firestoreService.db.collection("users").document(userId).collection("followers")
                    .getDocuments { [weak self] followersSnapshot, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            self.errorMessage = "Error al cargar admiradores: \(error.localizedDescription)"
                            self.isLoading = false
                            return
                        }
                        
                        let followerIds = followersSnapshot?.documents.compactMap { doc in
                            doc.data()["userId"] as? String
                        } ?? []
                        
                        
                        // Categorizar conexiones con IDs filtrados
                        self.categorizeConnections(
                            followingIds: filteredFollowingIds,
                            followerIds: followerIds
                        )
                    }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Categorizar conexiones
    private func categorizeConnections(followingIds: [String], followerIds: [String]) {
        let followingSet = Set(followingIds)
        let followersSet = Set(followerIds)
        
        let mutualIds = followingSet.intersection(followersSet)
        let connectionIds = followingSet.subtracting(mutualIds)
        let admirerIds = followersSet.subtracting(mutualIds)
        
        
        let fetchGroup = DispatchGroup()
        
        // Fetch mutuos
        fetchGroup.enter()
        self.fetchUsersInBatches(userIds: Array(mutualIds)) { [weak self] users in
            DispatchQueue.main.async {
                self?.mutualConnections = users
            }
            fetchGroup.leave()
        }
        
        // Fetch conexiones
        fetchGroup.enter()
        self.fetchUsersInBatches(userIds: Array(connectionIds)) { [weak self] users in
            DispatchQueue.main.async {
                self?.connections = users
            }
            fetchGroup.leave()
        }
        
        // Fetch admiradores
        fetchGroup.enter()
        self.fetchUsersInBatches(userIds: Array(admirerIds)) { [weak self] users in
            DispatchQueue.main.async {
                self?.admirers = users
                self?.isLoading = false
            }
            fetchGroup.leave()
        }
    }
    
    // ✅ FUNCIÓN EXISTENTE: Fetch visitas
    private func fetchVisits(userId: String) {
        firestoreService.fetchVisits(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let visits):
                let visitorIds = visits.map { $0.visitorId }
                self.fetchUsersInBatches(userIds: visitorIds) { users in
                    DispatchQueue.main.async {
                        self.visits = users
                        
                        // Actualizar timestamps
                        var timestamps: [String: [Date]] = [:]
                        for visit in visits {
                            if timestamps[visit.visitorId] == nil {
                                timestamps[visit.visitorId] = []
                            }
                            timestamps[visit.visitorId]?.append(visit.timestamp)
                        }
                        self.visitTimestamps = timestamps
                    }
                }
            case .failure(let error):
                self.errorMessage = "Error al cargar visitas: \(error.localizedDescription)"
            }
        }
    }
    
    // ✅ FUNCIÓN EXISTENTE: Fetch momentos
    private func fetchMoments(userId: String) {
        firestoreService.fetchMoments(for: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let moments):
                DispatchQueue.main.async {
                    self.moments = moments
                }
            case .failure(let error):
                self.errorMessage = "Error al cargar momentos: \(error.localizedDescription)"
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Refresh con delay para Firestore
    func refreshProfile() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }
        
        guard !isRefreshing && !isLoading else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isRefreshing = true
        }
        
        errorMessage = nil
        
        // ✅ DELAY MÍNIMO para que Firestore procese cambios recientes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.performRefresh(userId: userId)
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Perform refresh real
    private func performRefresh(userId: String) {
        let refreshGroup = DispatchGroup()
        var hasErrors = false
        
        // 1. Refresh perfil principal
        refreshGroup.enter()
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            switch result {
            case .success(let profile):
                DispatchQueue.main.async {
                    self?.userProfile = profile
                    self?.profileImagePath = profile.profileImagePath
                }
            case .failure(let error):
                hasErrors = true
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al actualizar perfil: \(error.localizedDescription)"
                }
            }
            refreshGroup.leave()
        }
        
        // 2. Refresh conexiones con verificación directa
        refreshGroup.enter()
        self.fetchConnections(userId: userId)
        
        // Simular que terminó (ya que fetchConnections maneja su propio completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshGroup.leave()
        }
        
        // 3. Refresh visitas
        refreshGroup.enter()
        self.fetchVisits(userId: userId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshGroup.leave()
        }
        
        // 4. Refresh momentos
        refreshGroup.enter()
        self.fetchMoments(userId: userId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshGroup.leave()
        }
        
        // Cuando terminen todas las operaciones
        refreshGroup.notify(queue: .main) {
            withAnimation(.easeInOut(duration: 0.4)) {
                self.isRefreshing = false
            }
            
            if !hasErrors {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Follow user
    func followUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        
        // Limpiar unfollow reciente si existe
        recentUnfollows.remove(userId)
        lastUnfollowTime.removeValue(forKey: userId)

        self.firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = "Error al seguir usuario: \(error.localizedDescription)"
                return
            }
            

            // Actualizar UI inmediatamente
            DispatchQueue.main.async {
                if let admirerIndex = self.admirers.firstIndex(where: { $0.id == userId }) {
                    let user = self.admirers[admirerIndex]
                    self.admirers.remove(at: admirerIndex)
                    self.mutualConnections.append(user)
                } else {
                    // Obtener usuario y agregarlo a conexiones
                    self.firestoreService.fetchUser(userId: userId) { [weak self] result in
                        switch result {
                        case .success(let user):
                            DispatchQueue.main.async {
                                self?.connections.append(user)
                            }
                        case .failure(let error):
                            self?.errorMessage = "Error al actualizar conexiones: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    // ✅ FUNCIÓN CORREGIDA: Unfollow user
    func unfollowUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado."
            return
        }

        
        // ✅ MARCAR COMO UNFOLLOW RECIENTE
        recentUnfollows.insert(userId)
        lastUnfollowTime[userId] = Date()

        self.firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = "Error al dejar de seguir usuario: \(error.localizedDescription)"
                
                // Limpiar cache de unfollow si falló
                self.recentUnfollows.remove(userId)
                self.lastUnfollowTime.removeValue(forKey: userId)
                return
            }
            

            // Actualizar UI inmediatamente
            DispatchQueue.main.async {
                if let mutualIndex = self.mutualConnections.firstIndex(where: { $0.id == userId }) {
                    let user = self.mutualConnections[mutualIndex]
                    self.mutualConnections.remove(at: mutualIndex)
                    self.admirers.append(user)
                } else if let connectionIndex = self.connections.firstIndex(where: { $0.id == userId }) {
                    self.connections.remove(at: connectionIndex)
                }
            }
        }
    }

    // ✅ NUEVA FUNCIÓN: Verificar estado de seguimiento real
    func verifyFollowingStatus(userId: String, completion: @escaping (Bool) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: userId) { isFollowing in
            completion(isFollowing)
        }
    }

    // ✅ FUNCIÓN EXISTENTE: Upload profile picture (sin cambios)
    func uploadProfilePicture(item: PhotosPickerItem) {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    DispatchQueue.main.async {
                        self.errorMessage = NSLocalizedString("profile.error.loadingImage", comment: "Error loading image")
                    }
                    return
                }

                self.storageService.uploadProfileImage(userId: userId, image: uiImage) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let path):
                        self.firestoreService.updateProfilePicture(userId: userId, profileImagePath: path) { error in
                            if let error = error {
                                DispatchQueue.main.async {
                                    self.errorMessage = "Error al actualizar la foto de perfil: \(error.localizedDescription)"
                                }
                            } else {
                                self.fetchProfile(userId: userId)
                                DispatchQueue.main.async {
                                    self.errorMessage = nil
                                }
                            }
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.errorMessage = "Error al subir la imagen: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error al cargar la imagen: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func refreshAfterMomentChange() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Recargar solo los momentos
        fetchMoments(userId: userId)
    }

    // ✅ FUNCIÓN PARA ELIMINAR MOMENTO DE LA UI INMEDIATAMENTE
    func removeMomentFromUI(momentId: String) {
        DispatchQueue.main.async {
            self.moments.removeAll { $0.id == momentId }
        }
    }

    // ✅ FUNCIÓN EXISTENTE: Update bio (sin cambios)
    func updateBio(newBio: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        self.firestoreService.updateBio(userId: userId, bio: newBio) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Error al actualizar la bio: \(error.localizedDescription)"
                }
            } else {
                self.fetchProfile(userId: userId)
                DispatchQueue.main.async {
                    self.errorMessage = nil
                }
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(selectedTab: .constant(4))
            .environmentObject(AuthService())
    }
}
