import SwiftUI
import FirebaseAuth

struct NovaMemoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = NovaMemoryViewModel()
    @State private var editingFact: NovaFact?
    @State private var editingText = ""

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
        .alert(
            Text(NSLocalizedString("nova.memory.edit.title", comment: "Edit memory title")),
            isPresented: Binding(
                get: { editingFact != nil },
                set: { isPresented in
                    if !isPresented {
                        editingFact = nil
                        editingText = ""
                    }
                }
            )
        ) {
            TextField(NSLocalizedString("nova.memory.edit.placeholder", comment: "Memory edit placeholder"), text: $editingText)

            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {
                editingFact = nil
                editingText = ""
            }

            Button(NSLocalizedString("nova.memory.edit.save", comment: "Save edited memory")) {
                if let editingFact {
                    viewModel.updateFact(editingFact, content: editingText)
                }
                editingFact = nil
                editingText = ""
            }
        } message: {
            Text(NSLocalizedString("nova.memory.edit.message", comment: "Edit memory message"))
        }
    }

    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                Text(NSLocalizedString("nova.memory.title", comment: "Nova's Memory"))
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(NovaColors.textPrimary)

                Text(NSLocalizedString("nova.memory.description", comment: "Manage what Nova knows about you"))
                    .font(.custom("Poppins-Regular", size: 13))
                    .foregroundColor(NovaColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 64)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(NovaColors.textPrimary)
                        .frame(width: 38, height: 38)
                        .background {
                            Color.clear
                                .momentsChromeGlass(in: Circle(), interactive: true)
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
                .tint(NovaColors.textPrimary)

            Text(NSLocalizedString("settings.loading", comment: "Loading..."))
                .font(.custom("Poppins-Medium", size: 14))
                .foregroundColor(NovaColors.textSecondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(NovaColors.textPrimary)
                .frame(width: 72, height: 72)
                .background {
                    Color.clear
                        .momentsChromeGlass(in: Circle())
                }

            VStack(spacing: 8) {
                Text(NSLocalizedString("nova.memory.empty", comment: "Nova doesn't remember anything yet"))
                    .font(.custom("Poppins-SemiBold", size: 18))
                    .foregroundColor(NovaColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("nova.memory.empty.subtitle", comment: "Talk to Nova to start building memory"))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(NovaColors.textSecondary)
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
                    let facts = viewModel.memory?.facts.filter { $0.type == type } ?? []
                    if !facts.isEmpty {
                        MemoryCategorySection(
                            type: type,
                            title: localizedCategoryName(type),
                            facts: facts,
                            onEdit: { fact in
                                editingFact = fact
                                editingText = fact.content
                            },
                            onToggleImportant: viewModel.toggleImportant,
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
                    .momentsChromeGlass(in: Capsule(), interactive: true)
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
    let onEdit: (NovaFact) -> Void
    let onToggleImportant: (NovaFact) -> Void
    let onDelete: (NovaFact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(NovaColors.textPrimary)
                    .frame(width: 28, height: 28)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle())
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.custom("Poppins-SemiBold", size: 15))
                        .foregroundColor(NovaColors.textPrimary)

                    Text("\(facts.count) \(facts.count == 1 ? localizedSingularItem : localizedPluralItem)")
                        .font(.custom("Poppins-Regular", size: 12))
                        .foregroundColor(NovaColors.textSecondary)
                }

                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    MemoryFactRow(fact: fact) {
                        onEdit(fact)
                    } onToggleImportant: {
                        onToggleImportant(fact)
                    } onDelete: {
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
        NSLocalizedString("nova.memory.item.singular", comment: "Memory item singular")
    }

    private var localizedPluralItem: String {
        NSLocalizedString("nova.memory.item.plural", comment: "Memory item plural")
    }
}

private struct MemoryFactRow: View {
    let fact: NovaFact
    let onEdit: () -> Void
    let onToggleImportant: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(fact.content)
                    .font(.custom("Poppins-Regular", size: 15))
                    .foregroundColor(NovaColors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if fact.importance >= 5 {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.yellow)
                    }

                    Text(fact.timestamp.timeAgoDisplay())
                        .font(.custom("Poppins-Regular", size: 11))
                        .foregroundColor(NovaColors.textTertiary)
                }
            }

            Spacer()

            Menu {
                Button(action: onEdit) {
                    Label(NSLocalizedString("nova.memory.edit.action", comment: "Edit memory action"), systemImage: "pencil")
                }

                Button(action: onToggleImportant) {
                    Label(
                        NSLocalizedString(
                            fact.importance >= 5 ? "nova.memory.unmarkImportant" : "nova.memory.markImportant",
                            comment: "Toggle important memory action"
                        ),
                        systemImage: fact.importance >= 5 ? "star.slash" : "star"
                    )
                }

                Button(role: .destructive, action: onDelete) {
                    Label(NSLocalizedString("common.delete", comment: "Delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NovaColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background {
                        Color.clear
                            .momentsChromeGlass(in: Circle(), interactive: true)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
    }
}

@MainActor
final class NovaMemoryViewModel: ObservableObject {
    @Published var memory: NovaMemory?
    @Published var isLoading = false
    @Published var showClearAllAlert = false

    private let store = NovaMemoryStore.shared
    private let contextStore = NovaContextStore.shared
    private let userId: String? = Auth.auth().currentUser?.uid

    func load() {
        guard let userId = userId else { return }
        isLoading = true
        Task {
            let loaded = await store.loadMemory(userId: userId)
            await MainActor.run {
                self.isLoading = false
                self.memory = loaded
            }
        }
    }

    func deleteFact(_ fact: NovaFact) {
        guard let memory = memory, userId != nil else { return }
        let updatedMemory = memory.removingFact(withId: fact.id)

        self.memory = updatedMemory

        persist(updatedMemory)
    }

    func updateFact(_ fact: NovaFact, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let memory = memory else { return }
        save(memory.updatingFact(withId: fact.id, content: trimmed))
    }

    func toggleImportant(_ fact: NovaFact) {
        guard let memory = memory else { return }
        let newImportance = fact.importance >= 5 ? max(3, fact.type.priority) : 5
        save(memory.updatingFact(withId: fact.id, importance: newImportance))
    }

    private func save(_ updatedMemory: NovaMemory) {
        guard userId != nil else { return }
        self.memory = updatedMemory

        persist(updatedMemory)
    }

    func clearAllMemory() {
        guard let userId = userId else { return }
        isLoading = true
        let cleared = NovaMemory(userId: userId).clearingFacts()
        Task {
            do {
                try await store.saveMemory(cleared)
                try await contextStore.clearContext(userId: userId)
                self.memory = cleared
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.load()
            }
        }
    }

    private func persist(_ memory: NovaMemory) {
        Task {
            do {
                try await store.saveMemory(memory)
            } catch {
                self.load()
            }
        }
    }
}
