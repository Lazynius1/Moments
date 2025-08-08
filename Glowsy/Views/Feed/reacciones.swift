import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Reaction Types
enum ReactionType: String, CaseIterable {
    case vibe = "vibe"
    case fire = "fire"
    case real = "real"
    case mood = "mood"
    case glow = "glow"
    case feel = "feel"
    
    var icon: String {
        switch self {
        case .vibe: return "water.waves" // ✅ ARREGLADO: era "waveform"
        case .fire: return "flame"
        case .real: return "checkmark.seal" // ✅ ARREGLADO: era "100.square"
        case .mood: return "face.smiling"
        case .glow: return "star"
        case .feel: return "heart"
        }
    }
    
    var filledIcon: String {
        switch self {
        case .vibe: return "water.waves.slash" // ✅ ARREGLADO: era "waveform.circle.fill"
        case .fire: return "flame.fill"
        case .real: return "checkmark.seal.fill" // ✅ ARREGLADO: era "100.square.fill"
        case .mood: return "face.smiling.fill" // ✅ ARREGLADO: era "face.smiling.inverse"
        case .glow: return "star.fill"
        case .feel: return "heart.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .vibe: return Color(hex: "00A896") // Tu color principal
        case .fire: return .red
        case .real: return .purple
        case .mood: return .yellow
        case .glow: return .orange
        case .feel: return .pink
        }
    }
    
    var displayName: String {
        switch self {
        case .vibe: return "Vibe"
        case .fire: return "Fire"
        case .real: return "Real"
        case .mood: return "Mood"
        case .glow: return "Glow"
        case .feel: return "Feel"
        }
    }
}

// MARK: - Modern Reaction Button
struct ModernReactionButton: View {
    let moment: Moment
    @State private var showReactionPicker = false
    @State private var currentReaction: ReactionType?
    @State private var reactionCount: Int = 0
    @State private var hasReacted: Bool = false
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        VStack(spacing: 4) {
            Button(action: {
                if hasReacted {
                    // Si ya reaccionó, quitar reacción
                    removeReaction()
                } else {
                    // Mostrar picker de reacciones
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showReactionPicker = true
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: hasReacted ?
                                        [currentReaction?.color.opacity(0.6) ?? Color.white.opacity(0.3),
                                         currentReaction?.color.opacity(0.8) ?? Color(hex: "00A896").opacity(0.3)] :
                                        [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: hasReacted ? (currentReaction?.filledIcon ?? "heart.fill") : "heart")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: hasReacted ?
                                [currentReaction?.color ?? .red, currentReaction?.color.opacity(0.8) ?? .pink] :
                                [Color.white.opacity(0.8), Color(hex: "00A896")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .scaleEffect(hasReacted ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hasReacted)
            
            // Contador de reacciones
            if reactionCount > 0 {
                Text("\(reactionCount)")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // ✨ NUEVO: Reaction Picker
            if showReactionPicker {
                ReactionPickerView(
                    onReactionSelected: { reaction in
                        addReaction(reaction)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            showReactionPicker = false
                        }
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            showReactionPicker = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .onAppear {
            loadReactionState()
        }
    }
    
    private func loadReactionState() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // Verificar si el usuario ya reaccionó y con qué reacción
        for reactionType in ReactionType.allCases {
            if let userIds = moment.reactions[reactionType.rawValue],
               userIds.contains(currentUserId) {
                hasReacted = true
                currentReaction = reactionType
                break
            }
        }
        
        // Calcular total de reacciones
        reactionCount = moment.reactions.values.reduce(0) { total, userIds in
            total + userIds.count
        }
    }
    
    private func addReaction(_ reactionType: ReactionType) {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // Actualización optimista
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReacted = true
            currentReaction = reactionType
            reactionCount += 1
        }
        
        firestoreService.addReaction(
            to: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                // Revertir si hay error
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = false
                        self.currentReaction = nil
                        self.reactionCount -= 1
                    }
                }
                print("Error adding reaction: \(error)")
            }
        }
    }
    
    private func removeReaction() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        // Actualización optimista
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasReacted = false
            currentReaction = nil
            reactionCount -= 1
        }
        
        firestoreService.removeReaction(
            from: momentId,
            reaction: reactionType.rawValue,
            userId: currentUserId,
            authorId: moment.authorId
        ) { error in
            if let error = error {
                // Revertir si hay error
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = true
                        self.currentReaction = reactionType
                        self.reactionCount += 1
                    }
                }
                print("Error removing reaction: \(error)")
            }
        }
    }
}

