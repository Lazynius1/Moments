import Foundation
import Combine
import SwiftUI

class AnalyticsService: ObservableObject {
    private let db = Firestore.firestore()
    private var sessionStartTime: Date?
    internal var currentSessionId: String?
    
    static let shared = AnalyticsService()
    
    private init() {
        startSession()
    }
    
    // MARK: - Session Management
    func startSession() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        sessionStartTime = Date()
        currentSessionId = UUID().uuidString
        
        let sessionData: [String: Any] = [
            "sessionId": currentSessionId!,
            "userId": userId,
            "startTime": Timestamp(date: sessionStartTime!),
            "deviceInfo": getDeviceInfo(),
            "appVersion": getAppVersion(),
            "isActive": true
        ]
        
        db.collection("users").document(userId).collection("sessions").document(currentSessionId!).setData(sessionData)
        
        // Track login activity
        trackLoginActivity()
    }
    
    func endSession() {
        guard let userId = Auth.auth().currentUser?.uid,
              let sessionId = currentSessionId,
              let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        
        db.collection("users").document(userId).collection("sessions").document(sessionId).updateData([
            "endTime": Timestamp(date: Date()),
            "duration": sessionDuration,
            "isActive": false
        ])
        
        // Update daily stats
        updateDailyStats(userId: userId, sessionDuration: sessionDuration)
    }
    
    // MARK: - Login Activity Tracking
    private func trackLoginActivity() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let loginData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "device": getDeviceInfo()["model"] as? String ?? "Unknown",
            "location": "España, Barcelona", // In production, use real geolocation
            "ipAddress": getIPAddress(),
            "isSuccessful": true,
            "sessionId": currentSessionId ?? UUID().uuidString
        ]
        
        db.collection("users").document(userId).collection("loginActivity").addDocument(data: loginData)
    }
    
    // MARK: - User Activity Tracking
    func trackScreenView(_ screenName: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let eventData: [String: Any] = [
            "eventType": "screen_view",
            "screenName": screenName,
            "timestamp": Timestamp(date: Date()),
            "sessionId": currentSessionId ?? ""
        ]
        
        db.collection("users").document(userId).collection("events").addDocument(data: eventData)
    }
    
    func trackInteraction(_ interactionType: String, details: [String: Any] = [:]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        var eventData: [String: Any] = [
            "eventType": "interaction",
            "interactionType": interactionType,
            "timestamp": Timestamp(date: Date()),
            "sessionId": currentSessionId ?? ""
        ]
        
        // Merge additional details
        eventData.merge(details) { _, new in new }
        
        db.collection("users").document(userId).collection("events").addDocument(data: eventData)
        
        // Update real-time interaction count
        updateInteractionCount(userId: userId)
    }
    
    func trackFeatureUsage(_ featureName: String) {
        guard let userId = Auth.auth().currentUser?.uid, !userId.isEmpty else {
            return
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        guard !dateString.isEmpty else {
            return
        }
        
        let featureRef = db.collection("users").document(userId).collection("featureUsage").document(dateString)
        
        featureRef.getDocument { snapshot, error in
            if let error = error {
                return
            }
            var data = snapshot?.data() ?? [:]
            let currentCount = data[featureName] as? Int ?? 0
            data[featureName] = currentCount + 1
            data["date"] = dateString
            
            featureRef.setData(data, merge: true) { error in
                if let error = error {
                }
            }
        }
    }
    
    // MARK: - Daily Stats Update
    private func updateDailyStats(userId: String, sessionDuration: TimeInterval) {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        let dailyStatsRef = db.collection("users").document(userId).collection("dailyStats").document(dateString)
        
        dailyStatsRef.getDocument { snapshot, error in
            var data = snapshot?.data() ?? [:]
            
            let currentTimeSpent = data["timeSpent"] as? TimeInterval ?? 0
            let currentSessions = data["sessionCount"] as? Int ?? 0
            
            data["timeSpent"] = currentTimeSpent + sessionDuration
            data["sessionCount"] = currentSessions + 1
            data["date"] = dateString
            data["lastUpdated"] = Timestamp(date: Date())
            
            dailyStatsRef.setData(data, merge: true)
        }
    }
    
    private func updateInteractionCount(userId: String) {
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: today)
        
        let dailyStatsRef = db.collection("users").document(userId).collection("dailyStats").document(dateString)
        
        dailyStatsRef.updateData([
            "interactionCount": FieldValue.increment(Int64(1))
        ]) { error in
            if let error = error {
                // If document doesn't exist, create it
                dailyStatsRef.setData([
                    "date": dateString,
                    "interactionCount": 1,
                    "lastUpdated": Timestamp(date: Date())
                ], merge: true)
            }
        }
    }
    
    // MARK: - Data Retrieval for UserActivityView
    func fetchUserActivityData(timeRange: ActivityTimeRange, completion: @escaping (Result<UserActivityData, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        let startDate: Date
        
        switch timeRange {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Fetch daily stats
        db.collection("users").document(userId).collection("dailyStats")
            .whereField("date", isGreaterThanOrEqualTo: dateFormatter.string(from: startDate))
            .whereField("date", isLessThanOrEqualTo: dateFormatter.string(from: endDate))
            .order(by: "date")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let dailyStats = snapshot?.documents.compactMap { doc -> DailyActivityStats? in
                    let data = doc.data()
                    guard let dateString = data["date"] as? String,
                          let date = dateFormatter.date(from: dateString) else { return nil }
                    
                    return DailyActivityStats(
                        date: date,
                        timeSpent: data["timeSpent"] as? TimeInterval ?? 0,
                        interactions: data["interactionCount"] as? Int ?? 0,
                        sessionCount: data["sessionCount"] as? Int ?? 0
                    )
                } ?? []
                
                // Fetch feature usage
                self.fetchFeatureUsage(userId: userId, startDate: startDate, endDate: endDate) { featureResult in
                    switch featureResult {
                    case .success(let featureUsage):
                        let activityData = UserActivityData(
                            dailyStats: dailyStats,
                            featureUsage: featureUsage,
                            timeRange: timeRange
                        )
                        completion(.success(activityData))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
    }
    
    private func fetchFeatureUsage(userId: String, startDate: Date, endDate: Date, completion: @escaping (Result<[FeatureUsageData], Error>) -> Void) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        db.collection("users").document(userId).collection("featureUsage")
            .whereField("date", isGreaterThanOrEqualTo: dateFormatter.string(from: startDate))
            .whereField("date", isLessThanOrEqualTo: dateFormatter.string(from: endDate))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                var featureStats: [String: Int] = [:]
                
                snapshot?.documents.forEach { doc in
                    let data = doc.data()
                    data.forEach { key, value in
                        guard key != "date", let count = value as? Int else { return }
                        featureStats[key, default: 0] += count
                    }
                }
                
                let totalUsage = featureStats.values.reduce(0, +)
                let featureUsage = featureStats.map { feature, count in
                    FeatureUsageData(
                        name: feature.capitalized,
                        icon: self.getFeatureIcon(feature),
                        usageCount: count,
                        percentage: totalUsage > 0 ? Double(count) / Double(totalUsage) : 0
                    )
                }.sorted { $0.usageCount > $1.usageCount }
                
                completion(.success(featureUsage))
            }
    }
    
    // MARK: - Real Login Activity Data
    func fetchLoginActivity(completion: @escaping (Result<[LoginActivityData], Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])))
            return
        }
        
        db.collection("users").document(userId).collection("loginActivity")
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let activities = snapshot?.documents.compactMap { doc -> LoginActivityData? in
                    let data = doc.data()
                    guard let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                          let device = data["device"] as? String,
                          let location = data["location"] as? String,
                          let ipAddress = data["ipAddress"] as? String,
                          let isSuccessful = data["isSuccessful"] as? Bool else { return nil }
                    
                    return LoginActivityData(
                        id: doc.documentID,
                        timestamp: timestamp,
                        device: device,
                        location: location,
                        ipAddress: ipAddress,
                        isSuccessful: isSuccessful,
                        failureReason: data["failureReason"] as? String
                    )
                } ?? []
                
                completion(.success(activities))
            }
    }
    
    // MARK: - Helper Functions
    private func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        return [
            "model": device.model,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "identifierForVendor": device.identifierForVendor?.uuidString ?? "Unknown"
        ]
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private func getIPAddress() -> String {
        // In production, you'd want to get the real IP from your backend
        return "192.168.1.100"
    }
    
    private func getFeatureIcon(_ featureName: String) -> String {
        switch featureName.lowercased() {
        case "feed": return "house.fill"
        case "chat", "messages": return "message.fill"
        case "stories": return "circle.dashed"
        case "profile": return "person.fill"
        case "search": return "magnifyingglass"
        case "camera": return "camera.fill"
        case "settings": return "gear"
        default: return "circle.fill"
        }
    }
}

