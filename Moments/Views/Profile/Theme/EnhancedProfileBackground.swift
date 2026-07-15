import SwiftUI
import Kingfisher

private func getThemeColor(_ theme: ProfileTheme) -> Color {
    switch theme {
    case .default: return Color.blue
    case .supporter: return Color(hex: "a8170c") // Rojo supporter
    case .earlyAdopter: return Color(hex: "4ECDC4") // Azul early adopter
    case .champion: return Color(hex: "FFD93D") // Amarillo champion
    case .vip: return Color(hex: "9B59B6") // Púrpura VIP
    case .plus: return Color(hex: "FFD700") // Dorado Plus
    }
}

// MARK: - Enhanced Profile Background
struct EnhancedProfileBackground: View {
    let profileImagePath: String?
    let scrollOffset: CGFloat
    let profileTheme: ProfileTheme
    let user: AppUser?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            backgroundGradientLayer
            adaptiveOverlay
        }
        .ignoresSafeArea(.all, edges: .all)
    }
    
    // MARK: - Background Layers
    
    private var backgroundGradientLayer: some View {
        (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
    }
    
    private var adaptiveOverlay: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.08 : 0.00),
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.06 : 0.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea()
    }
    
    // MARK: - Badge Helper Functions
    
    private func getUserBadge() -> UserBadge? {
        guard let user = user else { return nil }
        
        // Si el usuario tiene un badge principal, usarlo
        if let primaryBadge = user.primaryBadge {
            return primaryBadge
        }
        
        // Si no tiene badge principal pero es Plus, crear badge Plus
        if user.isPlusSubscriber {
            return UserBadge(
                badgeId: "plus",
                name: "Plus",
                emoji: "👑",
                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                purchaseDate: user.plusSubscription?.startDate ?? Date(),
                isVisible: true,
                price: "€2.99/mes"
            )
        }
        
        return nil
    }
}

// MARK: - Theme Centered Effects Views
// Eliminadas las estructuras que ya no se usan

// MARK: - Badge Centered Effects Views
struct BadgeEnergyFieldView: View {
    let badge: UserBadge
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    
    private var badgeEnergyGradient: RadialGradient {
        RadialGradient(
            colors: [
                badge.swiftUIColors.first?.opacity(1.0) ?? Color.blue.opacity(1.0),
                badge.swiftUIColors.first?.opacity(0.9) ?? Color.blue.opacity(0.9),
                badge.swiftUIColors.first?.opacity(0.7) ?? Color.blue.opacity(0.7),
                badge.swiftUIColors.first?.opacity(0.4) ?? Color.blue.opacity(0.4),
                Color.clear
            ],
            center: .center,
            startRadius: 20,
            endRadius: 120
        )
    }
    
    private var scaleEffect: CGFloat {
        1.0 + 0.2 * sin(animationPhase * 2 * Double.pi)
    }
    
    private var opacity: Double {
        0.8 + 0.2 * sin(animationPhase * 3 * Double.pi)
    }
    
    var body: some View {
        Circle()
            .stroke(badge.swiftUIColors.first ?? Color.blue, lineWidth: 4)
            .frame(width: 200, height: 200)
            .position(x: centerX, y: centerY)
            .rotationEffect(.degrees(animationPhase * 360))
            .opacity(0.8)
            .allowsHitTesting(false)
    }
}

struct BadgeOrbitingParticlesView: View {
    let badge: UserBadge
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    
    var body: some View {
        ForEach(0..<8, id: \.self) { index in
            BadgeParticleView(
                badge: badge,
                animationPhase: animationPhase,
                centerX: centerX,
                centerY: centerY,
                index: index
            )
        }
    }
}

struct BadgeParticleView: View {
    let badge: UserBadge
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let index: Int
    
    private var particleX: CGFloat {
        centerX + cos(animationPhase * 2 * Double.pi + Double(index) * Double.pi / 4) * 80
    }
    
    private var particleY: CGFloat {
        centerY + sin(animationPhase * 2 * Double.pi + Double(index) * Double.pi / 4) * 80
    }
    
    private var scaleEffect: CGFloat {
        0.5 + 0.5 * sin(animationPhase * 4 * Double.pi + Double(index))
    }
    
