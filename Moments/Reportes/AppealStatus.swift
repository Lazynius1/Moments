import SwiftUI

struct AppealStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var authService: AuthService
    @StateObject private var appealService = AppealService.shared
    @State private var appeals: [AppealStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedAppeal: AppealStatus?
    @State private var refreshing = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.clear.ignoresSafeArea()

                VStack(spacing: 0) {
                    AppealStatusHeader(
                        title: selectedAppeal == nil ? NSLocalizedString("appeal.status.title", comment: "My appeals navigation title") : NSLocalizedString("appeal.detail.title", comment: "Appeal detail title"),
                        showsBackButton: selectedAppeal != nil,
                        showsRefreshButton: selectedAppeal == nil,
                        refreshing: refreshing,
                        onBack: {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                selectedAppeal = nil
                            }
                        },
                        onRefresh: fetchAppeals
                    )

                    ZStack {
                        if let selectedAppeal {
                            AppealDetailFlowView(appeal: selectedAppeal)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            Group {
                                if isLoading {
                                    LoadingView()
                                } else if appeals.isEmpty {
                                    EmptyAppealsView()
                                } else {
                                    AppealsListView(
                                        appeals: appeals,
                                        selectedAppeal: $selectedAppeal,
                                        refreshing: $refreshing,
                                        onRefresh: fetchAppeals
                                    )
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarHidden(true)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: selectedAppeal?.id)
        .onAppear {
            fetchAppeals()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Error desconocido")
        }
    }

    private func fetchAppeals() {
        guard let userId = authService.currentFirebaseUser?.uid else { return }

        if !refreshing {
            isLoading = true
        }
        refreshing = true

        Task {
            do {
                let fetchedAppeals = try await appealService.fetchUserAppeals(userId: userId)

                await MainActor.run {
                    self.appeals = fetchedAppeals
                    self.isLoading = false
                    self.refreshing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.refreshing = false
                }
            }
        }
    }
}

// MARK: - Appeal Status Header
struct AppealStatusHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let showsBackButton: Bool
    let showsRefreshButton: Bool
    let refreshing: Bool
    let onBack: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AuthColors.primary(colorScheme))
                .lineLimit(1)

            HStack {
                if showsBackButton {
                    glassIconButton(systemName: "chevron.left", action: onBack)
                } else {
                    Color.clear
                        .frame(width: 42, height: 42)
                }

                Spacer()

                if showsRefreshButton {
                    refreshButton
                } else {
                    Color.clear
                        .frame(width: 42, height: 42)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var refreshButton: some View {
        Button {
            guard !refreshing else { return }
            onRefresh()
        } label: {
            ZStack {
                Color.clear
                    .momentsChromeGlass(in: Circle())

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(refreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: refreshing)
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
    }

    private func glassIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AuthColors.primary(colorScheme))
                .frame(width: 42, height: 42)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle(), interactive: true)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appeals List View
struct AppealsListView: View {
    let appeals: [AppealStatus]
    @Binding var selectedAppeal: AppealStatus?
    @Binding var refreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(appeals, id: \.id) { appeal in
                    AppealCard(appeal: appeal) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            selectedAppeal = appeal
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            onRefresh()
        }
    }
}

// MARK: - Appeal Card
struct AppealCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let appeal: AppealStatus
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(String(format: NSLocalizedString("appeal.status.ticket", comment: "Ticket number format"), appeal.ticketNumber))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AuthColors.primary(colorScheme))

                        Text(appeal.submittedAt)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))
                    }

                    AppealStatusBadge(status: appeal.status, priority: appeal.priority)

                    if let reason = appeal.suspensionReason, !reason.isEmpty {
                        Text(String(format: NSLocalizedString("appeal.status.reason", comment: "Suspension reason format"), reason))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                            .lineLimit(2)
                    }

                    Text(String(format: NSLocalizedString("appeal.status.estimatedResponse", comment: "Estimated response format"), appeal.estimatedResponseTime))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.45))
            }
            .padding(18)
            .background(
                Color.clear
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AuthColors.primary(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.08), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Appeal Status Badge
struct AppealStatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: String
    let priority: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 12, weight: .semibold))

            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Color.clear
                .momentsChromeGlass(in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(statusColor.opacity(colorScheme == .dark ? 0.28 : 0.18), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusIcon: String {
        switch status {
        case "pending": return "clock"
        case "reviewing": return "eye"
        case "approved": return "checkmark.circle"
        case "denied": return "xmark.circle"
        case "requires_info": return "questionmark.circle"
        default: return "circle"
        }
    }

    private var statusText: String {
        switch status {
        case "pending": return NSLocalizedString("appeal.status.pending", comment: "Pending appeal status")
        case "reviewing": return NSLocalizedString("appeal.status.reviewing", comment: "Reviewing appeal status")
        case "approved": return NSLocalizedString("appeal.status.approved", comment: "Approved appeal status")
        case "denied": return NSLocalizedString("appeal.status.denied", comment: "Denied appeal status")
        case "requires_info": return NSLocalizedString("appeal.status.requiresInfo", comment: "Requires more information appeal status")
        default: return status.capitalized
        }
    }

    private var statusColor: Color {
        switch status {
        case "approved": return .green
        case "denied": return .red
        case "requires_info": return .orange
        default: return AuthColors.primary(colorScheme)
        }
    }
}

// MARK: - Appeal Detail Flow View
struct AppealDetailFlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let appeal: AppealStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(format: NSLocalizedString("appeal.status.ticket", comment: "Ticket number format"), appeal.ticketNumber))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AuthColors.primary(colorScheme))

                    AppealStatusBadge(status: appeal.status, priority: appeal.priority)

                    if !appeal.statusDescription.isEmpty {
                        Text(appeal.statusDescription)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.74))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 12)

                VStack(spacing: 18) {
                    AppealDetailLine(
                        title: NSLocalizedString("appeal.status.submitted", comment: "Submitted label"),
                        value: appeal.submittedAt
                    )

                    AppealDetailLine(
                        title: NSLocalizedString("appeal.detail.estimatedTime", comment: "Estimated time label"),
                        value: appeal.estimatedResponseTime
                    )

                    if let reason = appeal.suspensionReason, !reason.isEmpty {
                        AppealDetailLine(
                            title: NSLocalizedString("appeal.detail.suspensionReason", comment: "Suspension reason label"),
                            value: reason
                        )
                    }

                    if let moderatorNotes = appeal.moderatorNotes, !moderatorNotes.isEmpty {
                        AppealDetailLine(
                            title: NSLocalizedString("appeal.detail.moderatorNotes", comment: "Moderator notes label"),
                            value: moderatorNotes
                        )
                    }
                }

                AppealTextSection(
                    title: NSLocalizedString("appeal.detail.yourMessage", comment: "User appeal message section title"),
                    text: appeal.appealMessage
                )

                if let additionalInfo = appeal.additionalInfo, !additionalInfo.isEmpty {
                    AppealTextSection(
                        title: NSLocalizedString("appeal.detail.additionalInfo", comment: "Additional information section title"),
                        text: additionalInfo
                    )
                }

                if !appeal.nextSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(NSLocalizedString("appeal.detail.nextSteps", comment: "Next steps section title"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AuthColors.primary(colorScheme))

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(appeal.nextSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AuthColors.primary(colorScheme))
                                        .frame(width: 24, height: 24)
                                        .background {
                                            Color.clear
                                                .momentsChromeGlass(in: Circle())
                                        }

                                    Text(step)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.76))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
    }
}

