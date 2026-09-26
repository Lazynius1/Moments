import SwiftUI
import FirebaseAuth
import Kingfisher

struct MessageRequestsView: View {
    @EnvironmentObject private var messageRequestService: MessageRequestService
    @Environment(\.colorScheme) private var colorScheme

    @State private var actionRequest: MessageRequest?
    @State private var showingActions = false
    @State private var showingOlderRequests = false
    @State private var visibleOlderRequestCount = 10
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteSelectedConfirmation = false
    @State private var isEditing = false
    @State private var selectedRequestIDs = Set<String>()

    let onOpenRequest: (MessageRequest) -> Void

    init(onOpenRequest: @escaping (MessageRequest) -> Void = { _ in }) {
        self.onOpenRequest = onOpenRequest
    }

    private var allRequests: [MessageRequest] {
        (messageRequestService.pendingRequests
            + messageRequestService.oldRequests)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private var recentRequests: [MessageRequest] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return allRequests
        }
        return allRequests.filter { $0.lastActivityAt >= cutoff }
    }

    private var olderRequests: [MessageRequest] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return []
        }
        return allRequests.filter { $0.lastActivityAt < cutoff }
    }

    private var selectedRequests: [MessageRequest] {
        allRequests.filter { selectedRequestIDs.contains(Self.requestID($0)) }
    }

    var body: some View {
        MessageRequestsInboxContent(
            recentRequests: recentRequests,
            olderRequests: olderRequests,
            hiddenRequests: messageRequestService.hiddenRequests,
            showingOlderRequests: showingOlderRequests,
            visibleOlderRequestCount: visibleOlderRequestCount,
            isEditing: isEditing,
            selectedRequestIDs: selectedRequestIDs,
            onOpen: handleOpen,
            onAction: presentActions,
            onToggleSelection: toggleSelection,
            onShowAll: showOlderRequests,
            onLoadMore: loadMoreOlderRequests,
            onDeleteAll: { showingDeleteAllConfirmation = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("messageRequests.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button("messageRequests.delete", role: .destructive) {
                        showingDeleteSelectedConfirmation = true
                    }
                    .disabled(selectedRequestIDs.isEmpty)
                }
                Button(isEditing ? "common.done" : "common.edit") {
                    if isEditing {
                        selectedRequestIDs.removeAll()
                    }
                    isEditing.toggle()
                }
                .disabled(allRequests.isEmpty && !isEditing)
            }
        }
        .momentsFloatingTabBarHidden()
        .task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            messageRequestService.listenToPendingRequests(for: userId)
        }
        .onChange(of: allRequests.map(Self.requestID)) { _, ids in
            selectedRequestIDs = selectedRequestIDs.intersection(Set(ids))
            if allRequests.isEmpty {
                isEditing = false
            }
        }
        .confirmationDialog("messageRequests.request.title", isPresented: $showingActions, presenting: actionRequest) { request in
            Button("messageRequests.accept") { accept(request) }
            Button("messageRequests.report", role: .destructive) { report(request) }
            Button("messageRequests.delete", role: .destructive) { reject(request) }
            Button("messageRequests.blockUser", role: .destructive) { block(request) }
            Button("common.cancel", role: .cancel) { }
        } message: { _ in
            Text("messageRequests.request.message")
        }
        .confirmationDialog("messageRequests.deleteAll.confirmation.title", isPresented: $showingDeleteAllConfirmation) {
            Button("messageRequests.deleteAll", role: .destructive, action: deleteAllRequests)
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("messageRequests.deleteAll.confirmation.message")
        }
        .confirmationDialog("messageRequests.deleteAll.confirmation.title", isPresented: $showingDeleteSelectedConfirmation) {
            Button("messageRequests.delete", role: .destructive, action: deleteSelectedRequests)
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("messageRequests.deleteAll.confirmation.message")
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private func handleOpen(_ request: MessageRequest) {
        if isEditing {
            toggleSelection(request)
        } else {
            onOpenRequest(request)
        }
    }

    private func presentActions(_ request: MessageRequest) {
        guard !isEditing else { return }
        actionRequest = request
        showingActions = true
    }

    private func toggleSelection(_ request: MessageRequest) {
        let id = Self.requestID(request)
        if selectedRequestIDs.contains(id) {
            selectedRequestIDs.remove(id)
        } else {
            selectedRequestIDs.insert(id)
        }
    }

    private func accept(_ request: MessageRequest) {
        messageRequestService.acceptRequest(request) { result in
            if case .success = result {
                InAppNotificationService.shared.showActionToast(.messageRequestAccepted)
            }
        }
    }

    private func reject(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { result in
            if case .success = result {
                InAppNotificationService.shared.showActionToast(.messageRequestDeleted)
            }
        }
    }

    private func block(_ request: MessageRequest) {
        let username = request.senderUsername
            ?? NSLocalizedString("messaging.user.default", comment: "")
        messageRequestService.blockUser(request) { result in
            if case .success = result {
                InAppNotificationService.shared.showActionToast(.blocked(username))
            }
        }
    }

    private func report(_ request: MessageRequest) {
        messageRequestService.reportRequest(request) { result in
            if case .success = result {
                InAppNotificationService.shared.showActionToast(.messageRequestReported)
            }
        }
    }

    private func showOlderRequests() {
        visibleOlderRequestCount = min(10, olderRequests.count)
        showingOlderRequests = true
    }

    private func loadMoreOlderRequests() {
        visibleOlderRequestCount = min(visibleOlderRequestCount + 10, olderRequests.count)
    }

    private func deleteAllRequests() {
        let targets = allRequests
        guard !targets.isEmpty else { return }
        targets.forEach { request in
            messageRequestService.rejectRequest(request) { _ in }
        }
        selectedRequestIDs.removeAll()
        isEditing = false
        InAppNotificationService.shared.showActionToast(.messageRequestsDeleted)
    }

    private func deleteSelectedRequests() {
        let targets = selectedRequests
        guard !targets.isEmpty else { return }
        targets.forEach { request in
            messageRequestService.rejectRequest(request) { _ in }
        }
        selectedRequestIDs.removeAll()
        isEditing = false
        InAppNotificationService.shared.showActionToast(
            targets.count == 1 ? .messageRequestDeleted : .messageRequestsDeleted
        )
    }

    static func requestID(_ request: MessageRequest) -> String {
        request.id ?? "\(request.senderId)_\(request.timestamp.timeIntervalSince1970)"
    }
}

