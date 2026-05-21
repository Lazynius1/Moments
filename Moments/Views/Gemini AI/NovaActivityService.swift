import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - 🎯 Servicio de Actividad de Nova
// Permite a Nova acceder a datos de la app para responder preguntas sobre actividad
class NovaActivityService {
    static let shared = NovaActivityService()
    private let db = Firestore.firestore()
    private let firestoreService = FirestoreService()
    
    private init() {}
    
    // MARK: - 📊 Story Chain Viewers (Optimizado con Resumen)
    /// Obtiene un resumen optimizado de viewers (5 más recientes + conteo total)
    func getStoryChainViewersSummary(chainId: String, userId: String, completion: @escaping (Result<StoryChainViewersSummary, Error>) -> Void) {
        // Obtener todas las stories del chain
        db.collection("users").document(userId).collection("stories")
            .whereField("chainId", isEqualTo: chainId)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(.success(StoryChainViewersSummary(recentViewers: [], totalCount: 0)))
                    return
                }
                
                // Obtener todos los viewers únicos de todas las stories del chain
                var allViewers: [String: StoryViewer] = [:]
                let group = DispatchGroup()
                
                for document in documents {
                    let storyId = document.documentID
                    group.enter()
                    
                    self.db.collection("users").document(userId).collection("stories")
                        .document(storyId).collection("viewers")
                        .getDocuments { snapshot, error in
                            defer { group.leave() }
                            
                            if let error = error {
                                return
                            }
                            
                            guard let viewerDocs = snapshot?.documents else { return }
                            
                            for viewerDoc in viewerDocs {
                                let data = viewerDoc.data()
                                if let userId = data["userId"] as? String,
                                   let username = data["username"] as? String,
                                   let timestamp = data["timestamp"] as? Timestamp {
                                    
                                    // Si ya existe, mantener el timestamp más reciente
                                    if let existing = allViewers[userId] {
                                        if timestamp.dateValue() > existing.timestamp {
                                            allViewers[userId] = StoryViewer(
                                                id: userId,
                                                userId: userId,
                                                username: username,
                                                profileImagePath: data["profileImagePath"] as? String,
                                                timestamp: timestamp.dateValue()
                                            )
                                        }
                                    } else {
                                        allViewers[userId] = StoryViewer(
                                            id: userId,
                                            userId: userId,
                                            username: username,
                                            profileImagePath: data["profileImagePath"] as? String,
                                            timestamp: timestamp.dateValue()
                                        )
                                    }
                                }
                            }
                        }
                }
                
