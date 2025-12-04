// ================== TrendingService.swift ==================

import Foundation

// MARK: - 🔥 Servicio de Trending con respeto a privacidad
class TrendingService: ObservableObject {
    static let shared = TrendingService()
    private let db = Firestore.firestore()
    private let privacyService = PrivacyService()
    
    private init() {}
    
    // MARK: - 📊 Modelos de datos
    struct TrendingHashtag: Identifiable, Codable {
        let id: String  // ✅ CAMBIO: String en lugar de UUID()
        let hashtag: String
        let count: Int
        let growth: Double // % de crecimiento en 24h
        let category: HashtagCategory
        
        // ✅ NUEVO: Inicializador personalizado
        init(hashtag: String, count: Int, growth: Double, category: HashtagCategory) {
            self.id = hashtag + "_\(count)"  // ID único basado en hashtag + count
            self.hashtag = hashtag
            self.count = count
            self.growth = growth
            self.category = category
        }
        
        enum HashtagCategory: String, CaseIterable, Codable {  // ✅ AGREGADO: Codable
            case general = "general"
            case food = "food"
            case travel = "travel"
            case fashion = "fashion"
            case tech = "tech"
            case art = "art"
            case lifestyle = "lifestyle"
            
            var emoji: String {
                switch self {
                case .general: return "🔥"
                case .food: return "🍕"
                case .travel: return "✈️"
                case .fashion: return "👗"
                case .tech: return "💻"
                case .art: return "🎨"
                case .lifestyle: return "🌟"
                }
            }
        }
    }
    
    struct TrendingLocation: Identifiable, Codable {
        let id: String  // ✅ CAMBIO: String en lugar de UUID()
        let locationName: String
        let momentCount: Int
        let uniqueUsers: Int
        let growth: Double
        let coordinate: LocationCoordinate?
        
        // ✅ NUEVO: Inicializador personalizado
        init(locationName: String, momentCount: Int, uniqueUsers: Int, growth: Double, coordinate: LocationCoordinate? = nil) {
            self.id = locationName + "_\(momentCount)"  // ID único basado en ubicación + count
            self.locationName = locationName
            self.momentCount = momentCount
            self.uniqueUsers = uniqueUsers
            self.growth = growth
            self.coordinate = coordinate
        }
        
        struct LocationCoordinate: Codable {
            let latitude: Double
            let longitude: Double
        }
    }
    
    struct TrendingMoment: Identifiable, Codable {
        let moment: Moment
        let trendingScore: Double
        let engagementRate: Double
        let timeToTrend: TimeInterval // Cuánto tardó en volverse trending
        
        var id: String { moment.id ?? UUID().uuidString }
    }
    
