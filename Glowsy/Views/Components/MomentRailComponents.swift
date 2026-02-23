import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// ✅ REUSABLE: Sistema de colores adaptativos
struct AdaptiveColors {
    let colorScheme: ColorScheme
    
    var background: Color {
        colorScheme == .dark ? .black : .white
    }
    
    // Colores principales
    var primary: Color {
        colorScheme == .dark ? .white : .black
    }
    
    var secondary: Color {
        colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)
    }
    
    var tertiary: Color {
        colorScheme == .dark ? .gray.opacity(0.6) : .gray.opacity(0.8)
    }
    
    // Colores de acento
    var accent: Color {
        Color(hex: "007AFF") // Royal Blue (Premium)
    }
    
    var accentSecondary: Color {
        colorScheme == .dark ? Color(hex: "007AFF").opacity(0.3) : Color(hex: "007AFF").opacity(0.6)
    }
    
    // Colores de fondo
    var cardBackground: Material {
        .ultraThinMaterial
    }
    
    var overlayStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.2), Color(hex: "007AFF").opacity(0.3)] :
        [Color.black.opacity(0.1), Color(hex: "007AFF").opacity(0.4)]
    }
    
    // Colores para botones
    var buttonStroke: [Color] {
        colorScheme == .dark ?
        [Color.white.opacity(0.3), Color(hex: "007AFF").opacity(0.3)] :
        [Color.black.opacity(0.2), Color(hex: "007AFF").opacity(0.5)]
    }
    
    var buttonGradient: [Color] {
        colorScheme == .dark ?
        [Color(hex: "007AFF"), Color.white.opacity(0.8)] :
        [Color(hex: "007AFF"), Color.black.opacity(0.7)]
    }
    
    // Sombras
    var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.1) : .black.opacity(0.15)
    }
}

// ✅ REUSABLE: ModernActionButtons (Glow Rail)
struct ModernActionButtons: View {
    let moment: Moment
    @Binding var isSaved: Bool
    @Binding var isSaveLoading: Bool
    @Binding var commentCount: Int
    let onComment: () -> Void
    let onSave: () -> Void
    let onContextMenu: () -> Void 
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme 
    @Binding var isImmersive: Bool 
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            HStack(spacing: 8) {
                // ✅ REACCIONES
                EpicReactionButton(
                    moment: moment,
                    showCount: moment.authorId == Auth.auth().currentUser?.uid || !moment.hideLikeCounts
                )
                .environmentObject(firestoreService)
                
                // ✅ COMENTARIOS
                if !moment.disableComments {
                    Button(action: onComment) {
                        iconButton(
                            systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left",
                            color: commentCount > 0 ? .blue : .white,
                            secondaryColor: commentCount > 0 ? .purple : .white,
                            isActive: commentCount > 0,
                            count: commentCount
                        )
                    }
                }
                
                // ✅ GUARDAR
                if moment.allowSharing {
                    Button(action: onSave) {
                        if isSaveLoading {
                            ProgressView()
                                .frame(width: 44, height: 44)
                                .tint(.white)
                        } else {
                            iconButton(
                                systemName: isSaved ? "bookmark.fill" : "bookmark",
                                color: isSaved ? .yellow : .white,
                                secondaryColor: isSaved ? .orange : .white,
                                isActive: isSaved
                            )
                        }
                    }
                }
                
                // ✅ OPCIONES (Ellipsis integrada)
                Button(action: {
                    HapticManager.shared.lightImpact()
                    onContextMenu()
                }) {
                    iconButton(
                        systemName: "ellipsis",
                        color: .white,
                        secondaryColor: .white.opacity(0.8),
                        isActive: false
                    )
                }
            }
            .padding(6)
            .liquidGlass(in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            .opacity(isImmersive ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: isImmersive)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }
    
    // ✅ Función auxiliar para botones de icono compactos con soporte para contador
    @ViewBuilder
    private func iconButton(systemName: String, color: Color, secondaryColor: Color, isActive: Bool, count: Int? = nil) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(isActive ? 1.05 : 1.0)
            
            // ✅ BADGE DE CONTADOR (Estilo Epic)
            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isActive ? color : Color.gray.opacity(0.6))
                    )
                    .offset(x: 4, y: -4)
            }
        }
    }
}

// ✅ REUSABLE: ModernFollowButton
struct ModernFollowButton: View {
    let isFollowing: Bool
    let isLoading: Bool
    let colorScheme: ColorScheme 
    let action: () -> Void
    
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.mediumImpact()
            action()
        }) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                
                Text(isFollowing ? NSLocalizedString("userListView.unfollowButton", comment: "") : NSLocalizedString("userListView.followButton", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 14))
            }
            .foregroundColor(isFollowing ? adaptiveColors.primary : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isFollowing ? adaptiveColors.primary.opacity(0.1) : Color(hex: "007AFF"))
            )
            .shadow(color: isFollowing ? .black.opacity(0.1) : Color(hex: "007AFF").opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(isLoading)
    }
}