    private var opacity: Double {
        0.7 + 0.3 * sin(animationPhase * 2 * Double.pi + Double(index) * 0.5)
    }
    
    var body: some View {
        Circle()
            .fill(badge.swiftUIColors.first?.opacity(0.9) ?? Color.blue.opacity(0.9))
            .frame(width: 12, height: 12)
            .position(x: particleX, y: particleY)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

// MARK: - Avatar Centered Effects Views
struct AvatarEnergyFieldView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    
    private var energyFieldGradient: RadialGradient {
        RadialGradient(
            colors: [
                getThemeColor(theme).opacity(1.0),
                getThemeColor(theme).opacity(0.9),
                getThemeColor(theme).opacity(0.6),
                Color.clear
            ],
            center: .center,
            startRadius: 30,
            endRadius: 150
        )
    }
    
    private var scaleEffect: CGFloat {
        1.0 + 0.2 * sin(animationPhase * 2 * Double.pi)
    }
    
    private var opacity: Double {
        0.6 + 0.4 * sin(animationPhase * 3 * Double.pi)
    }
    
    var body: some View {
        Circle()
            .fill(energyFieldGradient)
            .frame(width: 300, height: 300)
            .position(x: centerX, y: centerY)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .blur(radius: 0)
            .allowsHitTesting(false)
    }
}

struct AvatarOrbitingParticlesView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    
    var body: some View {
        ForEach(0..<8, id: \.self) { index in
            AvatarParticleView(
                theme: theme,
                animationPhase: animationPhase,
                centerX: centerX,
                centerY: centerY,
                index: index
            )
        }
    }
}

struct AvatarParticleView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let index: Int
    
    private var particleX: CGFloat {
        centerX + cos(animationPhase * 2 * Double.pi + Double(index) * Double.pi / 4) * 80
    }
    
    private var particleY: CGFloat {
        centerY + sin(animationPhase * 2 * Double.pi + Double(index) * Double.pi / 4) * 80
    }
    
    private var scaleEffect: CGFloat {
        0.5 + 0.5 * sin(animationPhase * 4 * Double.pi + Double(index))
    }
    
    private var opacity: Double {
        0.3 + 0.7 * sin(animationPhase * 2 * Double.pi + Double(index) * 0.5)
    }
    
    var body: some View {
        Circle()
            .fill(getThemeColor(theme).opacity(0.9))
            .frame(width: 12, height: 12)
            .position(x: particleX, y: particleY)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

// MARK: - Enhanced Profile Avatar with Advanced Effects
struct EnhancedProfileAvatar: View {
    let profileImagePath: String?
    let profileTheme: ProfileTheme
    let size: CGFloat
    let hasActiveStories: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var animationPhase: CGFloat = 0
    @State private var profileImage: UIImage?
    @State private var isLoadingImage = false
    @State private var pulseIntensity: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // Enhanced aura effects
            if profileTheme.profileAura != .none && !hasActiveStories {
                EnhancedAuraView(
                    aura: profileTheme.profileAura,
                    animationPhase: animationPhase,
                    intensity: pulseIntensity
                )
                .frame(width: size + 50, height: size + 50)
                .allowsHitTesting(false)
            }
            
            // Particle ring with physics
            if profileTheme.profileParticles != .none && !hasActiveStories {
                PhysicsParticleRingView(
                    particles: profileTheme.profileParticles,
                    animationPhase: animationPhase,
                    size: size
                )
                .frame(width: size + 80, height: size + 80)
                .allowsHitTesting(false)
            }
            
            // Main avatar with enhanced effects
            ZStack {
                // Dynamic border with gradient animation
                if profileTheme.dynamicBorder != .none {
                    EnhancedBorderView(
                        border: profileTheme.dynamicBorder,
                        animationPhase: animationPhase,
                        hasActiveStories: hasActiveStories,
                        rotationAngle: rotationAngle
                    )
                    .frame(width: size + 16, height: size + 16)
                    .allowsHitTesting(false)
                }
                
                // Profile image with enhanced loading states
                profileImageView
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(
                        color: getThemeColor(profileTheme).opacity(0.3),
                        radius: 15,
                        x: 0,
                        y: 5
                    )
            }
        }
        .onAppear {
            loadProfileImage()
            startAvatarAnimations()
        }
    }
    
    private var profileImageView: some View {
        Group {
            if let profileImage = profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.0 + pulseIntensity * 0.02) // Subtle breathing
            } else if isLoadingImage {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(getThemeColor(profileTheme))
                }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.3),
                                    Color.gray.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: size * 0.6))
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
        }
    }
    
    private func startAvatarAnimations() {
        // Pulse animation
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            pulseIntensity = 1.2
        }
        
        // Rotation animation for border
        withAnimation(.linear(duration: profileTheme.animation.duration * 3).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        
        // Main animation phase
        withAnimation(.linear(duration: profileTheme.animation.duration * 2).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
    }
    
    private func loadProfileImage() {
        guard let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) else {
            profileImage = nil
            return
        }
        
        isLoadingImage = true
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingImage = false
                
                if let data = data, let uiImage = UIImage(data: data) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        profileImage = uiImage
                    }
                } else {
                    profileImage = nil
                }
            }
        }.resume()
    }
}

