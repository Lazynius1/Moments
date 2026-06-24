import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import UserMessagingPlatform

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
    @Binding var isShowingModerationReviews: Bool
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
                    HelpSection(isShowingModerationReviews: $isShowingModerationReviews)
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
    /// Icono de audiencia en asset catalog (p. ej. Mejores amigos).
    var audienceIcon: ContentAudience? = nil
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
                Group {
                    if let audienceIcon {
                        AudienceIconView(
                            audience: audienceIcon,
                            size: AudienceIconMetrics.row,
                            tintColor: audienceIcon == .bestFriends ? Color(hex: "34C759") : nil,
                            colorScheme: colorScheme
                        )
                    } else if let attachmentIcon = AttachmentIcon(rawValue: icon) {
                        AttachmentIconView(icon: attachmentIcon, preset: .settingsRow, tintColor: iconForegroundColor)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundColor(iconForegroundColor)
                    }
                }
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

struct AdvancedAccountManagementView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService

    private enum FlowDestination: Equatable {
        case main
        case deleteAccount
    }

    @State private var flowDestination: FlowDestination = .main
    @State private var navigatingForward = true
    @State private var isShowingSessionManagement = false
    @State private var showDeactivateConfirmation = false
    @State private var isProcessing = false
    @State private var deletePasswordErrorMessage: String?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if flowDestination == .main {
                advancedMainContent
                    .transition(flowTransition)
            } else {
                DeleteAccountVerificationView(
                    isProcessing: $isProcessing,
                    passwordErrorMessage: $deletePasswordErrorMessage,
                    onConfirm: deleteAccount(confirmation:),
                    onCancel: { navigate(to: .main, forward: false) }
                )
                .environmentObject(authService)
                .transition(flowTransition)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: flowDestination)
        .interactiveDismissDisabled(isProcessing)
        .alert(NSLocalizedString("accountManagement.deactivate.title", comment: "Deactivate account"), isPresented: $showDeactivateConfirmation) {
            Button(NSLocalizedString("accountManagement.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("accountManagement.deactivate", comment: "Deactivate"), role: .destructive) {
                deactivateAccount()
            }
        } message: {
            Text(NSLocalizedString("accountManagement.deactivate.message", comment: "Deactivate account message"))
        }
        .alert(NSLocalizedString("accountManagement.error.title", comment: "Error"), isPresented: $showError) {
            Button(NSLocalizedString("accountManagement.ok", comment: "OK")) {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .fullScreenCover(isPresented: $isShowingSessionManagement) {
            LoginActivityView()
        }
    }

    private var advancedMainContent: some View {
        VStack(spacing: 0) {
            AdvancedSheetHeader(
                title: NSLocalizedString("settings.advanced.title", comment: "Advanced"),
                subtitle: NSLocalizedString("settings.dangerZone.warning", comment: "Danger zone warning"),
                leadingIcon: "chevron.down",
                onLeadingTap: { dismiss() }
            )
            .padding(.horizontal, 22)
            .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        AdvancedAccountActionRow(
                            icon: "clock.arrow.circlepath",
                            title: NSLocalizedString("settings.sections.loginActivity", comment: "Login Activity"),
                            subtitle: NSLocalizedString("settings.sections.loginActivity.subtitle", comment: "Review your recent activity"),
                            action: { isShowingSessionManagement = true }
                        )

                        AdvancedAccountActionRow(
                            icon: "pause",
                            title: NSLocalizedString("accountManagement.deactivate.title", comment: "Deactivate account title"),
                            subtitle: NSLocalizedString("accountManagement.deactivate.subtitle", comment: "Deactivate account subtitle"),
                            action: { showDeactivateConfirmation = true }
                        )

                        AdvancedAccountActionRow(
                            icon: "trash",
                            title: NSLocalizedString("accountManagement.deleteAccount.title", comment: "Delete account"),
                            subtitle: NSLocalizedString("accountManagement.delete.subtitle", comment: "Delete account subtitle"),
                            isDestructive: true,
                            action: { navigate(to: .deleteAccount) }
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13, weight: .medium))
                            Text("settings.info.title")
                                .font(.custom("Poppins-SemiBold", size: 12))
                        }
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("settings.info.deactivate")
                            Text("settings.info.delete")
                            Text("settings.info.reactivate")
                        }
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.58))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var flowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func navigate(to destination: FlowDestination, forward: Bool = true) {
        navigatingForward = forward
        deletePasswordErrorMessage = nil
        flowDestination = destination
    }

    private func deactivateAccount() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isProcessing = true

        AccountManagementService().deactivateAccount(userId: userId) { result in
            DispatchQueue.main.async {
                isProcessing = false

                switch result {
                case .success:
                    authService.logout()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func deleteAccount(confirmation: AccountDeletionConfirmation) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = NSLocalizedString("accountManagement.userNotFound", comment: "User not found error")
            showError = true
            return
        }

        isProcessing = true
        deletePasswordErrorMessage = nil

        AccountManagementService().deleteAccount(user: user, confirmation: confirmation) { result in
            DispatchQueue.main.async {
                isProcessing = false

                switch result {
                case .success:
                    dismiss()
                    authService.logout()
                case .failure(let error):
                    if let passwordError = AccountDeletionErrorPresenter.passwordMessage(for: error) {
                        deletePasswordErrorMessage = passwordError
                    } else {
                        errorMessage = String(format: NSLocalizedString("accountManagement.error.delete", comment: "Error deleting account"), error.localizedDescription)
                        showError = true
                    }
                }
            }
        }
    }
}

