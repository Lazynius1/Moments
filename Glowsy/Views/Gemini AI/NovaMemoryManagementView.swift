import SwiftUI
import FirebaseAuth

struct NovaMemoryManagementView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = NovaMemoryViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0B1215") : Color(hex: "FAF9F6"))
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
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(NovaFactType.allCases, id: \.self) { type in
                                let facts = viewModel.memory?.facts(ofType: type) ?? []
                                if !facts.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(type.emoji)
                                            Text(localizedCategoryName(type))
                                                .font(.custom("Poppins-Bold", size: 14))
                                        }
                                        .foregroundColor(ModernGeminiColors.primary)

                                        VStack(spacing: 0) {
                                            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                                                MemoryFactRow(fact: fact) {
                                                    viewModel.deleteFact(fact)
                                                }

                                                if index < facts.count - 1 {
                                                    Divider()
                                                        .padding(.leading, 4)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

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
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(localizedTitle())
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
    
    private func localizedTitle() -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch lang {
        case .es: return "Matices de tu Esencia"
        case .en: return "Nuances of your Essence"
        case .ca: return "Matisos de la teva Essència"
        }
    }

    private func localizedCategoryName(_ type: NovaFactType) -> String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch (type, lang) {
        case (.preference, .es): return "Vibras de Comunicación"
        case (.preference, .en): return "Communication Vibes"
        case (.preference, .ca): return "Vibres de Comunicació"
        case (.personal, .es): return "Tu Esencia"
        case (.personal, .en): return "Your Essence"
        case (.personal, .ca): return "La teva Essència"
        case (.professional, .es): return "Tu Camino"
        case (.professional, .en): return "Your Path"
        case (.professional, .ca): return "El teu Camí"
        case (.interest, .es): return "Lo que te hace vibrar"
        case (.interest, .en): return "What makes you glow"
        case (.interest, .ca): return "El que et fa vibrar"
        case (.general, .es): return "Destellos"
        case (.general, .en): return "Sparkles"
        case (.general, .ca): return "Espurnes"
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
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(categoryColor(fact.type).opacity(0.8))
                        .frame(width: 6, height: 6)
                    
                    Text(fact.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(ModernGeminiColors.textTertiary)
                }
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
    
    private func categoryColor(_ type: NovaFactType) -> Color {
        switch type {
        case .preference: return .blue
        case .personal: return .purple
        case .professional: return .orange
        case .interest: return .red
        case .general: return .gray
        }
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
