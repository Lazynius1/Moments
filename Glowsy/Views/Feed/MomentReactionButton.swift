// ✅ REEMPLAZAR todo el contenido de EpicReactionButton.swift con esto:

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Epic Reaction Button - VERSIÓN FINAL CORREGIDA
struct EpicReactionButton: View {
    let moment: Moment
    let showCount: Bool
    
    init(moment: Moment, showCount: Bool = true) {
        self.moment = moment
        self.showCount = showCount
    }
    @State private var showReactionPicker = false
    @State private var currentReaction: ReactionType?
    @State private var reactionCount: Int = 0
    @State private var hasReacted: Bool = false
    @State private var reactionListener: ListenerRegistration?
    
    // ✨ Estados para animaciones épicas
    @State private var isPressed = false
    @State private var showParticles = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var showRipple = false
    @State private var showReactionsSheet = false
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: {
                if hasReacted {
                    removeReactionWithAnimation()
                } else {
                    showPickerWithAnimation()
                }
            }) {
                ZStack {
                    // ✨ Ripple effect de fondo
                    if showRipple {
                        Circle()
                            .fill(currentReaction?.color.opacity(0.3) ?? Color.white.opacity(0.3))
                            .frame(width: 70, height: 70)
                            .scaleEffect(showRipple ? 1.5 : 0.5)
                            .opacity(showRipple ? 0 : 1)
                            .animation(.easeOut(duration: 0.6), value: showRipple)
                    }
                    
                    // ✨ Círculo principal con efectos (SIN BORDE)
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                        .shadow(
                            color: hasReacted ?
                            (currentReaction?.color.opacity(0.4) ?? .black.opacity(0.2)) :
                            .black.opacity(0.1),
                            radius: hasReacted ? 8 : 4,
                            x: 0, y: hasReacted ? 4 : 2
                        )
                    
                    // ✨ Emoji
                    Text(hasReacted ? (currentReaction?.filledIcon ?? "❤️") : "♡")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(
                            hasReacted ? 
                            LinearGradient(
                                colors: [currentReaction?.color ?? .red, currentReaction?.color.opacity(0.7) ?? .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(pulseScale)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    // ✨ Partículas
                    if showParticles {
                        ForEach(0..<6, id: \.self) { index in
                            ParticleView(
                                color: currentReaction?.color ?? .white,
                                angle: Double(index) * 60,
                                show: $showParticles
                            )
                        }
                    }
                }
            }
            .scaleEffect(isPressed ? 0.85 : (hasReacted ? 1.15 : 1.0))
            .animation(.interpolatingSpring(stiffness: 600, damping: 15), value: isPressed)
            .animation(.interpolatingSpring(stiffness: 400, damping: 12), value: hasReacted)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            .onLongPressGesture(minimumDuration: 0.5) {
                showReactionsList()
            }
            
            // ✨ Contador como Badge Interactivo (SIN BORDE)
            if showCount && reactionCount > 0 {
                Button(action: showReactionsList) {
                    Text("\(reactionCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(currentReaction?.color ?? Color.gray.opacity(0.6))
                        )
                }
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            // ✨ Epic Reaction Picker (COMO OVERLAY para no deformar)
            if showReactionPicker {
                EpicReactionPickerView(
                    onReactionSelected: { reaction in
                        addReactionWithAnimation(reaction)
                    },
                    onClose: {
                        hidePickerWithAnimation()
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(y: 30)),
                    removal: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: -20))
                ))
            }
        }
        .onAppear {
            setupReactionListener()
        }
        .onDisappear {
            reactionListener?.remove()
        }
        .onChange(of: hasReacted) { _ in
            if hasReacted {
                triggerSuccessAnimation()
            }
        }
        .sheet(isPresented: $showReactionsSheet) {
            ReactionsListSheet(moment: moment, onDismiss: {
                showReactionsSheet = false
            })
            .presentationBackground(.clear)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
    }
    
    // ✅ NUEVO: Setup con listener en tiempo real
    private func setupReactionListener() {
        guard let momentId = moment.id else { return }
        
        // ✅ Listener en tiempo real para reacciones usando el método correcto
        reactionListener = firestoreService.listenToReactions(
            for: momentId,
            authorId: moment.authorId
        ) { reactions in
            DispatchQueue.main.async {
                self.updateReactionState(with: reactions)
            }
        }
    }
    
    // ✅ NUEVO: Actualizar estado basado en reacciones de Firebase
    private func updateReactionState(with reactions: [String: [String]]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Verificar si el usuario actual tiene una reacción
        var userReaction: ReactionType?
        for (reactionTypeString, userIds) in reactions {
            if userIds.contains(currentUserId),
               let reactionType = ReactionType(rawValue: reactionTypeString) {
                userReaction = reactionType
                break
            }
        }
        
        // Calcular total de reacciones
        let totalCount = reactions.values.reduce(0) { total, userIds in
            total + userIds.count
        }
        
        // Actualizar UI con animación
        withAnimation(.easeInOut(duration: 0.3)) {
            self.hasReacted = userReaction != nil
            self.currentReaction = userReaction
            self.reactionCount = totalCount
        }
    }
    
    // ✨ ANIMACIONES ÉPICAS (mantenidas igual)
    private func showPickerWithAnimation() {
        HapticManager.shared.mediumImpact()
        
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
            showReactionPicker = true
        }
        
        withAnimation(.easeOut(duration: 0.6)) {
            showRipple = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showRipple = false
        }
    }
    
    private func hidePickerWithAnimation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showReactionPicker = false
        }
    }
    
    private func addReactionWithAnimation(_ reactionType: ReactionType) {
        HapticManager.shared.notification(.success)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showReactionPicker = false
        }
        
        // ✅ OPTIMISTIC UPDATE: Update local state immediately (No delay)
        self.triggerExplosionAnimation()
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            self.hasReacted = true
            self.currentReaction = reactionType
            self.reactionCount += 1
        }
        
        // Track the reaction locally
        Task { @MainActor in
            AffinityTracker.shared.trackInteraction(type: .momentReaction, with: moment.authorId)
        }
        
        self.addReactionToFirebase(reactionType)
    }
    
    private func removeReactionWithAnimation() {
        HapticManager.shared.selection()
        
        // ✅ OPTIMISTIC REMOVAL: Update local state immediately (No delay)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            self.hasReacted = false
            self.reactionCount = max(0, self.reactionCount - 1)
        }
        
        removeReactionFromFirebase()
    }
    
    private func triggerExplosionAnimation() {
        withAnimation(.easeOut(duration: 0.8)) {
            showParticles = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showParticles = false
        }
        
        withAnimation(.easeOut(duration: 0.6)) {
            showRipple = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showRipple = false
        }
    }
    
    private func triggerSuccessAnimation() {
        withAnimation(.easeInOut(duration: 0.15)) {
            pulseScale = 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.bouncy(duration: 0.3)) {
                pulseScale = 1.0
            }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            rotationAngle = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                rotationAngle = 0
            }
        }
    }
    
    // ✨ NUEVO: Mostrar lista de reacciones via Sheet local
    private func showReactionsList() {
        HapticManager.shared.lightImpact()
        
        // Mostrar sheet local
        showReactionsSheet = true
        
    }
    
    // ✅ CORREGIDO: Métodos de Firebase usando el método corregido
    private func addReactionToFirebase(_ reactionType: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        
        // ✅ USAR EL MÉTODO CORREGIDO (que ya tienes en FirestoreService)
        firestoreService.addReaction(
            to: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                // El estado se actualizará automáticamente via el listener
            } else {
            }
        }
    }
    
    private func removeReactionFromFirebase() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        
        // ✅ USAR EL MÉTODO AUXILIAR CORREGIDO
        firestoreService.removeReaction(
            from: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                // El estado se actualizará automáticamente via el listener
            } else {
            }
        }
    }
}

