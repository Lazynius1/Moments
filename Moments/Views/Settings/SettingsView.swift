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
            .onChange(of: authService.currentFirebaseUser) { user in
                guard user == nil else { return }
                isLoading = false
                showError = false
                errorMessage = nil
                dismiss()
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("settings.error.title"),
                    message: Text(errorMessage ?? NSLocalizedString("settings.error.unknown", comment: "Unknown settings error")),
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
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
