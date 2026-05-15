import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation
import UIKit

// MARK: - SavedMomentsViewModel CORREGIDO
class SavedMomentsViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var savedMomentIds: [String] = []
    @Published var visibilityByMomentId: [String: Bool] = [:]
    @Published private(set) var mutedUserIds: Set<String> = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let firestoreService = FirestoreService()
    private let privacyService = PrivacyService.shared
    private var visibilityValidationToken = UUID()

    func loadSavedMoments(completion: @escaping (Error?) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }

        isLoading = true
        error = nil
        firestoreService.fetchMutedUserIds(userId: userId) { [weak self] mutedIds in
            DispatchQueue.main.async {
                self?.mutedUserIds = mutedIds
            }
        }
        
        // Cargar los IDs de momentos guardados primero
        firestoreService.db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.error = error
                        self.isLoading = false
                        completion(error)
                    }
                    return
                }
                
                let savedDocuments = snapshot?.documents ?? []
                let momentIds = savedDocuments.compactMap { $0.documentID }
                
                DispatchQueue.main.async {
                    self.savedMomentIds = momentIds
                }
                
                // Si no hay momentos guardados
                guard !momentIds.isEmpty else {
                    DispatchQueue.main.async {
                        self.moments = []
                        self.visibilityByMomentId = [:]
                        self.isLoading = false
                        completion(nil)
                    }
                    return
                }
                
                // ✅ BUSCAR MOMENTOS SIN FILTROS DE PRIVACIDAD
                self.fetchSavedMomentsDirectly(momentIds: momentIds, completion: completion)
            }
    }
    
    // ✅ NUEVA FUNCIÓN: Buscar momentos guardados directamente sin filtros de privacidad
    private func fetchSavedMomentsDirectly(momentIds: [String], completion: @escaping (Error?) -> Void) {
        let group = DispatchGroup()
        var foundMoments: [Moment] = []
        var notFoundMomentIds: [String] = []
        let syncQueue = DispatchQueue(label: "saved.moments.direct.sync")
        
        
        // Obtener usuarios activos para buscar
        fetchActiveUsers { [weak self] userIds in
            guard let self = self else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Self deallocated"]))
                return
            }
            
            for userId in userIds {
                group.enter()
                
                // Buscar momentos de este usuario
                self.fetchMomentsFromUser(userId: userId) { userMoments in
                    defer { group.leave() }
                    
                    // Filtrar solo los momentos que están en nuestros guardados
                    let matchingMoments = userMoments.filter { moment in
                        guard let momentId = moment.id else { return false }
                        return momentIds.contains(momentId)
                    }
                    
                    if !matchingMoments.isEmpty {
                        syncQueue.async {
                            foundMoments.append(contentsOf: matchingMoments)
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                // Identificar momentos no encontrados para limpieza
                let foundMomentIds = Set(foundMoments.compactMap { $0.id })
                notFoundMomentIds = momentIds.filter { !foundMomentIds.contains($0) }
                
                // Limpiar momentos que ya no existen
                if !notFoundMomentIds.isEmpty {
                    self.cleanupMissingMoments(missingIds: notFoundMomentIds)
                }
                
                // Ordenar por timestamp
                let sortedMoments = foundMoments.sorted { $0.timestamp > $1.timestamp }
                
                self.moments = sortedMoments
                self.validateVisibilityForLoadedMoments(sortedMoments)
                self.isLoading = false
                completion(nil)
            }
        }
    }
    
    // ✅ FUNCIÓN AUXILIAR: Obtener momentos de un usuario específico
    private func fetchMomentsFromUser(userId: String, completion: @escaping ([Moment]) -> Void) {
        firestoreService.fetchMoments(for: userId) { result in
            switch result {
            case .success(let moments):
                completion(moments)
            case .failure(let error):
                completion([])
            }
        }
    }
    
    // ✅ FUNCIÓN AUXILIAR: Obtener usuarios activos
    private func fetchActiveUsers(completion: @escaping ([String]) -> Void) {
        // Obtener usuarios que han estado activos en los últimos 6 meses
        let recentDate = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        
        firestoreService.db.collection("users")
            .whereField("lastActiveAt", isGreaterThan: Timestamp(date: recentDate))
            .limit(to: 100) // Aumentar límite para mejor cobertura
            .getDocuments { snapshot, error in
                if let error = error {
                    // Fallback: buscar en todos los usuarios (menos eficiente pero funcional)
                    self.fetchAllUsers(completion: completion)
                    return
                }
                
                let userIds = snapshot?.documents.compactMap { doc in
                    doc.documentID
                } ?? []
                
                
                if userIds.isEmpty {
                    // Fallback si no hay usuarios con lastActiveAt
                    self.fetchAllUsers(completion: completion)
                } else {
                    completion(userIds)
                }
            }
    }
    
    // ✅ FUNCIÓN FALLBACK: Obtener todos los usuarios
    private func fetchAllUsers(completion: @escaping ([String]) -> Void) {
        firestoreService.db.collection("users")
            .limit(to: 200)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion([])
                    return
                }
                
                let userIds = snapshot?.documents.compactMap { doc in
                    doc.documentID
                } ?? []
                
                completion(userIds)
            }
    }
    
    // ✅ FUNCIÓN DE LIMPIEZA: Remover momentos que ya no existen
    private func cleanupMissingMoments(missingIds: [String]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let group = DispatchGroup()
        
        for momentId in missingIds {
            group.enter()
            
            firestoreService.db.collection("users").document(userId)
                .collection("savedMoments").document(momentId)
                .delete { error in
                    if let error = error {
                    } else {
                    }
                    group.leave()
                }
        }
        
        group.notify(queue: .main) {
            // Actualizar IDs locales
            self.savedMomentIds.removeAll { missingIds.contains($0) }
        }
    }
    
    // MARK: - Public Methods
    func isMomentSaved(momentId: String) -> Bool {
        return savedMomentIds.contains(momentId)
    }

    func isMomentFromMutedUser(_ moment: Moment) -> Bool {
        mutedUserIds.contains(moment.authorId)
    }

    func removeMoment(momentId: String, completion: @escaping (Error?) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }

        
        firestoreService.toggleSaveMoment(userId: userId, momentId: momentId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(error)
                } else {
                    self?.moments.removeAll { $0.id == momentId }
                    self?.savedMomentIds.removeAll { $0 == momentId }
                    self?.visibilityByMomentId.removeValue(forKey: momentId)
                    completion(nil)
                }
            }
        }
    }
    
    func addSavedMoment(_ moment: Moment) {
        guard let momentId = moment.id else { return }
        
        if !savedMomentIds.contains(momentId) {
            savedMomentIds.append(momentId)
            visibilityByMomentId[momentId] = true
            
            if !moments.contains(where: { $0.id == momentId }) {
                moments.append(moment)
                moments.sort { $0.timestamp > $1.timestamp }
            }
        }
    }

    func refreshVisibilityForMoment(_ moment: Moment, completion: ((Bool) -> Void)? = nil) {
        guard let momentId = moment.id,
              let viewerId = Auth.auth().currentUser?.uid else {
            completion?(false)
            return
        }

        privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { [weak self] canView in
            DispatchQueue.main.async {
                self?.visibilityByMomentId[momentId] = canView
                completion?(canView)
            }
        }
    }
    
    // MARK: - Debug Methods
    func debugSavedMoments() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        firestoreService.db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { snapshot, error in
                if let error = error {
                    return
                }
                
                let docs = snapshot?.documents ?? []
                
                docs.forEach { doc in
                }
            }
    }
    
    func forceRefresh() {
        moments = []
        savedMomentIds = []
        visibilityByMomentId = [:]
        loadSavedMoments()
    }

    private func validateVisibilityForLoadedMoments(_ moments: [Moment]) {
        guard let viewerId = Auth.auth().currentUser?.uid else {
            return
        }

        let token = UUID()
        visibilityValidationToken = token

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "saved.moments.visibility.sync")
        var result: [String: Bool] = [:]

        for moment in moments {
            guard let momentId = moment.id else { continue }
            group.enter()
            privacyService.canUserViewMomentEnhanced(moment, viewerId: viewerId) { canView in
                queue.async {
                    result[momentId] = canView
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.visibilityValidationToken == token else { return }
            self.visibilityByMomentId = result
        }
    }
}