private struct MessageRequestsInboxContent: View {
    let recentRequests: [MessageRequest]
    let olderRequests: [MessageRequest]
    let hiddenRequests: [MessageRequest]
    let showingOlderRequests: Bool
    let visibleOlderRequestCount: Int
    let isEditing: Bool
    let selectedRequestIDs: Set<String>
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void
    let onToggleSelection: (MessageRequest) -> Void
    let onShowAll: () -> Void
    let onLoadMore: () -> Void
    let onDeleteAll: () -> Void

    private var visibleOlderRequests: [MessageRequest] {
        Array(olderRequests.prefix(visibleOlderRequestCount))
    }

    private var canLoadMore: Bool {
        visibleOlderRequests.count < olderRequests.count
    }

    private var hasVisibleRequests: Bool {
        !recentRequests.isEmpty || (showingOlderRequests && !visibleOlderRequests.isEmpty)
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            inboxList
                .safeAreaBar(edge: .bottom) {
                    deleteAllBar
                }
        } else {
            inboxList
                .safeAreaInset(edge: .bottom) {
                    deleteAllFallback
                }
        }
    }

    private var inboxList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if hasVisibleRequests {
                    MessageRequestPrivacyNotice()
                } else {
                    MessageRequestHiddenNavigationLink(
                        requests: hiddenRequests,
                        count: hiddenRequests.count,
                        onOpen: onOpen,
                        onAction: onAction
                    )
                    MessageRequestRecentEmptyState()
                }

                if !recentRequests.isEmpty {
                    MessageRequestList(
                        requests: recentRequests,
                        isEditing: isEditing,
                        selectedRequestIDs: selectedRequestIDs,
                        onOpen: onOpen,
                        onAction: onAction,
                        onToggleSelection: onToggleSelection
                    )
                }

                if showingOlderRequests {
                    MessageRequestList(
                        requests: visibleOlderRequests,
                        isEditing: isEditing,
                        selectedRequestIDs: selectedRequestIDs,
                        onOpen: onOpen,
                        onAction: onAction,
                        onToggleSelection: onToggleSelection
                    )
                    if canLoadMore {
                        Button("messageRequests.loadMore", action: onLoadMore)
                            .buttonStyle(.plain)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 18)
                    }
                } else {
                    Button("common.viewAll", action: onShowAll)
                        .buttonStyle(.plain)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 18)
                }

                if hasVisibleRequests {
                    MessageRequestHiddenNavigationLink(
                        requests: hiddenRequests,
                        count: hiddenRequests.count,
                        onOpen: onOpen,
                        onAction: onAction
                    )
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .momentsScrollEdgeChrome()
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private var deleteAllBar: some View {
        if showingOlderRequests && !visibleOlderRequests.isEmpty && !isEditing {
            Button("messageRequests.deleteAll", role: .destructive, action: onDeleteAll)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var deleteAllFallback: some View {
        if showingOlderRequests && !visibleOlderRequests.isEmpty && !isEditing {
            Button("messageRequests.deleteAll", role: .destructive, action: onDeleteAll)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .padding(.vertical, 6)
        }
    }
}

private struct MessageRequestPrivacyNotice: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("messageRequests.privacy.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                SettingsView()
            } label: {
                Text("messageRequests.privacy.settings")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct MessageRequestHiddenNavigationLink: View {
    let requests: [MessageRequest]
    let count: Int
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void

    var body: some View {
        NavigationLink {
            MessageRequestHiddenDestination(
                requests: requests,
                onOpen: onOpen,
                onAction: onAction
            )
        } label: {
            MessageRequestHiddenLink(count: count)
        }
        .buttonStyle(.plain)
    }
}

private struct MessageRequestHiddenLink: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.title3.weight(.medium))
                .frame(width: 28)
            Text("messageRequests.hidden.title")
                .font(.body.weight(.semibold))
            Spacer()
            if count > 0 {
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
    }
}

private struct MessageRequestHiddenDestination: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingOlderRequests = false
    @State private var visibleOlderRequestCount = 10

    let requests: [MessageRequest]
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void

    private var recentRequests: [MessageRequest] {
        requests.filter { $0.lastActivityAt >= thirtyDaysAgo }
    }

    private var olderRequests: [MessageRequest] {
        requests.filter { $0.lastActivityAt < thirtyDaysAgo }
    }

    private var visibleOlderRequests: [MessageRequest] {
        Array(olderRequests.prefix(visibleOlderRequestCount))
    }

    private var canLoadMore: Bool {
        visibleOlderRequests.count < olderRequests.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if recentRequests.isEmpty {
                    MessageRequestHiddenEmptyState()
                } else {
                    MessageRequestList(
                        requests: recentRequests,
                        isEditing: false,
                        selectedRequestIDs: [],
                        onOpen: onOpen,
                        onAction: onAction,
                        onToggleSelection: { _ in }
                    )
                }

                MessageRequestOlderRequestsControl(
                    olderRequests: visibleOlderRequests,
                    hasMore: canLoadMore,
                    isShowingOlderRequests: showingOlderRequests,
                    onOpen: onOpen,
                    onAction: onAction,
                    onShowAll: showOlderRequests,
                    onLoadMore: loadMoreOlderRequests
                )

                NavigationLink {
                    MuteSettingsView()
                } label: {
                    Text("messageRequests.hidden.preferences")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 24)
        }
        .momentsScrollEdgeChrome()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("messageRequests.hidden.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .momentsFloatingTabBarHidden()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private var thirtyDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
    }

    private func showOlderRequests() {
        visibleOlderRequestCount = min(10, olderRequests.count)
        showingOlderRequests = true
    }

    private func loadMoreOlderRequests() {
        visibleOlderRequestCount = min(visibleOlderRequestCount + 10, olderRequests.count)
    }
}

