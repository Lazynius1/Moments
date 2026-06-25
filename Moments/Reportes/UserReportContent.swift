import SwiftUI
import FirebaseAuth

struct UserReportContent: View {
    let reportedUserId: String
    let reportedUsername: String?
    let onBack: () -> Void
    let onDismiss: () -> Void

    @State private var selectedReason: UserReportReason?
    @State private var additionalDetails: String = ""
    @State private var isSubmitting = false
    @State private var showSuccessMessage = false
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.9)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.58)
    }

    private var reportTitle: String {
        if let username = reportedUsername, !username.isEmpty {
            return String(format: NSLocalizedString("report.user.title.username", comment: "Report username title"), username)
        }
        return NSLocalizedString("report.user.title", comment: "Report account title")
    }

    var body: some View {
        VStack(spacing: 0) {
            NativeReportSheetHeader(title: reportTitle, onBack: onBack)

            if showSuccessMessage {
                successView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(NSLocalizedString("report.user.subtitle", comment: "Report account subtitle"))
                            .font(.system(size: legacyPoppinsSize(15)))
                            .foregroundColor(secondaryText)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)

                        NativeReportOptionsSection {
                            ForEach(Array(UserReportReason.allCases.enumerated()), id: \.element) { index, reason in
                                NativeReportOptionRow(
                                    icon: reason.icon,
                                    title: reason.title,
                                    subtitle: reason.subtitle,
                                    isSelected: selectedReason == reason,
                                    showsChevron: selectedReason != reason
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedReason = reason
                                    }
                                }

                                if index < UserReportReason.allCases.count - 1 {
                                    NativeReportDivider()
                                }
                            }
                        }

                        if selectedReason != nil {
                            NativeReportDetailsSection(
                                title: NSLocalizedString("report.user.additionalDetails", comment: "User report additional details"),
                                placeholder: NSLocalizedString("report.detailsPlaceholder", comment: "Details placeholder text"),
                                text: $additionalDetails
                            )
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if selectedReason != nil {
                        NativeReportSubmitBar(
                            isSubmitting: isSubmitting,
                            title: NSLocalizedString("report.sendButton", comment: "Send report button"),
                            action: submitReport
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString("report.success.title", comment: "Report success title"))
                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                    .foregroundColor(primaryText)

                Text(NSLocalizedString("report.success.message", comment: "Report success message"))
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onDismiss()
            }
        }
    }

    private func submitReport() {
        guard let reason = selectedReason,
              let currentUserId = Auth.auth().currentUser?.uid else { return }

        isSubmitting = true

        let description = additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await LocalPersistenceService.shared.reportContent(
                reporterId: currentUserId,
                reportedUserId: reportedUserId,
                reportedContentType: "user",
                reportedContentId: reportedUserId,
                category: reason.rawValue,
                description: description,
                priority: reason.priority.rawValue
            )

            await MainActor.run {
                isSubmitting = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showSuccessMessage = true
                }
            }
        }
    }
}

enum UserReportReason: String, CaseIterable {
    case inappropriateContent = "account_inappropriate_content"
    case impersonation = "account_impersonation"
    case underage = "account_underage"
    case bullying = "account_bullying_contact"
    case scam = "account_scam_spam"

    var icon: String {
        switch self {
        case .inappropriateContent:
            return "exclamationmark.bubble"
        case .impersonation:
            return "person.crop.circle.badge.exclamationmark"
        case .underage:
            return "figure.child"
        case .bullying:
            return "hand.raised"
        case .scam:
            return "exclamationmark.shield"
        }
    }

    var title: String {
        switch self {
        case .inappropriateContent:
            return NSLocalizedString("report.user.reason.inappropriate.title", comment: "Inappropriate account content")
        case .impersonation:
            return NSLocalizedString("report.user.reason.impersonation.title", comment: "Impersonation")
        case .underage:
            return NSLocalizedString("report.user.reason.underage.title", comment: "Underage user")
        case .bullying:
            return NSLocalizedString("report.user.reason.bullying.title", comment: "Bullying or unwanted contact")
        case .scam:
            return NSLocalizedString("report.user.reason.scam.title", comment: "Scam or spam")
        }
    }

    var subtitle: String {
        switch self {
        case .inappropriateContent:
            return NSLocalizedString("report.user.reason.inappropriate.subtitle", comment: "Inappropriate content subtitle")
        case .impersonation:
            return NSLocalizedString("report.user.reason.impersonation.subtitle", comment: "Impersonation subtitle")
        case .underage:
            return NSLocalizedString("report.user.reason.underage.subtitle", comment: "Underage subtitle")
        case .bullying:
            return NSLocalizedString("report.user.reason.bullying.subtitle", comment: "Bullying subtitle")
        case .scam:
            return NSLocalizedString("report.user.reason.scam.subtitle", comment: "Scam subtitle")
        }
    }

    var priority: ReportPriority {
        switch self {
        case .underage:
            return .high
        case .impersonation, .bullying, .scam:
            return .medium
        case .inappropriateContent:
            return .low
        }
    }
}