                group.notify(queue: .main) {
                    let allViewersList = Array(allViewers.values).sorted { $0.timestamp > $1.timestamp }
                    let recentViewers = Array(allViewersList.prefix(5))
                    let summary = StoryChainViewersSummary(
                        recentViewers: recentViewers,
                        totalCount: allViewersList.count
                    )
                    completion(.success(summary))
                }
            }
    }
    
    /// Obtiene los viewers de un Story Chain específico (método completo - usar solo si es necesario)
    func getStoryChainViewers(chainId: String, userId: String, completion: @escaping (Result<[StoryViewer], Error>) -> Void) {
        // Obtener todas las stories del chain
        db.collection("users").document(userId).collection("stories")
            .whereField("chainId", isEqualTo: chainId)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(.success([]))
                    return
                }
                
                // Obtener todos los viewers únicos de todas las stories del chain
                var allViewers: [String: StoryViewer] = [:]
                let group = DispatchGroup()
                
                for document in documents {
                    let storyId = document.documentID
                    group.enter()
                    
                    self.db.collection("users").document(userId).collection("stories")
                        .document(storyId).collection("viewers")
                        .getDocuments { snapshot, error in
                            defer { group.leave() }
                            
                            if let error = error {
                                return
                            }
                            
                            guard let viewerDocs = snapshot?.documents else { return }
                            
                            for viewerDoc in viewerDocs {
                                let data = viewerDoc.data()
                                if let userId = data["userId"] as? String,
                                   let username = data["username"] as? String,
                                   let timestamp = data["timestamp"] as? Timestamp {
                                    
                                    // Si ya existe, mantener el timestamp más reciente
                                    if let existing = allViewers[userId] {
                                        if timestamp.dateValue() > existing.timestamp {
                                            allViewers[userId] = StoryViewer(
                                                id: userId,
                                                userId: userId,
                                                username: username,
                                                profileImagePath: data["profileImagePath"] as? String,
                                                timestamp: timestamp.dateValue()
                                            )
                                        }
                                    } else {
                                        allViewers[userId] = StoryViewer(
                                            id: userId,
                                            userId: userId,
                                            username: username,
                                            profileImagePath: data["profileImagePath"] as? String,
                                            timestamp: timestamp.dateValue()
                                        )
                                    }
                                }
                            }
                        }
                }
                
                group.notify(queue: .main) {
                    let viewers = Array(allViewers.values).sorted { $0.timestamp > $1.timestamp }
                    completion(.success(viewers))
                }
            }
    }
    
    /// Obtiene el último Story Chain del usuario
    func getLatestStoryChain(userId: String, completion: @escaping (Result<StoryChainInfo?, Error>) -> Void) {
        db.collection("users").document(userId).collection("stories")
            .whereField("chainId", isNotEqualTo: NSNull())
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let document = snapshot?.documents.first,
                      let chainId = document.data()["chainId"] as? String,
                      let chainTitle = document.data()["chainTitle"] as? String else {
                    completion(.success(nil))
                    return
                }
                
                // Obtener todas las stories del chain
                self.db.collection("users").document(userId).collection("stories")
                    .whereField("chainId", isEqualTo: chainId)
                    .order(by: "chainPosition", descending: false)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        
                        let stories = snapshot?.documents ?? []
                        let chainInfo = StoryChainInfo(
                            chainId: chainId,
                            chainTitle: chainTitle,
                            storyCount: stories.count,
                            createdAt: (document.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                        )
                        
                        completion(.success(chainInfo))
                    }
            }
    }
    
    // MARK: - 👥 Profile Visits (Optimizado con Resumen)
    /// Obtiene un resumen optimizado de visitas (5 más recientes + conteo total)
    func getProfileVisitsSummary(userId: String, completion: @escaping (Result<ProfileVisitsSummary, Error>) -> Void) {
        // Primero obtener el conteo total
        db.collection("users").document(userId).collection("visits")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let totalCount = snapshot?.documents.count ?? 0
                
                // Obtener solo las 5 más recientes
                self.db.collection("users").document(userId).collection("visits")
                    .order(by: "timestamp", descending: true)
                    .limit(to: 5)
                    .getDocuments { snapshot, error in
                        if let error = error {
                            completion(.failure(error))
                            return
                        }
                        
                        guard let documents = snapshot?.documents else {
                            completion(.success(ProfileVisitsSummary(recentVisits: [], totalCount: totalCount)))
                            return
                        }
                        
                        let visits = documents.compactMap { doc -> ProfileVisit? in
                            let data = doc.data()
                            guard let visitorId = data["visitorId"] as? String,
                                  let timestamp = data["timestamp"] as? Timestamp else {
                                return nil
                            }
                            
                            return ProfileVisit(
                                visitorId: visitorId,
                                timestamp: timestamp.dateValue()
                            )
                        }
                        
                        // Obtener información de usuarios solo para las 5 más recientes
                        let visitorIds = Array(Set(visits.map { $0.visitorId }))
                        if visitorIds.isEmpty {
                            completion(.success(ProfileVisitsSummary(recentVisits: [], totalCount: totalCount)))
                            return
                        }
                        
                        self.firestoreService.fetchUsers(userIds: visitorIds) { result in
                            switch result {
                            case .success(let users):
                                let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
                                let visitsWithUsers = visits.compactMap { visit -> ProfileVisit? in
                                    guard let user = userDict[visit.visitorId] else { return nil }
                                    return ProfileVisit(
                                        visitorId: visit.visitorId,
                                        timestamp: visit.timestamp,
                                        username: user.username,
                                        profileImagePath: user.profileImagePath
                                    )
                                }
                                let summary = ProfileVisitsSummary(
                                    recentVisits: visitsWithUsers,
                                    totalCount: totalCount
                                )
                                completion(.success(summary))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    }
            }
    }
    
    /// Obtiene las visitas recientes al perfil (método completo - usar solo si es necesario)
    func getRecentProfileVisits(userId: String, limit: Int = 10, completion: @escaping (Result<[ProfileVisit], Error>) -> Void) {
        db.collection("users").document(userId).collection("visits")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let visits = documents.compactMap { doc -> ProfileVisit? in
                    let data = doc.data()
                    guard let visitorId = data["visitorId"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp else {
                        return nil
                    }
                    
                    return ProfileVisit(
                        visitorId: visitorId,
                        timestamp: timestamp.dateValue()
                    )
                }
                
                // Obtener información de usuarios
                let visitorIds = Array(Set(visits.map { $0.visitorId }))
                if visitorIds.isEmpty {
                    completion(.success([]))
                    return
                }
                
                self.firestoreService.fetchUsers(userIds: visitorIds) { result in
                    switch result {
                    case .success(let users):
                        let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
                        let visitsWithUsers = visits.compactMap { visit -> ProfileVisit? in
                            guard let user = userDict[visit.visitorId] else { return nil }
                            return ProfileVisit(
                                visitorId: visit.visitorId,
                                timestamp: visit.timestamp,
                                username: user.username,
                                profileImagePath: user.profileImagePath
                            )
                        }
                        completion(.success(visitsWithUsers))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
    }
    
    // MARK: - 📱 Activity Summary
    /// Obtiene un resumen de actividad del usuario
    func getActivitySummary(userId: String, completion: @escaping (Result<NovaActivitySummary, Error>) -> Void) {
        let group = DispatchGroup()
        var recentVisits: [ProfileVisit] = []
        var latestChain: StoryChainInfo?
        var error: Error?
        
        // Obtener visitas recientes
        group.enter()
        getRecentProfileVisits(userId: userId, limit: 5) { result in
            switch result {
            case .success(let visits):
                recentVisits = visits
            case .failure(let err):
                error = err
            }
            group.leave()
        }
        
        // Obtener último chain
        group.enter()
        getLatestStoryChain(userId: userId) { result in
            switch result {
            case .success(let chain):
                latestChain = chain
            case .failure(let err):
                if error == nil { error = err }
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            if let error = error {
                completion(.failure(error))
                return
            }
            
            let summary = NovaActivitySummary(
                recentVisits: recentVisits,
                latestStoryChain: latestChain
            )
            completion(.success(summary))
        }
    }
    
    // MARK: - 🔍 Query Helper
    /// Detecta si una pregunta es sobre actividad de la app
    static func isActivityQuery(_ text: String) -> ActivityQueryType? {
        let lowercased = text.lowercased()
        
        // Story Chain queries
        if lowercased.contains("story chain") || lowercased.contains("cadena") || lowercased.contains("historia") {
            if lowercased.contains("viewer") || lowercased.contains("visto") || lowercased.contains("vista") || lowercased.contains("quién") || lowercased.contains("who") {
                return .storyChainViewers
            }
            if lowercased.contains("último") || lowercased.contains("last") || lowercased.contains("reciente") {
                return .latestStoryChain
            }
        }
        
        // Profile visits queries
        if lowercased.contains("visita") || lowercased.contains("visit") || lowercased.contains("visitante") {
            if lowercased.contains("perfil") || lowercased.contains("profile") {
                return .profileVisits
            }
        }
        
        // General activity
        if lowercased.contains("actividad") || lowercased.contains("activity") || lowercased.contains("qué pasa") || lowercased.contains("what's happening") {
            return .activitySummary
        }
        
        // Weekly summary queries
        if lowercased.contains("resumen semanal") || lowercased.contains("weekly summary") || lowercased.contains("resum setmanal") ||
           lowercased.contains("esta semana") || lowercased.contains("this week") || lowercased.contains("aquesta setmana") {
            return .weeklySummary
        }
        
        return nil
    }
    
    // MARK: - 📊 Resumen Semanal
    /// Genera un resumen semanal comparando esta semana vs la anterior
    func getWeeklySummary(userId: String, completion: @escaping (Result<WeeklyActivitySummary, Error>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        
        // Calcular fechas
        guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
              let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek),
              let endOfLastWeek = calendar.date(byAdding: .day, value: 6, to: startOfLastWeek) else {
            completion(.failure(NSError(domain: "WeeklySummary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error calculating dates"])))
            return
        }
        
        let group = DispatchGroup()
        var thisWeekMoments: [Moment] = []
        var lastWeekMoments: [Moment] = []
        var thisWeekVisits: Int = 0
        var lastWeekVisits: Int = 0
        var thisWeekStoryViews: Int = 0
        var lastWeekStoryViews: Int = 0
        var error: Error?
        
        // Obtener momentos de esta semana
        group.enter()
        firestoreService.fetchMoments(for: userId) { result in
            switch result {
            case .success(let moments):
                thisWeekMoments = moments.filter { $0.timestamp >= startOfThisWeek }
                lastWeekMoments = moments.filter { $0.timestamp >= startOfLastWeek && $0.timestamp <= endOfLastWeek }
            case .failure(let err):
                error = err
            }
            group.leave()
        }
        
        // Obtener visitas de esta semana
        group.enter()
        db.collection("users").document(userId).collection("visits")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfThisWeek))
            .getDocuments { snapshot, _ in
                thisWeekVisits = snapshot?.documents.count ?? 0
                group.leave()
            }
        
        // Obtener visitas de la semana pasada
        group.enter()
        db.collection("users").document(userId).collection("visits")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfLastWeek))
            .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: endOfLastWeek))
            .getDocuments { snapshot, _ in
                lastWeekVisits = snapshot?.documents.count ?? 0
                group.leave()
            }
        
        // Obtener views de stories de esta semana
        group.enter()
        db.collection("users").document(userId).collection("stories")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfThisWeek))
            .getDocuments { [weak self] snapshot, _ in
                guard let self = self, let documents = snapshot?.documents else {
                    group.leave()
                    return
                }
                
                let storyGroup = DispatchGroup()
                var totalViews = 0
                
                for doc in documents {
                    storyGroup.enter()
                    self.db.collection("users").document(userId).collection("stories")
                        .document(doc.documentID).collection("viewers")
                        .getDocuments { snapshot, _ in
                            totalViews += snapshot?.documents.count ?? 0
                            storyGroup.leave()
                        }
                }
                
                storyGroup.notify(queue: .main) {
                    thisWeekStoryViews = totalViews
                    group.leave()
                }
            }
        
        // Obtener views de stories de la semana pasada
        group.enter()
        db.collection("users").document(userId).collection("stories")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: startOfLastWeek))
            .whereField("timestamp", isLessThanOrEqualTo: Timestamp(date: endOfLastWeek))
            .getDocuments { [weak self] snapshot, _ in
                guard let self = self, let documents = snapshot?.documents else {
                    group.leave()
                    return
                }
                
                let storyGroup = DispatchGroup()
                var totalViews = 0
                
                for doc in documents {
                    storyGroup.enter()
                    self.db.collection("users").document(userId).collection("stories")
                        .document(doc.documentID).collection("viewers")
                        .getDocuments { snapshot, _ in
                            totalViews += snapshot?.documents.count ?? 0
                            storyGroup.leave()
                        }
                }
                
                storyGroup.notify(queue: .main) {
                    lastWeekStoryViews = totalViews
                    group.leave()
                }
            }
        
        group.notify(queue: .main) {
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Calcular engagement de momentos
            let thisWeekEngagement = self.calculateMomentsEngagement(thisWeekMoments)
            let lastWeekEngagement = self.calculateMomentsEngagement(lastWeekMoments)
            
            let summary = WeeklyActivitySummary(
                thisWeek: WeekData(
                    momentsCount: thisWeekMoments.count,
                    momentsEngagement: thisWeekEngagement,
                    profileVisits: thisWeekVisits,
                    storyViews: thisWeekStoryViews
                ),
                lastWeek: WeekData(
                    momentsCount: lastWeekMoments.count,
                    momentsEngagement: lastWeekEngagement,
                    profileVisits: lastWeekVisits,
                    storyViews: lastWeekStoryViews
                )
            )
            
            completion(.success(summary))
        }
    }
    
    private func calculateMomentsEngagement(_ moments: [Moment]) -> MomentsEngagement {
        var totalReactions = 0
        var totalComments = 0
        var totalReach = 0 // Estimado basado en reacciones + comentarios
        
        for moment in moments {
            // Contar reacciones
            for (_, userIds) in moment.reactions {
                totalReactions += userIds.count
            }
            totalComments += moment.commentCount
            totalReach += moment.reactions.values.reduce(0) { $0 + $1.count } + moment.commentCount
        }
        
        return MomentsEngagement(
            totalReactions: totalReactions,
            totalComments: totalComments,
            estimatedReach: totalReach
        )
    }
    
    // MARK: - 🔧 Helper para cálculo de porcentajes
    func calculatePercentageChange(_ current: Int, _ previous: Int) -> Int {
        guard previous > 0 else { return current > 0 ? 100 : 0 }
        let change = Double(current - previous) / Double(previous) * 100
        return Int(round(change))
    }
    
    // MARK: - 🌊 Echo Sparks
    /// Activa un "Spark" de Nova para sugerir un Echo proactivamente
    func triggerEchoSpark(echoId: String, userId: String) {
        print("✨ Nova Activity: Triggering Echo Spark for \(userId) on echo \(echoId)")
        
        let insight = ProactiveInsight(
            type: .echoAvailable,
            severity: .high,
            metric: "echo",
            change: 0,
            suggestion: "Hay personas cerca con momentos similares. ¡Creen un Echo!"
        )
        
        NotificationCenter.default.post(
            name: NSNotification.Name("NovaEchoSparkTriggered"),
            object: nil,
            userInfo: ["echoId": echoId, "userId": userId, "insight": insight.rawData]
        )
    }
}

