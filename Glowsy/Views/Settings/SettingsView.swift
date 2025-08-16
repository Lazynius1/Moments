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
    @State private var isScheduleEnabled: Bool = false
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var phoneNumber: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false

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
                        phoneNumber: $phoneNumber
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
                            self.endTime = Date()
                        }
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
        .navigationViewStyle(StackNavigationViewStyle()) // Forzar navegación por stack
    }

    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }
    
    // ✅ Fondo moderno con glassmorphism
    private var modernBackgroundView: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color(hex: "1a1a2e").opacity(0.9),
                        Color(hex: "16213e").opacity(0.8),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white,
                        Color(hex: "f8f9fa"),
                        Color(hex: "e9ecef"),
                        Color.white
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.05 : 0.02)
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
    
    @State private var animateSections = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // ✅ Secciones con animaciones escalonadas
                Group {
                    ProfileSection(username: $username)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    AccountSection(username: $username, email: $email, phoneNumber: $phoneNumber)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    PrivacySection(
                        isPrivate: $isPrivate,
                        showMutualConnections: $showMutualConnections,
                        showFollowing: $showFollowing,
                        viewModel: viewModel
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    
                    OnlineStatusSection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    SecuritySection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    ActivitySection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    ArchiveSection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    SupportMomentsSection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    NotificationsSection(
                        viewModel: viewModel,
                        isScheduleEnabled: $isScheduleEnabled,
                        startTime: $startTime,
                        endTime: $endTime
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    
                    HelpSection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    AdvancedAccountSection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    
                    LogoutSection()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
                .opacity(animateSections ? 1 : 0)
                .offset(x: animateSections ? 0 : -50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                animateSections = true
            }
        }
    }
}

