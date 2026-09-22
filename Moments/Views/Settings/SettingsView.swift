import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import UserMessagingPlatform
struct SettingsProfileColors {
    static var background: Color {
        Color(hex: "FAF9F6")
    }

    static var secondaryBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }

    static var cardBackground: Color {
        Color(hex: "FAF9F6").opacity(0.8)
    }

    static var materialBackground: Color {
        Color(hex: "FAF9F6").opacity(0.95)
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

    /// Acento de UI adaptativo (texto, iconos, bordes) — sin índigo de marca.
    static func accent(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .black
    }

    static func accentStroke(_ colorScheme: ColorScheme, opacity: Double = 0.3) -> Color {
        accent(colorScheme).opacity(opacity)
    }

    static func accentBackground(_ colorScheme: ColorScheme, opacity: Double = 0.1) -> Color {
        accent(colorScheme).opacity(opacity)
    }

    /// Texto sobre fondo de acento (botones primarios).
    static func accentContrastingText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : .white
    }

    /// Verde del UISwitch en iOS (visible con el track activo en claro y oscuro).
    static let toggleTint = Color(uiColor: .systemGreen)

    static let purple = Color(hex: "9B59B6")
    static let blue = Color(hex: "6B73FF")
}

extension View {
    /// Tinte verde solo para `Toggle`. No aplicar en contenedores amplios: tiñe también los botones de `.alert`.
    func settingsSwitchTint() -> some View {
        tint(SettingsProfileColors.toggleTint)
    }
}

/// Destinos push de Ajustes, consolidados en un único `navigationDestination(item:)`
/// para no acumular modificadores que la transición zoom evalúa fuera del NavigationStack.
enum SettingsRoute: Hashable, Identifiable {
    case contentVisibility
    case connections
    case bestFriends
    case blockedAccounts
    case mute
    case passwordChange
    case savedMoments
    case userActivity
    case dataExport
    case moderationReviews
    case archivedStories
    case notificationSettings
    case loginActivity

    var id: Self { self }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = SettingsViewModel()
    @State private var isPrivate: Bool = false
    @State private var showFollowing: Bool = true
    @State private var showFollowers: Bool = true
    @State private var showReadReceipts: Bool = true
    @State private var isScheduleEnabled: Bool = false
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var phoneNumber: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    @State private var isShowingQRCode: Bool = false
    @State private var route: SettingsRoute?
    @State private var isShowingAdvancedAccountManagement: Bool = false
    @State private var isShowingNovaMemory: Bool = false
    @State private var isShowingPersonalInfo: Bool = false
    @State private var blockedAccountsCount: Int = 0
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var activityCategory: ActivityInteractionCategory?
    /// `onHingeChange` (iOS 27.1). `.unknown` en iPhone, donde no hay bisagra.
    @State private var hingePose: SettingsHingePose = .unknown

