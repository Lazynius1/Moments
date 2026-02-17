import SwiftUI
import FirebaseAuth
import Charts

struct UserActivityView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = UserActivityViewModel()
    @State private var selectedTimeRange: ActivityTimeRange = .week
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            if isLoading {
                ProgressView("Cargando actividad...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Time Range Selector
                        TimeRangeSelector(selectedRange: $selectedTimeRange) { range in
                            selectedTimeRange = range
                            viewModel.loadActivityData(for: range)
                        }
                        .padding(.horizontal)
                        
                        // Summary Cards
                        ActivitySummarySection(summary: viewModel.activitySummary)
                            .padding(.horizontal)
                        
                        // Time Spent Chart
                        TimeSpentChartSection(data: viewModel.timeSpentData, timeRange: selectedTimeRange)
                            .padding(.horizontal)
                        
                        // Interactions Chart
                        InteractionsChartSection(data: viewModel.interactionsData, timeRange: selectedTimeRange)
                            .padding(.horizontal)
                        
                        // Daily Breakdown
                        DailyBreakdownSection(data: viewModel.dailyBreakdown)
                            .padding(.horizontal)
                        
                        // App Features Usage
                        AppFeaturesSection(data: viewModel.featureUsage)
                            .padding(.horizontal)
                        
                        // Insights and Tips
                        InsightsSection(insights: viewModel.insights)
                            .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.top)
                }
            }
        }
        .navigationTitle("Tu Actividad")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color(hex: "4F46E5").opacity(0.3), Color(hex: "4F46E5").opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "4F46E5"))
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadActivityData(for: selectedTimeRange) {
                isLoading = false
            }
        }
        }
    }
}

struct TimeRangeSelector: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedRange: ActivityTimeRange
    let onRangeChanged: (ActivityTimeRange) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ActivityTimeRange.allCases, id: \.self) { range in
                Button(action: {
                    selectedRange = range
                    onRangeChanged(range)
                }) {
                    Text(range.title)
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(selectedRange == range ? .white : Color(hex: "4F46E5"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedRange == range ? Color(hex: "4F46E5") : Color.clear)
                        )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(hex: "4F46E5"), lineWidth: 1)
        )
    }
}

struct ActivitySummarySection: View {
    @Environment(\.colorScheme) var colorScheme
    let summary: ActivitySummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("userActivity.summary.title", comment: "Activity summary title"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            HStack(spacing: 12) {
                SummaryCard(
                    icon: "clock.fill",
                    title: NSLocalizedString("userActivity.totalTime", comment: "Total time"),
                    value: summary.totalTimeSpent,
                    color: Color(hex: "4F46E5")
                )
                
                SummaryCard(
                    icon: "heart.fill",
                    title: NSLocalizedString("userActivity.interactions", comment: "Interactions"),
                    value: "\(summary.totalInteractions)",
                    color: .red
                )
            }
            
            HStack(spacing: 12) {
                SummaryCard(
                    icon: "eye.fill",
                    title: NSLocalizedString("userActivity.postsViewed", comment: "Posts viewed"),
                    value: "\(summary.postsViewed)",
                    color: .blue
                )
                
                SummaryCard(
                    icon: "message.fill",
                    title: NSLocalizedString("userActivity.messages", comment: "Messages"),
                    value: "\(summary.messagesSent)",
                    color: .green
                )
            }
        }
    }
}

