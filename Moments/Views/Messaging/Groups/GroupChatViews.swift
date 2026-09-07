import SwiftUI
import PhotosUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

private func groupText(_ key: String) -> String { NSLocalizedString("groups." + key, comment: "Group chat") }
private let groupNameMaxLength = 60
private func limitedGroupName(_ value: String) -> String { String(value.prefix(groupNameMaxLength)) }

struct GroupChatAvatar: View {
    var name: String = ""
    var image: String = ""
    var local: UIImage? = nil
    var size: CGFloat = 52
    var camera: Bool = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let local {
                    Image(uiImage: local).resizable().scaledToFill()
                } else if let url = URL(string: image), !image.isEmpty {
                    KFImage(url).placeholder { fallback }.resizable().scaledToFill()
                } else { fallback }
            }
            .frame(width: size, height: size).clipShape(Circle())
            if camera {
                Image(systemName: "camera.fill").font(.system(size: max(10, size * 0.2), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel(groupText("photo"))
    }
    private var fallback: some View {
        Image(systemName: "person.3.fill").font(.system(size: size * 0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.primary.opacity(0.07))
    }
}

private struct GroupPersonRow: View {
    let member: GroupMember
    var detail: String = ""
    var joinedAt: Date? = nil
    var showsPresence: Bool = false
    var onlineStatusService: OnlineStatusService? = nil
    var profileZoomNamespace: Namespace.ID? = nil
    var onProfileTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var presence: PresenceDisplay?
    @State private var statusListener: ListenerRegistration?

    private var adaptiveColors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            profilePhoto
            VStack(alignment: .leading, spacing: 4) {
                profileName
                if showsPresence, let presence {
                    HStack(spacing: 6) {
                        Circle().fill(presence.status.color).frame(width: 8, height: 8)
                        Text(presence.statusText).font(.caption).foregroundStyle(adaptiveColors.secondary)
                        if let extra = presence.supplementalText {
                            Text("• \(extra)").font(.caption).foregroundStyle(adaptiveColors.tertiary)
                        }
                    }
                }
                if let joinedAt {
                    Text(String(format: groupText("joinedOn"), MomentsFormat.smartDate(from: joinedAt, context: .mediumDate)))
                        .font(.caption)
                        .foregroundStyle(adaptiveColors.secondary)
                }
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
        }
        .onAppear { attachPresence() }
        .onDisappear { detachPresence() }
        .onChange(of: member.id) { _, _ in
            detachPresence()
            attachPresence()
        }
    }

    private var avatarView: some View {
        AsyncProfileImageView(userId: member.id)
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .userProfileZoomSource(userId: member.id, namespace: profileZoomNamespace, cornerRadius: 24)
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if let onProfileTap {
            Button(action: onProfileTap) { avatarView }
                .buttonStyle(.plain)
        } else {
            avatarView
        }
    }

    @ViewBuilder
    private var profileName: some View {
        let name = Text(member.name).font(.body.weight(.medium)).lineLimit(1)
        if let onProfileTap {
            Button(action: onProfileTap) { name }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
        } else {
            name
        }
    }

    private func attachPresence() {
        guard showsPresence, let service = onlineStatusService, statusListener == nil else { return }
        statusListener = service.observeUserStatus(userId: member.id) { status, lastSeen in
            DispatchQueue.main.async {
                self.presence = service.presenceDisplay(for: status, lastSeen: lastSeen)
            }
        }
    }

    private func detachPresence() {
        statusListener?.remove()
        statusListener = nil
    }
}

private struct GroupMemberFollowButton: View {
    let userId: String
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var firestoreService = FirestoreService.shared
    @State private var followButtonState: FollowButtonState = .canFollow
    @State private var isFollowLoading = false

    var body: some View {
        ModernFollowButton(
            state: followButtonState,
            isLoading: isFollowLoading,
            colorScheme: colorScheme,
            targetUserId: userId,
            style: .compact,
            action: performFollowToggle
        )
        .onAppear {
            if let cached = FollowStateStore.shared.state(for: userId) {
                followButtonState = cached
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let changedUserId = notification.userInfo?["userId"] as? String,
                  changedUserId == userId,
                  let changedState = notification.userInfo?["state"] as? FollowButtonState else { return }
            if let changedViewerId = notification.userInfo?["viewerId"] as? String,
               changedViewerId != Auth.auth().currentUser?.uid {
                return
            }
            followButtonState = changedState
        }
    }

    private func performFollowToggle() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        guard followButtonState.isActionable else { return }

        let previousState = followButtonState
        let optimisticState: FollowButtonState = {
            switch previousState {
            case .following, .mutuals: return .canFollow
            case .canRequestFollow: return .requestPendingCancellable
            case .requestPendingCancellable: return .canRequestFollow
            case .canFollow: return .following
            default: return previousState
            }
        }()

        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
            followButtonState = optimisticState
        }
        FollowStateStore.shared.setState(optimisticState, for: userId)
        isFollowLoading = true

        if previousState.isFollowingOrMutual {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    isFollowLoading = false
                    if error != nil {
                        followButtonState = previousState
                        FollowStateStore.shared.setState(previousState, for: userId)
                    }
                }
            }
        } else if previousState == .requestPendingCancellable {
            firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    isFollowLoading = false
                    if error != nil {
                        followButtonState = previousState
                        FollowStateStore.shared.setState(previousState, for: userId)
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    isFollowLoading = false
                    if error != nil {
                        followButtonState = previousState
                        FollowStateStore.shared.setState(previousState, for: userId)
                    }
                }
            }
        }
    }
}

