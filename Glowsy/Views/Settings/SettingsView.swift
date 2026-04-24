import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices

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
    
    // Colores específicos que se mantienen
    static let accent = Color(hex: "4F46E5")
    static let purple = Color(hex: "9B59B6")
    static let blue = Color(hex: "6B73FF")
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = SettingsViewModel()
    @State private var isPrivate: Bool = false
    @State private var showMutualConnections: Bool = true
    @State private var showFollowing: Bool = true
    @State private var showAdmirers: Bool = true
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
    @State private var isShowingContentVisibility: Bool = false
    @State private var isShowingConnections: Bool = false
    @State private var isShowingBestFriends: Bool = false
    @State private var isShowingBlockedAccounts: Bool = false
    @State private var isShowingMute: Bool = false
    @State private var isShowingPasswordChange: Bool = false
    @State private var isShowingSavedMoments: Bool = false
    @State private var isShowingUserActivity: Bool = false
    @State private var isShowingDataExport: Bool = false
    @State private var isShowingArchivedStories: Bool = false
    @State private var isShowingSupportMoments: Bool = false
    @State private var isShowingNotificationSettings: Bool = false
    @State private var isShowingAdvancedAccountManagement: Bool = false
    @State private var isShowingNovaMemory: Bool = false
    @State private var isShowingPersonalInfo: Bool = false
    @State private var blockedAccountsCount: Int = 0

    var body: some View {
        NavigationView {
            ZStack {
                // ✅ Fondo moderno con glassmorphism
                modernBackgroundView
                
                if isLoading {
                    modernLoadingView
                } else {
                    SettingsFormView(
                        viewModel: viewModel,
                        isPrivate: $isPrivate,
                        showMutualConnections: $showMutualConnections,
                        showFollowing: $showFollowing,
                        isScheduleEnabled: $isScheduleEnabled,
                        startTime: $startTime,
                        endTime: $endTime,
                        username: $username,
                        email: $email,
                        phoneNumber: $phoneNumber,
                        isShowingPersonalInfo: $isShowingPersonalInfo,
                        isShowingQRCode: $isShowingQRCode,
                        isShowingContentVisibility: $isShowingContentVisibility,
                        isShowingConnections: $isShowingConnections,
                        isShowingBestFriends: $isShowingBestFriends,
                        isShowingBlockedAccounts: $isShowingBlockedAccounts,
                        isShowingMute: $isShowingMute,
                        isShowingPasswordChange: $isShowingPasswordChange,
                        isShowingSavedMoments: $isShowingSavedMoments,
                        isShowingUserActivity: $isShowingUserActivity,
                        isShowingDataExport: $isShowingDataExport,
                        isShowingArchivedStories: $isShowingArchivedStories,
                        isShowingSupportMoments: $isShowingSupportMoments,
                        isShowingNotificationSettings: $isShowingNotificationSettings,
                        isShowingAdvancedAccountManagement: $isShowingAdvancedAccountManagement,
                        isShowingNovaMemory: $isShowingNovaMemory,
                        showReadReceipts: $showReadReceipts,
                        blockedAccountsCount: blockedAccountsCount
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
            }
            .navigationTitle(NSLocalizedString("settings.title", comment: "Settings"))
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .onAppear {
                isLoading = true
                viewModel.fetchUserSettings { result in
                    switch result {
                    case .success(let user):
                        self.isPrivate = user.isPrivate
                        self.showMutualConnections = user.showMutualConnections
                        self.showFollowing = user.showFollowing
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
                            self.startTime = Date()
                            self.endTime = Date()
                        }
                        self.showReadReceipts = user.showReadReceipts
                    case .failure(let error):
                        self.showError(message: "Error al cargar configuración: \(error.localizedDescription)")
                    }
                    self.isLoading = false
                }
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("settings.error.title"),
                    message: Text(errorMessage ?? "Ocurrió un error desconocido"),
                    dismissButton: .default(Text("settings.ok"))
                )
            }
                    }
            .sheet(isPresented: $isShowingQRCode) {
                QRCodeView()
            }
            .sheet(isPresented: $isShowingPersonalInfo) {
                PersonalInfoView(username: $username, email: $email, phoneNumber: $phoneNumber)
                    .presentationDetents([.medium, .large])
                    .presentationContentInteraction(.scrolls)
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $isShowingContentVisibility) {
                ContentVisibilityView()
            }
            .fullScreenCover(isPresented: $isShowingConnections) {
                ConnectionVisibilityView(
                    showMutualConnections: $showMutualConnections,
                    showFollowing: $showFollowing,
                    showAdmirers: $showAdmirers,
                    viewModel: viewModel
                )
            }
            .fullScreenCover(isPresented: $isShowingBestFriends) {
                BestFriendsView()
            }
            .fullScreenCover(isPresented: $isShowingBlockedAccounts) {
                BlockedUsersView()
            }
            .fullScreenCover(isPresented: $isShowingMute) {
                MuteSettingsView()
            }
            .fullScreenCover(isPresented: $isShowingPasswordChange) {
                PasswordChangeView()
            }
            .fullScreenCover(isPresented: $isShowingSavedMoments) {
                SavedMomentsView()
            }
            .fullScreenCover(isPresented: $isShowingUserActivity) {
                UserActivityView()
            }
                    .fullScreenCover(isPresented: $isShowingDataExport) {
            DataExportView()
            }
            .fullScreenCover(isPresented: $isShowingArchivedStories) {
                ArchiveView()
            }
            .fullScreenCover(isPresented: $isShowingSupportMoments) {
                SupportMomentsView()
            }
            .fullScreenCover(isPresented: $isShowingNotificationSettings) {
                NotificationSettingsView(
                    viewModel: viewModel,
                    isScheduleEnabled: $isScheduleEnabled,
                    startTime: $startTime,
                    endTime: $endTime
                )
            }
            .sheet(isPresented: $isShowingAdvancedAccountManagement) {
                AdvancedAccountManagementView()
            }
            .sheet(isPresented: $isShowingNovaMemory) {
                NovaMemoryManagementView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .navigationViewStyle(StackNavigationViewStyle()) // Forzar navegación por stack
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
                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "4F46E5")))
                .scaleEffect(1.5)
            
                            Text("settings.loading")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .transition(.opacity.combined(with: .scale))
    }
}

