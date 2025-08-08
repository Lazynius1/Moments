import SwiftUI
import FirebaseAuth

struct BestFriendsView: View {
    @StateObject private var viewModel = BestFriendsViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.bestFriends.isEmpty && viewModel.connections.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle("Mejores Amigos")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .onAppear {
                viewModel.fetchBestFriends()
                viewModel.fetchConnections()
            }
            .alert(isPresented: $viewModel.showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(viewModel.errorMessage ?? "Ocurrió un error desconocido"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Sin mejores amigos")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text("Añade amigos desde tus conexiones para marcarlos como mejores amigos.")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
    }

    private var contentView: some View {
        List {
            Section(header: Text("Mejores Amigos").font(.custom("Poppins-SemiBold", size: 16))) {
                ForEach(viewModel.bestFriends) { user in
                    BestFriendRow(user: user, viewModel: viewModel)
                }
            }
            
            Section(header: Text("Conexiones").font(.custom("Poppins-SemiBold", size: 16))) {
                ForEach(viewModel.connections.filter { connection in
                    !viewModel.bestFriends.contains(where: { $0.id == connection.id })
                }) { user in
                    ConnectionRow(user: user, viewModel: viewModel)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

struct BestFriendRow: View {
    let user: AppUser
    @ObservedObject var viewModel: BestFriendsViewModel

    var body: some View {
        HStack {
            ProfileImageView(imagePath: user.profileImagePath)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            
            Text(user.username)
                .font(.custom("Poppins-Regular", size: 14))
            
            Spacer()
            
            Button(action: {
                viewModel.removeBestFriend(userId: user.id)
            }) {
                Text("Eliminar")
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConnectionRow: View {
    let user: AppUser
    @ObservedObject var viewModel: BestFriendsViewModel

    var body: some View {
        HStack {
            ProfileImageView(imagePath: user.profileImagePath)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            
            Text(user.username)
                .font(.custom("Poppins-Regular", size: 14))
            
            Spacer()
            
            Button(action: {
                viewModel.addBestFriend(userId: user.id)
            }) {
                Text("Añadir")
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

class BestFriendsViewModel: ObservableObject {
    @Published var bestFriends: [AppUser] = []
    @Published var connections: [AppUser] = []
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    
    private let bestFriendsService: BestFriendsService
    private let firestoreService: FirestoreService

    init(firestoreService: FirestoreService = FirestoreService(), bestFriendsService: BestFriendsService? = nil) {
        self.firestoreService = firestoreService
        self.bestFriendsService = bestFriendsService ?? BestFriendsService(firestoreService: firestoreService)
    }

    func fetchBestFriends() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Usuario no autenticado"
            showError = true
            return
        }
        
        isLoading = true
        bestFriendsService.fetchBestFriends(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let friends):
                    self?.bestFriends = friends
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                    self?.showError = true
                }
            }
        }
    }

    func fetchConnections() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Usuario no autenticado"
            showError = true
            return
        }
        
        isLoading = true
        firestoreService.db.collection("users").document(userId).collection("connections").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.showError = true
                    return
                }
                
                let dispatchGroup = DispatchGroup()
                var connections: [AppUser] = []
                
                for doc in snapshot?.documents ?? [] {
                    let friendId = doc.documentID
                    dispatchGroup.enter()
                    self?.firestoreService.fetchUser(userId: friendId) { result in
                        defer { dispatchGroup.leave() }
                        if case .success(let user) = result {
                            connections.append(user)
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    self?.connections = connections
                }
            }
        }
    }

    func addBestFriend(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            errorMessage = "Usuario no autenticado"
            showError = true
            return
        }
        
        bestFriendsService.addBestFriend(currentUserId: currentUserId, friendId: userId) { [weak self] error in
            if let error = error {
                self?.errorMessage = error.localizedDescription
                self?.showError = true
            } else {
                self?.fetchBestFriends()
            }
        }
    }

    func removeBestFriend(userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            errorMessage = "Usuario no autenticado"
            showError = true
            return
        }
        
        bestFriendsService.removeBestFriend(currentUserId: currentUserId, friendId: userId) { [weak self] error in
            if let error = error {
                self?.errorMessage = error.localizedDescription
                self?.showError = true
            } else {
                self?.fetchBestFriends()
            }
        }
    }
}

struct BestFriendsView_Previews: PreviewProvider {
    static var previews: some View {
        BestFriendsView()
    }
}