// MARK: - Enhanced Visual Effects Components

struct FloatingOrbsView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let intensity: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<6, id: \.self) { index in
                ProfileFloatingOrbView(
                    theme: theme,
                    animationPhase: animationPhase,
                    intensity: intensity,
                    index: index,
                    geometry: geometry
                )
            }
        }
    }
}

struct ProfileFloatingOrbView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let intensity: CGFloat
    let index: Int
    let geometry: GeometryProxy
    
    private var orbGradient: RadialGradient {
        RadialGradient(
            colors: [
                getThemeColor(theme).opacity(0.6),
                getThemeColor(theme).opacity(0.2),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 40
        )
    }
    
    private var xPosition: CGFloat {
        let baseX = 0.2
        let amplitude = 0.6
        let frequency = 2.0
        let phase = Double(index) * 1.0
        let xOffset = sin(animationPhase * frequency * Double.pi + phase)
        return geometry.size.width * (baseX + amplitude * xOffset)
    }
    
    private var yPosition: CGFloat {
        let baseY = 0.3
        let amplitude = 0.4
        let frequency = 1.5
        let phase = Double(index) * 0.8
        let yOffset = cos(animationPhase * frequency * Double.pi + phase)
        return geometry.size.height * (baseY + amplitude * yOffset)
    }
    
    private var scaleEffect: CGFloat {
        let baseScale = 0.5
        let amplitude = 0.5
        let frequency = 3.0
        let phase = Double(index) * 0.5
        let scaleOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseScale + amplitude * intensity * scaleOffset
    }
    
    private var opacity: Double {
        let baseOpacity = 0.3
        let amplitude = 0.4
        let frequency = 2.0
        let phase = Double(index) * 0.3
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    var body: some View {
        Circle()
            .fill(orbGradient)
            .frame(width: 80, height: 80)
            .position(x: xPosition, y: yPosition)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .blur(radius: 10)
    }
}

struct AmbientParticlesView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<15, id: \.self) { index in
                AmbientParticleView(
                    index: index,
                    animationPhase: animationPhase,
                    geometry: geometry
                )
            }
        }
    }
}

struct AmbientParticleView: View {
    let index: Int
    let animationPhase: CGFloat
    let geometry: GeometryProxy
    
    private var xPosition: CGFloat {
        // Usar un valor determinístico basado en el índice para evitar cambios aleatorios
        let seed = Double(index) * 0.618033988749895 // Número áureo
        let randomValue = sin(seed) * 0.5 + 0.5
        return geometry.size.width * randomValue
    }
    
    private var yPosition: CGFloat {
        let baseY = CGFloat(index) / 15.0
        let animationOffset = animationPhase * 0.1
        let totalY = baseY + animationOffset
        return geometry.size.height * totalY.truncatingRemainder(dividingBy: 1.0)
    }
    
    private var opacity: Double {
        let baseOpacity = 0.2
        let amplitude = 0.3
        let frequency = 4.0
        let phase = Double(index) * 0.4
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.4))
            .frame(width: 3, height: 3)
            .position(x: xPosition, y: yPosition)
            .opacity(opacity)
            .blur(radius: 1)
    }
}

