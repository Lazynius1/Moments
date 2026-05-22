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
    private enum FlowDestination: Equatable {
        case main
        case customPeople
        case manageLists
        case createList(returnToManageLists: Bool)
        case editList(CustomAudienceList)
    }

    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAudience: ChainContinuationSetting
    @Binding var selectedListId: String?
    @Binding var selectedListName: String?
    @Binding var customSelectedUsers: [String]
    var embeddedInFlow: Bool = false
    var onBack: (() -> Void)? = nil
    var onComplete: (() -> Void)? = nil
    
    @State private var flowDestination: FlowDestination = .main
    @State private var navigatingForward = true
    @State private var customLists: [CustomAudienceList] = []
    @State private var isLoadingLists = false
    @State private var selectedUsersForCustom: [AppUser] = []
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Group {
            if embeddedInFlow {
                selectorBody
            } else {
                NavigationView {
                    selectorBody
                }
            }
        }
    }
    
    private var selectorBody: some View {
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
                                Text(NSLocalizedString("storyChains.continuationAudience.navigationTitle", comment: ""))
                                    .font(.custom("Poppins-SemiBold", size: 20))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("storyChains.continuationAudience.subtitle", comment: ""))
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

                    if !embeddedInFlow {
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
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                    }
                    
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
                    selectedAudience = .custom
                    selectedListId = nil
                    selectedListName = nil
                    finishSelection()
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
                        finishSelection()
                    }
                )
                
                ChainAudienceGridCard(
                    setting: .connections,
                    isSelected: selectedAudience == .connections,
                    onTap: {
                        selectedAudience = .connections
                        resetSelection()
                        finishSelection()
                    }
                )
                
                ChainAudienceGridCard(
                    setting: .bestFriends,
                    isSelected: selectedAudience == .bestFriends,
                    onTap: {
                        selectedAudience = .bestFriends
                        resetSelection()
                        finishSelection()
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
                Button(action: { navigate(to: .manageLists) }) {
                    Text(NSLocalizedString("audience.manage", comment: ""))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(Color(hex: "007AFF"))
                }
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
                emptyCustomListsViewModern
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button(action: { navigate(to: .createList(returnToManageLists: false)) }) {
                            VStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(hex: "007AFF"))
                                    .frame(width: 48, height: 48)
                                    .liquidGlass(in: Circle(), interactive: true)
                                Text(NSLocalizedString("audience.create", comment: ""))
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
                            ChainCustomListCard(
                                list: list,
                                isSelected: selectedAudience == .customList && selectedListId == list.id,
                                onTap: {
                                    selectedAudience = .customList
                                    selectedListId = list.id
                                    selectedListName = list.name
                                    customSelectedUsers = []
                                    finishSelection()
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
            
            Button(action: { navigate(to: .customPeople) }) {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 36, height: 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("audience.type.custom", comment: ""))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        if selectedAudience == .custom && !customSelectedUsers.isEmpty {
                            Text(String(format: NSLocalizedString("audience.people.count", comment: ""), customSelectedUsers.count))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        } else {
                            Text(NSLocalizedString("audience.description.custom", comment: ""))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
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

    private var emptyCustomListsViewModern: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.primary)
            
            VStack(spacing: 4) {
                Text(NSLocalizedString("audience.noCustomLists.title", comment: ""))
                    .font(.custom("Poppins-SemiBold", size: 16))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("audience.noCustomLists.description", comment: ""))
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
                    Text(NSLocalizedString("audience.createFirstList", comment: ""))
                        .font(.custom("Poppins-Medium", size: 14))
                        .foregroundColor(.primary)
                }
            }
            .padding(.top, 6)
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
                    if error != nil {
                        return
                    }
                    
                    self.customLists = snapshot?.documents.compactMap { doc in
                        try? doc.data(as: CustomAudienceList.self)
                    } ?? []
                }
            }
    }

    private func loadSelectedUsersInfo() {
        guard !customSelectedUsers.isEmpty else {
            selectedUsersForCustom = []
            return
        }
        
        FirestoreService().fetchUsers(userIds: customSelectedUsers) { result in
            if case .success(let users) = result {
                DispatchQueue.main.async {
                    selectedUsersForCustom = users
                }
            }
        }
    }

    private func navigate(to destination: FlowDestination, forward: Bool = true) {
        navigatingForward = forward
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            flowDestination = destination
        }
    }

    private func finishSelection() {
        if embeddedInFlow {
            onComplete?()
        } else {
            dismiss()
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

    private var iconColor: Color {
        if setting == .bestFriends {
            return Color(hex: "34C759")
        }
        return colorScheme == .dark ? .white : .black
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: setting.icon)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 60, height: 60)

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

// MARK: - Tarjeta de Lista Personalizada para Cadenas
struct ChainCustomListCard: View {
    @Environment(\.colorScheme) var colorScheme
    let list: CustomAudienceList
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: list.color ?? "00A896").opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: list.icon ?? "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(hex: list.color ?? "00A896"))
                }
                
                VStack(spacing: 4) {
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

#Preview {
    ChainContinuationSelectorView(
        selectedAudience: .constant(.everyone),
        selectedListId: .constant(nil),
        selectedListName: .constant(nil),
        customSelectedUsers: .constant([])
    )
}
