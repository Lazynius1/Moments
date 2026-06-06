import SwiftUI
import PhotosUI
import Kingfisher
import FirebaseAuth

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
    @Binding var isShowingIncognito: Bool
    let isIncognitoActive: Bool
    @Binding var editingMoment: Moment?
    @Binding var pendingDeleteMoment: Moment?
    @StateObject private var savedMomentsViewModel = SavedMomentsViewModel()  // ✅ NUEVO: Guardados
    @State private var showingFullInfo = false // ✅ NUEVO: Para expandir intereses dentro del bloque social
    @State private var gridMenuSelection: ProfileGridMomentMenuSelection?
    @State private var showGridPinConfirm = false
    @State private var gridMenuToastMessage: String?

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
                ZStack(alignment: .topLeading) {
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
                            showProfileImageFullscreen: $showProfileImageFullscreen,
                            isShowingIncognito: $isShowingIncognito,
                            isIncognitoActive: isIncognitoActive

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
                                                        },
                                                        onLongPress: {
                                                            openGridMenu(moment: moment, index: index)
                                                        }
                                                    )
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

                        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                            Task { @MainActor in
                                if !viewModel.isRefreshing && savedRefreshCompleted {
                                    timer.invalidate()
                                    continuation.resume()
                                }
                            }
                        }
                    }
                }
                .scrollDisabled(gridMenuSelection != nil)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }

                ProfileGridMomentMenuOverlay(
                    selection: $gridMenuSelection,
                    showPinConfirm: $showGridPinConfirm,
                    toastMessage: $gridMenuToastMessage,
                    containerSize: proxy.size,
                    safeAreaInsets: proxy.safeAreaInsets,
                    pinnedMomentsCount: viewModel.moments.filter { $0.isPinned == true }.count,
                    pinnedMomentsLimit: 3,
                    onEdit: { moment in
                        editingMoment = moment
                    },
                    onDelete: { moment in
                        pendingDeleteMoment = moment
                    },
                    onArchive: { moment in
                        guard let momentId = moment.id else { return }
                        FirestoreService.shared.archiveMoment(userId: moment.authorId, momentId: momentId) { _ in
                            viewModel.moments.removeAll { $0.id == momentId }
                        }
                    },
                    onPin: { moment, shouldPin, replaceOldest in
                        handleGridPin(moment: moment, shouldPin: shouldPin, replaceOldest: replaceOldest)
                    }
                )
                }
            }
        }
    }

    private func openGridMenu(moment: Moment, index: Int) {
        showGridPinConfirm = false
        gridMenuSelection = ProfileGridMomentMenuSelection(moment: moment, index: index)
    }

    private func handleGridPin(moment: Moment, shouldPin: Bool, replaceOldest: Bool) {
        guard let momentId = moment.id else { return }
        let pinnedAt = Date()

        if shouldPin {
            let completion: (Error?) -> Void = { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    if replaceOldest, let oldestId = viewModel.oldestPinnedMomentId(excluding: momentId) {
                        viewModel.applyPinReplacement(
                            unpinningMomentId: oldestId,
                            pinningMomentId: momentId,
                            pinnedAt: pinnedAt
                        )
                    } else {
                        viewModel.applyMomentPinState(
                            momentId: momentId,
                            isPinned: true,
                            pinnedAt: pinnedAt
                        )
                    }
                }
            }

            if replaceOldest {
                FirestoreService.shared.pinMomentReplacingOldestIfNeeded(
                    userId: moment.authorId,
                    momentId: momentId,
                    pinnedMoments: viewModel.moments,
                    completion: completion
                )
            } else {
                FirestoreService.shared.pinMoment(
                    userId: moment.authorId,
                    momentId: momentId,
                    completion: completion
                )
            }
        } else {
            FirestoreService.shared.unpinMoment(userId: moment.authorId, momentId: momentId) { error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    viewModel.applyMomentPinState(
                        momentId: momentId,
                        isPinned: false,
                        pinnedAt: pinnedAt
                    )
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
