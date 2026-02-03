import SwiftUI
import FirebaseAuth

struct NovaMemoryManagementView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = NovaMemoryViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fondo moderno consistente con Gemini
                ModernGeminiBackground()
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack {
                        ProgressView()
                            .tint(ModernGeminiColors.primary)
                        Text(NSLocalizedString("settings.loading", comment: "Loading..."))
                            .font(.custom("Poppins-Medium", size: 14))
                            .padding(.top, 8)
                    }
                } else if viewModel.memory?.facts.isEmpty ?? true {
                    VStack(spacing: 20) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(ModernGeminiColors.textTertiary)
                        
                        Text(NSLocalizedString("nova.memory.empty", comment: "Nova doesn't remember anything yet"))
                            .font(.custom("Poppins-SemiBold", size: 18))
                            .multilineTextAlignment(.center)
                        
                        Text(NSLocalizedString("nova.memory.empty.subtitle", comment: "Talk to Nova to start building memory"))
                            .font(.custom("Poppins-Regular", size: 14))
                            .foregroundColor(ModernGeminiColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(NovaFactType.allCases, id: \.self) { type in
                            let facts = viewModel.memory?.facts(ofType: type) ?? []
                            if !facts.isEmpty {
                                Section(header: 
                                    HStack {
                                        Text(type.emoji)
                                        Text(localizedCategoryName(type))
                                            .font(.custom("Poppins-Bold", size: 14))
                                    }
                                    .foregroundColor(ModernGeminiColors.primary)
                                ) {
                                    ForEach(facts) { fact in
                                        MemoryFactRow(fact: fact) {
                                            viewModel.deleteFact(fact)
                                        }
                                    }
                                }
                                .listRowBackground(ModernGeminiColors.cardBackground)
                            }
                        }
                        
                        Section {
                            Button(role: .destructive) {
                                viewModel.showClearAllAlert = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text(NSLocalizedString("nova.memory.clearAll", comment: "Clear all memory"))
                                        .font(.custom("Poppins-Medium", size: 16))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .listRowBackground(Color.red.opacity(0.1))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(NSLocalizedString("nova.memory.title", comment: "Nova's Memory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ModernGeminiColors.textSecondary)
                    }
                }
            })
            .alert(Text(NSLocalizedString("nova.memory.clearAll.confirm", comment: "Are you sure?")), isPresented: $viewModel.showClearAllAlert) {
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                    viewModel.clearAllMemory()
                }
            } message: {
                Text(NSLocalizedString("nova.memory.clearAll.message", comment: "This cannot be undone."))
            }
            .onAppear {
                viewModel.load()
            }
        }
    }
    
    private func localizedCategoryName(_ type: NovaFactType) -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch (type, lang) {
        case (.preference, .es): return "Preferencias"
        case (.preference, .en): return "Preferences"
        case (.preference, .ca): return "Preferències"
        case (.personal, .es): return "Personal"
        case (.personal, .en): return "Personal"
        case (.personal, .ca): return "Personal"
        case (.professional, .es): return "Profesional"
        case (.professional, .en): return "Professional"
        case (.professional, .ca): return "Professional"
        case (.interest, .es): return "Intereses"
        case (.interest, .en): return "Interests"
        case (.interest, .ca): return "Interessos"
        case (.general, .es): return "General"
        case (.general, .en): return "General"
        case (.general, .ca): return "General"
        }
    }
}

struct MemoryFactRow: View {
    let fact: NovaFact
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.content)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                
                Text(fact.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(ModernGeminiColors.textTertiary)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

class NovaMemoryViewModel: ObservableObject {
    @Published var memory: NovaMemory?
    @Published var isLoading = false
    @Published var showClearAllAlert = false
    
    private let memoryService = NovaMemoryService()
    private let userId: String? = Auth.auth().currentUser?.uid
    
    func load() {
        guard let userId = userId else { return }
        isLoading = true
        memoryService.loadMemory(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                if case .success(let memory) = result {
                    self?.memory = memory
                }
            }
        }
    }
    
    func deleteFact(_ fact: NovaFact) {
        guard let memory = memory, let userId = userId else { return }
        let updatedMemory = memory.removingFact(withId: fact.id)
        
        // Optimistic update
        self.memory = updatedMemory
        
        memoryService.saveMemory(updatedMemory) { result in
            if case .failure = result {
                // Rollback if failed
                self.load()
            }
        }
    }
    
    func clearAllMemory() {
        guard let userId = userId else { return }
        isLoading = true
        memoryService.clearMemory(for: userId) { [weak self] (result: Result<Void, Error>) in
            DispatchQueue.main.async {
                self?.isLoading = false
                if case .success = result {
                    self?.memory = NovaMemory(userId: userId)
                }
            }
        }
    }
}
