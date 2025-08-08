import SwiftUI
import Kingfisher

private func getThemeColor(_ theme: ProfileTheme) -> Color {
    switch theme {
    case .default: return Color.blue
    case .supporter: return Color(hex: "FF6B6B") // Rosa supporter
    case .earlyAdopter: return Color(hex: "4ECDC4") // Azul early adopter
    case .champion: return Color(hex: "FFD93D") // Amarillo champion
    case .vip: return Color(hex: "9B59B6") // Púrpura VIP
    case .plus: return Color(hex: "FFD700") // Dorado Plus
    }
}

// MARK: - Enhanced Profile Background with Advanced Effects
struct EnhancedProfileBackground: View {
    let profileImagePath: String?
    let scrollOffset: CGFloat
    let profileTheme: ProfileTheme
    let user: AppUser? // NUEVO: Usuario para acceder al badge
    @Environment(\.colorScheme) var colorScheme
    @State private var animationPhase: CGFloat = 0
    @State private var animationTimer: Timer?
    @State private var particlePositions: [CGPoint] = []
    @State private var glowIntensity: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Enhanced gradient base with depth
            backgroundGradientLayer
            
            // Atmospheric effects layer
            atmosphericEffectsLayer
            
            // Particle systems
            particleSystemsLayer
            
            // Dynamic lighting effects
            dynamicLightingLayer
            
            // Profile image backdrop with enhanced blur
            profileImageBackdrop
            
            // Avatar-centered effects layer
            avatarCenteredEffects
            
