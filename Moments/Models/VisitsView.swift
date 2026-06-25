import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// ✅ MODELO: Visit actualizado
struct Visit: Identifiable, Codable {
    @DocumentID var id: String?
    let visitorId: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case visitorId
        case timestamp
    }
    
    init(visitorId: String, timestamp: Date) {
        self.id = nil
        self.visitorId = visitorId
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.visitorId = try container.decode(String.self, forKey: .visitorId)
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .timestamp) {
            self.timestamp = timestamp.dateValue()
        } else if let date = try? container.decode(Date.self, forKey: .timestamp) {
            self.timestamp = date
        } else {
            throw DecodingError.typeMismatch(Date.self, DecodingError.Context(
                codingPath: container.codingPath + [CodingKeys.timestamp],
                debugDescription: "No se pudo decodificar timestamp"
            ))
        }
        
        self._id = DocumentID(wrappedValue: nil)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visitorId, forKey: .visitorId)
        try container.encode(Timestamp(date: timestamp), forKey: .timestamp)
    }
}

// ✅ NUEVO: Estructura para visitas agrupadas
struct GroupedVisit: Identifiable {
    let id: String
    let user: AppUser
    let visits: [Visit] // Array de todas las visitas del usuario
    let lastVisit: Date // Última visita para ordenar
    let visitCount: Int // Total de visitas
    let isRecent: Bool // Si la última visita fue en los últimos 30 minutos
    let frequencyType: VisitorFrequencyType
    
    init(user: AppUser, visits: [Visit]) {
        self.id = user.id
        self.user = user
        self.visits = visits.sorted { $0.timestamp > $1.timestamp }
        self.lastVisit = self.visits.first?.timestamp ?? Date()
        self.visitCount = visits.count
        
        // Determinar si es reciente (últimos 30 minutos)
        let thirtyMinutesAgo = Calendar.current.date(byAdding: .minute, value: -30, to: Date()) ?? Date()
        self.isRecent = self.lastVisit >= thirtyMinutesAgo
        
        // Calcular frecuencia en las últimas 24h
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let recentVisitsCount = visits.filter { $0.timestamp >= oneDayAgo }.count
        
        switch recentVisitsCount {
        case 11...: self.frequencyType = .superStalker
        case 6...10: self.frequencyType = .stalker
        case 3...5: self.frequencyType = .frequent
        default: self.frequencyType = .normal
        }
    }
    
    var rowSubtitle: String {
        let relative = relativeLastVisitText
        guard visitCount > 1 else { return relative }
        return "\(relative) · \(visitCount)×"
    }

    private var relativeLastVisitText: String {
        let interval = Date().timeIntervalSince(lastVisit)

        if interval < 60 {
            return NSLocalizedString("visits.time.justNow", comment: "")
        }
        if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return String(format: NSLocalizedString("visits.time.minutesAgo", comment: ""), minutes)
        }
        if interval < 86_400 {
            let hours = max(1, Int(interval / 3600))
            return String(format: NSLocalizedString("visits.time.hoursAgo", comment: ""), hours)
        }
        if interval < 604_800 {
            let days = max(1, Int(interval / 86_400))
            return String(format: NSLocalizedString("visits.time.daysAgo", comment: ""), days)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: lastVisit)
    }

    // Legacy copy kept for older surfaces.
    var timeDescription: String {
        rowSubtitle
    }
}

// ✅ ENUM para tipos de visitantes frecuentes (sin cambios)
enum VisitorFrequencyType: Int, CaseIterable {
    case normal = 0
    case frequent = 1
    case stalker = 2
    case superStalker = 3
    
    var badge: String {
        switch self {
        case .normal: return ""
        case .frequent: return "👀"
        case .stalker: return "🕵️"
        case .superStalker: return "🔍👁️"
        }
    }
    
    var message: String {
        switch self {
        case .normal: return ""
        case .frequent: return "Visitante frecuente"
        case .stalker: return "¡Alguien está interesado! 😏"
        case .superStalker: return "¡Tu fan número 1! 🌟"
        }
    }
    
    var color: Color {
        switch self {
        case .normal: return .clear
        case .frequent: return .blue.opacity(0.6)
        case .stalker: return .orange.opacity(0.6)
        case .superStalker: return .red.opacity(0.6)
        }
    }
}