    // MARK: - 🔥 TRENDING HASHTAGS
    func fetchTrendingHashtags(limit: Int = 20, completion: @escaping (Result<[TrendingHashtag], Error>) -> Void) {

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        
        // Buscar momentos públicos de las últimas 24h
        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("timestamp", isGreaterThan: Timestamp(date: yesterday))
            .limit(to: 500) // Muestra grande para análisis
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                // Extraer y contar hashtags
                var hashtagCounts: [String: Int] = [:]
                
                for doc in documents {
                    if let content = doc.data()["content"] as? String {
                        let hashtags = self.extractHashtags(from: content)
                        for hashtag in hashtags {
                            hashtagCounts[hashtag, default: 0] += 1
                        }
                    }
                }
                
                // Crear trending hashtags con categorización
                let trendingHashtags = hashtagCounts
                    .filter { $0.value >= 3 } // Mínimo 3 usos
                    .sorted { $0.value > $1.value }
                    .prefix(limit)
                    .map { hashtag, count in
                        TrendingHashtag(
                            hashtag: hashtag,
                            count: count,
                            growth: Double.random(in: 15...150), // TODO: Calcular crecimiento real
                            category: self.categorizeHashtag(hashtag)
                        )
                    }
                completion(.success(Array(trendingHashtags)))
            }
    }
    
    // MARK: - 📍 TRENDING LOCATIONS
    func fetchTrendingLocations(limit: Int = 15, completion: @escaping (Result<[TrendingLocation], Error>) -> Void) {

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        
        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("timestamp", isGreaterThan: Timestamp(date: yesterday))
            .whereField("location", isNotEqualTo: "")
            .limit(to: 300)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                // Contar momentos por ubicación
                var locationData: [String: (count: Int, users: Set<String>)] = [:]
                
                for doc in documents {
                    let data = doc.data()
                    if let location = data["location"] as? String,
                       let authorId = data["authorId"] as? String,
                       !location.isEmpty {
                        
                        if locationData[location] == nil {
                            locationData[location] = (count: 0, users: Set<String>())
                        }
                        locationData[location]?.count += 1
                        locationData[location]?.users.insert(authorId)
                    }
                }
                
                // Crear trending locations
                let trendingLocations = locationData
                    .filter { $0.value.count >= 2 && $0.value.users.count >= 2 } // Mínimo 2 posts de 2 usuarios diferentes
                    .sorted { $0.value.count > $1.value.count }
                    .prefix(limit)
                    .map { location, data in
                        TrendingLocation(
                            locationName: location,
                            momentCount: data.count,
                            uniqueUsers: data.users.count,
                            growth: Double.random(in: 20...200), // TODO: Calcular crecimiento real
                            coordinate: nil // TODO: Geocoding si es necesario
                        )
                    }
                completion(.success(Array(trendingLocations)))
            }
    }
    
    // MARK: - 🚀 TRENDING MOMENTS (Algoritmo inteligente)
    func fetchTrendingMoments(for userId: String, limit: Int = 20, completion: @escaping (Result<[TrendingMoment], Error>) -> Void) {
        
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        
        // Buscar momentos públicos recientes
        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("timestamp", isGreaterThan: Timestamp(date: twoDaysAgo))
            .limit(to: 200)
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
                
                let group = DispatchGroup()
                var candidateMoments: [Moment] = []
                
                // Convertir documentos a momentos
                for doc in documents {
                    do {
                        var moment = try doc.data(as: Moment.self)
                        moment.id = doc.documentID
                        
                        // Excluir momentos del propio usuario
                        guard moment.authorId != userId else { continue }
                        
                        candidateMoments.append(moment)
                    } catch {
                    }
                }
                
                
                // Calcular trending score para cada momento
                self.calculateTrendingScores(for: candidateMoments, viewerId: userId) { trendingMoments in
                    let sortedTrending = trendingMoments
                        .sorted { $0.trendingScore > $1.trendingScore }
                        .prefix(limit)
                    
                    completion(.success(Array(sortedTrending)))
                }
            }
    }
    
    // MARK: - 🧮 ALGORITMO DE TRENDING SCORE
    private func calculateTrendingScores(for moments: [Moment], viewerId: String, completion: @escaping ([TrendingMoment]) -> Void) {
        let group = DispatchGroup()
        var trendingMoments: [TrendingMoment] = []
        let syncQueue = DispatchQueue(label: "trending.score.calculation")
        
        for moment in moments {
            group.enter()
            
            calculateMomentTrendingScore(moment: moment, viewerId: viewerId) { trendingScore, engagementRate in
                let trendingMoment = TrendingMoment(
                    moment: moment,
                    trendingScore: trendingScore,
                    engagementRate: engagementRate,
                    timeToTrend: Date().timeIntervalSince(moment.timestamp)
                )
                
                syncQueue.async {
                    trendingMoments.append(trendingMoment)
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: DispatchQueue.main) {
            completion(trendingMoments)
        }
    }
    
    private func calculateMomentTrendingScore(moment: Moment, viewerId: String, completion: @escaping (Double, Double) -> Void) {
        guard let momentId = moment.id else {
            completion(0, 0)
            return
        }
        
        let group = DispatchGroup()
        var reactionCount = 0
        var commentCount = 0
        
        // Contar reacciones
        group.enter()
        db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("reactions")
            .getDocuments { snapshot, _ in
                reactionCount = snapshot?.documents.count ?? 0
                group.leave()
            }
        
        // Contar comentarios
        group.enter()
        db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, _ in
                commentCount = snapshot?.documents.count ?? 0
                group.leave()
            }
        
        group.notify(queue: DispatchQueue.main) {
            // 📊 ALGORITMO DE TRENDING SCORE
            let ageInHours = Date().timeIntervalSince(moment.timestamp) / 3600
            let recencyFactor = max(0, 48 - ageInHours) / 48 // Peso por recencia (48h ventana)
            
            let engagementScore = Double(reactionCount * 2 + commentCount * 3) // Comentarios valen más
            let engagementRate = ageInHours > 0 ? engagementScore / ageInHours : engagementScore
            
            // Score final: engagement ajustado por tiempo + factor de recencia
            let trendingScore = (engagementRate * 10) + (recencyFactor * 50)
            
            
            completion(trendingScore, engagementRate)
        }
    }
    
    // MARK: - 🔧 UTILIDADES
    private func extractHashtags(from text: String) -> [String] {
        let pattern = #"#\w+"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex?.matches(in: text, options: [], range: range) ?? []
        
        return matches.compactMap { match in
            if let range = Range(match.range, in: text) {
                let hashtag = String(text[range])
                return hashtag.lowercased().replacingOccurrences(of: "#", with: "")
            }
            return nil
        }.filter { $0.count > 1 } // Filtrar hashtags muy cortos
    }
    
    private func categorizeHashtag(_ hashtag: String) -> TrendingHashtag.HashtagCategory {
        let foodKeywords = ["comida", "food", "pizza", "cafe", "restaurant", "cocina", "recipe"]
        let travelKeywords = ["travel", "viaje", "vacation", "playa", "beach", "trip", "city"]
        let fashionKeywords = ["fashion", "moda", "outfit", "style", "look", "ropa", "clothes"]
        let techKeywords = ["tech", "tecnologia", "app", "software", "code", "programming"]
        let artKeywords = ["art", "arte", "photo", "photography", "design", "creative"]
        let lifestyleKeywords = ["lifestyle", "life", "motivation", "fitness", "health", "wellbeing"]
        
        let lowerHashtag = hashtag.lowercased()
        
        if foodKeywords.contains(where: { lowerHashtag.contains($0) }) {
            return .food
        } else if travelKeywords.contains(where: { lowerHashtag.contains($0) }) {
            return .travel
        } else if fashionKeywords.contains(where: { lowerHashtag.contains($0) }) {
            return .fashion
        } else if techKeywords.contains(where: { lowerHashtag.contains($0) }) {
            return .tech
        } else if artKeywords.contains(where: { lowerHashtag.contains($0) }) {
            return .art
        } else if lifestyleKeywords.contains(where: { lowerHashtag.contains($0) }) {
            return .lifestyle
        } else {
            return .general
        }
    }
}

