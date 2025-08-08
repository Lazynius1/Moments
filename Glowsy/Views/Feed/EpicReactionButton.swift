// ✅ REEMPLAZAR todo el contenido de EpicReactionButton.swift con esto:

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Epic Reaction Button - VERSIÓN FINAL CORREGIDA
struct EpicReactionButton: View {
    let moment: Moment
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
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        VStack(spacing: 4) {
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
                            .fill(currentReaction?.color.opacity(0.3) ?? Color(hex: "00A896").opacity(0.3))
                            .frame(width: 80, height: 80)
                            .scaleEffect(showRipple ? 1.5 : 0.5)
                            .opacity(showRipple ? 0 : 1)
                            .animation(.easeOut(duration: 0.6), value: showRipple)
                    }
                    
                    // ✨ Círculo principal con efectos
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: hasReacted ?
                                        [currentReaction?.color.opacity(0.8) ?? Color.white.opacity(0.3),
                                         currentReaction?.color ?? Color(hex: "00A896")] :
                                        [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: hasReacted ? 2.5 : 1.5
                                )
                        )
                        .shadow(
                            color: hasReacted ?
                            (currentReaction?.color.opacity(0.4) ?? Color(hex: "00A896").opacity(0.4)) :
                            .black.opacity(0.1),
                            radius: hasReacted ? 8 : 4,
                            x: 0, y: hasReacted ? 4 : 2
                        )
                    
                    // ✨ Icono con animaciones mega épicas
                    Image(systemName: hasReacted ? (currentReaction?.filledIcon ?? "heart.fill") : "heart")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(
                                colors: hasReacted ?
                                [currentReaction?.color ?? .red, currentReaction?.color.opacity(0.7) ?? .pink] :
                                [Color.white.opacity(0.8), Color(hex: "00A896")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(pulseScale)
                        .rotationEffect(.degrees(rotationAngle))
                        .shadow(
                            color: hasReacted ?
                            (currentReaction?.color.opacity(0.6) ?? .clear) : .clear,
                            radius: hasReacted ? 4 : 0
                        )
                    
                    // ✨ Partículas optimizadas
                    if showParticles {
                        ForEach(0..<6, id: \.self) { index in
                            ParticleView(
                                color: currentReaction?.color ?? Color(hex: "00A896"),
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
            
            // ✨ Contador animado
            if reactionCount > 0 {
                Text("\(reactionCount)")
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(currentReaction?.color.opacity(0.8) ?? Color(hex: "00A896").opacity(0.8))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .scaleEffect(hasReacted ? 1.1 : 1.0)
                    .animation(.bouncy(duration: 0.4), value: reactionCount)
            }
            
            // ✨ Epic Reaction Picker
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
    }
    
    // ✅ NUEVO: Setup con listener en tiempo real
    private func setupReactionListener() {
        guard let momentId = moment.id else { return }
        
        print("🔄 Configurando listener para momento: \(momentId)")
        
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
        
        print("📊 Estado actualizado - Reaccionado: \(hasReacted), Tipo: \(userReaction?.rawValue ?? "ninguno"), Total: \(totalCount)")
    }
    
    // ✨ ANIMACIONES ÉPICAS (mantenidas igual)
    private func showPickerWithAnimation() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
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
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showReactionPicker = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.triggerExplosionAnimation()
            self.addReactionToFirebase(reactionType)
        }
    }
    
    private func removeReactionWithAnimation() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
        
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
    
    // ✅ CORREGIDO: Métodos de Firebase usando el método corregido
    private func addReactionToFirebase(_ reactionType: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        print("➕ Agregando reacción '\(reactionType.rawValue)' al momento \(momentId)")
        
        // ✅ USAR EL MÉTODO CORREGIDO (que ya tienes en FirestoreService)
        firestoreService.addReaction(
            to: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                print("❌ Error adding reaction: \(error)")
                // El estado se actualizará automáticamente via el listener
            } else {
                print("✅ Reacción agregada exitosamente")
            }
        }
    }
    
    private func removeReactionFromFirebase() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        print("🗑️ Removiendo reacción '\(reactionType.rawValue)' del momento \(momentId)")
        
        // ✅ USAR EL MÉTODO AUXILIAR CORREGIDO
        firestoreService.removeReaction(
            from: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                print("❌ Error removing reaction: \(error)")
                // El estado se actualizará automáticamente via el listener
            } else {
                print("✅ Reacción removida exitosamente")
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

// ✨ EPIC REACTION PICKER (mantener igual)
struct EpicReactionPickerView: View {
    let onReactionSelected: (ReactionType) -> Void
    let onClose: () -> Void
    @State private var appearScale: [CGFloat] = Array(repeating: 0.3, count: 6)
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(ReactionType.allCases.enumerated()), id: \.offset) { index, reaction in
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
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
                            
                            Image(systemName: reaction.filledIcon)
                                .font(.system(size: 20, weight: .bold))
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
                .animation(.bouncy(duration: 0.6, extraBounce: 0.3).delay(Double(index) * 0.1), value: appearScale[index])
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .offset(y: -90)
        .onAppear {
            for index in 0..<appearScale.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                    withAnimation(.bouncy(duration: 0.4, extraBounce: 0.2)) {
                        appearScale[index] = 1.0
                    }
                }
            }
        }
    }
}
