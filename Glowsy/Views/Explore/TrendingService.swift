// ================== TrendingService.swift ==================

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - 🔥 Servicio de Trending con respeto a privacidad
class TrendingService: ObservableObject {
    static let shared = TrendingService()
    private let db = Firestore.firestore()
    private let cacheQueue = DispatchQueue(label: "trending.cache.queue")
    private var personalizedCache: [String: (content: PersonalizedTrendingContent, expiresAt: Date)] = [:]
    private let personalizedCacheTTL: TimeInterval = 300
    
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
    func fetchTrendingHashtags(limit: Int = 20, viewerId: String? = nil, completion: @escaping (Result<[TrendingHashtag], Error>) -> Void) {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let resolvedViewerId = viewerId ?? Auth.auth().currentUser?.uid
        
        // Buscar momentos públicos de las últimas 48h para calcular crecimiento real 24h vs 24h previas
        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("timestamp", isGreaterThan: Timestamp(date: twoDaysAgo))
            .limit(to: 800)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let decodedMoments = snapshot?.documents.compactMap { doc -> Moment? in
                    guard var moment = try? doc.data(as: Moment.self) else { return nil }
                    moment.id = doc.documentID
                    guard moment.isArchived != true else { return nil }
                    return moment
                } ?? []

                guard !decodedMoments.isEmpty else {
                    completion(.success([]))
                    return
                }

                let processMoments: ([Moment]) -> Void = { moments in
                    var currentWindowCounts: [String: Int] = [:]
                    var previousWindowCounts: [String: Int] = [:]

                    for moment in moments {
                        guard moment.timestamp <= now else { continue } // Excluir programados/futuros
                        let hashtags = self.extractHashtags(from: moment.content)
                        guard !hashtags.isEmpty else { continue }

                        if moment.timestamp > yesterday {
                            for hashtag in hashtags { currentWindowCounts[hashtag, default: 0] += 1 }
                        } else {
                            for hashtag in hashtags { previousWindowCounts[hashtag, default: 0] += 1 }
                        }
                    }

                    let trendingHashtags = currentWindowCounts
                        .filter { $0.value >= 3 }
                        .sorted { $0.value > $1.value }
                        .prefix(limit)
                        .map { hashtag, count in
                            TrendingHashtag(
                                hashtag: hashtag,
                                count: count,
                                growth: self.calculateGrowth(current: count, previous: previousWindowCounts[hashtag] ?? 0),
                                category: self.categorizeHashtag(hashtag)
                            )
                        }

                    completion(.success(Array(trendingHashtags)))
                }

                guard let resolvedViewerId else {
                    processMoments(decodedMoments)
                    return
                }

                self.filterMomentsByTrendingSafety(decodedMoments, viewerId: resolvedViewerId, completion: processMoments)
            }
    }
    
    // MARK: - 📍 TRENDING LOCATIONS
    func fetchTrendingLocations(limit: Int = 15, viewerId: String? = nil, completion: @escaping (Result<[TrendingLocation], Error>) -> Void) {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let resolvedViewerId = viewerId ?? Auth.auth().currentUser?.uid
        
        db.collectionGroup("moments")
            .whereField("audience", isEqualTo: "everyone")
            .whereField("timestamp", isGreaterThan: Timestamp(date: twoDaysAgo))
            .whereField("location", isNotEqualTo: "")
            .limit(to: 500)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let decodedMoments = snapshot?.documents.compactMap { doc -> Moment? in
                    guard var moment = try? doc.data(as: Moment.self) else { return nil }
                    moment.id = doc.documentID
                    guard moment.isArchived != true else { return nil }
                    return moment
                } ?? []

                guard !decodedMoments.isEmpty else {
                    completion(.success([]))
                    return
                }

                let processMoments: ([Moment]) -> Void = { moments in
                    var currentWindow: [String: (count: Int, users: Set<String>)] = [:]
                    var previousWindow: [String: Int] = [:]

                    for moment in moments {
                        guard moment.timestamp <= now else { continue }
                        guard let location = moment.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty else { continue }

                        if moment.timestamp > yesterday {
                            if currentWindow[location] == nil {
                                currentWindow[location] = (count: 0, users: Set<String>())
                            }
                            currentWindow[location]?.count += 1
                            currentWindow[location]?.users.insert(moment.authorId)
                        } else {
                            previousWindow[location, default: 0] += 1
                        }
                    }

                    let trendingLocations = currentWindow
                        .filter { $0.value.count >= 2 && $0.value.users.count >= 2 }
                        .sorted { $0.value.count > $1.value.count }
                        .prefix(limit)
                        .map { location, data in
                            TrendingLocation(
                                locationName: location,
                                momentCount: data.count,
                                uniqueUsers: data.users.count,
                                growth: self.calculateGrowth(current: data.count, previous: previousWindow[location] ?? 0),
                                coordinate: nil
                            )
                        }

                    completion(.success(Array(trendingLocations)))
                }

                guard let resolvedViewerId else {
                    processMoments(decodedMoments)
                    return
                }

                self.filterMomentsByTrendingSafety(decodedMoments, viewerId: resolvedViewerId, completion: processMoments)
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
                
                var candidateMoments: [Moment] = []
                
                // Convertir documentos a momentos
                for doc in documents {
                    do {
                        var moment = try doc.data(as: Moment.self)
                        moment.id = doc.documentID
                        guard moment.isArchived != true else { continue }
                        
                        // Excluir momentos del propio usuario
                        guard moment.authorId != userId else { continue }
                        guard moment.timestamp <= now else { continue }
                        
                        candidateMoments.append(moment)
                    } catch {
                    }
                }
                
                self.filterMomentsByTrendingSafety(candidateMoments, viewerId: userId) { safeMoments in
                    // Calcular trending score para cada momento
                    self.calculateTrendingScores(for: safeMoments) { trendingMoments in
                    let sortedTrending = trendingMoments
                        .sorted { $0.trendingScore > $1.trendingScore }
                        .prefix(limit)
                    
                    completion(.success(Array(sortedTrending)))
                    }
                }
            }
    }
    
    // MARK: - 🧮 ALGORITMO DE TRENDING SCORE
    private func calculateTrendingScores(for moments: [Moment], completion: @escaping ([TrendingMoment]) -> Void) {
        let trendingMoments = moments.map { moment -> TrendingMoment in
            let (trendingScore, engagementRate) = calculateMomentTrendingScore(moment: moment)
            return TrendingMoment(
                moment: moment,
                trendingScore: trendingScore,
                engagementRate: engagementRate,
                timeToTrend: Date().timeIntervalSince(moment.timestamp)
            )
        }
        completion(trendingMoments)
    }
    
    private func calculateMomentTrendingScore(moment: Moment) -> (Double, Double) {
        let reactionCount = moment.reactions.values.reduce(0) { partialResult, users in
            partialResult + users.count
        }
        let commentCount = moment.commentCount

        let ageInHours = Date().timeIntervalSince(moment.timestamp) / 3600
        let recencyFactor = max(0, 48 - ageInHours) / 48
        
        let engagementScore = Double(reactionCount * 2 + commentCount * 3)
        let engagementRate = ageInHours > 0 ? engagementScore / ageInHours : engagementScore
        
        let trendingScore = (engagementRate * 10) + (recencyFactor * 50)
        return (trendingScore, engagementRate)
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

    private func calculateGrowth(current: Int, previous: Int) -> Double {
        guard previous > 0 else {
            return current > 0 ? 100.0 : 0.0
        }
        return ((Double(current - previous) / Double(previous)) * 100.0)
    }

    private func filterMomentsByTrendingSafety(
        _ moments: [Moment],
        viewerId: String,
        completion: @escaping ([Moment]) -> Void
    ) {
        guard !moments.isEmpty else {
            completion([])
            return
        }

        let uniqueAuthorIds = Array(Set(moments.map { $0.authorId }))
        let authorBatches = uniqueAuthorIds.chunked(into: 10)

        db.collection("users").document(viewerId).getDocument { [weak self] viewerSnapshot, _ in
            guard let self = self else { return }

            let viewerBlockedUsers = Set((viewerSnapshot?.data()?["blockedUsers"] as? [String]) ?? [])
            let syncQueue = DispatchQueue(label: "trending.safety.filter.sync")
            let group = DispatchGroup()
            var disallowedAuthors = Set<String>()

            for batch in authorBatches {
                guard !batch.isEmpty else { continue }
                group.enter()
                self.db.collection("users")
                    .whereField(FieldPath.documentID(), in: batch)
                    .getDocuments { snapshot, _ in
                        syncQueue.sync {
                            for document in snapshot?.documents ?? [] {
                                let authorId = document.documentID
                                if viewerBlockedUsers.contains(authorId) {
                                    disallowedAuthors.insert(authorId)
                                    continue
                                }

                                let data = document.data()
                                let authorBlockedUsers = Set((data["blockedUsers"] as? [String]) ?? [])
                                if authorBlockedUsers.contains(viewerId) {
                                    disallowedAuthors.insert(authorId)
                                    continue
                                }

                                let settings = data["contentVisibilitySettings"] as? [String: Any]
                                let hiddenFromUsers = Set((settings?["hiddenFromUsers"] as? [String]) ?? [])
                                if hiddenFromUsers.contains(viewerId) {
                                    disallowedAuthors.insert(authorId)
                                }
                            }
                        }
                        group.leave()
                    }
            }

            group.notify(queue: .main) {
                let filtered = moments.filter { !disallowedAuthors.contains($0.authorId) }
                completion(filtered)
            }
        }
    }
}

