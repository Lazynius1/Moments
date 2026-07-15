import FirebaseAuth
import FirebaseFirestore
import SwiftUI

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
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .momentsChromeGlass(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        VStack(spacing: 2) {
                            Text(NSLocalizedString("audience.actions.selectPeople", comment: "Select people navigation title"))
                                .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                                .foregroundStyle(colorScheme == .dark ? .white : .black)
                            Text(NSLocalizedString("audience.description.custom", comment: "Custom audience description"))
                                .font(.system(size: legacyPoppinsSize(13)))
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
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
                        .foregroundStyle(.gray)
                    
                    TextField("Buscar personas...", text: $searchText)
                        .font(.system(size: legacyPoppinsSize(16)))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .onChange(of: searchText) { _, newValue in
                            if !newValue.isEmpty {
                                searchUsers(query: newValue)
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .momentsChromeGlass(in: Capsule(), interactive: true)
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
                            .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "007AFF"))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                case .failure:
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
                                .foregroundStyle(.gray)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                // Info del usuario
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(user.username)")
                        .font(.system(size: legacyPoppinsSize(12)))
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color(hex: "00A896") : .gray)
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
        .onChange(of: viewModel.lists) { _, _ in
            onListsChanged?()
        }
        .overlay(alignment: .bottom) {
            if showingDeleteFeedback {
                Text(String(format: NSLocalizedString("audience.deleteList.success", comment: ""), deletedListName))
                    .font(.system(size: legacyPoppinsSize(15), weight: .medium))
                    .foregroundStyle(.white)
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
                    .foregroundStyle(.gray)
            } else {
                VStack(spacing: 0) {
                    if embeddedInFlow {
                        HStack(spacing: 12) {
                            Button(action: { onBack?() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .momentsChromeGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            VStack(spacing: 2) {
                                Text(NSLocalizedString("audience.customLists.title", comment: ""))
                                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("audience.customLists", comment: ""))
                                    .font(.system(size: legacyPoppinsSize(13)))
                                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
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
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .momentsChromeGlass(in: Circle(), interactive: true)
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
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .momentsChromeGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            VStack(spacing: 2) {
                                Text(NSLocalizedString("audience.customLists.title", comment: ""))
                                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                Text(NSLocalizedString("audience.customLists", comment: ""))
                                    .font(.system(size: legacyPoppinsSize(13)))
                                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                            }
                            .multilineTextAlignment(.center)

                            Spacer()

                            Button(action: { showingCreateList = true }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .momentsChromeGlass(in: Circle(), interactive: true)
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
            AudienceIconView(
                audience: .customList,
                size: 44,
                tintColor: .gray
            )
            
            VStack(spacing: 6) {
                Text(NSLocalizedString("audience.noCustomLists.title", comment: ""))
                    .font(.system(size: legacyPoppinsSize(20), weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Text(NSLocalizedString("audience.noCustomLists.description", comment: ""))
                    .font(.system(size: legacyPoppinsSize(16)))
                    .foregroundStyle(.gray)
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
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .momentsChromeGlass(in: Circle(), interactive: true)
                    
                    Text(NSLocalizedString("audience.createFirstList", comment: ""))
                        .font(.system(size: legacyPoppinsSize(16), weight: .semibold))
                        .foregroundStyle(.primary)
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
                        .foregroundStyle(Color(hex: list.color ?? "00A896"))
                }
                
                VStack(spacing: 4) {
                    Text(list.name)
                        .font(.system(size: legacyPoppinsSize(15), weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                        Text(String(format: NSLocalizedString("audience.people.count", comment: ""), list.members.count))
                            .font(.system(size: legacyPoppinsSize(12)))
                    }
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(MotionPolicy.animation(MotionPolicy.Spring.toggle, value: isPressed), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressing in
            isPressed = pressing
        })
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
            .delete { _ in }
    }
}