struct SettingsFormView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isPrivate: Bool
    @Binding var showMutualConnections: Bool
    @Binding var showFollowing: Bool
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String
    @Binding var isShowingPersonalInfo: Bool
    @Binding var isShowingQRCode: Bool
    @Binding var isShowingContentVisibility: Bool
    @Binding var isShowingConnections: Bool
    @Binding var isShowingBestFriends: Bool
    @Binding var isShowingBlockedAccounts: Bool
    @Binding var isShowingMute: Bool
    @Binding var isShowingPasswordChange: Bool
    @Binding var isShowingSavedMoments: Bool
    @Binding var isShowingUserActivity: Bool
    @Binding var isShowingDataExport: Bool
    @Binding var isShowingArchivedStories: Bool
    @Binding var isShowingSupportMoments: Bool
    @Binding var isShowingNotificationSettings: Bool
    @Binding var isShowingAdvancedAccountManagement: Bool
    @Binding var isShowingNovaMemory: Bool
    @Binding var showReadReceipts: Bool
    let blockedAccountsCount: Int
    
    @State private var animateSections = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                SettingsGroup(title: NSLocalizedString("settings.group.account", comment: "Account")) {
                    ProfileSection(username: $username)

                    AccountSection(
                        username: $username,
                        email: $email,
                        phoneNumber: $phoneNumber,
                        isShowingPersonalInfo: $isShowingPersonalInfo,
                        isShowingQRCode: $isShowingQRCode
                    )

                    SecuritySection(
                        isShowingPasswordChange: $isShowingPasswordChange
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)

                SettingsGroup(title: NSLocalizedString("settings.group.privacy", comment: "Privacy & Security")) {
                    PrivacySection(
                        isPrivate: $isPrivate,
                        showMutualConnections: $showMutualConnections,
                        showFollowing: $showFollowing,
                        viewModel: viewModel,
                        isShowingContentVisibility: $isShowingContentVisibility,
                        isShowingConnections: $isShowingConnections,
                        isShowingBestFriends: $isShowingBestFriends,
                        isShowingBlockedAccounts: $isShowingBlockedAccounts,
                        isShowingMute: $isShowingMute,
                        showReadReceipts: $showReadReceipts,
                        blockedAccountsCount: blockedAccountsCount
                    )

                    OnlineStatusSection()
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.1), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.content", comment: "Your Content & Activity")) {
                    ActivitySection(
                        isShowingSavedMoments: $isShowingSavedMoments,
                        isShowingUserActivity: $isShowingUserActivity,
                        isShowingDataExport: $isShowingDataExport,
                        isShowingNovaMemory: $isShowingNovaMemory
                    )

                    ArchiveSection(
                        isShowingArchivedStories: $isShowingArchivedStories
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.2), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.notifications", comment: "Notifications")) {
                    NotificationsSection(
                        viewModel: viewModel,
                        isScheduleEnabled: $isScheduleEnabled,
                        startTime: $startTime,
                        endTime: $endTime,
                        isShowingNotificationSettings: $isShowingNotificationSettings
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.3), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.support", comment: "Data & Support")) {
                    HelpSection()
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.4), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.advanced", comment: "Advanced Settings")) {
                    AdvancedAccountSection(
                        isShowingAdvancedAccountManagement: $isShowingAdvancedAccountManagement
                    )

                    LogoutSection()
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.5), value: animateSections)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateSections = true
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// Section group: plain list with a small caption header and thin dividers
struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.custom("Poppins-Bold", size: 11))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
        }
    }
}

struct SettingsRow: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let subtitle: String?
    var destination: AnyView? = nil
    var action: (() -> Void)? = nil
    var isDestructive: Bool = false
    var isExternal: Bool = false

    var body: some View {
        Group {
            if let destination = destination {
                NavigationLink(destination: destination) {
                    rowContent
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button(action: { action?() }) {
                    rowContent
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var rowContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(iconForegroundColor)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.custom("Poppins-Medium", size: 15))
                        .foregroundColor(isDestructive ? .red : (colorScheme == .dark ? .white : .black))

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                if isExternal {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray.opacity(0.5))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())

            Divider()
                .opacity(0.2)
                .padding(.leading, 42)
        }
    }

    private var iconForegroundColor: Color {
        if isDestructive {
            return .red
        }
        if icon == "star.fill" {
            return Color(hex: "34C759")
        }
        return colorScheme == .dark ? .white : .black
    }
}