    var body: some View {
        settingsNavigation
        .toolbarBackground(.hidden, for: .navigationBar)
        .momentsScrollEdgeChrome()
        .toolbar(.hidden, for: .tabBar)
        .momentsFloatingTabBarHidden()
        .sheet(isPresented: $isShowingPersonalInfo) {
            PersonalInfoView(username: $username, email: $email, phoneNumber: $phoneNumber)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingAdvancedAccountManagement) {
            AdvancedAccountManagementView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingNovaMemory) {
            NovaMemoryManagementView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .tint(colorScheme == .dark ? .white : .black)
        .onAppear {
            isLoading = true
            viewModel.fetchUserSettings { result in
                switch result {
                case .success(let user):
                    self.isPrivate = user.isPrivate
                    self.showFollowing = user.showFollowing
                    self.showFollowers = user.showFollowers
                    self.blockedAccountsCount = user.blockedUsers.count
                    self.username = user.username
                    self.email = user.email
                    if let start = user.activeHoursStart, let end = user.activeHoursEnd,
                       let startDate = viewModel.dateFormatter.date(from: start),
                       let endDate = viewModel.dateFormatter.date(from: end) {
                        self.startTime = startDate
                        self.endTime = endDate
                        self.isScheduleEnabled = true
                    } else {
                        self.isScheduleEnabled = false
                        self.startTime = Date()
                        self.endTime = Date()
                    }
                    self.showReadReceipts = user.showReadReceipts
                case .failure(let error):
                    guard Auth.auth().currentUser != nil, authService.currentFirebaseUser != nil else {
                        self.isLoading = false
                        dismiss()
                        return
                    }
                    self.showError(message: String(format: NSLocalizedString("settings.error.load", comment: "Settings load error"), error.localizedDescription))
                }
                self.isLoading = false
            }
        }
        .onChange(of: authService.currentFirebaseUser) { _, user in
            guard user == nil else { return }
            isLoading = false
            showError = false
            errorMessage = nil
            dismiss()
        }
        .onChange(of: route) { _, newRoute in
            if newRoute == .userActivity {
                activityCategory = nil
                preferredCompactColumn = .detail
            } else if newRoute != nil {
                preferredCompactColumn = .detail
            } else {
                activityCategory = nil
                preferredCompactColumn = .sidebar
            }
        }
        .onChange(of: activityCategory) { _, newCategory in
            if newCategory != nil {
                preferredCompactColumn = .detail
            }
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            if newValue == .regular {
                columnVisibility = .all
            } else if route != nil {
                preferredCompactColumn = .detail
            }
        }
        .modifier(SettingsHingeColumnRestorer(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn,
            pose: $hingePose,
            route: $route
        ))
        .alert("settings.error.title", isPresented: $showError) {
            Button("settings.ok") { }
        } message: {
            Text(errorMessage ?? NSLocalizedString("settings.error.unknown", comment: "Unknown settings error"))
        }
    }

    /// Presentado fuera del stack del perfil, así el split es la raíz:
    /// compacto (iPhone y Duo cerrado) empuja la categoría, y al abrir
    /// `columnVisibility = .all` vuelve a mostrar la barra.
    private var settingsNavigation: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            settingsNavigationPrimary
        } detail: {
            NavigationStack {
                settingsSplitDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.settingsSplitBackAction, {
            returnFromSettingsDetail()
        })
        .environment(\.settingsSidebarBackIsVisible, horizontalSizeClass == .regular)
    }

    @ViewBuilder
    private var settingsNavigationPrimary: some View {
        if route == .userActivity, activityCategory != nil {
            UserActivitySidebarView(
                selection: activityCategorySelection,
                onBack: returnToSettingsSidebar
            )
        } else {
            settingsRootPane
        }
    }