struct SummaryCard: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 24))
            
            Text(value)
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(title)
                .font(.custom("Poppins-Regular", size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct TimeSpentChartSection: View {
    @Environment(\.colorScheme) var colorScheme
    let data: [ActivityDataPoint]
    let timeRange: ActivityTimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("userActivity.timeInApp", comment: "Time in app"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            if #available(iOS 16.0, *) {
                Chart(data) { point in
                    BarMark(
                        x: .value("Día", point.date, unit: .day),
                        y: .value("Minutos", point.timeSpent)
                    )
                    .foregroundStyle(Color(hex: "4F46E5"))
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
            } else {
                // Fallback for iOS 15 and earlier
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(data) { point in
                            VStack {
                                Rectangle()
                                    .fill(Color(hex: "4F46E5"))
                                    .frame(width: 30, height: CGFloat(point.timeSpent) * 2)
                                
                                Text(point.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.custom("Poppins-Regular", size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
        )
    }
}

struct InteractionsChartSection: View {
    @Environment(\.colorScheme) var colorScheme
    let data: [ActivityDataPoint]
    let timeRange: ActivityTimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("userActivity.dailyInteractions", comment: "Daily interactions"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            if #available(iOS 16.0, *) {
                Chart(data) { point in
                    LineMark(
                        x: .value("Día", point.date, unit: .day),
                        y: .value("Interacciones", point.interactions)
                    )
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    
                    AreaMark(
                        x: .value("Día", point.date, unit: .day),
                        y: .value("Interacciones", point.interactions)
                    )
                    .foregroundStyle(.red.opacity(0.2))
                }
                .frame(height: 150)
            } else {
                // Fallback for iOS 15
                Text("Gráfico disponible en iOS 16+")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
                    .frame(height: 150)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
        )
    }
}

struct DailyBreakdownSection: View {
    @Environment(\.colorScheme) var colorScheme
    let data: [DailyActivity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("userActivity.dailyBreakdown", comment: "Daily breakdown"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            LazyVStack(spacing: 12) {
                ForEach(data) { day in
                    DailyActivityRow(activity: day)
                }
            }
        }
    }
}

struct DailyActivityRow: View {
    @Environment(\.colorScheme) var colorScheme
    let activity: DailyActivity
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(String(format: NSLocalizedString("userActivity.timeAndInteractions", comment: "Time and interactions"), "\(activity.timeSpent)", "\(activity.interactions)"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(activity.mostUsedFeature)
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(Color(hex: "4F46E5"))
                
                Text(NSLocalizedString("userActivity.mostUsedFeature", comment: "Most used feature"))
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.05))
        )
    }
}

struct AppFeaturesSection: View {
    @Environment(\.colorScheme) var colorScheme
    let data: [FeatureUsage]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("userActivity.featureUsage", comment: "Feature usage"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            VStack(spacing: 12) {
                ForEach(data) { feature in
                    FeatureUsageRow(feature: feature)
                }
            }
        }
    }
}

struct FeatureUsageRow: View {
    @Environment(\.colorScheme) var colorScheme
    let feature: FeatureUsage
    
    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .foregroundColor(Color(hex: "4F46E5"))
                .font(.system(size: 16))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.name)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(String(format: NSLocalizedString("userActivity.usageCount", comment: "Usage count"), "\(feature.usageCount)"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(Color(hex: "4F46E5"))
                        .frame(width: geometry.size.width * feature.percentage, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(width: 60, height: 6)
            
            Text("\(Int(feature.percentage * 100))%")
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.gray)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal)
    }
}

struct InsightsSection: View {
    @Environment(\.colorScheme) var colorScheme
    let insights: [ActivityInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("userActivity.insights", comment: "Insights"))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            VStack(spacing: 12) {
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }
}

struct InsightCard: View {
    @Environment(\.colorScheme) var colorScheme
    let insight: ActivityInsight
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .foregroundColor(insight.color)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(insight.description)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(insight.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(insight.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Models
enum ActivityTimeRange: String, CaseIterable {
    case week = "week"
    case month = "month"
    case year = "year"
    
    var title: String {
        switch self {
        case .week: return "Semana"
        case .month: return "Mes"
        case .year: return "Año"
        }
    }
}

struct ActivitySummary {
    let totalTimeSpent: String
    let totalInteractions: Int
    let postsViewed: Int
    let messagesSent: Int
}

struct ActivityDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let timeSpent: Int // minutes
    let interactions: Int
}

struct DailyActivity: Identifiable {
    let id = UUID()
    let date: Date
    let timeSpent: Int
    let interactions: Int
    let mostUsedFeature: String
}

struct FeatureUsage: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let usageCount: Int
    let percentage: Double
}

struct ActivityInsight: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
}

// MARK: - UserActivityViewModel (USA EL MÉTODO EXISTENTE)
class UserActivityViewModel: ObservableObject {
    @Published var activitySummary = ActivitySummary(totalTimeSpent: "0h 0m", totalInteractions: 0, postsViewed: 0, messagesSent: 0)
    @Published var timeSpentData: [ActivityDataPoint] = []
    @Published var interactionsData: [ActivityDataPoint] = []
    @Published var dailyBreakdown: [DailyActivity] = []
    @Published var featureUsage: [FeatureUsage] = []
    @Published var insights: [ActivityInsight] = []
    
    private let analyticsService = AnalyticsService.shared
    
    func loadActivityData(for timeRange: ActivityTimeRange, completion: (() -> Void)? = nil) {
        // USA EL MÉTODO QUE YA EXISTE EN AnalyticsService
        analyticsService.fetchUserActivityData(timeRange: timeRange) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let userData):
                    self?.processRealActivityData(userData)
                case .failure(let error):
                    // Fallback to empty data instead of mock
                    self?.loadEmptyData()
                }
                completion?()
            }
        }
    }
    
    private func processRealActivityData(_ userData: UserActivityData) {
        // Process real summary data
        let totalTimeMinutes = userData.dailyStats.reduce(0) { $0 + Int($1.timeSpent / 60) }
        let totalInteractions = userData.dailyStats.reduce(0) { $0 + $1.interactions }
        let totalHours = totalTimeMinutes / 60
        let remainingMinutes = totalTimeMinutes % 60
        
        activitySummary = ActivitySummary(
            totalTimeSpent: "\(totalHours)h \(remainingMinutes)m",
            totalInteractions: totalInteractions,
            postsViewed: calculatePostsViewed(from: userData),
            messagesSent: calculateMessagesSent(from: userData)
        )
        
        // Process real time spent data
        timeSpentData = userData.dailyStats.map { stat in
            ActivityDataPoint(
                date: stat.date,
                timeSpent: Int(stat.timeSpent / 60), // Convert to minutes
                interactions: stat.interactions
            )
        }
        
        interactionsData = timeSpentData
        
        // Process real daily breakdown
        dailyBreakdown = userData.dailyStats.map { stat in
            DailyActivity(
                date: stat.date,
                timeSpent: Int(stat.timeSpent / 60),
                interactions: stat.interactions,
                mostUsedFeature: getMostUsedFeature(for: stat.date, from: userData.featureUsage)
            )
        }
        
        // Process real feature usage
        featureUsage = userData.featureUsage.map { feature in
            FeatureUsage(
                name: feature.name,
                icon: feature.icon,
                usageCount: feature.usageCount,
                percentage: feature.percentage
            )
        }
        
        // Generate real insights
        insights = generateRealInsights(from: userData)
    }
    
    private func loadEmptyData() {
        activitySummary = ActivitySummary(totalTimeSpent: "0h 0m", totalInteractions: 0, postsViewed: 0, messagesSent: 0)
        timeSpentData = []
        interactionsData = []
        dailyBreakdown = []
        featureUsage = []
        insights = []
    }
    
    private func calculatePostsViewed(from userData: UserActivityData) -> Int {
        // Calculate from feature usage or events
        return userData.featureUsage.first(where: { $0.name.lowercased().contains("feed") })?.usageCount ?? 0
    }
    
    private func calculateMessagesSent(from userData: UserActivityData) -> Int {
        // Calculate from feature usage or events
        return userData.featureUsage.first(where: { $0.name.lowercased().contains("chat") || $0.name.lowercased().contains("message") })?.usageCount ?? 0
    }
    
    private func getMostUsedFeature(for date: Date, from featureUsage: [FeatureUsageData]) -> String {
        // For daily breakdown, return the most used feature overall
        return featureUsage.first?.name ?? "Feed"
    }
    
    private func generateRealInsights(from userData: UserActivityData) -> [ActivityInsight] {
        var insights: [ActivityInsight] = []
        
        // Analyze time spent trends
        let recentWeekData = userData.dailyStats.suffix(7)
        let previousWeekData = userData.dailyStats.dropLast(7).suffix(7)
        
        if !recentWeekData.isEmpty && !previousWeekData.isEmpty {
            let recentAverage = recentWeekData.reduce(0) { $0 + $1.timeSpent } / Double(recentWeekData.count)
            let previousAverage = previousWeekData.reduce(0) { $0 + $1.timeSpent } / Double(previousWeekData.count)
            
            if recentAverage > previousAverage * 1.2 {
                insights.append(ActivityInsight(
                    title: "¡Muy activo!",
                    description: "Has pasado un \(Int((recentAverage / previousAverage - 1) * 100))% más tiempo en la app esta semana",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green
                ))
            }
        }
        
        // Analyze most used feature
        if let topFeature = userData.featureUsage.first {
            insights.append(ActivityInsight(
                title: "Función favorita",
                description: "\(topFeature.name) es tu función más utilizada con \(topFeature.usageCount) usos",
                icon: topFeature.icon,
                color: Color(hex: "4F46E5")
            ))
        }
        
        // Analyze interaction patterns
        let totalInteractions = userData.dailyStats.reduce(0) { $0 + $1.interactions }
        if totalInteractions > 100 {
            insights.append(ActivityInsight(
                title: "Súper social",
                description: "Has realizado \(totalInteractions) interacciones en este período",
                icon: "person.2.fill",
                color: .blue
            ))
        }
        
        // Session frequency insight
        let totalSessions = userData.dailyStats.reduce(0) { $0 + $1.sessionCount }
        let averageSessionsPerDay = Double(totalSessions) / Double(userData.dailyStats.count)
        if averageSessionsPerDay > 3 {
            insights.append(ActivityInsight(
                title: "Usuario frecuente",
                description: "Abres la app un promedio de \(Int(averageSessionsPerDay)) veces al día",
                icon: "app.badge",
                color: .orange
            ))
        }
        
        return insights
    }
}

