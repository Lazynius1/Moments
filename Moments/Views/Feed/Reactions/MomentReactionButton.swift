// ✅ REEMPLAZAR todo el contenido de EpicReactionButton.swift con esto:

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Epic Reaction Button - VERSIÓN FINAL CORREGIDA
struct EpicReactionButton: View {
    let moment: Moment
    let showCount: Bool
    let size: CGFloat
    let emojiSize: CGFloat
    let pickerXOffset: CGFloat
    
    init(moment: Moment, showCount: Bool = true, size: CGFloat = 44, emojiSize: CGFloat = 24, pickerXOffset: CGFloat = 0) {
        self.moment = moment
        self.showCount = showCount
        self.size = size
        self.emojiSize = emojiSize
        self.pickerXOffset = pickerXOffset
    }
    @State private var showReactionPicker = false
    @State private var currentReaction: ReactionType?
    @State private var reactionCount: Int = 0
    @State private var hasReacted: Bool = false
    @State private var reactionListener: ListenerRegistration?
    
    // ✨ Estados para animaciones
    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var showRipple = false
    @State private var showReactionsSheet = false
    @State private var successAnimationTask: Task<Void, Never>?
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            if showReactionPicker {
                Color.black.opacity(0.001)
                    .frame(width: 1000, height: 2000)
                    .ignoresSafeArea(.all)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hidePickerWithAnimation()
                    }
            }
            
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // ✨ Ripple effect de fondo
                    if showRipple {
                        Circle()
                            .fill(currentReaction?.color.opacity(0.3) ?? Color.white.opacity(0.3))
                            .frame(width: size * 1.6, height: size * 1.6)
                            .scaleEffect(showRipple ? 1.5 : 0.5)
                            .opacity(showRipple ? 0 : 1)
                            .animation(.easeOut(duration: 0.6), value: showRipple)
                    }
                    
                    // ✨ Círculo principal con efectos (SIN BORDE)
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: size, height: size)
                        .contentShape(Circle())
                        .momentsChromeGlass(in: Circle())
                        .shadow(
                            color: hasReacted ?
                            (currentReaction?.color.opacity(0.4) ?? .black.opacity(0.2)) :
                            .black.opacity(0.1),
                            radius: hasReacted ? 8 : 4,
                            x: 0, y: hasReacted ? 4 : 2
                        )
                    
                    // Vacío: SF Symbol. Reaccionado: emoji con gradiente.
                    Group {
                        if hasReacted, let icon = currentReaction?.filledIcon {
                            Text(icon)
                                .font(.system(size: emojiSize, weight: .heavy))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            currentReaction?.color ?? .red,
                                            currentReaction?.color.opacity(0.7) ?? .pink
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            Image(systemName: "heart")
                                .font(.system(size: emojiSize * 0.92, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            colorScheme == .dark ? .white : Color(hex: "0B1215"),
                                            colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "0B1215").opacity(0.8)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .scaleEffect(pulseScale)
                    .rotationEffect(.degrees(rotationAngle))
                }
                .contentShape(Circle())
                .scaleEffect(isPressed ? 0.85 : (hasReacted ? 1.15 : 1.0))
                .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: isPressed), value: isPressed)
                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: hasReacted), value: hasReacted)
                .onTapGesture {
                    if hasReacted {
                        removeReactionWithAnimation()
                    } else {
                        showPickerWithAnimation()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.4, perform: {
                    showPickerWithAnimation()
                }, onPressingChanged: { pressing in
                    isPressed = pressing
                })
                
                // ✨ Contador como Badge Interactivo (SIN BORDE)
                if showCount && reactionCount > 0 {
                    Button(action: showReactionsList) {
                        Text(MomentsFormat.count(reactionCount, style: .socialMetric))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(currentReaction?.color ?? Color.gray.opacity(0.6))
                            )
                    }
                    .offset(x: 4, y: -4)
                    .transition(MotionPolicy.Transition.enterPop)
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
                    .offset(x: pickerXOffset)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(x: pickerXOffset, y: 30)),
                        removal: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(x: pickerXOffset, y: -20))
                    ))
                }
            }
        }
        .frame(width: size, height: size)
        // Por encima de comentarios/guardar mientras el picker está abierto.
        .zIndex(showReactionPicker ? 50 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reactionAccessibilityLabel)
        .accessibilityHint(Text("feed.reaction.accessibilityHint"))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            setupReactionListener()
        }
        .onDisappear {
            reactionListener?.remove()
            successAnimationTask?.cancel()
        }
        .onChange(of: hasReacted) { _, _ in
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

    private var reactionAccessibilityLabel: String {
        if hasReacted, let currentReaction {
            return String(
                format: NSLocalizedString("feed.reaction.accessibility.selected", comment: "Selected reaction accessibility label"),
                currentReaction.filledIcon,
                reactionCount
            )
        }
        return String(
            format: NSLocalizedString("feed.reaction.accessibility.default", comment: "Default reaction accessibility label"),
            reactionCount
        )
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
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
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
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toast) {
            showReactionPicker = false
        }
    }
    
    private func addReactionWithAnimation(_ reactionType: ReactionType) {
        HapticManager.shared.notification(.success)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showReactionPicker = false
        }
        
        // ✅ OPTIMISTIC UPDATE: Update local state immediately (No delay)
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.press) {
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
        HapticManager.shared.lightImpact()
        
        // ✅ OPTIMISTIC REMOVAL: Update local state immediately (No delay)
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.press) {
            self.hasReacted = false
            self.reactionCount = max(0, self.reactionCount - 1)
        }
        
        removeReactionFromFirebase()
    }
    
    private func triggerSuccessAnimation() {
        successAnimationTask?.cancel()
        successAnimationTask = Task { @MainActor in
            MotionPolicy.withOptionalAnimation(.easeInOut(duration: 0.15)) {
                pulseScale = 1.2
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            MotionPolicy.withOptionalAnimation(.bouncy(duration: 0.3)) {
                pulseScale = 1.0
            }

            MotionPolicy.withOptionalAnimation(.easeInOut(duration: 0.3)) {
                rotationAngle = 10
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            MotionPolicy.withOptionalAnimation(.easeInOut(duration: 0.3)) {
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
            if error != nil {
                // El estado se actualizará automáticamente via el listener
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
            if error != nil {
                // El estado se actualizará automáticamente via el listener
            }
        }
    }
}

// ✨ FLOATING REACTION ITEM VIEW con animación Bubble Float y escala táctil
struct FloatingReactionItemView: View {
    let reaction: ReactionType
    let index: Int
    let action: () -> Void
    
    @State private var isFloating = false
    
    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            Text(reaction.filledIcon)
                .font(.system(size: 32))
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 3)
                .offset(y: isFloating ? -4 : 4)
                .animation(
                    .easeInOut(duration: 1.4 + Double(index) * 0.08)
                    .repeatForever(autoreverses: true),
                    value: isFloating
                )
        }
        // Solo buttonStyle: un LongPress(minDuration: 0) bloqueaba el scroll
        // horizontal del picker y a veces el tap.
        .buttonStyle(.momentsPress(scale: 0.82, haptic: .none))
        .onAppear {
            guard !MotionPolicy.reduceMotion else { return }
            isFloating = true
        }
    }
}

