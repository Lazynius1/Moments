import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - 🔥 NUEVA ESTRUCTURA PARA CONFIGURACIÓN DINÁMICA
struct ModerationSettings: Codable {
    let deleteThresholds: ThresholdSettings
    let warningThresholds: ThresholdSettings
    let enableAutoApproval: Bool
    let enableDetailedLogging: Bool
    let moderationMode: String
    let updatedAt: Date?
    let updatedBy: String?
}

struct ThresholdSettings: Codable {
    let harassment: Double
    let hate: Double
    let sexual: Double
    let violence: Double
    let selfHarm: Double
    let sexualMinors: Double
}

// MARK: - Modelos de moderación OpenAI (mantener igual)
struct ModerationResponse: Codable {
    let id: String
    let model: String
    let results: [ModerationResult]
}

struct ModerationResult: Codable {
    let flagged: Bool
    let categories: ModerationCategories
    let categoryScores: ModerationCategoryScores
    
    enum CodingKeys: String, CodingKey {
        case flagged, categories
        case categoryScores = "category_scores"
    }
}

struct ModerationCategories: Codable {
    let harassment: Bool
    let harassmentThreatening: Bool
    let hate: Bool
    let hateThreatening: Bool
    let selfHarm: Bool
    let selfHarmInstructions: Bool
    let selfHarmIntent: Bool
    let sexual: Bool
    let sexualMinors: Bool
    let violence: Bool
    let violenceGraphic: Bool
    
    enum CodingKeys: String, CodingKey {
        case harassment, hate, sexual, violence
        case harassmentThreatening = "harassment/threatening"
        case hateThreatening = "hate/threatening"
        case selfHarm = "self-harm"
        case selfHarmInstructions = "self-harm/instructions"
        case selfHarmIntent = "self-harm/intent"
        case sexualMinors = "sexual/minors"
        case violenceGraphic = "violence/graphic"
    }
}

struct ModerationCategoryScores: Codable {
    let harassment: Double
    let harassmentThreatening: Double
    let hate: Double
    let hateThreatening: Double
    let selfHarm: Double
    let selfHarmInstructions: Double
    let selfHarmIntent: Double
    let sexual: Double
    let sexualMinors: Double
    let violence: Double
    let violenceGraphic: Double
    
    enum CodingKeys: String, CodingKey {
        case harassment, hate, sexual, violence
        case harassmentThreatening = "harassment/threatening"
        case hateThreatening = "hate/threatening"
        case selfHarm = "self-harm"
        case selfHarmInstructions = "self-harm/instructions"
        case selfHarmIntent = "self-harm/intent"
        case sexualMinors = "sexual/minors"
        case violenceGraphic = "violence/graphic"
    }
}

// MARK: - Resultado de moderación
enum ModerationAction {
    case approved
    case rejected(reason: String, category: String)
    case warning(reason: String, category: String)
}

// MARK: - Estados de comentario
enum CommentModerationStatus: String, CaseIterable {
    case approved = "approved"
    case pending = "pending"
    case rejected = "rejected"
    case manualReview = "manual_review"
}

// MARK: - Servicio principal de moderación CON CONFIGURACIÓN DINÁMICA
class CommentModerationService {
    
    static let shared = CommentModerationService()
    
    private let apiKey = "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"
    private let baseURL = "https://api.openai.com/v1/moderations"
    
    // 🔥 CACHE DE CONFIGURACIÓN
    private var cachedSettings: ModerationSettings?
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutos
    
    private init() {}
    
    // MARK: - 🔥 CARGAR CONFIGURACIÓN DESDE FIRESTORE
    private func loadModerationSettings() async -> ModerationSettings {
        if let cached = cachedSettings,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheValidityDuration {
            print("🔄 Usando configuración en cache")
            return cached
        }
        
        print("📥 Cargando configuración desde Firestore...")
        
        let db = Firestore.firestore()
        
        do {
            let document = try await db.collection("moderationSettings").document("comments").getDocument()
            
            if document.exists {
                // Usar Firestore Decoder directamente
                let settings = try document.data(as: ModerationSettings.self)
                
                // Actualizar cache
                self.cachedSettings = settings
                self.lastFetchTime = Date()
                
                print("✅ Configuración cargada: Modo \(settings.moderationMode)")
                print("📊 Umbrales delete - harassment: \(settings.deleteThresholds.harassment)")
                print("📊 Umbrales warning - harassment: \(settings.warningThresholds.harassment)")
                
                return settings
            } else {
                print("⚠️ No se encontró configuración, usando valores por defecto")
                return getDefaultSettings()
            }
            
        } catch {
            print("❌ Error cargando configuración: \(error.localizedDescription)")
            return getDefaultSettings()
        }
    }
    