struct EnhancedAuraView: View {
    let aura: ProfileAura
    let animationPhase: CGFloat
    let intensity: CGFloat
    
    var body: some View {
        ZStack {
            ForEach(0..<aura.colors.count, id: \.self) { index in
                AuraLayerView(
                    aura: aura,
                    animationPhase: animationPhase,
                    intensity: intensity,
                    index: index
                )
            }
        }
    }
}

struct AuraLayerView: View {
    let aura: ProfileAura
    let animationPhase: CGFloat
    let intensity: CGFloat
    let index: Int
    
    private var auraGradient: RadialGradient {
        RadialGradient(
            colors: [
                aura.colors[index].opacity(aura.intensity * 0.5 * intensity),
                aura.colors[index].opacity(aura.intensity * 0.3 * intensity),
                aura.colors[index].opacity(aura.intensity * 0.1 * intensity),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: aura.radius * 0.7
        )
    }
    
    private var scaleEffect: CGFloat {
        let baseScale = 1.0
        let amplitude = 0.15
        let frequency = 2.0
        let phase = Double(index) * 0.6
        let scaleOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseScale + amplitude * intensity * scaleOffset
    }
    
    private var opacity: Double {
        let baseOpacity = 0.4
        let amplitude = 0.3
        let frequency = 1.5
        let phase = Double(index) * 0.4
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    private var blurRadius: CGFloat {
        let baseBlur = 8.0
        let amplitude = 2.0
        let frequency = 3.0
        let blurOffset = sin(animationPhase * frequency * Double.pi)
        return baseBlur + amplitude * blurOffset
    }
    
    private var rotationAngle: Double {
        let baseRotation = animationPhase * 60
        let indexRotation = Double(index) * 30
        return baseRotation + indexRotation
    }
    
    var body: some View {
        Circle()
            .fill(auraGradient)
            .frame(width: aura.radius * 1.4, height: aura.radius * 1.4)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .blur(radius: blurRadius)
            .rotationEffect(.degrees(rotationAngle))
    }
}

struct PhysicsParticleRingView: View {
    let particles: ProfileParticles
    let animationPhase: CGFloat
    let size: CGFloat
    
    var body: some View {
        ZStack {
            ForEach(0..<particles.count, id: \.self) { index in
                PhysicsParticleView(
                    particles: particles,
                    animationPhase: animationPhase,
                    index: index
                )
            }
        }
    }
}

struct PhysicsParticleView: View {
    let particles: ProfileParticles
    let animationPhase: CGFloat
    let index: Int
    
    private var baseAngle: Double {
        (2 * Double.pi * Double(index)) / Double(particles.count)
    }
    
    private var dynamicRadius: Double {
        let baseRadius = particles.radius * 0.7
        let radiusVariation = 0.8 + 0.4 * sin(animationPhase * 3 * Double.pi + Double(index) * 0.3)
        return baseRadius * radiusVariation
    }
    
    private var wobble: Double {
        sin(animationPhase * 4 * Double.pi + Double(index) * 0.7) * 15
    }
    
    private var xOffset: Double {
        cos(baseAngle) * dynamicRadius + wobble
    }
    
    private var yOffset: Double {
        sin(baseAngle) * dynamicRadius + wobble * 0.5
    }
    
    private var scaleEffect: CGFloat {
        let baseScale = 0.4
        let amplitude = 0.4
        let frequency = 2.5
        let phase = Double(index) * 0.5
        let scaleOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseScale + amplitude * scaleOffset
    }
    
    private var opacity: Double {
        let baseOpacity = 0.4
        let amplitude = 0.4
        let frequency = 2.0
        let phase = Double(index) * 0.3
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    private var rotationAngle: Double {
        animationPhase * 180 + Double(index) * 45
    }
    
    var body: some View {
        Text(particles.emoji)
            .font(.system(size: 14))
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .offset(x: xOffset, y: yOffset)
            .rotationEffect(.degrees(rotationAngle))
            .shadow(
                color: Color.white.opacity(0.5),
                radius: 3,
                x: 0,
                y: 0
            )
    }
}

struct EnhancedBorderView: View {
    let border: DynamicBorder
    let animationPhase: CGFloat
    let hasActiveStories: Bool
    let rotationAngle: Double
    
    var body: some View {
        ZStack {
            ForEach(0..<border.colors.count, id: \.self) { index in
                BorderLayerView(
                    border: border,
                    animationPhase: animationPhase,
                    hasActiveStories: hasActiveStories,
                    rotationAngle: rotationAngle,
                    index: index
                )
            }
        }
    }
}

struct BorderLayerView: View {
    let border: DynamicBorder
    let animationPhase: CGFloat
    let hasActiveStories: Bool
    let rotationAngle: Double
    let index: Int
    
    private var borderGradient: AngularGradient {
        let opacity1 = hasActiveStories ? 0.4 : 0.7
        let opacity2 = hasActiveStories ? 0.2 : 0.4
        
        return AngularGradient(
            colors: [
                border.colors[index].opacity(opacity1),
                border.colors[(index + 1) % border.colors.count].opacity(opacity1),
                border.colors[index].opacity(opacity2),
                border.colors[(index + 1) % border.colors.count].opacity(opacity1)
            ],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }
    
    private var lineWidth: CGFloat {
        hasActiveStories ? border.width * 0.6 : border.width * 0.8
    }
    
    private var scaleEffect: CGFloat {
        let baseScale = 1.0
        let amplitude = hasActiveStories ? 0.06 : 0.1
        let frequency = 2.0
        let phase = Double(index) * 0.5
        let scaleOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseScale + amplitude * scaleOffset
    }
    
    private var opacity: Double {
        let baseOpacity = 0.5
        let amplitude = hasActiveStories ? 0.15 : 0.25
        let frequency = 1.5
        let phase = Double(index) * 0.3
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    private var finalRotationAngle: Double {
        rotationAngle + Double(index) * 60
    }
    
    var body: some View {
        Circle()
            .stroke(borderGradient, lineWidth: lineWidth)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .rotationEffect(.degrees(finalRotationAngle))
            .shadow(
                color: border.colors[index].opacity(0.3),
                radius: 5,
                x: 0,
                y: 0
            )
    }
}

// Eliminadas las estructuras de iluminación volumétrica que ya no se usan

// MARK: - Enhanced Particle Effects
// Eliminadas las estructuras que ya no se usan

// Eliminadas las estructuras de rayos de luz que ya no se usan

// Eliminadas las estructuras de ondas de energía que ya no se usan

// Eliminadas las estructuras de chispas dinámicas que ya no se usan

// Eliminadas las estructuras de efectos de brillo que ya no se usan

struct EnhancedProfilePreviewCard: View {
    let theme: ProfileTheme
    @Environment(\.colorScheme) var colorScheme
    @State private var animationPhase: CGFloat = 0
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // Enhanced background with effects
            EnhancedProfileBackground(
                profileImagePath: nil,
                scrollOffset: 0,
                profileTheme: theme,
                user: nil
            )
            
            VStack(spacing: 16) {
                // Enhanced avatar
                EnhancedProfileAvatar(
                    profileImagePath: nil,
                    profileTheme: theme,
                    size: 70,
                    hasActiveStories: false
                )
                
                // Profile info with enhanced styling
                VStack(spacing: 8) {
                    Text("Tu Perfil")
                        .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    // Enhanced badge
                    HStack(spacing: 10) {
                        Text(theme.emoji)
                            .font(.system(size: 24))
                            .scaleEffect(1.0 + 0.15 * sin(animationPhase * 3 * .pi))
                            .shadow(color: .white.opacity(0.5), radius: 3, x: 0, y: 0)
                        
                        Text(theme.displayName)
                            .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.white.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(
            color: getThemeColor(theme).opacity(0.4),
            radius: 20,
            x: 0,
            y: 10
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onAppear {
            withAnimation(.linear(duration: theme.animation.duration * 1.5).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
        }
        .onHover { hovering in
            MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            ForEach(ProfileTheme.allCases, id: \.self) { theme in
                EnhancedProfilePreviewCard(theme: theme)
                    .frame(height: 180)
            }
        }
        .padding()
    }
    .background(Color.black)
}
