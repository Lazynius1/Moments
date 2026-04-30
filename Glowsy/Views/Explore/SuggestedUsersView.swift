import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SuggestedUsersView: View {
    @StateObject private var viewModel = SuggestedUsersViewModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var navigateToProfile: Bool = false
    @State private var selectedUserId: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header con título
            headerView
            
            // Contenido principal
            contentView
        }
        .onAppear {
            viewModel.loadInitialUsers()
        }
        .sheet(isPresented: $navigateToProfile) {
            if !selectedUserId.isEmpty {
                UserProfileView(userId: selectedUserId)
            } else {
                Text("Error: Usuario no válido")
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("explore.suggestedUsers.title")
                .font(.custom("Poppins-SemiBold", size: 20))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    
    // MARK: - Content View
    private var contentView: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("explore.suggestedUsers.loading")
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.users.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 60))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("explore.suggestedUsers.empty")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(.primary)
                    
                    Text("explore.suggestedUsers.emptyDescription")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.users) { user in
                            SuggestedUserRow(
                                user: user,
                                commonInterests: Set(user.interests).intersection(Set(viewModel.currentUserInterests)).count,
                                buttonState: viewModel.userButtonStates[user.id] ?? .canFollow,
                                onFollow: { viewModel.followUser(user.id) },
                                onTap: { 
                                    if !user.id.isEmpty {
                                        selectedUserId = user.id
                                        navigateToProfile = true
                                    }
                                }
                            )
                            .onAppear {
                                if user.id == viewModel.users.last?.id {
                                    viewModel.loadMoreUsers()
                                }
                            }
                        }
                        
                        // Indicador de carga para scroll infinito
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("explore.suggestedUsers.loadingMore")
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    await viewModel.refreshUsers()
                }
            }
        }
    }
    
}

// MARK: - Fila de Usuario Sugerido
struct SuggestedUserRow: View {
    let user: AppUser
    let commonInterests: Int
    let buttonState: FollowButtonState
    let onFollow: () -> Void
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Button(action: onTap) {
                AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                        Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            }
            
            // Información del usuario
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        Text(user.username)
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.primary)
                        
                        if user.isVerified {
                            VerifiedBadge(size: 12)
                        }
                    }
                }
                
                if commonInterests > 0 {
                    Text(String(format: NSLocalizedString("explore.suggestedUsers.commonInterests", comment: "Common interests"), commonInterests))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                }
                
                // Intereses (máximo 2)
                if !user.interests.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(user.interests.prefix(2)), id: \.self) { interest in
                            Text(interest)
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.72))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlass(in: Capsule())
                        }
                        
                        if user.interests.count > 2 {
                            Text("+\(user.interests.count - 2)")
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .liquidGlass(in: Capsule())
                        }
                    }
                }
            }
            
            Spacer()
            
            // Botón de seguir
            SuggestedUserFollowButton(
                state: buttonState,
                onFollow: onFollow
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Botón de Seguir
struct SuggestedUserFollowButton: View {
    let state: FollowButtonState
    let onFollow: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onFollow) {
            HStack(spacing: 6) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 12, weight: .medium))
                Text(buttonText)
                    .font(.custom("Poppins-SemiBold", size: 12))
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12), interactive: state.isActionable)
        }
        .disabled(!state.isActionable)
        .opacity(isPassiveState ? 0.78 : 1)
    }
    
    private var buttonText: String {
        switch state {
        case .canFollow:
            return NSLocalizedString("followButton.follow", comment: "Follow button")
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "Following button")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "Requested button")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "Request button")
        case .ownProfile:
            return NSLocalizedString("followButton.ownProfile", comment: "Own profile button")
        case .blocked:
            return NSLocalizedString("followButton.blocked", comment: "Blocked button")
        }
    }
    
    private var buttonIcon: String {
        switch state {
        case .canFollow, .canRequestFollow:
            return "person.badge.plus"
        case .following:
            return "person.fill.checkmark"
        case .requestPending:
            return "clock"
        case .ownProfile:
            return "person.circle"
        case .blocked:
            return "person.crop.circle.badge.exclamationmark"
        }
    }

    private var isPassiveState: Bool {
        if case .requestPending = state {
            return true
        }
        return false
    }
    
    private var buttonBackgroundColor: Color {
        switch state {
        case .canFollow, .canRequestFollow:
            return Color(hex: "007AFF").opacity(0.8)
        case .following:
            return Color.red.opacity(0.2)
        case .requestPending:
            return Color.orange.opacity(0.8)
        case .ownProfile, .blocked:
            return Color.gray.opacity(0.5)
        }
    }
    
    private var buttonBorderColor: Color {
        switch state {
        case .canFollow, .canRequestFollow:
            return Color.white.opacity(0.2)
        case .following:
            return Color.red.opacity(0.3)
        case .requestPending:
            return Color.white.opacity(0.2)
        case .ownProfile, .blocked:
            return Color.white.opacity(0.2)
        }
    }
    
    private var buttonShadowColor: Color {
        switch state {
        case .canFollow, .canRequestFollow:
            return Color(hex: "007AFF").opacity(0.3)
        case .following:
            return Color.red.opacity(0.2)
        case .requestPending:
            return Color.orange.opacity(0.3)
        case .ownProfile, .blocked:
            return Color.gray.opacity(0.3)
        }
    }
    
    private var buttonShadowRadius: CGFloat {
        switch state {
        case .following:
            return 2
        default:
            return 4
        }
    }
}