struct AdvancedAccountSection: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isShowingAdvancedAccountManagement: Bool

    var body: some View {
        Button(action: { isShowingAdvancedAccountManagement = true }) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "gear.badge")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, alignment: .center)

                    Text(NSLocalizedString("settings.advanced.title", comment: "Advanced"))
                        .font(.custom("Poppins-Medium", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.3))
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())

                Divider()
                    .opacity(0.2)
                    .padding(.leading, 42)
            }
        }
        .buttonStyle(.plain)
    }
}

// ✅ NUEVA VISTA: Wrapper con advertencias
struct AdvancedAccountManagementView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var isShowingSessionManagement = false
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
            
            Form {
                // Warning section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 20))
                            
                            Text("settings.dangerZone.title")
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(.orange)
                        }
                        
                        Text("settings.dangerZone.warning")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
                
                Section(NSLocalizedString("settings.sections.loginActivity", comment: "Login Activity")) {
                    SettingsRow(
                        icon: "clock.arrow.circlepath",
                        title: NSLocalizedString("settings.sections.loginActivity", comment: "Login Activity"),
                        subtitle: NSLocalizedString("settings.sections.loginActivity.subtitle", comment: "Review your recent activity"),
                        action: { isShowingSessionManagement = true }
                    )
                }
                .listRowBackground(SettingsListRowBackground())
                
                // ✅ USAR TU AccountManagementSection EXISTENTE
                AccountManagementSection()
                
                // Info section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.info.title")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("settings.info.deactivate")
                            Text("settings.info.delete")
                            Text("settings.info.reactivate")
                        }
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(SettingsListRowBackground())
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(NSLocalizedString("settings.accountManagement", comment: "Account Management"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "4F46E5").opacity(0.3), Color(hex: "4F46E5").opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "4F46E5"))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingSessionManagement) {
            LoginActivityView()
        }
    }
}

struct ProfileSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @Binding var username: String
    
    var body: some View {
        VStack(spacing: 16) {
            // Foto de perfil con decoraciones Plus/Badges
            ZStack {
                // Foto de perfil base
                if let userId = authService.currentUser?.id {
                    AsyncProfileImageView(userId: userId)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 35))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        )
                }
                
                // Decoraciones basadas en el estado del usuario
                if let currentUser = authService.currentUser {
                    
                    // Anillo Plus para suscriptores
                    if currentUser.isPlusSubscriber {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 88, height: 88)
                            .rotationEffect(.degrees(45))
                    }
                    
                    // Badge principal en esquina superior derecha
                    if let primaryBadge = currentUser.primaryBadge {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: primaryBadge.swiftUIColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 28)
                            
                            Text(primaryBadge.emoji)
                                .font(.system(size: 14))
                        }
                        .offset(x: 28, y: -28)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    // Corona Plus en esquina superior izquierda
                    if currentUser.isPlusSubscriber {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.8))
                                .frame(width: 24, height: 24)
                            
                            Image(systemName: "crown.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: "FFD700"))
                        }
                        .offset(x: -28, y: -28)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(.top, 8)
            
            // Información del usuario y estado Plus
            VStack(spacing: 12) {
                // Nombre y badges inline
                HStack(spacing: 8) {
                    Text(username.isEmpty ? "Usuario" : username)
                        .font(.custom("Poppins-SemiBold", size: 20))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    // Badges inline
                    if let currentUser = authService.currentUser {
                        if currentUser.isPlusSubscriber {
                            Text("PRO")
                                .font(.custom("Poppins-Bold", size: 10))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "FFD700"))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                // Estado Plus (si aplica)
                if let currentUser = authService.currentUser, currentUser.isPlusSubscriber {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "FFD700"))
                        
                        Text("settings.plus.active")
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(Color(hex: "FFD700"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "FFD700").opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }
}

struct AccountSection: View {
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String
    @Binding var isShowingPersonalInfo: Bool
    @Binding var isShowingQRCode: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "person.crop.circle",
                title: NSLocalizedString("settings.sections.personalInfo", comment: "Personal Information"),
                subtitle: NSLocalizedString("settings.sections.personalInfo.subtitle", comment: "Username and email"),
                action: { isShowingPersonalInfo = true }
            )

            SettingsRow(
                icon: "qrcode",
                title: NSLocalizedString("settings.sections.qrCode", comment: "QR Code"),
                subtitle: NSLocalizedString("settings.sections.qrCode.subtitle", comment: "Share your profile"),
                action: { isShowingQRCode = true }
            )
        }
    }
}

struct ArchiveSection: View {
    @Binding var isShowingArchivedStories: Bool

    var body: some View {
        SettingsRow(
            icon: "archivebox",
            title: NSLocalizedString("settings.sections.archivedStories", comment: "Archived Stories"),
            subtitle: NSLocalizedString("settings.sections.archivedStories.subtitle", comment: "View all your past stories"),
            action: { isShowingArchivedStories = true }
        )
    }
}