            // Adaptive overlay for readability
            adaptiveOverlay
        }
        .ignoresSafeArea(.all, edges: .all)
        .onAppear {
            initializeEffects()
            startAdvancedAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    // MARK: - Background Layers
    
    private var backgroundGradientLayer: some View {
        ZStack {
            // Primary gradient
            if colorScheme == .dark {
                profileTheme.darkBackgroundGradient
            } else {
                profileTheme.backgroundGradient
            }
            
            // Secondary depth gradient (solo para temas no clásicos)
            if profileTheme != .default {
                LinearGradient(
                    colors: [
                        Color.clear,
                        getThemeColor(profileTheme).opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .scaleEffect(1.2)
                .rotationEffect(.degrees(profileTheme == .default ? 0 : animationPhase * 30))
                .opacity(0.6)
            }
        }
    }
    
    private var atmosphericEffectsLayer: some View {
        ZStack {
            // Floating orbs
            if profileTheme != .default {
                FloatingOrbsView(
                    theme: profileTheme,
                    animationPhase: animationPhase,
                    intensity: glowIntensity
                )
            }
            
            // Ambient particles
            AmbientParticlesView(
                theme: profileTheme,
                animationPhase: animationPhase
            )
        }
    }
    
    private var particleSystemsLayer: some View {
        ZStack {
            // Enhanced particle effects
            if profileTheme.particleEffect != .none {
                EnhancedParticleEffectView(
                    effect: profileTheme.particleEffect,
                    animationPhase: animationPhase,
                    positions: particlePositions
                )
            }
            
            // Light rays from center
            if profileTheme.lightRays != .none {
                EnhancedLightRaysView(
                    lightRays: profileTheme.lightRays,
                    animationPhase: animationPhase,
                    scrollOffset: scrollOffset
                )
            }
            
            // Energy waves
            if profileTheme.energyWaves != .none {
                EnhancedEnergyWavesView(
                    energyWaves: profileTheme.energyWaves,
                    animationPhase: animationPhase
                )
            }
            
            // Dynamic sparks
            if profileTheme.dynamicSparks != .none {
                EnhancedDynamicSparksView(
                    dynamicSparks: profileTheme.dynamicSparks,
                    animationPhase: animationPhase
                )
            }
        }
    }
    
    private var dynamicLightingLayer: some View {
        ZStack {
            // Enhanced glow effects
            if profileTheme.glowEffect != .none {
                EnhancedGlowEffectView(
                    effect: profileTheme.glowEffect,
                    animationPhase: animationPhase,
                    intensity: glowIntensity
                )
            }
            
            // Volumetric lighting
            VolumetricLightingView(
                theme: profileTheme,
                animationPhase: animationPhase
            )
        }
    }
    
    private var profileImageBackdrop: some View {
        Group {
            if let profileImagePath = profileImagePath, let url = URL(string: profileImagePath) {
                GeometryReader { geometry in
                    KFImage(url)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 35 + sin(animationPhase * 2) * 5) // Dynamic blur
                        .opacity(colorScheme == .dark ? 0.12 : 0.06)
                        .scaleEffect(1.3 + sin(animationPhase) * 0.1) // Breathing effect
                        .offset(y: scrollOffset * 0.15)
                        .ignoresSafeArea()
                        .overlay(
                            // Color tint based on theme
                            Rectangle()
                                .fill(getThemeColor(profileTheme).opacity(0.2))
                                .blendMode(.overlay)
                        )
                }
            }
        }
    }
    
    private var avatarCenteredEffects: some View {
        GeometryReader { geometry in
            ZStack {
                // Avatar position (ajustada basada en la prueba)
                let avatarCenterX = geometry.size.width / 2
                let avatarCenterY = geometry.size.height * 0.17 // Posición ajustada
                
                // Theme-based energy field (igual que en la preview)
                if profileTheme != .default {
                    ThemeEnergyFieldView(
                        theme: profileTheme,
                        animationPhase: animationPhase,
                        centerX: avatarCenterX,
                        centerY: avatarCenterY
                    )
                    
                    // Orbiting particles based on theme
                    ThemeOrbitingParticlesView(
                        theme: profileTheme,
                        animationPhase: animationPhase,
                        centerX: avatarCenterX,
                        centerY: avatarCenterY
                    )
                }
            }
        }
    }
    
    private var adaptiveOverlay: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03),
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea()
    }
    
    // MARK: - Animation System
    
    private func initializeEffects() {
        // Initialize particle positions
        particlePositions = (0..<20).map { _ in
            CGPoint(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
            )
        }
    }
    
    private func startAdvancedAnimation() {
        stopAnimation()
        
        // Main animation timer
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                animationPhase += 0.008 // Smoother animation
                if animationPhase >= 1.0 {
                    animationPhase = 0.0
                }
                
                // Dynamic glow intensity
                glowIntensity = 0.8 + 0.4 * sin(animationPhase * 4 * .pi)
                
                // Update particle positions
                updateParticlePositions()
            }
        }
    }
    
    private func updateParticlePositions() {
        for i in particlePositions.indices {
            let speed = CGFloat.random(in: 0.5...2.0)
            let angle = animationPhase * 2 * .pi + CGFloat(i) * 0.5
            particlePositions[i].x += cos(angle) * speed
            particlePositions[i].y += sin(angle) * speed * 0.5
            
            // Wrap around screen
            if particlePositions[i].x > UIScreen.main.bounds.width {
                particlePositions[i].x = -50
            }
            if particlePositions[i].y > UIScreen.main.bounds.height {
                particlePositions[i].y = -50
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
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
struct ThemeEnergyFieldView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    
    private var themeEnergyGradient: RadialGradient {
        RadialGradient(
            colors: [
                getThemeColor(theme).opacity(1.0),
                getThemeColor(theme).opacity(0.8),
                getThemeColor(theme).opacity(0.5),
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
        0.8 + 0.2 * sin(animationPhase * 3 * Double.pi)
    }
    
    var body: some View {
        Circle()
            .fill(themeEnergyGradient)
            .frame(width: 300, height: 300)
            .position(x: centerX, y: centerY)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .blur(radius: 0)
            .allowsHitTesting(false)
    }
}

struct ThemeOrbitingParticlesView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    
    var body: some View {
        ForEach(0..<8, id: \.self) { index in
            ThemeParticleView(
                theme: theme,
                animationPhase: animationPhase,
                centerX: centerX,
                centerY: centerY,
                index: index
            )
        }
    }
}

struct ThemeParticleView: View {
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
        0.7 + 0.3 * sin(animationPhase * 2 * Double.pi + Double(index) * 0.5)
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
                        .foregroundColor(.gray.opacity(0.7))
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

struct VolumetricLightingView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    VolumetricLightLayerView(
                        theme: theme,
                        animationPhase: animationPhase,
                        index: index,
                        geometry: geometry
                    )
                }
            }
        }
    }
}

