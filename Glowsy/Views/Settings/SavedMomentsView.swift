import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Kingfisher
import AVKit
import AVFoundation

// MARK: - SavedMomentsViewModel CORREGIDO
class SavedMomentsViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    @Published var savedMomentIds: [String] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let firestoreService = FirestoreService()

    func loadSavedMoments(completion: @escaping (Error?) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }

        isLoading = true
        error = nil
        
        print("🔄 [SavedMoments] Iniciando carga para usuario: \(userId)")
        
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
                    print("📚 [SavedMoments] IDs encontrados: \(momentIds.count)")
                }
                
                // Si no hay momentos guardados
                guard !momentIds.isEmpty else {
                    DispatchQueue.main.async {
                        self.moments = []
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
        
        print("🔄 [SavedMoments] Buscando \(momentIds.count) momentos directamente")
        
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
                    print("🧹 [SavedMoments] Limpiando \(notFoundMomentIds.count) momentos no encontrados")
                    self.cleanupMissingMoments(missingIds: notFoundMomentIds)
                }
                
                // Ordenar por timestamp
                let sortedMoments = foundMoments.sorted { $0.timestamp > $1.timestamp }
                
                self.moments = sortedMoments
                self.isLoading = false
                print("✅ [SavedMoments] Carga completada: \(sortedMoments.count) momentos encontrados")
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
                print("❌ [SavedMoments] Error obteniendo momentos de \(userId): \(error)")
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
                    print("❌ [SavedMoments] Error obteniendo usuarios activos: \(error)")
                    // Fallback: buscar en todos los usuarios (menos eficiente pero funcional)
                    self.fetchAllUsers(completion: completion)
                    return
                }
                
                let userIds = snapshot?.documents.compactMap { doc in
                    doc.documentID
                } ?? []
                
                print("👥 [SavedMoments] Usuarios activos encontrados: \(userIds.count)")
                
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
                    print("❌ [SavedMoments] Error obteniendo todos los usuarios: \(error)")
                    completion([])
                    return
                }
                
                let userIds = snapshot?.documents.compactMap { doc in
                    doc.documentID
                } ?? []
                
                print("👥 [SavedMoments] Usuarios totales encontrados: \(userIds.count)")
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
                        print("❌ [SavedMoments] Error limpiando momento \(momentId): \(error)")
                    } else {
                        print("🧹 [SavedMoments] Momento \(momentId) limpiado exitosamente")
                    }
                    group.leave()
                }
        }
        
        group.notify(queue: .main) {
            // Actualizar IDs locales
            self.savedMomentIds.removeAll { missingIds.contains($0) }
            print("✅ [SavedMoments] Limpieza completada")
        }
    }
    
    // MARK: - Public Methods
    func isMomentSaved(momentId: String) -> Bool {
        return savedMomentIds.contains(momentId)
    }

    func removeMoment(momentId: String, completion: @escaping (Error?) -> Void = { _ in }) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"]))
            return
        }

        print("🗑️ [SavedMoments] Eliminando momento: \(momentId)")
        
        firestoreService.toggleSaveMoment(userId: userId, momentId: momentId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [SavedMoments] Error eliminando: \(error)")
                    completion(error)
                } else {
                    print("✅ [SavedMoments] Momento eliminado correctamente")
                    self?.moments.removeAll { $0.id == momentId }
                    self?.savedMomentIds.removeAll { $0 == momentId }
                    completion(nil)
                }
            }
        }
    }
    
    func addSavedMoment(_ moment: Moment) {
        guard let momentId = moment.id else { return }
        
        if !savedMomentIds.contains(momentId) {
            savedMomentIds.append(momentId)
            
            if !moments.contains(where: { $0.id == momentId }) {
                moments.append(moment)
                moments.sort { $0.timestamp > $1.timestamp }
            }
        }
    }
    
    // MARK: - Debug Methods
    func debugSavedMoments() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("🔍 [SavedMoments] DEBUG: Verificando momentos guardados...")
        firestoreService.db.collection("users").document(userId).collection("savedMoments")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ [SavedMoments] Error en debug: \(error)")
                    return
                }
                
                let docs = snapshot?.documents ?? []
                print("📚 [SavedMoments] Documentos en savedMoments: \(docs.count)")
                
                docs.forEach { doc in
                    print("  - \(doc.documentID): \(doc.data())")
                }
            }
    }
    
    func forceRefresh() {
        print("🔄 [SavedMoments] Forzando recarga completa...")
        moments = []
        savedMomentIds = []
        loadSavedMoments()
    }
}

