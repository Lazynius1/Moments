import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ContentVisibilityView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ContentVisibilityViewModel()
    @State private var isLoading = true
    @State private var showingStoryAudienceSelector = false
    @State private var showingPostAudienceSelector = false
    @State private var showingStoryInteractionSettings = false // ✅ NUEVO
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            if isLoading {
                ProgressView("Cargando configuración...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
            } else {
                List {
                    // Stories Settings
                    Section {
                        contentTypeHeader(
                            icon: "circle.dashed",
                            title: "Historias",
                            description: "Controla quién puede ver tus historias"
                        )
                        
                        // Current story audience
                        Button(action: { showingStoryAudienceSelector = true }) {
                            currentAudienceRow(
                                audience: viewModel.storyAudience,
                                customListName: viewModel.storyCustomListName,
                                customCount: viewModel.storyCustomUsers.count
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // ✅ NUEVO: Configuración de interacciones
                        Button(action: { showingStoryInteractionSettings = true }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "00A896").opacity(0.2))
                                        .frame(width: 48, height: 48)
                                    
                                    Image(systemName: "gear")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(Color(hex: "00A896"))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Configuración de interacciones")
                                        .font(.custom("Poppins-SemiBold", size: 16))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(getInteractionSummary())
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(16)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                    } header: {
                        Text("")
                    }
                    .listRowBackground(SettingsListRowBackground())
                    
                    // Posts Settings
                    Section {
                        contentTypeHeader(
                            icon: "square.grid.3x3",
                            title: "Publicaciones",
                            description: "Controla quién puede ver tus publicaciones"
                        )
                        
                        // Current post audience
                        Button(action: { showingPostAudienceSelector = true }) {
                            currentAudienceRow(
                                audience: viewModel.postAudience,
                                customListName: viewModel.postCustomListName,
                                customCount: viewModel.postCustomUsers.count
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                    } header: {
                        Text("")
                    }
                    .listRowBackground(SettingsListRowBackground())
                    
                    // Hidden From Settings
                    Section {
                        NavigationLink(destination: HiddenFromView(viewModel: viewModel)) {
                            HStack {
                                Image(systemName: "eye.slash")
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .font(.system(size: 18))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ocultar mi contenido de")
                                        .font(.custom("Poppins-Medium", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("\(viewModel.hiddenFromUsers.count) personas no pueden ver tu contenido")
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                            }
                        }
                        
                    } header: {
                        Text("Restricciones adicionales")
                    }
                    .listRowBackground(SettingsListRowBackground())
                    
                    // Quick Lists Management
                    Section {
                        NavigationLink(destination: CustomAudienceListsView()) {
                            HStack {
                                Image(systemName: "list.bullet.rectangle")
                                    .foregroundColor(Color(hex: "00A896"))
                                    .font(.system(size: 18))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gestionar listas personalizadas")
                                        .font(.custom("Poppins-Medium", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("Crear y editar listas de audiencia")
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                            }
                        }
                    } header: {
                        Text("Listas de audiencia")
                    }
                    .listRowBackground(SettingsListRowBackground())
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Privacidad del Contenido")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.loadSettings {
                isLoading = false
            }
        }
        .sheet(isPresented: $showingStoryAudienceSelector) {
            StoryAudienceSelector(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPostAudienceSelector) {
            PostAudienceSelector(viewModel: viewModel)
        }
        // ✅ NUEVO: Sheet para configuración de interacciones
        .sheet(isPresented: $showingStoryInteractionSettings) {
            StoryInteractionSettingsView(viewModel: viewModel)
        }
    }
    
    // ✅ NUEVA FUNCIÓN: Resumen de configuración de interacciones
    private func getInteractionSummary() -> String {
        let activeCount = [
            viewModel.allowStoryMessages,
            viewModel.allowStoryReactions,
            viewModel.allowStoryEphemeralPhotos
        ].filter { $0 }.count
        
        switch activeCount {
        case 3: return "Todas las interacciones permitidas"
        case 2: return "Algunas interacciones permitidas"
        case 1: return "Interacciones limitadas"
        case 0: return "Sin interacciones"
        default: return "Configurar interacciones"
        }
    }
    
    private func contentTypeHeader(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Color(hex: "00A896"))
                    .font(.system(size: 20))
                
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            Text(description)
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
    
    private func currentAudienceRow(audience: ContentAudience, customListName: String?, customCount: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "00A896").opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: audience.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(hex: "00A896"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(getAudienceDisplayTitle(audience: audience, customListName: customListName))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(getAudienceDisplayDescription(audience: audience, customCount: customCount))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    private func getAudienceDisplayTitle(audience: ContentAudience, customListName: String?) -> String {
        if audience == .customList, let listName = customListName {
            return listName
        }
        return audience.title
    }
    
    private func getAudienceDisplayDescription(audience: ContentAudience, customCount: Int) -> String {
        switch audience {
        case .custom:
            return customCount > 0 ? "\(customCount) personas seleccionadas" : "Selección personalizada"
        case .customList:
            return "Lista personalizada"
        default:
            return audience.description
        }
    }
}

// ✅ NUEVA VISTA: Modal de configuración de interacciones
struct StoryInteractionSettingsView: View {
    @ObservedObject var viewModel: ContentVisibilityViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header informativo
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(Color(hex: "00A896"))
                            .font(.system(size: 18))
                        
                        Text("Configuración de Interacciones")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    Text("Controla qué tipo de interacciones pueden hacer otros usuarios en tus historias. Esta configuración se aplicará a todas tus historias futuras.")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "00A896").opacity(0.1))
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Opciones de configuración
                VStack(spacing: 16) {
                    InteractionToggleRow(
                        icon: "message.fill",
                        title: "Mensajes",
                        description: "Permite que te envíen mensajes privados desde tus historias",
                        isOn: $viewModel.allowStoryMessages
                    )
                    
                    InteractionToggleRow(
                        icon: "heart.fill",
                        title: "Reacciones",
                        description: "Permite que reaccionen con emojis a tus historias",
                        isOn: $viewModel.allowStoryReactions
                    )
                    
                    InteractionToggleRow(
                        icon: "camera.fill",
                        title: "Fotos efímeras",
                        description: "Permite que envíen fotos como respuesta a tus historias",
                        isOn: $viewModel.allowStoryEphemeralPhotos
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)
                
                Spacer()
                
                // Información adicional
                if !viewModel.allowStoryMessages && !viewModel.allowStoryReactions && !viewModel.allowStoryEphemeralPhotos {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 24))
                            .foregroundColor(.orange)
                        
                        Text("Modo solo visualización")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.orange)
                        
                        Text("Los usuarios solo podrán ver tus historias, sin poder interactuar")
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(Color(colorScheme == .dark ? .black : .white).ignoresSafeArea())
            .navigationTitle("Interacciones")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        viewModel.saveStoryInteractionSettings()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// ✅ NUEVO COMPONENTE: Row para cada toggle
struct InteractionToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Ícono
            ZStack {
                Circle()
                    .fill(Color(hex: "00A896").opacity(isOn ? 0.2 : 0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isOn ? Color(hex: "00A896") : .gray)
            }
            
            // Texto
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(description)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "00A896")))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Story Audience Selector
struct StoryAudienceSelector: View {
    @ObservedObject var viewModel: ContentVisibilityViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            AudienceSelectionView(
                selectedAudience: $viewModel.storyAudience,
                selectedListId: $viewModel.storyCustomListId,
                selectedListName: $viewModel.storyCustomListName,
                customSelectedUsers: $viewModel.storyCustomUsers
            )
            .navigationTitle("Audiencia de Historias")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        viewModel.saveStorySettings()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Post Audience Selector
struct PostAudienceSelector: View {
    @ObservedObject var viewModel: ContentVisibilityViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            AudienceSelectionView(
                selectedAudience: $viewModel.postAudience,
                selectedListId: $viewModel.postCustomListId,
                selectedListName: $viewModel.postCustomListName,
                customSelectedUsers: $viewModel.postCustomUsers
            )
            .navigationTitle("Audiencia de Publicaciones")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") {
                        viewModel.savePostSettings()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Updated ViewModel
class ContentVisibilityViewModel: ObservableObject {
    // Story settings
    @Published var storyAudience: ContentAudience = .everyone
    @Published var storyCustomListId: String?
    @Published var storyCustomListName: String?
    @Published var storyCustomUsers: [String] = []
    @Published var allowStoryMessages: Bool = true
    @Published var allowStoryReactions: Bool = true
    @Published var allowStoryEphemeralPhotos: Bool = true
    
    // Post settings
    @Published var postAudience: ContentAudience = .everyone
    @Published var postCustomListId: String?
    @Published var postCustomListName: String?
    @Published var postCustomUsers: [String] = []
    
    // Hidden from settings
    @Published var hiddenFromUsers: [AppUser] = []
    
    private let firestoreService = FirestoreService()
    
    func loadSettings(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion()
            return
        }
        
        firestoreService.db.collection("users").document(userId).getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                if let document = document, document.exists,
                   let data = document.data(),
                   let visibilitySettings = data["contentVisibilitySettings"] as? [String: Any] {
                    
                    // Load story settings
                    if let storyAudience = visibilitySettings["storyAudience"] as? String {
                        self?.storyAudience = ContentAudience(rawValue: storyAudience) ?? .everyone
                    }
                    self?.storyCustomListId = visibilitySettings["storyCustomListId"] as? String
                    self?.storyCustomListName = visibilitySettings["storyCustomListName"] as? String
                    self?.storyCustomUsers = visibilitySettings["storyCustomUsers"] as? [String] ?? []
                    // ✅ CARGAR configuración de interacciones
                    self?.allowStoryMessages = visibilitySettings["allowStoryMessages"] as? Bool ?? true
                    self?.allowStoryReactions = visibilitySettings["allowStoryReactions"] as? Bool ?? true
                    self?.allowStoryEphemeralPhotos = visibilitySettings["allowStoryEphemeralPhotos"] as? Bool ?? true
                    
                    // Load post settings
                    if let postAudience = visibilitySettings["postAudience"] as? String {
                        self?.postAudience = ContentAudience(rawValue: postAudience) ?? .everyone
                    }
                    self?.postCustomListId = visibilitySettings["postCustomListId"] as? String
                    self?.postCustomListName = visibilitySettings["postCustomListName"] as? String
                    self?.postCustomUsers = visibilitySettings["postCustomUsers"] as? [String] ?? []
                    
                    // Load hidden from users
                    if let hiddenUserIds = visibilitySettings["hiddenFromUsers"] as? [String] {
                        self?.loadHiddenUsers(userIds: hiddenUserIds)
                    }
                }
                completion()
            }
        }
    }
    
    func saveStorySettings() {
        saveSettings(
            audienceKey: "storyAudience",
            audience: storyAudience,
            listIdKey: "storyCustomListId",
            listId: storyCustomListId,
            listNameKey: "storyCustomListName",
            listName: storyCustomListName,
            customUsersKey: "storyCustomUsers",
            customUsers: storyCustomUsers
        )
    }
    
    func savePostSettings() {
        saveSettings(
            audienceKey: "postAudience",
            audience: postAudience,
            listIdKey: "postCustomListId",
            listId: postCustomListId,
            listNameKey: "postCustomListName",
            listName: postCustomListName,
            customUsersKey: "postCustomUsers",
            customUsers: postCustomUsers
        )
    }
    
    // ✅ FUNCIÓN para guardar configuración de interacciones
    func saveStoryInteractionSettings() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        firestoreService.db.collection("users").document(userId).updateData([
            "contentVisibilitySettings.allowStoryMessages": allowStoryMessages,
            "contentVisibilitySettings.allowStoryReactions": allowStoryReactions,
            "contentVisibilitySettings.allowStoryEphemeralPhotos": allowStoryEphemeralPhotos
        ]) { error in
            if let error = error {
                print("Error saving story interaction settings: \(error)")
            }
        }
    }
    
    private func saveSettings(
        audienceKey: String,
        audience: ContentAudience,
        listIdKey: String,
        listId: String?,
        listNameKey: String,
        listName: String?,
        customUsersKey: String,
        customUsers: [String]
    ) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        var settings: [String: Any] = [
            audienceKey: audience.rawValue,
            customUsersKey: customUsers,
            "hiddenFromUsers": hiddenFromUsers.map { $0.id }
        ]
        
        if let listId = listId {
            settings[listIdKey] = listId
        }
        if let listName = listName {
            settings[listNameKey] = listName
        }
        
        firestoreService.db.collection("users").document(userId).updateData([
            "contentVisibilitySettings": settings
        ]) { error in
            if let error = error {
                print("Error saving content visibility settings: \(error)")
            }
        }
    }
    
    private func loadHiddenUsers(userIds: [String]) {
        guard !userIds.isEmpty else { return }
        
        firestoreService.fetchUsers(userIds: userIds) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self?.hiddenFromUsers = users
                case .failure(let error):
                    print("Error loading hidden users: \(error)")
                }
            }
        }
    }
}

