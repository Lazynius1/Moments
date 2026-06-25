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
                                    .momentsChromeGlass(in: Circle(), interactive: true)
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
            
            VStack(spacing: 2) {
                AudienceGridCard(
                    audience: .everyone,
                    isSelected: selectedAudience == .everyone,
                    onTap: {
                        selectedAudience = .everyone
                        resetSelection()
                        finishSelection()
                    }
                )

                AudienceGridCard(
                    audience: .mutuals,
                    isSelected: selectedAudience == .mutuals,
                    onTap: {
                        selectedAudience = .mutuals
                        resetSelection()
                        finishSelection()
                    }
                )

                AudienceGridCard(
                    audience: .bestFriends,
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
                                    .momentsChromeGlass(in: Circle(), interactive: true)
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
                            CustomListCard(
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
            
            let isCustomPeopleSelected = selectedAudience == .custom && selectedListId == nil

            Button(action: { navigate(to: .customPeople) }) {
                HStack(alignment: .center, spacing: 14) {
                    AudienceIconView(
                        audience: .custom,
                        size: AudienceIconMetrics.gridCardEmphasis,
                        colorScheme: colorScheme
                    )
                    .frame(width: 40, height: 40)
                    .opacity(isCustomPeopleSelected ? 1 : 0.42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("audience.type.custom", comment: ""))
                            .font(.custom(isCustomPeopleSelected ? "Poppins-SemiBold" : "Poppins-Medium", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .opacity(isCustomPeopleSelected ? 1 : 0.82)

                        if selectedAudience == .custom && !customSelectedUsers.isEmpty {
                            Text(String(format: NSLocalizedString("audience.people.count", comment: ""), customSelectedUsers.count))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.55))
                                .opacity(isCustomPeopleSelected ? 1 : 0.72)
                        } else {
                            Text(NSLocalizedString("audience.description.custom", comment: ""))
                                .font(.custom("Poppins-Regular", size: 13))
                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.55))
                                .opacity(isCustomPeopleSelected ? 1 : 0.72)
                        }
                    }

                    Spacer(minLength: 8)

                    if isCustomPeopleSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            )
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 26, height: 26)
                            .opacity(0.55)
                    }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyCustomListsViewModern: some View {
        VStack(spacing: 16) {
            AudienceIconView(
                audience: .customList,
                size: AudienceIconMetrics.gridCardEmphasis,
                colorScheme: colorScheme
            )
            
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
                        .momentsChromeGlass(in: Circle(), interactive: true)
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
                case .mutuals: return .mutuals
                case .bestFriends: return .bestFriends
                case .custom: return .custom
                case .customList: return .customList
                }
            },
            set: { newValue in
                switch newValue {
                case .everyone: selectedAudience = .everyone
                case .mutuals: selectedAudience = .mutuals
                case .bestFriends: selectedAudience = .bestFriends
                case .custom: selectedAudience = .custom
                case .customList: selectedAudience = .customList
                case .onlyMe: selectedAudience = .everyone // Not applicable for continuation
                }
            }
        )
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
