import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsProfileColors {
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
    @State private var isShowingLoginActivity: Bool = false
    @State private var isShowingSavedMoments: Bool = false
    @State private var isShowingUserActivity: Bool = false
    @State private var isShowingDataExport: Bool = false
    @State private var isShowingArchivedStories: Bool = false
    @State private var isShowingSupportMoments: Bool = false
    @State private var isShowingNotificationSettings: Bool = false
    @State private var isShowingAdvancedAccountManagement: Bool = false
    @State private var isShowingNovaMemory: Bool = false

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
                        isShowingQRCode: $isShowingQRCode,
                        isShowingContentVisibility: $isShowingContentVisibility,
                        isShowingConnections: $isShowingConnections,
                        isShowingBestFriends: $isShowingBestFriends,
                        isShowingBlockedAccounts: $isShowingBlockedAccounts,
                        isShowingMute: $isShowingMute,
                        isShowingPasswordChange: $isShowingPasswordChange,
                        isShowingLoginActivity: $isShowingLoginActivity,
                        isShowingSavedMoments: $isShowingSavedMoments,
                        isShowingUserActivity: $isShowingUserActivity,
                        isShowingDataExport: $isShowingDataExport,
                        isShowingArchivedStories: $isShowingArchivedStories,
                        isShowingSupportMoments: $isShowingSupportMoments,
                        isShowingNotificationSettings: $isShowingNotificationSettings,
                        isShowingAdvancedAccountManagement: $isShowingAdvancedAccountManagement,
                        isShowingNovaMemory: $isShowingNovaMemory,
                        showReadReceipts: $showReadReceipts
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
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "00A896"))
                        }
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
            .fullScreenCover(isPresented: $isShowingQRCode) {
                QRCodeView()
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
            .fullScreenCover(isPresented: $isShowingLoginActivity) {
                LoginActivityView()
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
            .fullScreenCover(isPresented: $isShowingNovaMemory) {
                NovaMemoryManagementView()
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
                Color.black
            } else {
                Color(hex: "f8f9fa")
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
                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "00A896")))
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
    @Binding var isShowingQRCode: Bool
    @Binding var isShowingContentVisibility: Bool
    @Binding var isShowingConnections: Bool
    @Binding var isShowingBestFriends: Bool
    @Binding var isShowingBlockedAccounts: Bool
    @Binding var isShowingMute: Bool
    @Binding var isShowingPasswordChange: Bool
    @Binding var isShowingLoginActivity: Bool
    @Binding var isShowingSavedMoments: Bool
    @Binding var isShowingUserActivity: Bool
    @Binding var isShowingDataExport: Bool
    @Binding var isShowingArchivedStories: Bool
    @Binding var isShowingSupportMoments: Bool
    @Binding var isShowingNotificationSettings: Bool
    @Binding var isShowingAdvancedAccountManagement: Bool
    @Binding var isShowingNovaMemory: Bool
    @Binding var showReadReceipts: Bool
    
    @State private var animateSections = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // ✅ Bloque 1: Identidad y Conexión
                SettingsGroup(title: NSLocalizedString("settings.group.identity", comment: "Identity")) {
                    ProfileSection(username: $username)
                    
                    AccountSection(
                        username: $username,
                        email: $email,
                        phoneNumber: $phoneNumber,
                        isShowingQRCode: $isShowingQRCode
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                
                // ✅ Bloque 2: Seguridad y Privacidad
                SettingsGroup(title: NSLocalizedString("settings.group.security", comment: "Security & Privacy")) {
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
                        showReadReceipts: $showReadReceipts
                    )
                    
                    OnlineStatusSection()
                    
                    SecuritySection(
                        isShowingPasswordChange: $isShowingPasswordChange,
                        isShowingLoginActivity: $isShowingLoginActivity
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.1), value: animateSections)
                
                // ✅ Bloque 3: Contenido y Actividad
                SettingsGroup(title: NSLocalizedString("settings.group.activity", comment: "Content & Activity")) {
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
                
                // ✅ Bloque 4: Sistema y Soporte
                SettingsGroup(title: NSLocalizedString("settings.group.system", comment: "System & Support")) {
                    NotificationsSection(
                        viewModel: viewModel,
                        isScheduleEnabled: $isScheduleEnabled,
                        startTime: $startTime,
                        endTime: $endTime,
                        isShowingNotificationSettings: $isShowingNotificationSettings
                    )
                    
                    HelpSection()
                    
                    AdvancedAccountSection(
                        isShowingAdvancedAccountManagement: $isShowingAdvancedAccountManagement
                    )
                    
                    LogoutSection()
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(.easeOut(duration: 0.6).delay(0.3), value: animateSections)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateSections = true
            }
        }
    }
}

