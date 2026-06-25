import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ModernReportContent: View {
    let moment: Moment?
    let story: Story?
    let reportedUserId: String?
    let reportedUsername: String?
    
    let onBack: () -> Void
    let onDismiss: () -> Void
    
    @State private var selectedCategory: ReportCategory?
    @State private var additionalDetails: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccessMessage: Bool = false
    
    @Environment(\.colorScheme) var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.9)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.58)
    }
    
    private var contentType: String {
        if moment != nil { return NSLocalizedString("report.contentType.moment", comment: "Moment content type") }
        if story != nil { return NSLocalizedString("report.contentType.story", comment: "Story content type") }
        return NSLocalizedString("report.contentType.user", comment: "User content type")
    }
    
    private var contentId: String {
        return moment?.id ?? story?.id ?? reportedUserId ?? ""
    }
    
    private var authorId: String {
        return moment?.authorId ?? story?.authorId ?? reportedUserId ?? ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            NativeReportSheetHeader(
                title: String(format: NSLocalizedString("report.title", comment: "Report title"), contentType.capitalized),
                onBack: onBack
            )

            if showSuccessMessage {
                successView
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(String(format: NSLocalizedString("report.subtitle", comment: "Report subtitle"), contentType))
                            .font(.system(size: legacyPoppinsSize(15)))
                            .foregroundColor(secondaryText)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)

                        NativeReportOptionsSection {
                            ForEach(Array(ReportCategory.allCases.enumerated()), id: \.element) { index, category in
                                NativeReportOptionRow(
                                    icon: category.icon,
                                    title: category.title,
                                    subtitle: category.subtitle,
                                    isSelected: selectedCategory == category,
                                    showsChevron: selectedCategory != category
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedCategory = category
                                    }
                                }

                                if index < ReportCategory.allCases.count - 1 {
                                    NativeReportDivider()
                                }
                            }
                        }

                        if selectedCategory != nil {
                            NativeReportDetailsSection(
                                title: NSLocalizedString("report.additionalDetails", comment: "Additional details label"),
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
                    if selectedCategory != nil {
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
        .frame(maxHeight: 640)
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
        guard let category = selectedCategory,
              let currentUserId = Auth.auth().currentUser?.uid,
              !contentId.isEmpty else { return }
        
        isSubmitting = true
        
        let reporterId = currentUserId
        let reportedUserId = authorId
        let reportedContentType: String
        if moment != nil {
            reportedContentType = "moment"
        } else if story != nil {
            reportedContentType = "story"
        } else {
            reportedContentType = "user"
        }
        let reportedContentId = contentId
        let categoryRaw = category.rawValue
        let description = additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        let priority = category.priority.rawValue
        
        Task {
            await LocalPersistenceService.shared.reportContent(
                reporterId: reporterId,
                reportedUserId: reportedUserId,
                reportedContentType: reportedContentType,
                reportedContentId: reportedContentId,
                category: categoryRaw,
                description: description,
                priority: priority
            )
            
            DispatchQueue.main.async {
                self.isSubmitting = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    self.showSuccessMessage = true
                }
            }
        }
    }
}

struct NativeReportSheetHeader: View {
    let title: String
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.9)
    }

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                .foregroundColor(primaryText)
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

struct NativeReportOptionsSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 20)
    }
}

struct NativeReportOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let showsChevron: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.9)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.55)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(primaryText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: subtitle.isEmpty ? 0 : 3) {
                    Text(title)
                        .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                        .foregroundColor(primaryText)
                        .multilineTextAlignment(.leading)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundColor(secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NativeReportDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, 36)
    }
}

struct NativeReportDetailsSection: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.9)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.28)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                .foregroundColor(primaryText)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: legacyPoppinsSize(15)))
                    .foregroundColor(primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 108)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )

                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: legacyPoppinsSize(15)))
                        .foregroundColor(secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

struct NativeReportSubmitBar: View {
    let isSubmitting: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: action) {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(title)
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
    }
}