struct VolumetricLightLayerView: View {
    let theme: ProfileTheme
    let animationPhase: CGFloat
    let index: Int
    let geometry: GeometryProxy
    
    private var lightGradient: RadialGradient {
        RadialGradient(
            colors: [
                getThemeColor(theme).opacity(0.3),
                Color.clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 200
        )
    }
    
    private var xPosition: CGFloat {
        geometry.size.width * 0.5
    }
    
    private var yPosition: CGFloat {
        geometry.size.height * (0.2 + Double(index) * 0.3)
    }
    
    private var scaleEffect: CGFloat {
        let baseScale = 0.8
        let amplitude = 0.4
        let frequency = 1.5
        let phase = Double(index) * 0.8
        let scaleOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseScale + amplitude * scaleOffset
    }
    
    private var opacity: Double {
        let baseOpacity = 0.2
        let amplitude = 0.3
        let frequency = 2.0
        let phase = Double(index) * 0.5
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    private var rotationAngle: Double {
        animationPhase * 30 + Double(index) * 45
    }
    
    var body: some View {
        Ellipse()
            .fill(lightGradient)
            .frame(width: 400, height: 200)
            .position(x: xPosition, y: yPosition)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .blur(radius: 20)
            .rotationEffect(.degrees(rotationAngle))
    }
}

// MARK: - Enhanced Particle Effects

struct EnhancedParticleEffectView: View {
    let effect: ParticleEffect
    let animationPhase: CGFloat
    let positions: [CGPoint]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<min(effect.count, positions.count), id: \.self) { index in
                EnhancedParticleView(
                    emoji: effect.emoji,
                    index: index,
                    total: effect.count,
                    size: geometry.size,
                    animationPhase: animationPhase,
                    position: positions[index]
                )
            }
        }
    }
}

struct EnhancedParticleView: View {
    let emoji: String
    let index: Int
    let total: Int
    let size: CGSize
    let animationPhase: CGFloat
    let position: CGPoint
    
    private var dynamicScale: CGFloat {
        let baseScale = 0.7 + 0.5 * sin(animationPhase * 3 * .pi + CGFloat(index) * 0.6)
        let distanceFromCenter = sqrt(pow(position.x - size.width/2, 2) + pow(position.y - size.height/2, 2))
        let maxDistance = sqrt(pow(size.width/2, 2) + pow(size.height/2, 2))
        let distanceFactor = 1.0 - (distanceFromCenter / maxDistance) * 0.5
        return baseScale * distanceFactor
    }
    
    private var dynamicOpacity: Double {
        let baseOpacity = 0.5 + 0.5 * sin(animationPhase * 2 * .pi + CGFloat(index) * 0.4)
        return baseOpacity * 0.8
    }
    
    var body: some View {
        Text(emoji)
            .font(.system(size: 28))
            .scaleEffect(dynamicScale)
            .opacity(dynamicOpacity)
            .position(position)
            .shadow(
                color: Color.white.opacity(0.6),
                radius: 4,
                x: 0,
                y: 0
            )
            .blur(radius: 0.5)
    }
}

struct EnhancedLightRaysView: View {
    let lightRays: LightRays
    let animationPhase: CGFloat
    let scrollOffset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 0.3 + scrollOffset * 0.1
            
            ZStack {
                ForEach(0..<lightRays.count, id: \.self) { index in
                    LightRayView(
                        lightRays: lightRays,
                        animationPhase: animationPhase,
                        index: index,
                        centerX: centerX,
                        centerY: centerY
                    )
                }
            }
        }
    }
}

struct LightRayView: View {
    let lightRays: LightRays
    let animationPhase: CGFloat
    let index: Int
    let centerX: CGFloat
    let centerY: CGFloat
    
    private var angle: Double {
        (2 * Double.pi * Double(index)) / Double(lightRays.count)
    }
    
    private var dynamicLength: Double {
        let baseLength = lightRays.length
        let lengthVariation = 0.7 + 0.5 * sin(animationPhase * 2 * Double.pi + Double(index) * 0.4)
        return baseLength * lengthVariation
    }
    
