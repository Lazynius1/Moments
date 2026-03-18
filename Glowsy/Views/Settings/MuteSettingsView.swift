import SwiftUI
import FirebaseAuth

struct MuteSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = MuteSettingsViewModel()
    @State private var isLoading = true
    @State private var showAddMutedUser = false
    @State private var showAddMutedWord = false
    
    var body: some View {
        NavigationView {
            ZStack {
            (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6")).ignoresSafeArea()
            
            if isLoading {
                ProgressView("Cargando configuración...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.gray)
            } else {
                List {
                    // Muted Users Section
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("muteSettings.mutedAccounts.title", comment: "Muted accounts title"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text(NSLocalizedString("muteSettings.mutedAccounts.description", comment: "Muted accounts description"))
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: { showAddMutedUser = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(hex: "4F46E5"))
                                    .font(.system(size: 24))
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if viewModel.mutedUsers.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "person.slash")
                                        .font(.system(size: 30))
                                        .foregroundColor(.gray)
                                    
                                    Text(NSLocalizedString("muteSettings.noMutedUsers", comment: "No muted users"))
                                        .font(.custom("Poppins-Regular", size: 14))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            ForEach(viewModel.mutedUsers) { user in
                                MutedUserRow(user: user) {
                                    viewModel.unmuteUser(user.id)
                                }
                            }
                        }
                        
                    } header: {
                        Text("")
                    }
                    .listRowBackground(LiistRowBackground())
                    
                    // Muted Words Section
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("muteSettings.mutedWords.title", comment: "Muted words title"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text(NSLocalizedString("muteSettings.mutedWords.description", comment: "Muted words description"))
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: { showAddMutedWord = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(hex: "4F46E5"))
                                    .font(.system(size: 24))
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if viewModel.mutedWords.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "text.badge.xmark")
                                        .font(.system(size: 30))
                                        .foregroundColor(.gray)
                                    
                                    Text(NSLocalizedString("muteSettings.noMutedWords", comment: "No muted words"))
                                        .font(.custom("Poppins-Regular", size: 14))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            ForEach(Array(viewModel.mutedWords.enumerated()), id: \.offset) { index, word in
                                MutedWordRow(word: word) {
                                    viewModel.removeMutedWord(word)
                                }
                            }
                        }
                        
                    } header: {
                        Text("")
                    }
                    .listRowBackground(LiistRowBackground())
                    
                    // Settings Section
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .font(.system(size: 18))
                                
                                Text(NSLocalizedString("muteSettings.configuration.title", comment: "Mute configuration title"))
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            
                            Toggle(isOn: $viewModel.muteNotifications) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("muteSettings.notifications.title", comment: "Mute notifications title"))
                                        .font(.custom("Poppins-Medium", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(NSLocalizedString("muteSettings.notifications.description", comment: "Mute notifications description"))
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(Color(hex: "4F46E5"))
                            .onChange(of: viewModel.muteNotifications) { _ in
                                viewModel.saveSettings()
                            }
                            
                            Toggle(isOn: $viewModel.hideFromSearch) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("muteSettings.hideFromSearch.title", comment: "Hide from search title"))
                                        .font(.custom("Poppins-Medium", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(NSLocalizedString("muteSettings.hideFromSearch.description", comment: "Hide from search description"))
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(Color(hex: "4F46E5"))
                            .onChange(of: viewModel.hideFromSearch) { _ in
                                viewModel.saveSettings()
                            }
                        }
                        .padding(.vertical, 4)
                        
                    } header: {
                        Text(NSLocalizedString("muteSettings.additionalOptions", comment: "Additional options"))
                    }
                    .listRowBackground(LiistRowBackground())
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(NSLocalizedString("muteSettings.navigation.title", comment: "Mute navigation title"))
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
        .sheet(isPresented: $showAddMutedUser) {
            AddMutedUserView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAddMutedWord) {
            AddMutedWordView(viewModel: viewModel)
        }
        }
    }
}

struct MutedUserRow: View {
    @Environment(\.colorScheme) var colorScheme
    let user: AppUser
    let onUnmute: () -> Void
    @State private var showUnmuteAlert = false
    
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
                Text("\(user.username)")
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
            
            Button(NSLocalizedString("muteSettings.activate", comment: "Activate button")) {
                showUnmuteAlert = true
            }
            .font(.custom("Poppins-Medium", size: 14))
            .foregroundColor(Color(hex: "4F46E5"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "4F46E5"), lineWidth: 1)
            )
        }
                .alert(NSLocalizedString("muteSettings.alert.activateUser.title", comment: "Activate user alert title"), isPresented: $showUnmuteAlert) {
            Button(NSLocalizedString("muteSettings.cancel", comment: "Cancel button"), role: .cancel) { }
            Button(NSLocalizedString("muteSettings.activate", comment: "Activate button"), role: .destructive) {
                onUnmute()
            }
        } message: {
            Text(String(format: NSLocalizedString("muteSettings.alert.activateUser.message", comment: "Activate user alert message"), user.username))
        }
    }
}

struct MutedWordRow: View {
    @Environment(\.colorScheme) var colorScheme
    let word: String
    let onRemove: () -> Void
    @State private var showRemoveAlert = false
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.xmark")
                    .foregroundColor(.gray)
                    .font(.system(size: 16))
                
                Text(word)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            Spacer()
            
            Button(action: { showRemoveAlert = true }) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 20))
            }
        }
        .alert(NSLocalizedString("muteSettings.alert.removeWord.title", comment: "Remove word alert title"), isPresented: $showRemoveAlert) {
            Button(NSLocalizedString("muteSettings.cancel", comment: "Cancel button"), role: .cancel) { }
            Button(NSLocalizedString("muteSettings.remove", comment: "Remove button"), role: .destructive) {
                onRemove()
            }
        } message: {
            Text(String(format: NSLocalizedString("muteSettings.alert.removeWord.message", comment: "Remove word alert message"), word))
        }
    }
}

