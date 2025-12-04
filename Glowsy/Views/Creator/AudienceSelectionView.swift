import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Enum de audiencia
enum ContentAudience: String, Codable, CaseIterable {
    case everyone = "everyone"
    case connections = "connections"
    case bestFriends = "bestFriends"
    case custom = "custom"
    case customList = "customList" // Nuevo caso para listas
    case onlyMe = "onlyMe"
    
    var title: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.type.everyone", comment: "Everyone audience type")
        case .connections: return NSLocalizedString("audience.type.connections", comment: "Connections audience type")
        case .bestFriends: return NSLocalizedString("audience.type.bestFriends", comment: "Best friends audience type")
        case .custom: return NSLocalizedString("audience.type.custom", comment: "Custom audience type")
        case .customList: return NSLocalizedString("audience.type.customList", comment: "Custom list audience type")
        case .onlyMe: return NSLocalizedString("audience.type.onlyMe", comment: "Only me audience type")
        }
    }
    
    var description: String {
        switch self {
        case .everyone: return NSLocalizedString("audience.description.everyone", comment: "Everyone audience description")
        case .connections: return NSLocalizedString("audience.description.connections", comment: "Connections audience description")
        case .bestFriends: return NSLocalizedString("audience.description.bestFriends", comment: "Best friends audience description")
        case .custom: return NSLocalizedString("audience.description.custom", comment: "Custom audience description")
        case .customList: return NSLocalizedString("audience.description.customList", comment: "Custom list audience description")
        case .onlyMe: return NSLocalizedString("audience.description.onlyMe", comment: "Only me audience description")
        }
    }
    
    var icon: String {
        switch self {
        case .everyone: return "globe"
        case .connections: return "person.2.fill"
        case .bestFriends: return "heart.circle.fill"
        case .custom: return "person.crop.circle.badge.plus"
        case .customList: return "list.bullet.rectangle"
        case .onlyMe: return "lock.fill"
        }
    }
}

// MARK: - Vista Principal de Selección de Audiencia (REDISEÑADA)
struct AudienceSelectionView: View {
    @Binding var selectedAudience: ContentAudience
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomSelector = false
    @State private var showingCreateList = false
    @State private var showingManageLists = false
    @State private var customLists: [CustomAudienceList] = []
    @State private var isLoadingLists = false
    @State private var selectedUsersForCustom: [AppUser] = []
    @State private var listToDelete: CustomAudienceList? // Add for deletion
    @State private var showingDeleteAlert = false // Add for deletion alert
    @State private var showingSaveFeedback = false // Para mostrar feedback de guardado
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // ✅ Handle superior (estilo ContextMenu)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3))
                                .frame(width: 40, height: 5)
                                .padding(.top, 12)
                                .padding(.bottom, 20)
                            
