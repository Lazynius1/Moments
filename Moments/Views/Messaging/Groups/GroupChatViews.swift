import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

private func groupText(_ key: String) -> String { NSLocalizedString("groups." + key, comment: "Group chat") }
private let groupNameMaxLength = 60
private let groupDescriptionMaxLength = 280
private func limitedGroupName(_ value: String) -> String { String(value.prefix(groupNameMaxLength)) }
private func limitedGroupDescription(_ value: String) -> String { String(value.prefix(groupDescriptionMaxLength)) }

struct GroupMentionCandidateList: View {
    let query: String
    let members: [GroupMember]
    let onSelect: (GroupMember) -> Void

    private var matches: [GroupMember] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = members.filter {
            needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle)
        }
        return Array(filtered.prefix(10))
    }

    private var resultsPanelHeight: CGFloat {
        let rowHeight: CGFloat = 67
        let visibleRows = min(max(matches.count, 1), 3)
        return CGFloat(visibleRows) * rowHeight
    }

    var body: some View {
        Group {
            if matches.isEmpty {
                Text(NSLocalizedString("common.noResults", value: "No users found", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { member in
                            Button { onSelect(member) } label: {
                                GroupMentionSearchRow(member: member)
                            }
                            .buttonStyle(.plain)

                            if member.id != matches.last?.id {
                                Divider().opacity(0.25)
                            }
                        }
                    }
                }
                .frame(height: resultsPanelHeight)
            }
        }
        .padding(.vertical, 8)
        .momentsChromeGlass(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            interactive: false,
            style: .native
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

private struct GroupMentionSearchRow: View {
    let member: GroupMember

    var body: some View {
        HStack(spacing: 12) {
            AsyncProfileImageView(userId: member.id)
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            Text(member.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .momentsChromeGlass(in: Circle(), interactive: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct GroupChatAvatar: View {
    var name: String = ""
    var image: String = ""
    var local: UIImage? = nil
    var size: CGFloat = 52
    var camera: Bool = false
    var uploading: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let local {
                    Image(uiImage: local).resizable().scaledToFill()
                        .opacity(uploading ? 0.42 : 1)
                } else if let url = URL(string: image), !image.isEmpty {
                    KFImage(url).placeholder { fallback }.resizable().scaledToFill()
                } else { fallback }
            }
            .frame(width: size, height: size).clipShape(Circle())

            if uploading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                    .padding(12)
                    .background(.black.opacity(0.28), in: Circle())
                    .frame(width: size, height: size)
            }

            if camera {
                Image(systemName: "camera.fill")
                    .font(.system(size: max(10, size * 0.2), weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(max(6, size * 0.08))
                    .background(Color.clear.momentsChromeGlass(in: Circle(), interactive: true))
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
    @State private var showingPhotoCrop = false
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
                        Button { showingPhotoCrop = true } label: {
                            GroupChatAvatar(name: name, local: photo, size: 64, camera: true)
                        }
                        .buttonStyle(.plain)
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
        .fullScreenCover(isPresented: $showingPhotoCrop) {
            ProfileLibraryCropEntryView { cropped in
                photo = cropped
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
    @State private var memberSearch = ""
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
                    if !group.groupDescription.isEmpty {
                        Text(group.groupDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    Text(String(format: groupText("memberCount"), group.members.count))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    if admin {
                        Button { adding = true } label: { Label(groupText("add"), systemImage: "person.badge.plus") }
                            .disabled(group.members.count >= 50)
                    }
                    if admin && !group.pendingJoinNames.isEmpty {
                        Text(groupText("joinRequests")).font(.headline).padding(.top, 8)
                        ForEach(group.pendingJoinNames.keys.sorted(), id: \.self) { id in
                            HStack {
                                GroupPersonRow(
                                    member: GroupMember(id: id, name: group.pendingJoinNames[id] ?? "", image: ""),
                                    profileZoomNamespace: profileZoomNamespace,
                                    onProfileTap: { selectedProfileRoute = FeedProfileSheetRoute(userId: id) }
                                )
                                Button(groupText("decline")) { Task { await store.command("declineJoin", group: group, memberId: id) } }
                                Button(groupText("approveJoin")) { Task { await store.command("approveJoin", group: group, memberId: id) } }
                            }
                        }
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
        .searchable(text: $memberSearch, prompt: groupText("searchMembers"))
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
        if buckets.you.isEmpty && buckets.following.isEmpty && buckets.others.isEmpty && !memberSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(groupText("noMembersFound")).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    private func memberBuckets(_ members: [GroupMember]) -> (you: [GroupMember], following: [GroupMember], others: [GroupMember]) {
        _ = followEpoch
        let uid = store.uid
        let query = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = query.isEmpty ? members : members.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let you = visible.filter { $0.id == uid }
        let rest = visible.filter { $0.id != uid }
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
    @State private var description = ""
    @State private var showingPhotoCrop = false
    @State private var pendingPhoto: UIImage?
    @State private var isPhotoUploading = false
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.busy && !isPhotoUploading
    }
    private var saveTint: Color {
        colorScheme == .dark ? MomentsGlassButtonTint.light : MomentsGlassButtonTint.dark
    }
    private var saveLabel: Color {
        colorScheme == .dark ? MomentsGlassButtonTint.dark : MomentsGlassButtonTint.light
    }

    private func saveEdits(of group: GroupConversation) {
        Task {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if trimmed != group.name || trimmedDescription != group.groupDescription {
                guard await store.command("rename", group: group, name: trimmed,
                                          extra: ["description": trimmedDescription]) else { return }
            }
            dismiss()
        }
    }
    var body: some View {
        ScrollView {
            if let group = store.active {
                VStack(spacing: 20) {
                    Button { showingPhotoCrop = true } label: {
                        GroupChatAvatar(
                            name: name.isEmpty ? group.name : name,
                            image: group.image,
                            local: pendingPhoto,
                            size: 96,
                            camera: true,
                            uploading: isPhotoUploading
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPhotoUploading)
                    TextField(groupText("name"), text: Binding(get: { name }, set: { name = limitedGroupName($0) }))
                        .padding(14)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    TextField(groupText("descriptionPlaceholder"), text: Binding(get: { description }, set: { description = limitedGroupDescription($0) }), axis: .vertical)
                        .lineLimit(3...6)
                        .padding(14)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    Group {
                        if #available(iOS 26.0, *) {
                            Button(action: { saveEdits(of: group) }) {
                                Text(groupText("save"))
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                    .foregroundStyle(saveLabel)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.capsule)
                            .tint(saveTint)
                            .foregroundStyle(saveLabel)
                        } else {
                            Button(action: { saveEdits(of: group) }) {
                                Text(groupText("save"))
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                    .foregroundStyle(saveLabel)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .momentsChromeGlass(
                                        in: Capsule(),
                                        interactive: canSave,
                                        tint: saveTint.opacity(canSave ? 0.92 : 0.35)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
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
        .onChange(of: store.active?.id, initial: true) { _, _ in
            guard let group = store.active, name.isEmpty else { return }
            name = group.name
            description = group.groupDescription
        }
        .onChange(of: store.active?.image) { _, _ in
            pendingPhoto = nil
        }
        .fullScreenCover(isPresented: $showingPhotoCrop) {
            ProfileLibraryCropEntryView { cropped in
                pendingPhoto = cropped
                isPhotoUploading = true
                Task {
                    guard let group = store.active else {
                        isPhotoUploading = false
                        pendingPhoto = nil
                        return
                    }
                    await store.setPhoto(cropped, group: group)
                    isPhotoUploading = false
                    if store.error != nil { pendingPhoto = nil }
                }
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
                    Toggle(groupText("link.approval"), isOn: Binding(
                        get: { store.active?.linkRequiresApproval == true },
                        set: { value in
                            guard let group = store.active else { return }
                            Task { _ = await store.command("setLinkApproval", group: group, extra: ["requiresApproval": value]) }
                        }
                    ))
                    .disabled(store.busy)
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

struct GroupRequestsEntry: View {
    @ObservedObject var store: GroupRequestsStore
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill").font(.body)
                Text(groupText("requestsTitle")).font(.subheadline)
                Spacer()
                if store.count > 0 {
                    Text(store.count, format: .number).font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .background(.primary, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.foregroundStyle(.primary).padding(16)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 8)
    }
}

struct GroupRequestsView: View {
    @ObservedObject var store: GroupRequestsStore
    let onAccepted: (Conversation) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var sentTab: Bool
    init(store: GroupRequestsStore, initialSentTab: Bool = false, onAccepted: @escaping (Conversation) -> Void) {
        self.store = store
        self.onAccepted = onAccepted
        _sentTab = State(initialValue: initialSentTab)
    }
    private var rows: [GroupPendingRequest] { sentTab ? store.sent : store.received }
    private var loading: Bool { sentTab ? store.sentLoading : store.receivedLoading }
    private var failed: Bool { sentTab ? store.sentFailed : store.receivedFailed }
    var body: some View {
        VStack(spacing: 0) {
            Picker(groupText("requestsTitle"), selection: $sentTab) {
                Text("\(groupText("requestsReceived"))  \(store.received.count)").tag(false)
                Text("\(groupText("requestsSent"))  \(store.sent.count)").tag(true)
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if failed {
                        VStack(spacing: 12) {
                            Text(groupText("requestsError")).foregroundStyle(.secondary)
                            Button(groupText("requestsRetry")) { store.retry() }
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else if loading && rows.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else if rows.isEmpty {
                        Text(groupText(sentTab ? "requestsSentEmpty" : "requestsReceivedEmpty"))
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 32)
                    }
                    ForEach(rows) { row in
                        GroupRequestRow(row: row, sent: sentTab, busy: store.busy,
                            onAccept: { Task { if let conversation = await store.respond(row, accept: true) { onAccepted(conversation) } } },
                            onReject: { Task { _ = await store.respond(row, accept: false) } },
                            onCancel: { Task { await store.cancel(row) } })
                        Divider().padding(.leading, 68)
                    }
                    Text(groupText(sentTab ? "requestsSentFooter" : "requestsReceivedFooter"))
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 40).padding(.bottom, 24)
                }.padding(.horizontal, 20)
            }
        }
        .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground.ignoresSafeArea())
        .navigationTitle(groupText("requestsTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .momentsFloatingTabBarHidden()
        .alert(groupText("errorTitle"), isPresented: $store.actionFailed) {
            Button(groupText("ok"), role: .cancel) { }
        } message: { Text(groupText("manageError")) }
    }
}

private struct GroupRequestRow: View {
    let row: GroupPendingRequest
    let sent: Bool
    let busy: Bool
    let onAccept: () -> Void
    let onReject: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private var relativeDate: String? {
        row.createdAt.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GroupChatAvatar(name: row.name, image: row.image, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(sent ? groupText("requestsPending") : String(format: groupText("invitedYou"), row.inviter))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let relativeDate { Text(relativeDate).font(.caption).foregroundStyle(.tertiary) }
                HStack(spacing: 10) {
                    if sent {
                        requestButton(groupText("requestsCancel"), action: onCancel)
                    } else {
                        requestButton(groupText("decline"), action: onReject)
                        requestButton(groupText("accept"), primary: true, action: onAccept)
                    }
                }.padding(.top, 10).disabled(busy)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 24)
    }
    private func requestButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(primary ? (colorScheme == .dark ? Color.black : Color.white) : Color.primary)
                .background(primary ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(primary ? Color.clear : Color.secondary.opacity(0.6)))
        }.buttonStyle(.plain)
    }
}