// ✨ ÉPICAS PARTÍCULAS EXPLOSIVAS (mantener igual)
struct ParticleView: View {
    let color: Color
    let angle: Double
    @Binding var show: Bool
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var scale: CGFloat = 1
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(
                x: cos(angle * .pi / 180) * offset,
                y: sin(angle * .pi / 180) * offset
            )
            .onChange(of: show) { showing in
                if showing {
                    withAnimation(.easeOut(duration: 0.8)) {
                        offset = 30
                        opacity = 0
                        scale = 0.3
                    }
                } else {
                    offset = 0
                    opacity = 1
                    scale = 1
                }
            }
    }
}

// ✨ EPIC REACTION PICKER con Scroll Horizontal y Tracking de Uso
struct EpicReactionPickerView: View {
    let onReactionSelected: (ReactionType) -> Void
    let onClose: () -> Void
    @State private var appearScale: [CGFloat] = Array(repeating: 0.3, count: 16) // Actualizado para 16 reacciones
    
    @StateObject private var usageTracker: UserReactionUsageTracker
    
    @Environment(\.colorScheme) var colorScheme

    init(onReactionSelected: @escaping (ReactionType) -> Void, onClose: @escaping () -> Void) {
        self.onReactionSelected = onReactionSelected
        self.onClose = onClose
        
        let userId = Auth.auth().currentUser?.uid ?? ""
        self._usageTracker = StateObject(wrappedValue: UserReactionUsageTracker(userId: userId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ✨ Scroll Horizontal con todas las reacciones ordenadas por uso
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(usageTracker.getReactionsOrderedByUsage().enumerated()), id: \.offset) { index, reaction in
                        Button(action: {
                            HapticManager.shared.lightImpact()
                            
                            // Incrementar uso de esta reacción
                            usageTracker.incrementUsage(for: reaction)
                            onReactionSelected(reaction)
                        }) {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(reaction.color.opacity(0.2))
                                        .frame(width: 50, height: 50)
                                        .blur(radius: 8)
                                    
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [reaction.color.opacity(0.8), reaction.color],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 2
                                                )
                                        )
                                        .shadow(color: reaction.color.opacity(0.4), radius: 6, x: 0, y: 3)
                                    
                                    Text(reaction.filledIcon)
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [reaction.color, reaction.color.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: reaction.color.opacity(0.6), radius: 2)
                                }
                                
                                Text(reaction.displayName)
                                    .font(.custom("Poppins-Bold", size: 10))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 1)
                            }
                        }
                        .scaleEffect(appearScale[index])
                        .animation(.bouncy(duration: 0.6, extraBounce: 0.3).delay(Double(index) * 0.05), value: appearScale[index])
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                appearScale[index] = 0.9
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.bouncy(duration: 0.4)) {
                                    appearScale[index] = 1.0
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            
            // ✨ Botón de cerrar
            Button(action: onClose) {
                Text(NSLocalizedString("common.close", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .liquidGlass(in: Capsule())
            }
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.white.opacity(0.1))
                )
        )
        .frame(width: 280) // ✅ Ancho explícito para que no se vea estrecho en el overlay
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .offset(y: -90)
        .onAppear {
            for index in 0..<appearScale.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.03) {
                    withAnimation(.bouncy(duration: 0.4, extraBounce: 0.2)) {
                        appearScale[index] = 1.0
                    }
                }
            }
        }
    }
}

