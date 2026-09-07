import SwiftUI
import FirebaseFirestore
import Kingfisher

private func groupText(_ key: String) -> String { NSLocalizedString("groups." + key, comment: "Group chat") }

private struct GroupAvatar: View {
    let name: String
    var body: some View {
        Image(systemName: "person.3.fill").font(.system(size: 22))
            .frame(width: 52, height: 52).background(.primary.opacity(0.07), in: Circle()).accessibilityHidden(true)
    }
}

private struct GroupPersonRow: View {
    let member: GroupMember
    var detail: String = ""
    var body: some View {
        HStack(spacing: 14) {
            KFImage(URL(string: member.image)).placeholder { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                .resizable().scaledToFill().frame(width: 48, height: 48).background(.primary.opacity(0.06), in: Circle()).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name).font(.body.weight(.medium)).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
        }.contentShape(Rectangle())
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
    private var candidates: [GroupMember] {
        store.candidates.filter { member in
            !(group?.members.contains(where: { $0.id == member.id }) ?? false) && group?.pendingNames[member.id] == nil &&
            (search.isEmpty || member.name.localizedCaseInsensitiveContains(search))
        }
    }
    private var valid: Bool {
        (group != nil || (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60)) &&
        selected.count >= (group == nil ? 2 : 1) && selected.count + ((group?.members.count ?? 1) + (group?.pendingNames.count ?? 0)) <= 50
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if group == nil {
                    TextField(groupText("name"), text: $name).padding(16).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
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
        .navigationTitle(groupText(group == nil ? "create" : "add"))
        .searchable(text: $search, prompt: groupText("search"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button(groupText(group == nil ? "create" : "add")) {
                Task { if let id = await store.saveMembers(name: name, ids: selected.sorted(), to: group) { onSaved(id) } }
            }.disabled(!valid || store.busy)
        } }
        .task(id: search) {
            loading = true
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await store.loadCandidates(query: search); loading = false
        }
        .groupError(store)
    }
}

struct GroupDetailsView: View {
    @ObservedObject var store: GroupChatStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var adding = false
    @State private var leaving = false
    @State private var removing: GroupMember?
    var body: some View {
        ScrollView {
            if let group = store.active {
                let admin = group.admins.contains(store.uid)
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Spacer(); GroupAvatar(name: group.name); Spacer() }.padding(.top, 24)
                    Text(group.name).font(.title2.bold()).frame(maxWidth: .infinity)
                    Text(String(format: groupText("memberCount"), group.members.count)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    if admin {
                        HStack {
                            TextField(groupText("name"), text: $name)
                            Button(groupText("save")) { Task { await store.command("rename", group: group, name: name) } }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 || name == group.name || store.busy)
                        }.padding(14).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        Button { adding = true } label: { Label(groupText("add"), systemImage: "person.badge.plus") }.disabled(group.members.count >= 50)
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
                            GroupPersonRow(member: member, detail: member.id == group.owner ? groupText("owner") : (group.admins.contains(member.id) ? groupText("admin") : ""))
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
        } message: { Text(NSLocalizedString(store.error ?? "groups.error", comment: "Group error")) }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(invitation.name).font(.body.weight(.semibold))
                        Text(invitation.inviter).font(.caption).foregroundStyle(.secondary)
                        Text("groups.privacy").font(.caption).foregroundStyle(.secondary)
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