struct PrivacySection: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isPrivate: Bool
    @Binding var showMutualConnections: Bool
    @Binding var showFollowing: Bool
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isShowingContentVisibility: Bool
    @Binding var isShowingConnections: Bool
    @Binding var isShowingBestFriends: Bool
    @Binding var isShowingBlockedAccounts: Bool
    @Binding var isShowingMute: Bool
    @Binding var showReadReceipts: Bool
    let blockedAccountsCount: Int

    var body: some View {
        VStack(spacing: 0) {
            // Private Account toggle — plain row with divider
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: isPrivate ? "lock" : "lock.open")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("settings.privacy.privateAccount", comment: "Private account"))
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Text(NSLocalizedString("settings.privacy.privateAccount.description", comment: "Private account description"))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Toggle("", isOn: $isPrivate)
                        .labelsHidden()
                        .onChange(of: isPrivate) { newValue in
                            viewModel.updatePrivacySettings(isPrivate: newValue)
                        }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 4)

                Divider().opacity(0.2).padding(.leading, 42)
            }

            SettingsRow(icon: "eye.slash",
                title: NSLocalizedString("settings.sections.contentVisibility", comment: "Content Visibility"),
                subtitle: NSLocalizedString("settings.sections.contentVisibility.subtitle", comment: "Manage who can see your content"),
                action: { isShowingContentVisibility = true })

            SettingsRow(icon: "person.2.circle",
                title: NSLocalizedString("settings.sections.connections", comment: "Connections"),
                subtitle: getConnectionPrivacyStatus(),
                action: { isShowingConnections = true })

            SettingsRow(icon: "star.fill",
                title: NSLocalizedString("settings.sections.bestFriends", comment: "Best Friends"),
                subtitle: NSLocalizedString("settings.sections.bestFriends.subtitle", comment: "Manage best friends list"),
                action: { isShowingBestFriends = true })

            SettingsRow(icon: "hand.raised",
                title: NSLocalizedString("settings.sections.blockedAccounts", comment: "Blocked Accounts"),
                subtitle: blockedAccountsSubtitle(),
                action: { isShowingBlockedAccounts = true })

            SettingsRow(icon: "bell.slash",
                title: NSLocalizedString("settings.sections.mute", comment: "Mute"),
                subtitle: NSLocalizedString("settings.sections.mute.subtitle", comment: "Accounts, words and phrases"),
                action: { isShowingMute = true })

            // Read Receipts toggle — plain row, no divider at bottom (last item)
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("settings.privacy.readReceipts.title", comment: "Read receipts"))
                        .font(.custom("Poppins-Medium", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(NSLocalizedString("settings.privacy.readReceipts.description", comment: "Read receipts description"))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                Toggle("", isOn: $showReadReceipts)
                    .labelsHidden()
                    .onChange(of: showReadReceipts) { newValue in
                        viewModel.updateReadReceiptsPrivacy(enabled: newValue)
                    }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
        }
    }

    private func getConnectionPrivacyStatus() -> String {
        let hiddenCount = (!showMutualConnections ? 1 : 0) + (!showFollowing ? 1 : 0)
        switch hiddenCount {
        case 0: return NSLocalizedString("settings.privacy.connections.allPublic", comment: "All connections are public")
        case 1: return NSLocalizedString("settings.privacy.connections.hiddenCount.singular", comment: "1 hidden list")
        case 2: return NSLocalizedString("settings.privacy.connections.allHidden", comment: "All lists are hidden")
        default: return NSLocalizedString("settings.privacy.connections.configure", comment: "Configure")
        }
    }
    
    private func blockedAccountsSubtitle() -> String {
        let format = NSLocalizedString("settings.sections.blockedAccounts.subtitle", comment: "Blocked accounts count")
        let formatted = String(format: format, blockedAccountsCount)
        
        // Fallback robusto por si una traducción trae el placeholder mal y se muestra literal.
        if formatted.contains("%d") || formatted == format {
            return format.replacingOccurrences(of: "%d", with: "\(blockedAccountsCount)")
        }
        
        return formatted
    }
}

struct ConnectionVisibilityView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Binding var showMutualConnections: Bool
    @Binding var showFollowing: Bool
    @Binding var showAdmirers: Bool
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        Text("settings.privacy.control.title")
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(.gray)

                        VStack(spacing: 0) {
                            privacyToggleRow(
                                title: "settings.privacy.hideMutual",
                                description: "settings.privacy.hideMutual.description",
                                isOn: Binding(
                                    get: { !showMutualConnections },
                                    set: { newValue in
                                        showMutualConnections = !newValue
                                        viewModel.updatePrivacySettings(showMutualConnections: !newValue)
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }
                                )
                            )

                            Divider().opacity(0.2).padding(.leading, 32)

                            privacyToggleRow(
                                title: "settings.privacy.hideFollowing",
                                description: "settings.privacy.hideFollowing.description",
                                isOn: Binding(
                                    get: { !showFollowing },
                                    set: { newValue in
                                        showFollowing = !newValue
                                        viewModel.updatePrivacySettings(showFollowing: !newValue)
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }
                                )
                            )

                            Divider().opacity(0.2).padding(.leading, 32)

                            privacyToggleRow(
                                title: "settings.privacy.hideAdmirers",
                                description: "settings.privacy.hideAdmirers.description",
                                isOn: Binding(
                                    get: { !showAdmirers },
                                    set: { newValue in
                                        showAdmirers = !newValue
                                        viewModel.updatePrivacySettings(showAdmirers: !newValue)
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }
                                )
                            )
                        }

                        Text("settings.privacy.control.description")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(.gray.opacity(0.8))
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                }
            }
        .navigationTitle(NSLocalizedString("settings.connectionPrivacy", comment: "Connection Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Ocultar botón de atrás
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                }
            }
        }
        }
    }

    private func privacyToggleRow(title: LocalizedStringKey, description: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "eye.slash")
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .font(.custom("Poppins-SemiBold", size: 14))
                Text(description)
                    .foregroundColor(.gray)
                    .font(.custom("Poppins-Regular", size: 12))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Color(hex: "4F46E5"))
        }
        .padding(.vertical, 11)
    }
}

