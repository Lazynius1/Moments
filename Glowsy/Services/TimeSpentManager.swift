import Foundation
import UIKit
import Combine
import UserNotifications

class TimeSpentManager: ObservableObject {
    static let shared = TimeSpentManager()
    
    @Published var dailySeconds: [String: TimeInterval] = [:]
    @Published var dailyLimitSeconds: TimeInterval? = nil
    
    private var sessionStartTime: Date?
    private var timer: Timer?
    private var hasNotifiedToday: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    private let defaultsKey = "Glowsy_TimeSpentData"
    private let limitKey = "Glowsy_DailyLimitSettings"
    private let lastNotificationDateKey = "Glowsy_LastNotificationDate"
    
    private init() {
        loadData()
        setupObservers()
        
        // Start tracking immediately if app is already active
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                self.startSession()
            }
        }
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.startSession()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.endSession()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.endSession()
            }
            .store(in: &cancellables)
    }
    
    private func startSession() {
        if sessionStartTime == nil {
            sessionStartTime = Date()
            
            // Check if we already notified today
            let lastNotifiedDate = UserDefaults.standard.string(forKey: lastNotificationDateKey)
            hasNotifiedToday = (lastNotifiedDate == dateKey(for: Date()))
            
            startTimer()
        }
    }
    
    func endSession() {
        guard let start = sessionStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        addTime(duration: duration, for: start)
        sessionStartTime = nil
        stopTimer()
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.flushCurrentSessionInterval()
            self?.checkDailyLimit()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkDailyLimit() {
        guard let limit = dailyLimitSeconds else { return }

        let todayKey = dateKey(for: Date())
        let lastNotifiedDate = UserDefaults.standard.string(forKey: lastNotificationDateKey)
        hasNotifiedToday = (lastNotifiedDate == todayKey)
        guard !hasNotifiedToday else { return }
        
        let todaySeconds = getSeconds(for: Date())
        var currentSessionSeconds: TimeInterval = 0
        if let start = sessionStartTime {
            currentSessionSeconds = Date().timeIntervalSince(start)
        }
        
        let totalToday = todaySeconds + currentSessionSeconds
        
        if totalToday >= limit {
            sendDailyLimitInAppBanner()
            sendDailyLimitNotification()
            hasNotifiedToday = true
            UserDefaults.standard.set(dateKey(for: Date()), forKey: lastNotificationDateKey)
        }
    }
    
    private func sendDailyLimitNotification() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("userActivity.timeSpent.limitReached.title", value: "Moments", comment: "Limit reached notification title")
        content.body = NSLocalizedString("userActivity.timeSpent.limitReached.body", value: "Has alcanzado tu límite diario de tiempo en Moments.", comment: "Limit reached notification body")
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "dailyLimitReached", content: content, trigger: nil) // Fire immediately
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling limit notification: \(error)")
            }
        }
    }

    private func sendDailyLimitInAppBanner() {
        let title = NSLocalizedString("userActivity.timeSpent.limitReached.inAppTitle", value: "Límite diario alcanzado", comment: "In-app limit reached title")
        let body = NSLocalizedString("userActivity.timeSpent.limitReached.body", value: "Has alcanzado tu límite diario de tiempo en Moments.", comment: "Limit reached notification body")

        Task { @MainActor in
            let bannerNotification = Notification(
                id: UUID().uuidString,
                type: .message,
                senderId: "system_time_limit",
                senderUsername: title,
                timestamp: Date(),
                isPending: true,
                reaction: body
            )
            InAppNotificationService.shared.handleNewNotification(bannerNotification)
        }
    }
    
    private func addTime(duration: TimeInterval, for date: Date) {
        guard duration > 0 else { return }
        let key = dateKey(for: date)
        dailySeconds[key, default: 0] += duration
        saveData()
    }

    private func flushCurrentSessionInterval() {
        guard let start = sessionStartTime else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        addTime(duration: elapsed, for: start)
        sessionStartTime = now
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            dailySeconds = decoded
        }
        if UserDefaults.standard.object(forKey: limitKey) != nil {
            dailyLimitSeconds = UserDefaults.standard.double(forKey: limitKey)
        }
    }
    
    private func saveData() {
        if let encoded = try? JSONEncoder().encode(dailySeconds) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
    
    // MARK: - Daily Limit Preferences
    func setDailyLimit(_ seconds: TimeInterval?) {
        dailyLimitSeconds = seconds
        if let secs = seconds {
            UserDefaults.standard.set(secs, forKey: limitKey)
            
            // Re-check just in case they set a limit lower than what they've already spent today
            checkDailyLimit()
        } else {
            UserDefaults.standard.removeObject(forKey: limitKey)
        }
    }
    
    // YYYY-MM-DD format
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func getSeconds(for date: Date) -> TimeInterval {
        return dailySeconds[dateKey(for: date)] ?? 0
    }
    
    /// Returns data for the last 7 days including today. Order: [Today - 6, Today - 5, ... Today]
    func getLast7DaysData() -> [(date: Date, seconds: TimeInterval)] {
        var result: [(Date, TimeInterval)] = []
        let cal = Calendar.current
        let today = Date()
        
        for i in (0..<7).reversed() {
            if let targetDate = cal.date(byAdding: .day, value: -i, to: today) {
                let seconds = getSeconds(for: targetDate)
                result.append((targetDate, seconds))
            }
        }
        return result
    }
    
    func getWeeklyAverage() -> TimeInterval {
        let data = getLast7DaysData()
        let total = data.reduce(0) { $0 + $1.seconds }
        return total / 7.0
    }
    
    /// Useful for forcing an update on UI elements while the session is active
    func updateCurrentSession() {
        flushCurrentSessionInterval()
    }
}