// ✅ NUEVA SECCIÓN: Wrapper para Account Management
struct AdvancedAccountSection: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Header de sección con animación
            HStack {
                Image(systemName: "gear.circle.fill")
                    .foregroundColor(adaptiveColors.accent)
                    .font(.system(size: 20))
                
                Text("settings.advanced.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(adaptiveColors.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(adaptiveColors.tertiary)
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: adaptiveColors.overlayStroke,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }
            
            // ✅ Contenido expandible
            if isExpanded {
                VStack(spacing: 8) {
                    SettingsRow(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: NSLocalizedString("settings.sections.accountManagement", comment: "Account Management"),
                        subtitle: NSLocalizedString("settings.sections.accountManagement.subtitle", comment: "Deactivate or delete account"),
                        destination: AnyView(AdvancedAccountManagementView()),
                        iconColor: .orange
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
                .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }
}

// ✅ NUEVA VISTA: Wrapper con advertencias
struct AdvancedAccountManagementView: View {
    @Environment(\.colorScheme) var colorScheme
    
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
    }
}

struct ProfileSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @Binding var username: String
    
    var body: some View {
        Section {
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
                                .animation(
                                    Animation.linear(duration: 10.0)
                                        .repeatForever(autoreverses: false),
                                    value: UUID()
                                )
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
                
                // Información del usuario y estado Plus
                VStack(spacing: 12) {
                    // Nombre y badges inline
                    HStack(spacing: 8) {
                        Text(username.isEmpty ? "Usuario" : username)
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        // Badges inline
                        if let currentUser = authService.currentUser {
                            if currentUser.isPlusSubscriber {
                                Text("settings.plus")
                                    .font(.custom("Poppins-Bold", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "FFD700"))
                                    .clipShape(Capsule())
                            }
                            
                            if let primaryBadge = currentUser.primaryBadge {
                                Text(primaryBadge.name.uppercased())
                                    .font(.custom("Poppins-Bold", size: 9))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        LinearGradient(
                                            colors: primaryBadge.swiftUIColors,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
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
                            
                            Text("✨")
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "FFD700").opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(hex: "FFD700").opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Mensaje de agradecimiento personalizado
                    if let currentUser = authService.currentUser,
                       let thankYouMessage = currentUser.thankYouMessage {
                        Text(thankYouMessage)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(Color(hex: "00A896"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "00A896").opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Botón de editar badges (reemplaza "Editar perfil")
                    NavigationLink(destination: BadgeManagementView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.circle")
                                .font(.system(size: 14, weight: .medium))
                            
                            if let currentUser = authService.currentUser,
                               currentUser.isSupporter || currentUser.isPlusSubscriber {
                                Text("settings.badges.manage")
                            } else {
                                Text("settings.badges.explore")
                            }
                        }
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(Color(hex: "00A896"))
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(SettingsListRowBackground())
    }
}

struct AccountSection: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String

    var body: some View {
        Section("Cuenta") {
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
                destination: AnyView(QRCodeView())
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
}

struct ArchiveSection: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Section("Archivo") {
            SettingsRow(
                icon: "archivebox",
                title: NSLocalizedString("settings.sections.archivedStories", comment: "Archived Stories"),
                subtitle: NSLocalizedString("settings.sections.archivedStories.subtitle", comment: "View all your past stories"),
                destination: AnyView(ArchiveView())
            )
            
            SettingsRow(
                icon: "star",
                title: NSLocalizedString("settings.sections.highlightedStories", comment: "Highlighted Stories"),
                subtitle: NSLocalizedString("settings.sections.highlightedStories.subtitle", comment: "Manage your favorite stories"),
                destination: AnyView(HighlightedStoriesView())
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
}

struct PrivacySection: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isPrivate: Bool
    @Binding var showMutualConnections: Bool
    @Binding var showFollowing: Bool
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section("Privacidad") {
            HStack {
                Image(systemName: "lock.circle")
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.privacy.privateAccount")
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
            .font(.custom("Poppins-Regular", size: 14))
            
            SettingsRow(
                icon: "eye.slash",
                title: NSLocalizedString("settings.sections.contentVisibility", comment: "Content Visibility"),
                subtitle: NSLocalizedString("settings.sections.contentVisibility.subtitle", comment: "Manage who can see your content"),
                destination: AnyView(ContentVisibilityView())
            )
            
            SettingsRow(
                icon: "person.2.circle",
                title: NSLocalizedString("settings.sections.connections", comment: "Connections"),
                subtitle: getConnectionPrivacyStatus(),
                destination: AnyView(ConnectionVisibilityView(
                    showMutualConnections: $showMutualConnections,
                    showFollowing: $showFollowing,
                    viewModel: viewModel
                ))
            )
            
            SettingsRow(
                icon: "person.2.fill",
                title: NSLocalizedString("settings.sections.bestFriends", comment: "Best Friends"),
                subtitle: NSLocalizedString("settings.sections.bestFriends.subtitle", comment: "Manage best friends list"),
                destination: AnyView(BestFriendsView())
            )
            
            SettingsRow(
                icon: "hand.raised",
                title: NSLocalizedString("settings.sections.blockedAccounts", comment: "Blocked Accounts"),
                subtitle: String(format: NSLocalizedString("settings.sections.blockedAccounts.subtitle", comment: "X accounts"), 0),
                destination: AnyView(BlockedUsersView())
            )
            
            SettingsRow(
                icon: "bell.slash",
                title: NSLocalizedString("settings.sections.mute", comment: "Mute"),
                subtitle: NSLocalizedString("settings.sections.mute.subtitle", comment: "Accounts, words and phrases"),
                destination: AnyView(MuteSettingsView())
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
    
    private func getConnectionPrivacyStatus() -> String {
        let hiddenCount = (!showMutualConnections ? 1 : 0) + (!showFollowing ? 1 : 0)
        switch hiddenCount {
        case 0: return "Todas las conexiones públicas"
        case 1: return "1 lista oculta"
        case 2: return "Todas las listas ocultas"
        default: return "Configurar"
        }
    }
}

struct ConnectionVisibilityView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var showMutualConnections: Bool
    @Binding var showFollowing: Bool
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
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
        .listRowBackground(SettingsListRowBackground())
    }
}

struct SecuritySection: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Section("Seguridad") {
            SettingsRow(
                icon: "key",
                title: NSLocalizedString("settings.sections.password", comment: "Password"),
                subtitle: NSLocalizedString("settings.sections.password.subtitle", comment: "Change password"),
                destination: AnyView(PasswordChangeView())
            )
            
            SettingsRow(
                icon: "shield.checkered",
                title: NSLocalizedString("settings.sections.2fa", comment: "Two-Factor Authentication"),
                subtitle: NSLocalizedString("settings.sections.2fa.subtitle", comment: "Add an extra layer of security"),
                destination: AnyView(Text(NSLocalizedString("settings.2fa", comment: "Two-Factor Authentication")).navigationBarBackButtonHidden(true))
            )
            
            SettingsRow(
                icon: "clock.arrow.circlepath",
                title: NSLocalizedString("settings.sections.loginActivity", comment: "Login Activity"),
                subtitle: NSLocalizedString("settings.sections.loginActivity.subtitle", comment: "Review your recent activity"),
                destination: AnyView(LoginActivityView())
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
}

struct ActivitySection: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Section("Tu actividad") {
            SettingsRow(
                icon: "bookmark",
                title: NSLocalizedString("settings.sections.saved", comment: "Saved"),
                subtitle: NSLocalizedString("settings.sections.saved.subtitle", comment: "Moments you've saved"),
                destination: AnyView(SavedMomentsView())
            )
            
            SettingsRow(
                icon: "clock",
                title: NSLocalizedString("settings.sections.yourActivity", comment: "Your Activity"),
                subtitle: NSLocalizedString("settings.sections.yourActivity.subtitle", comment: "Time in app, interactions"),
                destination: AnyView(UserActivityView())
            )
            
            SettingsRow(
                icon: "arrow.down.circle",
                title: NSLocalizedString("settings.sections.downloadData", comment: "Download Your Data"),
                subtitle: NSLocalizedString("settings.sections.downloadData.subtitle", comment: "Request a copy of your data"),
                destination: AnyView(DataExportView())
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
}

struct NotificationsSection: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date

    var body: some View {
        Section("Notificaciones") {
            SettingsRow(
                icon: "bell",
                title: NSLocalizedString("settings.sections.pushNotifications", comment: "Push Notifications"),
                subtitle: NSLocalizedString("settings.sections.pushNotifications.subtitle", comment: "Posts, stories, comments"),
                destination: AnyView(NotificationSettingsView(
                    viewModel: viewModel,
                    isScheduleEnabled: $isScheduleEnabled,
                    startTime: $startTime,
                    endTime: $endTime
                ))
            )
            
            SettingsRow(
                icon: "envelope",
                title: NSLocalizedString("settings.sections.emailNotifications", comment: "Email Notifications"),
                subtitle: NSLocalizedString("settings.sections.emailNotifications.subtitle", comment: "Activity summaries"),
                destination: AnyView(Text(NSLocalizedString("settings.emailNotifications", comment: "Email Notifications")).navigationBarBackButtonHidden(true))
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
}

struct HelpSection: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        Section("Soporte") {
            SettingsRow(
                icon: "questionmark.circle",
                title: NSLocalizedString("settings.sections.helpCenter", comment: "Help Center"),
                subtitle: NSLocalizedString("settings.sections.helpCenter.subtitle", comment: "Get answers to your questions"),
                isExternal: true,
                action: {
                    if let url = URL(string: "https://example.com/support") {
                        UIApplication.shared.open(url)
                    }
                }
            )
            
            SettingsRow(
                icon: "exclamationmark.triangle",
                title: NSLocalizedString("settings.sections.reportProblem", comment: "Report a Problem"),
                subtitle: NSLocalizedString("settings.sections.reportProblem.subtitle", comment: "Let us know if something isn't working"),
                isExternal: true,
                action: {
                    if let url = URL(string: "https://example.com/report") {
                        UIApplication.shared.open(url)
                    }
                }
            )
            
            SettingsRow(
                icon: "doc.text",
                title: NSLocalizedString("settings.sections.termsOfUse", comment: "Terms of Use"),
                subtitle: "",
                isExternal: true,
                action: {
                    if let url = URL(string: "https://example.com/terms") {
                        UIApplication.shared.open(url)
                    }
                }
            )
            
            SettingsRow(
                icon: "hand.raised.circle",
                title: NSLocalizedString("settings.sections.privacyPolicy", comment: "Privacy Policy"),
                subtitle: "",
                isExternal: true,
                action: {
                    if let url = URL(string: "https://example.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .font(.custom("Poppins-Regular", size: 14))
        .listRowBackground(SettingsListRowBackground())
    }
}

struct LogoutSection: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutAlert: Bool = false

    var body: some View {
        Section {
            Button(action: {
                showLogoutAlert = true
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                    
                    Text("settings.logout")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
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
        .listRowBackground(SettingsListRowBackground())
    }
}

// Reemplaza tu SettingsRow existente con esta versión actualizada:

struct SettingsRow: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isPressed = false
    @State private var isHovered = false
    
    let icon: String
    let title: String
    let subtitle: String
    var destination: AnyView? = nil
    var isExternal: Bool = false
    var isDestructive: Bool = false
    var action: (() -> Void)? = nil
    var iconColor: Color? = nil
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Group {
            if let destination = destination {
                NavigationLink(destination: destination) {
                    rowContent
                }
                .buttonStyle(PlainButtonStyle())
            } else if let action = action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                rowContent
            }
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 16) {
            // ✅ Icono con animación y colores mejorados
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: iconColor != nil ? 
                            [iconColor!.opacity(0.2), iconColor!.opacity(0.1)] :
                            [adaptiveColors.accent.opacity(0.2), adaptiveColors.accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isPressed)
                
                Image(systemName: icon)
                    .foregroundColor(
                        isDestructive ? .red :
                        iconColor ?? adaptiveColors.accent
                    )
                    .font(.system(size: 18, weight: .medium))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundColor(
                        isDestructive ? .red : 
                        adaptiveColors.primary
                    )
                    .font(.custom("Poppins-Medium", size: 16))
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundColor(adaptiveColors.tertiary)
                        .font(.custom("Poppins-Regular", size: 13))
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // ✅ Indicadores mejorados con animaciones
            if isExternal {
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(adaptiveColors.accent)
                    .font(.system(size: 14, weight: .medium))
                    .rotationEffect(.degrees(isPressed ? 15 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isPressed)
            } else if destination != nil {
                Image(systemName: "chevron.right")
                    .foregroundColor(adaptiveColors.tertiary)
                    .font(.system(size: 12, weight: .semibold))
                    .offset(x: isPressed ? 3 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isPressed)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .opacity(isPressed ? 0.8 : 0.3)
                .animation(.easeInOut(duration: 0.2), value: isPressed)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: adaptiveColors.overlayStroke,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .opacity(isPressed ? 0.8 : 0.3)
                .animation(.easeInOut(duration: 0.2), value: isPressed)
        )
    }
}


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
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    
    var body: some View {
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
        .navigationBarBackButtonHidden(true) // Ocultar botón de atrás
    }
}

struct SettingsListRowBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color(colorScheme == .dark ? .black : .white).opacity(0.2))
            LinearGradient(
                colors: [Color(colorScheme == .dark ? .white : .black).opacity(0.1), Color(hex: "00A896").opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.overlay)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Online Status Section
struct OnlineStatusSection: View {
    @StateObject private var onlineStatusService = OnlineStatusService()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                
                Text("settings.onlineStatus.title")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(SettingsProfileColors.textPrimary)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Estado actual
                HStack {
                    Image(systemName: onlineStatusService.currentUserStatus.icon)
                        .foregroundColor(onlineStatusService.currentUserStatus.color)
                        .font(.system(size: 16))
                    
                    Text(String(format: NSLocalizedString("settings.onlineStatus.current", comment: "Current status"), onlineStatusService.currentUserStatus.displayName))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(SettingsProfileColors.textSecondary)
                    
                    Spacer()
                }
                
                // Selector de estado
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.onlineStatus.change")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(SettingsProfileColors.textPrimary)
                    
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
                        HStack {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(SettingsProfileColors.accent)
                                .font(.system(size: 16))
                            
                            Text("settings.onlineStatus.select")
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(SettingsProfileColors.textPrimary)
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SettingsProfileColors.cardBackground)
                                .shadow(color: SettingsProfileColors.shadowColor, radius: 2, x: 0, y: 1)
                        )
                    }
                }
                
                // Información adicional
                VStack(alignment: .leading, spacing: 4) {
                                            Text("settings.onlineStatus.info.auto")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(SettingsProfileColors.textSecondary)
                    
                                            Text("settings.onlineStatus.info.conversation")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(SettingsProfileColors.textSecondary)
                    
                                            Text("settings.onlineStatus.info.invisible")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(SettingsProfileColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SettingsProfileColors.cardBackground)
                .shadow(color: SettingsProfileColors.shadowColor, radius: 4, x: 0, y: 2)
        )
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

    func updatePrivacySettings(isPrivate: Bool? = nil, showMutualConnections: Bool? = nil, showFollowing: Bool? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        privacyService.updatePrivacySettings(
            userId: userId,
            isPrivate: isPrivate,
            showMutualConnections: showMutualConnections,
            showFollowing: showFollowing
        ) { error in
            if let error = error {
                print("Error updating privacy settings: \(error)")
            }
        }
    }

    func updateActiveHours(startTime: Date, endTime: Date) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let startHour = dateFormatter.string(from: startTime)
        let endHour = dateFormatter.string(from: endTime)
        firestoreService.updateActiveHours(userId: userId, startHour: startHour, endHour: endHour) { error in
            if let error = error {
                print("Error updating active hours: \(error)")
            }
        }
    }

    func updateNotificationPreference(type: String, isEnabled: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        notificationPreferences[type] = isEnabled
        firestoreService.updateNotificationPreferences(userId: userId, preferences: notificationPreferences) { error in
            if let error = error {
                print("Error updating notification preference: \(error)")
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