// MARK: - 📊 Modelos de Datos
// StoryViewer está definido en StoryModels.swift

// MARK: - Proactive Insights
enum InsightType {
    case profileVisitsDeclining
    case engagementDeclining
    case lowActivity
    case storyViewsLow
    case positiveTrend
    case echoAvailable
}

enum InsightSeverity {
    case low
    case medium
    case high
}

struct ProactiveInsight {
    let type: InsightType
    let severity: InsightSeverity
    let metric: String
    let change: Int
    let suggestion: String?
    
    var rawData: [String: Any] {
        var data: [String: Any] = [
            "type": typeString,
            "severity": severityString,
            "metric": metric,
            "change": change
        ]
        if let suggestion = suggestion {
            data["suggestion"] = suggestion
        }
        return data
    }
    
    private var typeString: String {
        switch type {
        case .profileVisitsDeclining: return "profileVisitsDeclining"
        case .engagementDeclining: return "engagementDeclining"
        case .lowActivity: return "lowActivity"
        case .storyViewsLow: return "storyViewsLow"
        case .positiveTrend: return "positiveTrend"
        case .echoAvailable: return "echoAvailable"
        }
    }
    
    private var severityString: String {
        switch severity {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
}

struct StoryChainInfo {
    let chainId: String
    let chainTitle: String
    let storyCount: Int
    let createdAt: Date
}

struct ProfileVisit: Identifiable {
    let id: String
    let visitorId: String
    let timestamp: Date
    let username: String?
    let profileImagePath: String?
    
    init(visitorId: String, timestamp: Date, username: String? = nil, profileImagePath: String? = nil) {
        self.id = visitorId
        self.visitorId = visitorId
        self.timestamp = timestamp
        self.username = username
        self.profileImagePath = profileImagePath
    }
}

struct NovaActivitySummary {
    let recentVisits: [ProfileVisit]
    let latestStoryChain: StoryChainInfo?
    
    // 🔥 NUEVO: Datos crudos para que Nova redacte según su personalidad
    var rawData: [String: Any] {
        var data: [String: Any] = [:]
        
        if let chain = latestStoryChain {
            data["latestStoryChain"] = [
                "title": chain.chainTitle,
                "storyCount": chain.storyCount,
                "createdAt": ISO8601DateFormatter().string(from: chain.createdAt)
            ]
        }
        
        data["recentVisits"] = recentVisits.prefix(5).map { visit in
            [
                "username": visit.username ?? "Usuario",
                "timestamp": ISO8601DateFormatter().string(from: visit.timestamp),
                "timeAgo": timeAgoString(from: visit.timestamp, lang: NovaLanguageService.getPreferredLanguage() ?? .es)
            ]
        }
        data["totalVisits"] = recentVisits.count
        
        return data
    }
    
    var formattedSummary: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        var summary = ""
        
        switch lang {
        case .es:
            if let chain = latestStoryChain {
                summary += "📱 Último Story Chain: \"\(chain.chainTitle)\" (\(chain.storyCount) partes)\n"
            }
            
            if !recentVisits.isEmpty {
                summary += "👥 Visitas recientes al perfil:\n"
                for (index, visit) in recentVisits.prefix(5).enumerated() {
                    let timeAgo = timeAgoString(from: visit.timestamp, lang: .es)
                    summary += "\(index + 1). \(visit.username ?? "Usuario") - \(timeAgo)\n"
                }
            } else {
                summary += "👥 No hay visitas recientes al perfil.\n"
            }
            
        case .en:
            if let chain = latestStoryChain {
                summary += "📱 Latest Story Chain: \"\(chain.chainTitle)\" (\(chain.storyCount) parts)\n"
            }
            
            if !recentVisits.isEmpty {
                summary += "👥 Recent profile visits:\n"
                for (index, visit) in recentVisits.prefix(5).enumerated() {
                    let timeAgo = timeAgoString(from: visit.timestamp, lang: .en)
                    summary += "\(index + 1). \(visit.username ?? "User") - \(timeAgo)\n"
                }
            } else {
                summary += "👥 No recent profile visits.\n"
            }
            
        case .ca:
            if let chain = latestStoryChain {
                summary += "📱 Última cadena d'històries: \"\(chain.chainTitle)\" (\(chain.storyCount) parts)\n"
            }
            
            if !recentVisits.isEmpty {
                summary += "👥 Visites recents al perfil:\n"
                for (index, visit) in recentVisits.prefix(5).enumerated() {
                    let timeAgo = timeAgoString(from: visit.timestamp, lang: .ca)
                    summary += "\(index + 1). \(visit.username ?? "Usuari") - \(timeAgo)\n"
                }
            } else {
                summary += "👥 No hi ha visites recents al perfil.\n"
            }
        }
        
        return summary
    }
    
    private func timeAgoString(from date: Date, lang: NovaLanguage) -> String {
        let interval = Date().timeIntervalSince(date)
        
        switch lang {
        case .es:
            if interval < 60 {
                return "hace un momento"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "hace \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "hace \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "hace \(days)d"
            }
        case .en:
            if interval < 60 {
                return "just now"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "\(minutes) min ago"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            } else {
                let days = Int(interval / 86400)
                return "\(days)d ago"
            }
        case .ca:
            if interval < 60 {
                return "fa un moment"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "fa \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "fa \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "fa \(days)d"
            }
        }
    }
}

enum ActivityQueryType {
    case storyChainViewers
    case latestStoryChain
    case profileVisits
    case activitySummary
    case weeklySummary
}

// MARK: - 📊 Estructuras de Resumen Optimizadas
struct StoryChainViewersSummary {
    let recentViewers: [StoryViewer] // Solo 5 más recientes
    let totalCount: Int // Conteo total
    
