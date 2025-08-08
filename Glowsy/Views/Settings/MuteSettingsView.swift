import SwiftUI
import FirebaseAuth

struct MuteSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = MuteSettingsViewModel()
    @State private var isLoading = true
    @State private var showAddMutedUser = false
    @State private var showAddMutedWord = false
    
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
                    // Muted Users Section
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cuentas silenciadas")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("No verás publicaciones ni historias de estas cuentas")
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: { showAddMutedUser = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(hex: "00A896"))
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
                                    
                                    Text("No has silenciado a nadie")
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
                                Text("Palabras y frases silenciadas")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text("No verás contenido que contenga estas palabras")
                                    .font(.custom("Poppins-Regular", size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Button(action: { showAddMutedWord = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(hex: "00A896"))
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
                                    
                                    Text("No has silenciado palabras")
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
                                
                                Text("Configuración de silenciado")
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            
                            Toggle(isOn: $viewModel.muteNotifications) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Silenciar notificaciones")
                                        .font(.custom("Poppins-Medium", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("No recibir notificaciones de cuentas silenciadas")
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(Color(hex: "00A896"))
                            .onChange(of: viewModel.muteNotifications) { _ in
                                viewModel.saveSettings()
                            }
                            
                            Toggle(isOn: $viewModel.hideFromSearch) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ocultar de búsquedas")
                                        .font(.custom("Poppins-Medium", size: 15))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text("Las cuentas silenciadas no aparecerán en búsquedas")
                                        .font(.custom("Poppins-Regular", size: 13))
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(Color(hex: "00A896"))
                            .onChange(of: viewModel.hideFromSearch) { _ in
                                viewModel.saveSettings()
                            }
                        }
                        .padding(.vertical, 4)
                        
                    } header: {
                        Text("Opciones adicionales")
                    }
                    .listRowBackground(LiistRowBackground())
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Silenciar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
            
            Button("Activar") {
                showUnmuteAlert = true
            }
            .font(.custom("Poppins-Medium", size: 14))
            .foregroundColor(Color(hex: "00A896"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "00A896"), lineWidth: 1)
            )
        }
        .alert("¿Activar usuario?", isPresented: $showUnmuteAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Activar", role: .destructive) {
                onUnmute()
            }
        } message: {
            Text("Volverás a ver el contenido de \(user.username)")
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
        .alert("¿Quitar palabra silenciada?", isPresented: $showRemoveAlert) {
            Button("Cancelar", role: .cancel) { }
            Button("Quitar", role: .destructive) {
                onRemove()
            }
        } message: {
            Text("Volverás a ver contenido que contenga '\(word)'")
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
                    
                    TextField("Buscar usuarios...", text: $searchText)
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
                    ProgressView("Buscando...")
                        .padding()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Text("No se encontraron usuarios")
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
                            
                            Button(isMuted ? "Activar" : "Silenciar") {
                                if isMuted {
                                    viewModel.unmuteUser(user.id)
                                } else {
                                    viewModel.muteUser(user)
                                }
                            }
                            .font(.custom("Poppins-Medium", size: 14))
                            .foregroundColor(isMuted ? Color(hex: "00A896") : .red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isMuted ? Color(hex: "00A896") : .red, lineWidth: 1)
                            )
                        }
                        .listRowBackground(LiistRowBackground())
                    }
                    .scrollContentBackground(.hidden)
                }
                
                Spacer()
            }
            .navigationTitle("Silenciar Usuario")
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
                    print("Error searching users: \(error)")
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
                    Text("Añadir palabra o frase")
                        .font(.custom("Poppins-SemiBold", size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("No verás contenido que contenga esta palabra o frase")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                    
                    TextField("Escribe una palabra o frase...", text: $newWord)
                        .font(.custom("Poppins-Regular", size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "00A896").opacity(0.3), lineWidth: 1)
                                )
                        )
                    
                    Button(action: {
                        if !newWord.trimmingCharacters(in: .whitespaces).isEmpty {
                            viewModel.addMutedWord(newWord.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        }
                    }) {
                        Text("Añadir")
                            .font(.custom("Poppins-SemiBold", size: 16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(newWord.isEmpty ? Color.gray : Color(hex: "00A896"))
                            )
                    }
                    .disabled(newWord.isEmpty)
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Palabra Silenciada")
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
}

class MuteSettingsViewModel: ObservableObject {
    @Published var mutedUsers: [AppUser] = []
    @Published var mutedWords: [String] = []
    @Published var muteNotifications = true
    @Published var hideFromSearch = true
    
    private let firestoreService = FirestoreService()
    
    func loadSettings(completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion()
            return
        }
        
        firestoreService.fetchUserProfile(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let user):
                    // Load mute settings from user data
                    // For now, using empty defaults
                    self?.mutedUsers = []
                    self?.mutedWords = []
                    self?.muteNotifications = true
                    self?.hideFromSearch = true
                case .failure(let error):
                    print("Error loading mute settings: \(error)")
                }
                completion()
            }
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
                print("Error saving mute settings: \(error)")
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
                colors: [Color(colorScheme == .dark ? .white : .black).opacity(0.1), Color(hex: "00A896").opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.overlay)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