// MARK: - Hidden From View y UserRowView (sin cambios)
struct HiddenFromView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: ContentVisibilityViewModel
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    
    var body: some View {
        VStack {
            // Info header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(Color(hex: "00A896"))
                    
                    Text("Información")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                Text("Las personas en esta lista no podrán ver tu contenido, pero aún pueden encontrar tu perfil y enviarte mensajes.")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "00A896").opacity(0.1))
            )
            .padding(.horizontal)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Buscar personas...", text: $searchText)
                    .font(.custom("Poppins-Regular", size: 16))
                    .onChange(of: searchText) { newValue in
                        if !newValue.isEmpty {
                            searchUsers(query: newValue)
                        } else {
                            searchResults = []
                        }
                    }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal)
            
            if isSearching {
                ProgressView("Buscando...")
                    .padding()
            } else {
                List {
                    if !viewModel.hiddenFromUsers.isEmpty {
                        Section("Oculto de estas personas") {
                            ForEach(viewModel.hiddenFromUsers) { user in
                                UserRowView(user: user, isSelected: true) {
                                    viewModel.hiddenFromUsers.removeAll { $0.id == user.id }
                                    viewModel.saveStorySettings()
                                    viewModel.savePostSettings()
                                }
                            }
                        }
                        .listRowBackground(SettingsListRowBackground())
                    }
                    
                    if !searchResults.isEmpty {
                        Section("Resultados de búsqueda") {
                            ForEach(searchResults) { user in
                                let isHidden = viewModel.hiddenFromUsers.contains { $0.id == user.id }
                                UserRowView(user: user, isSelected: isHidden) {
                                    if isHidden {
                                        viewModel.hiddenFromUsers.removeAll { $0.id == user.id }
                                    } else {
                                        viewModel.hiddenFromUsers.append(user)
                                    }
                                    viewModel.saveStorySettings()
                                    viewModel.savePostSettings()
                                }
                            }
                        }
                        .listRowBackground(SettingsListRowBackground())
                    } else if viewModel.hiddenFromUsers.isEmpty && searchText.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "eye.slash.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                
                                Text("No has ocultado tu contenido de nadie")
                                    .font(.custom("Poppins-Regular", size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                Text("Busca personas para ocultar tu contenido de ellas")
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                        .listRowBackground(SettingsListRowBackground())
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Ocultar Contenido")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
    
    private func searchUsers(query: String) {
        isSearching = true
        
        FirestoreService().searchUsers(query: query, limit: 10) { result in
            DispatchQueue.main.async {
                self.isSearching = false
                switch result {
                case .success(let users):
                    self.searchResults = users
                case .failure(let error):
                    print("Error searching users: \(error)")
                    self.searchResults = []
                }
            }
        }
    }
}

struct UserRowView: View {
    @Environment(\.colorScheme) var colorScheme
    let user: AppUser
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.custom("Poppins-Regular", size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: onTap) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "00A896"))
                        .font(.system(size: 20))
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