// MARK: - ReactionsListSheet
struct ReactionsListSheet: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    let moment: Moment
    let onDismiss: () -> Void

    @State private var reactions: [String: [String]] = [:]
    @State private var userProfiles: [String: AppUser] = [:]
    @State private var isLoading = true
    @State private var followStates: [String: Bool] = [:] // Estado de seguir para cada usuario
    @State private var followLoadingStates: [String: Bool] = [:] // Estados de carga para seguir
    @State private var searchText = ""

    @EnvironmentObject private var firestoreService: FirestoreService

    struct ReactionGroup {
        let type: ReactionType
        let users: [String]
        let count: Int
    }

    private var reactionGroups: [ReactionGroup] {
        let groups = reactions.compactMap { (reactionTypeString, userIds) -> ReactionGroup? in
            guard let reactionType = ReactionType(rawValue: reactionTypeString),
                  !userIds.isEmpty else { return nil }
            return ReactionGroup(type: reactionType, users: userIds, count: userIds.count)
        }
        return groups.sorted { $0.count > $1.count } // Order by count (most popular first)
    }
    
    // MARK: - Filtered Reaction Groups
    private var filteredReactionGroups: [ReactionGroup] {
        if searchText.isEmpty {
            return reactionGroups
        } else {
            return reactionGroups.compactMap { group in
                // Filtrar usuarios que coincidan con la búsqueda
                let filteredUsers = group.users.filter { userId in
                    if let user = userProfiles[userId] {
                        return user.username.localizedCaseInsensitiveContains(searchText) ||
                               (user.bio?.localizedCaseInsensitiveContains(searchText) ?? false)
                    }
                    return false
                }
                
                // Solo incluir grupos que tengan usuarios filtrados
                if filteredUsers.isEmpty {
                    return nil
                }
                
                return ReactionGroup(type: group.type, users: filteredUsers, count: filteredUsers.count)
            }
        }
    }

    var body: some View {
                        VStack(spacing: 0) {
                    // Header con título
                    headerView
                    
                    // Searchbar para buscar usuarios
                    searchBarView
                    
                    // Contenido principal
                    if isLoading { loadingView }
                    else if filteredReactionGroups.isEmpty { 
                        if reactionGroups.isEmpty { emptyStateView }
                        else { noResultsView }
                    }
                    else { reactionsList }
                }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { loadReactions() }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(NSLocalizedString("reactions.title", value: "Reacciones", comment: "Title for reactions sheet"))
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("\(filteredReactionGroups.count) \(filteredReactionGroups.count == 1 ? "tipo" : "tipos") de reacción")
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
                .tint(.white)
            
            Text("Cargando reacciones...")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(adaptiveColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            
            Text("No hay reacciones")
                .font(.custom("Poppins-Bold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("Sé el primero en reaccionar a este momento")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - No Results View
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
                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.4)],
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
        .padding(.vertical, 60)
    }

    // MARK: - Reactions List
    private var reactionsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredReactionGroups, id: \.type.rawValue) { group in
                    reactionGroupView(group: group)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Reaction Group View
    private func reactionGroupView(group: ReactionGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header del grupo con icono y contador
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(group.type.color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Text(group.type.filledIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(group.type.color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.type.displayName)
                        .font(.custom("Poppins-Bold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("\(group.count) \(group.count == 1 ? "persona" : "personas")")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                
                Spacer()
            }
            
            // Lista de usuarios
            VStack(spacing: 6) {
                ForEach(group.users.prefix(10), id: \.self) { userId in
                    userRowView(userId: userId, reactionType: group.type)
                }
                
                if group.users.count > 10 {
                    HStack {
                        Spacer()
                        Text("Y \(group.users.count - 10) más...")
                            .font(.custom("Poppins-Regular", size: 11))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.1))
                            )
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - User Row View
    private func userRowView(userId: String, reactionType: ReactionType) -> some View {
        HStack(spacing: 12) {
            // Avatar del usuario con estilo moderno
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                AsyncImage(url: URL(string: userProfiles[userId]?.profileImagePath ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            
            // Información del usuario
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(userProfiles[userId]?.username ?? "Usuario")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if userProfiles[userId]?.isVerified == true {
                        VerifiedBadge(size: 12)
                    }
                }
                
                Text("Reaccionó con \(reactionType.displayName)")
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
            }
            
            Spacer()
            
            // Botón de seguir/dejar de seguir
            followButton(for: userId)
            
            // Icono pequeño de la reacción
            Text(reactionType.filledIcon)
                .font(.system(size: 16))
                .foregroundColor(reactionType.color)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Data Loading
    private func loadReactions() {
        guard let momentId = moment.id else {
            isLoading = false
            return
        }
        
        firestoreService.fetchReactions(for: momentId, authorId: moment.authorId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let fetchedReactions):
                    self.reactions = fetchedReactions
                    self.loadUserProfiles(for: fetchedReactions)
                case .failure(let error):
                    self.isLoading = false
                }
            }
        }
    }

    private func loadUserProfiles(for reactions: [String: [String]]) {
        let allUserIds = Array(Set(reactions.values.flatMap { $0 }))
        
        guard !allUserIds.isEmpty else {
            isLoading = false
            return
        }
        
        firestoreService.fetchUsers(userIds: allUserIds) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    for user in users {
                        self.userProfiles[user.id] = user
                    }
                    
                    // Cargar estados de seguir después de cargar perfiles
                    self.loadFollowStates()
                case .failure(_):
                    break
                }
                self.isLoading = false
            }
        }
    }

    // MARK: - Follow Button
    @ViewBuilder
    private func followButton(for userId: String) -> some View {
        let isFollowing = followStates[userId] ?? false
        let isLoading = followLoadingStates[userId] ?? false
        
        // No mostrar botón para el usuario actual
        if userId == Auth.auth().currentUser?.uid {
            EmptyView()
        } else {
            Button(action: {
                handleFollowAction(for: userId)
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(colorScheme == .dark ? .white : .black)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                        Text(isFollowing ? NSLocalizedString("userListView.unfollowButton", comment: "") : NSLocalizedString("userListView.followButton", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 12))
                    }
                    .foregroundColor(isFollowing ? .red : (colorScheme == .dark ? .white : .black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
                    .shadow(
                        color: isFollowing ? 
                            .red.opacity(0.1) : 
                            .black.opacity(0.1),
                        radius: isFollowing ? 2 : 4,
                        x: 0,
                        y: isFollowing ? 1 : 2
                    )
                }
            }
            .disabled(isLoading)
            .scaleEffect(isFollowing ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFollowing)
        }
    }
    
    // MARK: - Follow Actions
    private func handleFollowAction(for userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let isFollowing = followStates[userId] ?? false
        
        // Actualizar estado de carga
        followLoadingStates[userId] = true
        
        if isFollowing {
            // Dejar de seguir
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    followLoadingStates[userId] = false
                    if error == nil {
                        followStates[userId] = false
                    } else {
                    }
                }
            }
        } else {
            // Seguir
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    followLoadingStates[userId] = false
                    if error == nil {
                        followStates[userId] = true
                    } else {
                    }
                }
            }
        }
    }
    
    // MARK: - Load Follow States
    private func loadFollowStates() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let userIds = Array(userProfiles.keys)
        for userId in userIds {
            if userId != currentUserId {
                firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: userId) { isFollowing in
                    DispatchQueue.main.async {
                        followStates[userId] = isFollowing
                    }
                }
            }
        }
    }
    
    // MARK: - Search Bar
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 16))
            
            TextField(NSLocalizedString("userListView.search.placeholder", comment: ""), text: $searchText)
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
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Adaptive Colors
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
}
