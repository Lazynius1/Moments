import SwiftUI
import FirebaseAuth
import Kingfisher

struct MessageRequestsView: View {
    @EnvironmentObject private var messageRequestService: MessageRequestService
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedFolder: MessageRequestFolder = .normal
    @State private var actionRequest: MessageRequest?
    @State private var showingActions = false

    let onOpenRequest: (MessageRequest) -> Void

    init(onOpenRequest: @escaping (MessageRequest) -> Void = { _ in }) {
        self.onOpenRequest = onOpenRequest
    }

    private var displayedRequests: [MessageRequest] {
        switch selectedFolder {
        case .normal: messageRequestService.pendingRequests
        case .old: messageRequestService.oldRequests
        case .hidden: messageRequestService.hiddenRequests
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MessageRequestFolderPicker(selection: $selectedFolder)
            MessageRequestFolderContent(
                folder: selectedFolder,
                requests: displayedRequests,
                visibleRequestCount: messageRequestService.pendingRequests.count,
                onOpen: onOpenRequest,
                onAction: presentActions
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("messageRequests.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .momentsFloatingTabBarHidden()
        .task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            messageRequestService.listenToPendingRequests(for: userId)
        }
        .confirmationDialog("messageRequests.request.title", isPresented: $showingActions, presenting: actionRequest) { request in
            Button("messageRequests.accept") { accept(request) }
            if selectedFolder == .hidden {
                Button("messageRequests.moveToRequests") { move(request, to: .normal) }
            } else {
                Button("messageRequests.moveToHidden") { move(request, to: .hidden) }
            }
            Button("messageRequests.report", role: .destructive) { report(request) }
            Button("messageRequests.delete", role: .destructive) { reject(request) }
            Button("messageRequests.blockUser", role: .destructive) { block(request) }
            Button("common.cancel", role: .cancel) { }
        } message: { _ in
            Text("messageRequests.request.message")
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")
    }

    private func presentActions(_ request: MessageRequest) {
        actionRequest = request
        showingActions = true
    }

    private func accept(_ request: MessageRequest) {
        messageRequestService.acceptRequest(request) { _ in }
    }

    private func reject(_ request: MessageRequest) {
        messageRequestService.rejectRequest(request) { _ in }
    }

    private func block(_ request: MessageRequest) {
        messageRequestService.blockUser(request) { _ in }
    }

    private func report(_ request: MessageRequest) {
        messageRequestService.reportRequest(request) { _ in }
    }

    private func move(_ request: MessageRequest, to folder: MessageRequestFolder) {
        messageRequestService.moveRequest(request, to: folder) { _ in }
    }
}

private struct MessageRequestFolderPicker: View {
    @Binding var selection: MessageRequestFolder

    var body: some View {
        Picker("messageRequests.folder.picker", selection: $selection) {
            Text("messageRequests.folder.requests").tag(MessageRequestFolder.normal)
            Text("messageRequests.folder.old").tag(MessageRequestFolder.old)
            Text("messageRequests.folder.hidden").tag(MessageRequestFolder.hidden)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct MessageRequestFolderContent: View {
    let folder: MessageRequestFolder
    let requests: [MessageRequest]
    let visibleRequestCount: Int
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MessageRequestCountHeader(folder: folder, count: visibleRequestCount)
            if requests.isEmpty {
                MessageRequestEmptyState(folder: folder)
            } else {
                MessageRequestList(
                    requests: requests,
                    onOpen: onOpen,
                    onAction: onAction
                )
            }
        }
    }
}

private struct MessageRequestCountHeader: View {
    let folder: MessageRequestFolder
    let count: Int

    var body: some View {
        VStack {
            if folder == .normal, count > 0 {
                Text(String(
                    format: NSLocalizedString(
                        count == 1 ? "messageRequests.count" : "messageRequests.count.plural",
                        comment: ""
                    ),
                    count
                ))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.clear.momentsChromeGlass(in: Capsule()))
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct MessageRequestList: View {
    let requests: [MessageRequest]
    let onOpen: (MessageRequest) -> Void
    let onAction: (MessageRequest) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(requests) { request in
                    MessageRequestListRow(
                        request: request,
                        onTap: { onOpen(request) },
                        onAction: { onAction(request) }
                    )
                }
            }
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .momentsScrollEdgeChrome()
    }
}

private struct MessageRequestEmptyState: View {
    let folder: MessageRequestFolder

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: folder == .hidden ? "eye.slash" : folder == .old ? "archivebox" : "message")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary.opacity(0.72))
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
        .momentsEmptyStateAppear()
    }

    private var title: LocalizedStringKey {
        switch folder {
        case .normal: "messageRequests.empty.title"
        case .old: "messageRequests.old.empty.title"
        case .hidden: "messageRequests.hidden.empty.title"
        }
    }

    private var description: LocalizedStringKey {
        switch folder {
        case .normal: "messageRequests.empty.description"
        case .old: "messageRequests.old.empty.description"
        case .hidden: "messageRequests.hidden.empty.description"
        }
    }
}

private struct MessageRequestListRow: View {
    let request: MessageRequest
    let onTap: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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

            Button(action: onAction) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
            }
            .buttonStyle(.plain)
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