// ✅ NUEVO: Contenedor para agrupar ajustes con estética glassmorphic
struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.custom("Poppins-Bold", size: 12))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.4))
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content
            }
            .background(
                Group {
                    if colorScheme == .dark {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.black.opacity(0.4))
                    } else {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                    }
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.05), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.1 : 0.5),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
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

    @State private var isPressed: Bool = false

    var body: some View {
        Group {
            if let destination = destination {
                NavigationLink(destination: destination) {
                    rowContent
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button(action: {
                    action?()
                }) {
                    rowContent
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isDestructive ? Color.red.opacity(0.1) : Color(hex: "00A896").opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isDestructive ? .red : Color(hex: "00A896"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-Medium", size: 16))
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(isPressed ? 0.6 : 0.3))
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// ✅ NUEVA SECCIÓN: Wrapper para Account Management
struct AdvancedAccountSection: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isShowingAdvancedAccountManagement: Bool
    
    var body: some View {
        Button(action: {
            isShowingAdvancedAccountManagement = true
        }) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color(hex: "00A896").opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "gear.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 18, weight: .medium))
                }
                
                Text("settings.advanced.title")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray.opacity(0.3))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

// ✅ NUEVA VISTA: Wrapper con advertencias
struct AdvancedAccountManagementView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
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
                                            colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "00A896"))
                    }
                }
            }
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
    @Binding var isShowingQRCode: Bool

    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(
                icon: "person.crop.circle",
                title: NSLocalizedString("settings.sections.personalInfo", comment: "Personal Information"),
                subtitle: NSLocalizedString("settings.sections.personalInfo.subtitle", comment: "Name, phone, email"),
                destination: AnyView(PersonalInfoView(username: $username, email: $email, phoneNumber: $phoneNumber))
            )
            
            SettingsRow(
                icon: "qrcode",
                title: NSLocalizedString("settings.sections.qrCode", comment: "QR Code"),
                subtitle: NSLocalizedString("settings.sections.qrCode.subtitle", comment: "Share your profile"),
                action: {
                    isShowingQRCode = true
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

struct ArchiveSection: View {
    @Binding var isShowingArchivedStories: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(
                icon: "archivebox",
                title: NSLocalizedString("settings.sections.archivedStories", comment: "Archived Stories"),
                subtitle: NSLocalizedString("settings.sections.archivedStories.subtitle", comment: "View all your past stories"),
                action: {
                    isShowingArchivedStories = true
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
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

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color(hex: "00A896").opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "lock.circle")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 18, weight: .medium))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.privacy.privateAccount")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text("settings.privacy.privateAccount.description")
                        .foregroundColor(.gray)
                        .font(.custom("Poppins-Regular", size: 12))
                }
                
                Spacer()
                
                Toggle("", isOn: $isPrivate)
                    .tint(Color(hex: "00A896"))
                    .onChange(of: isPrivate) { newValue in
                        viewModel.updatePrivacySettings(isPrivate: newValue)
                    }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            SettingsRow(
                icon: "eye.slash",
                title: NSLocalizedString("settings.sections.contentVisibility", comment: "Content Visibility"),
                subtitle: NSLocalizedString("settings.sections.contentVisibility.subtitle", comment: "Manage who can see your content"),
                action: {
                    isShowingContentVisibility = true
                }
            )
            
            SettingsRow(
                icon: "person.2.circle",
                title: NSLocalizedString("settings.sections.connections", comment: "Connections"),
                subtitle: getConnectionPrivacyStatus(),
                action: {
                    isShowingConnections = true
                }
            )
            
            SettingsRow(
                icon: "person.2.fill",
                title: NSLocalizedString("settings.sections.bestFriends", comment: "Best Friends"),
                subtitle: NSLocalizedString("settings.sections.bestFriends.subtitle", comment: "Manage best friends list"),
                action: {
                    isShowingBestFriends = true
                }
            )
            
            SettingsRow(
                icon: "hand.raised",
                title: NSLocalizedString("settings.sections.blockedAccounts", comment: "Blocked Accounts"),
                subtitle: NSLocalizedString("settings.sections.blockedAccounts.subtitle", comment: "Manage blocked users"),
                action: {
                    isShowingBlockedAccounts = true
                }
            )
            
            SettingsRow(
                icon: "bell.slash",
                title: NSLocalizedString("settings.sections.mute", comment: "Mute"),
                subtitle: NSLocalizedString("settings.sections.mute.subtitle", comment: "Accounts, words and phrases"),
                action: {
                    isShowingMute = true
                }
            )
            
            HStack {
                ZStack {
                    Circle()
                        .fill(Color(hex: "00A896").opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 18, weight: .medium))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.privacy.readReceipts.title")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text("settings.privacy.readReceipts.description")
                        .foregroundColor(.gray)
                        .font(.custom("Poppins-Regular", size: 12))
                }
                
                Spacer()
                
                Toggle("", isOn: $showReadReceipts)
                    .tint(Color(hex: "00A896"))
                    .onChange(of: showReadReceipts) { newValue in
                        viewModel.updateReadReceiptsPrivacy(enabled: newValue)
                    }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
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
            List {
            Section(header:
                Text("settings.privacy.control.title")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.gray)
            ) {
                HStack {
                    Image(systemName: "eye.slash.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.privacy.hideMutual")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.custom("Poppins-SemiBold", size: 14))
                        Text("settings.privacy.hideMutual.description")
                            .foregroundColor(.gray)
                            .font(.custom("Poppins-Regular", size: 12))
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { !showMutualConnections },
                        set: { newValue in
                            showMutualConnections = !newValue
                            viewModel.updatePrivacySettings(showMutualConnections: !newValue)
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        }
                    ))
                        .tint(Color(hex: "00A896"))
                }
                .padding(.vertical, 4)
                
                HStack {
                    Image(systemName: "eye.slash.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.privacy.hideFollowing")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.custom("Poppins-SemiBold", size: 14))
                        Text("settings.privacy.hideFollowing.description")
                            .foregroundColor(.gray)
                            .font(.custom("Poppins-Regular", size: 12))
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { !showFollowing },
                        set: { newValue in
                            showFollowing = !newValue
                            viewModel.updatePrivacySettings(showFollowing: !newValue)
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        }
                    ))
                        .tint(Color(hex: "00A896"))
                }
                .padding(.vertical, 4)
                
                HStack {
                    Image(systemName: "eye.slash.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.privacy.hideAdmirers")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.custom("Poppins-SemiBold", size: 14))
                        Text("settings.privacy.hideAdmirers.description")
                            .foregroundColor(.gray)
                            .font(.custom("Poppins-Regular", size: 12))
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { !showAdmirers },
                        set: { newValue in
                            showAdmirers = !newValue
                            viewModel.updatePrivacySettings(showAdmirers: !newValue)
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        }
                    ))
                        .tint(Color(hex: "00A896"))
                }
                .padding(.vertical, 4)
            }
            
            Section(footer:
                Text("settings.privacy.control.description")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.top, 8)
            ) {}
        }
        .navigationTitle(NSLocalizedString("settings.connectionPrivacy", comment: "Connection Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Ocultar botón de atrás
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
                                            colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "00A896"))
                    }
                }
            }
        }
        .listRowBackground(SettingsListRowBackground())
        }
    }
}