// ✅ ESTRUCTURA: VisitorAnalysis (sin cambios)
struct VisitorAnalysis {
    let userId: String
    let username: String
    let profileImagePath: String?
    let totalVisits: Int
    let visitsLast24h: Int
    let visitsLastWeek: Int
    let frequencyType: VisitorFrequencyType
    let lastVisit: Date
    let firstVisit: Date
    
    var daysSinceFirstVisit: Int {
        Calendar.current.dateComponents([.day], from: firstVisit, to: Date()).day ?? 0
    }
}

enum VisitGrouping {
    static func build(visits: [Visit], users: [AppUser]) -> [GroupedVisit] {
        let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        var groupedByUser: [String: [Visit]] = [:]

        for visit in visits {
            groupedByUser[visit.visitorId, default: []].append(visit)
        }

        return groupedByUser.compactMap { userId, userVisits -> GroupedVisit? in
            guard let user = userDict[userId] else { return nil }
            return GroupedVisit(user: user, visits: userVisits)
        }
        .sorted { $0.lastVisit > $1.lastVisit }
    }

    static func uniqueVisitorIds(from visits: [Visit]) -> [String] {
        Array(Set(visits.map(\.visitorId)))
    }
}

// MARK: - Embedded visits tab (SocialConnectionsView)

struct VisitsTabContent<VM: UserListViewModel>: View {
    let groupedVisits: [GroupedVisit]
    let isLoading: Bool
    let listViewModel: VM
    let searchText: String
    var sortMode: SocialConnectionsSortMode = .default
    let colorScheme: ColorScheme
    var profileZoomNamespace: Namespace.ID? = nil
    let onUserTap: (String) -> Void
    var onAvatarTap: ((String, Bool) -> Void)? = nil