struct SecuritySection: View {
    @EnvironmentObject var authService: AuthService
    @Binding var isShowingPasswordChange: Bool
    
    // Para el linking
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAlert = false
    @State private var showChatRecoverySettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "key",
                title: NSLocalizedString("settings.sections.password", comment: "Password"),
                subtitle: NSLocalizedString("settings.sections.password.subtitle", comment: "Change password"),
                action: { isShowingPasswordChange = true }
            )

            SettingsRow(
                icon: "lock.rotation",
                title: NSLocalizedString("chatRecovery.settings.rowTitle", comment: "Chat recovery PIN"),
                subtitle: NSLocalizedString("chatRecovery.settings.rowSubtitle", comment: "Restore encrypted chats after reinstalling the app"),
                action: { showChatRecoverySettings = true }
            )

            // ✅ NUEVO: Vincular con Apple
            if !authService.isAppleLinked {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "applelogo")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.security.appleId")
                                .font(.custom("Poppins-Medium", size: 16))
                            Text("settings.security.appleId.description")
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 44)
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            let nonce = authService.startAppleSignIn()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = nonce
                        } onCompletion: { result in
                            handleAppleLinkingResult(result)
                        }
                        .signInWithAppleButtonStyle(Color.primary == .white ? .white : .black)
                        .frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .alert("Error", isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "Error desconocido")
                }
            } else {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "applelogo")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.security.appleId")
                            .font(.custom("Poppins-Medium", size: 16))
                        Text("settings.security.appleId.linked")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $showChatRecoverySettings) {
            ChatRecoverySettingsView()
        }
    }
    
    private func handleAppleLinkingResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                guard let nonce = authService.currentNonce else {
                    errorMessage = NSLocalizedString("settings.security.appleId.error.nonce", comment: "Security error (nonce)")
                    showAlert = true
                    return
                }
                
                guard let appleIDToken = appleIDCredential.identityToken else {
                    errorMessage = NSLocalizedString("settings.security.appleId.error.token", comment: "Could not obtain Apple token")
                    showAlert = true
                    return
                }
                
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    errorMessage = NSLocalizedString("settings.security.appleId.error.invalidToken", comment: "Invalid Apple token")
                    showAlert = true
                    return
                }
                
                isLoading = true
                authService.linkWithApple(idToken: idTokenString, nonce: nonce) { result in
                    isLoading = false
                    switch result {
                    case .success:
                        // Refrescar UI (isAppleLinked cambiará automáticamente)
                        let impact = UINotificationFeedbackGenerator()
                        impact.notificationOccurred(.success)
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        case .failure(let error):
            // Si el usuario cancela, no mostramos error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

struct ActivitySection: View {
    @Binding var isShowingSavedMoments: Bool
    @Binding var isShowingUserActivity: Bool
    @Binding var isShowingDataExport: Bool
    @Binding var isShowingNovaMemory: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "bookmark",
                title: NSLocalizedString("settings.sections.saved", comment: "Saved"),
                subtitle: NSLocalizedString("settings.sections.saved.subtitle", comment: "Moments you've saved"),
                action: { isShowingSavedMoments = true })

            SettingsRow(icon: "clock",
                title: NSLocalizedString("settings.sections.yourActivity", comment: "Your Activity"),
                subtitle: NSLocalizedString("settings.sections.yourActivity.subtitle", comment: "Time in app, interactions"),
                action: { isShowingUserActivity = true })

            SettingsRow(icon: "brain.head.profile",
                title: NSLocalizedString("nova.memory.title", comment: "Nova's Memory"),
                subtitle: NSLocalizedString("nova.memory.description", comment: "Manage what Nova knows about you"),
                action: { isShowingNovaMemory = true })

            SettingsRow(icon: "arrow.down.circle",
                title: NSLocalizedString("settings.sections.downloadData", comment: "Download Your Data"),
                subtitle: NSLocalizedString("settings.sections.downloadData.subtitle", comment: "Request a copy of your data"),
                action: { isShowingDataExport = true })
        }
    }
}

struct NotificationsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var isShowingNotificationSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "bell",
                title: NSLocalizedString("settings.sections.pushNotifications", comment: "Push Notifications"),
                subtitle: NSLocalizedString("settings.sections.pushNotifications.subtitle", comment: "Posts, stories, comments"),
                action: { isShowingNotificationSettings = true })

            SettingsRow(icon: "envelope",
                title: NSLocalizedString("settings.sections.emailNotifications", comment: "Email Notifications"),
                subtitle: NSLocalizedString("settings.sections.emailNotifications.subtitle", comment: "Activity summaries"),
                action: {})
        }
    }
}

