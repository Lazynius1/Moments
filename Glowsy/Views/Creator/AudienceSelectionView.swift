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
        case .bestFriends: return "star.fill"
        case .custom: return "person.crop.circle.badge.plus"
        case .customList: return "list.bullet.rectangle"
        case .onlyMe: return "lock.fill"
        }
    }
}

// MARK: - Vista Principal de Selección de Audiencia (REDISEÑADA)
struct AudienceSelectionView: View {
    private enum FlowDestination: Equatable {
        case main
        case customPeople
        case manageLists
        case createList(returnToManageLists: Bool)
        case editList(CustomAudienceList)
    }
    
    @Binding var selectedAudience: ContentAudience
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var flowDestination: FlowDestination = .main
    @State private var navigatingForward = true
    @State private var customLists: [CustomAudienceList] = []
    @State private var isLoadingLists = false
    @State private var selectedUsersForCustom: [AppUser] = []
    @State private var listToDelete: CustomAudienceList? // Add for deletion
    @State private var showingDeleteAlert = false // Add for deletion alert
    @State private var showingSaveFeedback = false // Para mostrar feedback de guardado
    
    var body: some View {
        NavigationView {
            ZStack {
                if case .main = flowDestination {
                    mainContent
                        .transition(flowTransition)
                } else {
                    nestedFlowContent
                        .transition(flowTransition)
                }
            }
            .navigationBarHidden(true)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: flowDestination)
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("audience.saved")
                                        .font(.custom("Poppins-Medium", size: 16))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(Color(hex: "007AFF"))
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
    
    private var flowTransition: AnyTransition {
        if navigatingForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
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
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    
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
    
    @ViewBuilder
    private var nestedFlowContent: some View {
        switch flowDestination {
        case .main:
            EmptyView()
        case .customPeople:
            CustomAudienceSelector(
                selectedUsers: $selectedUsersForCustom,
                onComplete: {
                    customSelectedUsers = selectedUsersForCustom.map(\.id)
                    navigate(to: .main, forward: false)
                },
                onBack: {
                    navigate(to: .main, forward: false)
                },
                embeddedInFlow: true
            )
        case .manageLists:
            CustomAudienceListsView(
                embeddedInFlow: true,
                onBack: {
                    loadCustomLists()
                    navigate(to: .main, forward: false)
                },
                onCreateList: {
                    navigate(to: .createList(returnToManageLists: true))
                },
                onEditList: { list in
                    navigate(to: .editList(list))
                },
                onListsChanged: {
                    loadCustomLists()
                }
            )
        case .createList(let returnToManageLists):
            CreateCustomListView(
                embeddedInFlow: true,
                onBack: {
                    navigate(to: returnToManageLists ? .manageLists : .main, forward: false)
                },
                onCompleted: {
                    loadCustomLists()
                    navigate(to: returnToManageLists ? .manageLists : .main, forward: false)
                }
            )
        case .editList(let list):
            EditCustomListView(
                list: list,
                embeddedInFlow: true,
                onBack: {
                    navigate(to: .manageLists, forward: false)
                },
                onCompleted: {
                    loadCustomLists()
                    navigate(to: .manageLists, forward: false)
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
            // ✅ Grid de opciones 2x2
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                AudienceGridCard(
                    audience: .everyone,
                    isSelected: selectedAudience == .everyone,
                    onTap: {
                        selectedAudience = .everyone
                        resetSelection()
                        showSaveFeedback()
                    }
                )
                
                AudienceGridCard(
                    audience: .connections,
                    isSelected: selectedAudience == .connections,
                    onTap: {
                        selectedAudience = .connections
                        resetSelection()
                        showSaveFeedback()
                    }
                )
                
                AudienceGridCard(
                    audience: .bestFriends,
                    isSelected: selectedAudience == .bestFriends,
                    onTap: {
                        selectedAudience = .bestFriends
                        resetSelection()
                        showSaveFeedback()
                    }
                )
                
                AudienceGridCard(
                    audience: .onlyMe,
                    isSelected: selectedAudience == .onlyMe,
                    onTap: {
                        selectedAudience = .onlyMe
                        resetSelection()
                        showSaveFeedback()
                    }
                )
            }
        }
    }

    private func resetSelection() {
        selectedListId = nil
        selectedListName = nil
        customSelectedUsers = []
    }
    
    private var customListsSection: some View {
        VStack(spacing: 12) {
            // ✅ Header con botón de gestión
            HStack {
                Text("audience.customLists")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
                Button(action: { navigate(to: .manageLists) }) {
                    Text("audience.manage")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(Color(hex: "007AFF"))
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // ✅ Botón de Añadir rápido
                        Button(action: { navigate(to: .createList(returnToManageLists: false)) }) {
                            VStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(hex: "007AFF"))
                                    .frame(width: 48, height: 48)
                                    .liquidGlass(in: Circle(), interactive: true)
                                Text("audience.create")
                                    .font(.custom("Poppins-Medium", size: 14))
                                    .foregroundColor(Color(hex: "007AFF"))
                            }
                            .frame(width: 100, height: 140)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color(hex: "007AFF").opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                        }
                        
                        ForEach(customLists) { list in
                            CustomListCard(
                                list: list,
                                isSelected: selectedAudience == .customList && selectedListId == list.id,
                                onTap: {
                                    selectedAudience = .customList
                                    selectedListId = list.id
                                    selectedListName = list.name
                                    customSelectedUsers = []
                                    showSaveFeedback()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private var emptyCustomListsViewModern: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.primary)
            
            VStack(spacing: 4) {
                Text("audience.noCustomLists.title")
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("audience.noCustomLists.description")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { navigate(to: .createList(returnToManageLists: false)) }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .liquidGlass(in: Circle(), interactive: true)
                    Text("audience.createFirstList")
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.primary)
                }
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
                                    Color(hex: "007AFF").opacity(0.2)
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
                navigate(to: .customPeople)
            }) {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 36, height: 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("audience.custom")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(customSelectedUsers.isEmpty ?
                             NSLocalizedString("audience.description.custom", comment: "Custom audience description") :
                             String(format: NSLocalizedString("audience.people.count", comment: "People count"), customSelectedUsers.count))
                            .font(.custom("Poppins-Regular", size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    if selectedAudience == .custom && selectedListId == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "007AFF"))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    selectedAudience == .custom && selectedListId == nil ?
                                    Color(hex: "007AFF").opacity(0.4) :
                                    Color.clear,
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
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
    
    private func navigate(to destination: FlowDestination, forward: Bool = true) {
        navigatingForward = forward
        flowDestination = destination
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
struct CustomAudienceList: Identifiable, Codable, Equatable {
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

// MARK: - Tarjeta de Audiencia en Grid
struct AudienceGridCard: View {
    @Environment(\.colorScheme) var colorScheme
    let audience: ContentAudience
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    private var iconColor: Color {
        if audience == .bestFriends {
            return Color(hex: "34C759")
        }
        return colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: audience.icon)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 60, height: 60)
                
                // ✅ Texto
                VStack(spacing: 4) {
                    Text(audience.title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(audience.description)
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                isSelected ?
                                Color(hex: "007AFF").opacity(0.4) :
                                Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: isSelected ? Color(hex: "007AFF").opacity(0.1) : Color.clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}



// MARK: - Tarjeta de Lista Personalizada (Carousel)
struct CustomListCard: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // ✅ Icono con color personalizado
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                }
                
                // ✅ Información de la lista
                VStack(spacing: 2) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text("\(list.members.count) personas")
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
            .frame(width: 110, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isSelected ?
                                Color(hex: list.color ?? "00A896").opacity(0.6) :
                                Color.clear,
                                lineWidth: 2
                            )
                    )
            )
            .shadow(color: isSelected ? Color(hex: list.color ?? "00A896").opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .liquidGlass(in: Circle(), interactive: true)
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
                              Color(hex: "007AFF").opacity(0.2) :
                              (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: audience.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ?
                                       Color(hex: "007AFF") : (colorScheme == .dark ? .white : .black))
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
                        .foregroundColor(Color(hex: "007AFF"))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ?
                          Color(hex: "007AFF").opacity(0.1) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        Color(hex: "007AFF").opacity(0.5) :
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
    var onBack: (() -> Void)? = nil
    var embeddedInFlow: Bool = false
    
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @StateObject private var firestoreService = FirestoreService()
    
    var body: some View {
        ZStack {
            if !embeddedInFlow {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                if embeddedInFlow {
                    HStack(spacing: 12) {
                        Button(action: { onBack?() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text(NSLocalizedString("audience.actions.selectPeople", comment: "Select people navigation title"))
                                .font(.custom("Poppins-SemiBold", size: 20))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Text(NSLocalizedString("audience.description.custom", comment: "Custom audience description"))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                        }
                        .multilineTextAlignment(.center)
                        
                        Spacer()
                        
                        Color.clear
                            .frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
                
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .liquidGlass(in: Capsule(), interactive: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                
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
                            .background(Color(hex: "007AFF"))
                            .cornerRadius(12)
                    }
                    .padding()
                }
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
    @State private var showingDeleteFeedback = false
    @State private var deletedListName = ""
    var embeddedInFlow: Bool = false
    var onBack: (() -> Void)? = nil
    var onCreateList: (() -> Void)? = nil
    var onEditList: ((CustomAudienceList) -> Void)? = nil
    var onListsChanged: (() -> Void)? = nil
    
    var body: some View {
        Group {
            if embeddedInFlow {
                content
            } else {
                content
            }
        }
        .sheet(isPresented: Binding(
            get: { !embeddedInFlow && showingCreateList },
            set: { showingCreateList = $0 }
        )) {
            CreateCustomListView()
                .presentationBackground(.clear)
        }
        .sheet(item: Binding(
            get: { embeddedInFlow ? nil : selectedList },
            set: { selectedList = $0 }
        )) { list in
            EditCustomListView(list: list)
                .presentationBackground(.clear)
        }
        .alert(NSLocalizedString("audience.deleteList.title", comment: ""), isPresented: $showingDeleteAlert) {
            Button(NSLocalizedString("audience.actions.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                if let list = listToDelete {
                    deletedListName = list.name
                    viewModel.deleteList(list)
                    onListsChanged?()
                    showDeleteFeedback()
                }
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString("audience.deleteList.confirm", comment: ""),
                    listToDelete?.name ?? ""
                )
            )
        }
        .onAppear {
            viewModel.loadLists()
        }
        .onChange(of: viewModel.lists) { _ in
            onListsChanged?()
        }
        .overlay(alignment: .bottom) {
            if showingDeleteFeedback {
                Text(String(format: NSLocalizedString("audience.deleteList.success", comment: ""), deletedListName))
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color(hex: "007AFF"))
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private var content: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView(NSLocalizedString("common.loading", comment: ""))
                    .progressViewStyle(CircularProgressViewStyle())
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 0) {
                    if embeddedInFlow {
                        HStack(spacing: 12) {
                            Button(action: { onBack?() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            VStack(spacing: 2) {
                                Text(NSLocalizedString("audience.customLists.title", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("audience.customLists", comment: ""))
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            }
                            .multilineTextAlignment(.center)
                            
                            Spacer()
                            
                            Button(action: {
                                if embeddedInFlow {
                                    onCreateList?()
                                } else {
                                    showingCreateList = true
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    } else {
                        HStack(spacing: 12) {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            VStack(spacing: 2) {
                                Text(NSLocalizedString("audience.customLists.title", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("audience.customLists", comment: ""))
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            }
                            .multilineTextAlignment(.center)

                            Spacer()

                            Button(action: { showingCreateList = true }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                    }
                    
                    VStack {
                        if viewModel.lists.isEmpty {
                            emptyStateView
                        } else {
                            listContent
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 56))
                .foregroundColor(.gray)
            
            VStack(spacing: 6) {
                Text(NSLocalizedString("audience.noCustomLists.title", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 20))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("audience.noCustomLists.description", comment: ""))
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            
            Button(action: {
                if embeddedInFlow {
                    onCreateList?()
                } else {
                    showingCreateList = true
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .liquidGlass(in: Circle(), interactive: true)
                    
                    Text(NSLocalizedString("audience.createFirstList", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(.primary)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }
    
    private var listContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.lists) { list in
                    ManageableCustomListCard(
                        list: list,
                        onEdit: {
                            if embeddedInFlow {
                                onEditList?(list)
                            } else {
                                selectedList = list
                            }
                        },
                        onDelete: {
                            listToDelete = list
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding(16)
        }
    }
    
    private func showDeleteFeedback() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            showingDeleteFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showingDeleteFeedback = false
            }
        }
    }
}

// MARK: - Tarjeta de Lista Administrable (Grid)
struct ManageableCustomListCard: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onEdit) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                }
                
                VStack(spacing: 4) {
                    Text(list.name)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: ""), list.members.count))
                            .font(.custom("Poppins-Regular", size: 12))
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash.fill")
            }
        }
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
    var embeddedInFlow: Bool = false
    var onBack: (() -> Void)? = nil
    var onCompleted: (() -> Void)? = nil
    
    @State private var listName = ""
    @State private var listDescription = ""
    @State private var selectedColor = CustomAudienceList.predefinedColors.first!
    @State private var selectedIcon = CustomAudienceList.predefinedIcons.first!
    @State private var selectedMembers: Set<String> = []
    @State private var showingMemberPicker = false
    
    var body: some View {
        content
        .sheet(isPresented: Binding(
            get: { !embeddedInFlow && showingMemberPicker },
            set: { showingMemberPicker = $0 }
        )) {
            MemberPickerView(selectedMembers: $selectedMembers)
                .presentationBackground(.clear)
        }
    }
    
    private var content: some View {
        if embeddedInFlow && showingMemberPicker {
            return AnyView(
                MemberPickerView(
                    selectedMembers: $selectedMembers,
                    embeddedInFlow: true,
                    onBack: {
                        showingMemberPicker = false
                    },
                    onConfirm: {
                        showingMemberPicker = false
                    }
                )
            )
        }
        
        return AnyView(
        ZStack {
            if !embeddedInFlow {
                Group {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    
                    if colorScheme == .dark {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(hex: selectedColor).opacity(0.15),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(hex: selectedColor).opacity(0.1),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    }
                }
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    if embeddedInFlow {
                        HStack(spacing: 12) {
                            Button(action: { onBack?() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            VStack(spacing: 2) {
                                Text(NSLocalizedString("audience.create.action", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("audience.customLists", comment: ""))
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            }
                            .multilineTextAlignment(.center)
                            
                            Spacer()
                            
                            Color.clear
                                .frame(width: 40, height: 40)
                        }
                        .padding(.top, 20)
                    } else {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            .frame(width: 40, height: 5)
                            .padding(.top, 12)
                    }
                    
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: selectedColor).opacity(0.3))
                                .frame(width: 100, height: 100)
                                .blur(radius: 20)
                            
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 86, height: 86)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                
                                Circle()
                                    .fill(Color(hex: selectedColor).opacity(0.1))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(Color(hex: selectedColor))
                                    .shadow(color: Color(hex: selectedColor).opacity(0.3), radius: 5, x: 0, y: 3)
                            }
                        }
                        
                        VStack(spacing: 6) {
                            Text(listName.isEmpty ? NSLocalizedString("audience.list.placeholder", comment: "") : listName)
                                .font(.custom("Poppins-Bold", size: 24))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 12))
                                Text(String(format: NSLocalizedString("audience.members.count.short", comment: ""), selectedMembers.count))
                                    .font(.custom("Poppins-Medium", size: 14))
                            }
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label {
                                Text("audience.list.name")
                                    .font(.custom("Poppins-SemiBold", size: 14))
                            } icon: {
                                Image(systemName: "pencil.circle.fill")
                            }
                            .foregroundColor(.primary)
                            .padding(.leading, 4)
                            
                            TextField(NSLocalizedString("audience.list.name.example", comment: ""), text: $listName)
                                .font(.custom("Poppins-Medium", size: 17))
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label {
                                Text(NSLocalizedString("audience.list.description", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 14))
                            } icon: {
                                Image(systemName: "text.alignleft")
                            }
                            .foregroundColor(.primary)
                            .padding(.leading, 4)
                            
                            TextField(NSLocalizedString("audience.list.description.placeholder", comment: ""), text: $listDescription)
                                .font(.custom("Poppins-Medium", size: 17))
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Label {
                                Text(NSLocalizedString("audience.personalization", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 14))
                            } icon: {
                                Image(systemName: "paintpalette.fill")
                            }
                            .foregroundColor(.primary)
                            .padding(.leading, 4)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(CustomAudienceList.predefinedColors, id: \.self) { color in
                                        Circle()
                                            .fill(Color(hex: color))
                                            .frame(width: 42, height: 42)
                                            .overlay(
                                                Circle()
                                                    .stroke(colorScheme == .dark ? .white : .black, lineWidth: selectedColor == color ? 3 : 0)
                                                    .padding(2)
                                            )
                                            .scaleEffect(selectedColor == color ? 1.15 : 1.0)
                                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedColor)
                                            .onTapGesture {
                                                selectedColor = color
                                                hapticFeedback()
                                            }
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(CustomAudienceList.predefinedIcons, id: \.self) { icon in
                                        ZStack {
                                            Circle()
                                                .fill(selectedIcon == icon ?
                                                      Color(hex: selectedColor).opacity(0.15) :
                                                      (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)))
                                                .frame(width: 52, height: 52)
                                            
                                            Image(systemName: icon)
                                                .foregroundColor(selectedIcon == icon ?
                                                                 Color(hex: selectedColor) : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                                                .font(.system(size: 22, weight: .semibold))
                                        }
                                        .background(
                                            Circle()
                                                .stroke(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.3) : Color.clear, lineWidth: 2)
                                        )
                                        .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedIcon)
                                        .onTapGesture {
                                            selectedIcon = icon
                                            hapticFeedback()
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Label {
                                    Text("audience.members")
                                        .font(.custom("Poppins-SemiBold", size: 14))
                                } icon: {
                                    Image(systemName: "person.circle.fill")
                                }
                                .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: { showingMemberPicker = true }) {
                                    HStack(spacing: 4) {
                                        Text(NSLocalizedString("audience.view.all", comment: ""))
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.primary)
                                            .frame(width: 20, height: 20)
                                            .liquidGlass(in: Circle(), interactive: true)
                                    }
                                    .font(.custom("Poppins-Medium", size: 13))
                                    .foregroundColor(.primary)
                                }
                            }
                            .padding(.leading, 4)
                            
                            SuggestedMembersCarousel(selectedMembers: $selectedMembers)
                        }
                        
                        Button(action: {
                            viewModel.createList(
                                name: listName,
                                description: listDescription,
                                members: Array(selectedMembers),
                                color: selectedColor,
                                icon: selectedIcon
                            ) {
                                if embeddedInFlow {
                                    onCompleted?()
                                } else {
                                    dismiss()
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                    Text(NSLocalizedString("audience.create.action", comment: ""))
                                        .font(.custom("Poppins-Bold", size: 16))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                ZStack {
                                    if listName.isEmpty {
                                        Color.gray.opacity(0.3)
                                    } else {
                                        LinearGradient(
                                            colors: [Color(hex: selectedColor), Color(hex: selectedColor).opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                            )
                            .foregroundColor(listName.isEmpty ? .gray : .white)
                            .cornerRadius(24)
                            .shadow(color: (listName.isEmpty ? Color.clear : Color(hex: selectedColor).opacity(0.3)), radius: 15, x: 0, y: 8)
                        }
                        .disabled(listName.isEmpty || viewModel.isLoading)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Carousel de Miembros Sugeridos
struct SuggestedMembersCarousel: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedMembers: Set<String>
    @State private var suggestedUsers: [AppUser] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if isLoading {
                    ForEach(0..<5) { _ in
                        Circle()
                            .fill(colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.06) : Color(hex: "0B1215").opacity(0.05))
                            .frame(width: 60, height: 60)
                    }
                } else {
                    ForEach(suggestedUsers) { user in
                        SuggestedUserCircle(user: user, isSelected: selectedMembers.contains(user.id)) {
                            if selectedMembers.contains(user.id) {
                                selectedMembers.remove(user.id)
                            } else {
                                selectedMembers.insert(user.id)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            loadSuggestions()
        }
    }
    
    private func loadSuggestions() {
        // Cargamos sugerencias basadas en conexiones mutuas (amigos)
        guard let userId = Auth.auth().currentUser?.uid else { return }
        FirestoreService().fetchMutualConnections(userId: userId) { result in
            if case .success(let users) = result {
                DispatchQueue.main.async {
                    self.suggestedUsers = Array(users.prefix(10))
                    self.isLoading = false
                }
            }
        }
    }
}

struct SuggestedUserCircle: View {
    let user: AppUser
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Button(action: onToggle) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let urlStr = user.profileImagePath, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                        } else {
                            ZStack {
                                Color.gray.opacity(0.2)
                                Text(user.username.prefix(1).uppercased())
                                    .font(.custom("Poppins-Bold", size: 20))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color(hex: "00A896") : Color.clear, lineWidth: 2)
                    )
                    
                    if isSelected {
                        ZStack {
                            Circle().fill(Color(hex: "00A896"))
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 18, height: 18)
                        .offset(x: 2, y: 2)
                    } else {
                        ZStack {
                            Circle().fill(Color.white)
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .frame(width: 18, height: 18)
                        .offset(x: 2, y: 2)
                        .shadow(radius: 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(user.username)
                .font(.custom("Poppins-Medium", size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(width: 64)
        }
    }
}


// MARK: - Editar Lista (MEJORADA)
struct EditCustomListView: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = EditListViewModel()
    var embeddedInFlow: Bool = false
    var onBack: (() -> Void)? = nil
    var onCompleted: (() -> Void)? = nil
    
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
    @State private var visibleMembersLimit = 12
    private let membersPageSize = 12
    
    init(
        list: CustomAudienceList,
        embeddedInFlow: Bool = false,
        onBack: (() -> Void)? = nil,
        onCompleted: (() -> Void)? = nil
    ) {
        self.list = list
        self.embeddedInFlow = embeddedInFlow
        self.onBack = onBack
        self.onCompleted = onCompleted
        _listName = State(initialValue: list.name)
        _listDescription = State(initialValue: list.description ?? "")
        _selectedColor = State(initialValue: list.color ?? CustomAudienceList.predefinedColors.first!)
        _selectedIcon = State(initialValue: list.icon ?? CustomAudienceList.predefinedIcons.first!)
        _selectedMembers = State(initialValue: Set(list.members))
    }
    
    var body: some View {
        content
        .sheet(isPresented: Binding(
            get: { !embeddedInFlow && showingMemberPicker },
            set: { showingMemberPicker = $0 }
        )) {
            MemberPickerView(selectedMembers: $selectedMembers)
                .presentationBackground(.clear)
        }
        .onAppear {
            loadCurrentMembers()
        }
        .onChange(of: showingMemberPicker) { isPresented in
            if !isPresented {
                loadCurrentMembers()
            }
        }
        .onChange(of: searchText) { _ in
            filterMembers()
        }
    }
    
    private var content: some View {
        if embeddedInFlow && showingMemberPicker {
            return AnyView(
                MemberPickerView(
                    selectedMembers: $selectedMembers,
                    embeddedInFlow: true,
                    onBack: {
                        showingMemberPicker = false
                    },
                    onConfirm: {
                        showingMemberPicker = false
                    }
                )
            )
        }
        
        return AnyView(
        ZStack {
            if !embeddedInFlow {
                Group {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    
                    if colorScheme == .dark {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(hex: selectedColor).opacity(0.15),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(hex: selectedColor).opacity(0.1),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    }
                }
            }
            
            ScrollView {
                VStack(spacing: 32) {
                    if embeddedInFlow {
                        HStack(spacing: 12) {
                            Button(action: { onBack?() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .liquidGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            VStack(spacing: 2) {
                                Text(NSLocalizedString("common.edit", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text(list.name)
                                    .font(.custom("Poppins-Regular", size: 13))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            }
                            .multilineTextAlignment(.center)
                            
                            Spacer()
                            
                            Color.clear
                                .frame(width: 40, height: 40)
                        }
                        .padding(.top, 20)
                    } else {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            .frame(width: 40, height: 5)
                            .padding(.top, 12)
                    }
                    
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: selectedColor).opacity(0.3))
                                .frame(width: 90, height: 90)
                                .blur(radius: 15)
                            
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 76, height: 76)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(Color(hex: selectedColor))
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text(listName.isEmpty ? NSLocalizedString("audience.list.placeholder", comment: "") : listName)
                                .font(.custom("Poppins-Bold", size: 22))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Text(String(format: NSLocalizedString("audience.members.count.short", comment: ""), selectedMembers.count))
                                .font(.custom("Poppins-Medium", size: 14))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    
                    VStack(spacing: 28) {
                        basicInfoSection
                        customizationSection
                        membersManagementSection
                        
                        Button(action: {
                            viewModel.updateList(
                                listId: list.id!,
                                name: listName,
                                description: listDescription,
                                members: Array(selectedMembers),
                                color: selectedColor,
                                icon: selectedIcon
                            ) {
                                if embeddedInFlow {
                                    onCompleted?()
                                } else {
                                    dismiss()
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                if viewModel.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                    Text(NSLocalizedString("common.save", comment: ""))
                                        .font(.custom("Poppins-Bold", size: 16))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: selectedColor), Color(hex: selectedColor).opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(24)
                            .shadow(color: Color(hex: selectedColor).opacity(0.3), radius: 15, x: 0, y: 8)
                        }
                        .disabled(listName.isEmpty || viewModel.isLoading)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private var basicInfoSection: some View {
        VStack(spacing: 20) {
            // Nombre de la lista
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("audience.list.name")
                        .font(.custom("Poppins-SemiBold", size: 14))
                } icon: {
                    Image(systemName: "pencil.circle.fill")
                }
                .foregroundColor(.primary)
                .padding(.leading, 4)
                
                TextField(NSLocalizedString("audience.list.name.example", comment: ""), text: $listName)
                    .font(.custom("Poppins-Medium", size: 17))
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            
            // Descripción
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(NSLocalizedString("audience.list.description", comment: ""))
                        .font(.custom("Poppins-SemiBold", size: 14))
                } icon: {
                    Image(systemName: "text.alignleft")
                }
                .foregroundColor(.primary)
                .padding(.leading, 4)
                
                TextField(NSLocalizedString("audience.list.description.placeholder", comment: ""), text: $listDescription)
                    .font(.custom("Poppins-Medium", size: 17))
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }
    
    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label {
                Text(NSLocalizedString("audience.personalization", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 14))
            } icon: {
                Image(systemName: "paintpalette.fill")
            }
            .foregroundColor(.primary)
            .padding(.leading, 4)
            
            // Selector de color
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(CustomAudienceList.predefinedColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Circle()
                                        .stroke(colorScheme == .dark ? .white : .black, lineWidth: selectedColor == color ? 3 : 0)
                                        .padding(2)
                                )
                                .scaleEffect(selectedColor == color ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedColor)
                                .onTapGesture {
                                    selectedColor = color
                                    hapticFeedback()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
            
            // Selector de icono
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(CustomAudienceList.predefinedIcons, id: \.self) { icon in
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ?
                                          Color(hex: selectedColor).opacity(0.15) :
                                          (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)))
                                    .frame(width: 52, height: 52)
                                
                                Image(systemName: icon)
                                    .foregroundColor(selectedIcon == icon ?
                                                   Color(hex: selectedColor) : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                                    .font(.system(size: 22, weight: .semibold))
                            }
                            .background(
                                Circle()
                                    .stroke(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.3) : Color.clear, lineWidth: 2)
                            )
                            .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedIcon)
                            .onTapGesture {
                                selectedIcon = icon
                                hapticFeedback()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private var membersManagementSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header con contador y botón agregar
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("audience.members", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 14))
                        Text(String(format: NSLocalizedString("audience.members.count.long", comment: ""), selectedMembers.count))
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.gray)
                    }
                } icon: {
                    Image(systemName: "person.2.circle.fill")
                }
                .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingMemberPicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                            .liquidGlass(in: Circle(), interactive: true)
                        Text(NSLocalizedString("audience.list.add", comment: ""))
                            .foregroundColor(.primary)
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                }
            }
            .padding(.leading, 4)
            
            // Lista de miembros actuales
            if isLoadingMembers {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if currentMembers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.3))
                    Text(NSLocalizedString("audience.list.empty", comment: ""))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("audience.list.emptyAlt", comment: ""))
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(filteredMembers.prefix(visibleMembersLimit))) { member in
                        MemberRowWithRemove(
                            user: member,
                            onRemove: {
                                selectedMembers.remove(member.id)
                                loadCurrentMembers()
                            }
                        )
                    }
                }
                
                if filteredMembers.count > visibleMembersLimit {
                    Button(action: {
                        visibleMembersLimit += membersPageSize
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 24, height: 24)
                                .liquidGlass(in: Circle(), interactive: true)
                            Text(
                                String(
                                    format: NSLocalizedString("audience.list.loadMoreMembers", comment: "Load more members"),
                                    min(membersPageSize, filteredMembers.count - visibleMembersLimit)
                                )
                            )
                            .foregroundColor(.primary)
                        }
                        .font(.custom("Poppins-Medium", size: 14))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private func loadCurrentMembers() {
        guard !selectedMembers.isEmpty else {
            currentMembers = []
            filteredMembers = []
            visibleMembersLimit = membersPageSize
            return
        }
        
        isLoadingMembers = true
        FirestoreService().fetchUsers(userIds: Array(selectedMembers)) { result in
            DispatchQueue.main.async {
                self.isLoadingMembers = false
                switch result {
                case .success(let users):
                    self.currentMembers = users
                    self.filterMembers()
                    self.visibleMembersLimit = self.membersPageSize
                case .failure(let error):
                    self.currentMembers = []
                    self.filteredMembers = []
                    self.visibleMembersLimit = self.membersPageSize
                }
            }
        }
    }
    
    private func filterMembers() {
        visibleMembersLimit = membersPageSize
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
            Group {
                if let urlStr = user.profileImagePath, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.06) : Color(hex: "0B1215").opacity(0.05)
                    }
                } else {
                    ZStack {
                        colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.06) : Color(hex: "0B1215").opacity(0.05)
                        Text(user.username.prefix(1).uppercased())
                            .font(.custom("Poppins-Bold", size: 16))
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // Info del usuario
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Botón Eliminar
            Button(action: { showingRemoveAlert = true }) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red.opacity(0.7))
            }
            .alert(NSLocalizedString("audience.list.deleteMember.title", comment: ""), isPresented: $showingRemoveAlert) {
                Button(NSLocalizedString("audience.actions.cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                    onRemove()
                }
            } message: {
                Text(String(format: NSLocalizedString("audience.list.deleteMember.message", comment: ""), user.username))
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
        .cornerRadius(16)
    }
}

// MARK: - Selector de Miembros (MEJORADO)
struct MemberPickerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedMembers: Set<String>
    @Environment(\.dismiss) private var dismiss
    var embeddedInFlow: Bool = false
    var onBack: (() -> Void)? = nil
    var onConfirm: (() -> Void)? = nil
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @StateObject private var firestoreService = FirestoreService()
    @State private var selectedUsersData: [AppUser] = []
    @State private var selectedCarouselVisibleLimit = 12
    private let selectedCarouselPageSize = 10
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.62)
    }
    
    private var subtleStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.12)
    }
    
    private var visibleSelectedUsers: [AppUser] {
        Array(selectedUsersData.prefix(selectedCarouselVisibleLimit))
    }
    
    private var hiddenSelectedCount: Int {
        max(0, selectedUsersData.count - selectedCarouselVisibleLimit)
    }
    
    var body: some View {
        Group {
            if embeddedInFlow {
                content
            } else {
                NavigationView {
                    content
                        .navigationTitle(NSLocalizedString("audience.picker.title", comment: ""))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(NSLocalizedString("audience.actions.cancel", comment: "")) {
                                    closePicker()
                                }
                                .foregroundColor(secondaryTextColor)
                            }
                            
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(NSLocalizedString("common.confirm", comment: "")) {
                                    confirmPicker()
                                }
                                .foregroundColor(Color(hex: "00A896"))
                                .fontWeight(.semibold)
                                .disabled(selectedMembers.isEmpty)
                            }
                        }
                }
            }
        }
        .onAppear {
            preloadSelectedUsersData()
        }
        .onChange(of: selectedMembers) { _ in
            selectedUsersData.removeAll { !selectedMembers.contains($0.id) }
            selectedCarouselVisibleLimit = 12
            if selectedMembers.isEmpty {
                selectedUsersData = []
            }
        }
    }
    
    private var content: some View {
        ZStack {
            if !embeddedInFlow {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                if embeddedInFlow {
                    HStack(spacing: 12) {
                        Button(action: { closePicker() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text(NSLocalizedString("audience.picker.title", comment: ""))
                                .font(.custom("Poppins-SemiBold", size: 20))
                                .foregroundColor(primaryTextColor)
                            Text(NSLocalizedString("audience.members", comment: ""))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(secondaryTextColor)
                        }
                        .multilineTextAlignment(.center)
                        
                        Spacer()
                        
                        Button(NSLocalizedString("common.confirm", comment: "")) {
                            confirmPicker()
                        }
                        .font(.custom("Poppins-SemiBold", size: 14))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlass(in: Capsule(), interactive: true)
                        .opacity(selectedMembers.isEmpty ? 0.45 : 1.0)
                        .disabled(selectedMembers.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
                
                if !selectedUsersData.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(visibleSelectedUsers) { user in
                                VStack {
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Circle().fill(Color.gray.opacity(0.3))
                                        }
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle().stroke(
                                                colorScheme == .dark ? Color.white : Color.black.opacity(0.18),
                                                lineWidth: 2
                                            )
                                        )
                                        
                                        Button(action: {
                                            toggleSelection(user: user)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.5)))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                    
                                    Text(user.username)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 60)
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            if hiddenSelectedCount > 0 {
                                Button(action: {
                                    selectedCarouselVisibleLimit += selectedCarouselPageSize
                                }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: "00A896").opacity(0.18))
                                                .frame(width: 48, height: 48)
                                            Text("+\(hiddenSelectedCount)")
                                                .font(.custom("Poppins-SemiBold", size: 13))
                                                .foregroundColor(Color(hex: "00A896"))
                                        }
                                        Text(NSLocalizedString("audience.more", comment: "More"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .frame(width: 60)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                searchBar
                
                if !hasSearched {
                    initialStateView
                } else if isSearching {
                    loadingView
                } else if searchResults.isEmpty {
                    emptyResultsView
                } else {
                    resultsListView
                }
                
                if !selectedMembers.isEmpty {
                    selectedCounterFooter
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(secondaryTextColor)
            
            TextField(NSLocalizedString("audience.picker.searchPlaceholder", comment: ""), text: $searchText)
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
                        .foregroundColor(secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(in: Capsule(), interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var initialStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(secondaryTextColor)
            
            Text(NSLocalizedString("audience.picker.initialTitle", comment: ""))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(NSLocalizedString("audience.picker.initialDescription", comment: ""))
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(secondaryTextColor)
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
            Text(NSLocalizedString("common.searching", comment: ""))
                .font(.custom("Poppins-Regular", size: 16))
                .foregroundColor(secondaryTextColor)
            Spacer()
        }
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundColor(secondaryTextColor)
            
            Text(NSLocalizedString("common.noResults", comment: ""))
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(String(format: NSLocalizedString("audience.picker.noResultsDescription", comment: ""), searchText))
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(secondaryTextColor)
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
                        toggleSelection(user: user)
                    }
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listStyle(PlainListStyle())
        .listRowSeparator(.hidden)
    }
    
    private var selectedCounterFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("audience.picker.selectedCount", comment: ""), selectedMembers.count))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(NSLocalizedString("audience.picker.selectedDescription", comment: ""))
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(NSLocalizedString("common.clear", comment: "")) {
                    selectedMembers.removeAll()
                }
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule(), interactive: true)
                
                Button(NSLocalizedString("common.confirm", comment: "")) {
                    confirmPicker()
                }
                .font(.custom("Poppins-SemiBold", size: 14))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .liquidGlass(in: Capsule(), interactive: true)
                .opacity(selectedMembers.isEmpty ? 0.45 : 1.0)
                .disabled(selectedMembers.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func preloadSelectedUsersData() {
        guard !selectedMembers.isEmpty else {
            selectedUsersData = []
            return
        }
        
        firestoreService.fetchUsers(userIds: Array(selectedMembers)) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let users):
                    self.selectedUsersData = users
                case .failure:
                    self.selectedUsersData = []
                }
            }
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

    
    private func toggleSelection(user: AppUser) {
        if selectedMembers.contains(user.id) {
            selectedMembers.remove(user.id)
            selectedUsersData.removeAll(where: { $0.id == user.id })
        } else {
            selectedMembers.insert(user.id)
            if !selectedUsersData.contains(where: { $0.id == user.id }) {
                selectedUsersData.append(user)
            }
        }
    }
    
    private func closePicker() {
        if embeddedInFlow {
            onBack?()
        } else {
            dismiss()
        }
    }
    
    private func confirmPicker() {
        if embeddedInFlow {
            onConfirm?()
        } else {
            dismiss()
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
                AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 20))
                        )
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color(hex: "007AFF").opacity(0.35) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                            lineWidth: 1
                        )
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                
                Spacer()
                
                ZStack {
                    Image(systemName: isSelected ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? Color(hex: "007AFF") : .primary)
                        .frame(width: 28, height: 28)
                        .liquidGlass(in: Circle(), interactive: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color(hex: "007AFF").opacity(0.22) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                                lineWidth: 1
                            )
                    )
            )
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
            HStack(spacing: 16) {
                AsyncImage(url: URL(string: user.profileImagePath ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 20))
                        )
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color(hex: "007AFF").opacity(0.35) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                            lineWidth: 1
                        )
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                
                if user.isVerified {
                    VerifiedBadge(size: 14)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? Color(hex: "007AFF") : .primary)
                    .frame(width: 28, height: 28)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isSelected ? Color(hex: "007AFF").opacity(0.22) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModels
class CreateListViewModel: ObservableObject {
    @Published var isLoading = false
    private let db = Firestore.firestore()
    
    func createList(name: String, description: String, members: [String], color: String, icon: String, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
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
                .addDocument(from: newList) { [weak self] error in
                    self?.isLoading = false
                    if let error = error {
                    } else {
                        completion()
                    }
                }
        } catch {
            isLoading = false
        }
    }
}

class EditListViewModel: ObservableObject {
    @Published var isLoading = false
    private let db = Firestore.firestore()
    
    func updateList(listId: String, name: String, description: String, members: [String], color: String, icon: String, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
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
            .updateData(updateData) { [weak self] error in
                self?.isLoading = false
                if let error = error {
                } else {
                    completion()
                }
            }
    }
}