// MARK: - Reaction Picker View
struct ReactionPickerView: View {
    let onReactionSelected: (ReactionType) -> Void
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(ReactionType.allCases, id: \.self) { reaction in
                Button(action: {
                    onReactionSelected(reaction)
                }) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [reaction.color.opacity(0.6), reaction.color.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: reaction.color.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: reaction.filledIcon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [reaction.color, reaction.color.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text(reaction.displayName)
                            .font(.custom("Poppins-Medium", size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .scaleEffect(1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color(hex: "00A896").opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
        .offset(y: -80) // Aparecer arriba del botón
    }
}


// MARK: - Extension para FirestoreService con métodos auxiliares
extension FirestoreService {
    
    // ✅ MÉTODO CORREGIDO: Remover reacción de la subcolección
    func removeReaction(from momentId: String, reaction: String, userId: String, authorId: String, completion: @escaping (Error?) -> Void) {
        print("🗑️ Removiendo reacción '\(reaction)' del momento \(momentId) por el usuario \(userId)")
        
        // ✅ USAR LA SUBCOLECCIÓN en lugar del documento principal
        let reactionRef = db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions").document(userId)
        
        reactionRef.delete { error in
            if let error = error {
                print("❌ Error al remover reacción: \(error.localizedDescription)")
                completion(error)
            } else {
                print("✅ Reacción removida con éxito")
                completion(nil)
            }
        }
    }
    
    // ✅ Obtener reacciones de un momento
    func fetchReactions(for momentId: String, authorId: String, completion: @escaping (Result<[String: [String]], Error>) -> Void) {
        print("📊 Obteniendo reacciones para momento \(momentId)")
        
        db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions")
            .getDocuments { snapshot, error in
                
                if let error = error {
                    print("❌ Error al obtener reacciones: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                var reactions: [String: [String]] = [:]
                
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    if let reactionType = data["reactionType"] as? String,
                       let userId = data["userId"] as? String {
                        
                        if reactions[reactionType] == nil {
                            reactions[reactionType] = []
                        }
                        reactions[reactionType]?.append(userId)
                    }
                }
                
                print("📊 Reacciones obtenidas: \(reactions)")
                completion(.success(reactions))
            }
    }
    
    // ✅ Listener para reacciones en tiempo real
    func listenToReactions(for momentId: String, authorId: String, completion: @escaping ([String: [String]]) -> Void) -> ListenerRegistration {
        print("👂 Configurando listener para reacciones del momento \(momentId)")
        
        return db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions")
            .addSnapshotListener { snapshot, error in
                
                if let error = error {
                    print("❌ Error en listener de reacciones: \(error.localizedDescription)")
                    return
                }
                
                var reactions: [String: [String]] = [:]
                
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    if let reactionType = data["reactionType"] as? String,
                       let userId = data["userId"] as? String {
                        
                        if reactions[reactionType] == nil {
                            reactions[reactionType] = []
                        }
                        reactions[reactionType]?.append(userId)
                    }
                }
                
                completion(reactions)
            }
    }
    
    // ✅ Verificar si un usuario ya reaccionó
    func checkUserReaction(for momentId: String, authorId: String, userId: String, completion: @escaping (ReactionType?) -> Void) {
        
        db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions").document(userId)
            .getDocument { snapshot, error in
                
                if let error = error {
                    print("❌ Error verificando reacción del usuario: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let data = snapshot?.data(),
                      let reactionTypeString = data["reactionType"] as? String,
                      let reactionType = ReactionType(rawValue: reactionTypeString) else {
                    completion(nil)
                    return
                }
                
                completion(reactionType)
            }
    }
}