struct HelpSection: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "questionmark.circle",
                title: NSLocalizedString("settings.sections.helpCenter", comment: "Help Center"),
                subtitle: NSLocalizedString("settings.sections.helpCenter.subtitle", comment: "Get answers to your questions"),
                action: { if let url = URL(string: "https://momentsapp.app/help") { UIApplication.shared.open(url) } },
                isExternal: true)

            SettingsRow(icon: "exclamationmark.triangle",
                title: NSLocalizedString("settings.sections.reportProblem", comment: "Report a Problem"),
                subtitle: NSLocalizedString("settings.sections.reportProblem.subtitle", comment: "Let us know if something isn't working"),
                action: { if let url = URL(string: "https://momentsapp.app/report") { UIApplication.shared.open(url) } },
                isExternal: true)

            SettingsRow(icon: "doc.text",
                title: NSLocalizedString("settings.sections.termsOfUse", comment: "Terms of Use"),
                subtitle: "",
                action: { if let url = URL(string: "https://momentsapp.app/terms") { UIApplication.shared.open(url) } },
                isExternal: true)

            SettingsRow(icon: "hand.raised.circle",
                title: NSLocalizedString("settings.sections.privacyPolicy", comment: "Privacy Policy"),
                subtitle: "",
                action: { if let url = URL(string: "https://momentsapp.app/privacy") { UIApplication.shared.open(url) } },
                isExternal: true)
        }
    }
}

struct LogoutSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutAlert: Bool = false

    var body: some View {
        Button(action: { showLogoutAlert = true }) {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(.red)
                    .frame(width: 28, alignment: .center)

                Text(NSLocalizedString("settings.logout", comment: "Log out"))
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(.red)

                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("¿Cerrar sesión?", isPresented: $showLogoutAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Cerrar sesión", role: .destructive) {
                authService.logout()
                dismiss()
            }
        } message: {
            Text(NSLocalizedString("settings.logout.confirm", comment: "Logout confirm"))
        }
    }
}

// Reemplaza tu SettingsRow existente con esta versión actualizada:



struct PersonalInfoView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String
    
    private enum ViewState {
        case main
        case username
    }
    
    // Username change state
    @State private var viewState: ViewState = .main
    @State private var lastUsernameChange: Date? = nil
    private let firestoreService = FirestoreService()
    
    // Cooldown helpers
    private var canChangeUsername: Bool {
        guard let last = lastUsernameChange else { return true }
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        return last <= sixMonthsAgo
    }
    
    private var nextAvailableDate: String? {
        guard let last = lastUsernameChange, !canChangeUsername else { return nil }
        let next = Calendar.current.date(byAdding: .month, value: 6, to: last) ?? Date()
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.locale = Locale.current
        return fmt.string(from: next)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ZStack {
                    switch viewState {
                    case .main:
                        personalInfoMainContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                    case .username:
                        UsernameChangeContent(
                            currentUsername: $username,
                            lastUsernameChange: $lastUsernameChange,
                            onBack: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    viewState = .main
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewState)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewState == .username {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                viewState = .main
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                }
            }
        }
        .onAppear {
            // Load lastUsernameChange from Firestore
            if let uid = Auth.auth().currentUser?.uid {
                firestoreService.fetchUser(userId: uid) { result in
                    if case .success(let user) = result {
                        lastUsernameChange = user.lastUsernameChange
                    }
                }
            }
        }
    }
    
    private var navigationTitle: String {
        switch viewState {
        case .main:
            return NSLocalizedString("settings.sections.personalInfo", comment: "Personal Information")
        case .username:
            return NSLocalizedString("username.change.title", comment: "Change username title")
        }
    }
    
    private var personalInfoMainContent: some View {
        VStack(spacing: 0) {
            Button(action: {
                guard canChangeUsername else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    viewState = .username
                }
            }) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("settings.profile.username", comment: "Username label"))
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        if let nextDate = nextAvailableDate {
                            Text(String(format: NSLocalizedString("username.availableOn", comment: "Available on %@"), nextDate))
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer(minLength: 12)

                    Text("@\(username.isEmpty ? "—" : username)")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(1)

                    if canChangeUsername {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.3))
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.orange.opacity(0.8))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            Divider()
                .opacity(0.2)
                .padding(.leading, 2)
                .padding(.vertical, 4)

            HStack(spacing: 14) {
                Text(NSLocalizedString("settings.profile.email", comment: "Email label"))
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer(minLength: 12)

                Text(email.isEmpty ? NSLocalizedString("settings.notConfigured", comment: "Not configured") : email)
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Username Change Sheet
struct UsernameChangeContent: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var currentUsername: String
    @Binding var lastUsernameChange: Date?
    let onBack: (() -> Void)?
    
    @State private var newUsername: String = ""
    @State private var isChecking: Bool = false
    @State private var isAvailable: Bool? = nil
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var checkTask: Task<Void, Never>? = nil
    
    private let firestoreService = FirestoreService()
    
    private var isValidFormat: Bool {
        let clean = newUsername.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        return clean.count >= 3 && clean.count <= 30 && clean.unicodeScalars.allSatisfy({ allowed.contains($0) })
    }
    
    private var isDifferent: Bool {
        newUsername.lowercased() != currentUsername.lowercased()
    }
    
    private var canSave: Bool {
        isValidFormat && isDifferent && isAvailable == true && !isSaving
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("username.change.title", comment: "Change username title"))
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(.primary)
                    Text(NSLocalizedString("username.change.subtitle", comment: "Can be changed every 6 months"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("@")
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(.secondary)
                        
                        TextField(currentUsername, text: $newUsername)
                            .font(.custom("Poppins-Regular", size: 17))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: newUsername) { _ in
                                triggerAvailabilityCheck()
                            }
                        
                        Spacer()
                        
                        if isChecking {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if newUsername.count >= 3 && isDifferent {
                            if let available = isAvailable {
                                Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(available ? .green : .red)
                                    .font(.system(size: 20))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(borderColor, lineWidth: 1.5)
                            )
                    )
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.red)
                    } else if newUsername.count >= 3 && isDifferent, let available = isAvailable {
                        Text(available
                             ? NSLocalizedString("username.available", comment: "Username available")
                             : NSLocalizedString("username.taken", comment: "Username taken"))
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(available ? .green : .red)
                    } else {
                        Text(NSLocalizedString("username.rules", comment: "3-30 chars, letters, numbers and _"))
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: save) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 4)
                        }
                        Text(NSLocalizedString("username.change.save", comment: "Save username"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canSave ? Color.primary : Color.gray.opacity(0.3))
                    )
                    .foregroundColor(canSave ? (colorScheme == .dark ? .black : .white) : .gray)
                }
                .disabled(!canSave)
                .animation(.easeInOut(duration: 0.2), value: canSave)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    
    private var borderColor: Color {
        if let available = isAvailable, newUsername.count >= 3 && isDifferent {
            return available ? Color.green.opacity(0.6) : Color.red.opacity(0.6)
        }
        return Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4)
    }
    
    private func triggerAvailabilityCheck() {
        isAvailable = nil
        errorMessage = nil
        checkTask?.cancel()
        let username = newUsername.lowercased()
        guard username.count >= 3 && isDifferent else { return }
        isChecking = true
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
            guard !Task.isCancelled else { return }
            firestoreService.db.collection("usernames").document(username).getDocument { snap, _ in
                DispatchQueue.main.async {
                    isChecking = false
                    isAvailable = !(snap?.exists ?? false)
                }
            }
        }
    }
    
    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let oldUsernameLower = currentUsername.lowercased()
        isSaving = true
        errorMessage = nil
        firestoreService.changeUsername(userId: uid, oldUsername: currentUsername, newUsername: newUsername) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success:
                    let newUsernameLower = newUsername.lowercased()
                    currentUsername = newUsernameLower
                    lastUsernameChange = Date()
                    if let email = Auth.auth().currentUser?.email {
                        UserDefaults.standard.set(email, forKey: "cachedEmail_\(newUsernameLower)")
                    }
                    UserDefaults.standard.removeObject(forKey: "cachedEmail_\(oldUsernameLower)")
                    UserDefaults.standard.set(newUsernameLower, forKey: "current_username")
                    onBack?()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}