// MARK: - ✅ SavedMomentsView CORREGIDO sin confirmaciones duplicadas
struct SavedMomentsView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = SavedMomentsViewModel()
    @State private var selectedViewMode: ViewMode = .grid
    
    enum ViewMode: String, CaseIterable {
        case grid = "square.grid.3x3"
        case list = "list.bullet"
        
        var title: String {
            switch self {
            case .grid: return "Cuadrícula"
            case .list: return "Lista"
            }
        }
    }

    var body: some View {
        ZStack {
            backgroundGradient
            
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.moments.isEmpty {
                emptyStateView
            } else {
                mainContent
            }
        }
        .navigationTitle("Guardados")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                viewModeToggle
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
    }
    
    // MARK: - View Components
    private var backgroundGradient: some View {
        Color(colorScheme == .dark ? .black : .white)
            .ignoresSafeArea()
            .overlay(
                LinearGradient(
                    colors: [
                        Color(hex: "00A896").opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Cargando momentos guardados...")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.gray)
        }
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Error al cargar")
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(error.localizedDescription)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Reintentar") {
                viewModel.loadSavedMoments()
            }
            .font(.custom("Poppins-SemiBold", size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(hex: "00A896"))
            .cornerRadius(20)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bookmark")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("Sin momentos guardados")
                    .font(.custom("Poppins-Bold", size: 24))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Los momentos que guardes aparecerán aquí")
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Text("💡 Tip: Toca el ícono de bookmark en cualquier momento para guardarlo")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    private var viewModeToggle: some View {
        HStack(spacing: 8) {
            ForEach(ViewMode.allCases, id: \.rawValue) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedViewMode = mode
                    }
                }) {
                    Image(systemName: mode.rawValue)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(selectedViewMode == mode ? Color(hex: "00A896") : .gray)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(selectedViewMode == mode ? Color(hex: "00A896").opacity(0.15) : Color.clear)
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? .black.opacity(0.6) : .white.opacity(0.8))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            statsHeader
            
            if selectedViewMode == .grid {
                gridView
            } else {
                listView
            }
        }
    }
    
    private var statsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.moments.count) momentos")
                    .font(.custom("Poppins-Bold", size: 18))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Guardados en tu colección")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                ForEach(viewModel.moments) { moment in
                    GridMomentCard(
                        moment: moment,
                        viewModel: viewModel
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var listView: some View {
        List {
            ForEach(viewModel.moments) { moment in
                ListMomentCard(
                    moment: moment,
                    viewModel: viewModel
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
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

// MARK: - ✅ GridMomentCard CORREGIDO
struct GridMomentCard: View {
    let moment: Moment
    let viewModel: SavedMomentsViewModel // ✅ NUEVO: Recibir ViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var showingFullScreen = false
    
    var body: some View {
        Button(action: { showingFullScreen = true }) {
            ZStack {
                if let imagePath = moment.imagePath {
                    AsyncImage(url: URL(string: imagePath)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: UIScreen.main.bounds.width / 3 - 14, height: UIScreen.main.bounds.width / 3 - 14)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: UIScreen.main.bounds.width / 3 - 14, height: UIScreen.main.bounds.width / 3 - 14)
                            .overlay(ProgressView().scaleEffect(0.8))
                    }
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: "00A896").opacity(0.8), Color(hex: "00A896").opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        Text(moment.content)
                            .font(.custom("Poppins-Medium", size: 12))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(8)
                    }
                    .frame(width: UIScreen.main.bounds.width / 3 - 14, height: UIScreen.main.bounds.width / 3 - 14)
                }
                
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .cornerRadius(8)
        .contextMenu {
            // ✅ CORREGIDO: Eliminar directamente sin confirmación
            Button(action: {
                if let momentId = moment.id {
                    viewModel.removeMoment(momentId: momentId)
                }
            }) {
                Label("Eliminar de guardados", systemImage: "bookmark.slash")
            }
            
            Button(action: { /* Share action */ }) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            ModernSavedMomentsDetailView(
                moments: viewModel.moments, // ✅ CORREGIDO: Pasar todos los momentos
                initialIndex: viewModel.moments.firstIndex(where: { $0.id == moment.id }) ?? 0, // ✅ CORREGIDO: Índice correcto
                onDismiss: {
                    showingFullScreen = false
                },
                onRemoveMoment: { momentToRemove in
                    if let momentId = momentToRemove.id {
                        viewModel.removeMoment(momentId: momentId)
                    }
                }
            )
            .environmentObject(FirestoreService())
        }
    }
}

// MARK: - ✅ ListMomentCard CORREGIDO
struct ListMomentCard: View {
    let moment: Moment
    let viewModel: SavedMomentsViewModel // ✅ NUEVO: Recibir ViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var showingFullScreen = false
    
    var body: some View {
        Button(action: { showingFullScreen = true }) {
            HStack(spacing: 12) {
                if let imagePath = moment.imagePath {
                    AsyncImage(url: URL(string: imagePath)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay(ProgressView().scaleEffect(0.6))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [Color(hex: "00A896").opacity(0.8), Color(hex: "00A896").opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "text.quote")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(moment.username)")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(Color(hex: "00A896"))
                    
                    Text(moment.content)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(moment.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    // ✅ CORREGIDO: Eliminar directamente sin confirmación
                    Button(action: {
                        if let momentId = moment.id {
                            viewModel.removeMoment(momentId: momentId)
                        }
                    }) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                    
                    Button(action: { /* Share */ }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingFullScreen) {
            ModernSavedMomentsDetailView(
                moments: viewModel.moments, // ✅ CORREGIDO: Pasar todos los momentos
                initialIndex: viewModel.moments.firstIndex(where: { $0.id == moment.id }) ?? 0, // ✅ CORREGIDO: Índice correcto
                onDismiss: {
                    showingFullScreen = false
                },
                onRemoveMoment: { momentToRemove in
                    if let momentId = momentToRemove.id {
                        viewModel.removeMoment(momentId: momentId)
                    }
                }
            )
            .environmentObject(FirestoreService())
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
    @State private var showingComments = false
    @State private var selectedMoment: Moment?
    @State private var scrollOffset: CGFloat = 0
    @State private var showingRemoveAlert = false
    @State private var momentToRemove: Moment?
    
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
                    .padding(.top, safeAreaTop + 5)
                    .padding(.bottom, 20)
                    
                    // ✅ ScrollView con momentos guardados
                    modernSavedMomentsScrollView(
                        geometry: geometry,
                        safeAreaBottom: safeAreaBottom
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingComments) {
            if let moment = selectedMoment {
                ModernCommentsView(moment: moment)
                    .environmentObject(firestoreService)
            }
        }
        .alert("Eliminar de guardados", isPresented: $showingRemoveAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
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
                Text("¿Quieres eliminar el momento de \(moment.username) de tus guardados?")
            } else {
                Text("¿Quieres eliminar este momento de tus guardados?")
            }
        }
        .onAppear {
            print("📍 Abriendo vista detallada de guardados en momento índice: \(initialIndex)")
            currentIndex = initialIndex
        }
    }
    
    // ✅ ScrollView principal para momentos guardados
    private func modernSavedMomentsScrollView(geometry: GeometryProxy, safeAreaBottom: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 40) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                        ModernSavedDetailMomentCard(
                            moment: moment,
                            availableHeight: geometry.size.height - 200,
                            onComment: {
                                selectedMoment = moment
                                showingComments = true
                            },
                            onRemove: {
                                momentToRemove = moment
                                showingRemoveAlert = true
                            }
                        )
                        .id(index)
                        .environmentObject(firestoreService)
                        .onAppear {
                            if index != currentIndex {
                                currentIndex = index
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
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
                    print("📍 Scrolled to saved moment: \(initialIndex)")
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
    
    var body: some View {
        HStack {
            // ✅ Botón chevron izquierda
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color(hex: "00A896").opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            
            Spacer()
            
            // ✅ Info del usuario CENTRADA con badge de guardado
            if let moment = moment {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        AsyncSavedProfileImageView(userId: moment.authorId)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.4), Color(hex: "00A896").opacity(0.5)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                        
                        VStack(spacing: 2) {
                            Text(moment.username)
                                .font(.custom("Poppins-SemiBold", size: 16))
                                .foregroundColor(.white)
                            
                            Text(timeAgo(from: moment.timestamp))
                                .font(.custom("Poppins-Regular", size: 12))
                                .foregroundColor(.gray.opacity(0.8))
                        }
                    }
                    
                    // ✅ Badge de momento guardado
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("GUARDADO")
                            .font(.custom("Poppins-Bold", size: 11))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.8), Color.orange.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                }
            }
            
            Spacer()
            
            // ✅ Botón de eliminar de guardados
            Button(action: onRemove) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.3), Color.red.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
        }
        .padding(.horizontal, 20)
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
    
    @EnvironmentObject private var firestoreService: FirestoreService
    @Environment(\.colorScheme) var colorScheme  // ✅ AGREGAR esta línea
    @State private var currentImageIndex = 0
    @State private var detectedAspectRatio: CGFloat = 1.0
    @State private var commentCount: Int = 0
    @State private var hasLoadedInitialData: Bool = false
    @State private var isFollowing: Bool = false
    @State private var isFollowLoading: Bool = false
    @State private var aspectRatioType: AspectRatioType = .square
    
    // ✅ AGREGAR: Colores adaptativos
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
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
        VStack(spacing: 12) {
            // ✅ Header del momento con follow button
            postHeaderView
            
            // ✅ Contenido principal
            ZStack(alignment: .bottom) {
                // ✅ Media content
                ZStack {
                    EnhancedCarouselView(
                        mediaItems: mediaItems,
                        currentIndex: $currentImageIndex,
                        aspectRatio: detectedAspectRatio,
                        allMoments: [], // ✅ AGREGAR: Array vacío para guardados (no necesita ReelsViewer)
                        currentMoment: moment // ✅ AGREGAR: El momento actual
                    )
                    .frame(height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: adaptiveColors.overlayStroke,  // ✅ CAMBIAR esta línea
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: adaptiveColors.shadowColor, radius: 15, x: 0, y: 10)  // ✅ CAMBIAR esta línea
                    .onAppear {
                        detectAspectRatio()
                    }
                    
                    // ✅ Indicadores de media múltiple
                    if mediaItems.count > 1 {
                        VStack {
                            HStack(spacing: 8) {
                                ForEach(0..<mediaItems.count, id: \.self) { index in
                                    Capsule()
                                        .fill(currentImageIndex == index ?
                                              (colorScheme == .dark ? Color.white : Color.black) :
                                              (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)))  // ✅ CAMBIAR esta línea
                                        .frame(width: currentImageIndex == index ? 25 : 8, height: 4)
                                        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
                                }
                            }
                            .padding(.top, 20)
                            Spacer()
                        }
                    }
                    
                    // ✅ Descripción expandible
                    if !moment.content.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                ExpandableContentView(
                                    content: moment.content,
                                    colorScheme: colorScheme,
                                    onHashtagTap: { hashtag in
                                        print("🔍 Hashtag tocado: #\(hashtag)")
                                        // TODO: Navegar a ExploreView
                                    }
                                )
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                // ✅ Botones de acción específicos para guardados
                ModernSavedDetailActionButtons(
                    moment: moment,
                    commentCount: $commentCount,
                    colorScheme: colorScheme,  // ✅ AGREGAR esta línea (si este componente también necesita colorScheme)
                    onComment: onComment,
                    onRemoveFromSaved: onRemove
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
    }
    
    // ✅ Header del momento con follow button
    private var postHeaderView: some View {
        HStack(spacing: 12) {
            AsyncSavedProfileImageView(userId: moment.authorId)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: adaptiveColors.overlayStroke,  // ✅ CAMBIAR esta línea
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(moment.username)")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(adaptiveColors.primary)  // ✅ CAMBIAR esta línea
                
                Text(timeAgo(from: moment.timestamp))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(adaptiveColors.tertiary)  // ✅ CAMBIAR esta línea
            }
            
            Spacer()
            
            // ✅ Follow Button (solo si no es el usuario actual)
            if moment.authorId != Auth.auth().currentUser?.uid {
                ModernFollowButton(
                    isFollowing: isFollowing,
                    isLoading: isFollowLoading,
                    colorScheme: colorScheme,  // ✅ Esta línea ya está bien
                    action: toggleFollow
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // ✅ Funciones auxiliares
    private func loadMomentData() {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              let momentId = moment.id else { return }
        
        // Cargar conteo de comentarios
        firestoreService.db.collection("users").document(moment.authorId)
            .collection("moments").document(momentId)
            .collection("comments")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error cargando comentarios: \(error)")
                    return
                }
                
                DispatchQueue.main.async {
                    let newCount = snapshot?.documents.count ?? 0
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.commentCount = newCount
                    }
                }
            }
        
        // Verificar si está siguiendo al autor
        if moment.authorId != currentUserId {
            firestoreService.isFollowing(currentUserId: currentUserId, targetUserId: moment.authorId) { following in
                DispatchQueue.main.async {
                    self.isFollowing = following
                }
            }
        }
    }
    
    private func toggleFollow() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isFollowLoading = true
        
        if isFollowing {
            firestoreService.unfollowUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = false
                        }
                    }
                }
            }
        } else {
            firestoreService.followUser(currentUserId: currentUserId, targetUserId: moment.authorId) { error in
                DispatchQueue.main.async {
                    self.isFollowLoading = false
                    if error == nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            self.isFollowing = true
                        }
                    }
                }
            }
        }
    }
    
    private func detectAspectRatio() {
        if let savedAspectRatio = moment.aspectRatio {
            let aspectRatioFromDB = ProcessedMedia.AspectRatio(from: savedAspectRatio)
            
            DispatchQueue.main.async {
                self.detectedAspectRatio = aspectRatioFromDB.value
                
                switch aspectRatioFromDB {
                case .landscape:
                    self.aspectRatioType = .landscape
                case .portrait:
                    self.aspectRatioType = .portrait
                case .square:
                    self.aspectRatioType = .square
                case .nineBySixteen:
                    self.aspectRatioType = .portrait
                }
            }
            return
        }
        
        guard let firstItem = mediaItems.first, !firstItem.url.isEmpty else {
            detectedAspectRatio = 0.8
            aspectRatioType = .portrait
            return
        }
        
        if firstItem.type == .image {
            KFImage(URL(string: firstItem.url))
                .onSuccess { result in
                    let imageSize = result.image.size
                    let ratio = imageSize.width / imageSize.height
                    
                    DispatchQueue.main.async {
                        self.detectedAspectRatio = ratio
                        
                        let tolerance: CGFloat = 0.05
                        
                        if abs(ratio - 1.0) < tolerance {
                            self.aspectRatioType = .square
                        } else if abs(ratio - 0.8) < tolerance {
                            self.aspectRatioType = .portrait
                        } else if ratio > 1.4 {
                            self.aspectRatioType = .landscape
                        } else if ratio < 0.9 {
                            self.aspectRatioType = .portrait
                        } else {
                            self.aspectRatioType = .square
                        }
                    }
                }
                .onFailure { _ in
                    DispatchQueue.main.async {
                        self.detectedAspectRatio = 0.8
                        self.aspectRatioType = .portrait
                    }
                }
        } else {
            detectedAspectRatio = 16.0/9.0
            aspectRatioType = .landscape
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ✅ Botones de acción específicos para momentos guardados
struct ModernSavedDetailActionButtons: View {
    let moment: Moment
    @Binding var commentCount: Int
    let colorScheme: ColorScheme  // ✅ AGREGAR este parámetro
    let onComment: () -> Void
    let onRemoveFromSaved: () -> Void
    
    @EnvironmentObject private var firestoreService: FirestoreService
    
    // ✅ AGREGAR: Colores adaptativos
    private var adaptiveColors: AdaptiveColors {
        AdaptiveColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            
            VStack(spacing: 14) {
                // ✅ Reaction Button
                EpicReactionButton(moment: moment)
                    .environmentObject(firestoreService)
                
                // ✅ Comment button
                Button(action: onComment) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: commentCount > 0 ?
                                                [Color.blue.opacity(0.7), Color.purple.opacity(0.7)] :
                                                adaptiveColors.buttonStroke,  // ✅ CAMBIAR esta línea
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: adaptiveColors.shadowColor, radius: 6, x: 0, y: 3)  // ✅ CAMBIAR esta línea
                            
                            Image(systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: commentCount > 0 ?
                                        [Color.blue, Color.purple] :
                                        adaptiveColors.buttonGradient,  // ✅ CAMBIAR esta línea
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        if commentCount > 0 {
                            Text("\(commentCount)")
                                .font(.custom("Poppins-SemiBold", size: 12))
                                .foregroundColor(adaptiveColors.secondary)  // ✅ CAMBIAR esta línea
                        }
                    }
                }
                .scaleEffect(commentCount > 0 ? 1.08 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: commentCount)
                
                // ✅ Remove from saved button
                Button(action: onRemoveFromSaved) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.red.opacity(0.6), Color.orange.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: adaptiveColors.shadowColor, radius: 6, x: 0, y: 3)  // ✅ CAMBIAR esta línea
                            
                            Image(systemName: "bookmark.slash")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.red, Color.orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text("Quitar")
                            .font(.custom("Poppins-SemiBold", size: 11))
                            .foregroundColor(adaptiveColors.secondary)  // ✅ CAMBIAR esta línea
                    }
                }
                
                // ✅ Share button
                Button(action: shareAction) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: adaptiveColors.buttonStroke,  // ✅ CAMBIAR esta línea
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: adaptiveColors.shadowColor, radius: 6, x: 0, y: 3)  // ✅ CAMBIAR esta línea
                            
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: adaptiveColors.buttonGradient,  // ✅ CAMBIAR esta línea
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text("Compartir")
                            .font(.custom("Poppins-SemiBold", size: 11))
                            .foregroundColor(adaptiveColors.secondary)  // ✅ CAMBIAR esta línea
                    }
                }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
    
    private func shareAction() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        var items: [Any] = []
        let shareText = "¡Mira este momento de \(moment.username)!"
        items.append(shareText)
        
        if let momentId = moment.id {
            if let url = URL(string: "https://glowsy.app/moment/\(momentId)") {
                items.append(url)
            }
        }
        
        let activityController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        window.rootViewController?.present(activityController, animated: true)
    }
}
// MARK: - ✅ Componentes auxiliares específicos para guardados
struct ModernSavedDetailBackground: View {
    let scrollOffset: CGFloat
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(hex: "1a1a2e").opacity(0.95),
                    Color(hex: "16213e").opacity(0.85),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.08 + abs(scrollOffset) * 0.0002)
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
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        firestoreService.fetchUser(userId: userId) { result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    self.profileImageURL = user.profileImagePath
                }
            case .failure:
                break
            }
        }
    }
}