    private var filteredVisits: [GroupedVisit] {
        let base: [GroupedVisit]
        if searchText.isEmpty {
            base = groupedVisits
        } else {
            base = groupedVisits.filter {
                $0.user.username.localizedCaseInsensitiveContains(searchText) ||
                ($0.user.bio?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return SocialConnectionsSorting.sortVisits(base, mode: sortMode)
    }

    var body: some View {
        Group {
            if isLoading {
                VisitsTabSkeletonView(colorScheme: colorScheme)
            } else if groupedVisits.isEmpty {
                ModernEmptyVisitsView(colorScheme: colorScheme)
            } else if filteredVisits.isEmpty {
                SocialConnectionsNoResultsView(colorScheme: colorScheme)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredVisits) { groupedVisit in
                            GroupedVisitRow(
                                groupedVisit: groupedVisit,
                                colorScheme: colorScheme,
                                profileZoomNamespace: profileZoomNamespace,
                                listViewModel: listViewModel,
                                onUserTap: onUserTap,
                                onAvatarTap: onAvatarTap
                            )
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// Legacy sheet wrapper (deprecated)
struct VisitsView: View {
    @StateObject private var viewModel = VisitsViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var showSpecificUserStories = false
    @State private var selectedStoryUserId = ""

    var body: some View {
        VStack(spacing: 0) {
            headerView
            VisitsTabContent(
                groupedVisits: viewModel.groupedVisits,
                isLoading: viewModel.isLoading,
                listViewModel: EmptyUserListViewModel(),
                searchText: "",
                colorScheme: colorScheme,
                onUserTap: { userId in
                    LegacyNavigationBridge.profile(userId: userId)
                },
                onAvatarTap: handleAvatarTap
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showSpecificUserStories, onDismiss: {
            selectedStoryUserId = ""
        }) {
            StoriesView(startAtUserId: selectedStoryUserId)
                .environmentObject(FirestoreService.shared)
                .ignoresSafeArea(.keyboard)
        }
        .overlay(
            Group {
                if viewModel.showStalkerAlert, let stalker = viewModel.detectedStalker {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                        .onTapGesture {
                            viewModel.showStalkerAlert = false
                        }
                        .overlay(
                            StalkerAlertView(
                                stalker: stalker,
                                isPresented: $viewModel.showStalkerAlert,
                                colorScheme: colorScheme
                            )
                        )
                }
            }
        )
        .onAppear {
            viewModel.fetchVisits()
        }
    }

    private func handleAvatarTap(userId: String, hasStory: Bool) {
        SocialConnectionAvatarTapRouting.route(
            userId: userId,
            hasStory: hasStory,
            openProfile: { LegacyNavigationBridge.profile(userId: $0) },
            openStories: { userId in
                selectedStoryUserId = userId
                showSpecificUserStories = true
            }
        )
    }
}

struct VisitsRelationshipButton<VM: UserListViewModel>: View {
    let user: AppUser
    let viewModel: VM
    let colorScheme: ColorScheme

    @State private var followState: FollowButtonState = .canFollow
    @State private var isFollowLoading = false
    @State private var showingUnfollowConfirmation = false

    var body: some View {
        Group {
            if followState != .ownProfile {
                ModernFollowButton(
                    state: followState,
                    isLoading: isFollowLoading,
                    colorScheme: colorScheme,
                    action: performRelationshipAction
                )
            }
        }
        .onAppear {
            refreshFollowState()
            viewModel.prefetchRelationshipState(for: user.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: FollowStateStore.didChangeNotification)) { notification in
            guard let changedUserId = notification.userInfo?["userId"] as? String,
                  changedUserId == user.id else { return }
            refreshFollowState()
        }
        .confirmationDialog(
            NSLocalizedString("userProfile.unfollow.confirm.title", comment: ""),
            isPresented: $showingUnfollowConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("userProfile.unfollow.confirm.action", comment: ""), role: .destructive) {
                viewModel.unfollowUser(userId: user.id)
                FollowStateStore.shared.setState(.canFollow, for: user.id)
                refreshFollowState()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("userProfile.unfollow.confirm.message", comment: ""))
        }
    }

    private func refreshFollowState() {
        followState = viewModel.relationshipState(for: user.id)
    }

    private func performRelationshipAction() {
        guard !isFollowLoading else { return }

        switch followState {
        case .following:
            showingUnfollowConfirmation = true
        case .canFollow, .canRequestFollow:
            isFollowLoading = true
            viewModel.followUser(userId: user.id)
            let nextState: FollowButtonState = followState == .canRequestFollow ? .requestPendingCancellable : .following
            FollowStateStore.shared.setState(nextState, for: user.id)
            followState = nextState
            isFollowLoading = false
        case .requestPendingCancellable:
            viewModel.cancelFollowRequest(userId: user.id)
            FollowStateStore.shared.setState(.canRequestFollow, for: user.id)
            refreshFollowState()
        case .ownProfile, .blocked, .requestPending:
            break
        }
    }
}

// Row minimalista alineada con las listas sociales.
struct GroupedVisitRow<VM: UserListViewModel>: View {
    let groupedVisit: GroupedVisit
    let colorScheme: ColorScheme
    var profileZoomNamespace: Namespace.ID? = nil
    var listViewModel: VM? = nil
    var onUserTap: ((String) -> Void)? = nil
    var onAvatarTap: ((String, Bool) -> Void)? = nil
    @State private var isPressed = false
    @Namespace private var fallbackZoomNamespace

    private var zoomNamespace: Namespace.ID {
        profileZoomNamespace ?? fallbackZoomNamespace
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)
    }

    var body: some View {
        HStack(spacing: SocialConnectionRowMetrics.contentSpacing) {
            StoryRingAvatarView(
                userId: groupedVisit.user.id,
                size: SocialConnectionRowMetrics.avatarSize,
                lineWidth: 2.2,
                showBaseStroke: true,
                baseStrokeColor: colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                baseStrokeWidth: 0.9,
                profileZoomNamespace: zoomNamespace,
                onTap: handleAvatarTap
            )

            userInfoSection

            Spacer(minLength: 4)

            if let listViewModel {
                VisitsRelationshipButton(
                    user: groupedVisit.user,
                    viewModel: listViewModel,
                    colorScheme: colorScheme
                )
            }
        }
        .padding(.horizontal, SocialConnectionRowMetrics.horizontalPadding)
        .padding(.vertical, SocialConnectionRowMetrics.verticalPadding)
    }

    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: SocialConnectionRowMetrics.textLineSpacing) {
            HStack(spacing: 4) {
                Text(groupedVisit.user.username)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                if groupedVisit.user.isVerified {
                    VerifiedBadge(size: 13)
                }

                if groupedVisit.isRecent {
                    Circle()
                        .fill(Color(hex: "00A896"))
                        .frame(width: 6, height: 6)
                }
            }

            Text(groupedVisit.rowSubtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (colorScheme == .dark ? Color.white : Color.black)
                .opacity(isPressed ? 0.06 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { onUserTap?(groupedVisit.user.id) }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }

    private func handleAvatarTap(hasStory: Bool) {
        if let onAvatarTap {
            onAvatarTap(groupedVisit.user.id, hasStory)
            return
        }

        if hasStory {
            return
        }

        onUserTap?(groupedVisit.user.id)
    }
}

// ✅ ACTUALIZADO: VisitsViewModel con agrupación
class VisitsViewModel: ObservableObject {
    @Published var groupedVisits: [GroupedVisit] = []
    @Published var stalkerAnalysis: [VisitorAnalysis] = []
    @Published var isLoading: Bool = true
    @Published var showStalkerAlert: Bool = false
    @Published var detectedStalker: VisitorAnalysis?

    func fetchVisits() {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        isLoading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }

            let grouped = await ProfileVisitsService.shared.fetchGroupedVisits(userId: userId)
            self.groupedVisits = grouped

            let userDict = Dictionary(uniqueKeysWithValues: grouped.map { ($0.user.id, $0.user) })
            let allVisits = grouped.flatMap(\.visits)
            self.analyzeStalkers(allVisits: allVisits, userDict: userDict)
        }
    }

    // Análisis de stalkers (sin cambios)
    private func analyzeStalkers(allVisits: [Visit], userDict: [String: AppUser]) {
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        
        var visitorGroups: [String: [Visit]] = [:]
        for visit in allVisits {
            if visitorGroups[visit.visitorId] == nil {
                visitorGroups[visit.visitorId] = []
            }
            visitorGroups[visit.visitorId]?.append(visit)
        }
        
        var analyses: [VisitorAnalysis] = []
        
        for (visitorId, visits) in visitorGroups {
            guard visits.count >= 3, let user = userDict[visitorId] else { continue }
            
            let sortedVisits = visits.sorted { $0.timestamp < $1.timestamp }
            let visitsLast24h = visits.filter { $0.timestamp >= oneDayAgo }.count
            let visitsLastWeek = visits.filter { $0.timestamp >= oneWeekAgo }.count
            
            let frequencyType = getFrequencyType(for: visitsLast24h)
            guard frequencyType != .normal else { continue }
            
            let analysis = VisitorAnalysis(
                userId: visitorId,
                username: user.username,
                profileImagePath: user.profileImagePath,
                totalVisits: visits.count,
                visitsLast24h: visitsLast24h,
                visitsLastWeek: visitsLastWeek,
                frequencyType: frequencyType,
                lastVisit: sortedVisits.last?.timestamp ?? now,
                firstVisit: sortedVisits.first?.timestamp ?? now
            )
            analyses.append(analysis)
        }
        
        let sortedAnalyses = analyses.sorted { lhs, rhs in
            if lhs.frequencyType.rawValue == rhs.frequencyType.rawValue {
                return lhs.visitsLast24h > rhs.visitsLast24h
            }
            return lhs.frequencyType.rawValue > rhs.frequencyType.rawValue
        }
        
        DispatchQueue.main.async {
            self.stalkerAnalysis = sortedAnalyses
            
            if let superStalker = analyses.first(where: { $0.frequencyType == .superStalker }) {
                self.detectedStalker = superStalker
                self.showStalkerAlert = true
            }
        }
    }
    
    private func getFrequencyType(for visitCount: Int) -> VisitorFrequencyType {
        switch visitCount {
        case 11...: return .superStalker
        case 6...10: return .stalker
        case 3...5: return .frequent
        default: return .normal
        }
    }
}

// ✅ COMPONENTES AUXILIARES (sin cambios pero adaptados)
struct StalkerCard: View {
    let analysis: VisitorAnalysis
    let colorScheme: ColorScheme
    var profileZoomNamespace: Namespace.ID? = nil
    var onUserTap: ((String) -> Void)? = nil
    @Namespace private var fallbackZoomNamespace

    private var zoomNamespace: Namespace.ID {
        profileZoomNamespace ?? fallbackZoomNamespace
    }

    var body: some View {
        Button(action: { onUserTap?(analysis.userId) }) {
            VStack(spacing: 8) {
                ZStack {
                    AsyncImage(url: URL(string: analysis.profileImagePath ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            .userProfileZoomSource(
                                userId: analysis.userId,
                                namespace: zoomNamespace,
                                cornerRadius: 30
                            )
                            .overlay(
                                Circle()
                                    .stroke(analysis.frequencyType.color, lineWidth: 3)
                            )
                    } placeholder: {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    Text(analysis.frequencyType.badge)
                        .font(.system(size: 14))
                        .background(
                            Circle()
                                .fill(analysis.frequencyType.color)
                                .frame(width: 20, height: 20)
                        )
                        .offset(x: 25, y: -25)
                }
                
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text(analysis.username)
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        // ✅ INSIGNIA DE VERIFICADO
                        VerifiedBadgeView(userId: analysis.userId, size: 8)
                    }
                    
                    Text(String(format: NSLocalizedString("visits.count", comment: ""), analysis.visitsLast24h))
                        .font(.custom("Poppins-Regular", size: 10))
                        .foregroundColor(analysis.frequencyType.color)
                }
            }
            .frame(width: 80)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(analysis.frequencyType.color.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: analysis.frequencyType.color.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StalkerAlertView: View {
    let stalker: VisitorAnalysis
    @Binding var isPresented: Bool
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            Text("visits.stalkerAlert.title")
                .font(.custom("Poppins-Bold", size: 24))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            AsyncImage(url: URL(string: stalker.profileImagePath ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.6), lineWidth: 3)
                    )
            } placeholder: {
                Circle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(stalker.username)
                        .font(.custom("Poppins-SemiBold", size: 20))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    // ✅ INSIGNIA DE VERIFICADO
                    VerifiedBadgeView(userId: stalker.userId, size: 16)
                }
                
                Text(String(format: NSLocalizedString("visits.stalkerAlert.message", comment: ""), stalker.visitsLast24h))
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(colorScheme == .dark ? .gray.opacity(0.8) : .gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Text(stalker.frequencyType.message)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(stalker.frequencyType.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(stalker.frequencyType.color.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            Button("common.understood") {
                isPresented = false
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(Color(hex: "00A896"))
            .clipShape(Capsule())
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .padding(20)
    }
}

struct VisitsVisitorSkeletonRow: View {
    let colorScheme: ColorScheme

    private var surfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
        HStack(spacing: SocialConnectionRowMetrics.contentSpacing) {
            Circle()
                .fill(surfaceColor)
                .frame(width: SocialConnectionRowMetrics.avatarSize, height: SocialConnectionRowMetrics.avatarSize)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(surfaceColor)
                    .frame(width: 132, height: 12)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(surfaceColor)
                    .frame(width: 88, height: 10)
            }

            Spacer(minLength: 4)

            Capsule()
                .fill(surfaceColor)
                .frame(width: 108, height: 34)
        }
        .padding(.horizontal, SocialConnectionRowMetrics.horizontalPadding)
        .padding(.vertical, SocialConnectionRowMetrics.verticalPadding)
    }
}

struct VisitsTabSkeletonView: View {
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    VisitsVisitorSkeletonRow(colorScheme: colorScheme)
                }
            }
            .padding(.bottom, 40)
        }
        .shimmering(active: true)
    }
}

private struct VisitsSkeletonShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0.55 + (sin(phase) * 0.15) : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
    }
}

private extension View {
    func shimmering(active: Bool) -> some View {
        modifier(VisitsSkeletonShimmerModifier(active: active))
    }
}

struct VisitModernLoadingView: View {
    let colorScheme: ColorScheme
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                            [Color(hex: "00A896"), Color.white] :
                            [Color(hex: "00A896"), Color.black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
            
            Text("visits.loading")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct ModernEmptyVisitsView: View {
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "00A896").opacity(0.4),
                                        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: "eye.slash.circle")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                            [Color(hex: "00A896"), Color.white.opacity(0.7)] :
                            [Color(hex: "00A896"), Color.black.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("visits.empty.title")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text("visits.empty.description")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .gray.opacity(0.8) : .gray.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

struct VisitsView_Previews: PreviewProvider {
    static var previews: some View {
        VisitsView()
    }
}

// ✅ COMPONENTES PARA VISITSVIEW CON EL MISMO ESTILO QUE USERLISTVIEW
extension VisitsView {

    // ✅ Header simplificado como el ContextMenu
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("visits.title")
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text(
                String(
                    format: NSLocalizedString(
                        viewModel.groupedVisits.count == 1 ? "visits.visitorCount.single" : "visits.visitorCount.multiple",
                        comment: ""
                    ),
                    viewModel.groupedVisits.count
                )
            )
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
    
    private var contentView: some View {
        VisitsTabContent(
            groupedVisits: viewModel.groupedVisits,
            isLoading: viewModel.isLoading,
            listViewModel: EmptyUserListViewModel(),
            searchText: "",
            colorScheme: colorScheme,
            onUserTap: { userId in
                LegacyNavigationBridge.profile(userId: userId)
            }
        )
    }
}
