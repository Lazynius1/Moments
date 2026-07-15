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
    // ✨ NUEVAS REACCIONES
    case love = "love" // Cambiado de "heart" a "love" para diferenciarlo de "feel"
    case wow = "wow"
    case laugh = "laugh"
    case cry = "cry"
    case respect = "respect"
    case power = "power"
    case genius = "genius"
    case creative = "creative"
    case chill = "chill"
    case hype = "hype"
    
    var icon: String {
        switch self {
        case .vibe: return "✌🏻"
        case .fire: return "🔥"
        case .real: return "✅"
        case .mood: return "😊"
        case .glow: return "✨"
        case .feel: return "❤️"
        // ✨ NUEVAS REACCIONES
        case .love: return "💕"
        case .wow: return "😮"
        case .laugh: return "😂"
        case .cry: return "😢"
        case .respect: return "🙏🏻"
        case .power: return "⚡"
        case .genius: return "🧠"
        case .creative: return "🎨"
        case .chill: return "😌"
        case .hype: return "🎉"
        }
    }
    
    var filledIcon: String {
        // Para emojis, usamos el mismo emoji ya que no tienen versión "filled"
        return icon
    }
    
    var color: Color {
        switch self {
        case .vibe: return Color(hex: "007AFF") // Tu color principal
        case .fire: return .red
        case .real: return .purple
        case .mood: return .yellow
        case .glow: return .orange
        case .feel: return .pink
        // ✨ NUEVAS REACCIONES
        case .love: return .red
        case .wow: return .blue
        case .laugh: return .yellow
        case .cry: return .cyan // Cambiado: azul claro para diferenciarlo del azul de "wow"
        case .respect: return .green
        case .power: return .orange
        case .genius: return .indigo // Cambiado: índigo para diferenciarlo del amarillo de "mood"
        case .creative: return .purple
        case .chill: return .green
        case .hype: return .pink
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
        // ✨ NUEVAS REACCIONES
        case .love: return "Love" // Cambiado de "Heart" a "Love"
        case .wow: return "Wow"
        case .laugh: return "Laugh"
        case .cry: return "Cry"
        case .respect: return "Respect"
        case .power: return "Power"
        case .genius: return "Genius"
        case .creative: return "Creative"
        case .chill: return "Chill"
        case .hype: return "Hype"
        }
    }
}