    var formattedSummary: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        switch lang {
        case .es:
            if totalCount == 0 {
                return "Tu Story Chain aún no tiene viewers."
            }
            var summary = "Tu Story Chain tiene \(totalCount) viewer\(totalCount == 1 ? "" : "s") en total.\n\n"
            if !recentViewers.isEmpty {
                summary += "Los 5 más recientes:\n"
                for (index, viewer) in recentViewers.enumerated() {
                    summary += "\(index + 1). \(viewer.username)\n"
                }
                if totalCount > 5 {
                    summary += "\n... y \(totalCount - 5) más"
                }
            }
            return summary
        case .en:
            if totalCount == 0 {
                return "Your Story Chain doesn't have viewers yet."
            }
            var summary = "Your Story Chain has \(totalCount) viewer\(totalCount == 1 ? "" : "s") in total.\n\n"
            if !recentViewers.isEmpty {
                summary += "The 5 most recent:\n"
                for (index, viewer) in recentViewers.enumerated() {
                    summary += "\(index + 1). \(viewer.username)\n"
                }
                if totalCount > 5 {
                    summary += "\n... and \(totalCount - 5) more"
                }
            }
            return summary
        case .ca:
            if totalCount == 0 {
                return "La teva cadena d'històries encara no té viewers."
            }
            var summary = "La teva cadena d'històries té \(totalCount) viewer\(totalCount == 1 ? "" : "s") en total.\n\n"
            if !recentViewers.isEmpty {
                summary += "Els 5 més recents:\n"
                for (index, viewer) in recentViewers.enumerated() {
                    summary += "\(index + 1). \(viewer.username)\n"
                }
                if totalCount > 5 {
                    summary += "\n... i \(totalCount - 5) més"
                }
            }
            return summary
        }
    }
}