private struct AdvancedSheetHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let leadingIcon: String
    let onLeadingTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                Button(action: onLeadingTap) {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AuthColors.primary(colorScheme))
                        .frame(width: 40, height: 40)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(spacing: 5) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .multilineTextAlignment(.center)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.58))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 56)
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct AdvancedAccountActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String
    var isDestructive: Bool = false
    let action: () -> Void

    private var accent: Color {
        isDestructive ? .red : AuthColors.primary(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(isDestructive ? .red : AuthColors.primary(colorScheme))

                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.54))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 34, height: 34)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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
                            Text(NSLocalizedString("common.pro", comment: "PRO badge"))
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
                        .tint(SettingsProfileColors.toggleTint)
                        .onChange(of: isPrivate) { _, newValue in
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

            SettingsRow(
                icon: "star.fill",
                audienceIcon: .bestFriends,
                title: NSLocalizedString("settings.sections.bestFriends", comment: "Best Friends"),
                subtitle: NSLocalizedString("settings.sections.bestFriends.subtitle", comment: "Manage best friends list"),
                action: { isShowingBestFriends = true }
            )

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
                    .tint(SettingsProfileColors.toggleTint)
                    .onChange(of: showReadReceipts) { _, newValue in
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
        .settingsSwitchTint()
        .navigationTitle(NSLocalizedString("settings.connectionPrivacy", comment: "Connection Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Ocultar botón de atrás
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
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
                .labelsHidden()
                .tint(SettingsProfileColors.toggleTint)
        }
        .padding(.vertical, 11)
    }
}

private struct AppleLinkSettingsRow: View {
    @EnvironmentObject private var authService: AuthService

    let colorScheme: ColorScheme
    let isLoading: Bool
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("settings.security.appleId")
                            .font(.custom("Poppins-Medium", size: 15))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("settings.security.appleId.description")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                Group {
                    if colorScheme == .dark {
                        appleLinkButton(style: .white)
                    } else {
                        appleLinkButton(style: .black)
                    }
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(isLoading)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)

            Divider()
                .opacity(0.2)
                .padding(.leading, 42)
        }
    }

    private func appleLinkButton(style: SignInWithAppleButton.Style) -> some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = authService.startAppleSignIn()
            request.requestedScopes = [.fullName, .email]
            request.nonce = nonce
        } onCompletion: { result in
            onCompletion(result)
        }
        .signInWithAppleButtonStyle(style)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SecurityStatusRow<OverlayView: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isConfigured: Bool
    let isLoading: Bool
    let usesOverlayForInteraction: Bool
    let action: (() -> Void)?
    let overlayView: OverlayView

    private var rowBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.custom("Poppins-Medium", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text(subtitle)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isConfigured {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "34C759"))
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

    var body: some View {
        Group {
            if !isConfigured && usesOverlayForInteraction {
                rowBody
                    .overlay {
                        overlayView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
            } else if let action {
                Button(action: action) {
                    rowBody
                }
                .buttonStyle(.plain)
            } else {
                rowBody
            }
        }
        .disabled(isLoading)
    }
}

