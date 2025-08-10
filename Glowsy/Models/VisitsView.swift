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
    
    // ✅ Tiempo desde la última visita de forma inteligente
    var timeDescription: String {
        let interval = Date().timeIntervalSince(lastVisit)
        
        if visitCount == 1 {
            // Una sola visita
            if interval < 60 {
                return "Visitó hace un momento"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "Visitó hace \(minutes) min"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "Visitó hace \(hours)h"
            } else {
                let days = Int(interval / 86400)
                return "Visitó hace \(days)d"
            }
        } else {
            // Múltiples visitas
            if interval < 60 {
                return "Última visita: hace un momento (\(visitCount) veces)"
            } else if interval < 3600 {
                let minutes = Int(interval / 60)
                return "Última visita: hace \(minutes) min (\(visitCount) veces)"
            } else if interval < 86400 {
                let hours = Int(interval / 3600)
                return "Última visita: hace \(hours)h (\(visitCount) veces)"
            } else {
                let days = Int(interval / 86400)
                return "Última visita: hace \(days)d (\(visitCount) veces)"
            }
        }
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

// ✅ VISTA PRINCIPAL: VisitsView SIN overlay grisáceo
struct VisitsView: View {
    @StateObject private var viewModel = VisitsViewModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Spacer()
            
            // ✅ Contenedor principal con el mismo estilo que ContextMenu
            VStack(spacing: 0) {
                // ✅ Handle superior igual que ContextMenu
                handleView
                
                // ✅ Header con título
                headerView
                
                // ✅ Contenido principal
                contentView
                
                // ✅ Botón cerrar en la parte inferior
                cancelButton
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color(hex: "00A896").opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
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
    
    // Sección de stalkers (sin cambios)
    private var stalkerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🕵️ Visitantes Frecuentes")
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Text("\(viewModel.stalkerAnalysis.count)")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.6))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.stalkerAnalysis, id: \.userId) { analysis in
                        StalkerCard(analysis: analysis, colorScheme: colorScheme)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 20)
    }
    
    // ✅ ACTUALIZADO: Header con contador de visitantes únicos
    private var visitsHeader: some View {
        HStack {
            Text("📋 Visitantes")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Text("\(viewModel.groupedVisits.count)")
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "00A896").opacity(0.6))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

// ✅ NUEVA: Row de visita agrupada
struct GroupedVisitRow: View {
    let groupedVisit: GroupedVisit
    let colorScheme: ColorScheme
    @State private var showProfile = false
    @State private var showExpandedVisits = false

    var body: some View {
        VStack(spacing: 0) {
            // Row principal
            Button(action: { showProfile = true }) {
                HStack(spacing: 16) {
                    // Avatar con badge
                    ZStack {
                        AsyncImage(url: URL(string: groupedVisit.user.profileImagePath ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: groupedVisit.frequencyType == .normal ?
                                                [Color(hex: "00A896"), colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.3)] :
                                                [groupedVisit.frequencyType.color, groupedVisit.frequencyType.color.opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: groupedVisit.frequencyType == .normal ? 2 : 3
                                        )
                                )
                        } placeholder: {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.gray.opacity(0.6))
                                )
                                .overlay(ProgressView().tint(Color(hex: "00A896")))
                        }
                        
                        // Badge de stalker
                        if groupedVisit.frequencyType != .normal {
                            Text(groupedVisit.frequencyType.badge)
                                .font(.system(size: 16))
                                .background(
                                    Circle()
                                        .fill(groupedVisit.frequencyType.color)
                                        .frame(width: 24, height: 24)
                                )
                                .offset(x: 20, y: -20)
                        }
                        
                        // ✅ NUEVO: Indicador de visitas múltiples
                        if groupedVisit.visitCount > 1 {
                            Text("\(groupedVisit.visitCount)")
                                .font(.custom("Poppins-Bold", size: 10))
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color(hex: "00A896"))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                                .offset(x: -20, y: 20)
                        }
                        
                        // ✅ NUEVO: Indicador de visita reciente (pulsing)
                        if groupedVisit.isRecent {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .offset(x: 22, y: 22)
                                .opacity(0.8)
                                .scaleEffect(1.0)
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: groupedVisit.isRecent)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(groupedVisit.user.username)
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                // ✅ INSIGNIA DE VERIFICADO
                                VerifiedBadgeView(userId: groupedVisit.user.id, size: 12)
                            }
                            