struct ProfileVisitsSummary {
    let recentVisits: [ProfileVisit] // Solo 5 más recientes
    let totalCount: Int // Conteo total
    
    var formattedSummary: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        switch lang {
        case .es:
            if totalCount == 0 {
                return "No hay visitas a tu perfil aún."
            }
            var summary = "Tu perfil tiene \(totalCount) visita\(totalCount == 1 ? "" : "s") en total.\n\n"
            if !recentVisits.isEmpty {
                summary += "Las 5 más recientes:\n"
                for (index, visit) in recentVisits.enumerated() {
                    let timeAgo = timeAgoString(from: visit.timestamp, lang: .es)
                    summary += "\(index + 1). \(visit.username ?? "Usuario") - \(timeAgo)\n"
                }
                if totalCount > 5 {
                    summary += "\n... y \(totalCount - 5) más"
                }
            }
            return summary
        case .en:
            if totalCount == 0 {
                return "No visits to your profile yet."
            }
            var summary = "Your profile has \(totalCount) visit\(totalCount == 1 ? "" : "s") in total.\n\n"
            if !recentVisits.isEmpty {
                summary += "The 5 most recent:\n"
                for (index, visit) in recentVisits.enumerated() {
                    let timeAgo = timeAgoString(from: visit.timestamp, lang: .en)
                    summary += "\(index + 1). \(visit.username ?? "User") - \(timeAgo)\n"
                }
                if totalCount > 5 {
                    summary += "\n... and \(totalCount - 5) more"
                }
            }
            return summary
        case .ca:
            if totalCount == 0 {
                return "No hi ha visites al teu perfil encara."
            }
            var summary = "El teu perfil té \(totalCount) visita\(totalCount == 1 ? "" : "s") en total.\n\n"
            if !recentVisits.isEmpty {
                summary += "Les 5 més recents:\n"
                for (index, visit) in recentVisits.enumerated() {
                    let timeAgo = timeAgoString(from: visit.timestamp, lang: .ca)
                    summary += "\(index + 1). \(visit.username ?? "Usuari") - \(timeAgo)\n"
                }
                if totalCount > 5 {
                    summary += "\n... i \(totalCount - 5) més"
                }
            }
            return summary
        }
    }
    
    private func timeAgoString(from date: Date, lang: NovaLanguage) -> String {
        let interval = Date().timeIntervalSince(date)
        switch lang {
        case .es:
            if interval < 60 { return "hace un momento" }
            else if interval < 3600 { return "hace \(Int(interval / 60)) min" }
            else if interval < 86400 { return "hace \(Int(interval / 3600))h" }
            else { return "hace \(Int(interval / 86400))d" }
        case .en:
            if interval < 60 { return "just now" }
            else if interval < 3600 { return "\(Int(interval / 60)) min ago" }
            else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
            else { return "\(Int(interval / 86400))d ago" }
        case .ca:
            if interval < 60 { return "fa un moment" }
            else if interval < 3600 { return "fa \(Int(interval / 60)) min" }
            else if interval < 86400 { return "fa \(Int(interval / 3600))h" }
            else { return "fa \(Int(interval / 86400))d" }
        }
    }
}

