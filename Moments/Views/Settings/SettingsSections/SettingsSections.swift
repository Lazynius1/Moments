import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import UserMessagingPlatform

struct SettingsFormView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isPrivate: Bool
    @Binding var showFollowing: Bool
    @Binding var showFollowers: Bool
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var username: String
    @Binding var email: String
    @Binding var phoneNumber: String
    @Binding var isShowingPersonalInfo: Bool
    @Binding var isShowingQRCode: Bool
    @Binding var route: SettingsRoute?
    @Binding var isShowingAdvancedAccountManagement: Bool
    @Binding var isShowingNovaMemory: Bool
    @Binding var showReadReceipts: Bool
    let blockedAccountsCount: Int

    @State private var animateSections = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                SettingsGroup(title: NSLocalizedString("settings.group.account", comment: "Account")) {
                    ProfileSection(username: $username)

                    AccountSection(
                        username: $username,
                        email: $email,
                        phoneNumber: $phoneNumber,
                        isShowingPersonalInfo: $isShowingPersonalInfo,
                        isShowingQRCode: $isShowingQRCode
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)

                SettingsGroup(title: NSLocalizedString("settings.group.security", comment: "Security")) {
                    SecuritySection(route: $route)
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.1), value: animateSections), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.privacy", comment: "Privacy")) {
                    PrivacySection(
                        isPrivate: $isPrivate,
                        showFollowing: $showFollowing,
                        showFollowers: $showFollowers,
                        viewModel: viewModel,
                        route: $route,
                        showReadReceipts: $showReadReceipts,
                        blockedAccountsCount: blockedAccountsCount
                    )
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.15), value: animateSections), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.content", comment: "Your Content & Activity")) {
                    ActivitySection(
                        route: $route,
                        isShowingNovaMemory: $isShowingNovaMemory
                    )

                    ArchiveSection(route: $route)
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.2), value: animateSections), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.notifications", comment: "Notifications & presence")) {
                    NotificationsSection(
                        viewModel: viewModel,
                        isScheduleEnabled: $isScheduleEnabled,
                        startTime: $startTime,
                        endTime: $endTime,
                        route: $route
                    )

                    OnlineStatusSection()
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.25), value: animateSections), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.data", comment: "Data")) {
                    DataSection(route: $route)
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.3), value: animateSections), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.support", comment: "Support & Legal")) {
                    HelpSection(route: $route)
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.35), value: animateSections), value: animateSections)

                SettingsGroup(title: NSLocalizedString("settings.group.advanced", comment: "Advanced Settings")) {
                    AdvancedAccountSection(
                        isShowingAdvancedAccountManagement: $isShowingAdvancedAccountManagement
                    )

                    LogoutSection()
                }
                .opacity(animateSections ? 1 : 0)
                .offset(y: animateSections ? 0 : 20)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.4), value: animateSections), value: animateSections)

                SettingsVersionFooter()
                    .opacity(animateSections ? 1 : 0)
                    .animation(MotionPolicy.animation(MotionPolicy.Spring.onboarding.delay(0.5), value: animateSections), value: animateSections)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateSections = true
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// Footer: logo por tema + versión de la app (CFBundleShortVersionString)
struct SettingsVersionFooter: View {
    @Environment(\.colorScheme) private var colorScheme

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(colorScheme == .dark ? "SplashLogoDark" : "SplashLogoLight")
                .resizable()
                .scaledToFit()
                .frame(height: 30)

            Text(verbatim: "v\(appVersion)")
                .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.35) : .black.opacity(0.30))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

