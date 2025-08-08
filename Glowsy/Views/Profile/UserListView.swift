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
    let visitTimestamps: [String: [Date]] // Mapa de userId a timestamps de visitas
    let viewModel: ViewModel
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Fondo degradado similar al resto de la app
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.9),
                    Color(hex: "00A896").opacity(0.2),
                    Color.black.opacity(0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header personalizado con glassmorphism
                headerView
                
                // Contenido principal
                contentView
            }
        }
    }
    
    private var headerView: some View {
        ZStack {
            // Fondo glassmorphic para el header
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color(hex: "00A896").opacity(0.2),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Rectangle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "00A896").opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        ),
                    alignment: .bottom
                )
            
            HStack {
                // Título con estilo consistente
                Text(title)
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(hex: "00A896").opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Spacer()
                
                // Botón de cerrar con glassmorphism
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color(hex: "00A896").opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.1), value: false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(height: 70)
    }
    
    private var contentView: some View {
        Group {
            if users.isEmpty {
                emptyStateView
            } else {
                userListView
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: getEmptyStateIcon())
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.6), Color(hex: "00A896").opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("No hay \(title.lowercased())")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(.white.opacity(0.8))
            
            Text("Cuando tengas \(title.lowercased()), aparecerán aquí")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
    
    private var userListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(users) { user in
                    ProfileUserRowView(
                        user: user,
                        visitTimestamps: visitTimestamps[user.id] ?? [],
                        title: title,
                        viewModel: viewModel,
                        onDismiss: onDismiss
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
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

struct ProfileUserRowView<ViewModel: UserListViewModel>: View {
    let user: AppUser
    let visitTimestamps: [Date]
    let title: String
    let viewModel: ViewModel
    let onDismiss: () -> Void
    
    @State private var isPressed: Bool = false
    
    var body: some View {
        ZStack {
            // Fondo glassmorphic para cada fila
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color(hex: "00A896").opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color(hex: "00A896").opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: .black.opacity(0.1),
                    radius: isPressed ? 2 : 8,
                    x: 0,
                    y: isPressed ? 1 : 4
                )
            
            HStack(spacing: 12) {
                // Avatar con borde mejorado
                avatarView
                
                // Información del usuario
                VStack(alignment: .leading, spacing: 4) {
                    VerifiedUsernameView(
                        username: user.username,
                        isVerified: user.isVerified,
                        usernameColor: .white,
                        badgeSize: 14,
                        spacing: 4
                    )
                    .font(.custom("Poppins-SemiBold", size: 16))
                    
                    // Bio o información adicional
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    // Indicador de visitas frecuentes mejorado
                    if shouldShowFrequentVisitsIndicator() {
                        frequentVisitsIndicator
                    }
                }
                
                Spacer()
                
                // Botón de acción mejorado
                actionButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            // Aquí podrías navegar al perfil del usuario
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )
    }
    
    private var avatarView: some View {
        Group {
            if let profileImagePath = user.profileImagePath, let url = URL(string: profileImagePath) {
                KFImage(url)
                    .placeholder {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.gray.opacity(0.6))
                            
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color(hex: "00A896"))
                        }
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color(hex: "00A896").opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.gray.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    private var frequentVisitsIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            
            Text("Visitas frecuentes")
                .font(.custom("Poppins-SemiBold", size: 10))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private var actionButton: some View {
        Group {
            if title == "Visitas" || title == "Admiradores" {
                Button(action: {
                    viewModel.followUser(userId: user.id)
                    onDismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Seguir")
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(hex: "00A896"),
                                Color(hex: "00A896").opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "00A896").opacity(0.3), radius: 4, x: 0, y: 2)
                }
            } else if title == "Conexiones" || title == "Conexiones Mutuas" {
                Button(action: {
                    viewModel.unfollowUser(userId: user.id)
                    onDismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Dejar de seguir")
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.5),
                                        Color.blue.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .blue.opacity(0.2), radius: 2, x: 0, y: 1)
                }
            }
        }
    }
    
    private func shouldShowFrequentVisitsIndicator() -> Bool {
        return visitTimestamps.count >= 3 &&
               visitTimestamps.allSatisfy { Date().timeIntervalSince($0) < 24 * 3600 }
    }
}


struct UserListView_Previews: PreviewProvider {
    static var previews: some View {
        UserListView(
            title: "Visitas",
            users: [
                AppUser(
                    id: "1",
                    username: "testuser",
                    email: "test@example.com",
                    interests: [],
                    isPlusSubscriber: false,
                    profileImagePath: nil,
                    bio: "Esta es una biografía de ejemplo",
                    blockedUsers: [],
                    isPrivate: false,
                    activeHoursStart: nil,
                    activeHoursEnd: nil,
                    notificationPreferences: nil,
                    bestFriends: []
                ),
                AppUser(
                    id: "2",
                    username: "usuario2",
                    email: "user2@example.com",
                    interests: [],
                    isPlusSubscriber: false,
                    profileImagePath: nil,
                    bio: "Otra biografía",
                    blockedUsers: [],
                    isPrivate: false,
                    activeHoursStart: nil,
                    activeHoursEnd: nil,
                    notificationPreferences: nil,
                    bestFriends: []
                )
            ],
            visitTimestamps: [
                "1": [Date(), Date().addingTimeInterval(-3600), Date().addingTimeInterval(-7200)],
                "2": [Date().addingTimeInterval(-86400)]
            ],
            viewModel: MockUserListViewModel(),
            onDismiss: {}
        )
        .preferredColorScheme(.dark)
    }
}

class MockUserListViewModel: UserListViewModel {
    func followUser(userId: String) {
        print("Following user: \(userId)")
    }
    
    func unfollowUser(userId: String) {
        print("Unfollowing user: \(userId)")
    }
}