// MARK: - 🔍 TRENDING PARA EXPLORAR
extension TrendingService {
    
    /// Obtiene contenido trending personalizado para la vista Explore
    func fetchPersonalizedTrendingContent(for userId: String, completion: @escaping (Result<PersonalizedTrendingContent, Error>) -> Void) {
        if let cached = cachedPersonalizedContent(for: userId) {
            completion(.success(cached))
            return
        }

        let group = DispatchGroup()
        var hashtags: [TrendingHashtag] = []
        var locations: [TrendingLocation] = []
        var moments: [TrendingMoment] = []
        var error: Error?
        
        // Fetch trending hashtags
        group.enter()
        fetchTrendingHashtags(limit: 10, viewerId: userId) { result in
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
        fetchTrendingLocations(limit: 8, viewerId: userId) { result in
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
        
        group.notify(queue: .main) {
            if let error = error {
                completion(.failure(error))
            } else {
                let content = PersonalizedTrendingContent(
                    hashtags: hashtags,
                    locations: locations,
                    moments: moments,
                    lastUpdated: Date()
                )
                self.storePersonalizedContent(content, for: userId)
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

    private func cachedPersonalizedContent(for userId: String) -> PersonalizedTrendingContent? {
        cacheQueue.sync {
            guard let entry = personalizedCache[userId] else { return nil }
            guard entry.expiresAt > Date() else {
                personalizedCache[userId] = nil
                return nil
            }
            return entry.content
        }
    }

    private func storePersonalizedContent(_ content: PersonalizedTrendingContent, for userId: String) {
        cacheQueue.async {
            self.personalizedCache[userId] = (content: content, expiresAt: Date().addingTimeInterval(self.personalizedCacheTTL))
        }
    }
}
