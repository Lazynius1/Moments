import SwiftUI
import FirebaseAuth

struct BlockedUsersView: View {
    @StateObject private var viewModel = BlockedUsersViewModel()
    @State private var hasFetchedBlockedUsers = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Cargando usuarios bloqueados...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray)
                } else if viewModel.blockedUsers.isEmpty {
                    VStack {
                        Image(systemName: "hand.raised.slash")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                        Text("blockedUsers.empty")
                            .font(.custom("Poppins-Regular", size: 16))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                } else {
                    List(viewModel.blockedUsers, id: \.id) { user in
                        HStack {
                            Text(user.username)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.black)
                            Spacer()
                            Button(action: {
                                viewModel.unblockUser(userId: user.id)
                            }) {
                                Text("blockedUsers.unblock")
                                    .font(.custom("Poppins-Regular", size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("blockedUsers.title", comment: "Blocked Users"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color(hex: "4F46E5").opacity(0.3), Color(hex: "4F46E5").opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "4F46E5"))
                        }
                    }
                }
            }
            .onAppear {
                if !hasFetchedBlockedUsers {
                    viewModel.fetchBlockedUsers()
                    hasFetchedBlockedUsers = true
                }
            }
            .alert(isPresented: $viewModel.showError) {
                Alert(
                    title: Text(NSLocalizedString("blockedUsers.error.title", comment: "Error")),
                    message: Text(viewModel.errorMessage ?? NSLocalizedString("blockedUsers.unknownError", comment: "Unknown error occurred")),
                    dismissButton: .default(Text(NSLocalizedString("blockedUsers.ok", comment: "OK")))
                )
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
        NavigationView {
            BlockedUsersView()
        }
    }
}