    private var settingsRootPane: some View {
        ZStack {
            modernBackgroundView

            if isLoading {
                modernLoadingView
            } else {
                settingsSidebar
            }
        }
        .navigationTitle(NSLocalizedString("settings.title", comment: "Settings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            SettingsExplicitBackToolbarContent(action: { dismiss() })
        }
    }

    private var settingsSidebar: some View {
        SettingsFormView(
            viewModel: viewModel,
            isPrivate: $isPrivate,
            showFollowing: $showFollowing,
            showFollowers: $showFollowers,
            isScheduleEnabled: $isScheduleEnabled,
            startTime: $startTime,
            endTime: $endTime,
            username: $username,
            email: $email,
            phoneNumber: $phoneNumber,
            isShowingPersonalInfo: $isShowingPersonalInfo,
            isShowingQRCode: $isShowingQRCode,
            route: settingsRouteSelection,
            isShowingAdvancedAccountManagement: $isShowingAdvancedAccountManagement,
            isShowingNovaMemory: $isShowingNovaMemory,
            showReadReceipts: $showReadReceipts,
            blockedAccountsCount: blockedAccountsCount
        )
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private var settingsSplitDetail: some View {
        Group {
            if route == .userActivity, let activityCategory {
                UserActivityDestinationView(category: activityCategory)
            } else if route == .userActivity {
                UserActivitySidebarView(
                    selection: activityCategorySelection,
                    onBack: nil
                )
            } else if let route {
                destinationView(for: route)
            } else {
                ContentUnavailableView(
                    "settings.title",
                    systemImage: "gearshape",
                    description: Text("settings.selectSection")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(modernBackgroundView)
    }

    private func returnToSettingsSidebar() {
        activityCategory = nil
        route = nil
        preferredCompactColumn = .sidebar
        columnVisibility = .all
    }

    private var settingsRouteSelection: Binding<SettingsRoute?> {
        Binding(
            get: { route },
            set: { newRoute in
                route = newRoute
                if newRoute != nil {
                    preferredCompactColumn = .detail
                    showDetailInCompactLayout()
                }
            }
        )
    }

    private var activityCategorySelection: Binding<ActivityInteractionCategory?> {
        Binding(
            get: { activityCategory },
            set: { newCategory in
                activityCategory = newCategory
                if newCategory != nil {
                    preferredCompactColumn = .detail
                    showDetailInCompactLayout()
                }
            }
        )
    }

    private func showDetailInCompactLayout() {
        preferredCompactColumn = .detail
    }

    private func returnFromSettingsDetail() {
        if route == .userActivity, activityCategory != nil {
            activityCategory = nil
            preferredCompactColumn = .detail
        } else {
            returnToSettingsSidebar()
        }
    }

    @ViewBuilder
    private func destinationView(for route: SettingsRoute) -> some View {
        switch route {
        case .contentVisibility:
            ContentVisibilityView()
        case .connections:
            ConnectionVisibilityView(
                showFollowing: $showFollowing,
                showFollowers: $showFollowers,
                viewModel: viewModel
            )
        case .bestFriends:
            BestFriendsView()
        case .blockedAccounts:
            BlockedUsersView()
        case .mute:
            MuteSettingsView()
        case .passwordChange:
            Group {
                if authService.isPasswordLinked {
                    PasswordChangeView()
                        .environmentObject(authService)
                } else {
                    SetPasswordView()
                        .environmentObject(authService)
                }
            }
            .onAppear {
                authService.refreshLinkedProviders()
            }
        case .savedMoments:
            SavedMomentsView()
        case .userActivity:
            EmptyView()
        case .dataExport:
            DataExportView()
        case .moderationReviews:
            ModerationReviewStatusView()
        case .archivedStories:
            ArchiveView()
        case .notificationSettings:
            NotificationSettingsView(
                viewModel: viewModel,
                isScheduleEnabled: $isScheduleEnabled,
                startTime: $startTime,
                endTime: $endTime
            )
        case .loginActivity:
            LoginActivityView()
        }
    }

    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }

    // ✅ Fondo moderno (ahora negro sólido en dark mode para coincidir con feed)
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                Color(hex: "0B1215")
            } else {
                Color(hex: "FAF9F6")
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.02 : 0.02)
        }
        .ignoresSafeArea()
    }

    // ✅ Vista de carga moderna
    private var modernLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: SettingsProfileColors.accent(colorScheme)))
                .scaleEffect(1.5)

                            Text("settings.loading")
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .transition(MotionPolicy.Transition.enterPop)
    }
}

private enum SettingsHingePose {
    case unknown
    case closed
    case partiallyOpen
    case fullyOpen
}

/// `onHingeChange` (SDK 27.1). Abierta: las dos columnas. Cerrada: solo la categoría.
private struct SettingsHingeColumnRestorer: ViewModifier {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    @Binding var pose: SettingsHingePose
    @Binding var route: SettingsRoute?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                switch context.hinge?.status {
                case .partiallyOpen:
                    pose = .partiallyOpen
                    columnVisibility = .all
                case .fullyOpen:
                    pose = .fullyOpen
                    columnVisibility = .all
                case .closed:
                    pose = .closed
                    if route != nil {
                        preferredCompactColumn = .detail
                        columnVisibility = .detailOnly
                    }
                default:
                    pose = .unknown
                }
            }
        } else {
            content
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView()
                .environmentObject(AuthService())
                .preferredColorScheme(.light)
            SettingsView()
                .environmentObject(AuthService())
                .preferredColorScheme(.dark)
        }
    }
}