                            // ✅ Título principal
                            VStack(spacing: 8) {
                                Text("audience.selection.title")
                                    .font(.custom("Poppins-Bold", size: 24))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("audience.selection.subtitle")
                                    .font(.custom("Poppins-Regular", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                            
                            // ✅ Contenido principal con estilo ContextMenu
                            VStack(spacing: 16) {
                                predefinedAudienceSection
                                customListsSection
                                manualSelectionSection
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingCustomSelector) {
                customSelectorSheet
            }
            .sheet(isPresented: $showingCreateList) {
                CreateCustomListView()
                    .onDisappear { loadCustomLists() }
            }
            .sheet(isPresented: $showingManageLists) {
                CustomAudienceListsView()
                    .onDisappear { loadCustomLists() }
            }
            .onAppear {
                loadCustomLists()
                loadSelectedUsersInfo()
            }

            .overlay(
                // ✅ Feedback de guardado
                Group {
                    if showingSaveFeedback {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                
                                Text("audience.saved")
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color(hex: "00A896"))
                                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                            .padding(.bottom, 100)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showingSaveFeedback)
                    }
                }
            )
        }
    }
    
    private var predefinedAudienceSection: some View {
        VStack(spacing: 12) {
            // ✅ Header de sección con estilo moderno
            HStack {
                Text("audience.predefined")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // ✅ Opciones con estilo ContextMenu
            VStack(spacing: 8) {
                AudienceOptionRowModern(
                    audience: .everyone,
                    isSelected: selectedAudience == .everyone,
                    customCount: nil,
                    onTap: {
                        selectedAudience = .everyone
                        selectedListId = nil
                        selectedListName = nil
                        customSelectedUsers = []
                        showSaveFeedback()
                    }
                )
                
                AudienceOptionRowModern(
                    audience: .connections,
                    isSelected: selectedAudience == .connections,
                    customCount: nil,
                    onTap: {
                        selectedAudience = .connections
                        selectedListId = nil
                        selectedListName = nil
                        customSelectedUsers = []
                        showSaveFeedback()
                    }
                )
                
                AudienceOptionRowModern(
                    audience: .bestFriends,
                    isSelected: selectedAudience == .bestFriends,
                    customCount: nil,
                    onTap: {
                        selectedAudience = .bestFriends
                        selectedListId = nil
                        selectedListName = nil
                        customSelectedUsers = []
                        showSaveFeedback()
                    }
                )
                
                AudienceOptionRowModern(
                    audience: .onlyMe,
                    isSelected: selectedAudience == .onlyMe,
                    customCount: nil,
                    onTap: {
                        selectedAudience = .onlyMe
                        selectedListId = nil
                        selectedListName = nil
                        customSelectedUsers = []
                        showSaveFeedback()
                    }
                )
            }
        }
    }
    
    private var customListsSection: some View {
        VStack(spacing: 12) {
            // ✅ Header con botón de gestión
            HStack {
                Text("audience.customLists")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
                Button(action: { showingManageLists = true }) {
                    Text("audience.manage")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(Color(hex: "00A896"))
                }
            }
            .padding(.horizontal, 4)
            
            if isLoadingLists {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("audience.loadingLists")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                .padding()
            } else if customLists.isEmpty {
                emptyCustomListsViewModern
            } else {
                VStack(spacing: 8) {
                    ForEach(customLists) { list in
                        CustomListRowModern(
                            list: list,
                            isSelected: selectedAudience == .customList && selectedListId == list.id,
                            onTap: {
                                selectedAudience = .customList
                                selectedListId = list.id
                                selectedListName = list.name
                                customSelectedUsers = []
                                showSaveFeedback()
                            },
                            onDelete: {
                                listToDelete = list
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
            }
        }
    }
    
    private var emptyCustomListsViewModern: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "00A896").opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "00A896"))
            }
            
            VStack(spacing: 4) {
                Text("audience.noCustomLists.title")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("audience.noCustomLists.description")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingCreateList = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("audience.createFirstList")
                        .font(.custom("Poppins-Medium", size: 14))
                }
                .foregroundColor(Color(hex: "00A896"))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "00A896").opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                    Color(hex: "00A896").opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var manualSelectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("audience.manualSelection")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            Button(action: {
                selectedAudience = .custom
                showingCustomSelector = true
                showSaveFeedback()
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(selectedAudience == .custom && selectedListId == nil ?
                                  Color(hex: "00A896").opacity(0.15) :
                                  (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(selectedAudience == .custom && selectedListId == nil ?
                                             Color(hex: "00A896") : (colorScheme == .dark ? .white : .black))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("audience.custom")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(customSelectedUsers.isEmpty ?
                             NSLocalizedString("audience.description.custom", comment: "Custom audience description") :
                             String(format: NSLocalizedString("audience.people.count", comment: "People count"), customSelectedUsers.count))
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    if selectedAudience == .custom && selectedListId == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "00A896"))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    selectedAudience == .custom && selectedListId == nil ?
                                    Color(hex: "00A896").opacity(0.3) :
                                    (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var customSelectorSheet: some View {
        NavigationView {
            CustomAudienceSelector(selectedUsers: $selectedUsersForCustom) {
                customSelectedUsers = selectedUsersForCustom.map { $0.id }
                showingCustomSelector = false
            }
            .navigationTitle(NSLocalizedString("audience.actions.selectPeople", comment: "Select people navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("audience.actions.cancel", comment: "Cancel action")) {
                        showingCustomSelector = false
                    }
                    .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func loadCustomLists() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoadingLists = true
        FirestoreService().fetchCustomLists(for: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let lists):
                    self.customLists = lists
                case .failure(let error):
                    self.customLists = []
                }
                self.isLoadingLists = false
            }
        }
    }
    
    private func loadSelectedUsersInfo() {
        guard !customSelectedUsers.isEmpty else { return }
        FirestoreService().fetchUsers(userIds: customSelectedUsers) { result in
            if case .success(let users) = result {
                DispatchQueue.main.async {
                    self.selectedUsersForCustom = users
                }
            }
        }
    }
    
    // ✅ Función para mostrar feedback de guardado
    private func showSaveFeedback() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showingSaveFeedback = true
        }
        
        // Auto-dismiss después de 2 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSaveFeedback = false
            }
        }
    }
}