// MARK: - Data Models
struct UserActivityData {
    let dailyStats: [DailyActivityStats]
    let featureUsage: [FeatureUsageData]
    let timeRange: ActivityTimeRange
}

struct DailyActivityStats {
    let date: Date
    let timeSpent: TimeInterval
    let interactions: Int
    let sessionCount: Int
}

struct FeatureUsageData {
    let name: String
    let icon: String
    let usageCount: Int
    let percentage: Double
}

struct LoginActivityData {
    let id: String
    let timestamp: Date
    let device: String
    let location: String
    let ipAddress: String
    let isSuccessful: Bool
    let failureReason: String?
}

// MARK: - AppDelegate Integration
extension AnalyticsService {
    func applicationDidBecomeActive() {
        startSession()
    }
    
    func applicationWillResignActive() {
        endSession()
    }
}

extension AnalyticsService {
    // Make currentSessionId accessible (change private to internal in the property declaration)
    func getCurrentSessionId() -> String? {
        return currentSessionId
    }
    
    // Enhanced login tracking with real location
    func trackSuccessfulLogin() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let loginData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "device": getDeviceInfo()["model"] as? String ?? "Unknown",
            "location": RealLoginActivityService.shared.getCurrentLocationString(),
            "ipAddress": getIPAddress(),
            "isSuccessful": true,
            "sessionId": currentSessionId ?? UUID().uuidString,
            "loginMethod": "email",
            "coordinates": RealLoginActivityService.shared.getCoordinatesDict()
        ]
        
        db.collection("users").document(userId).collection("loginActivity").addDocument(data: loginData)
    }
    
    func trackFailedLogin(reason: String, email: String = "") {
        RealLoginActivityService.shared.trackFailedLoginAttempt(
            email: email.isEmpty ? Auth.auth().currentUser?.email ?? "unknown" : email,
            reason: reason
        )
    }
    
    // Method to manually end current session (useful for logout)
    func endCurrentSession() {
        endSession()
    }
}

// MARK: - ✨ NUEVOS: Métodos específicos para comentarios
extension AnalyticsService {
    
    func trackCommentEngagement(momentId: String, commentDepth: Int, hasReactions: Bool) {
        trackInteraction("comment_engagement", details: [
            "momentId": momentId,
            "commentDepth": commentDepth,
            "hasReactions": hasReactions
        ])
    }
    
    func trackSwipeGesture(action: String, success: Bool) {
        trackInteraction("swipe_gesture", details: [
            "action": action,
            "success": success
        ])
    }
    
    func trackCommentModeration(result: String, reason: String = "") {
        trackInteraction("comment_moderation", details: [
            "result": result, // "approved", "flagged", "blocked"
            "reason": reason
        ])
    }
    
    func trackMentionUsage(mentionCount: Int, commentLength: Int) {
        trackInteraction("mention_usage", details: [
            "mentionCount": mentionCount,
            "commentLength": commentLength
        ])
    }
    
    func trackCommentActions(action: String, commentId: String = "", isNested: Bool = false) {
        trackInteraction("comment_action", details: [
            "action": action, // "create", "edit", "delete", "like", "reply"
            "commentId": commentId,
            "isNested": isNested
        ])
    }
}