    // MARK: - 🔧 CONFIGURACIÓN POR DEFECTO
    private func getDefaultSettings() -> ModerationSettings {
        return ModerationSettings(
            deleteThresholds: ThresholdSettings(
                harassment: 0.8,
                hate: 0.8,
                sexual: 0.9,
                violence: 0.8,
                selfHarm: 0.9,
                sexualMinors: 0.1
            ),
            warningThresholds: ThresholdSettings(
                harassment: 0.5,
                hate: 0.5,
                sexual: 0.6,
                violence: 0.5,
                selfHarm: 0.7,
                sexualMinors: 0.1
            ),
            enableAutoApproval: true,
            enableDetailedLogging: true,
            moderationMode: "balanced",
            updatedAt: nil,
            updatedBy: nil
        )
    }
    
    // MARK: - 🔥 FUNCIÓN PRINCIPAL DE MODERACIÓN (ACTUALIZADA)
    func moderateComment(_ text: String) async throws -> ModerationAction {
        // 1. Cargar configuración dinámica
        let settings = await loadModerationSettings()
        
        // 2. Llamar a OpenAI
        let request = createModerationRequest(for: text)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommentsModerationError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            print("❌ OpenAI API Error: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("Error details: \(errorData)")
            }
            throw CommentsModerationError.apiError
        }
        
        let moderationResponse = try JSONDecoder().decode(ModerationResponse.self, from: data)
        