// MARK: - User Reaction Usage Tracker
class UserReactionUsageTracker: ObservableObject {
    @Published var reactionUsageCounts: [String: Int] = [:]
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
        loadUsageCounts()
    }
    
    private func loadUsageCounts() {
        // Cargar desde UserDefaults por ahora
        // En el futuro se puede sincronizar con Firestore
        if let data = UserDefaults.standard.data(forKey: "reactionUsage_\(userId)"),
           let counts = try? JSONDecoder().decode([String: Int].self, from: data) {
            reactionUsageCounts = counts
        } else {
            // Inicializar con valores por defecto
            for reaction in ReactionType.allCases {
                reactionUsageCounts[reaction.rawValue] = 0
            }
        }
    }
    
    func incrementUsage(for reaction: ReactionType) {
        let currentCount = reactionUsageCounts[reaction.rawValue] ?? 0
        reactionUsageCounts[reaction.rawValue] = currentCount + 1
        saveUsageCounts()
    }
    
    private func saveUsageCounts() {
        if let data = try? JSONEncoder().encode(reactionUsageCounts) {
            UserDefaults.standard.set(data, forKey: "reactionUsage_\(userId)")
        }
    }
    
    func getReactionsOrderedByUsage() -> [ReactionType] {
        return ReactionType.allCases.sorted { reaction1, reaction2 in
            let count1 = reactionUsageCounts[reaction1.rawValue] ?? 0
            let count2 = reactionUsageCounts[reaction2.rawValue] ?? 0
            return count1 > count2 // Orden descendente (más usado primero)
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
                    MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
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
                                         currentReaction?.color.opacity(0.8) ?? Color(hex: "007AFF").opacity(0.3)] :
                                        [Color.white.opacity(0.3), Color(hex: "007AFF").opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    Text(hasReacted ? (currentReaction?.filledIcon ?? "❤️") : "♡")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(
                            hasReacted ? 
                            LinearGradient(
                                colors: [currentReaction?.color ?? .red, currentReaction?.color.opacity(0.7) ?? .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.blue, Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .scaleEffect(hasReacted ? 1.1 : 1.0)
            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: hasReacted), value: hasReacted)
            
            // Contador de reacciones
            if reactionCount > 0 {
                Text("\(reactionCount)")
                    .font(.system(size: legacyPoppinsSize(12), weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            
            // ✨ NUEVO: Reaction Picker con Scroll Horizontal
            if showReactionPicker {
                ReactionPickerView(
                    onReactionSelected: { reaction in
                        addReaction(reaction)
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
                            showReactionPicker = false
                        }
                    },
                    onClose: {
                        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
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
              let _ = moment.id else { return }
        
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
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
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
            if error != nil {
                // Revertir si hay error
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = false
                        self.currentReaction = nil
                        self.reactionCount -= 1
                    }
                }
            }
        }
    }
    
    private func removeReaction() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id,
              let reactionType = currentReaction else { return }
        
        // Actualización optimista
        MotionPolicy.withOptionalAnimation(MotionPolicy.Spring.toggle) {
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
            if error != nil {
                // Revertir si hay error
                DispatchQueue.main.async {
                    withAnimation {
                        self.hasReacted = true
                        self.currentReaction = reactionType
                        self.reactionCount += 1
                    }
                }
            }
        }
    }
}

// MARK: - Reaction Picker View con Scroll Horizontal
struct ReactionPickerView: View {
    let onReactionSelected: (ReactionType) -> Void
    let onClose: () -> Void
    
    @StateObject private var usageTracker: UserReactionUsageTracker
    
    init(onReactionSelected: @escaping (ReactionType) -> Void, onClose: @escaping () -> Void) {
        self.onReactionSelected = onReactionSelected
        self.onClose = onClose
        
        let userId = Auth.auth().currentUser?.uid ?? ""
        self._usageTracker = StateObject(wrappedValue: UserReactionUsageTracker(userId: userId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ✨ Scroll Horizontal con todas las reacciones
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(usageTracker.getReactionsOrderedByUsage(), id: \.self) { reaction in
                        Button(action: {
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
                                    .font(.system(size: legacyPoppinsSize(10), weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 1)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(1.0)
                        .animation(MotionPolicy.animation(MotionPolicy.Spring.press, value: true), value: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            // ✨ Botón de cerrar
            Button(action: onClose) {
                Text("Cerrar")
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color(hex: "007AFF").opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .offset(y: -80)
    }
}


// MARK: - Extension para FirestoreService con métodos auxiliares
extension FirestoreService {
    
    // ✅ MÉTODO CORREGIDO: Remover reacción de la subcolección
    func removeReaction(from momentId: String, reaction: String, userId: String, authorId: String, completion: @escaping (Error?) -> Void) {
        
        // ✅ USAR LA SUBCOLECCIÓN en lugar del documento principal
        let reactionRef = db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions").document(userId)
        
        reactionRef.delete { error in
            if let error = error {
                completion(error)
            } else {
                completion(nil)
            }
        }
    }
    
    // ✅ Obtener reacciones de un momento
    func fetchReactions(for momentId: String, authorId: String, completion: @escaping (Result<[String: [String]], Error>) -> Void) {
        
        db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions")
            .getDocuments { snapshot, error in
                
                if let error = error {
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
                
                completion(.success(reactions))
            }
    }
    
    // ✅ Listener para reacciones en tiempo real
    func listenToReactions(for momentId: String, authorId: String, completion: @escaping ([String: [String]]) -> Void) -> ListenerRegistration {
        
        return db.collection("users").document(authorId)
            .collection("moments").document(momentId)
            .collection("reactions")
            .addSnapshotListener { snapshot, error in
                
                if error != nil {
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
                
                if error != nil {
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