struct GroupMemberPicker: View {
    @ObservedObject var store: GroupChatStore
    let group: GroupConversation?
    let onSaved: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var search = ""
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var skipContinue: GroupSaveResult?
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    private var candidates: [GroupMember] {
        store.candidates.filter { member in
            !(group?.members.contains(where: { $0.id == member.id }) ?? false) && group?.pendingNames[member.id] == nil &&
            (search.isEmpty || member.name.localizedCaseInsensitiveContains(search))
        }
    }
    private var valid: Bool {
        (group != nil || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        selected.count >= (group == nil ? 2 : 1) && selected.count + ((group?.members.count ?? 1) + (group?.pendingNames.count ?? 0)) <= 50
    }
    private var headerTitle: String {
        if group != nil { return groupText("add") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? groupText("create") : trimmed
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if group == nil {
                    HStack(alignment: .center, spacing: 14) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            GroupChatAvatar(name: name, local: photo, size: 64, camera: true)
                        }
                        TextField(groupText("name"), text: Binding(get: { name }, set: { name = limitedGroupName($0) }))
                            .padding(16).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }.padding(.horizontal, 20)
                }
                Text(groupText("pickerHint")).font(.subheadline).foregroundStyle(.secondary).padding(20)
                Text(String(format: groupText("selectedCount"), selected.count)).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if candidates.isEmpty && !loading { Text(groupText("noConnections")).foregroundStyle(.secondary).padding(20) }
                ForEach(candidates) { member in
                    Button {
                        if selected.contains(member.id) { selected.remove(member.id) }
                        else if selected.count + ((group?.members.count ?? 1) + (group?.pendingNames.count ?? 0)) < 50 { selected.insert(member.id) }
                    } label: {
                        HStack {
                            GroupPersonRow(member: member)
                            Image(systemName: selected.contains(member.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(member.id) ? Color.accentColor : .secondary)
                        }.padding(.horizontal, 20).padding(.vertical, 14)
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 16)
        }
        .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: groupText("search"))
        .toolbar(.hidden, for: .tabBar)
        .momentsFloatingTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 200)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(groupText(group == nil ? "create" : "add")) {
                    Task {
                        guard let result = await store.saveMembers(name: name, ids: selected.sorted(), to: group) else { return }
                        if let photo, group == nil {
                            let doc = try? await Firestore.firestore().collection("groupConversations").document(result.id).getDocument()
                            if let doc, doc.exists { await store.setPhoto(photo, group: GroupConversation(doc)) }
                        }
                        if result.skipped.isEmpty { onSaved(result.id) } else { skipContinue = result }
                    }
                }.disabled(!valid || store.busy)
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                photo = image
            }
        }
        .task(id: search) {
            loading = true
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await store.loadCandidates(query: search); loading = false
        }
        .alert(groupText("errorTitle"), isPresented: Binding(get: { store.error != nil || skipContinue != nil }, set: { if !$0 {
            if let id = skipContinue?.id { onSaved(id) }
            skipContinue = nil
            store.error = nil
        } })) {
            Button(groupText("ok")) {
                if let id = skipContinue?.id { onSaved(id) }
                skipContinue = nil
                store.error = nil
            }
        } message: {
            if let skipped = skipContinue?.skipped {
                Text(store.inviteForbiddenMessage(skipped) ?? NSLocalizedString("groups.inviteForbidden", comment: ""))
            } else {
                let key = store.error ?? "groups.error"
                Text(key.hasPrefix("groups.") ? NSLocalizedString(key, comment: "Group error") : key)
            }
        }
    }
}

