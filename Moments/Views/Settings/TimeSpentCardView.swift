import SwiftUI

struct TimeSpentCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var manager = TimeSpentManager.shared
    
    @State private var data: [(date: Date, seconds: TimeInterval)] = []
    @State private var average: TimeInterval = 0
    
    // Auto refresh every minute when view is open
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("userActivity.timeSpent.title", value: "Time on Moments", comment: "Time spent title"))
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("\(formatTime(average))")
                        .font(.system(size: legacyPoppinsSize(28), weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(NSLocalizedString("userActivity.timeSpent.average", value: "Daily average", comment: "Daily average subtitle"))
                        .font(.system(size: legacyPoppinsSize(13)))
                        .foregroundColor(.gray)
                }
                Spacer()
                
                Image(systemName: "clock.fill")
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .font(.system(size: 20))
            }
            
            // Daily Bars Chart
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(data, id: \.date) { item in
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            let maxH = geo.size.height
                            // Use at least 1 hour threshold, but expand if user played more
                            let maxSecs = max(data.map { $0.seconds }.max() ?? 1, 3600)
                            let height = maxH * CGFloat(item.seconds / maxSecs)
                            
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                SettingsProfileColors.accent(colorScheme).opacity(0.85),
                                                SettingsProfileColors.accent(colorScheme).opacity(0.45)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: max(height, 4)) // minimum 4px height visible
                            }
                        }
                        .frame(height: 100)
                        
                        Text(dayAbbreviation(for: item.date))
                            .font(.system(size: legacyPoppinsSize(11)))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .onAppear {
            refreshData()
        }
        .onReceive(timer) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        manager.updateCurrentSession()
        data = manager.getLast7DaysData()
        average = manager.getWeeklyAverage()
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func dayAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // Mon, Tue, Wed
        return formatter.string(from: date).prefix(1).uppercased() // M, T, W
    }
}
