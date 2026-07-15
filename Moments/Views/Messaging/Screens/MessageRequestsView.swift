import SwiftUI
import FirebaseAuth
import Kingfisher

struct MessageRequestsView: View {
    @EnvironmentObject var messageRequestService: MessageRequestService
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    @State private var showingActionSheet = false
    @State private var actionRequest: MessageRequest?
    let onOpenRequest: (MessageRequest) -> Void

    init(onOpenRequest: @escaping (MessageRequest) -> Void = { _ in }) {
        self.onOpenRequest = onOpenRequest
    }
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            requestCountHeader

            if messageRequestService.pendingRequests.isEmpty {
                emptyStateView
            } else {
                requestsListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("messageRequests.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .onAppear {
            if let userId = Auth.auth().currentUser?.uid {
                messageRequestService.listenToPendingRequests(for: userId)
            }
        }
        .onDisappear {
            messageRequestService.removeAllListeners()
        }
        .confirmationDialog("messageRequests.request.title", isPresented: $showingActionSheet) {
            if let request = actionRequest {
                Button("messageRequests.accept") { acceptRequest(request) }
                Button("messageRequests.delete", role: .destructive) { rejectRequest(request) }
                Button("messageRequests.blockUser", role: .destructive) { blockUser(request) }
                Button("common.cancel", role: .cancel) { }
            }
        } message: {
            Text("messageRequests.request.message")
        }
    }

    // MARK: - Request Count Header
    private var requestCountHeader: some View {
        Group {
            if !messageRequestService.pendingRequests.isEmpty {
                Text(String(format: NSLocalizedString("messageRequests.count", comment: "Request count"), messageRequestService.pendingRequests.count))
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(adaptiveColors.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.clear.momentsChromeGlass(in: Capsule()))
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }
    
    // MARK: - Actions
    private func acceptRequest(_ request: MessageRequest) {
        messageRequestService.acceptRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Success
                    break
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func rejectRequest(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // success
                    break
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func blockUser(_ request: MessageRequest) {
        messageRequestService.blockUser(request) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // User blocked successfully
                    break
                case .failure(_):
                    break
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "message")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(adaptiveColors.secondary.opacity(0.72))

            Text("messageRequests.empty.title")
                .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                .foregroundStyle(adaptiveColors.primary)

            Text("messageRequests.empty.description")
                .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                .foregroundStyle(adaptiveColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
    }
    
    // MARK: - Requests List View
    private var requestsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(messageRequestService.pendingRequests) { request in
                    RequestListRow(request: request) {
                        onOpenRequest(request)
                    } onAction: {
                        actionRequest = request
                        showingActionSheet = true
                    }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }
    
}

// MARK: - Request List Row
struct RequestListRow: View {
    let request: MessageRequest
    let onTap: () -> Void
    let onAction: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                avatar
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)

            Button(action: onAction) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(adaptiveColors.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if let profileImagePath = request.senderProfileImagePath {
            KFImage(URL(string: profileImagePath))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(adaptiveColors.secondary.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(adaptiveColors.secondary)
                )
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.senderUsername ?? NSLocalizedString("messaging.user.default", comment: "Default user name"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(adaptiveColors.primary)
                    .lineLimit(1)

                Text(request.messagePreview)
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(adaptiveColors.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeAgoString(from: request.timestamp))
                .font(.system(size: legacyPoppinsSize(12)))
                .foregroundStyle(adaptiveColors.secondary)
                .lineLimit(1)
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        MomentsFormat.relativeTime(from: date)
    }
}

#Preview {
    MessageRequestsView()
        .environmentObject(MessageRequestService())
        .environmentObject(AuthService())
}