// MARK: - Fila de Lista Personalizada
struct CustomListRow: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icono
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                            .font(.custom("Poppins-Regular", size: 13))
                    }
                    .foregroundColor(.gray)
                    
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ?
                          Color(hex: list.color ?? "00A896").opacity(0.1) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        Color(hex: list.color ?? "00A896").opacity(0.5) :
                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Modelo de Lista de Audiencia Personalizada
struct CustomAudienceList: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let description: String?
    let members: [String] // Array de user IDs
    let createdAt: Date
    let updatedAt: Date
    let color: String? // Para identificar visualmente las listas
    let icon: String? // Nombre del SF Symbol
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case members
        case createdAt
        case updatedAt
        case color
        case icon
    }
    
    init(id: String? = nil,
         name: String,
         description: String? = nil,
         members: [String] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         color: String? = nil,
         icon: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.color = color
        self.icon = icon
    }
    // Equatable conformance
        static func == (lhs: CustomAudienceList, rhs: CustomAudienceList) -> Bool {
            lhs.id == rhs.id
        }
    }

// MARK: - Extensión para colores predefinidos
extension CustomAudienceList {
    static let predefinedColors = [
        "FF6B6B", // Rojo
        "4ECDC4", // Turquesa
        "45B7D1", // Azul
        "FFA07A", // Salmón
        "98D8C8", // Menta
        "F7DC6F", // Amarillo
        "BB8FCE", // Púrpura
        "85C1E2"  // Azul claro
    ]
    
    static let predefinedIcons = [
        "person.3.fill",
        "briefcase.fill",
        "house.fill",
        "graduationcap.fill",
        "heart.fill",
        "star.fill",
        "flag.fill",
        "bolt.fill"
    ]
}