// Section group: category caption + rows inside a rounded card
struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let content: Content

    private let cardCornerRadius: CGFloat = 18

    private var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.50) : .black.opacity(0.40))
                .tracking(0.4)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(cardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
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
                NavigationLink {
                    destination
                        .momentsFloatingTabBarHidden()
                } label: {
                    rowContent
                }
                .buttonStyle(.momentsPressSubtle)
            } else {
                Button(action: { action?() }) {
                    rowContent
                }
                .buttonStyle(.momentsPressSubtle)
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
                            .foregroundStyle(iconForegroundColor)
                    }
                }
                .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(isDestructive ? .red : (colorScheme == .dark ? .white : .black))

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(.gray)
                    }
                }

                Spacer()

                if isExternal {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.gray.opacity(0.5))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.3))
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
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, alignment: .center)

                    Text(NSLocalizedString("settings.advanced.title", comment: "Advanced"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.3))
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())

                Divider()
                    .opacity(0.2)
                    .padding(.leading, 42)
            }
        }
        .buttonStyle(.momentsPressSubtle)
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
        NavigationStack {
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
            .animation(MotionPolicy.animation(MotionPolicy.Spring.sheet, value: flowDestination), value: flowDestination)
            .interactiveDismissDisabled(isProcessing)
            .navigationDestination(isPresented: $isShowingSessionManagement) {
                LoginActivityView()
            }
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
                                .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                        }
                        .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.62))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("settings.info.deactivate")
                            Text("settings.info.delete")
                            Text("settings.info.reactivate")
                        }
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.58))
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
                        .foregroundStyle(AuthColors.primary(colorScheme))
                        .frame(width: 40, height: 40)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                }
                .buttonStyle(.momentsPressSubtle)

                Spacer()
            }

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(AuthColors.primary(colorScheme))
                    .multilineTextAlignment(.center)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.58))
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
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundStyle(isDestructive ? .red : AuthColors.primary(colorScheme))

                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.54))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuthColors.secondary(colorScheme, opacity: 0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.momentsPressSubtle)
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
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
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
                                .foregroundStyle(Color(hex: "FFD700"))
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
                        .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    // Badges inline
                    if let currentUser = authService.currentUser {
                        if currentUser.isPlusSubscriber {
                            Text(NSLocalizedString("common.pro", comment: "PRO badge"))
                                .font(.system(size: legacyPoppinsSize(10), weight: .bold))
                                .foregroundStyle(.white)
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
                            .foregroundStyle(Color(hex: "FFD700"))

                        Text("settings.plus.active")
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .foregroundStyle(Color(hex: "FFD700"))
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
    @Binding var route: SettingsRoute?

    var body: some View {
        SettingsRow(
            icon: "archivebox",
            title: NSLocalizedString("settings.sections.archivedStories", comment: "Archived Stories"),
            subtitle: NSLocalizedString("settings.sections.archivedStories.subtitle", comment: "View all your past stories"),
            action: { route = .archivedStories }
        )
    }
}

struct PrivacySection: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var isPrivate: Bool
    @Binding var showFollowing: Bool
    @Binding var showFollowers: Bool
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var route: SettingsRoute?
    @Binding var showReadReceipts: Bool
    let blockedAccountsCount: Int

    var body: some View {
        VStack(spacing: 0) {
            // Private Account toggle — plain row with divider
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: isPrivate ? "lock" : "lock.open")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(NSLocalizedString("settings.privacy.privateAccount", comment: "Private account"))
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                        Text(NSLocalizedString("settings.privacy.privateAccount.description", comment: "Private account description"))
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(.gray)
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
                action: { route = .contentVisibility })

            SettingsRow(icon: "person.2.circle",
                title: NSLocalizedString("settings.sections.connections", comment: "Connections"),
                subtitle: getConnectionPrivacyStatus(),
                action: { route = .connections })

            SettingsRow(icon: "hand.raised",
                title: NSLocalizedString("settings.sections.blockedAccounts", comment: "Blocked Accounts"),
                subtitle: blockedAccountsSubtitle(),
                action: { route = .blockedAccounts })

            SettingsRow(icon: "bell.slash",
                title: NSLocalizedString("settings.sections.mute", comment: "Mute"),
                subtitle: NSLocalizedString("settings.sections.mute.subtitle", comment: "Accounts, words and phrases"),
                action: { route = .mute })

            MessageRequestPolicyRow(viewModel: viewModel)

            // Read Receipts toggle — plain row, no divider at bottom (last item)
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("settings.privacy.readReceipts.title", comment: "Read receipts"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    Text(NSLocalizedString("settings.privacy.readReceipts.description", comment: "Read receipts description"))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.gray)
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
        let hiddenCount = (!showFollowing ? 1 : 0) + (!showFollowers ? 1 : 0)
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

struct MessageRequestPolicyRow: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: SettingsViewModel
    @State private var policy: MessageRequestPolicy = .everyone
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("settings.privacy.messageRequests.title", comment: "Message requests"))
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    Text(NSLocalizedString("settings.privacy.messageRequests.description", comment: "Who can send you message requests"))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Menu {
                    ForEach(MessageRequestPolicy.allCases, id: \.rawValue) { option in
                        Button {
                            guard option != policy else { return }
                            policy = option
                            viewModel.updateMessageRequestPolicy(option)
                        } label: {
                            if option == policy {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(policy.displayName)
                            .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.gray)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)

            Divider().opacity(0.2).padding(.leading, 42)
        }
        .onAppear(perform: loadPolicyIfNeeded)
    }

    private func loadPolicyIfNeeded() {
        guard !hasLoaded, let userId = Auth.auth().currentUser?.uid else { return }
        hasLoaded = true
        Firestore.firestore().collection("users").document(userId).getDocument { snapshot, _ in
            let raw = snapshot?.data()?["messageRequestPolicy"] as? String
            if let loaded = raw.flatMap(MessageRequestPolicy.init(rawValue:)) {
                policy = loaded
            }
        }
    }
}