struct SecuritySection: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var authService: AuthService
    @Binding var isShowingPasswordChange: Bool

    // Para el linking
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var alertTitle: String = "common.error"
    @State private var showAlert = false
    @State private var showChatRecoverySettings = false
    @State private var showUnlinkAppleConfirmation = false
    @State private var showAppleOnlyAccessInfo = false
    @State private var hasPasskey = false

    private var appleIdSubtitle: LocalizedStringKey {
        if authService.isAppleLinked {
            if authService.isAppleOnlyAccess {
                return "settings.security.appleId.onlyMethod"
            }
            return authService.canUnlinkApple
                ? "settings.security.appleId.unlinkHint"
                : "settings.security.appleId.linked"
        }
        return "settings.security.appleId.description"
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "key",
                title: authService.isPasswordLinked
                    ? NSLocalizedString("settings.sections.password", comment: "Password")
                    : NSLocalizedString("settings.security.password.add", comment: "Add password"),
                subtitle: authService.isPasswordLinked
                    ? NSLocalizedString("settings.sections.password.subtitle", comment: "Change password")
                    : NSLocalizedString("settings.security.password.addDescription", comment: "Add backup password"),
                action: {
                    isShowingPasswordChange = true
                }
            )

            SettingsRow(
                icon: "lock.rotation",
                title: NSLocalizedString("chatRecovery.settings.rowTitle", comment: "Chat recovery PIN"),
                subtitle: NSLocalizedString("chatRecovery.settings.rowSubtitle", comment: "Restore encrypted chats after reinstalling the app"),
                action: { showChatRecoverySettings = true }
            )

            // Vincular / gestionar Apple ID
            if authService.isAppleLinked {
                SecurityStatusRow(
                    icon: "applelogo",
                    title: "settings.security.appleId",
                    subtitle: appleIdSubtitle,
                    isConfigured: true,
                    isLoading: isLoading,
                    usesOverlayForInteraction: false,
                    action: {
                        if authService.canUnlinkApple {
                            showUnlinkAppleConfirmation = true
                        } else {
                            showAppleOnlyAccessInfo = true
                        }
                    },
                    overlayView: EmptyView()
                )
            } else {
                AppleLinkSettingsRow(
                    colorScheme: colorScheme,
                    isLoading: isLoading,
                    onCompletion: handleAppleLinkingResult
                )
            }

            // ✅ NUEVO: Registro de Passkey
            SecurityStatusRow(
                icon: "faceid",
                title: "login.passkey",
                subtitle: hasPasskey ? "settings.security.passkey.generated" : "settings.security.passkey.description",
                isConfigured: hasPasskey,
                isLoading: isLoading,
                usesOverlayForInteraction: false,
                action: hasPasskey ? nil : {
                    isLoading = true
                    PasskeyService.shared.registerPasskey { result in
                        DispatchQueue.main.async {
                            isLoading = false
                            switch result {
                            case .success:
                                let impact = UINotificationFeedbackGenerator()
                                impact.notificationOccurred(.success)
                                if let uid = Auth.auth().currentUser?.uid {
                                    UserDefaults.standard.set(true, forKey: "hasPasskey_\(uid)")
                                }
                                hasPasskey = true
                                alertTitle = "common.success"
                                errorMessage = NSLocalizedString("settings.security.passkey.success", comment: "Passkey registered successfully")
                                showAlert = true
                            case .failure(let error):
                                if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                                    return
                                }
                                alertTitle = "common.error"
                                errorMessage = error.localizedDescription
                                showAlert = true
                            }
                        }
                    }
                },
                overlayView: EmptyView()
            )
        }
        .onAppear {
            authService.refreshLinkedProviders()
            if let uid = Auth.auth().currentUser?.uid {
                let localHasPasskey = UserDefaults.standard.bool(forKey: "hasPasskey_\(uid)")
                hasPasskey = localHasPasskey

                // Solo consultamos a Firebase si localmente no consta que tenga Passkey.
                // Así ahorramos lecturas de base de datos.
                if !localHasPasskey {
                    Firestore.firestore().collection("users").document(uid).collection("passkeys").limit(to: 1).getDocuments { snapshot, error in
                        if error != nil {
                            return
                        }
                        let found = !(snapshot?.isEmpty ?? true)
                        if found {
                            DispatchQueue.main.async {
                                hasPasskey = true
                            }
                            UserDefaults.standard.set(true, forKey: "hasPasskey_\(uid)")
                        }
                    }
                }
            }
        }
        .alert(NSLocalizedString(alertTitle, comment: ""), isPresented: $showAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage ?? NSLocalizedString("comments.error.unknown", comment: "Unknown error"))
        }
        .alert("settings.security.appleId.unlink.title", isPresented: $showUnlinkAppleConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("settings.security.appleId.unlink.confirm", role: .destructive) {
                unlinkAppleId()
            }
        } message: {
            Text("settings.security.appleId.unlink.message")
        }
        .alert("settings.security.appleId.cannotUnlink.title", isPresented: $showAppleOnlyAccessInfo) {
            Button("common.ok", role: .cancel) {}
            Button("settings.security.password.add") {
                isShowingPasswordChange = true
            }
        } message: {
            Text("settings.security.appleId.cannotUnlink.message")
        }
        .sheet(isPresented: $showChatRecoverySettings) {
            ChatRecoverySettingsView()
        }
    }

    private func unlinkAppleId() {
        isLoading = true
        authService.unlinkFromApple { result in
            isLoading = false
            switch result {
            case .success:
                let impact = UINotificationFeedbackGenerator()
                impact.notificationOccurred(.success)
                alertTitle = "common.success"
                errorMessage = NSLocalizedString("settings.security.appleId.unlink.success", comment: "Apple ID unlinked successfully")
                showAlert = true
            case .failure(let error):
                alertTitle = "common.error"
                errorMessage = error.localizedDescription
                showAlert = true
            }
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
                        let impact = UINotificationFeedbackGenerator()
                        impact.notificationOccurred(.success)
                    case .failure(let error):
                        alertTitle = "common.error"
                        errorMessage = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            alertTitle = "common.error"
            errorMessage = error.localizedDescription
            showAlert = true
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
            SettingsRow(icon: AttachmentIcon.bookmark.rawValue,
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
    @Binding var isShowingModerationReviews: Bool
    @State private var requiresPrivacyOptions = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "checklist",
                title: NSLocalizedString("settings.sections.contentReviews", comment: "Content reviews"),
                subtitle: NSLocalizedString("settings.sections.contentReviews.subtitle", comment: "Check the status of your content review requests"),
                action: { isShowingModerationReviews = true })

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

            // ✅ NUEVO: Botón para gestionar el consentimiento de anuncios (UMP / GDPR)
            if requiresPrivacyOptions {
                SettingsRow(icon: "shield.righthalf.filled",
                    title: NSLocalizedString("settings.sections.adPrivacy", comment: "Ad Privacy & Consent"),
                    subtitle: NSLocalizedString("settings.sections.adPrivacy.subtitle", comment: "Manage your advertising preferences"),
                    action: {
                        AdMobConfiguration.shared.showPrivacyOptionsForm()
                    })
            }
        }
        .onAppear {
            // Actualizar el estado al cargar la vista
            requiresPrivacyOptions = UserMessagingPlatform.ConsentInformation.shared.privacyOptionsRequirementStatus == .required
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
        .alert("settings.logout.alert.title", isPresented: $showLogoutAlert) {
            Button("settings.logout.alert.cancel", role: .cancel) {}
            Button("settings.logout.alert.confirm", role: .destructive) {
                authService.logout()
                dismiss()
            }
        } message: {
            Text("settings.logout.alert.message")
        }
    }
}