// MARK: - Fila de Opción de Audiencia (ESTILO MODERNO)
struct AudienceOptionRowModern: View {
    @Environment(\.colorScheme) var colorScheme
    let audience: ContentAudience
    let isSelected: Bool
    let customCount: Int?
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // ✅ Icono con estilo moderno
                ZStack {
                    Circle()
                        .fill(isSelected ?
                              Color(hex: "00A896").opacity(0.15) :
                              (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: audience.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ?
                                       Color(hex: "00A896") : (colorScheme == .dark ? .white : .black))
                }
                
                // ✅ Texto con mejor jerarquía
                VStack(alignment: .leading, spacing: 2) {
                    Text(audience.title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if let count = customCount {
                        Text("\(count) personas")
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    } else {
                        Text(audience.description)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // ✅ Checkmark o chevron
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "00A896"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ?
                                Color(hex: "00A896").opacity(0.3) :
                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Fila de Lista Personalizada (ESTILO MODERNO)
struct CustomListRowModern: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // ✅ Icono con color personalizado
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.15 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                // ✅ Información de la lista
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                            .font(.custom("Poppins-Regular", size: 13))
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    
                    if let description = list.description, !description.isEmpty {
                        Text(description)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // ✅ Checkmark o chevron
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ?
                                Color(hex: list.color ?? "00A896").opacity(0.3) :
                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Fila de Opción de Audiencia
struct AudienceOptionRow: View {
    @Environment(\.colorScheme) var colorScheme
    let audience: ContentAudience
    let isSelected: Bool
    let customCount: Int?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icono
                ZStack {
                    Circle()
                        .fill(isSelected ?
                              Color(hex: "00A896").opacity(0.2) :
                              (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: audience.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ?
                                       Color(hex: "00A896") : (colorScheme == .dark ? .white : .black))
                }
                
                // Texto
                VStack(alignment: .leading, spacing: 4) {
                    Text(audience.title)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if let count = customCount {
                        Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), count))
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.gray)
                    } else {
                        Text(audience.description)
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "00A896"))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ?
                          Color(hex: "00A896").opacity(0.1) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        Color(hex: "00A896").opacity(0.5) :
                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Selector de Audiencia Personalizada
struct CustomAudienceSelector: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedUsers: [AppUser]
    let onComplete: () -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @StateObject private var firestoreService = FirestoreService()
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            VStack {
                // Barra de búsqueda
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Buscar personas...", text: $searchText)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .onChange(of: searchText) { newValue in
                            if !newValue.isEmpty {
                                searchUsers(query: newValue)
                            }
                        }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding()
                
                if isSearching {
                    ProgressView()
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { user in
                                UserSelectionCard(
                                    user: user,
                                    isSelected: selectedUsers.contains { $0.id == user.id },
                                    onToggle: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if let index = selectedUsers.firstIndex(where: { $0.id == user.id }) {
                                                selectedUsers.remove(at: index)
                                            } else {
                                                selectedUsers.append(user)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
                
                // Botón de completar
                if !selectedUsers.isEmpty {
                    Button(action: onComplete) {
                        Text(String(format: NSLocalizedString("audience.selectPeople", comment: "Select people"), selectedUsers.count))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "00A896"))
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
        }
    }
    
    private func searchUsers(query: String) {
        isSearching = true
        firestoreService.searchUsers(query: query, limit: 20) { result in
            DispatchQueue.main.async {
                self.isSearching = false
                switch result {
                case .success(let users):
                    self.searchResults = users
                case .failure(let error):
                    self.searchResults = []
                }
            }
        }
    }
}

// MARK: - Fila de Selección de Usuario
struct UserSelectionRow: View {
    let user: AppUser
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Avatar
                AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
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
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                // Info del usuario
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(user.username)")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(hex: "00A896") : .gray)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Vista de Gestión de Listas Personalizadas
struct CustomAudienceListsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CustomAudienceListsViewModel()
    @State private var showingCreateList = false
    @State private var selectedList: CustomAudienceList?
    @State private var showingDeleteAlert = false
    @State private var listToDelete: CustomAudienceList?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView("Cargando listas...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .foregroundColor(.gray)
                } else {
                    VStack {
                        if viewModel.lists.isEmpty {
                            emptyStateView
                        } else {
                            listContent
                        }
                    }
                }
            }
            .navigationTitle("Listas Personalizadas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreateList = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(Color(hex: "00A896"))
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateList) {
            CreateCustomListView()
        }
        .sheet(item: $selectedList) { list in
            EditCustomListView(list: list)
        }
        .alert("Eliminar lista", isPresented: $showingDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let list = listToDelete {
                    viewModel.deleteList(list)
                }
            }
        } message: {
                            Text("audience.deleteList.confirm")
        }
        .onAppear {
            viewModel.loadLists()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
                            Text("audience.noCustomLists.title")
                .font(.custom("Poppins-SemiBold", size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
                            Text("audience.noCustomLists.description")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: { showingCreateList = true }) {
                Label("Crear primera lista", systemImage: "plus.circle.fill")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "00A896"), Color(hex: "00A896").opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.top, 10)
        }
    }
    
    private var listContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.lists) { list in
                    ManageableCustomListRow(
                        list: list,
                        onEdit: { selectedList = list },
                        onDelete: {
                            listToDelete = list
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Fila de Lista Administrable
struct ManageableCustomListRow: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icono
            ZStack {
                Circle()
                    .fill(Color(hex: list.color ?? "00A896").opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: list.icon ?? "person.3.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color(hex: list.color ?? "00A896"))
            }
            
            // Información de la lista
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                    Text(String(format: NSLocalizedString("audience.people.count", comment: "People count"), list.members.count))
                        .font(.custom("Poppins-Regular", size: 13))
                }
                .foregroundColor(.gray)
                
                if let description = list.description, !description.isEmpty {
                    Text(description)
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Botones de acción
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "00A896"))
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - ViewModel
class CustomAudienceListsViewModel: ObservableObject {
    @Published var lists: [CustomAudienceList] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    deinit {
        listener?.remove()
    }
    
    func loadLists() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        listener?.remove()
        listener = db.collection("users").document(userId)
            .collection("customAudienceLists")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.lists = []
                    self.isLoading = false
                    return
                }
                
                self.lists = documents.compactMap { doc in
                    try? doc.data(as: CustomAudienceList.self)
                }
                
                self.isLoading = false
            }
    }
    
    func deleteList(_ list: CustomAudienceList) {
        guard let userId = Auth.auth().currentUser?.uid,
              let listId = list.id else { return }
        
        db.collection("users").document(userId)
            .collection("customAudienceLists")
            .document(listId)
            .delete { error in
                if let error = error {
                }
            }
    }
}

// MARK: - Crear Nueva Lista
struct CreateCustomListView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateListViewModel()
    