struct GroupDetailsView: View {
    @ObservedObject var store: GroupChatStore
    @State private var adding = false
    @State private var removing: GroupMember?
    @StateObject private var onlineStatusService = OnlineStatusService()
    @State private var followEpoch = 0
    @State private var selectedProfileRoute: FeedProfileSheetRoute?
    @Namespace private var profileZoomNamespace
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ScrollView {
            if let group = store.active {
                let admin = group.admins.contains(store.uid)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        GroupChatAvatar(name: group.name, image: group.image, size: 72)
                        Spacer()
                    }.padding(.top, 16)
                    Text(group.name)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity)
                    Text(String(format: groupText("memberCount"), group.members.count))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    if admin {
                        Button { adding = true } label: { Label(groupText("add"), systemImage: "person.badge.plus") }
                            .disabled(group.members.count >= 50)
                    }
                    if admin && !group.pendingNames.isEmpty {
                        Text(groupText("pendingInvitations")).font(.headline).padding(.top, 8)
                        ForEach(group.pendingNames.keys.sorted(), id: \.self) { id in
                            HStack {
                                GroupPersonRow(
                                    member: GroupMember(id: id, name: group.pendingNames[id] ?? "", image: ""),
                                    profileZoomNamespace: profileZoomNamespace,
                                    onProfileTap: { selectedProfileRoute = FeedProfileSheetRoute(userId: id) }
                                )
                                Button(groupText("cancel")) { Task { await store.command("cancelInvite", group: group, memberId: id) } }
                            }
                        }
                    }
                    Text(groupText("members")).font(.headline).padding(.top, 8)
                    memberSections(group: group, admin: admin)
                }.padding(.horizontal, 20).disabled(store.busy)
            } else { ContentUnavailableView(groupText("unavailable"), systemImage: "person.3") }
        }
        .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground.ignoresSafeArea())
        .navigationDestination(isPresented: $adding) {
            if let group = store.active { GroupMemberPicker(store: store, group: group) { _ in adding = false } }
        }
        .navigationTitle(groupText("members"))
        .userProfileNavigationDestination(item: $selectedProfileRoute, namespace: profileZoomNamespace)
        .task(id: store.active?.members.map(\.id).joined(separator: ",")) {
            guard let members = store.active?.members, let viewer = Auth.auth().currentUser?.uid else { return }
            for member in members where member.id != viewer {
                FollowStateStore.shared.resolve(viewerId: viewer, targetUserId: member.id) { _ in
                    DispatchQueue.main.async { followEpoch += 1 }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { _ in
            followEpoch += 1
        }
        .alert(groupText("remove"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(groupText("cancel"), role: .cancel) { removing = nil }
            Button(groupText("remove"), role: .destructive) {
                if let member = removing, let group = store.active { Task { await store.command("remove", group: group, memberId: member.id) } }
                removing = nil
            }
        } message: { Text(groupText("removeBody")) }
        .groupError(store)
    }

    @ViewBuilder
    private func memberSections(group: GroupConversation, admin: Bool) -> some View {
        let buckets = memberBuckets(group.members)
        if !buckets.you.isEmpty {
            Text(groupText("you")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(buckets.you) { member in memberRow(member, group: group, admin: admin) }
        }
        if !buckets.following.isEmpty {
            Text(groupText("followingSection")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
            ForEach(buckets.following) { member in memberRow(member, group: group, admin: admin) }
        }
        if !buckets.others.isEmpty {
            Text(groupText("othersSection")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
            ForEach(buckets.others) { member in memberRow(member, group: group, admin: admin) }
        }
    }

    private func memberBuckets(_ members: [GroupMember]) -> (you: [GroupMember], following: [GroupMember], others: [GroupMember]) {
        _ = followEpoch
        let uid = store.uid
        let you = members.filter { $0.id == uid }
        let rest = members.filter { $0.id != uid }
        let following = rest.filter { FollowStateStore.shared.state(for: $0.id)?.isFollowingOrMutual == true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let others = rest.filter { FollowStateStore.shared.state(for: $0.id)?.isFollowingOrMutual != true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (you, following, others)
    }

    @ViewBuilder
    private func memberRow(_ member: GroupMember, group: GroupConversation, admin: Bool) -> some View {
        HStack {
            GroupPersonRow(
                member: member,
                detail: member.id == group.owner ? groupText("owner") : (group.admins.contains(member.id) ? groupText("admin") : ""),
                joinedAt: group.joinedDate(for: member.id),
                showsPresence: true,
                onlineStatusService: onlineStatusService,
                profileZoomNamespace: profileZoomNamespace,
                onProfileTap: { selectedProfileRoute = FeedProfileSheetRoute(userId: member.id) }
            )
            if member.id != store.uid {
                GroupMemberFollowButton(userId: member.id)
            }
            if admin && member.id != group.owner && member.id != store.uid {
                Menu {
                    if !group.admins.contains(member.id) {
                        Button(groupText("promote")) { Task { await store.command("promote", group: group, memberId: member.id) } }
                    } else if group.owner == store.uid {
                        Button(groupText("demote")) { Task { await store.command("demote", group: group, memberId: member.id) } }
                    }
                    if !group.admins.contains(member.id) || group.owner == store.uid {
                        Button(groupText("remove"), role: .destructive) { removing = member }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }.accessibilityLabel(groupText("manage"))
            }
        }.padding(.vertical, 8)
    }
}

private struct GroupErrorModifier: ViewModifier {
    @ObservedObject var store: GroupChatStore
    func body(content: Content) -> some View {
        content.alert(groupText("errorTitle"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button(groupText("ok"), role: .cancel) { store.error = nil }
        } message: {
            let key = store.error ?? "groups.error"
            Text(key.hasPrefix("groups.") ? NSLocalizedString(key, comment: "Group error") : key)
        }
    }
}
private extension View {
    func groupError(_ store: GroupChatStore) -> some View { modifier(GroupErrorModifier(store: store)) }
}

struct NewGroupView: View {
    @StateObject private var store = GroupChatStore()
    let onCreated: (Conversation) -> Void
    var body: some View {
        GroupMemberPicker(store: store, group: nil) { id in
            Task {
                do {
                    let doc = try await Firestore.firestore().collection("groupConversations").document(id).getDocument()
                    if let conversation = ChatService.shared.groupConversation(doc, userId: store.uid) { onCreated(conversation) }
                } catch { store.error = "groups.error" }
            }
        }
    }
}

struct GroupEditView: View {
    let groupId: String
    @StateObject private var store = GroupChatStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    var body: some View {
        ScrollView {
            if let group = store.active {
                VStack(spacing: 20) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        GroupChatAvatar(name: name.isEmpty ? group.name : name, image: group.image, size: 96, camera: true)
                    }
                    TextField(groupText("name"), text: Binding(get: { name }, set: { name = limitedGroupName($0) }))
                        .padding(14)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    Button(groupText("save")) {
                        Task {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty, trimmed != group.name {
                                _ = await store.command("rename", group: group, name: trimmed)
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(groupText("unavailable"), systemImage: "person.3")
            }
        }
        .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground.ignoresSafeArea())
        .navigationTitle(groupText("edit"))
        .navigationBarTitleDisplayMode(.inline)
        .task { store.open(groupId) }
        .onChange(of: store.active?.name) { _, value in
            if name.isEmpty, let value { name = value }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data), let group = store.active else { return }
                await store.setPhoto(image, group: group)
            }
        }
        .groupError(store)
    }
}

struct GroupInviteLinkManageView: View {
    let groupId: String
    @StateObject private var store = GroupChatStore()
    @Environment(\.colorScheme) private var colorScheme
    @State private var shareURL: URL?
    @State private var copied = false
    @State private var confirmRenew = false
    @State private var confirmDisable = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(groupText("linkBody"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let shareURL {
                    Text(shareURL.absoluteString)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.url = shareURL
                            copied = true
                        } label: {
                            Label(copied ? groupText("linkCopied") : groupText("copyLink"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        ShareLink(item: shareURL) {
                            Label(groupText("shareLink"), systemImage: "square.and.arrow.up")
                        }
                    }
                    Divider().padding(.top, 8)
                    Button(groupText("renewLink")) { confirmRenew = true }
                        .disabled(store.busy)
                    Button(groupText("disableLink"), role: .destructive) { confirmDisable = true }
                        .disabled(store.busy)
                } else if store.active != nil {
                    if store.busy {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Button(groupText("getLink")) {
                            Task { shareURL = await loadLink(renew: false) }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground.ignoresSafeArea())
        .navigationTitle(groupText("inviteLink"))
        .navigationBarTitleDisplayMode(.inline)
        .task { store.open(groupId) }
        .task(id: store.active?.id) {
            guard store.active != nil, shareURL == nil else { return }
            shareURL = await loadLink(renew: false)
        }
        .alert(groupText("renewLink"), isPresented: $confirmRenew) {
            Button(groupText("cancel"), role: .cancel) {}
            Button(groupText("renewLink")) {
                Task { shareURL = await loadLink(renew: true) }
            }
        } message: { Text(groupText("renewBody")) }
        .alert(groupText("disableLink"), isPresented: $confirmDisable) {
            Button(groupText("cancel"), role: .cancel) {}
            Button(groupText("disableLink"), role: .destructive) {
                Task {
                    guard let group = store.active else { return }
                    if await store.command("revokeLink", group: group) { shareURL = nil }
                }
            }
        } message: { Text(groupText("disableBody")) }
        .groupError(store)
    }

    private func loadLink(renew: Bool) async -> URL? {
        guard let group = store.active else { return nil }
        return await store.invitationLink(group, renew: renew)
    }
}

struct GroupManagementView: View {
    let groupId: String
    @StateObject private var store = GroupChatStore()
    var body: some View {
        GroupDetailsView(store: store).task { store.open(groupId) }
    }
}

struct GroupInvitationRows: View {
    @StateObject private var store = GroupChatStore()
    let onAccepted: (Conversation) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.invitations.isEmpty {
                Text("groups.invitations").font(.headline)
                ForEach(store.invitations) { invitation in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            GroupChatAvatar(name: invitation.name, image: invitation.image, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invitation.name).font(.body.weight(.semibold)).lineLimit(1)
                                Text(String(format: groupText("invitedYou"), invitation.inviter))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack {
                            Button("groups.decline") { Task { _ = await store.respond(to: invitation, accept: false) } }
                            Spacer()
                            Button("groups.accept") { Task {
                                if let conversation = await store.respond(to: invitation, accept: true) { onAccepted(conversation) }
                            } }
                        }.disabled(store.busy)
                    }
                }
            }
        }
        .padding(store.invitations.isEmpty ? 0 : 16)
        .task { store.start() }
        .onDisappear { store.stop() }
        .groupError(store)
    }
}

struct GroupJoinLinkView: View {
    let link: GroupInviteLink
    let onJoined: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = GroupChatStore()
    @State private var name: String?
    @State private var image = ""

    private var adaptiveColors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        ChatRecoveryGateView(onCancel: { dismiss() }) {
            VStack(spacing: 0) {
                Spacer(minLength: 20)

                VStack(spacing: 14) {
                    GroupChatAvatar(name: name ?? "", image: image, size: 104)
                    if let name {
                        Text(name)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.4)
                            .multilineTextAlignment(.center)
                        Text(groupText("joinBody"))
                            .font(.system(size: 15))
                            .foregroundStyle(adaptiveColors.secondary)
                            .multilineTextAlignment(.center)
                    } else if store.error == nil {
                        ProgressView()
                    } else {
                        Text(groupText("linkError"))
                            .font(.system(size: 15))
                            .foregroundStyle(adaptiveColors.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 24)

                Button {
                    Task {
                        if await store.joinLink(link) { dismiss(); onJoined() }
                    }
                } label: {
                    Text(groupText("joinLink"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(adaptiveColors.surfaceBackground)
                .background(adaptiveColors.primary, in: Capsule())
                .disabled(store.busy || name == nil)
                .opacity(name == nil ? 0.4 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                } else {
                    adaptiveColors.surfaceBackground
                }
            }
            .task(id: link.id) {
                if let preview = await store.previewLink(link) {
                    name = preview.name
                    image = preview.image
                }
            }
        }
        .groupJoinLinkPresentation()
        .groupError(store)
    }
}

private struct GroupJoinLinkPresentation: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        } else {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(AdaptiveColors(colorScheme: colorScheme).surfaceBackground)
        }
    }
}

private extension View {
    func groupJoinLinkPresentation() -> some View {
        modifier(GroupJoinLinkPresentation())
    }
}
