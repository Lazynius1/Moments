import SwiftUI

struct ModerationReviewStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    private let appealService = AppealService.shared
    @State private var requests: [ModerationReviewStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedRequest: ModerationReviewStatus?
    @State private var refreshing = false

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    AppealStatusHeader(
                        title: selectedRequest == nil
                        ? NSLocalizedString("moderationReview.status.title", comment: "Moderation review requests title")
                        : NSLocalizedString("moderationReview.status.detailTitle", comment: "Moderation review request detail title"),
                        showsBackButton: true,
                        showsRefreshButton: selectedRequest == nil,
                        refreshing: refreshing,
                        onBack: {
                            if selectedRequest != nil {
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                    selectedRequest = nil
                                }
                            } else {
                                dismiss()
                            }
                        },
                        onRefresh: fetchRequests
                    )

                    ZStack {
                        if let selectedRequest {
                            ModerationReviewDetailView(request: selectedRequest)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            Group {
                                if isLoading {
                                    LoadingView()
                                } else if requests.isEmpty {
                                    ModerationReviewEmptyView()
                                } else {
                                    ModerationReviewListView(
                                        requests: requests,
                                        selectedRequest: $selectedRequest,
                                        onRefresh: fetchRequests
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
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: selectedRequest?.id)
        .onAppear {
            fetchRequests()
        }
        .alert(NSLocalizedString("appeal.error.title", comment: "Error title"), isPresented: $showError) {
            Button(NSLocalizedString("appeal.error.ok", comment: "OK button for error alerts")) { }
        } message: {
            Text(errorMessage ?? NSLocalizedString("appeal.error.unknown", comment: "Unknown error"))
        }
    }

    private func fetchRequests() {
        guard let userId = authService.currentFirebaseUser?.uid else { return }

        if !refreshing {
            isLoading = true
        }
        refreshing = true

        Task {
            do {
                let fetchedRequests = try await appealService.fetchUserModerationReviews(userId: userId)
                await MainActor.run {
                    requests = fetchedRequests
                    isLoading = false
                    refreshing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                    refreshing = false
                }
            }
        }
    }
}

private struct ModerationReviewListView: View {
    let requests: [ModerationReviewStatus]
    @Binding var selectedRequest: ModerationReviewStatus?
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(requests) { request in
                    ModerationReviewCard(request: request) {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            selectedRequest = request
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

private struct ModerationReviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let request: ModerationReviewStatus
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(String(format: NSLocalizedString("moderationReview.status.ticket", comment: "Moderation review ticket number format"), request.ticketNumber))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AuthColors.primary(colorScheme))

                        Text(request.submittedAt)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.62))
                            .lineLimit(1)
                    }

                    AppealStatusBadge(status: request.status, priority: request.priority)

                    Text(request.contentType == "story"
                         ? NSLocalizedString("moderationReview.context.story", comment: "Story content type")
                         : NSLocalizedString("moderationReview.context.moment", comment: "Moment content type"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))

                    Text(request.reviewMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                        .lineLimit(2)

                    Text(String(format: NSLocalizedString("moderationReview.status.estimatedResponse", comment: "Moderation review estimated response"), request.estimatedResponseTime))
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
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AuthColors.primary(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.08), lineWidth: 0.8)
                            .allowsHitTesting(false)
                    }
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ModerationReviewDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let request: ModerationReviewStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                detailCard(
                    title: NSLocalizedString("moderationReview.previewTitle", comment: "Moderation review preview title"),
                    lines: [
                        request.contentType == "story"
                        ? NSLocalizedString("moderationReview.context.story", comment: "Story content type")
                        : NSLocalizedString("moderationReview.context.moment", comment: "Moment content type"),
                        scopeText,
                        request.moderationCategory ?? ""
                    ].filter { !$0.isEmpty }
                )

                detailCard(
                    title: NSLocalizedString("moderationReview.messageTitle", comment: "Moderation review message title"),
                    lines: [request.reviewMessage]
                )

                if let additionalInfo = request.additionalInfo, !additionalInfo.isEmpty {
                    detailCard(
                        title: NSLocalizedString("moderationReview.additionalInfo", comment: "Moderation review additional info title"),
                        lines: [additionalInfo]
                    )
                }

                detailCard(
                    title: NSLocalizedString("moderationReview.contactEmail", comment: "Moderation review contact email"),
                    lines: [
                        request.contactEmail,
                        String(format: NSLocalizedString("moderationReview.status.estimatedResponse", comment: "Moderation review estimated response"), request.estimatedResponseTime)
                    ]
                )

                if let moderatorNotes = request.moderatorNotes, !moderatorNotes.isEmpty {
                    detailCard(
                        title: NSLocalizedString("moderationReview.status.teamNotes", comment: "Moderation review team notes title"),
                        lines: [moderatorNotes]
                    )
                }
            }
            .padding()
        }
    }

    private var scopeText: String {
        switch request.moderationScope {
        case "storySticker":
            return NSLocalizedString("moderationReview.scope.storySticker", comment: "Story sticker moderation scope")
        case "postHiddenLayer":
            return NSLocalizedString("moderationReview.scope.postHiddenLayer", comment: "Post hidden layer moderation scope")
        case "story":
            return NSLocalizedString("moderationReview.scope.story", comment: "Story moderation scope")
        default:
            return NSLocalizedString("moderationReview.scope.post", comment: "Post moderation scope")
        }
    }

    private func detailCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.68))

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AuthColors.primary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            Color.clear
                .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
    }
}

private struct ModerationReviewEmptyView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.6))

            Text(NSLocalizedString("moderationReview.status.empty.title", comment: "Moderation review empty title"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AuthColors.primary(colorScheme))

            Text(NSLocalizedString("moderationReview.status.empty.message", comment: "Moderation review empty message"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AuthColors.secondary(colorScheme, opacity: 0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