    private var endX: Double {
        centerX + cos(angle) * dynamicLength
    }
    
    private var endY: Double {
        centerY + sin(angle) * dynamicLength
    }
    
    private var rayGradient: LinearGradient {
        let rayColor = lightRays.colors[index % lightRays.colors.count]
        return LinearGradient(
            colors: [
                rayColor.opacity(0.9),
                rayColor.opacity(0.6),
                rayColor.opacity(0.3),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var lineWidth: CGFloat {
        let baseWidth = lightRays.width
        let widthVariation = 0.8 + 0.4 * sin(animationPhase * 3 * Double.pi + Double(index) * 0.3)
        return baseWidth * widthVariation
    }
    
    private var opacity: Double {
        let baseOpacity = 0.8
        let amplitude = 0.2
        let frequency = 2.5
        let phase = Double(index) * 0.4
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    private var shadowColor: Color {
        lightRays.colors[index % lightRays.colors.count].opacity(0.4)
    }
    
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: centerX, y: centerY))
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(
            rayGradient,
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round
            )
        )
        .opacity(opacity)
        .blur(radius: 1.5)
        .shadow(
            color: shadowColor,
            radius: 8,
            x: 0,
            y: 0
        )
    }
}

struct EnhancedEnergyWavesView: View {
    let energyWaves: EnergyWaves
    let animationPhase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 0.3
            
            ZStack {
                ForEach(0..<energyWaves.count, id: \.self) { index in
                    EnergyWaveView(
                        energyWaves: energyWaves,
                        animationPhase: animationPhase,
                        index: index,
                        centerX: centerX,
                        centerY: centerY
                    )
                }
            }
        }
    }
}

struct EnergyWaveView: View {
    let energyWaves: EnergyWaves
    let animationPhase: CGFloat
    let index: Int
    let centerX: CGFloat
    let centerY: CGFloat
    
    private var waveRadius: CGFloat {
        energyWaves.radius + CGFloat(index) * 30
    }
    
    private var dynamicScale: CGFloat {
        let baseScale = 0.3
        let amplitude = 0.7
        let frequency = energyWaves.speed * 2
        let phase = Double(index) * 1.2
        let scaleOffset = sin(animationPhase * frequency + phase)
        return baseScale + amplitude * scaleOffset
    }
    
    private var waveGradient: LinearGradient {
        LinearGradient(
            colors: energyWaves.colors + [Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var lineWidth: CGFloat {
        4 * (1.0 - Double(index) / Double(energyWaves.count))
    }
    
    private var opacity: Double {
        0.8 * (1.0 - Double(index) / Double(energyWaves.count))
    }
    
    private var shadowColor: Color {
        energyWaves.colors.first?.opacity(0.3) ?? Color.clear
    }
    
    var body: some View {
        Circle()
            .stroke(
                waveGradient,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    dash: [10, 5]
                )
            )
            .frame(width: waveRadius * 2, height: waveRadius * 2)
            .position(x: centerX, y: centerY)
            .scaleEffect(dynamicScale)
            .opacity(opacity)
            .blur(radius: 2)
            .shadow(
                color: shadowColor,
                radius: 6,
                x: 0,
                y: 0
            )
    }
}

struct EnhancedDynamicSparksView: View {
    let dynamicSparks: DynamicSparks
    let animationPhase: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 0.3
            
            ZStack {
                ForEach(0..<dynamicSparks.count, id: \.self) { index in
                    DynamicSparkView(
                        dynamicSparks: dynamicSparks,
                        animationPhase: animationPhase,
                        index: index,
                        centerX: centerX,
                        centerY: centerY
                    )
                }
            }
        }
    }
}

struct DynamicSparkView: View {
    let dynamicSparks: DynamicSparks
    let animationPhase: CGFloat
    let index: Int
    let centerX: CGFloat
    let centerY: CGFloat
    
    private var angle: Double {
        (2 * Double.pi * Double(index)) / Double(dynamicSparks.count)
    }
    
    private var dynamicDistance: Double {
        let baseDistance = dynamicSparks.spreadRadius
        let distanceVariation = 0.5 + 0.7 * sin(animationPhase * dynamicSparks.speed * 1.8 + Double(index) * 0.3)
        return baseDistance * distanceVariation
    }
    
