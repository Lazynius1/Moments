import SwiftUI
import FirebaseAuth

struct BestFriendsView: View {
    @StateObject private var viewModel = BestFriendsViewModel()
    @Environment(\.dismiss) var dismiss
    
    // ✅ NUEVO: Estado para búsqueda
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.bestFriends.isEmpty && viewModel.connections.isEmpty && viewModel.mutualConnections.isEmpty {
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
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color(hex: "00A896").opacity(0.3), Color(hex: "00A896").opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "00A896"))
                        }
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
        VStack(spacing: 0) {
            // ✅ NUEVO: Campo de búsqueda debajo del título
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField("Buscar en listas...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 16))
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
                        // Lista con contenido filtrado
            List {
                let filtered = viewModel.filteredUsers(searchText: searchText)
                
                // ✅ NUEVO: Sección de mejores amigos filtrados
                if !filtered.bestFriends.isEmpty {
                    Section(header: Text("Mejores Amigos").font(.custom("Poppins-SemiBold", size: 16))) {
                        ForEach(filtered.bestFriends) { user in
                            BestFriendRow(user: user, viewModel: viewModel)
                        }
                    }
                }
                
                // ✅ NUEVO: Sección de conexiones mutuas filtradas
                if !filtered.mutualConnections.isEmpty {
                    Section(header: Text("Conexiones Mutuas").font(.custom("Poppins-SemiBold", size: 16))) {
                        ForEach(filtered.mutualConnections.filter { connection in
                            !viewModel.bestFriends.contains(where: { $0.id == connection.id })
                        }) { user in
                            ConnectionRow(user: user, viewModel: viewModel)
                        }
                    }
                }
                
                // ✅ NUEVO: Sección de conexiones filtradas
                if !filtered.connections.isEmpty {
                    Section(header: Text("Conexiones").font(.custom("Poppins-SemiBold", size: 16))) {
                        ForEach(filtered.connections.filter { connection in
                            !viewModel.bestFriends.contains(where: { $0.id == connection.id })
                        }) { user in
                            ConnectionRow(user: user, viewModel: viewModel)
                        }
                    }
                }
                
                // ✅ NUEVO: Sección de admiradores filtrados
                if !filtered.admirers.isEmpty {
                    Section(header: Text("Admiradores").font(.custom("Poppins-SemiBold", size: 16))) {
                        ForEach(filtered.admirers) { user in
                            AdmirerRow(user: user, viewModel: viewModel)
                        }
                    }
                }
                
                // ✅ NUEVO: Mensaje si no hay resultados de búsqueda
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
                   filtered.bestFriends.isEmpty && filtered.connections.isEmpty && filtered.mutualConnections.isEmpty && filtered.admirers.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("No se encontraron resultados para '\(searchText)'")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
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

// ✅ NUEVO: Fila para admiradores
struct AdmirerRow: View {
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
            
            // ✅ Solo botón para agregar como mejor amigo
            Button(action: {
                viewModel.addBestFriend(userId: user.id)
            }) {
                Text("Agregar")
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

class BestFriendsViewModel: ObservableObject {
    @Published var bestFriends: [AppUser] = []
    @Published var connections: [AppUser] = []
    @Published var mutualConnections: [AppUser] = []  // ✅ NUEVO: Usuarios mutuos
    @Published var admirers: [AppUser] = []  // ✅ NUEVO: Admiradores (gente que te sigue)
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    
    private let bestFriendsService: BestFriendsService
    private let firestoreService: FirestoreService
    
    // ✅ NUEVO: Función para filtrar usuarios por texto de búsqueda
    func filteredUsers(searchText: String) -> (bestFriends: [AppUser], connections: [AppUser], mutualConnections: [AppUser], admirers: [AppUser]) {
        let lowercasedSearch = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if lowercasedSearch.isEmpty {
            return (bestFriends, connections, mutualConnections, admirers)
        }
        
        let filteredBestFriends = bestFriends.filter { user in
            user.username.lowercased().contains(lowercasedSearch) ||
            (user.bio?.lowercased().contains(lowercasedSearch) ?? false)
        }
        
        let filteredConnections = connections.filter { user in
            user.username.lowercased().contains(lowercasedSearch) ||
            (user.bio?.lowercased().contains(lowercasedSearch) ?? false)
        }
        
        let filteredMutualConnections = mutualConnections.filter { user in
            user.username.lowercased().contains(lowercasedSearch) ||
            (user.bio?.lowercased().contains(lowercasedSearch) ?? false)
        }
        
        let filteredAdmirers = admirers.filter { user in
            user.username.lowercased().contains(lowercasedSearch) ||
            (user.bio?.lowercased().contains(lowercasedSearch) ?? false)
        }
        
        return (filteredBestFriends, filteredConnections, filteredMutualConnections, filteredAdmirers)
    }

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
        
        // ✅ NUEVO: Usar la misma lógica que ProfileView
        let dispatchGroup = DispatchGroup()
        
        // 1. Obtener usuarios que sigues
        dispatchGroup.enter()
        firestoreService.db.collection("users").document(userId).collection("following").getDocuments { [weak self] snapshot, error in
            defer { dispatchGroup.leave() }
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Error al cargar seguidos: \(error.localizedDescription)"
                    self?.showError = true
                    self?.isLoading = false
                }
                return
            }
            
            let followingIds = snapshot?.documents.map { $0.documentID } ?? []
            
            // 2. Obtener usuarios que te siguen
            dispatchGroup.enter()
            self?.firestoreService.db.collection("users").document(userId).collection("followers").getDocuments { [weak self] snapshot, error in
                defer { dispatchGroup.leave() }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Error al cargar seguidores: \(error.localizedDescription)"
                        self?.showError = true
                        self?.isLoading = false
                    }
                    return
                }
                
                let followerIds = snapshot?.documents.map { $0.documentID } ?? []
                
                // 3. Categorizar conexiones (igual que ProfileView)
                let followingSet = Set(followingIds)
                let followersSet = Set(followerIds)
                
                let mutualIds = followingSet.intersection(followersSet)        // Mutuos
                let connectionIds = followingSet.subtracting(mutualIds)       // Conexiones (solo sigues tú)
                let admirerIds = followersSet.subtracting(mutualIds)          // Admiradores (solo te siguen)
                
                // 4. Cargar usuarios de conexiones (los que puedes agregar como mejores amigos)
                if !connectionIds.isEmpty {
                    dispatchGroup.enter()
                    self?.fetchUsersInBatches(userIds: Array(connectionIds)) { [weak self] users in
                        defer { dispatchGroup.leave() }
                        DispatchQueue.main.async {
                            self?.connections = users
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.connections = []
                    }
                }
                
                // ✅ NUEVO: Cargar usuarios mutuos (también se pueden agregar como mejores amigos)
                if !mutualIds.isEmpty {
                    dispatchGroup.enter()
                    self?.fetchUsersInBatches(userIds: Array(mutualIds)) { [weak self] users in
                        defer { dispatchGroup.leave() }
                        DispatchQueue.main.async {
                            self?.mutualConnections = users
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.mutualConnections = []
                    }
                }
                
                // ✅ NUEVO: Cargar admiradores (gente que te sigue pero tú no sigues)
                if !admirerIds.isEmpty {
                    dispatchGroup.enter()
                    self?.fetchUsersInBatches(userIds: Array(admirerIds)) { [weak self] users in
                        defer { dispatchGroup.leave() }
                        DispatchQueue.main.async {
                            self?.admirers = users
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.admirers = []
                    }
                }
                
                // 5. Completar cuando termine todo
                dispatchGroup.notify(queue: .main) {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                }
            }
        }
    }
    
    // ✅ NUEVO: Función helper para cargar usuarios en lotes
    private func fetchUsersInBatches(userIds: [String], completion: @escaping ([AppUser]) -> Void) {
        let batchSize = 10
        var allUsers: [AppUser] = []
        let dispatchGroup = DispatchGroup()
        
        for batch in stride(from: 0, to: userIds.count, by: batchSize) {
            let endIndex = min(batch + batchSize, userIds.count)
            let batchIds = Array(userIds[batch..<endIndex])
            
            dispatchGroup.enter()
            firestoreService.db.collection("users").whereField("__name__", in: batchIds).getDocuments { snapshot, error in
                defer { dispatchGroup.leave() }
                
                if let error = error {
                    // Error fetching batch
                    return
                }
                
                let users = snapshot?.documents.compactMap { doc -> AppUser? in
                    try? doc.data(as: AppUser.self)
                } ?? []
                
                allUsers.append(contentsOf: users)
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(allUsers)
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
