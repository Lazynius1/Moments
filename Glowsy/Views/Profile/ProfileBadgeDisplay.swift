import SwiftUI

// MARK: - ✅ SIMPLE: Badge Display que respeta preferencias
struct ProfileBadgeDisplay: View {
    let user: AppUser
    @State private var showBadgeDetails = false
    
    var body: some View {
        // ✅ Solo mostrar si el usuario quiere mostrar badges
        if user.showBadge, let displayBadge = user.displayBadge {
            HStack(spacing: 8) {
                // ✅ Mostrar el badge que el usuario eligió (Plus o Support Badge)
                if displayBadge.badgeId == "plus" {
                    PlusBadge()
                } else {
                    SupportBadge(badge: displayBadge) {
                        showBadgeDetails = true
                    }
                }
                
                // ✅ OPCIONAL: Supporter Level Indicator (solo si tiene badges de apoyo)
                if user.isSupporter && user.supporterLevel != .none {
                    SupporterLevelIndicator(level: user.supporterLevel)
                }
            }
            .sheet(isPresented: $showBadgeDetails) {
                // ✅ Solo mostrar detalles si no es badge Plus
                if let displayBadge = user.displayBadge, displayBadge.badgeId != "plus" {
                    BadgeDetailSheet(badge: displayBadge, user: user)
                }
            }
        }
        // ✅ Si showBadge = false o no hay displayBadge, no mostrar nada
    }
}


// MARK: - Plus Badge (sin cambios)
struct PlusBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            
            Text("PLUS")
                .font(.custom("Poppins-Bold", size: 10))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Support Badge (sin cambios)
struct SupportBadge: View {
    let badge: UserBadge
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(badge.emoji)
                    .font(.system(size: 12))
                
                Text(badge.name.uppercased())
                    .font(.custom("Poppins-Bold", size: 9))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: badge.swiftUIColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: badge.swiftUIColors.first?.opacity(0.3) ?? .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporter Level Indicator (sin cambios)
struct SupporterLevelIndicator: View {
    let level: SupporterLevel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 2) {
            Text(level.emoji)
                .font(.system(size: 10))
            
            ForEach(0..<levelStars, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "FFD700"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(
                    colorScheme == .dark ?
                    Color.black.opacity(0.7) :
                    Color.white.opacity(0.9)
                )
        )
        .overlay(
            Capsule()
                .stroke(Color(hex: "FFD700").opacity(0.5), lineWidth: 0.5)
        )
    }
    
    private var levelStars: Int {
        switch level {
        case .none: return 0
        case .supporter: return 1
        case .earlyAdopter: return 2
        case .champion: return 3
        case .vip: return 4
        }
    }
}

// MARK: - Badge Detail Sheet (sin cambios)
struct BadgeDetailSheet: View {
    let badge: UserBadge
    let user: AppUser
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Badge Hero Section
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: badge.swiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                            .scaleEffect(1.2)
                            .blur(radius: 20)
                            .opacity(0.5)
                        
                        Circle()
                            .fill(LinearGradient(
                                colors: badge.swiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                        
                        Text(badge.emoji)
                            .font(.system(size: 50))
                    }
                    
                    VStack(spacing: 8) {
                        Text(badge.name)
                            .font(.custom("Poppins-Bold", size: 24))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text("Badge de apoyo - \(badge.price)")
                            .font(.custom("Poppins-Medium", size: 16))
                            .foregroundColor(.gray)
                    }
                }
                
                // Badge Info
                VStack(spacing: 16) {
                    InfoCard(title: "Fecha de compra", value: formatDate(badge.purchaseDate))
                    InfoCard(title: "Tipo", value: "Una sola vez")
                    InfoCard(title: "Estado", value: badge.isVisible ? "Visible" : "Oculto")
                }
                
                // Support Stats
                if user.isSupporter {
                    SupportStatsCard(user: user)
                }
                
                Spacer()
                
