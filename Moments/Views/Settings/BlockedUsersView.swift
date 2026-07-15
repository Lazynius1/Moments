import SwiftUI
import FirebaseAuth

struct BlockedUsersView: View {
    @StateObject private var viewModel = BlockedUsersViewModel()
    @State private var hasFetchedBlockedUsers = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("common.searching", comment: "Searching"))
                        .progressViewStyle(CircularProgressViewStyle())
                        .font(.system(size: legacyPoppinsSize(16)))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.blockedUsers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("blockedUsers.empty", comment: "No blocked users"))
                            .font(.system(size: legacyPoppinsSize(16)))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(format: NSLocalizedString("settings.sections.blockedAccounts.subtitle", comment: "Blocked accounts count"), viewModel.blockedUsers.count))
                                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)

                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.blockedUsers, id: \.id) { user in
                                    HStack(spacing: 12) {
                                        Text(user.username)
                                            .font(.system(size: legacyPoppinsSize(15)))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        Button(action: {
                                            viewModel.unblockUser(userId: user.id)
                                        }) {
                                            Text(NSLocalizedString("blockedUsers.unblock", comment: "Unblock"))
                                                .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.clear.momentsChromeGlass(in: Capsule(), interactive: true))
                                        }
                                        .buttonStyle(.momentsPressSubtle)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 20)
                    }
                    .momentRefresh {
                        viewModel.fetchBlockedUsers()
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            }
            .padding(.top, 8)
        }
        .onAppear {
            if !hasFetchedBlockedUsers {
                viewModel.fetchBlockedUsers()
                hasFetchedBlockedUsers = true
            }
        }
        .alert(NSLocalizedString("blockedUsers.error.title", comment: "Error"), isPresented: $viewModel.showError) {
            Button(NSLocalizedString("blockedUsers.ok", comment: "OK")) { }
        } message: {
            Text(viewModel.errorMessage ?? NSLocalizedString("blockedUsers.unknownError", comment: "Unknown error occurred"))
        }
        .navigationTitle(NSLocalizedString("blockedUsers.title", comment: "Blocked Users"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationInteractivePopEnabled()
        .toolbarBackground(.hidden, for: .navigationBar)
        .momentsScrollEdgeChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
    }
}

class BlockedUsersViewModel: ObservableObject {
    @Published var blockedUsers: [AppUser] = []
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String?

    private let firestoreService = FirestoreService()

    func fetchBlockedUsers() {
        guard let userId = Auth.auth().currentUser?.uid else {
            showError(message: NSLocalizedString("blockedUsers.notAuthenticated", comment: "User not authenticated"))
            return
        }

        isLoading = true
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let user):
                let blockedUserIds = user.blockedUsers
                if blockedUserIds.isEmpty {
                    self.blockedUsers = []
                    self.isLoading = false
                    return
                }
                self.firestoreService.fetchUsers(userIds: blockedUserIds) { result in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        switch result {
                        case .success(let users):
                            self.blockedUsers = users
                        case .failure(let error):
                            self.showError(message: "Error al obtener usuarios bloqueados: \(error.localizedDescription)")
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.showError(message: "Error al obtener perfil: \(error.localizedDescription)")
                }
            }
        }
    }

    func unblockUser(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            showError(message: NSLocalizedString("blockedUsers.notAuthenticated", comment: "User not authenticated"))
            return
        }

        isLoading = true
        firestoreService.unblockUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.showError(message: "Error al desbloquear usuario: \(error.localizedDescription)")
                } else {
                    // Actualizar la lista de usuarios bloqueados localmente
                    if let index = self.blockedUsers.firstIndex(where: { $0.id == userId }) {
                        self.blockedUsers.remove(at: index)
                    }
                }
            }
        }
    }

    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }
}

struct BlockedUsersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BlockedUsersView()
        }
    }
}
