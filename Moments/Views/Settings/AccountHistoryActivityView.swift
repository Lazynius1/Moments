import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AccountHistoryActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var history: [AccountHistoryItem] = []
    @State private var isLoading = true
    @State private var selectedFilter: AccountHistoryEventType? = nil // nil = All
    @State private var sortDescending: Bool = true // true = Newest first
    
    // Date Filtering
    @State private var dateFilter: AccountHistoryDateFilter = .all
    @State private var customDateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customDateTo: Date = Date()
    
    private enum AccountHistoryDateFilter: String, CaseIterable, Identifiable {
        case all, week, month, year, custom
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .all: return "userActivity.simple.filters.date.all"
            case .week: return "userActivity.simple.filters.date.week"
            case .month: return "userActivity.simple.filters.date.month"
            case .year: return "userActivity.simple.filters.date.year"
            case .custom: return "userActivity.simple.filters.date.custom"
            }
        }
    }
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                accountHistoryHeader
                
                if dateFilter == .custom {
                    customDateRangeControls
                }
                
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Title and Description
                            VStack(alignment: .center, spacing: 8) {
                                Text(NSLocalizedString("userActivity.accountHistory.title", value: "Información sobre el historial de la cuenta", comment: "Account history title"))
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .multilineTextAlignment(.center)
                                
                                Text(NSLocalizedString("userActivity.accountHistory.description", value: "Revisa los cambios que has hecho en tu cuenta desde que la creaste.", comment: "Description for Account History"))
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            
                            // Timeline View
                            let filteredHistory = getFilteredAndSortedHistory()
                            
                            if filteredHistory.isEmpty {
                                Text(NSLocalizedString("userActivity.accountHistory.noChanges", value: "No record of changes found.", comment: "No changes state for account history"))
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                                    .padding(.top, 40)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, item in
                                        AccountHistoryRowView(
                                            item: item,
                                            isFirst: index == 0,
                                            isLast: index == filteredHistory.count - 1
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("userActivity.accountHistory.title", value: "Historial de la cuenta", comment: "Account history title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                SettingsToolbarBackButton(action: { dismiss() })
            }
        }
        .onAppear {
            fetchHistory()
        }
    }
    
    private var accountHistoryHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sorting Menu
                Menu {
                    Button {
                        sortDescending = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("accountHistory.filter.newest", value: "Más recientes", comment: ""))
                            if sortDescending { Image(systemName: "checkmark") }
                        }
                    }
                    Button {
                        sortDescending = false
                    } label: {
                        HStack {
                            Text(NSLocalizedString("accountHistory.filter.oldest", value: "Más antiguos", comment: ""))
                            if !sortDescending { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.sort", value: "Ordenar por", comment: "Sort filter title"),
                        value: sortDescending ? NSLocalizedString("accountHistory.filter.newest", value: "Más recientes", comment: "") : NSLocalizedString("accountHistory.filter.oldest", value: "Más antiguos", comment: "")
                    )
                }
                
                // Date Menu
                Menu {
                    ForEach(AccountHistoryDateFilter.allCases) { option in
                        Button {
                            dateFilter = option
                        } label: {
                            HStack {
                                Text(NSLocalizedString(option.titleKey, comment: ""))
                                if dateFilter == option { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.date", value: "Fecha", comment: ""),
                        value: NSLocalizedString(dateFilter.titleKey, comment: "")
                    )
                }
                
                // Type Menu
                Menu {
                    Button {
                        selectedFilter = nil
                    } label: {
                        HStack {
                            Text(NSLocalizedString("accountHistory.filter.all", value: "Todos", comment: ""))
                            if selectedFilter == nil { Image(systemName: "checkmark") }
                        }
                    }
                    
                    ForEach(AccountHistoryEventType.allCases, id: \.self) { type in
                        Button {
                            selectedFilter = type
                        } label: {
                            HStack {
                                Text(type.localizedName)
                                if selectedFilter == type { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: NSLocalizedString("userActivity.simple.filters.type", value: "Tipo", comment: "Type filter title"),
                        value: selectedFilter?.localizedName ?? NSLocalizedString("accountHistory.filter.all", value: "Todos", comment: "")
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }
    
    private var customDateRangeControls: some View {
        HStack(spacing: 8) {
            DatePicker(
                NSLocalizedString("userActivity.simple.filters.from", value: "Desde", comment: "From date"),
                selection: $customDateFrom,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            )

            DatePicker(
                NSLocalizedString("userActivity.simple.filters.to", value: "Hasta", comment: "To date"),
                selection: $customDateTo,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
                    .overlay(
                        Capsule()
                            .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private func filterChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.custom("Poppins-Medium", size: 11))
                .foregroundColor(.gray)
            Text(value)
                .font(.custom("Poppins-SemiBold", size: 12))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(colorScheme == .dark ? .white : .black).opacity(0.07))
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                )
        )
    }
    
    private func getFilteredAndSortedHistory() -> [AccountHistoryItem] {
        var filtered = history
        
        // Filter by Type
        if let filter = selectedFilter {
            filtered = filtered.filter { $0.type == filter }
        }
        
        // Filter by Date
        let now = Date()
        let calendar = Calendar.current
        
        filtered = filtered.filter { item in
            switch dateFilter {
            case .all:
                return true
            case .week:
                let startOfWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return item.timestamp >= startOfWeek
            case .month:
                let startOfMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                return item.timestamp >= startOfMonth
            case .year:
                let startOfYear = calendar.date(byAdding: .year, value: -1, to: now) ?? now
                return item.timestamp >= startOfYear
            case .custom:
                let start = calendar.startOfDay(for: min(customDateFrom, customDateTo))
                let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customDateFrom, customDateTo))) ?? now
                return item.timestamp >= start && item.timestamp < end
            }
        }
        
        // Sort
        return filtered.sorted { 
            sortDescending ? ($0.timestamp > $1.timestamp) : ($0.timestamp < $1.timestamp)
        }
    }
    
    private func fetchHistory() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                var fetchedItems = try await FirestoreService.shared.fetchAccountHistory(userId: userId)
                
                // If there is no join event, create a synthetic one based on the current user creation details fallback
                if !fetchedItems.contains(where: { $0.type == .join }) {
                    let db = Firestore.firestore()
                    let doc = try await db.collection("users").document(userId).getDocument()
                    var joinDate = Date()
                    if let data = doc.data(), let stamp = data["createdAt"] as? Timestamp {
                        joinDate = stamp.dateValue()
                    } else if let authCreationDate = Auth.auth().currentUser?.metadata.creationDate {
                        joinDate = authCreationDate
                    }
                    
                    fetchedItems.append(AccountHistoryItem(
                        id: "synthetic-\(userId)-join",
                        type: .join,
                        oldValue: nil,
                        newValue: nil,
                        timestamp: joinDate
                    ))
                }
                
                self.history = fetchedItems
                self.isLoading = false
                
            } catch {
                print("❌ Error fetching account history: \(error)")
                self.isLoading = false
            }
        }
    }
}

struct AccountHistoryRowView: View {
    let item: AccountHistoryItem
    let isFirst: Bool
    let isLast: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line & dot
            VStack(spacing: 0) {
                // Top line
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.gray.opacity(0.3))
                    .frame(width: 2, height: 16)
                
                // Timeline dot
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    Image(systemName: item.type.icon)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                // Bottom line
                Rectangle()
                    .fill(isLast ? Color.clear : Color.gray.opacity(0.3))
                    .frame(width: 2) // height is implicit to fill space
            }
            .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(item.type.localizedName)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(dateString)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
                
                if let oldValue = item.oldValue, let newValue = item.newValue {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text("De:")
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(Color(hex: "F97316"))
                            Text(oldValue)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(3)
                        }
                        HStack(alignment: .top) {
                            Text("A:")
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(SettingsProfileColors.accent(colorScheme))
                            Text(newValue)
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(3)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.all, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.top, 12) // Align text reasonably with the dot
            .padding(.bottom, 32) // Space before next item
            
            Spacer()
        }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: item.timestamp)
    }
}
