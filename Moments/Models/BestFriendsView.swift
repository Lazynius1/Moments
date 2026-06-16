import SwiftUI
import FirebaseAuth

struct BestFriendsView: View {
    @StateObject private var viewModel = BestFriendsViewModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // ✅ NUEVO: Estado para búsqueda
    @State private var searchText = ""
    @State private var visibleUserLimit = 30
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView()
                } else if hasAnyUsers == false {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle(NSLocalizedString("bestFriends.title", comment: "Best Friends"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }

            .onAppear {
                viewModel.fetchBestFriends()
                viewModel.fetchConnections()
            }
            .onChange(of: searchText) { _, _ in
                visibleUserLimit = 30
                viewModel.searchUsersGlobally(query: searchText)
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
                Text(NSLocalizedString("bestFriends.empty.title", comment: "No best friends"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(.primary)
                
                Text(NSLocalizedString("bestFriends.empty.description", comment: "Add friends from your following to mark them as best friends."))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
    }

    private var filteredResults: (bestFriends: [AppUser], connections: [AppUser], mutualConnections: [AppUser], admirers: [AppUser]) {
        viewModel.filteredUsers(searchText: searchText)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchingMode: Bool {
        isSearchFieldFocused || !trimmedSearchText.isEmpty
    }

    private var selectedIds: Set<String> {
        Set(viewModel.bestFriends.map(\.id))
    }

    private var hasAnyUsers: Bool {
        !viewModel.bestFriends.isEmpty ||
        !viewModel.connections.isEmpty ||
        !viewModel.mutualConnections.isEmpty ||
        !viewModel.admirers.isEmpty
    }

    private var visibleMutuals: [AppUser] {
        filteredResults.mutualConnections.filter { connection in
            !viewModel.bestFriends.contains(where: { $0.id == connection.id })
        }
    }

    private var visibleConnections: [AppUser] {
        filteredResults.connections.filter { connection in
            !viewModel.bestFriends.contains(where: { $0.id == connection.id })
        }
    }

    private var selectedUsers: [AppUser] {
        deduplicatedUsers(filteredResults.bestFriends)
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    private var suggestedUsers: [AppUser] {
        deduplicatedUsers(
            visibleMutuals +
            visibleConnections +
            filteredResults.admirers +
            viewModel.remoteSearchResults
        )
        .filter { !selectedIds.contains($0.id) }
        .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    private var displayedSuggestedUsers: [AppUser] {
        Array(suggestedUsers.prefix(visibleUserLimit))
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            // ✅ NUEVO: Campo de búsqueda debajo del título
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.6))
                    .font(.system(size: 16, weight: .medium))
                
                TextField(NSLocalizedString("bestFriends.search.placeholder", comment: "Search lists..."), text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .focused($isSearchFieldFocused)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.45))
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .momentsChromeGlass(in: Capsule(), interactive: true)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if isSearchingMode == false && selectedUsers.isEmpty == false {
                        userSectionHeader(NSLocalizedString("bestFriends.title", comment: "Best Friends"))

                        LazyVStack(spacing: 0) {
                            ForEach(selectedUsers) { user in
                                SelectableBestFriendRow(
                                    user: user,
                                    isSelected: true,
                                    colorScheme: colorScheme
                                ) {
                                    toggleSelection(for: user)
                                }
                            }
                        }
                    }

                    if isSearchingMode == false || displayedSuggestedUsers.isEmpty == false {
                        userSectionHeader(NSLocalizedString("explore.suggestedUsers.title", comment: "People you might be interested in"))

                        LazyVStack(spacing: 0) {
                            ForEach(displayedSuggestedUsers) { user in
                                SelectableBestFriendRow(
                                    user: user,
                                    isSelected: viewModel.bestFriends.contains(where: { $0.id == user.id }),
                                    colorScheme: colorScheme
                                ) {
                                    toggleSelection(for: user)
                                }
                                .onAppear {
                                    loadMoreIfNeeded(currentUser: user)
                                }
                            }
                        }
                    }

                    if displayedSuggestedUsers.isEmpty &&
                        isSearchingMode {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text(String(format: NSLocalizedString("bestFriends.search.noResults", comment: "No results found for '%@'"), searchText))
                                .foregroundColor(.secondary)
                                .font(.custom("Poppins-Regular", size: 14))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func userSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.custom("Poppins-SemiBold", size: 12))
            .foregroundColor(.gray.opacity(0.8))
            .padding(.leading, 4)
    }

    private func deduplicatedUsers(_ users: [AppUser]) -> [AppUser] {
        var seen = Set<String>()
        return users.filter { user in
            seen.insert(user.id).inserted
        }
    }

    private func toggleSelection(for user: AppUser) {
        if viewModel.bestFriends.contains(where: { $0.id == user.id }) {
            viewModel.removeBestFriend(userId: user.id)
        } else {
            viewModel.addBestFriend(userId: user.id)
        }
    }

    private func loadMoreIfNeeded(currentUser: AppUser) {
        guard let currentIndex = displayedSuggestedUsers.firstIndex(where: { $0.id == currentUser.id }) else { return }
        let thresholdIndex = max(displayedSuggestedUsers.count - 5, 0)

        if currentIndex >= thresholdIndex && visibleUserLimit < suggestedUsers.count {
            visibleUserLimit += 30
        }
    }
}

struct SelectableBestFriendRow: View {
    let user: AppUser
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                ProfileImageView(imagePath: user.profileImagePath)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                Text(user.username)
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(
                        isSelected
                        ? (colorScheme == .dark ? .white : .black)
                        : (colorScheme == .dark ? .white.opacity(0.32) : .black.opacity(0.28))
                    )
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
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
                Text(NSLocalizedString("bestFriends.button.remove", comment: "Remove"))
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
                Text(NSLocalizedString("bestFriends.button.add", comment: "Add"))
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
                Text(NSLocalizedString("bestFriends.button.addGeneric", comment: "Add"))
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
    @Published var remoteSearchResults: [AppUser] = []
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    
    private let bestFriendsService: BestFriendsService
    private let firestoreService: FirestoreService
    private var currentUserId: String?
    private var blockedUserIds: Set<String> = []
    private var searchWorkItem: DispatchWorkItem?
    
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
        self.currentUserId = Auth.auth().currentUser?.uid
    }

    func fetchBestFriends() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = NSLocalizedString("bestFriends.error.auth", comment: "User not authenticated")
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
            errorMessage = NSLocalizedString("bestFriends.error.auth", comment: "User not authenticated")
            showError = true
            return
        }
        
        isLoading = true
        
        // ✅ NUEVO: Usar la misma lógica que ProfileView
        let dispatchGroup = DispatchGroup()

        firestoreService.db.collection("users").document(userId).getDocument { [weak self] document, _ in
            let blocked = document?.data()?["blockedUsers"] as? [String] ?? []
            DispatchQueue.main.async {
                self?.blockedUserIds = Set(blocked)
            }
        }
        
        // 1. Obtener usuarios que sigues
        dispatchGroup.enter()
        firestoreService.db.collection("users").document(userId).collection("following").getDocuments { [weak self] snapshot, error in
            defer { dispatchGroup.leave() }
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = String(format: NSLocalizedString("bestFriends.error.following", comment: "Error loading following: %@"), error.localizedDescription)
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
                        self?.errorMessage = String(format: NSLocalizedString("bestFriends.error.followers", comment: "Error loading followers: %@"), error.localizedDescription)
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

    func searchUsersGlobally(query: String) {
        let cleanQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        searchWorkItem?.cancel()

        guard !cleanQuery.isEmpty else {
            remoteSearchResults = []
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.firestoreService.searchUsers(query: cleanQuery) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }

                    switch result {
                    case .success(let users):
                        let filtered = users.filter { user in
                            guard user.id != self.currentUserId else { return false }
                            if self.blockedUserIds.contains(user.id) { return false }
                            if user.blockedUsers.contains(self.currentUserId ?? "") { return false }
                            return true
                        }
                        self.remoteSearchResults = filtered
                    case .failure(_):
                        self.remoteSearchResults = []
                    }
                }
            }
        }

        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
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
                
                if error != nil {
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
            errorMessage = NSLocalizedString("bestFriends.error.auth", comment: "User not authenticated")
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
            errorMessage = NSLocalizedString("bestFriends.error.auth", comment: "User not authenticated")
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
