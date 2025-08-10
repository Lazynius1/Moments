import SwiftUI
import FirebaseStorage
import Kingfisher

protocol UserListViewModel {
    func followUser(userId: String)
    func unfollowUser(userId: String)
}

struct UserListView<ViewModel: UserListViewModel>: View {
    let title: String
    let users: [AppUser]
    let visitTimestamps: [String: [Date]]
    let viewModel: ViewModel
    let onDismiss: () -> Void
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
            
            // ✅ Botón cerrar en la parte inferior
            cancelButton
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "00A896").opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // ✅ Header actualizado sin padding extra del handle
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("\(users.count) \(users.count == 1 ? "persona" : "personas")")
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
            
            TextField("Buscar usuarios...", text: $searchText)
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
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
                            colors: [Color.gray.opacity(0.6), Color(hex: "00A896").opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No hay \(title.lowercased())")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Cuando tengas \(title.lowercased()), aparecerán aquí")
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
                            colors: [Color.gray.opacity(0.6), Color(hex: "00A896").opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No se encontraron resultados")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Intenta con otros términos de búsqueda")
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
            LazyVStack(spacing: 8) {
                ForEach(filteredUsers) { user in
                    ModernProfileUserRowView(
                        user: user,
                        visitTimestamps: visitTimestamps[user.id] ?? [],
                        title: title,
                        viewModel: viewModel,
                        onDismiss: onDismiss
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
    
    // ✅ Botón cancelar idéntico al ContextMenu
    private var cancelButton: some View {
        Button("Cerrar") {
            withAnimation(.easeOut(duration: 0.3)) {
                onDismiss()
            }
        }
        .font(.custom("Poppins-SemiBold", size: 16))
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
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
    let title: String
    let viewModel: ViewModel
    let onDismiss: () -> Void
    
    @State private var isPressed: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            // Acción de tap (navegar al perfil)
        }) {
            HStack(spacing: 16) {
                // ✅ Avatar con el mismo estilo que el ContextMenu
                avatarView
                
                // ✅ Información del usuario
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(user.username)
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isPressed ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
                .fill(Color(hex: "00A896").opacity(0.15))
                .frame(width: 48, height: 48)
            
            if let profileImagePath = user.profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .placeholder {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
        }
    }
    
    // ✅ Indicador de visitas frecuentes con el estilo del ContextMenu
    private var frequentVisitsIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange)
            
            Text("Visitas frecuentes")
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
            if title == "Visitas" || title == "Admiradores" {
                Button(action: {
                    viewModel.followUser(userId: user.id)
                    withAnimation(.easeOut(duration: 0.3)) {
                        onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Seguir")
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "00A896").opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 4, x: 0, y: 2)
                }
            } else if title == "Conexiones" || title == "Conexiones Mutuas" {
                Button(action: {
                    viewModel.unfollowUser(userId: user.id)
                    withAnimation(.easeOut(duration: 0.3)) {
                        onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Dejar")
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
}