// MARK: - ViewModel
class SuggestedUsersViewModel: ObservableObject {
    @Published var users: [AppUser] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var userButtonStates: [String: FollowButtonState] = [:]
    @Published var currentUserInterests: [String] = []
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService()
    private var currentUserId: String?
    private var blockedUsers: Set<String> = []
    private var followedUserIds: Set<String> = [] // Usuarios ya seguidos
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 10
    private var followStateObserver: NSObjectProtocol?

    init() {
        followStateObserver = NotificationCenter.default.addObserver(
            forName: FollowStateStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userId = notification.userInfo?["userId"] as? String,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            self?.userButtonStates[userId] = state
        }
    }

    deinit {
        if let followStateObserver {
            NotificationCenter.default.removeObserver(followStateObserver)
        }
    }
    
    func loadInitialUsers() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        currentUserId = userId
        isLoading = true
        
        // Cargar intereses del usuario actual
        loadCurrentUserInterests()
        
        // Cargar usuarios bloqueados
        loadBlockedUsers()
        
        // Cargar usuarios seguidos primero
        loadFollowedUsers { [weak self] in
            // Cargar usuarios sugeridos (ya con usuarios seguidos cargados)
            self?.loadSuggestedUsers()
        }
    }
    
    private func loadCurrentUserInterests() {
        guard let userId = currentUserId else { return }
        
        firestoreService.db.collection("users").document(userId).getDocument { [weak self] document, error in
            if let data = document?.data(),
               let interests = data["interests"] as? [String] {
                DispatchQueue.main.async {
                    self?.currentUserInterests = interests
                }
            }
        }
    }
    
    private func loadBlockedUsers() {
        guard let userId = currentUserId else { return }
        
        firestoreService.db.collection("users").document(userId).getDocument { [weak self] document, error in
            if let data = document?.data(),
               let blocked = data["blockedUsers"] as? [String] {
                DispatchQueue.main.async {
                    self?.blockedUsers = Set(blocked)
                }
            }
        }
    }
    
    // Cargar usuarios seguidos
    private func loadFollowedUsers(completion: @escaping () -> Void) {
        guard let userId = currentUserId else {
            completion()
            return
        }
        
        firestoreService.fetchFollowing(userId: userId) { [weak self] result in
            switch result {
            case .success(let users):
                DispatchQueue.main.async {
                    self?.followedUserIds = Set(users.map { $0.id })
                    completion()
                }
            case .failure(_):
                // Aún si falla, llamamos al completion para cargar sugeridos
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    private func loadSuggestedUsers() {
        guard let userId = currentUserId else { return }
        
        firestoreService.db.collection("users")
            .whereField("isPrivate", isEqualTo: false)
            .limit(to: pageSize)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                
                if let error = error {
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let newUsers = documents.compactMap { doc -> AppUser? in
                    do {
                        let user = try doc.data(as: AppUser.self)
                        return user.id != userId ? user : nil
                    } catch {
                        return nil
                    }
                }
                
                // Filtrar usuarios bloqueados Y usuarios ya seguidos
                let filteredUsers = newUsers.filter { user in
                    !(self?.blockedUsers.contains(user.id) ?? false) &&
                    !(user.blockedUsers ?? []).contains(userId) &&
                    !(self?.followedUserIds.contains(user.id) ?? false) // Excluir usuarios ya seguidos
                }
                
                // Ordenar por intereses comunes
                let sortedUsers = filteredUsers.sorted { user1, user2 in
                    let commonInterests1 = Set(user1.interests).intersection(self?.currentUserInterests ?? []).count
                    let commonInterests2 = Set(user2.interests).intersection(self?.currentUserInterests ?? []).count
                    return commonInterests1 > commonInterests2
                }
                
                DispatchQueue.main.async {
                    self?.users = sortedUsers
                    self?.lastDocument = documents.last
                    
                    // Actualizar estados de botones
                    for user in sortedUsers {
                        self?.checkUserButtonState(for: user.id)
                    }
                }
            }
    }
    
    func loadMoreUsers() {
        guard !isLoadingMore, let lastDoc = lastDocument else { return }
        
        isLoadingMore = true
        
        firestoreService.db.collection("users")
            .whereField("isPrivate", isEqualTo: false)
            .start(afterDocument: lastDoc)
            .limit(to: pageSize)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    self?.isLoadingMore = false
                }
                
                if let error = error {
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else { return }
                
                let newUsers = documents.compactMap { doc -> AppUser? in
                    do {
                        let user = try doc.data(as: AppUser.self)
                        return user.id != self?.currentUserId ? user : nil
                    } catch {
                        return nil
                    }
                }
                
                // Filtrar usuarios bloqueados, duplicados Y usuarios ya seguidos
                let existingIds = Set(self?.users.map { $0.id } ?? [])
                let filteredUsers = newUsers.filter { user in
                    !existingIds.contains(user.id) &&
                    !(self?.blockedUsers.contains(user.id) ?? false) &&
                    !(user.blockedUsers ?? []).contains(self?.currentUserId ?? "") &&
                    !(self?.followedUserIds.contains(user.id) ?? false) // Excluir usuarios ya seguidos
                }
                
                // Ordenar por intereses comunes
                let sortedUsers = filteredUsers.sorted { user1, user2 in
                    let commonInterests1 = Set(user1.interests).intersection(self?.currentUserInterests ?? []).count
                    let commonInterests2 = Set(user2.interests).intersection(self?.currentUserInterests ?? []).count
                    return commonInterests1 > commonInterests2
                }
                
                DispatchQueue.main.async {
                    self?.users.append(contentsOf: sortedUsers)
                    self?.lastDocument = documents.last
                    
                    // Actualizar estados de botones para nuevos usuarios
                    for user in sortedUsers {
                        self?.checkUserButtonState(for: user.id)
                    }
                }
            }
    }
    
    func refreshUsers() async {
        users = []
        userButtonStates = [:]
        followedUserIds = [] // Limpiar usuarios seguidos para recargar
        lastDocument = nil
        loadInitialUsers()
    }
    
    func followUser(_ userId: String) {
        guard let currentUserId = currentUserId else { return }
        
        // No cambiar el estado a loading, mantener el estado actual
        firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.userButtonStates[userId] = .following
                    FollowStateStore.shared.setState(.following, for: userId)
                    self?.followedUserIds.insert(userId) // Agregar a usuarios seguidos
                    // Eliminar de la lista de usuarios sugeridos
                    if let index = self?.users.firstIndex(where: { $0.id == userId }) {
                        self?.users.remove(at: index)
                    }
                } else {
                    // En caso de error, recargar el estado del botón
                    self?.checkUserButtonState(for: userId)
                }
            }
        }
    }
    
    
    private func checkUserButtonState(for userId: String) {
        guard let currentUserId = currentUserId else { return }

        if let cachedState = FollowStateStore.shared.state(for: userId) {
            userButtonStates[userId] = cachedState
        }
        
        privacyService.getFollowButtonState(
            viewerId: currentUserId,
            targetUserId: userId
        ) { [weak self] (state: FollowButtonState) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let reconciledState = FollowStateStore.shared.reconciledState(state, for: userId)
                self.userButtonStates[userId] = reconciledState
                FollowStateStore.shared.setState(reconciledState, for: userId)
                
                // Si el estado es "siguiendo", agregar a followedUserIds y eliminar de sugerencias
                if reconciledState == .following {
                    self.followedUserIds.insert(userId)
                    // Eliminar de la lista de sugerencias
                    if let index = self.users.firstIndex(where: { $0.id == userId }) {
                        self.users.remove(at: index)
                    }
                }
            }
        }
    }
}


#Preview {
    SuggestedUsersView()
}