    @State private var listName = ""
    @State private var listDescription = ""
    @State private var selectedColor = CustomAudienceList.predefinedColors.first!
    @State private var selectedIcon = CustomAudienceList.predefinedIcons.first!
    @State private var selectedMembers: Set<String> = []
    @State private var showingMemberPicker = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Nombre de la lista
                        VStack(alignment: .leading, spacing: 8) {
                            Text("audience.list.name")
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(.gray)
                            
                            TextField("Ej: Trabajo, Familia, Amigos cercanos...", text: $listName)
                                .font(.custom("Poppins-Regular", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                                .cornerRadius(12)
                        }
                        
                        // Descripción
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Descripción (opcional)")
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(.gray)
                            
                            TextField("Describe esta lista...", text: $listDescription)
                                .font(.custom("Poppins-Regular", size: 16))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                                .cornerRadius(12)
                        }
                        
                        // Color e icono
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Personalización")
                                .font(.custom("Poppins-SemiBold", size: 14))
                                .foregroundColor(.gray)
                            
                            // Selector de color
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(CustomAudienceList.predefinedColors, id: \.self) { color in
                                        Circle()
                                            .fill(Color(hex: color))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                            )
                                            .onTapGesture {
                                                selectedColor = color
                                            }
                                    }
                                }
                            }
                            
                            // Selector de icono
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(CustomAudienceList.predefinedIcons, id: \.self) { icon in
                                        ZStack {
                                            Circle()
                                                .fill(selectedIcon == icon ?
                                                      Color(hex: selectedColor).opacity(0.2) :
                                                      (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                                                .frame(width: 50, height: 50)
                                            
                                            Image(systemName: icon)
                                                .foregroundColor(selectedIcon == icon ?
                                                               Color(hex: selectedColor) : .gray)
                                                .font(.system(size: 22))
                                        }
                                        .onTapGesture {
                                            selectedIcon = icon
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Miembros
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("audience.members")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                Button(action: { showingMemberPicker = true }) {
                                    Label("Agregar", systemImage: "plus.circle.fill")
                                        .font(.custom("Poppins-Medium", size: 14))
                                        .foregroundColor(Color(hex: "00A896"))
                                }
                            }
                            
                            if selectedMembers.isEmpty {
                                Text("audience.noMembers")
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                            } else {
                                // ✅ MEJORADO: Feedback visual mejorado para miembros seleccionados
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(hex: selectedColor))
                                        
                                        Text("\(selectedMembers.count) personas seleccionadas")
                                            .font(.custom("Poppins-Medium", size: 14))
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                    }
                                    
                                    Text("Toca 'Agregar' para modificar la selección")
                                        .font(.custom("Poppins-Regular", size: 12))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hex: selectedColor).opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(hex: selectedColor).opacity(0.4), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Nueva Lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .gray : .gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Crear") {
                        viewModel.createList(
                            name: listName,
                            description: listDescription,
                            members: Array(selectedMembers),
                            color: selectedColor,
                            icon: selectedIcon
                        ) {
                            dismiss()
                        }
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .fontWeight(.semibold)
                    .disabled(listName.isEmpty)
                }
            }
            .toolbarBackground(Color(colorScheme == .dark ? .black : .white), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showingMemberPicker) {
            MemberPickerView(selectedMembers: $selectedMembers)
        }
    }
}