struct ConnectionVisibilityView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Binding var showFollowing: Bool
    @Binding var showFollowers: Bool
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        Text("settings.privacy.control.title")
                            .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                            .foregroundStyle(.gray)

                        VStack(spacing: 0) {
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
                                title: "settings.privacy.hideFollowers",
                                description: "settings.privacy.hideFollowers.description",
                                isOn: Binding(
                                    get: { !showFollowers },
                                    set: { newValue in
                                        showFollowers = !newValue
                                        viewModel.updatePrivacySettings(showFollowers: !newValue)
                                        let impact = UIImpactFeedbackGenerator(style: .light)
                                        impact.impactOccurred()
                                    }
                                )
                            )
                        }

                        Text("settings.privacy.control.description")
                            .font(.system(size: legacyPoppinsSize(11)))
                            .foregroundStyle(.gray.opacity(0.8))
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
        .navigationInteractivePopEnabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .momentsScrollEdgeChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
    }

    private func privacyToggleRow(title: LocalizedStringKey, description: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "eye.slash")
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                Text(description)
                    .foregroundStyle(.gray)
                    .font(.system(size: legacyPoppinsSize(12)))
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
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("settings.security.appleId")
                            .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        Text("settings.security.appleId.description")
                            .font(.system(size: legacyPoppinsSize(12)))
                            .foregroundStyle(.gray)
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
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text(subtitle)
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.gray)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isConfigured {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "34C759"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.gray.opacity(0.3))
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
                .buttonStyle(.momentsPressSubtle)
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
    @Binding var route: SettingsRoute?

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
                    route = .passwordChange
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
                route = .passwordChange
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
    @Binding var route: SettingsRoute?
    @Binding var isShowingNovaMemory: Bool

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: AttachmentIcon.bookmark.rawValue,
                title: NSLocalizedString("settings.sections.saved", comment: "Saved"),
                subtitle: NSLocalizedString("settings.sections.saved.subtitle", comment: "Moments you've saved"),
                action: { route = .savedMoments })

            SettingsRow(icon: "clock",
                title: NSLocalizedString("settings.sections.yourActivity", comment: "Your Activity"),
                subtitle: NSLocalizedString("settings.sections.yourActivity.subtitle", comment: "Time in app, interactions"),
                action: { route = .userActivity })

            SettingsRow(
                icon: "star.fill",
                audienceIcon: .bestFriends,
                title: NSLocalizedString("settings.sections.bestFriends", comment: "Best Friends"),
                subtitle: NSLocalizedString("settings.sections.bestFriends.subtitle", comment: "Manage best friends list"),
                action: { route = .bestFriends }
            )

            SettingsRow(icon: "brain.head.profile",
                title: NSLocalizedString("nova.memory.title", comment: "Nova's Memory"),
                subtitle: NSLocalizedString("nova.memory.description", comment: "Manage what Nova knows about you"),
                action: { isShowingNovaMemory = true })
        }
    }
}

/// Gestión de datos: exportación y almacenamiento local.
struct DataSection: View {
    @Binding var route: SettingsRoute?

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "arrow.down.circle",
                title: NSLocalizedString("settings.sections.downloadData", comment: "Download Your Data"),
                subtitle: NSLocalizedString("settings.sections.downloadData.subtitle", comment: "Request a copy of your data"),
                action: { route = .dataExport })

            SettingsRow(icon: "bubble.left.and.bubble.right",
                title: NSLocalizedString("settings.sections.chatStorage", comment: "Chat Storage"),
                subtitle: NSLocalizedString("settings.sections.chatStorage.subtitle", comment: "Media cache and download preferences"),
                action: { route = .chatStorage })
        }
    }
}

struct NotificationsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isScheduleEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var route: SettingsRoute?

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "bell",
                title: NSLocalizedString("settings.sections.pushNotifications", comment: "Push Notifications"),
                subtitle: NSLocalizedString("settings.sections.pushNotifications.subtitle", comment: "Posts, stories, comments"),
                action: { route = .notificationSettings })

            SettingsRow(icon: "envelope",
                title: NSLocalizedString("settings.sections.emailNotifications", comment: "Email Notifications"),
                subtitle: NSLocalizedString("settings.sections.emailNotifications.subtitle", comment: "Activity summaries"),
                action: {})
        }
    }
}

struct HelpSection: View {
    @Binding var route: SettingsRoute?
    @State private var requiresPrivacyOptions = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "checklist",
                title: NSLocalizedString("settings.sections.contentReviews", comment: "Content reviews"),
                subtitle: NSLocalizedString("settings.sections.contentReviews.subtitle", comment: "Check the status of your content review requests"),
                action: { route = .moderationReviews })

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
                    .foregroundStyle(.red)
                    .frame(width: 28, alignment: .center)

                Text(NSLocalizedString("settings.logout", comment: "Log out"))
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(.red)

                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.momentsPressSubtle)
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