// ✨ EPIC REACTION PICKER con Scroll Horizontal y Tracking de Uso (Cápsula de Cristal Fina y Animada)
struct EpicReactionPickerView: View {
    let onReactionSelected: (ReactionType) -> Void
    let onClose: () -> Void
    @State private var appearScale: [CGFloat] = Array(repeating: 0.3, count: 16)
    
    @StateObject private var usageTracker: UserReactionUsageTracker
    @Environment(\.colorScheme) var colorScheme

    init(onReactionSelected: @escaping (ReactionType) -> Void, onClose: @escaping () -> Void) {
        self.onReactionSelected = onReactionSelected
        self.onClose = onClose
        
        let userId = Auth.auth().currentUser?.uid ?? ""
        self._usageTracker = StateObject(wrappedValue: UserReactionUsageTracker(userId: userId))
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(usageTracker.getReactionsOrderedByUsage().enumerated()), id: \.offset) { index, reaction in
                    FloatingReactionItemView(reaction: reaction, index: index) {
                        usageTracker.incrementUsage(for: reaction)
                        onReactionSelected(reaction)
                    }
                    .scaleEffect(appearScale[index])
                    .animation(.bouncy(duration: 0.5, extraBounce: 0.25).delay(Double(index) * 0.03), value: appearScale[index])
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        // interactive: false — el glass interactivo se pelea con el ScrollView horizontal.
        .momentsChromeGlass(in: Capsule(), interactive: false)
        .clipShape(Capsule())
        .frame(width: 280)
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
            radius: 24,
            x: 0,
            y: 12
        )
        .offset(y: -90)
        .onAppear {
            for index in 0..<appearScale.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.02) {
                    withAnimation(.bouncy(duration: 0.35, extraBounce: 0.2)) {
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
    @State private var followStates: [String: FollowButtonState] = [:] // Estado de seguir para cada usuario
    @State private var followLoadingStates: [String: Bool] = [:] // Estados de carga para seguir
    @State private var pendingUnfollowUserId: String?
    @State private var searchText = ""

    @EnvironmentObject private var firestoreService: FirestoreService
    private let privacyService = PrivacyService()

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
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: Binding(
                get: { pendingUnfollowUserId != nil },
                set: { if !$0 { pendingUnfollowUserId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                if let userId = pendingUnfollowUserId {
                    pendingUnfollowUserId = nil
                    performFollowAction(for: userId)
                }
            }

            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                pendingUnfollowUserId = nil
            }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let userId = notification.userInfo?["userId"] as? String,
                  let state = notification.userInfo?["state"] as? FollowButtonState else { return }
            followStates[userId] = state
        }
        .onAppear { loadReactions() }
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(NSLocalizedString("reactions.title", value: "Reacciones", comment: "Title for reactions sheet"))
                .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Text(String(format: NSLocalizedString(
                filteredReactionGroups.count == 1 ? "reactions.typeCount.single" : "reactions.typeCount",
                comment: "Reaction type count"
            ), filteredReactionGroups.count))
                .font(.system(size: legacyPoppinsSize(13)))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
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
            
            Text(NSLocalizedString("reactions.loading", comment: "Loading reactions"))
                .font(.system(size: legacyPoppinsSize(16), weight: .medium))
                .foregroundStyle(adaptiveColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .frame(width: 76, height: 76)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle())
                }
            
            Text(NSLocalizedString("reactions.empty.title", comment: "No reactions"))
                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Text(NSLocalizedString("reactions.empty.subtitle", comment: "Empty reactions subtitle"))
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .momentsEmptyStateAppear()
    }
    