struct AppealDetailLine: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))

            Text(value)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AuthColors.primary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(colorScheme == .dark ? 0.18 : 0.12)
                .padding(.top, 6)
        }
    }
}

struct AppealTextSection: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AuthColors.primary(colorScheme))

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.76))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Empty Appeals View
struct EmptyAppealsView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.58))

            VStack(spacing: 12) {
                Text(NSLocalizedString("appeal.status.noAppeals.title", comment: "No appeals title"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AuthColors.primary(colorScheme))

                Text(NSLocalizedString("appeal.status.noAppeals.description", comment: "No appeals description"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AuthColors.primary(colorScheme)))
                .scaleEffect(1.5)

            Text(NSLocalizedString("appeal.status.loading", comment: "Loading appeals text"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
        }
    }
}

// MARK: - Data Models
struct AppealStatus: Identifiable {
    let id: String
    let ticketNumber: String
    let status: String
    let priority: String
    let appealMessage: String
    let additionalInfo: String?
    let contactEmail: String
    let suspensionReason: String?
    let suspensionDate: String?
    let suspensionExpiry: String?
    let submittedAt: String
    let reviewedAt: String?
    let resolvedAt: String?
    let moderatorId: String?
    let moderatorNotes: String?
    let estimatedResponseTime: String
    let nextSteps: [String]
    let statusDescription: String
}
