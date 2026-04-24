import SwiftUI
import FirebaseAuth

struct NovaMemoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = NovaMemoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.memory?.facts.isEmpty ?? true {
                    emptyStateView
                } else {
                    memoryContentView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.load()
        }
        .alert(Text(NSLocalizedString("nova.memory.clearAll.confirm", comment: "Are you sure?")), isPresented: $viewModel.showClearAllAlert) {
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                viewModel.clearAllMemory()
            }
        } message: {
            Text(NSLocalizedString("nova.memory.clearAll.message", comment: "This cannot be undone."))
        }
    }

    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(NSLocalizedString("nova.memory.title", comment: "Nova's Memory"))
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(ModernGeminiColors.textPrimary)

                Text(NSLocalizedString("nova.memory.description", comment: "Manage what Nova knows about you"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(ModernGeminiColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 64)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ModernGeminiColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background {
                            Color.clear
                                .liquidGlass(in: Circle(), interactive: true)
                        }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(ModernGeminiColors.textPrimary)

            Text(NSLocalizedString("settings.loading", comment: "Loading..."))
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(ModernGeminiColors.textSecondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(ModernGeminiColors.textPrimary)
                .frame(width: 72, height: 72)
                .background {
                    Color.clear
                        .liquidGlass(in: Circle())
                }

            VStack(spacing: 8) {
                Text(NSLocalizedString("nova.memory.empty", comment: "Nova doesn't remember anything yet"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("nova.memory.empty.subtitle", comment: "Talk to Nova to start building memory"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(ModernGeminiColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var memoryContentView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(NovaFactType.allCases, id: \.self) { type in
                    let facts = viewModel.memory?.facts(ofType: type) ?? []
                    if !facts.isEmpty {
                        MemoryCategorySection(
                            type: type,
                            title: localizedCategoryName(type),
                            facts: facts,
                            onDelete: viewModel.deleteFact
                        )
                    }
                }

                clearAllButton
                    .padding(.top, 4)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }

    private var clearAllButton: some View {
        Button(role: .destructive) {
            viewModel.showClearAllAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))

                Text(NSLocalizedString("nova.memory.clearAll", comment: "Clear all memory"))
                    .font(.custom("Poppins-Medium", size: 15))
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                Color.clear
                    .liquidGlass(in: Capsule(), interactive: true)
            }
        }
    }

    private func localizedCategoryName(_ type: NovaFactType) -> String {
        switch type {
        case .preference:
            return NSLocalizedString("nova.memory.section.preference", comment: "Memory category preferences")
        case .personal:
            return NSLocalizedString("nova.memory.section.personal", comment: "Memory category personal")
        case .professional:
            return NSLocalizedString("nova.memory.section.professional", comment: "Memory category work and studies")
        case .interest:
            return NSLocalizedString("nova.memory.section.interest", comment: "Memory category interests")
        case .general:
            return NSLocalizedString("nova.memory.section.general", comment: "Memory category general")
        }
    }
}

private struct MemoryCategorySection: View {
    let type: NovaFactType
    let title: String
    let facts: [NovaFact]
    let onDelete: (NovaFact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .frame(width: 28, height: 28)
                    .background {
                        Color.clear
                            .liquidGlass(in: Circle())
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(ModernGeminiColors.textPrimary)

                    Text("\(facts.count) \(facts.count == 1 ? localizedSingularItem : localizedPluralItem)")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(ModernGeminiColors.textSecondary)
                }

                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    MemoryFactRow(fact: fact) {
                        onDelete(fact)
                    }

                    if index < facts.count - 1 {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 2)
                    }
                }
            }
        }
    }

    private var iconName: String {
        switch type {
        case .preference: return "slider.horizontal.3"
        case .personal: return "person.crop.circle"
        case .professional: return "briefcase"
        case .interest: return "sparkles"
        case .general: return "text.bubble"
        }
    }

    private var localizedSingularItem: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch lang {
        case .es: return "detalle"
        case .en: return "detail"
        case .ca: return "detall"
        }
    }

    private var localizedPluralItem: String {
        let lang = NovaLanguageService.getPreferredLanguage() ?? .es
        switch lang {
        case .es: return "detalles"
        case .en: return "details"
        case .ca: return "detalls"
        }
    }
}

private struct MemoryFactRow: View {
    let fact: NovaFact
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(fact.content)
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(ModernGeminiColors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(fact.timestamp.timeAgoDisplay())
                    .font(.custom("Poppins-Regular", size: 11))
                    .foregroundColor(ModernGeminiColors.textTertiary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
                    .frame(width: 34, height: 34)
                    .background {
                        Color.clear
                            .liquidGlass(in: Circle(), interactive: true)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
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

        self.memory = updatedMemory

        memoryService.saveMemory(updatedMemory) { result in
            if case .failure = result {
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