    // MARK: - No Results View
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .frame(width: 76, height: 76)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle())
                }
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("reactions.search.noResults.title", comment: "No search results"))
                    .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("reactions.search.noResults.subtitle", comment: "No search results subtitle"))
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .momentsEmptyStateAppear()
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
                        .foregroundStyle(group.type.color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.type.displayName)
                        .font(.system(size: legacyPoppinsSize(14), weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    Text(String(format: NSLocalizedString(
                        group.count == 1 ? "reactions.peopleCount.single" : "reactions.peopleCount",
                        comment: "People reaction count"
                    ), group.count))
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                
                Spacer()
            }
            
            // Lista de usuarios
            VStack(spacing: 0) {
                ForEach(Array(group.users.prefix(10).enumerated()), id: \.element) { index, userId in
                    userRowView(userId: userId, reactionType: group.type)
                    if index < min(group.users.count, 10) - 1 {
                        Divider()
                            .opacity(colorScheme == .dark ? 0.18 : 0.12)
                            .padding(.leading, 52)
                    }
                }
                
                if group.users.count > 10 {
                    Text(String(format: NSLocalizedString("reactions.more", comment: "More reactions"), group.users.count - 10))
                        .font(.system(size: legacyPoppinsSize(11)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.35))
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            
            // Información del usuario
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(userProfiles[userId]?.username ?? NSLocalizedString("messaging.user.default", comment: "Default user"))
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                    
                    if userProfiles[userId]?.isVerified == true {
                        VerifiedBadge(size: 12)
                    }
                }
                
                Text(String(format: NSLocalizedString("reactions.userReacted", comment: "User reacted with"), reactionType.displayName))
                    .font(.system(size: legacyPoppinsSize(11)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
            }
            
            Spacer()
            
            // Botón de seguir/dejar de seguir
            followButton(for: userId)
            
            // Icono pequeño de la reacción
            Text(reactionType.filledIcon)
                .font(.system(size: 16))
                .foregroundStyle(reactionType.color)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
                case .failure:
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
        let state = followStates[userId] ?? .canFollow
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
                        Image(systemName: followIcon(for: state))
                            .font(.system(size: 12, weight: .medium))
                        Text(followTitle(for: state))
                            .font(.system(size: legacyPoppinsSize(12), weight: .semibold))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .momentsChromeGlass(in: RoundedRectangle(cornerRadius: 12), interactive: state.isActionable)
                }
            }
            .disabled(isLoading || !state.isActionable)
            .opacity(isPassiveFollowState(state) ? 0.78 : 1)
            .buttonStyle(.momentsPressSubtle)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toast, value: isLoading), value: isLoading)
        }
    }
    
    // MARK: - Follow Actions
    private func handleFollowAction(for userId: String) {
        if followStates[userId] == .following {
            pendingUnfollowUserId = userId
            return
        }

        performFollowAction(for: userId)
    }

    private func performFollowAction(for userId: String) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let currentState = followStates[userId] ?? .canFollow
        guard currentState.isActionable else { return }
        
        // Actualizar estado de carga
        followLoadingStates[userId] = true
        
        if currentState == .following {
            // Dejar de seguir
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    followLoadingStates[userId] = false
                    if error == nil {
                        HapticManager.shared.lightImpact()
                        followStates[userId] = .canFollow
                        FollowStateStore.shared.setState(.canFollow, for: userId)
                    } else {
                    }
                }
            }
        } else if currentState == .requestPendingCancellable {
            firestoreService.cancelFollowRequest(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    followLoadingStates[userId] = false
                    if error == nil {
                        followStates[userId] = .canRequestFollow
                        FollowStateStore.shared.setState(.canRequestFollow, for: userId)
                    }
                }
            }
        } else {
            // Seguir
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: userId) { error in
                DispatchQueue.main.async {
                    followLoadingStates[userId] = false
                    if error == nil {
                        HapticManager.shared.mediumImpact()
                        let newState: FollowButtonState = currentState == .canRequestFollow ? .requestPendingCancellable : .following
                        followStates[userId] = newState
                        FollowStateStore.shared.setState(newState, for: userId)
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
                if let cachedState = FollowStateStore.shared.state(for: userId) {
                    followStates[userId] = cachedState
                }

                privacyService.getFollowButtonState(viewerId: currentUserId, targetUserId: userId) { state in
                    DispatchQueue.main.async {
                        let reconciledState = FollowStateStore.shared.reconciledState(state, for: userId)
                        followStates[userId] = reconciledState
                        FollowStateStore.shared.setState(reconciledState, for: userId)
                    }
                }
            }
        }
    }

    private func followTitle(for state: FollowButtonState) -> String {
        switch state {
        case .following:
            return NSLocalizedString("userProfile.followButton.following", comment: "")
        case .canRequestFollow:
            return NSLocalizedString("feed.follow.request", comment: "")
        case .requestPending:
            return NSLocalizedString("feed.follow.requested", comment: "")
        case .requestPendingCancellable:
            return NSLocalizedString("feed.follow.cancelRequest", comment: "")
        case .blocked:
            return NSLocalizedString("userProfile.followButton.blocked", comment: "")
        default:
            return NSLocalizedString("userProfile.followButton.canFollow", comment: "")
        }
    }

    private func followIcon(for state: FollowButtonState) -> String {
        switch state {
        case .following:
            return "person.fill.checkmark"
        case .canRequestFollow:
            return "person.crop.circle.badge.plus"
        case .requestPending:
            return "clock"
        case .requestPendingCancellable:
            return "xmark.circle"
        case .blocked:
            return "slash.circle"
        default:
            return "person.badge.plus"
        }
    }

    private func isPassiveFollowState(_ state: FollowButtonState) -> Bool {
        if case .requestPending = state {
            return true
        }
        return false
    }
    
    // MARK: - Search Bar
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
                .font(.system(size: 16))
            
            TextField(NSLocalizedString("userListView.search.placeholder", comment: ""), text: $searchText)
                    .font(.system(size: legacyPoppinsSize(16)))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .momentsChromeGlass(in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Adaptive Colors
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
}