// MARK: - SavedMomentsView Redesign 2026
private enum SavedMediaFilter: CaseIterable {
    case all
    case photos
    case videos
    
    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("savedMoments.filter.media.all", comment: "Saved moments media filter: all")
        case .photos:
            return NSLocalizedString("savedMoments.filter.media.photos", comment: "Saved moments media filter: photos")
        case .videos:
            return NSLocalizedString("savedMoments.filter.media.videos", comment: "Saved moments media filter: videos")
        }
    }
}

private enum SavedCollectionFilter: CaseIterable {
    case all
    case location
    case text
    case multiple
    
    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("savedMoments.filter.collection.all", comment: "Saved moments collection filter: all")
        case .location:
            return NSLocalizedString("savedMoments.filter.collection.location", comment: "Saved moments collection filter: location")
        case .text:
            return NSLocalizedString("savedMoments.filter.collection.text", comment: "Saved moments collection filter: text")
        case .multiple:
            return NSLocalizedString("savedMoments.filter.collection.multiple", comment: "Saved moments collection filter: multiple media")
        }
    }
}

private enum SavedSortMode: CaseIterable {
    case newest
    case oldest
    case author
    
    var title: String {
        switch self {
        case .newest:
            return NSLocalizedString("savedMoments.sort.newest", comment: "Saved moments sort newest")
        case .oldest:
            return NSLocalizedString("savedMoments.sort.oldest", comment: "Saved moments sort oldest")
        case .author:
            return NSLocalizedString("savedMoments.sort.author", comment: "Saved moments sort by author")
        }
    }
}

private struct SavedMomentsDetailRoute: Identifiable {
    let id = UUID()
    let moments: [Moment]
    let initialIndex: Int
}

private struct SavedMomentCommentsRoute: Identifiable {
    let id = UUID()
    let moment: Moment
}