    private var wobble: Double {
        sin(animationPhase * 5 * Double.pi + Double(index) * 0.8) * 20
    }
    
    private var xPosition: Double {
        centerX + cos(angle) * dynamicDistance + wobble
    }
    
    private var yPosition: Double {
        centerY + sin(angle) * dynamicDistance + wobble * 0.6
    }
    
    private var scaleEffect: CGFloat {
        let baseScale = 0.5
        let amplitude = 0.7
        let frequency = 4.0
        let phase = Double(index) * 0.5
        let scaleOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseScale + amplitude * scaleOffset
    }
    
    private var opacity: Double {
        let baseOpacity = 0.6
        let amplitude = 0.4
        let frequency = 2.8
        let phase = Double(index) * 0.6
        let opacityOffset = sin(animationPhase * frequency * Double.pi + phase)
        return baseOpacity + amplitude * opacityOffset
    }
    
    private var rotationAngle: Double {
        animationPhase * 360 + Double(index) * 30
    }
    
    var body: some View {
        Text(dynamicSparks.emoji)
            .font(.system(size: 20))
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .position(x: xPosition, y: yPosition)
            .rotationEffect(.degrees(rotationAngle))
            .shadow(
                color: Color.white.opacity(0.7),
                radius: 5,
                x: 0,
                y: 0
            )
            .blur(radius: 0.8)
    }
}

struct EnhancedGlowEffectView: View {
    let effect: GlowEffect
    let animationPhase: CGFloat
    let intensity: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Primary glow with enhanced movement
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(effect.opacity * 1.5 * intensity),
                                Color.white.opacity(effect.opacity * 0.8 * intensity),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: effect.radius * 15
                        )
                    )
                    .frame(width: effect.radius * 30, height: effect.radius * 30)
                    .position(
                        x: geometry.size.width * (0.25 + 0.5 * sin(animationPhase * 1.8 * .pi)) + cos(animationPhase * 2.2 * .pi) * 80,
                        y: geometry.size.height * (0.15 + 0.3 * cos(animationPhase * 1.5 * .pi)) + sin(animationPhase * 2 * .pi) * 60
                    )
                    .blur(radius: effect.radius * 1.2)
                    .opacity(0.6 + 0.4 * intensity)
                
                // Secondary glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(effect.opacity * 1.2 * intensity),
                                Color.white.opacity(effect.opacity * 0.6 * intensity),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: effect.radius * 12
                        )
                    )
                    .frame(width: effect.radius * 24, height: effect.radius * 24)
                    .position(
                        x: geometry.size.width * (0.75 + 0.3 * cos(animationPhase * 2.1 * .pi)) + sin(animationPhase * 1.8 * .pi) * 70,
                        y: geometry.size.height * (0.85 + 0.2 * sin(animationPhase * 1.7 * .pi)) + cos(animationPhase * 2.3 * .pi) * 50
                    )
                    .blur(radius: effect.radius)
                    .opacity(0.5 + 0.3 * intensity)
                
                // Tertiary accent glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(effect.opacity * 0.8 * intensity),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: effect.radius * 8
                        )
                    )
                    .frame(width: effect.radius * 16, height: effect.radius * 16)
                    .position(
                        x: geometry.size.width * (0.5 + 0.4 * sin(animationPhase * 2.5 * .pi)),
                        y: geometry.size.height * (0.5 + 0.3 * cos(animationPhase * 2.8 * .pi))
                    )
                    .blur(radius: effect.radius * 0.8)
                    .opacity(0.4 + 0.2 * intensity)
            }
        }
    }
}

// MARK: - Enhanced Preview Card
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
                        .font(.custom("Poppins-Bold", size: 20))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    // Enhanced badge
                    HStack(spacing: 10) {
                        Text(theme.emoji)
                            .font(.system(size: 24))
                            .scaleEffect(1.0 + 0.15 * sin(animationPhase * 3 * .pi))
                            .shadow(color: .white.opacity(0.5), radius: 3, x: 0, y: 0)
                        
                        Text(theme.displayName)
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(.white.opacity(0.95))
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
            withAnimation(.easeInOut(duration: 0.3)) {
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
