import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Custom User Selector View
struct CustomUserSelectorView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedUsers: [String]
    
    @State private var selectedUsersForCustom: [AppUser] = []
    
    var body: some View {
        NavigationView {
            CustomAudienceSelector(selectedUsers: $selectedUsersForCustom) {
                selectedUsers = selectedUsersForCustom.map { $0.id }
                dismiss()
            }
            .navigationTitle(NSLocalizedString("audience.actions.selectPeople", comment: "Select people navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("audience.actions.cancel", comment: "Cancel action")) {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            // Cargar usuarios seleccionados actuales
            loadSelectedUsersInfo()
        }
    }
    
    private func loadSelectedUsersInfo() {
        guard !selectedUsers.isEmpty else { return }
        FirestoreService().fetchUsers(userIds: selectedUsers) { result in
            if case .success(let users) = result {
                DispatchQueue.main.async {
                    selectedUsersForCustom = users
                }
            }
        }
    }
}

struct ChainContinuationSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAudience: ChainContinuationSetting
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    
    @State private var showingCustomUserSelector = false
    @State private var showingCustomListSelector = false
    @State private var showingCustomListCreator = false
    @State private var customLists: [CustomAudienceList] = []
    @State private var isLoadingLists = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // ✅ Handle superior
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3))
                                .frame(width: 40, height: 5)
                                .padding(.top, 12)
                                .padding(.bottom, 20)
                            
                            // ✅ Título principal
                            VStack(spacing: 8) {
                                Text(NSLocalizedString("storyChains.continuationAudience", comment: ""))
                                    .font(.custom("Poppins-Bold", size: 24))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text(NSLocalizedString("storyChains.visibilityInfo", comment: ""))
                                    .font(.custom("Poppins-Regular", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                            
                            // ✅ Contenido principal
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
            .sheet(isPresented: $showingCustomUserSelector) {
                CustomUserSelectorView(selectedUsers: $customSelectedUsers)
            }
            .sheet(isPresented: $showingCustomListCreator) {
                CreateCustomListView()
                    .onDisappear { loadCustomLists() }
            }
            .onAppear {
                loadCustomLists()
            }
        }
    }
    
    // MARK: - Sections
    private var predefinedAudienceSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("audience.predefined", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ChainAudienceGridCard(
                    setting: .everyone,
                    isSelected: selectedAudience == .everyone,
                    onTap: {
                        selectedAudience = .everyone
                        resetSelection()
                        dismiss()
                    }
                )
                
                ChainAudienceGridCard(
                    setting: .connections,
                    isSelected: selectedAudience == .connections,
                    onTap: {
                        selectedAudience = .connections
                        resetSelection()
                        dismiss()
                    }
                )
                
                ChainAudienceGridCard(
                    setting: .bestFriends,
                    isSelected: selectedAudience == .bestFriends,
                    onTap: {
                        selectedAudience = .bestFriends
                        resetSelection()
                        dismiss()
                    }
                )
            }
        }
    }
    
    private var customListsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("audience.customLists", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            if isLoadingLists {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text(NSLocalizedString("audience.loadingLists", comment: ""))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                .padding()
            } else if customLists.isEmpty {
                // Vista vacía simple
                Button(action: { showingCustomListCreator = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("audience.create", comment: ""))
                    }
                    .font(.custom("Poppins-Medium", size: 14))
                    .foregroundColor(Color(hex: "00A896"))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "00A896").opacity(0.1))
                    .cornerRadius(12)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(customLists) { list in
                            ChainCustomListCard(
                                list: list,
                                isSelected: selectedAudience == .customList && selectedListId == list.id,
                                onTap: {
                                    selectedAudience = .customList
                                    selectedListId = list.id
                                    selectedListName = list.name
                                    customSelectedUsers = []
                                    dismiss()
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
    
    private var manualSelectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("audience.manualSelection", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            Button(action: { showingCustomUserSelector = true }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(selectedAudience == .custom ? Color(hex: "00A896").opacity(0.15) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(selectedAudience == .custom ? Color(hex: "00A896") : (colorScheme == .dark ? .white : .black))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("audience.type.custom", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        if selectedAudience == .custom && !customSelectedUsers.isEmpty {
                            Text(String(format: NSLocalizedString("audience.people.count", comment: ""), customSelectedUsers.count))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(Color(hex: "00A896"))
                        } else {
                            Text(NSLocalizedString("audience.description.custom", comment: ""))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .padding()
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selectedAudience == .custom ? Color(hex: "00A896").opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Helper Functions
    private func loadCustomLists() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoadingLists = true
        
        Firestore.firestore().collection("users").document(userId)
            .collection("customAudienceLists")
            .order(by: "updatedAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingLists = false
                    if let error = error {
                        return
                    }
                    
                    self.customLists = snapshot?.documents.compactMap { doc in
                        try? doc.data(as: CustomAudienceList.self)
                    } ?? []
                }
            }
    }
    
    private func resetSelection() {
        selectedListId = nil
        selectedListName = nil
        customSelectedUsers = []
    }
    
    private func convertToContentAudience() -> Binding<ContentAudience> {
        Binding<ContentAudience>(
            get: {
                switch selectedAudience {
                case .everyone: return .everyone
                case .connections: return .connections
                case .bestFriends: return .bestFriends
                case .custom: return .custom
                case .customList: return .customList
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: selectedAudience = .everyone
                case .connections: selectedAudience = .connections
                case .bestFriends: selectedAudience = .bestFriends
                case .custom: selectedAudience = .custom
                case .customList: selectedAudience = .customList
                case .onlyMe: selectedAudience = .everyone // Not applicable for continuation
                }
            }
        )
    }
}

// MARK: - Tarjeta de Audiencia en Grid para Cadenas
struct ChainAudienceGridCard: View {
    @Environment(\.colorScheme) var colorScheme
    let setting: ChainContinuationSetting
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // ✅ Icono
                ZStack {
                    Circle()
                        .fill(isSelected ?
                              Color(hex: "00A896").opacity(0.15) :
                              (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: setting.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isSelected ?
                                       Color(hex: "00A896") : (colorScheme == .dark ? .white : .black))
                }
                
                // ✅ Texto
                VStack(spacing: 4) {
                    Text(setting.title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(setting.description)
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
                                Color(hex: "00A896").opacity(0.4) :
                                Color.clear,
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: isSelected ? Color(hex: "00A896").opacity(0.1) : Color.clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Tarjeta de Lista Personalizada para Cadenas
struct ChainCustomListCard: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: list.color ?? "00A896").opacity(isSelected ? 1.0 : 0.8))
                }
                
                VStack(spacing: 4) {
                    Text(list.name)
                        .font(.custom("Poppins-Medium", size: 13))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(String(format: NSLocalizedString("audience.members.count.short", comment: ""), list.members.count))
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 100, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ?
                          Color(hex: list.color ?? "00A896").opacity(0.1) :
                          (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isSelected ?
                        Color(hex: list.color ?? "00A896").opacity(0.5) :
                        Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ChainContinuationSelectorView(
        selectedAudience: .constant(.everyone),
        selectedListId: .constant(nil),
        selectedListName: .constant(nil),
        customSelectedUsers: .constant([])
    )
}