struct SecuritySection: View {
    @Binding var isShowingPasswordChange: Bool
    @Binding var isShowingLoginActivity: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(
                icon: "key",
                title: NSLocalizedString("settings.sections.password", comment: "Password"),
                subtitle: NSLocalizedString("settings.sections.password.subtitle", comment: "Change password"),
                action: { isShowingPasswordChange = true }
            )
            
            SettingsRow(
                icon: "clock.arrow.circlepath",
                title: NSLocalizedString("settings.sections.loginActivity", comment: "Login Activity"),
                subtitle: NSLocalizedString("settings.sections.loginActivity.subtitle", comment: "Review your recent activity"),
                action: { isShowingLoginActivity = true }
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

struct ActivitySection: View {
    @Binding var isShowingSavedMoments: Bool
    @Binding var isShowingUserActivity: Bool
    @Binding var isShowingDataExport: Bool
    @Binding var isShowingNovaMemory: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(
                icon: "bookmark",
                title: NSLocalizedString("settings.sections.saved", comment: "Saved"),
                subtitle: NSLocalizedString("settings.sections.saved.subtitle", comment: "Moments you've saved"),
                action: { isShowingSavedMoments = true }
            )
            
            SettingsRow(
                icon: "clock",
                title: NSLocalizedString("settings.sections.yourActivity", comment: "Your Activity"),
                subtitle: NSLocalizedString("settings.sections.yourActivity.subtitle", comment: "Time in app, interactions"),
                action: { isShowingUserActivity = true }
            )
            
            SettingsRow(
                icon: "brain.head.profile",
                title: NSLocalizedString("nova.memory.title", comment: "Nova's Memory"),
                subtitle: NSLocalizedString("nova.memory.description", comment: "Manage what Nova knows about you"),
                action: { isShowingNovaMemory = true }
            )
            
            SettingsRow(
                icon: "arrow.down.circle",
                title: NSLocalizedString("settings.sections.downloadData", comment: "Download Your Data"),
                subtitle: NSLocalizedString("settings.sections.downloadData.subtitle", comment: "Request a copy of your data"),
                action: { isShowingDataExport = true }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

struct NotificationsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var isShowingNotificationSettings: Bool

    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(
                icon: "bell",
                title: NSLocalizedString("settings.sections.pushNotifications", comment: "Push Notifications"),
                subtitle: NSLocalizedString("settings.sections.pushNotifications.subtitle", comment: "Posts, stories, comments"),
                action: {
                    isShowingNotificationSettings = true
                }
            )
            
            SettingsRow(
                icon: "envelope",
                title: NSLocalizedString("settings.sections.emailNotifications", comment: "Email Notifications"),
                subtitle: NSLocalizedString("settings.sections.emailNotifications.subtitle", comment: "Activity summaries"),
                action: {
                    // TODO: Implementar vista de notificaciones por email
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

struct HelpSection: View {
    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(
                icon: "questionmark.circle",
                title: NSLocalizedString("settings.sections.helpCenter", comment: "Help Center"),
                subtitle: NSLocalizedString("settings.sections.helpCenter.subtitle", comment: "Get answers to your questions"),
                action: {
                    if let url = URL(string: "https://momentsapp.app/help") {
                        UIApplication.shared.open(url)
                    }
                },
                isExternal: true
            )
            
            SettingsRow(
                icon: "exclamationmark.triangle",
                title: NSLocalizedString("settings.sections.reportProblem", comment: "Report a Problem"),
                subtitle: NSLocalizedString("settings.sections.reportProblem.subtitle", comment: "Let us know if something isn't working"),
                action: {
                    if let url = URL(string: "https://momentsapp.app/report") {
                        UIApplication.shared.open(url)
                    }
                },
                isExternal: true
            )
            
            SettingsRow(
                icon: "doc.text",
                title: NSLocalizedString("settings.sections.termsOfUse", comment: "Terms of Use"),
                subtitle: "",
                action: {
                    if let url = URL(string: "https://momentsapp.app/terms") {
                        UIApplication.shared.open(url)
                    }
                },
                isExternal: true
            )
            
            SettingsRow(
                icon: "hand.raised.circle",
                title: NSLocalizedString("settings.sections.privacyPolicy", comment: "Privacy Policy"),
                subtitle: "",
                action: {
                    if let url = URL(string: "https://momentsapp.app/privacy") {
                        UIApplication.shared.open(url)
                    }
                },
                isExternal: true
            )
        }
        .padding(.horizontal, 12)
    }
}

struct LogoutSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutAlert: Bool = false

    var body: some View {
        Button(action: {
            showLogoutAlert = true
        }) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                }
                
                Text("settings.logout")
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.red)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.red.opacity(0.5))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .alert("¿Cerrar sesión?", isPresented: $showLogoutAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Cerrar sesión", role: .destructive) {
                authService.logout()
                dismiss()
            }
        } message: {
            Text("settings.logout.confirm")
        }
    }
}

