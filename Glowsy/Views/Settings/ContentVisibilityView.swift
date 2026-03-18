import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ContentVisibilityView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ContentVisibilityViewModel()
    @State private var isLoading = true
    @State private var showingStoryAudienceSelector = false
    @State private var showingPostAudienceSelector = false
    @State private var showingStoryInteractionSettings = false // ✅ NUEVO
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
                
                if isLoading {
                    ProgressView(NSLocalizedString("contentVisibility.loading", comment: "Loading configuration..."))
                        .progressViewStyle(CircularProgressViewStyle())
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(.gray)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            
                            // MARK: Stories
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: "circle.dashed")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                    Text(NSLocalizedString("contentVisibility.stories.title", comment: "Stories").uppercased())
                                        .font(.custom("Poppins-Bold", size: 11))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                }
                                .padding(.leading, 4)
                                
                                VStack(spacing: 0) {
                                    Button(action: { showingStoryAudienceSelector = true }) {
                                        currentAudienceRow(
                                            audience: viewModel.storyAudience,
                                            customListName: viewModel.storyCustomListName,
                                            customCount: viewModel.storyCustomUsers.count
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    Divider().opacity(0.2).padding(.leading, 42)
                                    
                                    Button(action: { showingStoryInteractionSettings = true }) {
                                        HStack(spacing: 14) {
                                            Image(systemName: "gear")
                                                .font(.system(size: 19, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .frame(width: 28, alignment: .center)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(NSLocalizedString("contentVisibility.interactions.title", comment: "Interactions title"))
                                                    .font(.custom("Poppins-SemiBold", size: 15))
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
                                        .padding(.vertical, 11)
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            // MARK: Posts
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.grid.3x3")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                    Text(NSLocalizedString("contentVisibility.posts.title", comment: "Posts").uppercased())
                                        .font(.custom("Poppins-Bold", size: 11))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                }
                                .padding(.leading, 4)
                                
                                VStack(spacing: 0) {
                                    Button(action: { showingPostAudienceSelector = true }) {
                                        currentAudienceRow(
                                            audience: viewModel.postAudience,
                                            customListName: viewModel.postCustomListName,
                                            customCount: viewModel.postCustomUsers.count
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            // MARK: Additional restrictions
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                    Text(NSLocalizedString("contentVisibility.additionalRestrictions", comment: "Additional restrictions header").uppercased())
                                        .font(.custom("Poppins-Bold", size: 11))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                }
                                .padding(.leading, 4)
                                
                                VStack(spacing: 0) {
                                    NavigationLink(destination: HiddenFromView(viewModel: viewModel)) {
                                        HStack(spacing: 14) {
                                            Image(systemName: "eye.slash")
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .font(.system(size: 18))
                                                .frame(width: 28, alignment: .center)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(NSLocalizedString("contentVisibility.hideFrom", comment: "Hide from label"))
                                                    .font(.custom("Poppins-Medium", size: 15))
                                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                                Text(String(format: NSLocalizedString("contentVisibility.hiddenCount", comment: "Hidden users count"), viewModel.hiddenFromUsers.count))
                                                    .font(.custom("Poppins-Regular", size: 13))
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 11)
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                            
                            // MARK: Audience lists
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NSLocalizedString("contentVisibility.audienceLists", comment: "Audience lists header").uppercased())
                                    .font(.custom("Poppins-Bold", size: 11))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.35))
                                    .padding(.leading, 4)
                                
                                VStack(spacing: 0) {
                                    NavigationLink(destination: CustomAudienceListsView()) {
                                        HStack(spacing: 14) {
                                            Image(systemName: "list.bullet.rectangle")
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .font(.system(size: 18))
                                                .frame(width: 28, alignment: .center)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(NSLocalizedString("contentVisibility.manageCustomLists", comment: "Manage custom lists label"))
                                                    .font(.custom("Poppins-Medium", size: 15))
                                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                                Text(NSLocalizedString("contentVisibility.createEditAudience", comment: "Create and edit custom audiences label"))
                                                    .font(.custom("Poppins-Regular", size: 13))
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 11)
                                        .padding(.horizontal, 4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                } // end else
            } // end ZStack
            .navigationTitle(NSLocalizedString("contentVisibility.title", comment: "Content Privacy"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .onAppear {
                viewModel.loadSettings {
                    isLoading = false
                }
            }
            .sheet(isPresented: $showingStoryAudienceSelector) {
                StoryAudienceSelector(viewModel: viewModel)
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $showingPostAudienceSelector) {
                PostAudienceSelector(viewModel: viewModel)
                    .presentationBackground(.clear)
            }
            // ✅ NUEVO: Sheet para configuración de interacciones
            .sheet(isPresented: $showingStoryInteractionSettings) {
                StoryInteractionSettingsView(viewModel: viewModel)
            }
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
        case 3: return NSLocalizedString("contentVisibility.interactions.allAllowed", comment: "All interactions allowed")
        case 2: return NSLocalizedString("contentVisibility.interactions.someAllowed", comment: "Some interactions allowed")
        case 1: return NSLocalizedString("contentVisibility.interactions.limited", comment: "Limited interactions")
        case 0: return NSLocalizedString("contentVisibility.interactions.none", comment: "No interactions")
        default: return NSLocalizedString("contentVisibility.interactions.configure", comment: "Configure interactions")
        }
    }
    
    private func contentTypeHeader(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .font(.system(size: 18, weight: .medium))

                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }

            Text(description)
                .font(.custom("Poppins-Regular", size: 13))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 6)
    }
    
    private func currentAudienceRow(audience: ContentAudience, customListName: String?, customCount: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: audience.icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(getAudienceDisplayTitle(audience: audience, customListName: customListName))
                    .font(.custom("Poppins-SemiBold", size: 15))
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
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
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
            return customCount > 0 ? String(format: NSLocalizedString("contentVisibility.custom.selected", comment: "Selected people"), customCount) : NSLocalizedString("contentVisibility.custom.selection", comment: "Custom selection")
        case .customList:
            return NSLocalizedString("contentVisibility.customList", comment: "Custom list")
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
                            .foregroundColor(Color(hex: "4F46E5"))
                            .font(.system(size: 18))
                        
                        Text(NSLocalizedString("contentVisibility.interactionsConfig.title", comment: "Configure interactions title"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    Text(NSLocalizedString("contentVisibility.interactionsConfig.description", comment: "Configure interactions description"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "4F46E5").opacity(0.1))
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Opciones de configuración
                VStack(spacing: 16) {
                    InteractionToggleRow(
                        icon: "message.fill",
                        title: NSLocalizedString("contentVisibility.interactions.messages.title", comment: "Messages"),
                        description: NSLocalizedString("contentVisibility.interactions.messages.description", comment: "Allow them to send you private messages from your stories"),
                        isOn: $viewModel.allowStoryMessages
                    )
                    
                    InteractionToggleRow(
                        icon: "heart.fill",
                        title: NSLocalizedString("contentVisibility.interactions.reactions.title", comment: "Reactions"),
                        description: NSLocalizedString("contentVisibility.interactions.reactions.description", comment: "Allow them to react with emojis to your stories"),
                        isOn: $viewModel.allowStoryReactions
                    )
                    
                    InteractionToggleRow(
                        icon: "camera.fill",
                        title: NSLocalizedString("contentVisibility.interactions.ephemeralPhotos.title", comment: "Ephemeral photos"),
                        description: NSLocalizedString("contentVisibility.interactions.ephemeralPhotos.description", comment: "Allow them to send photos as responses to your stories"),
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
                        
                        Text(NSLocalizedString("contentVisibility.viewOnlyMode", comment: "View only mode label"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.orange)
                        
                        Text(NSLocalizedString("contentVisibility.viewOnlyMode.description", comment: "View only mode description"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background((colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea())
            .navigationTitle(NSLocalizedString("contentVisibility.interactions.navigation", comment: "Interactions"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("contentVisibility.cancel", comment: "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("contentVisibility.save", comment: "Save")) {
                        viewModel.saveStoryInteractionSettings()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "4F46E5"))
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(isOn ? Color(hex: "4F46E5") : .gray)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text(description)
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "4F46E5")))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 4)
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
            .navigationTitle(NSLocalizedString("contentVisibility.storyAudience.navigation", comment: "Story Audience"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("contentVisibility.done", comment: "Done")) {
                        viewModel.saveStorySettings()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "4F46E5"))
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
            .navigationTitle(NSLocalizedString("contentVisibility.postAudience.navigation", comment: "Post Audience"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("contentVisibility.done", comment: "Done")) {
                        viewModel.savePostSettings()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "4F46E5"))
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

        var updates: [String: Any] = [
            "contentVisibilitySettings.\(audienceKey)": audience.rawValue,
            "contentVisibilitySettings.\(customUsersKey)": customUsers,
            "contentVisibilitySettings.hiddenFromUsers": hiddenFromUsers.map { $0.id }
        ]

        if let listId = listId, !listId.isEmpty {
            updates["contentVisibilitySettings.\(listIdKey)"] = listId
        } else {
            updates["contentVisibilitySettings.\(listIdKey)"] = FieldValue.delete()
        }

        if let listName = listName, !listName.isEmpty {
            updates["contentVisibilitySettings.\(listNameKey)"] = listName
        } else {
            updates["contentVisibilitySettings.\(listNameKey)"] = FieldValue.delete()
        }

        firestoreService.db.collection("users").document(userId).updateData(updates) { error in
            if let error = error {
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
                    break
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
                        .foregroundColor(Color(hex: "4F46E5"))
                    
                    Text(NSLocalizedString("contentVisibility.info.title", comment: "Information title"))
                        .font(.custom("Poppins-SemiBold", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                Text(NSLocalizedString("contentVisibility.info.description", comment: "Information description"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "4F46E5").opacity(0.1))
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
                    .fill(colorScheme == .dark ? Color(hex: "FAF9F6").opacity(0.06) : Color(hex: "0B1215").opacity(0.05))
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
                                
                                Text("contentVisibility.noHiddenUsers.title")
                                    .font(.custom("Poppins-Regular", size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                
                                Text("contentVisibility.noHiddenUsers.description")
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
                .background((colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea())
            }
        }
        .navigationTitle(NSLocalizedString("contentVisibility.hideContent.navigation", comment: "Hide Content"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
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
                        .foregroundColor(Color(hex: "4F46E5"))
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