struct AddMutedUserView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: MuteSettingsViewModel
    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField(NSLocalizedString("muteSettings.search.placeholder", comment: "Search users placeholder"), text: $searchText)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
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
                    ProgressView(NSLocalizedString("muteSettings.searching", comment: "Searching progress"))
                        .padding()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Text(NSLocalizedString("muteSettings.noUsersFound", comment: "No users found"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(searchResults) { user in
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
                                Text("\(user.username)")
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
                            
                            let isMuted = viewModel.mutedUsers.contains { $0.id == user.id }
                            
                            Button(isMuted ? NSLocalizedString("muteSettings.activate", comment: "Activate button") : NSLocalizedString("muteSettings.navigation.title", comment: "Mute button")) {
                                if isMuted {
                                    viewModel.unmuteUser(user.id)
                                } else {
                                    viewModel.muteUser(user)
                                }
                            }
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(isMuted ? Color(hex: "4F46E5") : .red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isMuted ? Color(hex: "4F46E5") : .red, lineWidth: 1)
                            )
                        }
                        .listRowBackground(LiistRowBackground())
                    }
                    .scrollContentBackground(.hidden)
                }
                
                Spacer()
            }
            .navigationTitle(NSLocalizedString("muteSettings.muteUser.title", comment: "Mute user navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
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

struct AddMutedWordView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var viewModel: MuteSettingsViewModel
    @State private var newWord = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("muteSettings.addWord.title", comment: "Add word title"))
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(NSLocalizedString("muteSettings.addWord.description", comment: "Add word description"))
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                    
                    TextField(NSLocalizedString("muteSettings.textField.placeholder", comment: "Text field placeholder"), text: $newWord)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "4F46E5").opacity(0.3), lineWidth: 1)
                                )
                        )
                    
                    Button(action: {
                        if !newWord.trimmingCharacters(in: .whitespaces).isEmpty {
                            viewModel.addMutedWord(newWord.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        }
                    }) {
                        Text(NSLocalizedString("muteSettings.add", comment: "Add button"))
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(newWord.isEmpty ? Color.gray : Color(hex: "4F46E5"))
                            )
                    }
                    .disabled(newWord.isEmpty)
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle(NSLocalizedString("muteSettings.mutedWord.title", comment: "Muted word navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("muteSettings.cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

class MuteSettingsViewModel: ObservableObject {
    @Published var mutedUsers: [AppUser] = []
    @Published var mutedWords: [String] = []
    @Published var muteNotifications = false
    @Published var hideFromSearch = false
    
    private let firestoreService = FirestoreService()
    
    func loadSettings(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion()
            return
        }
        
        firestoreService.db.collection("users").document(userId).getDocument { [weak self] snapshot, _ in
            guard let self = self else {
                completion()
                return
            }
            
            let rawSettings = snapshot?.data()?["muteSettings"] as? [String: Any] ?? [:]
            let mutedUserIds = rawSettings["mutedUsers"] as? [String] ?? []
            let words = rawSettings["mutedWords"] as? [String] ?? []
            let muteNotifs = rawSettings["muteNotifications"] as? Bool ?? false
            let hideSearch = rawSettings["hideFromSearch"] as? Bool ?? false
            
            DispatchQueue.main.async {
                self.mutedWords = words
                self.muteNotifications = muteNotifs
                self.hideFromSearch = hideSearch
            }
            
            self.loadMutedUsers(userIds: mutedUserIds) {
                completion()
            }
        }
    }

    private func loadMutedUsers(userIds: [String], completion: @escaping () -> Void) {
        guard !userIds.isEmpty else {
            DispatchQueue.main.async {
                self.mutedUsers = []
                completion()
            }
            return
        }
        
        let group = DispatchGroup()
        let lock = NSLock()
        var loadedById: [String: AppUser] = [:]
        
        for mutedUserId in userIds {
            group.enter()
            firestoreService.fetchUserProfile(userId: mutedUserId) { result in
                if case .success(let user) = result {
                    lock.lock()
                    loadedById[user.id] = user
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.mutedUsers = userIds.compactMap { loadedById[$0] }
            completion()
        }
    }
    
    func muteUser(_ user: AppUser) {
        if !mutedUsers.contains(where: { $0.id == user.id }) {
            mutedUsers.append(user)
            saveSettings()
        }
    }
    
    func unmuteUser(_ userId: String) {
        mutedUsers.removeAll { $0.id == userId }
        saveSettings()
    }
    
    func addMutedWord(_ word: String) {
        if !mutedWords.contains(word.lowercased()) {
            mutedWords.append(word.lowercased())
            saveSettings()
        }
    }
    
    func removeMutedWord(_ word: String) {
        mutedWords.removeAll { $0 == word }
        saveSettings()
    }
    
    func saveSettings() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let settings: [String: Any] = [
            "mutedUsers": mutedUsers.map { $0.id },
            "mutedWords": mutedWords,
            "muteNotifications": muteNotifications,
            "hideFromSearch": hideFromSearch
        ]
        
        firestoreService.db.collection("users").document(userId).updateData([
            "muteSettings": settings
        ]) { error in
            if let error = error {
            }
        }
    }
}

struct LiistRowBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color(colorScheme == .dark ? .black : .white).opacity(0.2))
            LinearGradient(
                colors: [Color(colorScheme == .dark ? .white : .black).opacity(0.1), Color(hex: "4F46E5").opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.overlay)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
