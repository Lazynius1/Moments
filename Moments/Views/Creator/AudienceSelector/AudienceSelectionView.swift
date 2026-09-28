import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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
    
    var body: some View {
        NavigationStack {
            ZStack {
                if case .main = flowDestination {
                    mainContent
                        .transition(flowTransition)
                } else {
                    nestedFlowContent
                        .transition(flowTransition)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: flowDestination)
            .onAppear {
                loadCustomLists()
                loadSelectedUsersInfo()
            }

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
        ScrollView {
            VStack(spacing: 16) {
                predefinedAudienceSection
                customListsSection
                manualSelectionSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .momentsSheetScrollHeader {
            AudienceSelectionHeader()
        }
    }

    private struct AudienceSelectionHeader: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(spacing: 8) {
                Text("audience.selection.title")
                    .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text("audience.selection.subtitle")
                    .font(.system(size: legacyPoppinsSize(16)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
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
                    let updatedUserIDs = selectedUsersForCustom.map(\.id)
                    let didChange = Set(updatedUserIDs) != Set(customSelectedUsers)
                    customSelectedUsers = updatedUserIDs
                    selectedAudience = .custom
                    selectedListId = nil
                    selectedListName = nil
                    if didChange {
                        InAppNotificationService.shared.showActionToast(
                            .plain("audience.saved", fallback: "Audience saved", icon: "checkmark.circle.fill")
                        )
                    }
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
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
                        showSaveFeedback()
                    }
                )

                AudienceGridCard(
                    audience: .mutuals,
                    isSelected: selectedAudience == .mutuals,
                    onTap: {
                        selectedAudience = .mutuals
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

    private func showSaveFeedback() {
        InAppNotificationService.shared.showActionToast(
            .plain("audience.saved", fallback: "Audience saved", icon: "checkmark.circle.fill")
        )
    }
    
    private var customListsSection: some View {
        VStack(spacing: 12) {
            // ✅ Header con botón de gestión
            HStack {
                Text("audience.customLists")
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
                Button(action: { navigate(to: .manageLists) }) {
                    Text("audience.manage")
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 4)
            
            if isLoadingLists {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("audience.loadingLists")
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
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
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                    .frame(width: 48, height: 48)
                                    .momentsChromeGlass(in: Circle(), interactive: true)
                                Text("audience.create")
                                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                            }
                            .frame(width: 100, height: 140)
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
            AudienceIconView(
                audience: .customList,
                size: AudienceIconMetrics.gridCardEmphasis,
                colorScheme: colorScheme
            )
            
            VStack(spacing: 4) {
                Text("audience.noCustomLists.title")
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text("audience.noCustomLists.description")
                    .font(.system(size: legacyPoppinsSize(14)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { navigate(to: .createList(returnToManageLists: false)) }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                    Text("audience.createFirstList")
                        .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                        .foregroundStyle(.primary)
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
                    .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            let isCustomPeopleSelected = selectedAudience == .custom && selectedListId == nil

            Button(action: {
                selectedAudience = .custom
                navigate(to: .customPeople)
            }) {
                HStack(alignment: .center, spacing: 14) {
                    AudienceIconView(
                        audience: .custom,
                        size: AudienceIconMetrics.gridCardEmphasis,
                        colorScheme: colorScheme
                    )
                    .frame(width: 40, height: 40)
                    .opacity(isCustomPeopleSelected ? 1 : 0.42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("audience.custom")
                            .font(.system(size: legacyPoppinsSize(16), weight: isCustomPeopleSelected ? .semibold : .medium))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .opacity(isCustomPeopleSelected ? 1 : 0.82)

                        Text(customSelectedUsers.isEmpty ?
                             NSLocalizedString("audience.description.custom", comment: "Custom audience description") :
                             String(format: NSLocalizedString("audience.people.count", comment: "People count"), customSelectedUsers.count))
                            .font(.system(size: legacyPoppinsSize(13)))
                            .foregroundStyle((colorScheme == .dark ? Color.white : Color.black).opacity(0.55))
                            .opacity(isCustomPeopleSelected ? 1 : 0.72)
                    }

                    Spacer(minLength: 8)

                    if isCustomPeopleSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            )
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
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
    private func loadCustomLists() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoadingLists = true
        FirestoreService().fetchCustomLists(for: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let lists):
                    self.customLists = lists
                case .failure:
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
    
    private func navigate(to destination: FlowDestination, forward: Bool = true) {
        navigatingForward = forward
        flowDestination = destination
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
    @State private var showingEmojiPicker = false
    @State private var selectedImage: UIImage?
    @State private var showingImageCrop = false
    
    var body: some View {
        content
        .sheet(isPresented: Binding(
            get: { !embeddedInFlow && showingMemberPicker },
            set: { showingMemberPicker = $0 }
        )) {
            MemberPickerView(selectedMembers: $selectedMembers)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(isPresented: $showingEmojiPicker) { emoji in
                selectedIcon = emoji
                selectedImage = nil
                hapticFeedback()
            }
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $showingImageCrop) {
            ProfileLibraryCropEntryView { croppedImage in
                selectedImage = croppedImage
                hapticFeedback()
            }
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
                    HStack(spacing: 12) {
                        Button(action: {
                            if embeddedInFlow {
                                onBack?()
                            } else {
                                dismiss()
                            }
                        }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .momentsChromeGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            VStack(spacing: 2) {
                                Text(NSLocalizedString("audience.create.action", comment: ""))
                                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("audience.customLists", comment: ""))
                                    .font(.system(size: legacyPoppinsSize(13)))
                                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            }
                            .multilineTextAlignment(.center)
                            
                            Spacer()
                            
                            Color.clear
                                .frame(width: 40, height: 40)
                        }
                        .padding(.top, 20)
                    
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
                                
                                CustomAudienceListIcon(
                                    icon: selectedIcon,
                                    size: 36,
                                    weight: .bold,
                                    localImage: selectedImage,
                                    imageSize: 60
                                )
                                    .foregroundStyle(Color(hex: selectedColor))
                                    .shadow(color: Color(hex: selectedColor).opacity(0.3), radius: 5, x: 0, y: 3)

                                if viewModel.isLoading && selectedImage != nil {
                                    Circle()
                                        .fill(.black.opacity(0.38))
                                        .frame(width: 86, height: 86)
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                        }
                        
                        VStack(spacing: 6) {
                            Text(listName.isEmpty ? NSLocalizedString("audience.list.placeholder", comment: "") : listName)
                                .font(.system(size: legacyPoppinsSize(24), weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                                .multilineTextAlignment(.center)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 12))
                                Text(String(format: NSLocalizedString("audience.members.count.short", comment: ""), selectedMembers.count))
                                    .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                            }
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label {
                                Text("audience.list.name")
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            } icon: {
                                Image(systemName: "pencil.circle.fill")
                            }
                            .foregroundStyle(.primary)
                            .padding(.leading, 4)
                            
                            TextField(NSLocalizedString("audience.list.name.example", comment: ""), text: $listName)
                                .font(.system(size: legacyPoppinsSize(17), weight: .medium))
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
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            } icon: {
                                Image(systemName: "text.alignleft")
                            }
                            .foregroundStyle(.primary)
                            .padding(.leading, 4)
                            
                            TextField(NSLocalizedString("audience.list.description.placeholder", comment: ""), text: $listDescription)
                                .font(.system(size: legacyPoppinsSize(17), weight: .medium))
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
                                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                            } icon: {
                                Image(systemName: "paintpalette.fill")
                            }
                            .foregroundStyle(.primary)
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
                                            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: selectedColor), value: selectedColor)
                                            .onTapGesture {
                                                selectedColor = color
                                                hapticFeedback()
                                            }
                                    }

                                    ColorPicker(
                                        NSLocalizedString("common.color", comment: ""),
                                        selection: Binding(
                                            get: { Color(hex: selectedColor) },
                                            set: { selectedColor = $0.toHex().uppercased() }
                                        ),
                                        supportsOpacity: false
                                    )
                                    .labelsHidden()
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                colorScheme == .dark ? .white : .black,
                                                lineWidth: CustomAudienceList.predefinedColors.contains(selectedColor) ? 0 : 3
                                            )
                                            .padding(2)
                                            .allowsHitTesting(false)
                                    }
                                    .scaleEffect(CustomAudienceList.predefinedColors.contains(selectedColor) ? 1 : 1.15)
                                    .accessibilityLabel(Text(NSLocalizedString("common.color", comment: "")))
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
                                                .foregroundStyle(selectedIcon == icon ?
                                                                 Color(hex: selectedColor) : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                                                .font(.system(size: 22, weight: .semibold))
                                        }
                                        .background(
                                            Circle()
                                                .stroke(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.3) : Color.clear, lineWidth: 2)
                                        )
                                        .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                                        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: selectedIcon), value: selectedIcon)
                                        .onTapGesture {
                                            selectedIcon = icon
                                            selectedImage = nil
                                            hapticFeedback()
                                        }
                                    }

                                    Button {
                                        showingEmojiPicker = true
                                    } label: {
                                        let isCustomEmoji = !CustomAudienceList.predefinedIcons.contains(selectedIcon)
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    isCustomEmoji
                                                        ? Color(hex: selectedColor).opacity(0.15)
                                                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                                                )
                                                .frame(width: 52, height: 52)

                                            CustomAudienceListIcon(
                                                icon: isCustomEmoji ? selectedIcon : "face.smiling",
                                                size: 22
                                            )
                                            .foregroundStyle(
                                                isCustomEmoji
                                                    ? Color(hex: selectedColor)
                                                    : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                            )
                                        }
                                        .background {
                                            Circle()
                                                .stroke(
                                                    isCustomEmoji ? Color(hex: selectedColor).opacity(0.3) : .clear,
                                                    lineWidth: 2
                                                )
                                        }
                                        .scaleEffect(isCustomEmoji ? 1.1 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(NSLocalizedString("storyEditor.emojiPicker.title", comment: "")))

                                    Button {
                                        showingImageCrop = true
                                    } label: {
                                        let isPhotoSelected = selectedImage != nil
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    isPhotoSelected
                                                        ? Color(hex: selectedColor).opacity(0.15)
                                                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                                                )
                                                .frame(width: 52, height: 52)

                                            CustomAudienceListIcon(
                                                icon: "photo.fill",
                                                size: 21,
                                                localImage: selectedImage,
                                                imageSize: 52
                                            )
                                            .foregroundStyle(
                                                isPhotoSelected
                                                    ? Color(hex: selectedColor)
                                                    : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                            )
                                        }
                                        .background {
                                            Circle()
                                                .stroke(
                                                    isPhotoSelected ? Color(hex: selectedColor).opacity(0.3) : .clear,
                                                    lineWidth: 2
                                                )
                                        }
                                        .scaleEffect(isPhotoSelected ? 1.1 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(NSLocalizedString("common.photo", comment: "")))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Label {
                                    Text("audience.members")
                                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                                } icon: {
                                    Image(systemName: "person.circle.fill")
                                }
                                .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Button(action: { showingMemberPicker = true }) {
                                    HStack(spacing: 4) {
                                        Text(NSLocalizedString("audience.view.all", comment: ""))
                                            .foregroundStyle(.primary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.primary)
                                            .frame(width: 20, height: 20)
                                            .momentsChromeGlass(in: Circle(), interactive: true)
                                    }
                                    .font(.system(size: legacyPoppinsSize(13), weight: .medium))
                                    .foregroundStyle(.primary)
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
                                icon: selectedIcon,
                                image: selectedImage
                            ) { result in
                                switch result {
                                case .success:
                                    InAppNotificationService.shared.showActionToast(
                                        .plain("audience.saved", fallback: "Audience saved", icon: "checkmark.circle.fill")
                                    )
                                    if embeddedInFlow {
                                        onCompleted?()
                                    } else {
                                        dismiss()
                                    }
                                case .failure(let error):
                                    InAppNotificationService.shared.showActionToast(
                                        InAppActionToast(systemImage: "exclamationmark.triangle.fill", prefix: error.localizedDescription)
                                    )
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
                                        .font(.system(size: legacyPoppinsSize(16), weight: .bold))
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
                            .foregroundStyle(listName.isEmpty ? .gray : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        FirestoreService().fetchMutuals(userId: userId) { result in
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
                                    .font(.system(size: legacyPoppinsSize(20), weight: .bold))
                                    .foregroundStyle(.gray)
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
                                .foregroundStyle(.white)
                        }
                        .frame(width: 18, height: 18)
                        .offset(x: 2, y: 2)
                    } else {
                        ZStack {
                            Circle().fill(Color.white)
                            Image(systemName: "plus")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 18, height: 18)
                        .offset(x: 2, y: 2)
                        .shadow(radius: 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(user.username)
                .font(.system(size: legacyPoppinsSize(10), weight: .medium))
                .foregroundStyle(.gray)
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
    @State private var persistedListName: String
    @State private var persistedListDescription: String
    @State private var persistedColor: String
    @State private var persistedIcon: String
    @State private var persistedMembers: Set<String>
    @State private var showingMemberPicker = false
    @State private var showingEmojiPicker = false
    @State private var selectedImage: UIImage?
    @State private var selectedImagePath: String?
    @State private var persistedImagePath: String?
    @State private var showingImageCrop = false
    
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
        _persistedListName = State(initialValue: list.name)
        _persistedListDescription = State(initialValue: list.description ?? "")
        _persistedColor = State(initialValue: list.color ?? CustomAudienceList.predefinedColors.first!)
        _persistedIcon = State(initialValue: list.icon ?? CustomAudienceList.predefinedIcons.first!)
        _persistedMembers = State(initialValue: Set(list.members))
        _selectedImagePath = State(initialValue: list.imagePath)
        _persistedImagePath = State(initialValue: list.imagePath)
    }
    
    var body: some View {
        content
        .sheet(isPresented: Binding(
            get: { !embeddedInFlow && showingMemberPicker },
            set: { showingMemberPicker = $0 }
        )) {
            MemberPickerView(
                selectedMembers: $selectedMembers,
                existingMemberIDs: persistedMembers,
                listName: listName,
                onBack: closeMemberPickerSavingIfNeeded,
                onRemoveMembers: persistMemberRemoval
            )
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(isPresented: $showingEmojiPicker) { emoji in
                selectedIcon = emoji
                selectedImage = nil
                selectedImagePath = nil
                hapticFeedback()
            }
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $showingImageCrop) {
            ProfileLibraryCropEntryView { croppedImage in
                selectedImage = croppedImage
                selectedImagePath = nil
                hapticFeedback()
            }
        }
    }
    
    private var content: some View {
        if embeddedInFlow && showingMemberPicker {
            return AnyView(
                MemberPickerView(
                    selectedMembers: $selectedMembers,
                    existingMemberIDs: persistedMembers,
                    listName: listName,
                    embeddedInFlow: true,
                    onBack: closeMemberPickerSavingIfNeeded,
                    onRemoveMembers: persistMemberRemoval
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
                                
                                CustomAudienceListIcon(
                                    icon: selectedIcon,
                                    size: 32,
                                    weight: .bold,
                                    imagePath: selectedImagePath,
                                    localImage: selectedImage,
                                    imageSize: 76
                                )
                                    .foregroundStyle(Color(hex: selectedColor))

                                if viewModel.isLoading && selectedImage != nil {
                                    Circle()
                                        .fill(.black.opacity(0.38))
                                        .frame(width: 76, height: 76)
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text(listName.isEmpty ? NSLocalizedString("audience.list.placeholder", comment: "") : listName)
                                .font(.system(size: legacyPoppinsSize(22), weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                            
                            Text(String(format: NSLocalizedString("audience.members.count.short", comment: ""), selectedMembers.count))
                                .font(.system(size: legacyPoppinsSize(14), weight: .medium))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
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
                        
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
            .momentsSheetScrollHeader {
                editHeader
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }

    private var editHeader: some View {
        HStack(spacing: 12) {
            Button(action: saveAndCloseIfNeeded) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(NSLocalizedString("common.edit", comment: ""))
                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                Text(list.name)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
            }
            .multilineTextAlignment(.center)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
    
    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private var hasUnsavedChanges: Bool {
        listName != persistedListName ||
        listDescription != persistedListDescription ||
        selectedColor != persistedColor ||
        selectedIcon != persistedIcon ||
        selectedImage != nil ||
        selectedImagePath != persistedImagePath ||
        selectedMembers != persistedMembers
    }

    private func closeEditor() {
        if embeddedInFlow {
            onBack?()
        } else {
            dismiss()
        }
    }

    private func saveAndCloseIfNeeded() {
        guard !viewModel.isLoading else { return }
        guard hasUnsavedChanges else {
            closeEditor()
            return
        }
        guard let listId = list.id, !listName.isEmpty else { return }

        viewModel.updateList(
            listId: listId,
            name: listName,
            description: listDescription,
            members: Array(selectedMembers),
            color: selectedColor,
            icon: selectedIcon,
            image: selectedImage,
            imagePath: selectedImagePath,
            previousImagePath: persistedImagePath
        ) { result in
            switch result {
            case .success(let savedImagePath):
                selectedImage = nil
                selectedImagePath = savedImagePath
                InAppNotificationService.shared.showActionToast(
                    .plain("audience.saved", fallback: "Audience saved", icon: "checkmark.circle.fill")
                )
                updatePersistedSnapshot()
                if let onCompleted {
                    onCompleted()
                } else {
                    closeEditor()
                }
            case .failure(let error):
                InAppNotificationService.shared.showActionToast(
                    InAppActionToast(systemImage: "exclamationmark.triangle.fill", prefix: error.localizedDescription)
                )
            }
        }
    }

    private func updatePersistedSnapshot() {
        persistedListName = listName
        persistedListDescription = listDescription
        persistedColor = selectedColor
        persistedIcon = selectedIcon
        persistedImagePath = selectedImagePath
        persistedMembers = selectedMembers
    }
    
    private var basicInfoSection: some View {
        VStack(spacing: 20) {
            // Nombre de la lista
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("audience.list.name")
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                } icon: {
                    Image(systemName: "pencil.circle.fill")
                }
                .foregroundStyle(.primary)
                .padding(.leading, 4)
                
                TextField(NSLocalizedString("audience.list.name.example", comment: ""), text: $listName)
                    .font(.system(size: legacyPoppinsSize(17), weight: .medium))
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
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                } icon: {
                    Image(systemName: "text.alignleft")
                }
                .foregroundStyle(.primary)
                .padding(.leading, 4)
                
                TextField(NSLocalizedString("audience.list.description.placeholder", comment: ""), text: $listDescription)
                    .font(.system(size: legacyPoppinsSize(17), weight: .medium))
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
                    .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
            } icon: {
                Image(systemName: "paintpalette.fill")
            }
            .foregroundStyle(.primary)
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
                                .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: selectedColor), value: selectedColor)
                                .onTapGesture {
                                    selectedColor = color
                                    hapticFeedback()
                                }
                        }

                        ColorPicker(
                            NSLocalizedString("common.color", comment: ""),
                            selection: Binding(
                                get: { Color(hex: selectedColor) },
                                set: { selectedColor = $0.toHex().uppercased() }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 42, height: 42)
                        .overlay {
                            Circle()
                                .stroke(
                                    colorScheme == .dark ? .white : .black,
                                    lineWidth: CustomAudienceList.predefinedColors.contains(selectedColor) ? 0 : 3
                                )
                                .padding(2)
                                .allowsHitTesting(false)
                        }
                        .scaleEffect(CustomAudienceList.predefinedColors.contains(selectedColor) ? 1 : 1.15)
                        .accessibilityLabel(Text(NSLocalizedString("common.color", comment: "")))
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
                                    .foregroundStyle(selectedIcon == icon ?
                                                   Color(hex: selectedColor) : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                                    .font(.system(size: 22, weight: .semibold))
                            }
                            .background(
                                Circle()
                                    .stroke(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.3) : Color.clear, lineWidth: 2)
                            )
                            .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                            .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: selectedIcon), value: selectedIcon)
                            .onTapGesture {
                                selectedIcon = icon
                                selectedImage = nil
                                selectedImagePath = nil
                                hapticFeedback()
                            }
                        }

                        Button {
                            showingEmojiPicker = true
                        } label: {
                            let isCustomEmoji = !CustomAudienceList.predefinedIcons.contains(selectedIcon)
                            ZStack {
                                Circle()
                                    .fill(
                                        isCustomEmoji
                                            ? Color(hex: selectedColor).opacity(0.15)
                                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                                    )
                                    .frame(width: 52, height: 52)

                                CustomAudienceListIcon(
                                    icon: isCustomEmoji ? selectedIcon : "face.smiling",
                                    size: 22
                                )
                                .foregroundStyle(
                                    isCustomEmoji
                                        ? Color(hex: selectedColor)
                                        : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                )
                            }
                            .background {
                                Circle()
                                    .stroke(
                                        isCustomEmoji ? Color(hex: selectedColor).opacity(0.3) : .clear,
                                        lineWidth: 2
                                    )
                            }
                            .scaleEffect(isCustomEmoji ? 1.1 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(NSLocalizedString("storyEditor.emojiPicker.title", comment: "")))

                        Button {
                            showingImageCrop = true
                        } label: {
                            let isPhotoSelected = selectedImage != nil || selectedImagePath != nil
                            ZStack {
                                Circle()
                                    .fill(
                                        isPhotoSelected
                                            ? Color(hex: selectedColor).opacity(0.15)
                                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                                    )
                                    .frame(width: 52, height: 52)

                                CustomAudienceListIcon(
                                    icon: "photo.fill",
                                    size: 21,
                                    imagePath: selectedImagePath,
                                    localImage: selectedImage,
                                    imageSize: 52
                                )
                                .foregroundStyle(
                                    isPhotoSelected
                                        ? Color(hex: selectedColor)
                                        : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                )
                            }
                            .background {
                                Circle()
                                    .stroke(
                                        isPhotoSelected ? Color(hex: selectedColor).opacity(0.3) : .clear,
                                        lineWidth: 2
                                    )
                            }
                            .scaleEffect(isPhotoSelected ? 1.1 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(NSLocalizedString("common.photo", comment: "")))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private var membersManagementSection: some View {
        Button(action: { showingMemberPicker = true }) {
            HStack(spacing: 14) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .momentsChromeGlass(in: Circle(), interactive: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("audience.picker.title", comment: ""))
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(String(format: NSLocalizedString("audience.members.count.long", comment: ""), selectedMembers.count))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func persistMemberRemoval(
        _ users: [AppUser],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let listId = list.id else { return }
        let removedIDs = Set(users.map(\.id))
        let updatedMembers = selectedMembers.subtracting(removedIDs)

        viewModel.updateList(
            listId: listId,
            name: listName,
            description: listDescription,
            members: Array(updatedMembers),
            color: selectedColor,
            icon: selectedIcon,
            image: selectedImage,
            imagePath: selectedImagePath,
            previousImagePath: persistedImagePath
        ) { result in
            if case .success(let savedImagePath) = result {
                selectedImage = nil
                selectedImagePath = savedImagePath
                selectedMembers = updatedMembers
                updatePersistedSnapshot()
            }
            completion(result.map { _ in () })
        }
    }

    private func closeMemberPickerSavingIfNeeded() {
        guard selectedMembers != persistedMembers else {
            showingMemberPicker = false
            return
        }
        guard let listId = list.id, !viewModel.isLoading else { return }

        viewModel.updateList(
            listId: listId,
            name: listName,
            description: listDescription,
            members: Array(selectedMembers),
            color: selectedColor,
            icon: selectedIcon,
            image: selectedImage,
            imagePath: selectedImagePath,
            previousImagePath: persistedImagePath
        ) { result in
            switch result {
            case .success(let savedImagePath):
                selectedImage = nil
                selectedImagePath = savedImagePath
                updatePersistedSnapshot()
                showingMemberPicker = false
                InAppNotificationService.shared.showActionToast(
                    .plain("audience.list.updated", fallback: "List updated", icon: "checkmark.circle.fill")
                )
            case .failure(let error):
                InAppNotificationService.shared.showActionToast(
                    InAppActionToast(systemImage: "exclamationmark.triangle.fill", prefix: error.localizedDescription)
                )
            }
        }
    }
}

// MARK: - Fila plana seleccionable para miembros de audiencia
struct AudienceMemberSelectionRow: View {
    @Environment(\.colorScheme) var colorScheme
    let user: AppUser
    let isSelected: Bool
    let isSelectionEnabled: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
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
                            .font(.system(size: legacyPoppinsSize(16), weight: .bold))
                            .foregroundStyle(.gray)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // Info del usuario
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                if user.isVerified {
                    VerifiedBadge(size: 13)
                }
            }
            
            Spacer()

            if isSelectionEnabled {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? (colorScheme == .dark ? .white : .black)
                                : (colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.2)),
                            lineWidth: isSelected ? 0 : 1.5
                        )
                        .background(
                            Circle().fill(isSelected ? (colorScheme == .dark ? .white : .black) : .clear)
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                    }
                }
                .frame(width: 26, height: 26)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectionEnabled)
    }
}

// MARK: - Selector de Miembros (MEJORADO)
struct MemberPickerView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedMembers: Set<String>
    @Environment(\.dismiss) private var dismiss
    let listName: String?
    let embeddedInFlow: Bool
    let onBack: (() -> Void)?
    let onRemoveMembers: (([AppUser], @escaping (Result<Void, Error>) -> Void) -> Void)?
    @State private var existingMemberIDs: Set<String>
    @State private var showingManageMembers = false
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @StateObject private var firestoreService = FirestoreService()
    @State private var suggestedUsers: [AppUser] = []
    @State private var isLoadingSuggestions = true

    init(
        selectedMembers: Binding<Set<String>>,
        existingMemberIDs: Set<String> = [],
        listName: String? = nil,
        embeddedInFlow: Bool = false,
        onBack: (() -> Void)? = nil,
        onRemoveMembers: (([AppUser], @escaping (Result<Void, Error>) -> Void) -> Void)? = nil
    ) {
        _selectedMembers = selectedMembers
        _existingMemberIDs = State(initialValue: existingMemberIDs)
        self.listName = listName
        self.embeddedInFlow = embeddedInFlow
        self.onBack = onBack
        self.onRemoveMembers = onRemoveMembers
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.65) : .black.opacity(0.62)
    }

    var body: some View {
        ZStack {
            if !embeddedInFlow {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
                    .ignoresSafeArea()
            }

            if showingManageMembers, let listName {
                AudienceManageMembersView(
                    selectedMembers: $selectedMembers,
                    memberIDs: existingMemberIDs.intersection(selectedMembers),
                    listName: listName,
                    onBack: { showingManageMembers = false },
                    onRemoveMembers: onRemoveMembers
                )
            } else {
                addMembersContent
            }
        }
        .onAppear {
            loadSuggestedUsers()
        }
        .onChange(of: selectedMembers) { _, members in
            existingMemberIDs.formIntersection(members)
        }
    }
    
    private var addMembersContent: some View {
        VStack(spacing: 0) {
            MemberPickerHeader(
                title: NSLocalizedString("audience.picker.title", comment: ""),
                subtitle: NSLocalizedString("audience.members", comment: ""),
                onBack: closePicker
            )

            searchBar

            if listName != nil {
                manageMembersRow
            }

            if !hasSearched {
                initialStateView
            } else if isSearching {
                loadingView
            } else if searchResults.isEmpty {
                emptyResultsView
            } else {
                resultsListView
            }
        }
    }

    private var manageMembersRow: some View {
        Button(action: { showingManageMembers = true }) {
            HStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .momentsChromeGlass(in: Circle(), interactive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("audience.manageMembers", value: "Manage members", comment: "Audience list member management"))
                        .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text(String(format: NSLocalizedString("audience.members.count.long", comment: ""), existingMemberIDs.intersection(selectedMembers).count))
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(secondaryTextColor)
            
            TextField(NSLocalizedString("audience.picker.searchPlaceholder", comment: ""), text: $searchText)
                .font(.system(size: legacyPoppinsSize(16)))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .onSubmit {
                    if !searchText.isEmpty {
                        searchUsers(query: searchText)
                    }
                }
                .onChange(of: searchText) { _, newValue in
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
                        .foregroundStyle(secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .momentsChromeGlass(in: Capsule(), interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var initialStateView: some View {
        Group {
            if isLoadingSuggestions {
                loadingView
            } else if suggestedUsers.isEmpty {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundStyle(secondaryTextColor)

                    Text(NSLocalizedString("audience.picker.initialTitle", comment: ""))
                        .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                        .foregroundStyle(primaryTextColor)

                    Text(NSLocalizedString("audience.picker.initialDescription", comment: ""))
                        .font(.system(size: legacyPoppinsSize(14)))
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Spacer()
                }
            } else {
                membersList(users: suggestedUsers, sectionTitle: NSLocalizedString("messaging.new.suggestions", comment: ""))
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(NSLocalizedString("common.searching", comment: ""))
                .font(.system(size: legacyPoppinsSize(16)))
                .foregroundStyle(secondaryTextColor)
            Spacer()
        }
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(secondaryTextColor)
            
            Text(NSLocalizedString("common.noResults", comment: ""))
                .font(.system(size: legacyPoppinsSize(18), weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Text(String(format: NSLocalizedString("audience.picker.noResultsDescription", comment: ""), searchText))
                .font(.system(size: legacyPoppinsSize(14)))
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
    }
    
    private var resultsListView: some View {
        membersList(users: searchResults)
    }

    private func membersList(users: [AppUser], sectionTitle: String? = nil) -> some View {
        List {
            if let sectionTitle {
                Text(sectionTitle)
                    .font(.system(size: legacyPoppinsSize(13), weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(users) { user in
                AudienceMemberSelectionRow(
                    user: user,
                    isSelected: selectedMembers.contains(user.id),
                    isSelectionEnabled: true,
                    onToggle: { toggleSelection(user: user) }
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listStyle(PlainListStyle())
        .listRowSeparator(.hidden)
    }
    
    private func searchUsers(query: String) {
        hasSearched = true
        isSearching = true
        firestoreService.searchUsers(query: query, limit: 20) { result in
            DispatchQueue.main.async {
                self.isSearching = false
                switch result {
                case .success(let users):
                    self.searchResults = users.filter { !self.existingMemberIDs.contains($0.id) }
                case .failure:
                    self.searchResults = []
                }
            }
        }
    }

    private func loadSuggestedUsers() {
        isLoadingSuggestions = true
        firestoreService.fetchNewConversationSuggestions(recentPartnerIds: []) { result in
            DispatchQueue.main.async {
                self.isLoadingSuggestions = false
                self.suggestedUsers = ((try? result.get()) ?? []).filter { !self.existingMemberIDs.contains($0.id) }
            }
        }
    }

    
    private func toggleSelection(user: AppUser) {
        if selectedMembers.contains(user.id) {
            selectedMembers.remove(user.id)
        } else {
            selectedMembers.insert(user.id)
        }
    }
    
    private func closePicker() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }
    
}

private struct MemberPickerHeader: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: legacyPoppinsSize(13)))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

private struct AudienceManageMembersView: View {
    @Binding var selectedMembers: Set<String>
    let memberIDs: Set<String>
    let listName: String
    let onBack: () -> Void
    let onRemoveMembers: (([AppUser], @escaping (Result<Void, Error>) -> Void) -> Void)?

    @State private var members: [AppUser] = []
    @State private var selectedForRemoval: Set<String> = []
    @State private var isEditing = false
    @State private var isLoading = true
    @State private var isRemoving = false
    @State private var showingConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    ForEach(members) { user in
                        AudienceMemberSelectionRow(
                            user: user,
                            isSelected: selectedForRemoval.contains(user.id),
                            isSelectionEnabled: isEditing,
                            onToggle: { toggle(user) }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .momentsSheetScrollHeader {
            manageHeader
        }
        .task {
            loadMembers()
        }
        .alert(NSLocalizedString("audience.manageMembers.remove.title", comment: ""), isPresented: $showingConfirmation) {
            Button(NSLocalizedString("audience.actions.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                removeSelectedMembers()
            }
        } message: {
            Text(removalConfirmationMessage)
        }
    }

    private var manageHeader: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(NSLocalizedString("audience.manageMembers", value: "Manage members", comment: "Audience list member management"))
                    .font(.system(size: legacyPoppinsSize(19), weight: .semibold))
                Text(String(format: NSLocalizedString("audience.members.count.short", comment: ""), members.count))
                    .font(.system(size: legacyPoppinsSize(12)))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer()

            if selectedForRemoval.isEmpty {
                Button(NSLocalizedString("common.edit", comment: "")) {
                    isEditing = true
                }
                .font(.system(size: legacyPoppinsSize(14), weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .momentsChromeGlass(
                    in: Capsule(),
                    interactive: !isRemoving && !members.isEmpty
                )
                .buttonStyle(.plain)
                .disabled(isRemoving || members.isEmpty)
            } else {
                Button(action: { showingConfirmation = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text("\(selectedForRemoval.count)")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(minWidth: 54, minHeight: 40)
                    .momentsChromeGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(isRemoving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func loadMembers() {
        guard !memberIDs.isEmpty else {
            members = []
            isLoading = false
            return
        }

        FirestoreService().fetchUsers(userIds: Array(memberIDs)) { result in
            DispatchQueue.main.async {
                members = (try? result.get()) ?? []
                isLoading = false
            }
        }
    }

    private func toggle(_ user: AppUser) {
        guard isEditing else { return }
        if selectedForRemoval.contains(user.id) {
            selectedForRemoval.remove(user.id)
        } else {
            selectedForRemoval.insert(user.id)
        }
    }

    private func removeSelectedMembers() {
        let removedUsers = usersSelectedForRemoval
        guard !removedUsers.isEmpty, let onRemoveMembers else { return }
        isRemoving = true

        onRemoveMembers(removedUsers) { result in
            DispatchQueue.main.async {
                isRemoving = false
                switch result {
                case .success:
                    selectedMembers.subtract(selectedForRemoval)
                    members.removeAll { selectedForRemoval.contains($0.id) }
                    let subtitle = removalSubtitle(for: removedUsers)
                    selectedForRemoval.removeAll()
                    isEditing = false
                    InAppNotificationService.shared.showActionToast(
                        InAppActionToast(
                            systemImage: "checkmark.circle.fill",
                            prefix: NSLocalizedString("audience.list.updated", value: "List updated", comment: "Audience list updated"),
                            subtitle: subtitle
                        )
                    )
                case .failure(let error):
                    InAppNotificationService.shared.showActionToast(
                        InAppActionToast(systemImage: "exclamationmark.triangle.fill", prefix: error.localizedDescription)
                    )
                }
            }
        }
    }

    private var usersSelectedForRemoval: [AppUser] {
        members.filter { selectedForRemoval.contains($0.id) }
    }

    private var removalConfirmationMessage: String {
        guard let first = usersSelectedForRemoval.first else { return "" }
        if usersSelectedForRemoval.count == 1 {
            return String.localizedStringWithFormat(
                NSLocalizedString("audience.manageMembers.remove.single", comment: "One member removal confirmation"),
                first.username,
                listName
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("audience.manageMembers.remove.plural", comment: "Multiple member removal confirmation"),
            first.username,
            usersSelectedForRemoval.count - 1,
            listName
        )
    }

    private func removalSubtitle(for removedUsers: [AppUser]) -> String {
        guard let first = removedUsers.first else { return "" }
        if removedUsers.count == 1 {
            return String(
                format: NSLocalizedString(
                    "audience.list.membersRemoved.single",
                    value: "You removed %@ from %@",
                    comment: "One member removed from an audience list"
                ),
                first.username,
                listName
            )
        }

        return String(
            format: NSLocalizedString(
                "audience.list.membersRemoved.plural",
                value: "You removed %@ and %d more from %@",
                comment: "Several members removed from an audience list"
            ),
            first.username,
            removedUsers.count - 1,
            listName
        )
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
                                .foregroundStyle(.secondary)
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
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                
                if user.isVerified {
                    VerifiedBadge(size: 14)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? Color(hex: "007AFF") : .primary)
                    .frame(width: 28, height: 28)
                    .momentsChromeGlass(in: Circle(), interactive: true)
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
    private let storageService = StorageService()
    
    func createList(
        name: String,
        description: String,
        members: [String],
        color: String,
        icon: String,
        image: UIImage?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "AudienceList", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to save the list."])))
            return
        }
        
        isLoading = true
        let document = db.collection("users").document(userId)
            .collection("customAudienceLists")
            .document()

        let persistList: (String?) -> Void = { [weak self] imagePath in
            guard let self else { return }
            let newList = CustomAudienceList(
                name: name,
                description: description.isEmpty ? nil : description,
                members: members,
                color: color,
                icon: icon,
                imagePath: imagePath
            )

            do {
                try document.setData(from: newList) { error in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let error {
                            if let imagePath {
                                self.storageService.deleteMedia(path: imagePath) { _ in }
                            }
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
                }
            } catch {
                self.isLoading = false
                if let imagePath {
                    self.storageService.deleteMedia(path: imagePath) { _ in }
                }
                completion(.failure(error))
            }
        }

        guard let image else {
            persistList(nil)
            return
        }

        storageService.uploadAudienceListImage(
            userId: userId,
            listId: document.documentID,
            image: image
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let imagePath):
                    persistList(imagePath)
                case .failure(let error):
                    self?.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
}

class EditListViewModel: ObservableObject {
    @Published var isLoading = false
    private let db = Firestore.firestore()
    private let storageService = StorageService()
    
    func updateList(
        listId: String,
        name: String,
        description: String,
        members: [String],
        color: String,
        icon: String,
        image: UIImage?,
        imagePath: String?,
        previousImagePath: String?,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "AudienceList", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to save the list."])))
            return
        }
        
        isLoading = true

        let persistChanges: (String?, Bool) -> Void = { [weak self] resolvedImagePath, uploadedNewImage in
            guard let self else { return }
            let updateData: [String: Any] = [
                "name": name,
                "description": description.isEmpty ? FieldValue.delete() : description,
                "members": members,
                "color": color,
                "icon": icon,
                "imagePath": resolvedImagePath.map { $0 as Any } ?? FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            self.db.collection("users").document(userId)
                .collection("customAudienceLists")
                .document(listId)
                .updateData(updateData) { error in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let error {
                            if uploadedNewImage, let resolvedImagePath {
                                self.storageService.deleteMedia(path: resolvedImagePath) { _ in }
                            }
                            completion(.failure(error))
                            return
                        }

                        if let previousImagePath,
                           previousImagePath != resolvedImagePath {
                            self.storageService.deleteMedia(path: previousImagePath) { _ in }
                        }
                        completion(.success(resolvedImagePath))
                    }
                }
        }

        guard let image else {
            persistChanges(imagePath, false)
            return
        }

        storageService.uploadAudienceListImage(
            userId: userId,
            listId: listId,
            image: image
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let uploadedPath):
                    persistChanges(uploadedPath, true)
                case .failure(let error):
                    self?.isLoading = false
                    completion(.failure(error))
                }
            }
        }
    }
}