private struct MessageRequestList: View {
    let requests: [MessageRequest]
    let isEditing: Bool
    let selectedRequestIDs: Set<String>
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void
    let onToggleSelection: (MessageRequest) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(requests) { request in
                MessageRequestListRow(
                    request: request,
                    isEditing: isEditing,
                    isSelected: selectedRequestIDs.contains(MessageRequestsView.requestID(request)),
                    onTap: { onOpen(request) },
                    onAction: { onAction(request) },
                    onToggleSelection: { onToggleSelection(request) }
                )
            }
        }
    }
}

private struct MessageRequestRecentEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "paperplane")
                .font(.title2.weight(.medium))
                .frame(width: 88, height: 88)
                .overlay(Circle().stroke(.secondary, lineWidth: 2))
                .foregroundStyle(.primary)
            Text("messageRequests.recent.empty.title")
                .font(.headline)
            Text("messageRequests.recent.empty.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
        .momentsEmptyStateAppear()
    }
}

private struct MessageRequestHiddenEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "paperplane")
                .font(.title2.weight(.medium))
                .frame(width: 88, height: 88)
                .overlay(Circle().stroke(.secondary, lineWidth: 2))
                .foregroundStyle(.primary)
            Text("messageRequests.hidden.empty.title")
                .font(.headline)
            Text("messageRequests.hidden.empty.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
        .momentsEmptyStateAppear()
    }
}