// Reemplaza tu SettingsRow existente con esta versión actualizada:



struct PersonalInfoView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String
    
    var body: some View {
        SettingsSubsectionWrapper(title: NSLocalizedString("settings.sections.personalInfo", comment: "Personal Information")) {
            ScrollView {
                VStack(spacing: 16) {
                    // ✅ Sección de información
                    VStack(spacing: 12) {
                        HStack {
                            Text("settings.profile.username")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Spacer()
                            Text(username.isEmpty ? "No configurado" : username)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                        
                        HStack {
                            Text("settings.profile.email")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Spacer()
                            Text(email.isEmpty ? "No configurado" : email)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                        
                        HStack {
                            Text("settings.profile.phone")
                                .font(.custom("Poppins-Medium", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Spacer()
                            Text(phoneNumber.isEmpty ? "No configurado" : phoneNumber)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 20)
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
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                Form {
                    Section("Horario de notificaciones") {
                        Toggle("Establecer horario", isOn: $isScheduleEnabled)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .tint(Color(hex: "00A896"))
                        
                        if isScheduleEnabled {
                            DatePicker("Hora de inicio",
                                       selection: $startTime,
                                       displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            DatePicker("Hora de fin",
                                       selection: $endTime,
                                       displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Button(action: {
                                viewModel.updateActiveHours(startTime: startTime, endTime: endTime)
                            }) {
                                Text("settings.schedule.save")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(colorScheme == .dark ? .black : .white).opacity(0.2))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(hex: "00A896").opacity(0.5), lineWidth: 1.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .listRowBackground(SettingsListRowBackground())
                    
                    Section("Tipos de notificaciones") {
                        ForEach(NotificationType.allCases, id: \.rawValue) { type in
                            Toggle(type.displayName, isOn: Binding(
                                get: { viewModel.notificationPreferences[type.rawValue] ?? true },
                                set: { viewModel.updateNotificationPreference(type: type.rawValue, isEnabled: $0) }
                            ))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .tint(Color(hex: "00A896"))
                        }
                    }
                    .listRowBackground(SettingsListRowBackground())
                    
                    Section("Configuración avanzada") {
                        Toggle("Solo comentarios de mejores amigos", isOn: Binding(
                            get: { viewModel.notificationPreferences["commentsBestFriendsOnly"] ?? false },
                            set: { viewModel.updateNotificationPreference(type: "commentsBestFriendsOnly", isEnabled: $0) }
                        ))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .tint(Color(hex: "00A896"))
                        
                        Toggle("Silenciar likes en publicaciones antiguas", isOn: Binding(
                            get: { viewModel.notificationPreferences["muteOldPostLikes"] ?? false },
                            set: { viewModel.updateNotificationPreference(type: "muteOldPostLikes", isEnabled: $0) }
                        ))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .tint(Color(hex: "00A896"))
                    }
                    .listRowBackground(SettingsListRowBackground())
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(NSLocalizedString("settings.notifications", comment: "Notifications"))
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
                                                colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "00A896"))
                        }
                    }
                }
            }
        }
    }
}

struct SettingsListRowBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
    }
}

// MARK: - Online Status Section
struct OnlineStatusSection: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var onlineStatusService = OnlineStatusService()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    Circle()
                        .fill(onlineStatusService.currentUserStatus.color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: onlineStatusService.currentUserStatus.icon)
                        .foregroundColor(onlineStatusService.currentUserStatus.color)
                        .font(.system(size: 18, weight: .medium))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.onlineStatus.title")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text(String(format: NSLocalizedString("settings.onlineStatus.current", comment: "Current status"), onlineStatusService.currentUserStatus.displayName))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Menu {
                    ForEach(OnlineStatus.allCases, id: \.self) { status in
                        Button(action: {
                            onlineStatusService.setGlobalStatus(status)
                        }) {
                            HStack {
                                Image(systemName: status.icon)
                                    .foregroundColor(status.color)
                                Text(status.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("settings.onlineStatus.select")
                            .font(.custom("Poppins-Medium", size: 13))
                        Image(systemName: "chevron.up.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: "00A896").opacity(0.1))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
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
                    "commentsBestFriendsOnly": false,
                    "muteOldPostLikes": false
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

    func updateActiveHours(startTime: Date, endTime: Date) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let startHour = dateFormatter.string(from: startTime)
        let endHour = dateFormatter.string(from: endTime)
        firestoreService.updateActiveHours(userId: userId, startHour: startHour, endHour: endHour) { error in
            if let error = error {
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