struct NotificationSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @State private var isSavingSchedule: Bool = false
    @State private var showSavedSchedule: Bool = false
    @State private var showScheduleError: Bool = false
    @State private var scheduleErrorMessage: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("settings.notifications.schedule.title", comment: "Notification Schedule"))
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(.gray)

                            notificationToggleRow(
                                title: NSLocalizedString("settings.notifications.schedule.enable", comment: "Set schedule"),
                                isOn: $isScheduleEnabled
                            )
                            .onChange(of: isScheduleEnabled) { enabled in
                                if !enabled {
                                    viewModel.clearActiveHours()
                                }
                            }

                            if isScheduleEnabled {
                                DatePicker(NSLocalizedString("settings.notifications.schedule.start", comment: "Start time"),
                                           selection: $startTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.top, 2)

                                DatePicker(NSLocalizedString("settings.notifications.schedule.end", comment: "End time"),
                                           selection: $endTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(.top, 2)

                                Button(action: {
                                    guard !isSavingSchedule else { return }
                                    isSavingSchedule = true
                                    HapticManager.shared.lightImpact()
                                    viewModel.updateActiveHours(startTime: startTime, endTime: endTime) { error in
                                        DispatchQueue.main.async {
                                            isSavingSchedule = false
                                            if let error = error {
                                                HapticManager.shared.notification(.error)
                                                scheduleErrorMessage = error.localizedDescription
                                                showScheduleError = true
                                                return
                                            }

                                            HapticManager.shared.notification(.success)
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                                showSavedSchedule = true
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    showSavedSchedule = false
                                                }
                                            }
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if isSavingSchedule {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                                                .scaleEffect(0.85)
                                            Text(NSLocalizedString("settings.schedule.saving", comment: "Saving schedule"))
                                        } else {
                                            Image(systemName: "checkmark.circle")
                                            Text(NSLocalizedString("settings.schedule.save", comment: "Save schedule"))
                                        }
                                    }
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(colorScheme == .dark ? .black : .white).opacity(0.2))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(hex: "4F46E5").opacity(0.5), lineWidth: 1.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .scaleEffect(isSavingSchedule ? 0.98 : 1.0)
                                    .animation(.easeInOut(duration: 0.15), value: isSavingSchedule)
                                }
                                .buttonStyle(SaveSchedulePressStyle())
                                .disabled(isSavingSchedule)
                                .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("settings.notifications.types.title", comment: "Notification Types"))
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(.gray)

                            VStack(spacing: 0) {
                                ForEach(Array(NotificationType.allCases.enumerated()), id: \.element.rawValue) { index, type in
                                    notificationToggleRow(
                                        title: type.displayName,
                                        isOn: Binding(
                                            get: { viewModel.notificationPreferences[type.rawValue] ?? true },
                                            set: { viewModel.updateNotificationPreference(type: type.rawValue, isEnabled: $0) }
                                        )
                                    )

                                    if index < NotificationType.allCases.count - 1 {
                                        Divider().padding(.leading, 4)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("settings.notifications.advanced.title", comment: "Advanced Settings"))
                                .font(.custom("Poppins-Medium", size: 12))
                                .foregroundColor(.gray)

                            VStack(spacing: 0) {
                                notificationToggleRow(
                                    title: NSLocalizedString("settings.notifications.mutualsOnly", comment: "Mutuals comments only"),
                                    isOn: Binding(
                                        get: { viewModel.notificationPreferences["commentsMutualsOnly"] ?? false },
                                        set: { viewModel.updateNotificationPreference(type: "commentsMutualsOnly", isEnabled: $0) }
                                    )
                                )

                                Divider().padding(.leading, 4)

                                notificationToggleRow(
                                    title: NSLocalizedString("settings.notifications.muteOldReactions", comment: "Mute reactions on old posts"),
                                    isOn: Binding(
                                        get: { viewModel.notificationPreferences["muteOldPostReactions"] ?? false },
                                        set: { viewModel.updateNotificationPreference(type: "muteOldPostReactions", isEnabled: $0) }
                                    )
                                )
                            }

                            Text(NSLocalizedString("settings.notifications.oldPostsExplain", comment: "Old posts explanation"))
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                }

                if showSavedSchedule {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(NSLocalizedString("settings.schedule.saved", comment: "Schedule saved"))
                                .font(.custom("Poppins-Medium", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.45),
                                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 12, y: 6)
                        .padding(.top, 10)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle(NSLocalizedString("settings.notifications", comment: "Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .alert(NSLocalizedString("settings.error.title", comment: "Error"), isPresented: $showScheduleError) {
                Button(NSLocalizedString("settings.ok", comment: "OK"), role: .cancel) { }
            } message: {
                Text(scheduleErrorMessage)
            }
        }
    }

    private func notificationToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.custom("Poppins-Regular", size: 14))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .tint(Color(hex: "4F46E5"))
            .padding(.vertical, 10)
    }
}