                // Actions
                VStack(spacing: 12) {
                    if user.thankYouMessage != nil {
                        Text(user.thankYouMessage!)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: badge.swiftUIColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(colorScheme == .dark ? .black : .white))
            .navigationTitle("Badge Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("✕") { dismiss() })
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Info Card (sin cambios)
struct InfoCard: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Text(title)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Support Stats Card (sin cambios)
struct SupportStatsCard: View {
    let user: AppUser
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Tu apoyo")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text(user.supporterLevel.emoji)
                    .font(.system(size: 20))
            }
            
            VStack(spacing: 8) {
                StatRow(label: "Nivel", value: user.supporterLevel.displayName)
                StatRow(label: "Badges", value: "\(user.ownedBadges.count)")
                StatRow(label: "Total contribuido", value: "€\(String(format: "%.2f", user.totalSpentOnBadges))")
                
                if user.hasActivePlusSubscription {
                    StatRow(label: "Plus Subscriber", value: "Activo")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [Color(hex: "007AFF").opacity(0.1), Color(hex: "02C39A").opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "007AFF").opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Stat Row (sin cambios)
struct StatRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Text(label)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.custom("Poppins-SemiBold", size: 13))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }
}

// MARK: - Badge Collection View (para configuración - sin cambios)
struct BadgeCollectionView: View {
    let user: AppUser
    @StateObject private var badgeService = BadgeService()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Mis Badges")
                    .font(.custom("Poppins-Bold", size: 24))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Toca un badge para mostrar/ocultar")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
            
            // ✅ NUEVO: Sección del Badge Plus (siempre visible si es suscriptor Plus)
            if user.isPlusSubscriber {
                VStack(spacing: 16) {
                    Text("Badge Plus")
                        .font(.custom("Poppins-Bold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    PlusBadgeToggleCard(user: user)
                }
                .padding(.vertical, 20)
            }
            
            if badgeService.ownedBadges.isEmpty {
                // Empty State
                VStack(spacing: 16) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("Aún no tienes badges")
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(.gray)
                    
                    NavigationLink(destination: SupportMomentsView()) {
                        Text("Explorar badges")
                            .font(.custom("Poppins-SemiBold", size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: "007AFF"))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 40)
            } else {
                // Badge Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(badgeService.ownedBadges) { badge in
                        BadgeToggleCard(badge: badge, badgeService: badgeService)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear {
            if let userId = user.id.isEmpty ? nil : user.id {
                badgeService.loadUserBadges(userId: userId)
            }
        }
    }
}

// MARK: - Badge Toggle Card (MEJORADO con feedback)
struct BadgeToggleCard: View {
    let badge: UserBadge
    @ObservedObject var badgeService: BadgeService
    @Environment(\.colorScheme) var colorScheme
    @State private var isUpdating = false
    @State private var showSuccessFeedback = false
    @State private var currentIsVisible: Bool
    
    init(badge: UserBadge, badgeService: BadgeService) {
        self.badge = badge
        self.badgeService = badgeService
        self._currentIsVisible = State(initialValue: badge.isVisible)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: badge.swiftUIColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                    .opacity(currentIsVisible ? 1.0 : 0.3)
                
                Text(badge.emoji)
                    .font(.system(size: 24))
                    .opacity(currentIsVisible ? 1.0 : 0.5)
                
                if !currentIsVisible {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 24, height: 24)
                        )
                        .offset(x: 15, y: -15)
                }
                
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
                
                // ✅ NUEVO: Feedback de éxito
                if showSuccessFeedback {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .background(
                            Circle()
                                .fill(.white)
                                .frame(width: 24, height: 24)
                        )
                        .offset(x: 15, y: -15)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            VStack(spacing: 2) {
                Text(badge.name)
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .opacity(currentIsVisible ? 1.0 : 0.6)
                
                Text(currentIsVisible ? "Visible" : "Oculto")
                    .font(.custom("Poppins-Regular", size: 10))
                    .foregroundColor(currentIsVisible ? Color(hex: "007AFF") : .gray)
            }
            
            // ✅ NUEVO: Botón de guardar
            if currentIsVisible != badge.isVisible {
                Button(action: {
                    saveBadgeVisibility()
                }) {
                    HStack(spacing: 4) {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        
                        Text("Guardar")
                            .font(.custom("Poppins-SemiBold", size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "007AFF"))
                    .clipShape(Capsule())
                }
                .disabled(isUpdating)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            currentIsVisible ? Color(hex: "007AFF").opacity(0.3) : Color.gray.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .onTapGesture {
            toggleBadgeVisibility()
        }
        .animation(.easeInOut(duration: 0.2), value: currentIsVisible)
        .animation(.easeInOut(duration: 0.2), value: showSuccessFeedback)
    }
    
    private func toggleBadgeVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIsVisible.toggle()
        }
    }
    
    private func saveBadgeVisibility() {
        isUpdating = true
        
        badgeService.toggleBadgeVisibility(badge) { success in
            DispatchQueue.main.async {
                isUpdating = false
                
                if success {
                    // ✅ NUEVO: Feedback de éxito
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSuccessFeedback = true
                    }
                    
                    // Ocultar feedback después de 2 segundos
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSuccessFeedback = false
                        }
                    }
                    
                } else {
                    // ❌ NUEVO: Revertir cambios si falla
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentIsVisible = badge.isVisible
                    }
                }
            }
        }
    }
}