struct SavedMomentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = SavedMomentsViewModel()
    
    @State private var searchText = ""
    @State private var mediaFilter: SavedMediaFilter = .all
    @State private var collectionFilter: SavedCollectionFilter = .all
    @State private var sortMode: SavedSortMode = .newest
    
    @State private var isSelectionMode = false
    @State private var selectedMomentIds: Set<String> = []
    
    @State private var detailRoute: SavedMomentsDetailRoute?
    
    @State private var showRemoveSelectionAlert = false
    @State private var restrictedMomentToRemove: Moment?
    @State private var showingRestrictedRemoveAlert = false
    
    private var filteredMoments: [Moment] {
        let searched = viewModel.moments.filter { moment in
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            let query = searchText.lowercased()
            return moment.username.lowercased().contains(query) ||
                moment.content.lowercased().contains(query) ||
                (moment.location?.lowercased().contains(query) ?? false)
        }
        
        let byMedia = searched.filter { moment in
            switch mediaFilter {
            case .all:
                return true
            case .photos:
                return hasImage(moment)
            case .videos:
                return hasVideo(moment)
            }
        }
        
        let byCollection = byMedia.filter { moment in
            switch collectionFilter {
            case .all:
                return true
            case .location:
                return !(moment.location ?? "").isEmpty
            case .text:
                return !moment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .multiple:
                return (moment.mediaItems?.count ?? 0) > 1
            }
        }
        
        switch sortMode {
        case .newest:
            return byCollection.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return byCollection.sorted { $0.timestamp < $1.timestamp }
        case .author:
            return byCollection.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            background
            
            VStack(spacing: 14) {
                header
                
                if viewModel.isLoading {
                    loadingView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    errorView(error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.moments.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .padding(.top, 8)
            
            if isSelectionMode {
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .onAppear {
            if viewModel.moments.isEmpty && !viewModel.isLoading {
                viewModel.loadSavedMoments()
            }
        }
        .refreshable {
            await refreshMoments()
        }
        .fullScreenCover(item: $detailRoute) { route in
            ModernSavedMomentsDetailView(
                moments: route.moments,
                initialIndex: route.initialIndex,
                onDismiss: {
                    detailRoute = nil
                },
                onRemoveMoment: { momentToRemove in
                    if let momentId = momentToRemove.id {
                        viewModel.removeMoment(momentId: momentId)
                    }
                }
            )
            .environmentObject(FirestoreService())
        }
        .alert(NSLocalizedString("savedMoments.selection.remove.title", comment: "Remove selected alert title"), isPresented: $showRemoveSelectionAlert) {
            Button(NSLocalizedString("savedMoments.cancel", comment: "Cancel action"), role: .cancel) { }
            Button(NSLocalizedString("savedMoments.remove.confirm", comment: "Confirm remove action"), role: .destructive) {
                removeSelected()
            }
        } message: {
            Text(String(format: NSLocalizedString("savedMoments.selection.remove.message", comment: "Remove selected saved moments confirmation"), selectedMomentIds.count))
        }
        .alert(NSLocalizedString("savedMoments.remove.title", comment: "Remove from saved"), isPresented: $showingRestrictedRemoveAlert) {
            Button(NSLocalizedString("savedMoments.cancel", comment: "Cancel"), role: .cancel) {
                restrictedMomentToRemove = nil
            }
            Button(NSLocalizedString("savedMoments.remove.confirm", comment: "Remove"), role: .destructive) {
                if let moment = restrictedMomentToRemove, let momentId = moment.id {
                    viewModel.removeMoment(momentId: momentId)
                }
                restrictedMomentToRemove = nil
            }
        } message: {
            if let moment = restrictedMomentToRemove {
                if viewModel.isMomentFromMutedUser(moment) {
                    Text(NSLocalizedString("savedMoments.remove.message.muted", comment: "Moment hidden due to muted account"))
                } else {
                    Text(NSLocalizedString("savedMoments.remove.message.restricted", comment: "This moment is no longer available. Do you want to remove it from your collection?"))
                }
            } else {
                Text(NSLocalizedString("savedMoments.remove.message.restricted", comment: "This moment is no longer available. Do you want to remove it from your collection?"))
            }
        }
        .onChange(of: filteredMoments.map { $0.id ?? "" }) { validIds in
            let validSet = Set(validIds)
            selectedMomentIds = Set(selectedMomentIds.filter { validSet.contains($0) })
        }
    }
    
    private var background: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
        }
    }
    
    private var content: some View {
        VStack(spacing: 14) {
            searchBar
            filterPanel
            gridContent
        }
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("profile.tab.saved", comment: "Saved tab title"))
                    .font(.custom("Poppins-SemiBold", size: 22))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
                Text(String(format: NSLocalizedString("savedMoments.count", comment: "Saved moments count"), viewModel.moments.count))
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(isSelectionMode ? NSLocalizedString("savedMoments.cancel", comment: "Cancel selection mode") : NSLocalizedString("savedMoments.select", comment: "Enable selection mode")) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isSelectionMode.toggle()
                    if !isSelectionMode {
                        selectedMomentIds.removeAll()
                    }
                }
            }
            .font(.custom("Poppins-SemiBold", size: 13))
            .foregroundColor(isSelectionMode ? .red : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
        }
        .padding(.horizontal, 14)
    }
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(NSLocalizedString("savedMoments.search.placeholder", comment: "Saved moments search placeholder"), text: $searchText)
                .font(.custom("Poppins-Regular", size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.clear.liquidGlass(in: Capsule()))
        .padding(.horizontal, 14)
    }
    
    private var filterPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                mediaSegments
                
                Menu {
                    ForEach(SavedSortMode.allCases, id: \.self) { mode in
                        Button(mode.title) { sortMode = mode }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                        Text(sortMode.title)
                            .lineLimit(1)
                    }
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
                }
            }
            
            collectionRail
        }
        .padding(.horizontal, 14)
    }
    
    private var mediaSegments: some View {
        HStack(spacing: 8) {
            ForEach(SavedMediaFilter.allCases, id: \.self) { filter in
                Button(action: { mediaFilter = filter }) {
                    Text(filter.title)
                        .font(.custom("Poppins-SemiBold", size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if mediaFilter == filter {
                                    Color.clear.liquidGlass(in: Capsule(), interactive: true)
                                } else {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.16),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var collectionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SavedCollectionFilter.allCases, id: \.self) { filter in
                    Button(action: { collectionFilter = filter }) {
                        Text(filter.title)
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Group {
                                    if collectionFilter == filter {
                                        Color.clear.liquidGlass(in: Capsule(), interactive: true)
                                    } else {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Capsule()
                                                    .stroke(
                                                        Color.white.opacity(colorScheme == .dark ? 0.06 : 0.16),
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var gridContent: some View {
        ScrollView {
            if filteredMoments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("savedMoments.empty.filtered.title", comment: "No results for current filters"))
                        .font(.custom("Poppins-SemiBold", size: 16))
                    Text(NSLocalizedString("savedMoments.empty.filtered.description", comment: "Hint for filtered empty state"))
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(NSLocalizedString("savedMoments.clearFilters", comment: "Clear filters action")) {
                        searchText = ""
                        mediaFilter = .all
                        collectionFilter = .all
                    }
                    .font(.custom("Poppins-SemiBold", size: 13))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                    spacing: 4
                ) {
                    ForEach(filteredMoments.indices, id: \.self) { index in
                        let moment = filteredMoments[index]
                        let momentId = moment.id ?? UUID().uuidString
                        let isRestricted = !(viewModel.visibilityByMomentId[momentId] ?? true)
                        let isMutedRestriction = isRestricted && viewModel.isMomentFromMutedUser(moment)
                        
                        ScreenshotProtectedView(
                            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                        ) {
                            SavedMomentGridCard(
                                moment: moment,
                                isRestricted: isRestricted,
                                isMutedRestriction: isMutedRestriction,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedMomentIds.contains(momentId),
                                onTap: {
                                    handleTap(moment: moment, currentList: filteredMoments)
                                },
                                onLongPress: {
                                    if !isSelectionMode {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            isSelectionMode = true
                                        }
                                    }
                                    toggleSelection(moment: moment)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, isSelectionMode ? 90 : 20)
            }
        }
    }
    
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text(String(format: NSLocalizedString("savedMoments.selection.count", comment: "Selected items count"), selectedMomentIds.count))
                .font(.custom("Poppins-SemiBold", size: 14))
            
            Spacer()
            
            Button(action: shareSelectedLinks) {
                Label(NSLocalizedString("savedMoments.share", comment: "Share action"), systemImage: "square.and.arrow.up")
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
            .disabled(selectedMomentIds.isEmpty)
            
            Button(action: { showRemoveSelectionAlert = true }) {
                Label(NSLocalizedString("savedMoments.remove", comment: "Remove action"), systemImage: "bookmark.slash")
                    .font(.custom("Poppins-SemiBold", size: 13))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clear.liquidGlass(in: Capsule(), interactive: true))
            .disabled(selectedMomentIds.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.3), lineWidth: 1)
                )
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.2)
            Text(NSLocalizedString("savedMoments.loading", comment: "Loading saved moments"))
                .font(.custom("Poppins-Medium", size: 15))
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("savedMoments.error.title", comment: "Saved moments loading error title"))
                .font(.custom("Poppins-Bold", size: 19))
            Text(error.localizedDescription)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(NSLocalizedString("savedMoments.retry", comment: "Retry action")) {
                viewModel.loadSavedMoments()
            }
            .font(.custom("Poppins-SemiBold", size: 14))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().fill(.ultraThinMaterial))
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text(NSLocalizedString("savedMoments.empty.title", comment: "Saved moments empty title"))
                .font(.custom("Poppins-Bold", size: 23))
            Text(NSLocalizedString("savedMoments.empty.description", comment: "Saved moments empty description"))
                .font(.custom("Poppins-Regular", size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)
            Text(NSLocalizedString("savedMoments.empty.tip", comment: "Saved moments empty tip"))
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }
    
    private func hasVideo(_ moment: Moment) -> Bool {
        if let first = moment.primaryVisibleMediaItem {
            return first.type == .video
        }
        return moment.previewVideoURLString != nil
    }
    
    private func hasImage(_ moment: Moment) -> Bool {
        if let first = moment.primaryVisibleMediaItem {
            return first.type == .image
        }
        return moment.previewImageURLString != nil
    }
    
    private func toggleSelection(moment: Moment) {
        guard let momentId = moment.id else { return }
        
        // Block restricted moments from being selected
        if let canView = viewModel.visibilityByMomentId[momentId], !canView {
            HapticManager.shared.notification(.warning)
            return
        }
        
        if selectedMomentIds.contains(momentId) {
            selectedMomentIds.remove(momentId)
        } else {
            selectedMomentIds.insert(momentId)
        }
    }
    
    private func handleTap(moment: Moment, currentList: [Moment]) {
        if isSelectionMode {
            toggleSelection(moment: moment)
            return
        }

        guard let momentId = moment.id else { return }

        if let canView = viewModel.visibilityByMomentId[momentId], !canView {
            restrictedMomentToRemove = moment
            showingRestrictedRemoveAlert = true
            return
        }

        if viewModel.visibilityByMomentId[momentId] == nil {
            viewModel.refreshVisibilityForMoment(moment) { canView in
                guard canView else {
                    HapticManager.shared.notification(.warning)
                    return
                }
                openDetailForAccessibleMoments(momentId: momentId, currentList: currentList)
            }
            return
        }

        openDetailForAccessibleMoments(momentId: momentId, currentList: currentList)
    }

    private func openDetailForAccessibleMoments(momentId: String, currentList: [Moment]) {
        let accessibleMoments = currentList.filter { candidate in
            guard let candidateId = candidate.id else { return false }
            return viewModel.visibilityByMomentId[candidateId] ?? true
        }

        guard let resolvedIndex = accessibleMoments.firstIndex(where: { $0.id == momentId }) else {
            return
        }

        detailRoute = SavedMomentsDetailRoute(
            moments: accessibleMoments,
            initialIndex: resolvedIndex
        )
    }
    
    private func removeSelected() {
        let ids = selectedMomentIds
        ids.forEach { viewModel.removeMoment(momentId: $0) }
        selectedMomentIds.removeAll()
        isSelectionMode = false
    }
    
    private func shareSelectedLinks() {
        let selectedMoments = viewModel.moments.filter { moment in
            guard let id = moment.id else { return false }
            return selectedMomentIds.contains(id)
        }
        
        let urls: [URL] = selectedMoments.compactMap { moment in
            guard let momentId = moment.id else { return nil }
            var components = URLComponents(string: "https://momentsapp.app/moment/\(momentId)")
            if !moment.authorId.isEmpty {
                components?.queryItems = [URLQueryItem(name: "a", value: moment.authorId)]
            }
            return components?.url
        }
        
        guard !urls.isEmpty else { return }
        
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: { $0.isKeyWindow }),
           let presenter = topViewController(from: window.rootViewController) {
            if let popover = controller.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
            presenter.present(controller, animated: true)
        }
    }
    
    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
    
    @MainActor
    private func refreshMoments() async {
        await withCheckedContinuation { continuation in
            viewModel.loadSavedMoments { _ in
                continuation.resume()
            }
        }
    }
}

private struct SavedMomentGridCard: View {
    let moment: Moment
    let isRestricted: Bool
    let isMutedRestriction: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var generatedThumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                ZStack(alignment: .bottomLeading) {
                    preview
                        .blur(radius: isRestricted ? 16 : 0)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    if isRestricted {
                        savedRestrictedOverlay
                    }

                    if mediaCount > 1 && !isRestricted {
                        Label("\(mediaCount)", systemImage: "square.stack.3d.up")
                            .font(.custom("Poppins-SemiBold", size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.28).onEnded { _ in onLongPress() })
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(hex: "2563EB") : Color.clear, lineWidth: 2)
            )
            
            if isSelectionMode && !isRestricted {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? Color(hex: "2563EB") : .white.opacity(0.9))
                    .padding(6)
            }
        }
    }

    private var savedRestrictedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                )

            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                Text(
                    NSLocalizedString(
                        isMutedRestriction ? "savedMoments.restricted.muted.title" : "savedMoments.restricted.title",
                        comment: "Saved moment restricted title"
                    )
                )
                    .font(.custom("Poppins-SemiBold", size: 10))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(
                    NSLocalizedString(
                        isMutedRestriction ? "savedMoments.restricted.muted.subtitle" : "savedMoments.restricted.subtitle",
                        comment: "Saved moment restricted subtitle"
                    )
                )
                    .font(.custom("Poppins-Regular", size: 9))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private var preview: some View {
        if let media = moment.primaryVisibleMediaItem {
            if media.type == .video {
                savedVideoPreview(url: media.url, thumbnail: media.thumbnailUrl)
            } else {
                KFImage(URL(string: media.url))
                    .resizable()
                    .scaledToFill()
            }
        } else if let image = moment.previewImageURLString {
            KFImage(URL(string: image))
                .resizable()
                .scaledToFill()
        } else if let video = moment.previewVideoURLString {
            savedVideoPreview(url: video, thumbnail: moment.previewImageURLString ?? moment.thumbnailUrl)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "007AFF"), Color(hex: "4F46E5")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if !moment.content.isEmpty {
                    Text(moment.content)
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .padding(8)
                } else {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    @ViewBuilder
    private func savedVideoPreview(url: String, thumbnail: String?) -> some View {
        ZStack {
            if let thumb = thumbnail, let thumbUrl = URL(string: thumb) {
                KFImage(thumbUrl)
                    .resizable()
                    .scaledToFill()
            } else if let generatedThumbnail = generatedThumbnail {
                Image(uiImage: generatedThumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.8))
                    )
                    .onAppear {
                        generateThumbnail(for: url)
                    }
            }
            
            if !isRestricted {
                VStack {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
    }
    
    private var mediaCount: Int {
        if let items = moment.mediaItems, !items.isEmpty {
            return items.count
        }
        var count = 0
        if moment.imagePath != nil { count += 1 }
        if moment.videoUrl != nil { count += 1 }
        return max(count, 1)
    }
    
    private func generateThumbnail(for videoPath: String) {
        guard generatedThumbnail == nil, let videoURL = URL(string: videoPath) else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            
            do {
                let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.8, preferredTimescale: 600), actualTime: nil)
                let thumbnail = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.generatedThumbnail = thumbnail
                }
            } catch {
                // Keep fallback placeholder if thumbnail extraction fails.
            }
        }
    }
}

