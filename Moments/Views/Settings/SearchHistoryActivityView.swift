import SwiftUI
import SwiftData
import Kingfisher
import FirebaseAuth

struct SearchHistoryActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var searches: [CachedSearch] = []
    @State private var userProfiles: [String: AppUser] = [:]
    
    // For social status
    @State private var followedUserIds: Set<String> = []
    @State private var followerUserIds: Set<String> = []
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()
            
            if searches.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                    Text(NSLocalizedString("userActivity.recentSearches.empty", value: "No hay búsquedas recientes", comment: "Empty search history"))
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.gray)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searches, id: \.id) { search in
                            VStack(spacing: 0) {
                                SearchHistoryRowView(
                                    search: search,
                                    userProfile: {
                                        if let targetId = search.targetId {
                                            return userProfiles[targetId]
                                        }
                                        return nil
                                    }(),
                                    socialStatus: {
                                        if search.type == "user", let targetId = search.targetId {
                                            return getSocialStatus(userId: targetId)
                                        }
                                        return nil
                                    }(),
                                    onDelete: { deleteSearch(search) }
                                )
                                
                                if search.id != searches.last?.id {
                                    Divider()
                                        .padding(.leading, 68)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(NSLocalizedString("userActivity.recentSearches.title", value: "Historial de búsquedas", comment: "Search history title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if !searches.isEmpty {
                    Button(action: {
                        clearAllSearches()
                    }) {
                        Text(NSLocalizedString("userActivity.recentSearches.clearAll", value: "Borrar todo", comment: "Clear all searches"))
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(Color(hex: "3B82F6"))
                    }
                }
            }
        }
        .onAppear {
            loadSearches()
            loadConnections()
        }
    }
    
    private func loadConnections() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let group = DispatchGroup()
        
        group.enter()
        FirestoreService.shared.fetchFollowing(userId: currentUserId) { result in
            defer { group.leave() }
            if case .success(let following) = result {
                DispatchQueue.main.async {
                    self.followedUserIds = Set(following.map { $0.id })
                }
            }
        }
        
        group.enter()
        FirestoreService.shared.fetchFollowers(userId: currentUserId) { result in
            defer { group.leave() }
            if case .success(let followers) = result {
                DispatchQueue.main.async {
                    self.followerUserIds = Set(followers.map { $0.id })
                }
            }
        }
    }
    
    private func getSocialStatus(userId: String) -> String? {
        let isFollowing = followedUserIds.contains(userId)
        let isFollower = followerUserIds.contains(userId)
        
        if isFollowing && isFollower {
            return NSLocalizedString("social.mutual", comment: "Mutual connection")
        } else if isFollower {
            return NSLocalizedString("social.followsYou", comment: "Follows you")
        } else if isFollowing {
            return NSLocalizedString("social.following", comment: "Following")
        }
        return nil
    }
    
    private func loadSearches() {
        searches = LocalPersistenceService.shared.loadRecentSearches()
        for search in searches {
            if search.type == "user", let targetId = search.targetId {
                loadUserProfile(userId: targetId)
            }
        }
    }
    
    private func loadUserProfile(userId: String) {
        if userProfiles[userId] == nil {
            FirestoreService.shared.fetchUserProfile(userId: userId) { result in
                switch result {
                case .success(let user):
                    DispatchQueue.main.async {
                        self.userProfiles[userId] = user
                    }
                case .failure(_):
                    break
                }
            }
        }
    }
    
    private func deleteSearch(_ search: CachedSearch) {
        LocalPersistenceService.shared.deleteSearch(id: search.id)
        withAnimation {
            searches.removeAll { $0.id == search.id }
        }
    }
    
    private func clearAllSearches() {
        LocalPersistenceService.shared.clearSearchHistory()
        withAnimation {
            searches.removeAll()
        }
    }
}

struct SearchHistoryRowView: View {
    let search: CachedSearch
    let userProfile: AppUser?
    let socialStatus: String?
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon or Profile Image
            ZStack {
                if search.type == "user", let user = userProfile, let imageUrl = user.profileImagePath, !imageUrl.isEmpty {
                    KFImage(URL(string: imageUrl))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(hex: "3B82F6").opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: getSearchIcon(for: search.type))
                        .foregroundColor(Color(hex: "3B82F6"))
                        .font(.system(size: 16))
                }
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(search.query)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                if search.type == "user" {
                    if let status = socialStatus {
                        Text(status)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    } else if let user = userProfile, let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    } else {
                        Text(NSLocalizedString("explore.recentSearches.type.user", value: "Usuario", comment: ""))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }
                } else {
                    // Si no es un usuario mostraremos el tipo explícito de la búsqueda
                    Text(getSearchTypeLabel(for: search.type))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Delete single search button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .foregroundColor(.gray)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(8)
                    .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func getSearchIcon(for type: String) -> String {
        switch type {
        case "hashtag": return "number"
        case "user": return "person.fill"
        case "location": return "mappin.and.ellipse"
        default: return "magnifyingglass"
        }
    }
    
    private func getSearchTypeLabel(for type: String) -> String {
        switch type {
        case "hashtag": return NSLocalizedString("explore.recentSearches.type.hashtag", value: "Hashtag", comment: "")
        case "location": return NSLocalizedString("explore.recentSearches.type.location", value: "Ubicación", comment: "")
        default: return NSLocalizedString("explore.recentSearches.type.text", value: "Búsqueda textual", comment: "")
        }
    }
}