// MARK: - ✅ NUEVO: Plus Badge Toggle Card
struct PlusBadgeToggleCard: View {
    let user: AppUser
    @EnvironmentObject var authService: AuthService
    @Environment(\.colorScheme) var colorScheme
    @State private var isUpdating = false
    @State private var showSuccessFeedback = false
    @State private var currentShowPlusBadge: Bool
    
    init(user: AppUser) {
        self.user = user
        self._currentShowPlusBadge = State(initialValue: user.showPlusBadge)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                    .opacity(currentShowPlusBadge ? 1.0 : 0.3)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(currentShowPlusBadge ? 1.0 : 0.5)
                
                if !currentShowPlusBadge {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 24, height: 24)
                        )
                        .offset(x: 15, y: -15)
                }
                
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
                
                // ✅ NUEVO: Feedback de éxito
                if showSuccessFeedback {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .background(
                            Circle()
                                .fill(.white)
                                .frame(width: 24, height: 24)
                        )
                        .offset(x: 15, y: -15)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            VStack(spacing: 2) {
                Text("Plus")
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .opacity(currentShowPlusBadge ? 1.0 : 0.6)
                
                Text(currentShowPlusBadge ? "Visible" : "Oculto")
                    .font(.custom("Poppins-Regular", size: 10))
                    .foregroundColor(currentShowPlusBadge ? Color(hex: "FFD700") : .gray)
            }
            
            // ✅ NUEVO: Botón de guardar
            if currentShowPlusBadge != user.showPlusBadge {
                Button(action: {
                    savePlusBadgeVisibility()
                }) {
                    HStack(spacing: 4) {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        
                        Text("Guardar")
                            .font(.custom("Poppins-SemiBold", size: 10))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "007AFF"))
                    .clipShape(Capsule())
                }
                .disabled(isUpdating)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            currentShowPlusBadge ? Color(hex: "FFD700").opacity(0.3) : Color.gray.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .onTapGesture {
            togglePlusBadgeVisibility()
        }
        .animation(.easeInOut(duration: 0.2), value: currentShowPlusBadge)
        .animation(.easeInOut(duration: 0.2), value: showSuccessFeedback)
    }
    
    private func togglePlusBadgeVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentShowPlusBadge.toggle()
        }
    }
    
    private func savePlusBadgeVisibility() {
        isUpdating = true
        
        authService.updateUserField("showPlusBadge", value: currentShowPlusBadge) { success in
            DispatchQueue.main.async {
                isUpdating = false
                
                if success {
                    // ✅ NUEVO: Feedback de éxito
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSuccessFeedback = true
                    }
                    
                    // Ocultar feedback después de 2 segundos
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSuccessFeedback = false
                        }
                    }
                    

                } else {
                    // ❌ NUEVO: Revertir cambios si falla
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentShowPlusBadge = user.showPlusBadge
                    }
                }
            }
        }
    }
}
