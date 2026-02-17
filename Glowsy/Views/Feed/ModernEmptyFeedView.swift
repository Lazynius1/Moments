import SwiftUI
import FirebaseAuth

struct ModernEmptyFeedView: View {
    let feedType: FeedType
    @Environment(\.colorScheme) var colorScheme
    @State private var appearAnimation = false
    @State private var breathingEffect = false
    
    var body: some View {
        ZStack {
            // 1. Fondo Atmosférico de Marca
            LiquidBrandAuroraBackground()
                .opacity(appearAnimation ? 1 : 0)
            
            VStack(spacing: 32) {
                // 2. Elemento Hero Flotante
                ZStack {
                    // Resplandor de fondo
                    Circle()
                        .fill(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 180, height: 180)
                        .blur(radius: 40)
                        .scaleEffect(breathingEffect ? 1.2 : 1.0)
                    
                    // Tarjeta de Cristal 3D
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                            
                            Image(systemName: feedType == .following ? "person.2.circle.fill" : "sparkles.rectangle.stack.fill")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .purple.opacity(0.5), radius: 10, x: 0, y: 5)
                                .scaleEffect(breathingEffect ? 1.05 : 1.0)
                        }
                        
                        VStack(spacing: 8) {
                            Text(emptyTitle)
                                .font(.custom("Poppins-Bold", size: 24))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)
                            
                            Text(emptyDescription)
                                .font(.custom("Poppins-Regular", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                    }
                    .padding(.vertical, 40)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 32)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.3), .clear, .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
                    .offset(y: appearAnimation ? 0 : 40)
                }
                
                // 3. Acciones CTAs
                VStack(spacing: 16) {
                    // Botón Principal: Crear
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("ShowCreatorView"), object: nil)
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(NSLocalizedString("feed.empty.action.create", comment: "Create first moment"))
                        }
                        .font(.custom("Poppins-SemiBold", size: 17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .pink.opacity(0.3), radius: 15, x: 0, y: 8)
                    }
                    
                    // Botón Secundario: Explorar
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("ShowExploreView"), object: nil)
                    }) {
                        Text(NSLocalizedString("feed.empty.action.explore", comment: "Explore trends"))
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 40)
                .offset(y: appearAnimation ? 0 : 60)
                .opacity(appearAnimation ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                appearAnimation = true
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathingEffect = true
            }
        }
    }
    
    private var emptyTitle: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.following.title", comment: "Empty following feed title")
        case .forYou:
            return NSLocalizedString("feed.empty.foryou.title", comment: "Empty for you feed title")
        }
    }
    
    private var emptyDescription: String {
        switch feedType {
        case .following:
            return NSLocalizedString("feed.empty.following.description", comment: "Empty following feed description")
        case .forYou:
            return NSLocalizedString("feed.empty.foryou.description", comment: "Empty for you feed description")
        }
    }
}

// MARK: - Liquid Background con Colores de Marca
struct LiquidBrandAuroraBackground: View {
    @State private var animate = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base layer adaptativa
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            // Orbe Azul
            Circle()
                .fill(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 500, height: 500)
                .blur(radius: 100)
                .offset(x: animate ? -150 : 150, y: animate ? -200 : 200)
            
            // Orbe Rosa/Púrpura
            Circle()
                .fill(LinearGradient(colors: [.pink.opacity(0.2), .purple.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 450, height: 450)
                .blur(radius: 90)
                .offset(x: animate ? 150 : -150, y: animate ? 100 : -100)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Previews
#Preview("Following") {
    ModernEmptyFeedView(feedType: .following)
}

#Preview("For You") {
    ModernEmptyFeedView(feedType: .forYou)
}

#Preview("Dark Mode") {
    ModernEmptyFeedView(feedType: .forYou)
        .preferredColorScheme(.dark)
}
