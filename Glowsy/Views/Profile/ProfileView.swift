import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore // ✅ NUEVO: Para fetchTaggedMoments
import WidgetKit
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
    static let accent = Color(hex: "007AFF")
    static let purple = Color(hex: "9B59B6")
    static let blue = Color(hex: "6B73FF")
}

// MARK: - ✅ NUEVO: Enum para tabs del perfil
enum ProfileTabType: String, CaseIterable {
    case moments = "Moments"
    case saved = "Guardados"
    case tagged = "Etiquetas" // ✅ NUEVO
    
    var icon: String {
        switch self {
        case .moments: return "square.grid.2x2"
        case .saved: return "bookmark"
        case .tagged: return "person.crop.rectangle" // ✅ NUEVO
        }
    }
    
    var localizedTitle: String {
        switch self {
        case .moments: return NSLocalizedString("profile.tab.moments", comment: "Moments tab")
        case .saved: return NSLocalizedString("profile.tab.saved", comment: "Saved tab")
        case .tagged: return NSLocalizedString("profile.tab.tagged", comment: "Tagged tab") // ✅ NUEVO
        }
    }
}

// MARK: - ✅ NUEVO: Pill Tabs Component
struct ProfilePillTabs: View {
    @Binding var selectedTab: ProfileTabType
    @Environment(\.colorScheme) var colorScheme
    @State private var transientOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .overlay(
                        Capsule()
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
                    )

                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.055 : 0.035))
                    .frame(width: segmentWidth(for: proxy.size.width), height: 34)
                    .liquidGlass(in: Capsule(), interactive: true)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 7, x: 0, y: 2)
                    .offset(x: pillOffset(for: proxy.size.width))

                HStack(spacing: 0) {
                    ForEach(Array(ProfileTabType.allCases.enumerated()), id: \.element) { index, tab in
                        Button(action: {
                            if tab != selectedTab {
                                HapticManager.shared.selection()
                            }
                            withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
                                selectedTab = tab
                                transientOffset = 0
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13, weight: .medium))

                                Text(tab.localizedTitle)
                                    .font(.custom("Poppins-Medium", size: 13))
                            }
                            .foregroundColor(labelColor(for: index, width: proxy.size.width))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 3)
                .animation(.smooth(duration: 0.18, extraBounce: 0.01), value: visualIndex(for: proxy.size.width))

                Capsule()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Capsule())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    transientOffset = constrainedTranslation(value.translation.width, width: proxy.size.width)
                                }
                            }
                            .onEnded { value in
                                settleSelection(translation: value.translation.width, locationX: value.location.x, width: proxy.size.width)
                            }
                    )
            }
        }
        .frame(height: 42)
    }

    private var currentIndex: Int {
        ProfileTabType.allCases.firstIndex(of: selectedTab) ?? 0
    }

    private func segmentWidth(for totalWidth: CGFloat) -> CGFloat {
        let innerWidth = totalWidth - 6
        return innerWidth / CGFloat(ProfileTabType.allCases.count)
    }

    private func baseOffset(for totalWidth: CGFloat) -> CGFloat {
        let segmentWidth = segmentWidth(for: totalWidth)
        let start = -((CGFloat(ProfileTabType.allCases.count - 1) * segmentWidth) / 2)
        return start + (CGFloat(currentIndex) * segmentWidth)
    }

    private func pillOffset(for totalWidth: CGFloat) -> CGFloat {
        baseOffset(for: totalWidth) + transientOffset
    }

    private func visualIndex(for totalWidth: CGFloat) -> Int {
        let width = segmentWidth(for: totalWidth)
        let start = -((CGFloat(ProfileTabType.allCases.count - 1) * width) / 2)
        let raw = ((pillOffset(for: totalWidth) - start) / width).rounded()
        return min(max(Int(raw), 0), ProfileTabType.allCases.count - 1)
    }

    private func labelColor(for index: Int, width: CGFloat) -> Color {
        visualIndex(for: width) == index ? ProfileColors.textPrimary : ProfileColors.textSecondary
    }

    private func constrainedTranslation(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let segment = segmentWidth(for: width)
        let minOffset = -((CGFloat(ProfileTabType.allCases.count - 1) * segment) / 2)
        let maxOffset = ((CGFloat(ProfileTabType.allCases.count - 1) * segment) / 2)
        let proposed = baseOffset(for: width) + translation
        let clamped = min(max(proposed, minOffset), maxOffset)
        return clamped - baseOffset(for: width)
    }

    private func settleSelection(translation: CGFloat, locationX: CGFloat, width: CGFloat) {
        let segment = segmentWidth(for: width)
        let rawIndex = Int((locationX / segment).clamped(to: 0...(CGFloat(ProfileTabType.allCases.count) - 0.001)))
        let threshold = min(segment * 0.28, 36)
        let targetIndex: Int

        if abs(translation) > threshold {
            let direction = translation > 0 ? 1 : -1
            targetIndex = min(max(currentIndex + direction, 0), ProfileTabType.allCases.count - 1)
        } else {
            targetIndex = min(max(rawIndex, 0), ProfileTabType.allCases.count - 1)
        }

        let targetTab = ProfileTabType.allCases[targetIndex]
        if targetTab != selectedTab {
            HapticManager.shared.selection()
        }

        withAnimation(.smooth(duration: 0.18, extraBounce: 0.01)) {
            selectedTab = targetTab
            transientOffset = 0
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
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
    @State private var scrollOffset: CGFloat = 0
    @State private var showMomentDetail = false
    @State private var selectedMomentIndex = 0
    @State private var showingReportSheet = false
    @State private var showingBlockConfirmation = false
    @State private var showingThemeSelector = false // ✅ NUEVO: Estado para selector de tema
    // ✅ NUEVO: Estado para código QR
    @State private var isShowingQRCode = false
    @State private var selectedProfileTab: ProfileTabType = .moments  // ✅ NUEVO: Tab selector
    @State private var showProfileImageFullscreen = false // ✅ NUEVO: Estado para ver foto grande
    @State private var selectedExternalProfileUserId: String? = nil
    @State private var showExternalProfile = false
    

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
            case .admirers: return NSLocalizedString("profile.ui.followers", comment: "Followers")
            case .connections: return NSLocalizedString("profile.ui.following", comment: "Following")
            case .mutualConnections: return NSLocalizedString("profile.ui.mutuals", comment: "Mutuals")
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
                        selectedPhoto: $selectedPhoto,
                        scrollOffset: $scrollOffset,
                        showMomentDetail: $showMomentDetail,
                        selectedMomentIndex: $selectedMomentIndex,
                        showingThemeSelector: $showingThemeSelector,
                        selectedProfileTab: $selectedProfileTab,  // ✅ NUEVO
                        showingQRCode: $isShowingQRCode, // ✅ NUEVO: Binding
                        showProfileImageFullscreen: $showProfileImageFullscreen // ✅ NUEVO
                    )

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
                        onSave: { photo, bio, website, interests in
                            if let photo = photo {
                                viewModel.uploadProfilePicture(item: photo)
                            }
                            viewModel.updateProfileDetails(bio: bio, websiteUrl: website, interests: interests)
                        }
                    )
                }
                .sheet(isPresented: $showingThemeSelector) {
                    if let currentUser = authService.currentUser {
                        ProfileThemeSelector(user: currentUser)
                    }
                }
                .sheet(isPresented: $isShowingQRCode) {
                    QRCodeView()
                }
                .sheet(isPresented: $showProfileImageFullscreen) {
                    if let profileImagePath = viewModel.userProfile?.profileImagePath {
                        ProfileImageViewer(
                            profileImagePath: profileImagePath,
                            username: viewModel.userProfile?.username ?? "Yo"
                        )
                        .presentationDetents([.fraction(0.99)])
                        .presentationDragIndicator(.hidden)
                        .presentationBackground(.clear)
                    }
                }
                
                .fullScreenCover(isPresented: $showMomentDetail) {
                    ModernMomentDetailView(
                        moments: selectedProfileTab == .tagged ? viewModel.taggedMoments : viewModel.moments,
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
                            .presentationDragIndicator(.visible)
                            .interactiveDismissDisabled(false)
                            .presentationBackground(.clear)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                    case .admirers, .connections, .mutualConnections:
                        UserListView(
                            title: listType.title,
                            users: usersForList(type: listType),
                            visitTimestamps: [:],
                            viewModel: viewModel,
                            onDismiss: { showingUserList = nil },
                            rowAction: rowAction(for: listType),
                            onUserTap: { user in
                                openUserProfileFromList(userId: user.id)
                            }
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .interactiveDismissDisabled(false)
                        .presentationBackground(.clear)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .fullScreenCover(isPresented: $showExternalProfile, onDismiss: {
                    selectedExternalProfileUserId = nil
                }) {
                    if let userId = selectedExternalProfileUserId {
                        UserProfileView(userId: userId)
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
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowProfileVisits"))) { _ in
                    showingUserList = .visits
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

    private func rowAction(for type: UserListType) -> UserListRowAction {
        switch type {
        case .visits, .admirers:
            return .follow
        case .connections, .mutualConnections:
            return .unfollow
        }
    }

    private func openUserProfileFromList(userId: String) {
        showingUserList = nil
        selectedExternalProfileUserId = userId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showExternalProfile = true
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
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var scrollOffset: CGFloat
    @Binding var showMomentDetail: Bool
    @Binding var selectedMomentIndex: Int
    @Binding var showingThemeSelector: Bool
    @Binding var selectedProfileTab: ProfileTabType  // ✅ NUEVO: Tab selector
    @Binding var showingQRCode: Bool // ✅ NUEVO: Binding para QR
    @Binding var showProfileImageFullscreen: Bool // ✅ NUEVO
    @StateObject private var savedMomentsViewModel = SavedMomentsViewModel()  // ✅ NUEVO: Guardados
    @State private var showingFullInfo = false // ✅ NUEVO: Para expandir intereses dentro del bloque social

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
                            showingThemeSelector: $showingThemeSelector,
                            showingQRCode: $showingQRCode,
                            showProfileImageFullscreen: $showProfileImageFullscreen

                        )
                        .padding(.top, safeAreaTop + 6)
                        .padding(.bottom, 8)
                        
                        ProfileOverviewCard(
                            viewModel: viewModel,
                            showingUserList: $showingUserList,
                            showingInterests: $showingFullInfo,
                            interests: viewModel.userProfile?.interests ?? []
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                        // ✅ NUEVO: Destacadas Compactas (Después del bloque social)
                        ProfileHighlightsView(
                            userId: viewModel.userProfile?.id ?? "",
                            isOwnProfile: viewModel.userProfile?.id == Auth.auth().currentUser?.uid,
                            isCompact: true
                        )
                        .padding(.bottom, 14)
                        
                        if viewModel.isRefreshing {
                            ModernRefreshIndicator()
                                .padding(.bottom, 10)
                        }

                        
                        VStack(spacing: 0) {
                            // ✅ NUEVO: Pill Tabs para cambiar entre Moments y Guardados
                            ProfilePillTabs(selectedTab: $selectedProfileTab)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .frame(maxWidth: UIScreen.main.bounds.width)
                            
                            // ✅ NUEVO: Contenido basado en el tab seleccionado
                            switch selectedProfileTab {
                            case .moments:
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
                                            ForEach(Array(viewModel.moments.enumerated()), id: \.offset) { index, moment in
                                                ScreenshotProtectedView(
                                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                                ) {
                                                    ModernMomentThumbnail(
                                                        moment: moment,
                                                        size: itemWidth,
                                                        customListNamesById: viewModel.customListNamesById,
                                                        onTap: {
                                                            selectedMomentIndex = index
                                                            showMomentDetail = true
                                                        }
                                                    )
                                                }
                                                .contextMenu {
                                                    Button {
                                                        if let momentId = moment.id {
                                                            FirestoreService.shared.archiveMoment(userId: moment.authorId, momentId: momentId) { _ in
                                                                viewModel.moments.removeAll { $0.id == momentId }
                                                            }
                                                        }
                                                    } label: {
                                                        Label(NSLocalizedString("contextMenu.archiveMoment", comment: "Archive"), systemImage: "archivebox")
                                                    }

                                                    Button {
                                                        // Abrir edición: reutilizar el mismo flujo que el menú contextual
                                                        NotificationCenter.default.post(
                                                            name: NSNotification.Name("EditMoment"),
                                                            object: moment
                                                        )
                                                    } label: {
                                                        Label(NSLocalizedString("contextMenu.editMoment", comment: "Edit"), systemImage: "pencil")
                                                    }

                                                    Button(role: .destructive) {
                                                        if let momentId = moment.id {
                                                            FirestoreService.shared.deleteMoment(userId: moment.authorId, momentId: momentId) { _ in
                                                                viewModel.moments.removeAll { $0.id == momentId }
                                                                LocalPersistenceService.shared.deleteMoment(momentId: momentId)
                                                            }
                                                        }
                                                    } label: {
                                                        Label(NSLocalizedString("contextMenu.deleteMoment", comment: "Delete"), systemImage: "trash")
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                    }
                                    .frame(height: calculateGridHeight(itemCount: viewModel.moments.count))
                                }
                                
                            case .saved:
                                // ✅ NUEVO: Contenido real de guardados
                                ProfileSavedContent(
                                    viewModel: savedMomentsViewModel
                                )
                                .onAppear {
                                    if savedMomentsViewModel.moments.isEmpty && !savedMomentsViewModel.isLoading {
                                        savedMomentsViewModel.loadSavedMoments()
                                    }
                                }
                            
                            case .tagged:
                                // ✅ NUEVO: Contenido de momentos donde has sido etiquetado
                                Group {
                                    if viewModel.isLoadingTagged {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(height: 400)
                                    } else if viewModel.taggedMoments.isEmpty {
                                        ProfileSectionEmptyState(
                                            icon: "person.crop.rectangle",
                                            titleKey: "profile.tagged.empty.title",
                                            subtitleKey: "profile.tagged.empty.description"
                                        )
                                        .frame(height: 400, alignment: .top)
                                    } else {
                                        LazyVGrid(columns: [
                                            GridItem(.flexible(), spacing: 4),
                                            GridItem(.flexible(), spacing: 4),
                                            GridItem(.flexible(), spacing: 4)
                                        ], spacing: 4) {
                                            ForEach(Array(viewModel.taggedMoments.enumerated()), id: \.element.id) { index, moment in
                                                ScreenshotProtectedView(
                                                    isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                                ) {
                                                    Button(action: {
                                                        selectedMomentIndex = index
                                                        showMomentDetail = true
                                                    }) {
                                                        if let imagePath = moment.imagePath, let url = URL(string: imagePath) {
                                                            AsyncImage(url: url) { image in
                                                                image
                                                                    .resizable()
                                                                    .aspectRatio(contentMode: .fill)
                                                            } placeholder: {
                                                                Rectangle()
                                                                    .fill(Color.gray.opacity(0.3))
                                                            }
                                                            .frame(width: (UIScreen.main.bounds.width - 16) / 3, height: (UIScreen.main.bounds.width - 16) / 3)
                                                            .clipped()
                                                            .cornerRadius(4)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(height: calculateGridHeight(itemCount: viewModel.taggedMoments.count))
                                    }
                                }
                                .onAppear {
                                    if viewModel.taggedMoments.isEmpty && !viewModel.isLoadingTagged,
                                       let userId = viewModel.userProfile?.id {
                                        viewModel.fetchTaggedMoments(userId: userId)
                                    }
                                }
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
                        var savedRefreshCompleted = true

                        viewModel.refreshProfile()

                        if selectedProfileTab == .saved {
                            savedRefreshCompleted = false
                            savedMomentsViewModel.loadSavedMoments { _ in
                                savedRefreshCompleted = true
                            }
                        }
                        
                        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            if !viewModel.isRefreshing && savedRefreshCompleted {
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
                    .frame(width: 32, height: 32)
                
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
        .clipShape(Capsule())
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
    @Binding var showingThemeSelector: Bool
    @Binding var showingQRCode: Bool
    @Binding var showProfileImageFullscreen: Bool // ✅ NUEVO

    @Environment(\.colorScheme) var colorScheme
    
    private var storyCount: Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }
        return storyViewModel.stories[userId]?.count ?? 0
    }
    
    private var storyViewedStatus: [Bool] {
        guard let userId = Auth.auth().currentUser?.uid,
              let userStories = storyViewModel.stories[userId] else {
            return []
        }
        
        // Para historias propias, siempre están "vistas" (iluminadas)
        return userStories.map { _ in true }
    }

    private var storyAudiences: [String?] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        return storyViewModel.stories[userId]?.map { $0.audience } ?? []
    }
    
    private var isOwnStory: Bool {
        return true // Siempre es el perfil propio
    }

    var body: some View {
        VStack(spacing: 18) {
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
                    .frame(width: 124, height: 124)
                    .blur(radius: 12)
                
                // Avatar principal
                Group {
                    if let profileImagePath = viewModel.userProfile?.profileImagePath, let url = URL(string: profileImagePath) {
                        KFImage(url)
                            .placeholder {
                                Circle()
                                    .fill(ProfileColors.materialBackground)
                                    .frame(width: 96, height: 96)
                                    .overlay(
                                        ProgressView()
                                            .tint(ProfileColors.accent)
                                            .scaleEffect(1.2)
                                    )
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .contentShape(Circle())
                    } else {
                        // Placeholder cuando no hay imagen
                        Circle()
                            .fill(ProfileColors.materialBackground)
                            .frame(width: 96, height: 96)
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
                            .frame(width: 32, height: 32)
                        
                        Text(primaryBadge.emoji)
                            .font(.system(size: 16))
                    }
                    .offset(x: 38, y: -38)
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
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "FFD700"))
                    }
                    .offset(x: -38, y: -38)
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
                    // ✅ Si no hay historia, mostrar foto en grande
                    showProfileImageFullscreen = true
                }
            }
            
            // Información del usuario adaptativa
            VStack(spacing: 8) {
                VStack(spacing: 6) {
                    VerifiedUsernameGradientView(
                        username: viewModel.userProfile?.username ?? "Usuario",
                        isVerified: viewModel.userProfile?.isVerified ?? false,
                        badgeSize: 20,
                        spacing: 6,
                        gradient: LinearGradient(
                            colors: [Color(hex: "007AFF"), Color(hex: "6B73FF")], // ✅ MISMO GRADIENTE QUE USERPROFILEVIEW
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.custom("Poppins-Bold", size: 24))
                    
                    // Badges horizontales adaptativos
                    if let currentUser = authService.currentUser,
                       (currentUser.isPlusSubscriber || currentUser.isSupporter) {
                        HStack(spacing: 6) {
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
                VStack(spacing: 6) {
                    ExpandableBioView(bio: viewModel.userProfile?.bio ?? "Añade una biografía")
                    
                    // ✅ NUEVO: Link in Bio
                    if let websiteUrl = viewModel.userProfile?.websiteUrl, !websiteUrl.isEmpty, 
                       let url = URL(string: websiteUrl.hasPrefix("http") ? websiteUrl : "https://\(websiteUrl)") {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .semibold))
                                
                                Text(websiteUrl.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                                    .font(.custom("Poppins-Medium", size: 13))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .foregroundColor(Color(hex: "007AFF")) // Color acento
                            .padding(.vertical, 4)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            
            // Botones de acción adaptativos
            HStack(spacing: 14) {
                Button(action: {
                    newBio = viewModel.userProfile?.bio ?? ""
                    isShowingEditProfile = true
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 15))
                        Text("profile.editButton")
                            .font(.custom("Poppins-SemiBold", size: 13))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .liquidGlass(in: Capsule(), interactive: true)
                }
                
                // ✅ NUEVO: Botón de compartir perfil (QR)
                Button(action: {
                    showingQRCode = true
                }) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ProfileColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .liquidGlass(in: Circle(), interactive: true)
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
                        .frame(width: 40, height: 40)
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
        }
        .padding(.horizontal, 24)
    }
    // Border inteligente del avatar adaptativo (SIN BORDE VERDE)
    @ViewBuilder
    private func avatarBorderOverlay() -> some View {
        let currentUser = authService.currentUser
        
        if storyViewModel.hasActiveStory {
            StorySegmentedRing(
                storyCount: storyCount,
                hasStory: storyViewModel.hasActiveStory,
                hasUnseenStory: false, // Propias siempre iluminadas
                storyViewedStatus: storyViewedStatus,
                storyAudiences: storyAudiences,
                isOwnStory: isOwnStory,
                colorScheme: colorScheme,
                ringSize: 96,
                lineWidth: 3
            )
        } else if currentUser?.isPlusSubscriber == true && currentUser?.showPlusBadge == true {
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        }
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
        .shadow(color: badge.swiftUIColors.first?.opacity(0.3) ?? .clear, radius: 3, x: 0, y: 1)
    }
}


struct ProfileOverviewCard: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var showingUserList: ProfileView.UserListType?
    @Binding var showingInterests: Bool
    let interests: [String]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ModernStatsSection(
                viewModel: viewModel,
                showingUserList: $showingUserList,
                embeddedStyle: true
            )

            if !interests.isEmpty {
                Divider()
                    .overlay(ProfileColors.borderColor.opacity(colorScheme == .dark ? 0.22 : 0.4))
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showingInterests.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("profile.interests.title")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(ProfileColors.textPrimary)

                        Text("\(interests.count)")
                            .font(.custom("Poppins-Medium", size: 11))
                            .foregroundColor(ProfileColors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ProfileColors.materialBackground.opacity(0.7))
                            .clipShape(Capsule())

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ProfileColors.textSecondary)
                            .rotationEffect(.degrees(showingInterests ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }

                if showingInterests {
                    ModernInterestsView(
                        interests: interests,
                        showsTitle: false,
                        embeddedStyle: true
                    )
                    .padding(.top, 12)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sección de estadísticas moderna (ARREGLADA)
struct ModernStatsSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var showingUserList: ProfileView.UserListType?
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    private var computedStats: [(String, Int, ProfileView.UserListType)] {
        [
            (NSLocalizedString("profile.stats.visits", comment: "Visits"), viewModel.visits.count, .visits),
            (NSLocalizedString("profile.ui.followers", comment: "Followers"), viewModel.admirers.count, .admirers),
            (NSLocalizedString("profile.ui.following", comment: "Following"), viewModel.connections.count, .connections),
            (NSLocalizedString("profile.ui.mutuals", comment: "Mutuals"), viewModel.mutualConnections.count, .mutualConnections)
        ]
    }

    var body: some View {
        HStack(spacing: embeddedStyle ? 0 : 6) {
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
                    .padding(.vertical, embeddedStyle ? 10 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if embeddedStyle && index < computedStats.count - 1 {
                    Rectangle()
                        .fill(ProfileColors.borderColor.opacity(colorScheme == .dark ? 0.24 : 0.4))
                        .frame(width: 1, height: 30)
                }
            }
        }
        .padding(.horizontal, embeddedStyle ? 2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingUserList)
    }
}

// MARK: - Vista de intereses
struct ModernInterestsView: View {
    let interests: [String]
    var showsTitle: Bool = true
    var embeddedStyle: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle {
                Text("profile.interests.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(ProfileColors.textPrimary)
            }
            
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
                        .padding(.horizontal, embeddedStyle ? 14 : 16)
                        .padding(.vertical, embeddedStyle ? 9 : 10)
                        .background(embeddedStyle ? ProfileColors.materialBackground.opacity(0.62) : ProfileColors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ProfileColors.borderColor.opacity(embeddedStyle ? 0.18 : 0), lineWidth: embeddedStyle ? 1 : 0)
                        )
                        .shadow(color: ProfileColors.shadowColor, radius: embeddedStyle ? 0 : 4, x: 0, y: embeddedStyle ? 0 : 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interestEmoji(for interest: String) -> String {
        return InterestEmojiHelper.emoji(for: interest)
    }
}

// MARK: - Thumbnail de momento moderno (OPTIMIZADO)
// Reemplaza solo el contenido del body en tu ModernMomentThumbnail

struct ModernMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let customListNamesById: [String: String]
    let onTap: (() -> Void)? // ✅ MANTENER: Callback opcional
    @State private var isPressed = false
    
    // ✅ NUEVOS: Estados para thumbnails de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false

    private struct AudienceBadgeStyle {
        let icon: String
        let title: String
        let background: Color
    }

    private var normalizedAudience: String {
        moment.audience?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") ?? "everyone"
    }

    private var audienceBadgeStyle: AudienceBadgeStyle {
        switch normalizedAudience {
        case "bestfriends", "bestfriend":
            return AudienceBadgeStyle(
                icon: "heart.fill",
                title: NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type"),
                background: Color(hex: "24C26A").opacity(0.92)
            )
        case "connections", "connection", "mutuals", "mutual":
            return AudienceBadgeStyle(
                icon: "person.2.fill",
                title: NSLocalizedString("audience.type.connections", comment: "Connections audience type"),
                background: Color(hex: "00B4D8").opacity(0.92)
            )
        case "customlist":
            let listName = moment.customListId.flatMap { customListNamesById[$0] }
            let resolvedName = (listName?.isEmpty == false)
                ? (listName ?? "")
                : NSLocalizedString("audience.type.customList", comment: "Custom list audience type")
            return AudienceBadgeStyle(
                icon: "list.bullet.rectangle",
                title: resolvedName,
                background: Color(hex: "A855F7").opacity(0.92)
            )
        case "custom":
            return AudienceBadgeStyle(
                icon: "person.crop.circle.badge.plus",
                title: NSLocalizedString("audience.type.custom", comment: "Custom audience type"),
                background: Color(hex: "F59E0B").opacity(0.92)
            )
        case "onlyme":
            return AudienceBadgeStyle(
                icon: "lock.fill",
                title: NSLocalizedString("audience.type.onlyMe", comment: "Only me audience type"),
                background: Color.black.opacity(0.78)
            )
        default:
            return AudienceBadgeStyle(
                icon: "globe",
                title: NSLocalizedString("audience.type.everyone", comment: "Everyone audience type"),
                background: Color(hex: "0EA5A3").opacity(0.9)
            )
        }
    }

    var body: some View {
        Button(action: {
            onTap?() // ✅ MANTENER: Ejecutar callback si existe
        }) {
            ZStack(alignment: .bottomTrailing) {
                // ✅ NUEVO: Lógica actualizada para manejar videos y imágenes
                if let mediaItem = moment.primaryVisibleMediaItem, !mediaItem.url.isEmpty {
                    // Es un momento nuevo con mediaItems
                    if mediaItem.type == .video {
                        // ✅ NUEVO: Priorizar thumbnailUrl si existe
                        if let thumbnailUrl = mediaItem.thumbnailUrl, !thumbnailUrl.isEmpty {
                            imageView(imageURL: thumbnailUrl)
                        } else {
                            // Si no hay thumbnail URL (legacy), generar uno
                            videoThumbnailView(videoURL: mediaItem.url)
                        }
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
                                .overlay(ProgressView().tint(Color(hex: "007AFF")))
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

                // ✅ NUEVO: Badge de audiencia en esquina superior izquierda
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            audienceBadgeView

                            // Indicador de publicación programada (solo autor)
                            if moment.isScheduled && moment.authorId == Auth.auth().currentUser?.uid {
                                scheduledBadgeView
                            }
                        }
                        Spacer()
                    }
                    Spacer()
                }
                
                // ✅ NUEVO: Indicador de video
                if let mediaItem = moment.primaryVisibleMediaItem, mediaItem.type == .video {
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
                // ✅ NUEVO: El autor siempre ve el contador, los demás solo si no está oculto
                if let likeCount = moment.reactions["heart"]?.count, likeCount > 0,
                   (moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts) {
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

    @ViewBuilder
    private var audienceBadgeView: some View {
        let style = audienceBadgeStyle
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            Text(style.title)
                .font(.custom("Poppins-SemiBold", size: 8))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(style.background)
        .clipShape(Capsule())
        .padding(6)
    }

    @ViewBuilder
    private var scheduledBadgeView: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8, weight: .bold))
            Text(moment.scheduledRemainingText)
                .font(.custom("Poppins-Bold", size: 8))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.72))
        .clipShape(Capsule())
        .padding(.horizontal, 6)
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
                                        .tint(Color(hex: "007AFF"))
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
                                    .tint(Color(hex: "007AFF"))
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
        EmptyView()
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
    init(moment: Moment, size: CGFloat, customListNamesById: [String: String] = [:], onTap: (() -> Void)? = nil) {
        self.moment = moment
        self.size = size
        self.customListNamesById = customListNamesById
        self.onTap = onTap
    }
}


// MARK: - Estado vacío para momentos
struct ProfileSectionEmptyState: View {
    let icon: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(ProfileColors.textPrimary.opacity(0.05))
                    .frame(width: 54, height: 54)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(ProfileColors.textSecondary.opacity(0.7))
            }

            VStack(spacing: 6) {
                Text(titleKey)
                    .font(.custom("Poppins-SemiBold", size: 17))
                    .foregroundColor(ProfileColors.textPrimary)

                Text(subtitleKey)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Estado vacío para momentos
struct ModernEmptyMomentsView: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "camera",
            titleKey: "profile.moments.empty.title",
            subtitleKey: "profile.moments.empty.subtitle"
        )
    }
}

// MARK: - ✅ NUEVO: Placeholder para Guardados
struct ProfileSavedPlaceholder: View {
    var body: some View {
        ProfileSectionEmptyState(
            icon: "bookmark",
            titleKey: LocalizedStringKey("profile.saved.empty.title"),
            subtitleKey: LocalizedStringKey("profile.saved.empty.subtitle")
        )
    }
}

// MARK: - ✅ NUEVO: Contenido real de guardados en perfil
struct ProfileSavedContent: View {
    @ObservedObject var viewModel: SavedMomentsViewModel
    @State private var showingSavedMomentDetail = false
    @State private var selectedSavedMomentIndex = 0
    @State private var showingSavedManager = false
    @State private var selectedFilter: SavedQuickFilter = .all
    @State private var detailMoments: [Moment] = []
    @Environment(\.colorScheme) var colorScheme
    @State private var showingRestrictedRemoveAlert = false
    @State private var restrictedMomentToRemove: Moment?
    
    enum SavedQuickFilter: CaseIterable {
        case all
        case videos
        case text
        case location
        
        var title: String {
            switch self {
            case .all:
                return NSLocalizedString("profile.saved.filter.all", comment: "All saved filter")
            case .videos:
                return NSLocalizedString("profile.saved.filter.videos", comment: "Videos saved filter")
            case .text:
                return NSLocalizedString("profile.saved.filter.text", comment: "Text saved filter")
            case .location:
                return NSLocalizedString("profile.saved.filter.location", comment: "Location saved filter")
            }
        }
        
        func matches(_ moment: Moment) -> Bool {
            switch self {
            case .all:
                return true
            case .videos:
                if let firstMedia = moment.primaryVisibleMediaItem {
                    return firstMedia.type == .video
                }
                return moment.videoUrl != nil
            case .text:
                return !moment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .location:
                return !(moment.location ?? "").isEmpty
            }
        }
    }
    
    private var filteredMoments: [Moment] {
        viewModel.moments.filter { selectedFilter.matches($0) }
    }
    
    private var previewMoments: [Moment] {
        Array(filteredMoments.prefix(12))
    }
    
    private var recentMoments: [Moment] {
        Array(viewModel.moments.sorted { $0.timestamp > $1.timestamp }.prefix(8))
    }
    
    private var gridSpacing: CGFloat { 4 }
    
    private var gridItemSize: CGFloat {
        // 20 + 20 outer padding, then 8 + 8 inner grid padding.
        let availableWidth = UIScreen.main.bounds.width - 56
        return max(88, (availableWidth - (gridSpacing * 2)) / 3)
    }
    
    var body: some View {
        if viewModel.isLoading {
            // Estado de carga
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(NSLocalizedString("profile.saved.loading", comment: "Loading saved"))
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(ProfileColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else if viewModel.moments.isEmpty {
            // Estado vacío
            ProfileSavedPlaceholder()
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(SavedQuickFilter.allCases, id: \.self) { filter in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedFilter = filter
                                }
                            }) {
                                Text(filter.title)
                                    .font(.custom("Poppins-Medium", size: 12))
                                    .foregroundColor(selectedFilter == filter ? ProfileColors.textPrimary : ProfileColors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Color.clear.liquidGlass(
                                            in: Capsule(),
                                            interactive: true
                                        )
                                        .opacity(selectedFilter == filter ? 1 : 0.78)
                                    )
                            }
                            .scaleEffect(selectedFilter == filter ? 1.0 : 0.985)
                        }
                    }
                    
                    Spacer()

                    Button(action: {
                        showingSavedManager = true
                    }) {
                        HStack(spacing: 6) {
                            Text(NSLocalizedString("profile.saved.openAll", comment: "Open all saved"))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.custom("Poppins-SemiBold", size: 12))
                        .foregroundColor(ProfileColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
                    }
                }
                .padding(.horizontal, 20)
                
                if previewMoments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 30))
                            .foregroundColor(ProfileColors.textSecondary)
                        Text(NSLocalizedString("profile.saved.filtered.empty", comment: "No saved moments for selected filter"))
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(ProfileColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 20)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(gridItemSize), spacing: gridSpacing), count: 3),
                        spacing: gridSpacing
                    ) {
                        ForEach(Array(previewMoments.enumerated()), id: \.offset) { index, moment in
                            ScreenshotProtectedView(
                                isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                            ) {
                                ProfileSavedMomentThumbnail(
                                    moment: moment,
                                    size: gridItemSize,
                                    isRestricted: isMomentRestricted(moment),
                                    isMutedRestriction: isMomentRestricted(moment) && isMomentMuted(moment),
                                    onTap: {
                                        handleSavedMomentTap(
                                            moment: moment,
                                            sourceMoments: filteredMoments,
                                            fallbackIndex: index
                                        )
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: calculateSavedGridHeight(itemCount: previewMoments.count))
                }
                
                if !recentMoments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(NSLocalizedString("profile.saved.recent", comment: "Recent saved moments section"))
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(ProfileColors.textPrimary)
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(recentMoments.enumerated()), id: \.offset) { _, moment in
                                    ScreenshotProtectedView(
                                        isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                                    ) {
                                        ProfileSavedMomentThumbnail(
                                            moment: moment,
                                            size: 92,
                                            isRestricted: isMomentRestricted(moment),
                                            isMutedRestriction: isMomentRestricted(moment) && isMomentMuted(moment),
                                            onTap: {
                                                handleSavedMomentTap(
                                                    moment: moment,
                                                    sourceMoments: recentMoments,
                                                    fallbackIndex: 0
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingSavedMomentDetail) {
                ModernSavedMomentsDetailView(
                    moments: detailMoments.isEmpty ? filteredMoments.filter { !isMomentRestricted($0) } : detailMoments,
                    initialIndex: selectedSavedMomentIndex,
                    onDismiss: {
                        showingSavedMomentDetail = false
                    },
                    onRemoveMoment: { moment in
                        if let momentId = moment.id {
                            viewModel.removeMoment(momentId: momentId)
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingSavedManager) {
                SavedMomentsView()
            }
            .alert(NSLocalizedString("savedMoments.remove.title", comment: "Remove from saved"), isPresented: $showingRestrictedRemoveAlert) {
                Button(NSLocalizedString("savedMoments.cancel", comment: "Cancel"), role: .cancel) {
                    restrictedMomentToRemove = nil
                }
                Button(NSLocalizedString("savedMoments.remove.confirm", comment: "Remove"), role: .destructive) {
                    if let moment = restrictedMomentToRemove, let momentId = moment.id {
                        viewModel.removeMoment(momentId: momentId)
                    }
                    restrictedMomentToRemove = nil
                }
            } message: {
                if let moment = restrictedMomentToRemove {
                    if isMomentMuted(moment) {
                        Text(NSLocalizedString("savedMoments.remove.message.muted", comment: "Moment hidden due to muted account"))
                    } else {
                        Text(NSLocalizedString("savedMoments.remove.message.restricted", comment: "This moment is no longer available. Do you want to remove it from your collection?"))
                    }
                } else {
                    Text(NSLocalizedString("savedMoments.remove.message.restricted", comment: "This moment is no longer available. Do you want to remove it from your collection?"))
                }
            }
        }
    }

    private func isMomentRestricted(_ moment: Moment) -> Bool {
        guard let momentId = moment.id else { return true }
        return !(viewModel.visibilityByMomentId[momentId] ?? true)
    }

    private func isMomentMuted(_ moment: Moment) -> Bool {
        viewModel.isMomentFromMutedUser(moment)
    }

    private func handleSavedMomentTap(moment: Moment, sourceMoments: [Moment], fallbackIndex: Int) {
        guard let momentId = moment.id else { return }

        if let canView = viewModel.visibilityByMomentId[momentId], !canView {
            restrictedMomentToRemove = moment
            showingRestrictedRemoveAlert = true
            return
        }

        if viewModel.visibilityByMomentId[momentId] == nil {
            viewModel.refreshVisibilityForMoment(moment) { canView in
                guard canView else {
                    HapticManager.shared.notification(.warning)
                    return
                }
                openSavedDetail(momentId: momentId, sourceMoments: sourceMoments, fallbackIndex: fallbackIndex)
            }
            return
        }

        openSavedDetail(momentId: momentId, sourceMoments: sourceMoments, fallbackIndex: fallbackIndex)
    }

    private func openSavedDetail(momentId: String, sourceMoments: [Moment], fallbackIndex: Int) {
        let accessibleMoments = sourceMoments.filter { candidate in
            guard let candidateId = candidate.id else { return false }
            return viewModel.visibilityByMomentId[candidateId] ?? true
        }

        guard !accessibleMoments.isEmpty else { return }

        detailMoments = accessibleMoments
        selectedSavedMomentIndex = accessibleMoments.firstIndex(where: { $0.id == momentId }) ?? min(fallbackIndex, max(accessibleMoments.count - 1, 0))
        showingSavedMomentDetail = true
    }
    
    private func calculateSavedGridHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let columns = 3
        let rows = ceil(Double(itemCount) / Double(columns))
        return CGFloat(rows) * gridItemSize + (CGFloat(rows - 1) * gridSpacing)
    }
}

// MARK: - Thumbnail para momento guardado
struct ProfileSavedMomentThumbnail: View {
    let moment: Moment
    let size: CGFloat
    let isRestricted: Bool
    let isMutedRestriction: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    // Estados para miniaturas de video
    @State private var videoThumbnail: UIImage?
    @State private var isLoadingVideoThumbnail = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // --- CONTENIDO MEDIA ---
                Group {
                    if let mediaItem = moment.primaryVisibleMediaItem {
                        if mediaItem.type == .video {
                            videoView(videoURL: mediaItem.url, thumbnailURL: mediaItem.thumbnailUrl)
                        } else {
                            imageView(url: mediaItem.url)
                        }
                    } else if let imagePath = moment.imagePath {
                        imageView(url: imagePath)
                    } else if let videoUrl = moment.videoUrl {
                        videoView(videoURL: videoUrl, thumbnailURL: moment.thumbnailUrl)
                    } else {
                        // Momento de texto
                        textMomentView()
                    }
                }
                .blur(radius: isRestricted ? 14 : 0)

                if isRestricted {
                    savedRestrictedOverlay
                }
                
                // --- INDICADORES ---
                
                // Play indicator si es video
                if isVideo && !isRestricted {
                    VStack {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(.black.opacity(0.3)))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                }
                
                if !isRestricted {
                    // Badge de guardado
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(ProfileColors.blue.opacity(0.8)))
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var isVideo: Bool {
        if let firstMedia = moment.primaryVisibleMediaItem {
            return firstMedia.type == .video
        }
        return moment.videoUrl != nil
    }
    
    @ViewBuilder
    private func imageView(url: String) -> some View {
        KFImage(URL(string: url))
            .placeholder {
                Rectangle()
                    .fill(ProfileColors.borderColor.opacity(0.3))
                    .overlay(ProgressView().scaleEffect(0.8))
            }
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipped()
    }
    
    @ViewBuilder
    private func videoView(videoURL: String, thumbnailURL: String?) -> some View {
        ZStack {
            if let thumb = thumbnailURL, let url = URL(string: thumb) {
                // Usar thumbnail del servidor
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else if let generated = videoThumbnail {
                // Usar thumbnail generado localmente
                Image(uiImage: generated)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                // Cargando o fallback
                Rectangle()
                    .fill(ProfileColors.borderColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        VStack(spacing: 4) {
                            if isLoadingVideoThumbnail {
                                ProgressView().scaleEffect(0.6).tint(.white)
                            } else {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    )
                    .onAppear {
                        loadVideoThumbnail(from: videoURL)
                    }
            }
        }
    }
    
    @ViewBuilder
    private func textMomentView() -> some View {
        ZStack {
            LinearGradient(
                colors: [ProfileColors.blue.opacity(0.8), ProfileColors.accent.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Text(moment.content)
                .font(.custom("Poppins-Medium", size: 10))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(6)
        }
        .frame(width: size, height: size)
    }

    private var savedRestrictedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                )
                .frame(width: size, height: size)

            VStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(
                    NSLocalizedString(
                        isMutedRestriction ? "savedMoments.restricted.muted.title" : "savedMoments.restricted.title",
                        comment: "Saved moment restricted title"
                    )
                )
                    .font(.custom("Poppins-SemiBold", size: 9))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(
                    NSLocalizedString(
                        isMutedRestriction ? "savedMoments.restricted.muted.subtitle" : "savedMoments.restricted.subtitle",
                        comment: "Saved moment restricted subtitle"
                    )
                )
                    .font(.custom("Poppins-Regular", size: 8))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
    
    private func loadVideoThumbnail(from urlString: String) {
        guard videoThumbnail == nil, !isLoadingVideoThumbnail, let url = URL(string: urlString) else { return }
        
        isLoadingVideoThumbnail = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: size * 2, height: size * 2)
            
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
                                    // Mejor cálculo: si supera 100 caracteres o tiene más de 2 saltos de línea
                                    needsExpansion = bio.count > 100 || bio.filter { $0 == "\n" }.count > 2
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
                        .padding(.vertical, 4)
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
@MainActor
class ProfileViewModel: ObservableObject, UserListViewModel {
    @Published var userProfile: AppUser?
    @Published var visits: [AppUser] = []
    @Published var visitTimestamps: [String: [Date]] = [:]
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []
    @Published var admirers: [AppUser] = []
    @Published var moments: [Moment] = []
    @Published var customListNamesById: [String: String] = [:]
    @Published var taggedMoments: [Moment] = [] // ✅ NUEVO
    @Published var isLoadingTagged: Bool = false // ✅ NUEVO
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    @Published var profileImagePath: String?
    @Published var isRefreshing: Bool = false

    private let firestoreService = FirestoreService()
    private let storageService = StorageService()
    // ✅ UserDefaults compartido con el widget (App Group "group.com.glowsyapp")
    private let widgetUserDefaults = UserDefaults(suiteName: "group.com.glowsyapp")
    
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
        
        // ✅ SwiftData: Cargar perfil y moments del caché local inmediatamente
        if let cachedProfile = LocalPersistenceService.shared.loadUser(userId: userId) {
            self.userProfile = cachedProfile
            self.profileImagePath = cachedProfile.profileImagePath
            self.isLoading = false // UI instantánea
        }
        
        // ✅ Cargar conexiones del caché
        let cachedConnections = LocalPersistenceService.shared.loadConnections(userId: userId)
        if !cachedConnections.followers.isEmpty || !cachedConnections.following.isEmpty {
            self.categorizeConnections(
                userId: userId,
                followingIds: cachedConnections.following.map { $0.id },
                followerIds: cachedConnections.followers.map { $0.id }
            )
        }
        
        let cachedMoments = LocalPersistenceService.shared.loadProfileMoments(userId: userId)
        if !cachedMoments.isEmpty && self.moments.isEmpty {
            self.moments = cachedMoments
        }

        self.firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let profile):
                self.userProfile = profile
                self.profileImagePath = profile.profileImagePath
                
                // ✅ SwiftData: Guardar perfil en caché local
                Task { @MainActor in
                    LocalPersistenceService.shared.saveUser(profile)
                }

                self.fetchConnections(userId: userId)
                self.fetchVisits(userId: userId)
                self.fetchMoments(userId: userId)
                self.fetchCustomAudienceListNames(userId: userId)
                
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
                            userId: userId,
                            followingIds: filteredFollowingIds,
                            followerIds: followerIds
                        )
                    }
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Categorizar conexiones
    private func categorizeConnections(userId: String, followingIds: [String], followerIds: [String]) {
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
        
        fetchGroup.notify(queue: .main) {
            // ✅ SwiftData: Guardar en caché local
            let allFollowers = self.mutualConnections + self.admirers
            let allFollowing = self.mutualConnections + self.connections
            LocalPersistenceService.shared.saveFollowers(userId: userId, followers: allFollowers)
            LocalPersistenceService.shared.saveFollowing(userId: userId, following: allFollowing)
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
                        
                         // 🔄 Actualizar contador de visitas de hoy para el widget
                         let calendar = Calendar.current
                         let today = calendar.startOfDay(for: Date())
                         let todayCount = visits.filter { visit in
                             let visitDay = calendar.startOfDay(for: visit.timestamp)
                             return visitDay == today
                         }.count
                         
                         self.widgetUserDefaults?.set(todayCount, forKey: "widget_profile_visits_today")
                         WidgetCenter.shared.reloadTimelines(ofKind: "GlowsyWidgetExtension")
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
                    
                    // ✅ SwiftData: Guardar moments del perfil en caché local
                    Task { @MainActor in
                        // Usamos sync: true para purgar momentos eliminados del perfil
                        LocalPersistenceService.shared.saveProfileMoments(moments, userId: userId, sync: true)
                    }
                }
            case .failure(let error):
                self.errorMessage = "Error al cargar momentos: \(error.localizedDescription)"
            }
        }
    }

    private func fetchCustomAudienceListNames(userId: String, completion: (() -> Void)? = nil) {
        firestoreService.fetchCustomLists(for: userId) { [weak self] result in
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

    // ✅ NUEVO: Cargar momentos donde el usuario ha sido etiquetado
    func fetchTaggedMoments(userId: String) {
        isLoadingTagged = true
        
        // Buscar todos los momentos donde el usuario aparece en taggedUsers
        let db = Firestore.firestore()
        db.collectionGroup("moments")
            .whereField("taggedUsers", arrayContains: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments { [weak self] (snapshot: QuerySnapshot?, error: Error?) in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoadingTagged = false
                    
                    if let error = error {
                        print("❌ Error loading tagged moments: \(error)")
                        return
                    }
                    
                    if let documents = snapshot?.documents {
                        self.taggedMoments = documents.compactMap { doc -> Moment? in
                            guard let moment = try? doc.data(as: Moment.self) else { return nil }
                            return moment.isArchived == true ? nil : moment
                        }
                    }
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

        // 5. Refresh nombres de listas personalizadas
        refreshGroup.enter()
        self.fetchCustomAudienceListNames(userId: userId) {
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

    // ✅ FUNCIÓN CORREGIDA: Upload profile picture (OFFLINE AWARE)
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

                // 1. Guardar copia local temporal
                let fileName = "temp_profile_\(UUID().uuidString).jpg"
                if let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = documentsDir.appendingPathComponent(fileName)
                    if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                        try jpegData.write(to: fileURL)
                        
                        // 2. Delegar a LocalPersistence (Optimistic UI + Sync)
                        await LocalPersistenceService.shared.updateProfile(
                            userId: userId,
                            bio: nil,
                            website: nil,
                            interests: nil,
                            profileImageLocalPath: fileURL.path
                        )
                        
                        // 3. Refrescar localmente (Optimistic UI ya se encarga, pero aseguramos)
                        fetchProfile(userId: userId)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Error al cargar la imagen: \(error.localizedDescription)"
                }
            }
        }
    }
    

    // ✅ FUNCIÓN EXISTENTE: Update bio (OFFLINE AWARE)
    func updateProfileDetails(bio: String?, websiteUrl: String?, interests: [String]? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.errorMessage = "Usuario no autenticado. Por favor, inicia sesión."
            return
        }

        // Delegar a LocalPersistence (Optimistic UI + Sync)
        Task {
            await LocalPersistenceService.shared.updateProfile(
                userId: userId,
                bio: bio,
                website: websiteUrl,
                interests: interests,
                profileImageLocalPath: nil
            )
            
            DispatchQueue.main.async {
                self.fetchProfile(userId: userId)
            }
        }
    }
    
    // Mantenemos updateBio por compatibilidad, pero redirigimos
    func updateBio(newBio: String) {
        updateProfileDetails(bio: newBio, websiteUrl: nil)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(selectedTab: .constant(4))
            .environmentObject(AuthService())
    }
}