// MARK: - Editar Lista (MEJORADA)
struct EditCustomListView: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = EditListViewModel()
    
    @State private var listName: String
    @State private var listDescription: String
    @State private var selectedColor: String
    @State private var selectedIcon: String
    @State private var selectedMembers: Set<String>
    @State private var showingMemberPicker = false
    @State private var currentMembers: [AppUser] = []
    @State private var isLoadingMembers = false
    @State private var searchText = ""
    @State private var filteredMembers: [AppUser] = []
    
    init(list: CustomAudienceList) {
        self.list = list
        _listName = State(initialValue: list.name)
        _listDescription = State(initialValue: list.description ?? "")
        _selectedColor = State(initialValue: list.color ?? CustomAudienceList.predefinedColors.first!)
        _selectedIcon = State(initialValue: list.icon ?? CustomAudienceList.predefinedIcons.first!)
        _selectedMembers = State(initialValue: Set(list.members))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Información básica
                        basicInfoSection
                        
                        Divider().background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                        
                        // Personalización
                        customizationSection
                        
                        Divider().background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                        
                        // Gestión de miembros
                        membersManagementSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Editar Lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Guardar") {
                        viewModel.updateList(
                            listId: list.id!,
                            name: listName,
                            description: listDescription,
                            members: Array(selectedMembers),
                            color: selectedColor,
                            icon: selectedIcon
                        ) {
                            dismiss()
                        }
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .fontWeight(.semibold)
                    .disabled(listName.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingMemberPicker) {
            MemberPickerView(selectedMembers: $selectedMembers)
        }
        .onAppear {
            loadCurrentMembers()
        }
        .onChange(of: searchText) { newValue in
            filterMembers()
        }
        .onChange(of: currentMembers) { _ in
            filterMembers()
        }
    }
    
    private var basicInfoSection: some View {
        VStack(spacing: 16) {
            // Nombre de la lista
            VStack(alignment: .leading, spacing: 8) {
                Text("audience.list.name")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.gray)
                
                TextField("Ej: Trabajo, Familia, Amigos cercanos...", text: $listName)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
            }
            
            // Descripción
            VStack(alignment: .leading, spacing: 8) {
                Text("Descripción (opcional)")
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.gray)
                
                TextField("Describe esta lista...", text: $listDescription)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
            }
        }
    }
    
    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personalización")
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(.gray)
            
            // Selector de color
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.gray)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CustomAudienceList.predefinedColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Selector de icono
            VStack(alignment: .leading, spacing: 8) {
                Text("Icono")
                    .font(.custom("Poppins-Medium", size: 12))
                    .foregroundColor(.gray)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(CustomAudienceList.predefinedIcons, id: \.self) { icon in
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ?
                                          Color(hex: selectedColor).opacity(0.2) :
                                          Color.white.opacity(0.1))
                                    .frame(width: 50, height: 50)
                                
                                Image(systemName: icon)
                                    .foregroundColor(selectedIcon == icon ?
                                                   Color(hex: selectedColor) : .gray)
                                    .font(.system(size: 22))
                            }
                            .onTapGesture {
                                selectedIcon = icon
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private var membersManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header con contador y botón agregar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Miembros")
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.gray)
                    Text("\(selectedMembers.count) personas en la lista")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: { showingMemberPicker = true }) {
                    Label("Agregar", systemImage: "plus.circle.fill")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(Color(hex: "00A896"))
                }
            }
            
            // Buscador dentro de la lista
            if !currentMembers.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                    
                    TextField("Buscar en la lista...", text: $searchText)
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Lista de miembros actuales
            if isLoadingMembers {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Cargando miembros...")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                }
                .padding()
            } else if filteredMembers.isEmpty && !currentMembers.isEmpty {
                Text("No se encontraron miembros con '\(searchText)'")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if currentMembers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                    Text("No hay miembros en esta lista")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.gray)
                    Text("Toca 'Agregar' para añadir personas")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            } else {
                // ✅ MEJORADO: Feedback visual mejorado para miembros existentes
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: selectedColor))
                        
                        Text("\(filteredMembers.count) miembros mostrados")
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    
                    if !searchText.isEmpty {
                        Text("Resultados de búsqueda para '\(searchText)'")
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: selectedColor).opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: selectedColor).opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.bottom, 8)
                
                VStack(spacing: 8) {
                    ForEach(filteredMembers) { member in
                        MemberRowWithRemove(
                            user: member,
                            onRemove: {
                                selectedMembers.remove(member.id)
                                loadCurrentMembers()
                            }
                        )
                    }
                }
            }
        }
    }
    
    private func loadCurrentMembers() {
        guard !selectedMembers.isEmpty else {
            currentMembers = []
            return
        }
        
        isLoadingMembers = true
        FirestoreService().fetchUsers(userIds: Array(selectedMembers)) { result in
            DispatchQueue.main.async {
                self.isLoadingMembers = false
                switch result {
                case .success(let users):
                    self.currentMembers = users
                case .failure(let error):
                    self.currentMembers = []
                }
            }
        }
    }
    
    private func filterMembers() {
        if searchText.isEmpty {
            filteredMembers = currentMembers
        } else {
            filteredMembers = currentMembers.filter { user in
                user.username.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Fila de Miembro con Opción de Eliminar
struct MemberRowWithRemove: View {
    @Environment(\.colorScheme) var colorScheme
    let user: AppUser
    let onRemove: () -> Void
    @State private var showingRemoveAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                    )
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            
            // Info del usuario
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Botón eliminar
            Button(action: { showingRemoveAlert = true }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
        .cornerRadius(8)
        .alert("Eliminar miembro", isPresented: $showingRemoveAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                onRemove()
            }
        } message: {
            Text("¿Eliminar a \(user.username) de esta lista?")
        }
    }
}

// MARK: - Selector de Miembros (MEJORADO)
struct MemberPickerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedMembers: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @StateObject private var firestoreService = FirestoreService()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Barra de búsqueda
                    searchBar
                    
                    // Contenido principal
                    if !hasSearched {
                        initialStateView
                    } else if isSearching {
                        loadingView
                    } else if searchResults.isEmpty {
                        emptyResultsView
                    } else {
                        resultsListView
                    }
                    
                    // Footer con contador
                    if !selectedMembers.isEmpty {
                        selectedCounterFooter
                    }
                }
            }
            .navigationTitle("Agregar Miembros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Confirmar") {
                        // ✅ CONFIRMAR: Cerrar y guardar selección
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "00A896"))
                    .fontWeight(.semibold)
                    .disabled(selectedMembers.isEmpty)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Buscar personas...", text: $searchText)
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .onSubmit {
                    if !searchText.isEmpty {
                        searchUsers(query: searchText)
                    }
                }
                .onChange(of: searchText) { newValue in
                    if newValue.isEmpty {
                        hasSearched = false
                        searchResults = []
                    } else if newValue.count >= 2 {
                        searchUsers(query: newValue)
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    hasSearched = false
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }
    
    private var initialStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Buscar personas")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text("Escribe el nombre de usuario para encontrar personas y agregarlas a tu lista")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Buscando...")
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(.gray)
            Spacer()
        }
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Sin resultados")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(.white)
            
            Text("No se encontraron personas con '\(searchText)'")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
    }
    
    private var resultsListView: some View {
        List {
            ForEach(searchResults) { user in
                UserSelectionRowEnhanced(
                    user: user,
                    isSelected: selectedMembers.contains(user.id),
                    onToggle: {
                        if selectedMembers.contains(user.id) {
                            selectedMembers.remove(user.id)
                        } else {
                            selectedMembers.insert(user.id)
                        }
                    }
                )
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(PlainListStyle())
    }
    
    private var selectedCounterFooter: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.2))
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selectedMembers.count) seleccionadas")
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.white)
                    Text("Personas para agregar a la lista")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // ✅ MEJORADO: Botones más claros y útiles
                HStack(spacing: 12) {
                    Button("Limpiar") {
                        selectedMembers.removeAll()
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(.red)
                    
                    Button("Confirmar") {
                        dismiss()
                    }
                    .font(.custom("Poppins-SemiBold", size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: "00A896"))
                    )
                    .disabled(selectedMembers.isEmpty)
                }
            }
            .padding()
            .background(Color.black)
        }
    }
    
    private func searchUsers(query: String) {
        hasSearched = true
        isSearching = true
        firestoreService.searchUsers(query: query, limit: 20) { result in
            DispatchQueue.main.async {
                self.isSearching = false
                switch result {
                case .success(let users):
                    self.searchResults = users
                case .failure(let error):
                    self.searchResults = []
                }
            }
        }
    }
}