private struct MessageRequestOlderRequestsControl: View {
    let olderRequests: [MessageRequest]
    let hasMore: Bool
    let isShowingOlderRequests: Bool
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void
    let onShowAll: () -> Void
    let onLoadMore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isShowingOlderRequests {
                MessageRequestList(
                    requests: olderRequests,
                    isEditing: false,
                    selectedRequestIDs: [],
                    onOpen: onOpen,
                    onAction: onAction,
                    onToggleSelection: { _ in }
                )
                if hasMore {
                    Button("messageRequests.loadMore", action: onLoadMore)
                        .buttonStyle(.plain)
                        .font(.body.weight(.semibold))
                        .padding(.vertical, 18)
                }
            } else {
                VStack(spacing: 6) {
                    Text("messageRequests.recent.empty.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("common.viewAll", action: onShowAll)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 22)
            }
        }
    }
}

private struct MessageRequestListRow: View {
    let request: MessageRequest
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onAction: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            Button(action: onTap) {
                MessageRequestAvatar(path: request.senderProfileImagePath)
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                MessageRequestRowContent(
                    username: request.senderUsername,
                    preview: request.messagePreview,
                    messageCount: request.messageCount,
                    date: request.lastActivityAt
                )
            }
            .buttonStyle(.plain)

            if !isEditing {
                Button(action: onAction) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct MessageRequestAvatar: View {
    let path: String?

    var body: some View {
        ZStack {
            Circle().fill(.secondary.opacity(0.12))
            if let path, let url = URL(string: path) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill").foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }
}

private struct MessageRequestRowContent: View {
    let username: String?
    let preview: String
    let messageCount: Int
    let date: Date

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(username ?? NSLocalizedString("messaging.user.default", comment: ""))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(messageCount)/5")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(MomentsFormat.relativeTime(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationStack {
        MessageRequestsView()
            .environmentObject(MessageRequestService())
    }
}