                            // Mensaje de frecuencia
                            if groupedVisit.frequencyType != .normal {
                                Text(groupedVisit.frequencyType.message)
                                    .font(.custom("Poppins-Medium", size: 10))
                                    .foregroundColor(groupedVisit.frequencyType.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(groupedVisit.frequencyType.color.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text(groupedVisit.timeDescription)
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(colorScheme == .dark ? .gray.opacity(0.8) : .gray.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        // ✅ NUEVO: Botón para expandir si hay múltiples visitas
                        if groupedVisit.visitCount > 1 {
                            Button(action: {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showExpandedVisits.toggle()
                                }
                            }) {
                                Image(systemName: showExpandedVisits ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "00A896"))
                                    .frame(width: 24, height: 24)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .gray.opacity(0.6) : .gray.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(PlainButtonStyle())
            
            // ✅ NUEVO: Lista expandible de visitas individuales
            if showExpandedVisits && groupedVisit.visitCount > 1 {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal, 20)
                    
                    ForEach(Array(groupedVisit.visits.prefix(5).enumerated()), id: \.element.id) { index, visit in
                        HStack {
                            Circle()
                                .fill(Color(hex: "00A896").opacity(0.6))
                                .frame(width: 6, height: 6)
                            
                            Text(timeAgoString(from: visit.timestamp))
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(colorScheme == .dark ? .gray.opacity(0.7) : .gray.opacity(0.6))
                            
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    // Mostrar "y X más" si hay más de 5 visitas
                    if groupedVisit.visitCount > 5 {
                        HStack {
                            Text("... y \(groupedVisit.visitCount - 5) más")
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(colorScheme == .dark ? .gray.opacity(0.6) : .gray.opacity(0.5))
                                .italic()
                            
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: groupedVisit.frequencyType == .normal ? [
                            colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1),
                            Color(hex: "00A896").opacity(0.3)
                        ] : [
                            groupedVisit.frequencyType.color.opacity(0.4),
                            groupedVisit.frequencyType.color.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: groupedVisit.frequencyType == .normal ?
            (colorScheme == .dark ? .black.opacity(0.1) : .gray.opacity(0.2)) :
            groupedVisit.frequencyType.color.opacity(0.3),
            radius: 8,
            x: 0,
            y: 4
        )
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: groupedVisit.user.id)
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Hace un momento"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "Hace \(minutes) min"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "Hace \(hours)h"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "Hace \(days)d"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM"
            return formatter.string(from: date)
        }
    }
}

// ✅ ACTUALIZADO: VisitsViewModel con agrupación
class VisitsViewModel: ObservableObject {
    @Published var groupedVisits: [GroupedVisit] = [] // ✅ CAMBIO: visitas agrupadas
    @Published var stalkerAnalysis: [VisitorAnalysis] = []
    @Published var isLoading: Bool = true
    @Published var showStalkerAlert: Bool = false
    @Published var detectedStalker: VisitorAnalysis?
    
    private let firestoreService = FirestoreService()
    private var listener: ListenerRegistration?
    
    func fetchVisits() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No hay usuario autenticado")
            self.isLoading = false
            return
        }

        print("🔍 Cargando visitas para usuario: \(userId)")
        
        listener?.remove()
        listener = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("visits")
            .order(by: "timestamp", descending: true)
            .limit(to: 200) // ✅ Aumentamos el límite para mejor agrupación
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error al cargar visitas: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                    return
                }

                guard let documents = snapshot?.documents else {
                    print("📭 No hay documentos de visitas")
                    DispatchQueue.main.async {
                        self.groupedVisits = []
                        self.isLoading = false
                    }
                    return
                }
                
                print("📊 Encontrados \(documents.count) documentos de visitas")

                // Decodificar visitas
                let visits = documents.compactMap { doc -> Visit? in
                    do {
                        let visit = try doc.data(as: Visit.self)
                        return visit
                    } catch {
                        print("❌ Error al decodificar visita \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                }
                
                print("✅ Total de visitas válidas: \(visits.count)")

                // Obtener visitantes únicos
                let uniqueVisitorIds = Array(Set(visits.map { $0.visitorId }))
                print("👥 Visitantes únicos: \(uniqueVisitorIds.count)")

                guard !uniqueVisitorIds.isEmpty else {
                    DispatchQueue.main.async {
                        self.groupedVisits = []
                        self.stalkerAnalysis = []
                        self.isLoading = false
                    }
                    return
                }

                // Obtener perfiles de usuarios
                self.firestoreService.fetchUsers(userIds: uniqueVisitorIds) { result in
                    switch result {
                    case .success(let users):
                        print("👤 Usuarios obtenidos: \(users.count)")
                        let userDict = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })

                        // ✅ NUEVA LÓGICA: Agrupar visitas por usuario
                        var groupedByUser: [String: [Visit]] = [:]
                        for visit in visits {
                            if groupedByUser[visit.visitorId] == nil {
                                groupedByUser[visit.visitorId] = []
                            }
                            groupedByUser[visit.visitorId]?.append(visit)
                        }
                        
                        // Crear GroupedVisit para cada usuario
                        let groupedVisits = groupedByUser.compactMap { (userId, userVisits) -> GroupedVisit? in
                            guard let user = userDict[userId] else {
                                print("⚠️ Usuario no encontrado para userId: \(userId)")
                                return nil
                            }
                            
                            return GroupedVisit(user: user, visits: userVisits)
                        }
                        
                        // Ordenar por última visita (más reciente primero)
                        let sortedGroupedVisits = groupedVisits.sorted { $0.lastVisit > $1.lastVisit }

                        DispatchQueue.main.async {
                            self.groupedVisits = sortedGroupedVisits
                            self.isLoading = false
                            print("✅ Vista actualizada con \(sortedGroupedVisits.count) grupos de visitas")
                            
                            // Analizar stalkers
                            self.analyzeStalkers(allVisits: visits, userDict: userDict)
                        }
                        
                    case .failure(let error):
                        print("❌ Error al cargar usuarios: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.groupedVisits = []
                            self.isLoading = false
                        }
                    }
                }
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

    deinit {
        listener?.remove()
    }
}

// ✅ COMPONENTES AUXILIARES (sin cambios pero adaptados)
struct StalkerCard: View {
    let analysis: VisitorAnalysis
    let colorScheme: ColorScheme
    @State private var showProfile = false
    
    var body: some View {
        Button(action: { showProfile = true }) {
            VStack(spacing: 8) {
                ZStack {
                    AsyncImage(url: URL(string: analysis.profileImagePath ?? "")) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
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
                    
                    Text("\(analysis.visitsLast24h) visitas")
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
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: analysis.userId)
        }
    }
}

struct StalkerAlertView: View {
    let stalker: VisitorAnalysis
    @Binding var isPresented: Bool
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🕵️ ¡Tienes un stalker!")
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
                
                Text("Ha visitado tu perfil \(stalker.visitsLast24h) veces en las últimas 24 horas")
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
            
            Button("¡Entendido! 😏") {
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
            
            Text("Cargando visitas...")
                .font(.custom("Poppins-Medium", size: 16))
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
                Text("No hay visitas aún")
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Cuando otros usuarios vean tu perfil, aparecerán aquí")
                    .font(.custom("Poppins-Regular", size: 16))
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
    // ✅ Handle superior idéntico al ContextMenu
    private var handleView: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.white.opacity(0.4))
            .frame(width: 40, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 20)
    }
    
    // ✅ Header simplificado como el ContextMenu
    private var headerView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("Visitas")
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("\(viewModel.groupedVisits.count) \(viewModel.groupedVisits.count == 1 ? "visitante" : "visitantes")")
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
    
    private var contentView: some View {
        Group {
            if viewModel.isLoading {
                VisitModernLoadingView(colorScheme: colorScheme)
            } else if viewModel.groupedVisits.isEmpty {
                ModernEmptyVisitsView(colorScheme: colorScheme)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Sección de stalkers si existen
                        if !viewModel.stalkerAnalysis.isEmpty {
                            stalkerSection
                        }
                        
                        // Header de visitas con contador
                        visitsHeader
                        
                        // ✅ NUEVA: Lista de visitas agrupadas
                        ForEach(viewModel.groupedVisits) { groupedVisit in
                            GroupedVisitRow(
                                groupedVisit: groupedVisit,
                                colorScheme: colorScheme
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // ✅ Botón cancelar en la parte inferior
    private var cancelButton: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.3)) {
                dismiss()
            }
        }) {
            Text("Cerrar")
                .font(.custom("Poppins-SemiBold", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}