// MARK: - ✅ Vista detallada de momentos GUARDADOS con diseño del feed
struct ModernSavedMomentsDetailView: View {
    let moments: [Moment]
    let initialIndex: Int
    let onDismiss: () -> Void
    let onRemoveMoment: ((Moment) -> Void)?
    
    @StateObject private var firestoreService = FirestoreService()
    @State private var currentIndex: Int
    @State private var commentsRoute: SavedMomentCommentsRoute?
    @State private var scrollOffset: CGFloat = 0
    @State private var showingRemoveAlert = false
    @State private var momentToRemove: Moment?
    @State private var peekImageURL: String? = nil
    @State private var peekAspectRatio: CGFloat = 1.0
    @State private var isPeeking = false
    @State private var peekOverlayProgress: CGFloat = 0
    @State private var peekIsProtected = false
    
    init(moments: [Moment], initialIndex: Int, onDismiss: @escaping () -> Void, onRemoveMoment: ((Moment) -> Void)? = nil) {
        self.moments = moments
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.onRemoveMoment = onRemoveMoment
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            
            ZStack {
                // ✅ Fondo moderno igual que el feed
                ModernSavedDetailBackground(scrollOffset: scrollOffset)
                    .ignoresSafeArea(.all)
                
                VStack(spacing: 0) {
                    // ✅ Header específico para momentos guardados
                    ModernSavedDetailHeader(
                        moment: moments[safe: currentIndex],
                        onDismiss: onDismiss,
                        onRemove: {
                            if let moment = moments[safe: currentIndex] {
                                momentToRemove = moment
                                showingRemoveAlert = true
                            }
                        }
                    )
                    .padding(.top, max(safeAreaTop * 0.15, 4))
                    .padding(.bottom, 6)
                    
                    // ✅ ScrollView con momentos guardados
                    modernSavedMomentsScrollView(
                        geometry: geometry,
                        safeAreaBottom: safeAreaBottom
                    )
                }
                
                if (isPeeking || peekOverlayProgress > 0.01), let imageURL = peekImageURL {
                    ZStack {
                        ScreenshotProtectedView(isProtected: peekIsProtected, fillsContainer: true) {
                            ZStack {
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .ignoresSafeArea()
                                
                                KFImage(URL(string: imageURL))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: UIScreen.main.bounds.width - 32,
                                        height: (UIScreen.main.bounds.width - 32) / max(peekAspectRatio, 0.1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPeeking)
                    .allowsHitTesting(false)
                    .zIndex(998)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $commentsRoute) { route in
            ModernCommentsView(moment: route.moment)
                .environmentObject(firestoreService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
                        .alert(NSLocalizedString("savedMoments.remove.title", comment: "Remove from saved"), isPresented: $showingRemoveAlert) {
            Button(NSLocalizedString("savedMoments.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("savedMoments.remove.confirm", comment: "Remove"), role: .destructive) {
                if let moment = momentToRemove {
                    onRemoveMoment?(moment)
                    
                    // Si solo hay un momento, cerrar la vista
                    if moments.count == 1 {
                        onDismiss()
                    }
                }
            }
        } message: {
            if let moment = momentToRemove {
                LiveUsernameContent(userId: moment.authorId, fallbackUsername: moment.username) { username in
                    Text(String(format: NSLocalizedString("savedMoments.remove.message.user", comment: "Remove moment from user"), username))
                }
            } else {
                Text(NSLocalizedString("savedMoments.remove.message.generic", comment: "Remove generic message"))
            }
        }
        .onAppear {
            currentIndex = initialIndex
        }
        .environmentObject(firestoreService)
    }
    
    // ✅ ScrollView principal para momentos guardados
    private func modernSavedMomentsScrollView(geometry: GeometryProxy, safeAreaBottom: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 40) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                        ScreenshotProtectedView(
                            isProtected: (moment.audience?.lowercased() ?? "") != "everyone"
                        ) {
                            ModernSavedDetailMomentCard(
                                moment: moment,
                                availableHeight: geometry.size.height - 200,
                                onComment: {
                                    commentsRoute = SavedMomentCommentsRoute(moment: moment)
                                },
                                onRemove: {
                                    momentToRemove = moment
                                    showingRemoveAlert = true
                                },
                                onPeek: { imageURL, ratio, isPressing in
                                    if isPressing {
                                        peekImageURL = imageURL
                                        peekAspectRatio = max(ratio, 0.1)
                                        peekIsProtected = (moment.audience?.lowercased() ?? "") != "everyone"
                                        isPeeking = true
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            peekOverlayProgress = 1
                                        }
                                    } else {
                                        withAnimation(.easeIn(duration: 0.16)) {
                                            peekOverlayProgress = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                            guard peekOverlayProgress <= 0.01 else { return }
                                            isPeeking = false
                                            peekIsProtected = false
                                            peekImageURL = nil
                                            peekAspectRatio = 1.0
                                        }
                                    }
                                }
                            )
                        }
                        .id(index)
                        .environmentObject(firestoreService)
                        .onAppear {
                            if index != currentIndex {
                                currentIndex = index
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.bottom, safeAreaBottom + 40)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: SavedDetailScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(SavedDetailScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(initialIndex, anchor: .center)
                }
            }
        }
    }
}

// MARK: - ✅ Header específico para momentos guardados
struct ModernSavedDetailHeader: View {
    let moment: Moment?
    let onDismiss: () -> Void
    let onRemove: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.9)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.55)
    }
    
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.85)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12),
                            lineWidth: 1
                        )
                    )
            }
            
            if let moment = moment {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    
                    HStack(spacing: 10) {
                        AsyncSavedProfileImageView(userId: moment.authorId)
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.16),
                                    lineWidth: 1
                                )
                            )
                        
                        VStack(alignment: .leading, spacing: 1) {
                            LiveUsernameText(userId: moment.authorId, fallbackUsername: moment.username)
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(primaryTextColor)
                                .lineLimit(1)
                            
                            Text(timeAgo(from: moment.timestamp))
                                .font(.custom("Poppins-Regular", size: 11))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }
            
            Button(action: onRemove) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12),
                            lineWidth: 1
                        )
                    )
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ✅ Tarjeta de momento guardado con funcionalidad completa
struct ModernSavedDetailMomentCard: View {
    let moment: Moment
    let availableHeight: CGFloat
    let onComment: () -> Void
    let onRemove: () -> Void
    let onPeek: ((String, CGFloat, Bool) -> Void)?
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme  // ✅ AGREGAR esta línea
    @State private var currentImageIndex = 0
    
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    @State private var showTags: Bool = false // ✅ NUEVO: Control de etiquetas
    @State private var isImmersive: Bool = false // ✅ NUEVO: Soporte para modo inmersivo
    @State private var realAspectRatio: CGFloat = 1.0
    @State private var immersiveActivationTask: DispatchWorkItem?
    @State private var aspectRatioType: AspectRatioType = .square
    @State private var showContextMenu = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var editedContent = ""
    @State private var isDeleting = false
    
    
    enum AspectRatioType {
        case square, portrait, landscape
        