// MARK: - 🔍 TRENDING PARA EXPLORAR
extension TrendingService {
    
    /// Obtiene contenido trending personalizado para la vista Explore
    func fetchPersonalizedTrendingContent(for userId: String, completion: @escaping (Result<PersonalizedTrendingContent, Error>) -> Void) {
        let group = DispatchGroup()
        var hashtags: [TrendingHashtag] = []
        var locations: [TrendingLocation] = []
        var moments: [TrendingMoment] = []
        var error: Error?
        
        // Fetch trending hashtags
        group.enter()
        fetchTrendingHashtags(limit: 10) { result in
            switch result {
            case .success(let trendingHashtags):
                hashtags = trendingHashtags
            case .failure(let err):
                error = err
            }
            group.leave()
        }
        
        // Fetch trending locations
        group.enter()
        fetchTrendingLocations(limit: 8) { result in
            switch result {
            case .success(let trendingLocations):
                locations = trendingLocations
            case .failure(let err):
                if error == nil { error = err }
            }
            group.leave()
        }
        
        // Fetch trending moments
        group.enter()
        fetchTrendingMoments(for: userId, limit: 15) { result in
            switch result {
            case .success(let trendingMoments):
                moments = trendingMoments
            case .failure(let err):
                if error == nil { error = err }
            }
            group.leave()
        }
        
        group.notify(queue: DispatchQueue.main) {
            if let error = error {
                completion(.failure(error))
            } else {
                let content = PersonalizedTrendingContent(
                    hashtags: hashtags,
                    locations: locations,
                    moments: moments,
                    lastUpdated: Date()
                )
                completion(.success(content))
            }
        }
    }
    
    struct PersonalizedTrendingContent {
        let hashtags: [TrendingHashtag]
        let locations: [TrendingLocation]
        let moments: [TrendingMoment]
        let lastUpdated: Date
    }
}
