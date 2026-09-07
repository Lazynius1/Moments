import SwiftUI
import PhotosUI
import UIKit
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var presence: PresenceDisplay?
    @State private var statusListener: ListenerRegistration?

    private var adaptiveColors: AdaptiveColors { AdaptiveColors(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 14) {
            KFImage(URL(string: member.image)).placeholder { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                .resizable().scaledToFill().frame(width: 48, height: 48).background(.primary.opacity(0.06), in: Circle()).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name).font(.body.weight(.medium)).lineLimit(1)
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
        .contentShape(Rectangle())
        .onAppear { attachPresence() }
        .onDisappear { detachPresence() }
        .onChange(of: member.id) { _, _ in
            detachPresence()
            attachPresence()
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var adding = false
    @State private var leaving = false
    @State private var shareURL: URL?
    @State private var removing: GroupMember?
    @State private var photoItem: PhotosPickerItem?
    @StateObject private var onlineStatusService = OnlineStatusService()
    var body: some View {
        ScrollView {
            if let group = store.active {
                let admin = group.admins.contains(store.uid)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        if admin {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                GroupChatAvatar(name: group.name, image: group.image, size: 96, camera: true)
                            }
                        } else {
                            GroupChatAvatar(name: group.name, image: group.image, size: 96)
                        }
                        Spacer()
                    }.padding(.top, 24)
                    Text(group.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                    Text(String(format: groupText("memberCount"), group.members.count)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    if admin {
                        HStack {
                            TextField(groupText("name"), text: Binding(get: { name }, set: { name = limitedGroupName($0) }))
                            Button(groupText("save")) { Task { await store.command("rename", group: group, name: name) } }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == group.name || store.busy)
                        }.padding(14).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        Button { adding = true } label: { Label(groupText("add"), systemImage: "person.badge.plus") }.disabled(group.members.count >= 50)
                    }
                    if admin {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(groupText("inviteLink")).font(.headline)
                            Text(groupText("linkBody")).font(.caption).foregroundStyle(.secondary)
                            Button(groupText("getLink")) { Task { shareURL = await store.invitationLink(group) } }
                            if let shareURL { ShareLink(item: shareURL) { Label(groupText("shareLink"), systemImage: "square.and.arrow.up") } }
                            Button(groupText("renewLink")) { Task { shareURL = await store.invitationLink(group, renew: true) } }
                            Button(groupText("disableLink"), role: .destructive) { Task {
                                if await store.command("revokeLink", group: group) { shareURL = nil }
                            } }
                        }
                    }
                    Toggle(groupText("mute"), isOn: Binding(get: { group.muted.contains(store.uid) }, set: { value in Task { await store.command("mute", group: group, muted: value) } })).disabled(store.busy)
                    if admin && !group.pendingNames.isEmpty {
                        Text(groupText("pendingInvitations")).font(.headline)
                        ForEach(group.pendingNames.keys.sorted(), id: \.self) { id in
                            HStack {
                                Text(group.pendingNames[id] ?? "")
                                Spacer()
                                Button(groupText("cancel")) { Task { await store.command("cancelInvite", group: group, memberId: id) } }
                            }
                        }
                    }
                    Text(groupText("members")).font(.headline).padding(.top, 12)
                    ForEach(group.members) { member in
                        HStack {
                            GroupPersonRow(
                                member: member,
                                detail: member.id == group.owner ? groupText("owner") : (group.admins.contains(member.id) ? groupText("admin") : ""),
                                joinedAt: group.joinedDate(for: member.id),
                                showsPresence: true,
                                onlineStatusService: onlineStatusService
                            )
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
                    Button(groupText("leave"), role: .destructive) { leaving = true }.padding(.vertical, 20)
                }.padding(.horizontal, 20).disabled(store.busy)
            } else { ContentUnavailableView(groupText("unavailable"), systemImage: "person.3") }
        }
        .background(AdaptiveColors(colorScheme: colorScheme).surfaceBackground.ignoresSafeArea())
        .navigationDestination(isPresented: $adding) {
            if let group = store.active { GroupMemberPicker(store: store, group: group) { _ in adding = false } }
        }
        .navigationTitle(groupText("details"))
        .onAppear { name = store.active?.name ?? "" }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data), let group = store.active else { return }
                await store.setPhoto(image, group: group)
            }
        }
        .alert(groupText("leave"), isPresented: $leaving) {
            Button(groupText("cancel"), role: .cancel) { }
            Button(groupText("leave"), role: .destructive) { Task { if let group = store.active, await store.command("leave", group: group) { dismiss() } } }
        } message: { Text(groupText("leaveBody")) }
        .alert(groupText("remove"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(groupText("cancel"), role: .cancel) { removing = nil }
            Button(groupText("remove"), role: .destructive) {
                if let member = removing, let group = store.active { Task { await store.command("remove", group: group, memberId: member.id) } }
                removing = nil
            }
        } message: { Text(groupText("removeBody")) }
        .groupError(store)
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
    @StateObject private var store = GroupChatStore()
    @State private var name: String?
    @State private var image = ""
    var body: some View {
        NavigationStack {
            ChatRecoveryGateView(onCancel: { dismiss() }) {
                VStack(spacing: 24) {
                    GroupChatAvatar(name: name ?? "", image: image, size: 88)
                    if let name {
                        Text(name).font(.title2.bold())
                        Text(groupText("linkBody")).foregroundStyle(.secondary)
                        Button(groupText("joinLink")) { Task {
                            if await store.joinLink(link) { dismiss(); onJoined() }
                        } }.buttonStyle(.borderedProminent).disabled(store.busy)
                    } else if store.error == nil { ProgressView() }
                    else { Text(groupText("linkError")).foregroundStyle(.secondary) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: link.id) {
                        if let preview = await store.previewLink(link) {
                            name = preview.name; image = preview.image
                        }
                    }
            }
            .navigationTitle(groupText("inviteLink"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("cancel")) { dismiss() } } }
        }.groupError(store)
    }
}