        var maxHeight: CGFloat {
            switch self {
            case .square: return 400
            case .portrait: return 500
            case .landscape: return 280
            }
        }
        
        var exactRatio: CGFloat {
            switch self {
            case .square: return 1.0
            case .portrait: return 0.8
            case .landscape: return 1.78
            }
        }
    }

    private var mediaItems: [MediaItem] {
        // ✅ MODERACIÓN: Usar visibleMediaItems para excluir archivos moderados del carrusel
        let visible = moment.visibleMediaItems
        if !visible.isEmpty {
            return visible
        }

        guard moment.shouldUseLegacyMediaFallback else {
            return [MediaItem(type: .image, url: "")]
        }
        
        // ✅ FALLBACK: Para momentos legacy que solo tienen imagePath/videoUrl
        var items: [MediaItem] = []
        if let imagePath = moment.imagePath, !imagePath.isEmpty {
            items.append(MediaItem(type: .image, url: imagePath))
        }
        if let videoUrl = moment.videoUrl, !videoUrl.isEmpty {
            items.append(MediaItem(type: .video, url: videoUrl))
        }
        return items.isEmpty ? [MediaItem(type: .image, url: "")] : items
    }
    
    private var cardHeight: CGFloat {
        let maxWidth = UIScreen.main.bounds.width - 30
        let aspectRatio = detectedAspectRatio > 0 ? detectedAspectRatio : aspectRatioType.exactRatio
        let calculatedHeight = maxWidth / aspectRatio
        let maxAllowedHeight = min(aspectRatioType.maxHeight, availableHeight - 80)
        return min(calculatedHeight, maxAllowedHeight)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                ZStack {
                    EnhancedCarouselView(
                        mediaItems: mediaItems,
                        currentIndex: $currentImageIndex,
                        showTags: $showTags,
                        aspectRatio: detectedAspectRatio,
                        allMoments: [],
                        currentMoment: moment,
                        isImmersive: $isImmersive // ✅ NUEVO
                    )
                    .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 10, pressing: { isPressing in
                        if isPressing {
                            scheduleImmersiveActivation()
                        } else {
                            cancelImmersiveActivation()
                            endImmersive()
                        }
                    }, perform: {})
                    .frame(height: max(cardHeight, 200))
                    .clipShape(RoundedRectangle(cornerRadius: isImmersive ? 12 : 20))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isImmersive)
                    .overlay(
                        RoundedRectangle(cornerRadius: isImmersive ? 12 : 20)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.12), radius: 15, x: 0, y: 10)
                    .shadow(color: colorScheme == .dark ? .white.opacity(0.05) : .black.opacity(0.08), radius: 1, x: 0, y: 1)
                    .onAppear {
                        detectAspectRatio()
                    }

                    if moment.hasHiddenLayers,
                       moment.hiddenLayerCount > 0,
                       mediaItems.count == 1,
                       mediaItems.first?.type == .image,
                       currentImageIndex == 0 {
                        HiddenLayersOverlayView(moment: moment, isImmersive: isImmersive)
                            .frame(height: max(cardHeight, 200))
                            .clipShape(RoundedRectangle(cornerRadius: isImmersive ? 12 : 20))
                            .zIndex(3)
                    }
                    
                    if mediaItems.count > 1 {
                        VStack {
                            HStack(spacing: 8) {
                                ForEach(0..<mediaItems.count, id: \.self) { index in
                                    Circle()
                                        .fill(currentImageIndex == index ? Color.white : Color.white.opacity(0.35))
                                        .frame(width: currentImageIndex == index ? 8 : 6, height: currentImageIndex == index ? 8 : 6)
                                        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
                                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                                }
                            }
                            .padding(.top, 20)
                            Spacer()
                        }
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }
                    
                    if mediaItems.count > 1 {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(currentImageIndex + 1)/\(mediaItems.count)")
                                    .font(.custom("Poppins-Medium", size: 11))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.4)))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                            }
                            .padding(.top, 14)
                            .padding(.trailing, 14)
                            Spacer()
                        }
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }

                    if !moment.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack {
                            Spacer()
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 130)
                            .overlay(alignment: .bottomLeading) {
                                ExpandableContentView(
                                    content: moment.content,
                                    colorScheme: colorScheme,
                                    onHashtagTap: { _ in }
                                )
                                .padding(.leading, 14)
                                .padding(.trailing, isImmersive ? 14 : 124)
                                .padding(.bottom, 14)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }

                    let currentMediaItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : nil
                    if let currentMediaItem, !currentMediaItem.isHiddenByModeration,
                       let tags = currentMediaItem.tags, !tags.isEmpty {
                        VStack {
                            HStack {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        showTags.toggle()
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(showTags ? Color(hex: "007AFF") : Color.black.opacity(0.6))
                                            .frame(width: 32, height: 32)
                                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                                }
                                .padding(.leading, 12)
                                .padding(.top, 12)
                                Spacer()
                            }
                            Spacer()
                        }
                        .zIndex(100)
                        .opacity(isImmersive ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: isImmersive)
                    }
                }
                
                ModernActionButtons(
                    moment: moment, // Sin likes, solo rail y acciones existentes
                    isSaved: .constant(true),
                    isSaveLoading: .constant(false),
                    commentCount: $commentCount,
                    onComment: {
                        HapticManager.shared.lightImpact()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            onComment()
                        }
                    },
                    onSave: {
                        HapticManager.shared.mediumImpact()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            onRemove()
                        }
                    },
                    onContextMenu: {
                        HapticManager.shared.mediumImpact()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showContextMenu = true
                        }
                    },
                    isImmersive: $isImmersive
                )
                .environmentObject(firestoreService)
            }
            .padding(.horizontal, 15)
        }
        .onAppear {
            if !hasLoadedInitialData {
                loadMomentData()
                hasLoadedInitialData = true
            }
        }
        .onDisappear {
            cancelImmersiveActivation()
            onPeek?("", 1.0, false)
        }
        .overlay {
            if showContextMenu {
                ModernContextMenuOverlay(
                    moment: moment,
                    isPresented: $showContextMenu,
                    onEdit: {
                        editedContent = moment.content
                        showEditSheet = true
                    },
                    onDelete: {
                        showDeleteAlert = true
                    },
                    onReport: {}
                )
                .zIndex(1000)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditMomentView(
                moment: moment,
                editedContent: $editedContent,
                onSave: { newContent in
                    updateMoment(newContent: newContent)
                }
            )
        }
        .alert(NSLocalizedString("contextMenu.delete.title", comment: "Delete moment alert title"), isPresented: $showDeleteAlert) {
            Button(NSLocalizedString("contextMenu.delete.cancel", comment: "Cancel button"), role: .cancel) { }
            Button(NSLocalizedString("contextMenu.delete.confirm", comment: "Delete button"), role: .destructive) {
                deleteMoment()
            }
        } message: {
            Text(NSLocalizedString("contextMenu.delete.message", comment: "Delete moment confirmation message"))
        }
    }
    // ✅ Funciones auxiliares
    private func loadMomentData() {
        guard let momentId = moment.id else { return }
        
        // Cargar conteo de comentarios
        firestoreService.db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if let error = error {
                    return
                }
                
                DispatchQueue.main.async {
                    let newCount = snapshot?.documents.count ?? 0
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.commentCount = newCount
                    }
                }
            }
    }
    
    private func detectAspectRatio() {
        if let savedAspectRatio = moment.aspectRatio {
            let safeRatio = ProcessedMedia.AspectRatio(from: savedAspectRatio).value
            let displayRatio = safeRatio < 0.8 ? 0.8 : safeRatio
            
            DispatchQueue.main.async {
                self.realAspectRatio = safeRatio
                self.detectedAspectRatio = displayRatio
                
                if displayRatio > 1.4 {
                    self.aspectRatioType = .landscape
                } else if displayRatio < 0.9 {
                    self.aspectRatioType = .portrait
                } else if abs(displayRatio - 1.0) < 0.05 {
                    self.aspectRatioType = .square
                } else {
                    self.aspectRatioType = .portrait
                }
            }
            return
        }
        
        guard let firstItem = mediaItems.first, !firstItem.url.isEmpty else {
            realAspectRatio = 0.8
            detectedAspectRatio = 0.8
            aspectRatioType = .portrait
            return
        }
        
        if firstItem.type == .image {
            KFImage(URL(string: firstItem.url))
                .onSuccess { result in
                    let imageSize = result.image.size
                    let ratio = imageSize.width / imageSize.height
                    let displayRatio = ratio < 0.8 ? 0.8 : ratio
                    
                    DispatchQueue.main.async {
                        self.realAspectRatio = ratio
                        self.detectedAspectRatio = displayRatio
                        
                        let tolerance: CGFloat = 0.05
                        
                        if abs(displayRatio - 1.0) < tolerance {
                            self.aspectRatioType = .square
                        } else if abs(displayRatio - 0.8) < tolerance {
                            self.aspectRatioType = .portrait
                        } else if displayRatio > 1.4 {
                            self.aspectRatioType = .landscape
                        } else if displayRatio < 0.9 {
                            self.aspectRatioType = .portrait
                        } else {
                            self.aspectRatioType = .square
                        }
                    }
                }
                .onFailure { _ in
                    DispatchQueue.main.async {
                        self.realAspectRatio = 0.8
                        self.detectedAspectRatio = 0.8
                        self.aspectRatioType = .portrait
                    }
                }
        } else {
            realAspectRatio = 16.0/9.0
            detectedAspectRatio = 16.0/9.0
            aspectRatioType = .landscape
        }
    }
    
    private func updateMoment(newContent: String) {
        guard let momentId = moment.id else { return }

        firestoreService.updateMoment(
            userId: moment.authorId,
            momentId: momentId,
            content: newContent
        ) { _ in
        }
    }

    private func deleteMoment() {
        guard let momentId = moment.id else { return }
        guard !isDeleting else { return }

        isDeleting = true
        firestoreService.deleteMoment(
            userId: moment.authorId,
            momentId: momentId
        ) { error in
            DispatchQueue.main.async {
                self.isDeleting = false
                if error == nil {
                    onRemove()
                }
            }
        }
    }
    
    private func scheduleImmersiveActivation() {
        cancelImmersiveActivation()
        
        let task = DispatchWorkItem {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                self.isImmersive = true
                HapticManager.shared.mediumImpact()

                let currentItem = mediaItems.indices.contains(currentImageIndex) ? mediaItems[currentImageIndex] : mediaItems.first
                let shouldUseFullscreenPeek = mediaItems.count > 1 &&
                    currentItem?.type == .image &&
                    currentItem?.isHiddenByModeration != true

                if let item = currentItem, item.type == .image, !item.isHiddenByModeration {
                    let currentItemRatio = item.resolvedAspectRatioValue ?? realAspectRatio
                    if currentItemRatio > 0,
                       currentItemRatio.isFinite,
                       (shouldUseFullscreenPeek || abs(currentItemRatio - detectedAspectRatio) > 0.035) {
                        onPeek?(item.url, currentItemRatio, true)
                    }
                }
            }
        }
        
        immersiveActivationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }
    
    private func cancelImmersiveActivation() {
        immersiveActivationTask?.cancel()
        immersiveActivationTask = nil
    }
    
    private func endImmersive() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            self.isImmersive = false
            onPeek?("", 1.0, false)
        }
    }
}
// MARK: - ✅ Componentes auxiliares específicos para guardados
struct ModernSavedDetailBackground: View {
    let scrollOffset: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Igual que el feed en modo oscuro: base profunda y uniforme.
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(hex: "080808"), location: 0),
                        .init(color: Color(hex: "080808"), location: 0.3),
                        .init(color: Color(hex: "0C0C0C"), location: 0.7),
                        .init(color: Color(hex: "080808"), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                // Igual que el feed en modo claro: blanco limpio con profundidad suave.
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.2),
                        .init(color: Color(hex: "f8f9fa"), location: 0.5),
                        .init(color: Color(hex: "e9ecef"), location: 0.8),
                        .init(color: .white, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity((colorScheme == .dark ? 0.06 : 0.03) + abs(scrollOffset) * 0.00015)
                .ignoresSafeArea()
        }
    }
}

struct SavedDetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ✅ AsyncProfileImageView específico para guardados
struct AsyncSavedProfileImageView: View {
    let userId: String
    @State private var profileImageURL: String?
    @State private var pendingUserId: String?
    @EnvironmentObject private var firestoreService: FirestoreService
    
    var body: some View {
        AsyncImage(url: URL(string: profileImageURL ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.gray)
                )
        }
        .onAppear {
            loadProfileImage(for: userId)
        }
        .onChange(of: userId) { newUserId in
            loadProfileImage(for: newUserId)
        }
    }
    
    private func loadProfileImage(for requestedUserId: String) {
        // Evita mostrar la foto previa mientras llega el nuevo fetch.
        pendingUserId = requestedUserId
        profileImageURL = nil
        
        firestoreService.fetchUser(userId: requestedUserId) { result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    guard pendingUserId == requestedUserId else { return }
                    self.profileImageURL = user.profileImagePath
                }
            case .failure:
                DispatchQueue.main.async {
                    guard pendingUserId == requestedUserId else { return }
                    self.profileImageURL = nil
                }
            }
        }
    }
}