// MARK: - Card de Usuario Mejorada
struct UserSelectionCard: View {
    @Environment(\.colorScheme) var colorScheme
    let user: AppUser
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                // Avatar más grande
                AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        )
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? [Color.blue, Color.purple] : [Color.gray.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                
                // Info del usuario
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Checkbox mejorado
                ZStack {
                    Circle()
                        .fill(
                            isSelected ? 
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) : 
                            LinearGradient(
                                colors: [Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? Color.clear : Color.gray.opacity(0.5),
                                    lineWidth: 2
                                )
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected ? 
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color.gray.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ?
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Fila de Usuario Mejorada
struct UserSelectionRowEnhanced: View {
    @Environment(\.colorScheme) var colorScheme
    let user: AppUser
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Avatar
                AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
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
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                
                // Info del usuario
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.custom("Poppins-Medium", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Checkbox animado
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "00A896") : Color.clear)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.clear : Color.gray, lineWidth: 2)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ViewModels
class CreateListViewModel: ObservableObject {
    private let db = Firestore.firestore()
    
    func createList(name: String, description: String, members: [String], color: String, icon: String, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let newList = CustomAudienceList(
            name: name,
            description: description.isEmpty ? nil : description,
            members: members,
            color: color,
            icon: icon
        )
        
        do {
            try db.collection("users").document(userId)
                .collection("customAudienceLists")
                .addDocument(from: newList) { error in
                    if let error = error {
                    } else {
                        completion()
                    }
                }
        } catch {
        }
    }
}

class EditListViewModel: ObservableObject {
    private let db = Firestore.firestore()
    
    func updateList(listId: String, name: String, description: String, members: [String], color: String, icon: String, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let updateData: [String: Any] = [
            "name": name,
            "description": description.isEmpty ? FieldValue.delete() : description,
            "members": members,
            "color": color,
            "icon": icon,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("users").document(userId)
            .collection("customAudienceLists")
            .document(listId)
            .updateData(updateData) { error in
                if let error = error {
                } else {
                    completion()
                }
            }
    }
}