private struct SaveSchedulePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct SettingsListRowBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                colorScheme == .dark ?
                Color(hex: "FAF9F6").opacity(0.05) :
                Color(hex: "0B1215").opacity(0.04)
            )
    }
}

// MARK: - Online Status Section
struct OnlineStatusSection: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var onlineStatusService = OnlineStatusService()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: onlineStatusService.currentUserStatus.icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(onlineStatusService.currentUserStatus.color)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("settings.onlineStatus.title", comment: "Online Status"))
                        .font(.custom("Poppins-Medium", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(String(format: NSLocalizedString("settings.onlineStatus.current", comment: "Current status"), onlineStatusService.currentUserStatus.displayName))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                Menu {
                    ForEach(OnlineStatus.allCases, id: \.self) { status in
                        Button(action: { onlineStatusService.setGlobalStatus(status) }) {
                            HStack {
                                Image(systemName: status.icon)
                                Text(status.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("settings.onlineStatus.select", comment: "Select"))
                            .font(.custom("Poppins-Medium", size: 13))
                        Image(systemName: "chevron.up.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(colorScheme == .dark ? .white : .black).opacity(0.08))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - ViewModels y extensiones
class SettingsViewModel: ObservableObject {
    @Published var notificationPreferences: [String: Bool] = [:]
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func fetchUserSettings(completion: @escaping (Result<AppUser, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }

        firestoreService.fetchUser(userId: userId) { result in
            switch result {
            case .success(let user):
                self.notificationPreferences = user.notificationPreferences ?? [
                    NotificationType.like.rawValue: true,
                    NotificationType.newFollower.rawValue: true,
                    NotificationType.followRequest.rawValue: true,
                    NotificationType.mutualConnection.rawValue: true,
                    NotificationType.profileVisit.rawValue: true,
                    NotificationType.comment.rawValue: true,
                    "commentsMutualsOnly": false,
                    "muteOldPostReactions": false
                ]
                completion(.success(user))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    func updatePrivacySettings(isPrivate: Bool? = nil, showMutualConnections: Bool? = nil, showFollowing: Bool? = nil, showAdmirers: Bool? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        privacyService.updatePrivacySettings(
            userId: userId,
            isPrivate: isPrivate,
            showMutualConnections: showMutualConnections,
            showFollowing: showFollowing,
            showAdmirers: showAdmirers
        ) { error in
            if let error = error {
            }
        }
    }

    func updateReadReceiptsPrivacy(enabled: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        firestoreService.db.collection("users").document(userId).updateData([
            "showReadReceipts": enabled
        ]) { error in
            if let error = error {
            }
        }
    }

    func updateActiveHours(startTime: Date, endTime: Date, completion: ((Error?) -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let startHour = dateFormatter.string(from: startTime)
        let endHour = dateFormatter.string(from: endTime)
        firestoreService.updateActiveHours(userId: userId, startHour: startHour, endHour: endHour) { error in
            if let error = error {
            }
            completion?(error)
        }
    }

    func clearActiveHours() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        firestoreService.clearActiveHours(userId: userId) { error in
            if let error = error {
                // Handle error
            }
        }
    }

    func updateNotificationPreference(type: String, isEnabled: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        notificationPreferences[type] = isEnabled
        firestoreService.updateNotificationPreferences(userId: userId, preferences: notificationPreferences) { error in
            if let error = error {
            }
        }
    }
}

extension NotificationType {
    static var allCases: [NotificationType] {
        [.like, .newFollower, .followRequest, .mutualConnection, .profileVisit, .comment]
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
