import SwiftUI

protocol UserListViewModel {
    func followUser(userId: String)
    func unfollowUser(userId: String)
}

enum UserListRowAction {
    case follow
    case unfollow
    case none
}

struct UserListView<ViewModel: UserListViewModel>: View {
    let title: String
    let users: [AppUser]
    let visitTimestamps: [String: [Date]]
    let viewModel: ViewModel
    let onDismiss: () -> Void
    let rowAction: UserListRowAction
    let onUserTap: ((AppUser) -> Void)?
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Header con título (sin handle custom)
            headerView
            
            // ✅ Searchbar para buscar usuarios
            searchBarView
            
            // ✅ Contenido principal
            contentView
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // ✅ Header actualizado sin padding extra del handle
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("\(users.count) \(users.count == 1 ? NSLocalizedString("userListView.person.singular", comment: "Person singular") : NSLocalizedString("userListView.person.plural", comment: "Person plural"))")
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
    
    // ✅ Searchbar para buscar usuarios
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 16))
            
            TextField(NSLocalizedString("userListView.search.placeholder", comment: "Search users placeholder"), text: $searchText)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // ✅ Usuarios filtrados por búsqueda
    private var filteredUsers: [AppUser] {
        if searchText.isEmpty {
            return users
        } else {
            return users.filter { user in
                user.username.localizedCaseInsensitiveContains(searchText) ||
                (user.bio?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    private var contentView: some View {
        Group {
            if filteredUsers.isEmpty {
                if users.isEmpty {
                    emptyStateView
                } else {
                    noResultsView
                }
            } else {
                userListView
            }
        }
    }
    
    // ✅ Estado vacío con el mismo estilo
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: getEmptyStateIcon())
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.6), Color(hex: "007AFF").opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text(String(format: NSLocalizedString("userListView.empty.title", comment: "Empty state title"), title.lowercased()))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(String(format: NSLocalizedString("userListView.empty.description", comment: "Empty state description"), title.lowercased()))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
    }
    
    // ✅ Lista de usuarios con scroll
    // ✅ Estado cuando no hay resultados de búsqueda
    private var noResultsView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.6), Color(hex: "007AFF").opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("userListView.noResults.title", comment: "No results title"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("userListView.noResults.description", comment: "No results description"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
    
    private var userListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredUsers.enumerated()), id: \.element.id) { index, user in
                    VStack(spacing: 0) {
                        ModernProfileUserRowView(
                            user: user,
                            visitTimestamps: visitTimestamps[user.id] ?? [],
                            rowAction: rowAction,
                            viewModel: viewModel,
                            onDismiss: onDismiss,
                            onUserTap: onUserTap
                        )

                        if index < filteredUsers.count - 1 {
                            Divider()
                                .overlay(
                                    (colorScheme == .dark ? Color.white : Color.black)
                                        .opacity(0.08)
                                )
                                .padding(.leading, 84)
                                .padding(.trailing, 20)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    
    private func getEmptyStateIcon() -> String {
        switch title.lowercased() {
        case "visitas":
            return "eye.slash"
        case "admiradores":
            return "heart.slash"
        case "conexiones":
            return "person.2.slash"
        case "conexiones mutuas":
            return "arrow.triangle.2.circlepath"
        default:
            return "person.slash"
        }
    }
}

// ✅ Fila de usuario modernizada con el estilo del ContextMenu
struct ModernProfileUserRowView<ViewModel: UserListViewModel>: View {
    let user: AppUser
    let visitTimestamps: [Date]
    let rowAction: UserListRowAction
    let viewModel: ViewModel
    let onDismiss: () -> Void
    let onUserTap: ((AppUser) -> Void)?
    
    @State private var isPressed: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // ✅ Avatar con anillo de historias y carga async consistente
            avatarView
            
            // ✅ Información del usuario
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(user.username)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if user.isVerified {
                        VerifiedBadge(size: 14)
                    }
                }
                
                // Bio o información adicional
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        .lineLimit(1)
                }
                
                // ✅ Indicador de visitas frecuentes modernizado
                if shouldShowFrequentVisitsIndicator() {
                    frequentVisitsIndicator
                }
            }
            
            Spacer()
            
            // ✅ Botón de acción modernizado
            actionButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            (colorScheme == .dark ? Color.white : Color.black)
                .opacity(isPressed ? 0.06 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { openUserProfile() }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
    
    // ✅ Avatar con círculo de fondo igual que el ContextMenu
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "007AFF").opacity(0.15))
                .frame(width: 48, height: 48)
            
            StoryRingAvatarView(
                userId: user.id,
                size: 44,
                lineWidth: 2.1,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                baseStrokeWidth: 0.9
            )
        }
    }
    
    // ✅ Indicador de visitas frecuentes con el estilo del ContextMenu
    private var frequentVisitsIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
            
            Text(NSLocalizedString("userListView.frequentVisits", comment: "Frequent visits indicator"))
                .font(.custom("Poppins-Medium", size: 10))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // ✅ Botón de acción con el estilo del ContextMenu
    private var actionButton: some View {
        Group {
            if rowAction == .follow {
                Button(action: {
                    viewModel.followUser(userId: user.id)
                    withAnimation(.easeOut(duration: 0.3)) {
                        onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                        Text(NSLocalizedString("userListView.followButton", comment: "Follow button"))
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "007AFF").opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color(hex: "007AFF").opacity(0.3), radius: 4, x: 0, y: 2)
                }
            } else if rowAction == .unfollow {
                Button(action: {
                    viewModel.unfollowUser(userId: user.id)
                    withAnimation(.easeOut(duration: 0.3)) {
                        onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 12, weight: .medium))
                        Text(NSLocalizedString("userListView.unfollowButton", comment: "Unfollow button"))
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .shadow(color: .red.opacity(0.2), radius: 2, x: 0, y: 1)
                }
            } else {
                // ✅ Chevron para otros casos
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
    }
    
    private func shouldShowFrequentVisitsIndicator() -> Bool {
        return visitTimestamps.count >= 3 &&
               visitTimestamps.allSatisfy { Date().timeIntervalSince($0) < 24 * 3600 }
    }

    private func openUserProfile() {
        if let onUserTap {
            onUserTap(user)
            return
        }

        withAnimation(.easeOut(duration: 0.25)) {
            onDismiss()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToProfile"),
                object: user.id
            )
        }
    }
}