// MARK: - 📊 Resumen Semanal
struct WeeklyActivitySummary {
    let thisWeek: WeekData
    let lastWeek: WeekData
    
    // 🔥 NUEVO: Datos crudos en formato JSON para que Nova redacte según su personalidad
    var rawData: [String: Any] {
        let momentsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsCount, lastWeek.momentsCount)
        let reachChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsEngagement.estimatedReach, lastWeek.momentsEngagement.estimatedReach)
        let visitsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.profileVisits, lastWeek.profileVisits)
        let storyViewsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.storyViews, lastWeek.storyViews)
        
        return [
            "moments": [
                "thisWeek": thisWeek.momentsCount,
                "lastWeek": lastWeek.momentsCount,
                "change": momentsChange,
                "trend": momentsChange > 0 ? "up" : momentsChange < 0 ? "down" : "stable"
            ],
            "engagement": [
                "thisWeek": [
                    "reactions": thisWeek.momentsEngagement.totalReactions,
                    "comments": thisWeek.momentsEngagement.totalComments,
                    "estimatedReach": thisWeek.momentsEngagement.estimatedReach
                ],
                "lastWeek": [
                    "reactions": lastWeek.momentsEngagement.totalReactions,
                    "comments": lastWeek.momentsEngagement.totalComments,
                    "estimatedReach": lastWeek.momentsEngagement.estimatedReach
                ],
                "reachChange": reachChange,
                "trend": reachChange > 0 ? "up" : reachChange < 0 ? "down" : "stable"
            ],
            "profileVisits": [
                "thisWeek": thisWeek.profileVisits,
                "lastWeek": lastWeek.profileVisits,
                "change": visitsChange,
                "trend": visitsChange > 0 ? "up" : visitsChange < 0 ? "down" : "stable"
            ],
            "storyViews": [
                "thisWeek": thisWeek.storyViews,
                "lastWeek": lastWeek.storyViews,
                "change": storyViewsChange,
                "trend": storyViewsChange > 0 ? "up" : storyViewsChange < 0 ? "down" : "stable"
            ]
        ]
    }
    
    // 🔥 NUEVO: Detectar problemas y generar consejos proactivos (multilingüe)
    var proactiveInsights: [ProactiveInsight] {
        var insights: [ProactiveInsight] = []
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        let visitsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.profileVisits, lastWeek.profileVisits)
        let reachChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsEngagement.estimatedReach, lastWeek.momentsEngagement.estimatedReach)
        let momentsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsCount, lastWeek.momentsCount)
        let storyViewsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.storyViews, lastWeek.storyViews)
        
        // Helper para obtener sugerencias multilingües
        func getSuggestion(for type: InsightType) -> String? {
            switch (type, lang) {
            case (.profileVisitsDeclining, .es):
                return "subir un nuevo Story Chain para animar a la gente"
            case (.profileVisitsDeclining, .en):
                return "upload a new Story Chain to engage people"
            case (.profileVisitsDeclining, .ca):
                return "pujar una nova Story Chain per animar la gent"
                
            case (.engagementDeclining, .es):
                return "publicar contenido más interactivo o responder a comentarios"
            case (.engagementDeclining, .en):
                return "post more interactive content or respond to comments"
            case (.engagementDeclining, .ca):
                return "publicar contingut més interactiu o respondre comentaris"
                
            case (.lowActivity, .es):
                return "publicar más momentos para mantener el engagement"
            case (.lowActivity, .en):
                return "post more moments to maintain engagement"
            case (.lowActivity, .ca):
                return "publicar més moments per mantenir l'engagement"
                
            case (.storyViewsLow, .es):
                return "crear stories más atractivas o en mejores horarios"
            case (.storyViewsLow, .en):
                return "create more attractive stories or post at better times"
            case (.storyViewsLow, .ca):
                return "crear històries més atractives o en millors horaris"
                
            default:
                return nil
            }
        }
        
        // Detectar visitas bajando significativamente
        if visitsChange < -15 {
            insights.append(ProactiveInsight(
                type: .profileVisitsDeclining,
                severity: visitsChange < -30 ? .high : .medium,
                metric: "profileVisits",
                change: visitsChange,
                suggestion: getSuggestion(for: .profileVisitsDeclining)
            ))
        }
        
        // Detectar engagement bajando
        if reachChange < -20 {
            insights.append(ProactiveInsight(
                type: .engagementDeclining,
                severity: reachChange < -40 ? .high : .medium,
                metric: "engagement",
                change: reachChange,
                suggestion: getSuggestion(for: .engagementDeclining)
            ))
        }
        
        // Detectar menos momentos publicados
        if momentsChange < -30 && thisWeek.momentsCount < 3 {
            insights.append(ProactiveInsight(
                type: .lowActivity,
                severity: .medium,
                metric: "moments",
                change: momentsChange,
                suggestion: getSuggestion(for: .lowActivity)
            ))
        }
        
        // Detectar stories con pocas views
        if storyViewsChange < -25 && thisWeek.storyViews < 10 {
            insights.append(ProactiveInsight(
                type: .storyViewsLow,
                severity: .medium,
                metric: "storyViews",
                change: storyViewsChange,
                suggestion: getSuggestion(for: .storyViewsLow)
            ))
        }
        
        // Detectar tendencias positivas para celebrar
        if visitsChange > 20 {
            insights.append(ProactiveInsight(
                type: .positiveTrend,
                severity: .low,
                metric: "profileVisits",
                change: visitsChange,
                suggestion: nil // Solo celebrar, sin sugerencia
            ))
        }
        
        return insights
    }
    
    var formattedSummary: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        
        switch lang {
        case .es:
            var summary = "📊 **Resumen Semanal de Actividad**\n\n"
            
            // Momentos
            let momentsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsCount, lastWeek.momentsCount)
            summary += "📸 **Momentos:**\n"
            summary += "• Esta semana: \(thisWeek.momentsCount) momentos\n"
            summary += "• Semana pasada: \(lastWeek.momentsCount) momentos\n"
            if momentsChange != 0 {
                summary += "• \(momentsChange > 0 ? "↑" : "↓") \(abs(momentsChange))% vs semana anterior\n"
            }
            summary += "\n"
            
            // Engagement de momentos
            let reachChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsEngagement.estimatedReach, lastWeek.momentsEngagement.estimatedReach)
            summary += "💬 **Engagement de Momentos:**\n"
            summary += "• Esta semana: \(thisWeek.momentsEngagement.estimatedReach) personas alcanzadas\n"
            summary += "• Semana pasada: \(lastWeek.momentsEngagement.estimatedReach) personas alcanzadas\n"
            if reachChange != 0 {
                summary += "• \(reachChange > 0 ? "↑" : "↓") \(abs(reachChange))% vs semana anterior\n"
            }
            summary += "• Reacciones esta semana: \(thisWeek.momentsEngagement.totalReactions)\n"
            summary += "• Comentarios esta semana: \(thisWeek.momentsEngagement.totalComments)\n"
            summary += "\n"
            
            // Visitas al perfil
            let visitsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.profileVisits, lastWeek.profileVisits)
            summary += "👥 **Visitas al Perfil:**\n"
            summary += "• Esta semana: \(thisWeek.profileVisits) visitas\n"
            summary += "• Semana pasada: \(lastWeek.profileVisits) visitas\n"
            if visitsChange != 0 {
                summary += "• \(visitsChange > 0 ? "↑" : "↓") \(abs(visitsChange))% vs semana anterior\n"
            }
            summary += "\n"
            
            // Views de stories
            let storyViewsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.storyViews, lastWeek.storyViews)
            summary += "📱 **Views de Stories:**\n"
            summary += "• Esta semana: \(thisWeek.storyViews) views\n"
            summary += "• Semana pasada: \(lastWeek.storyViews) views\n"
            if storyViewsChange != 0 {
                summary += "• \(storyViewsChange > 0 ? "↑" : "↓") \(abs(storyViewsChange))% vs semana anterior\n"
            }
            
            return summary
            
        case .en:
            var summary = "📊 **Weekly Activity Summary**\n\n"
            
            // Moments
            let momentsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsCount, lastWeek.momentsCount)
            summary += "📸 **Moments:**\n"
            summary += "• This week: \(thisWeek.momentsCount) moments\n"
            summary += "• Last week: \(lastWeek.momentsCount) moments\n"
            if momentsChange != 0 {
                summary += "• \(momentsChange > 0 ? "↑" : "↓") \(abs(momentsChange))% vs last week\n"
            }
            summary += "\n"
            
            // Moments engagement
            let reachChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsEngagement.estimatedReach, lastWeek.momentsEngagement.estimatedReach)
            summary += "💬 **Moments Engagement:**\n"
            summary += "• This week: \(thisWeek.momentsEngagement.estimatedReach) people reached\n"
            summary += "• Last week: \(lastWeek.momentsEngagement.estimatedReach) people reached\n"
            if reachChange != 0 {
                summary += "• \(reachChange > 0 ? "↑" : "↓") \(abs(reachChange))% vs last week\n"
            }
            summary += "• Reactions this week: \(thisWeek.momentsEngagement.totalReactions)\n"
            summary += "• Comments this week: \(thisWeek.momentsEngagement.totalComments)\n"
            summary += "\n"
            
            // Profile visits
            let visitsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.profileVisits, lastWeek.profileVisits)
            summary += "👥 **Profile Visits:**\n"
            summary += "• This week: \(thisWeek.profileVisits) visits\n"
            summary += "• Last week: \(lastWeek.profileVisits) visits\n"
            if visitsChange != 0 {
                summary += "• \(visitsChange > 0 ? "↑" : "↓") \(abs(visitsChange))% vs last week\n"
            }
            summary += "\n"
            
            // Story views
            let storyViewsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.storyViews, lastWeek.storyViews)
            summary += "📱 **Story Views:**\n"
            summary += "• This week: \(thisWeek.storyViews) views\n"
            summary += "• Last week: \(lastWeek.storyViews) views\n"
            if storyViewsChange != 0 {
                summary += "• \(storyViewsChange > 0 ? "↑" : "↓") \(abs(storyViewsChange))% vs last week\n"
            }
            
            return summary
            
        case .ca:
            var summary = "📊 **Resum Setmanal d'Activitat**\n\n"
            
            // Moments
            let momentsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsCount, lastWeek.momentsCount)
            summary += "📸 **Moments:**\n"
            summary += "• Aquesta setmana: \(thisWeek.momentsCount) moments\n"
            summary += "• Setmana passada: \(lastWeek.momentsCount) moments\n"
            if momentsChange != 0 {
                summary += "• \(momentsChange > 0 ? "↑" : "↓") \(abs(momentsChange))% vs setmana anterior\n"
            }
            summary += "\n"
            
            // Engagement de moments
            let reachChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.momentsEngagement.estimatedReach, lastWeek.momentsEngagement.estimatedReach)
            summary += "💬 **Engagement de Moments:**\n"
            summary += "• Aquesta setmana: \(thisWeek.momentsEngagement.estimatedReach) persones assolides\n"
            summary += "• Setmana passada: \(lastWeek.momentsEngagement.estimatedReach) persones assolides\n"
            if reachChange != 0 {
                summary += "• \(reachChange > 0 ? "↑" : "↓") \(abs(reachChange))% vs setmana anterior\n"
            }
            summary += "• Reaccions aquesta setmana: \(thisWeek.momentsEngagement.totalReactions)\n"
            summary += "• Comentaris aquesta setmana: \(thisWeek.momentsEngagement.totalComments)\n"
            summary += "\n"
            
            // Visites al perfil
            let visitsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.profileVisits, lastWeek.profileVisits)
            summary += "👥 **Visites al Perfil:**\n"
            summary += "• Aquesta setmana: \(thisWeek.profileVisits) visites\n"
            summary += "• Setmana passada: \(lastWeek.profileVisits) visites\n"
            if visitsChange != 0 {
                summary += "• \(visitsChange > 0 ? "↑" : "↓") \(abs(visitsChange))% vs setmana anterior\n"
            }
            summary += "\n"
            
            // Views de stories
            let storyViewsChange = NovaActivityService.shared.calculatePercentageChange(thisWeek.storyViews, lastWeek.storyViews)
            summary += "📱 **Views d'Històries:**\n"
            summary += "• Aquesta setmana: \(thisWeek.storyViews) views\n"
            summary += "• Setmana passada: \(lastWeek.storyViews) views\n"
            if storyViewsChange != 0 {
                summary += "• \(storyViewsChange > 0 ? "↑" : "↓") \(abs(storyViewsChange))% vs setmana anterior\n"
            }
            
            return summary
        }
    }
    
    func calculatePercentageChange(_ current: Int, _ previous: Int) -> Int {
        guard previous > 0 else { return current > 0 ? 100 : 0 }
        let change = Double(current - previous) / Double(previous) * 100
        return Int(round(change))
    }
}

struct WeekData {
    let momentsCount: Int
    let momentsEngagement: MomentsEngagement
    let profileVisits: Int
    let storyViews: Int
}

struct MomentsEngagement {
    let totalReactions: Int
    let totalComments: Int
    let estimatedReach: Int
}

