import SwiftUI

struct VerifiedBadge: View {
    let size: CGFloat
    let gradient: LinearGradient
    
    init(size: CGFloat = 16, gradient: LinearGradient? = nil) {
        self.size = size
        self.gradient = gradient ?? LinearGradient(
            colors: [Color.blue, Color.purple, Color.pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(gradient)
    }
}

struct VerifiedUsernameView: View {
    let username: String
    let isVerified: Bool
    let usernameColor: Color
    let badgeSize: CGFloat
    let spacing: CGFloat
    
    init(
        username: String,
        isVerified: Bool,
        usernameColor: Color = .primary,
        badgeSize: CGFloat = 16,
        badgeColor: Color = .blue,
        spacing: CGFloat = 4
    ) {
        self.username = username
        self.isVerified = isVerified
        self.usernameColor = usernameColor
        self.badgeSize = badgeSize
        self.spacing = spacing
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            Text(username)
                .foregroundColor(usernameColor)
            
            if isVerified {
                VerifiedBadge(size: badgeSize)
            }
        }
    }
}

// ✅ NUEVA: Versión que funciona con gradients
struct VerifiedUsernameGradientView: View {
    let username: String
    let isVerified: Bool
    let badgeSize: CGFloat
    let spacing: CGFloat
    let gradient: LinearGradient
    
    init(
        username: String,
        isVerified: Bool,
        badgeSize: CGFloat = 16,
        spacing: CGFloat = 4,
        gradient: LinearGradient
    ) {
        self.username = username
        self.isVerified = isVerified
        self.badgeSize = badgeSize
        self.spacing = spacing
        self.gradient = gradient
    }
    
    var body: some View {
        HStack(spacing: spacing) {
            Text(username)
                .foregroundStyle(gradient)
            
            if isVerified {
                VerifiedBadge(size: badgeSize)
            }
        }
    }
}

// MARK: - Preview
struct VerifiedBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Solo la chapita
            VerifiedBadge(size: 20, gradient: LinearGradient(
                colors: [Color(hex: "00A896"), Color(hex: "02C39A"), Color(hex: "00A896").opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            
            // Username con chapita
            VerifiedUsernameView(
                username: "Usuario Verificado",
                isVerified: true,
                usernameColor: .primary,
                badgeSize: 16,
                badgeColor: .blue
            )
            
            // Username sin chapita
            VerifiedUsernameView(
                username: "Usuario Normal",
                isVerified: false
            )
            
            // Diferentes tamaños
            HStack(spacing: 20) {
                VerifiedBadge(size: 12, gradient: LinearGradient(
                    colors: [Color(hex: "00A896"), Color(hex: "02C39A"), Color(hex: "00A896").opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                VerifiedBadge(size: 16, gradient: LinearGradient(
                    colors: [Color(hex: "00A896"), Color(hex: "02C39A"), Color(hex: "00A896").opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                VerifiedBadge(size: 20, gradient: LinearGradient(
                    colors: [Color(hex: "00A896"), Color(hex: "02C39A"), Color(hex: "00A896").opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            }
        }
        .padding()
    }
} 