        // 3. Procesar con configuración dinámica
        return processModerationResult(moderationResponse.results.first, settings: settings)
    }
    
    // MARK: - Crear request (sin cambios)
    private func createModerationRequest(for text: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["input": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        return request
    }
    
    // MARK: - 🔥 PROCESAR RESULTADO CON CONFIGURACIÓN DINÁMICA
    private func processModerationResult(_ result: ModerationResult?, settings: ModerationSettings) -> ModerationAction {
        guard let result = result else {
            return .approved
        }
        
        if !result.flagged {
            return .approved
        }
        
        let categories = result.categories
        let scores = result.categoryScores
        
        print("🔍 Aplicando umbrales dinámicos:")
        print("📊 Scores - harassment: \(scores.harassment), hate: \(scores.hate), sexual: \(scores.sexual)")
        print("⚙️ Delete thresholds - harassment: \(settings.deleteThresholds.harassment), hate: \(settings.deleteThresholds.hate)")
        print("⚙️ Warning thresholds - harassment: \(settings.warningThresholds.harassment), hate: \(settings.warningThresholds.hate)")
        
        // 🚨 RECHAZAR INMEDIATAMENTE - Contenido muy grave (sin cambios)
        if categories.sexualMinors {
            return .rejected(reason: "Contenido relacionado con menores no permitido", category: "sexual/minors")
        }
        
        if categories.hateThreatening || categories.harassmentThreatening {
            return .rejected(reason: "Amenazas no permitidas", category: "threats")
        }
        
        if categories.selfHarmInstructions {
            return .rejected(reason: "Contenido de autolesión no permitido", category: "self-harm")
        }
        
        if categories.violenceGraphic && scores.violenceGraphic > settings.deleteThresholds.violence {
            return .rejected(reason: "Violencia extrema no permitida", category: "violence")
        }
        
        // 🚨 RECHAZAR - Usando umbrales dinámicos de eliminación
        if scores.harassment > settings.deleteThresholds.harassment {
            print("🚨 Eliminando por harassment: \(scores.harassment) > \(settings.deleteThresholds.harassment)")
            return .rejected(reason: "Contenido de acoso detectado", category: "harassment")
        }
        
        if scores.hate > settings.deleteThresholds.hate {
            print("🚨 Eliminando por hate: \(scores.hate) > \(settings.deleteThresholds.hate)")
            return .rejected(reason: "Discurso de odio detectado", category: "hate")
        }
        
        if scores.sexual > settings.deleteThresholds.sexual {
            print("🚨 Eliminando por sexual: \(scores.sexual) > \(settings.deleteThresholds.sexual)")
            return .rejected(reason: "Contenido sexual inapropiado", category: "sexual")
        }
        
        if scores.violence > settings.deleteThresholds.violence {
            print("🚨 Eliminando por violence: \(scores.violence) > \(settings.deleteThresholds.violence)")
            return .rejected(reason: "Contenido violento detectado", category: "violence")
        }
        
        if scores.selfHarm > settings.deleteThresholds.selfHarm {
            print("🚨 Eliminando por selfHarm: \(scores.selfHarm) > \(settings.deleteThresholds.selfHarm)")
            return .rejected(reason: "Contenido de autolesión detectado", category: "self-harm")
        }
        
        // ⚠️ ADVERTIR - Usando umbrales dinámicos de advertencia
        if scores.harassment > settings.warningThresholds.harassment {
            print("⚠️ Advertencia por harassment: \(scores.harassment) > \(settings.warningThresholds.harassment)")
            return .warning(reason: "Comentario detectado como potencialmente ofensivo", category: "harassment")
        }
        
        if scores.hate > settings.warningThresholds.hate {
            print("⚠️ Advertencia por hate: \(scores.hate) > \(settings.warningThresholds.hate)")
            return .warning(reason: "Posible discurso de odio detectado", category: "hate")
        }
        
        if scores.sexual > settings.warningThresholds.sexual {
            print("⚠️ Advertencia por sexual: \(scores.sexual) > \(settings.warningThresholds.sexual)")
            return .warning(reason: "Contenido sexual inapropiado", category: "sexual")
        }
        
        if scores.violence > settings.warningThresholds.violence {
            print("⚠️ Advertencia por violence: \(scores.violence) > \(settings.warningThresholds.violence)")
            return .warning(reason: "Contenido violento detectado", category: "violence")
        }
        
        if scores.selfHarm > settings.warningThresholds.selfHarm {
            print("⚠️ Advertencia por selfHarm: \(scores.selfHarm) > \(settings.warningThresholds.selfHarm)")
            return .warning(reason: "Contenido de autolesión detectado", category: "self-harm")
        }
        
        // ✅ Si llega aquí, aprobar
        print("✅ Contenido aprobado - todos los scores están por debajo de los umbrales")
        return .approved
    }
    
    // MARK: - Función wrapper para usar en tu código existente (sin cambios)
    func moderateAndHandle(
        content: String,
        onApproved: @escaping () -> Void,
        onWarning: @escaping (String, String) -> Void,
        onRejected: @escaping (String, String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task {
            do {
                let result = try await moderateComment(content)
                
                await MainActor.run {
                    switch result {
                    case .approved:
                        onApproved()
                        
                    case .warning(let reason, let category):
                        onWarning(reason, category)
                        
                    case .rejected(let reason, let category):
                        onRejected(reason, category)
                    }
                }
                
            } catch {
                await MainActor.run {
                    onError(error)
                }
            }
        }
    }
    
    // 🔥 NUEVA FUNCIÓN: Guardar log en Firestore (sin cambios)
    func logModerationEvent(
        userId: String,
        content: String,
        action: String,
        reason: String,
        category: String,
        momentId: String
    ) {
        let db = Firestore.firestore()
        
        // 📊 Datos del log
        let logData: [String: Any] = [
            "userId": userId,
            "content": content,
            "action": action,
            "reason": reason,
            "category": category,
            "momentId": momentId,
            "timestamp": Timestamp(),
            "platform": "ios",
            "moderationType": "auto_comment",
            "moderationVersion": "2.0", // ✅ Actualizado para indicar versión dinámica
            "apiProvider": "openai"
        ]
        
        // 💾 Guardar en Firestore
        db.collection("moderationLogs").addDocument(data: logData) { error in
            if let error = error {
                print("❌ Error guardando log de moderación: \(error.localizedDescription)")
            } else {
                print("📊 Log de moderación guardado exitosamente")
                print("📝 Acción: \(action) - Categoría: \(category)")
                print("📝 Razón: \(reason)")
            }
        }
    }
    
    // 🔥 NUEVA FUNCIÓN: Log con más detalles (scores de OpenAI) (sin cambios)
    func logModerationEventWithDetails(
        userId: String,
        content: String,
        action: String,
        reason: String,
        category: String,
        momentId: String,
        moderationResult: ModerationResult? = nil
    ) {
        let db = Firestore.firestore()
        
        // 📊 Datos básicos
        var logData: [String: Any] = [
            "userId": userId,
            "content": content,
            "action": action,
            "reason": reason,
            "category": category,
            "momentId": momentId,
            "timestamp": Timestamp(),
            "platform": "ios",
            "moderationType": "auto_comment",
            "moderationVersion": "2.0", // ✅ Actualizado
            "apiProvider": "openai"
        ]
        
        // 📈 Agregar scores detallados si están disponibles
        if let result = moderationResult {
            let scores: [String: Any] = [
                "flagged": result.flagged,
                "harassment": result.categoryScores.harassment,
                "harassmentThreatening": result.categoryScores.harassmentThreatening,
                "hate": result.categoryScores.hate,
                "hateThreatening": result.categoryScores.hateThreatening,
                "selfHarm": result.categoryScores.selfHarm,
                "selfHarmInstructions": result.categoryScores.selfHarmInstructions,
                "selfHarmIntent": result.categoryScores.selfHarmIntent,
                "sexual": result.categoryScores.sexual,
                "sexualMinors": result.categoryScores.sexualMinors,
                "violence": result.categoryScores.violence,
                "violenceGraphic": result.categoryScores.violenceGraphic
            ]
            
            let categories: [String: Any] = [
                "harassment": result.categories.harassment,
                "harassmentThreatening": result.categories.harassmentThreatening,
                "hate": result.categories.hate,
                "hateThreatening": result.categories.hateThreatening,
                "selfHarm": result.categories.selfHarm,
                "selfHarmInstructions": result.categories.selfHarmInstructions,
                "selfHarmIntent": result.categories.selfHarmIntent,
                "sexual": result.categories.sexual,
                "sexualMinors": result.categories.sexualMinors,
                "violence": result.categories.violence,
                "violenceGraphic": result.categories.violenceGraphic
            ]
            
            logData["scores"] = scores
            logData["categoriesDetailed"] = categories
        }
        
        // 💾 Guardar en Firestore
        db.collection("moderationLogs").addDocument(data: logData) { error in
            if let error = error {
                print("❌ Error guardando log detallado: \(error.localizedDescription)")
            } else {
                print("📊 Log detallado guardado exitosamente")
                print("📝 Acción: \(action) - Categoría: \(category)")
                print("📝 Razón: \(reason)")
                if let result = moderationResult {
                    print("📈 Score más alto: \(self.getHighestScore(result.categoryScores))")
                }
            }
        }
    }
    
    // 🔧 Helper para obtener el score más alto (sin cambios)
    private func getHighestScore(_ scores: ModerationCategoryScores) -> String {
        let scoreDict = [
            "harassment": scores.harassment,
            "hate": scores.hate,
            "sexual": scores.sexual,
            "violence": scores.violence,
            "selfHarm": scores.selfHarm
        ]
        
        if let maxCategory = scoreDict.max(by: { $0.value < $1.value }) {
            return "\(maxCategory.key): \(String(format: "%.2f", maxCategory.value))"
        }
        
        return "N/A"
    }
    
    // 🔥 NUEVA FUNCIÓN: Forzar recarga de configuración
    func reloadSettings() {
        cachedSettings = nil
        lastFetchTime = nil
        print("🔄 Cache de configuración limpiado - se recargará en el próximo uso")
    }
}

// MARK: - Errores de moderación (sin cambios)
enum CommentsModerationError: Error {
    case apiError
    case invalidResponse
    case networkError
    
    var localizedDescription: String {
        switch self {
        case .apiError:
            return "Error en la API de moderación"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .networkError:
            return "Error de conexión"
        }
    }
}
