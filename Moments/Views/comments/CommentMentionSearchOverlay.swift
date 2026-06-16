import SwiftUI

struct CommentMentionSearchOverlay: View {
    let placeholder: String
    let query: String?
    let showsSearchField: Bool
    let onSelect: (AppUser) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [AppUser] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool

    private let firestoreService = FirestoreService()

    init(
        placeholder: String = NSLocalizedString("creator.tag.search", comment: ""),
        query: String? = nil,
        showsSearchField: Bool = true,
        onSelect: @escaping (AppUser) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        self.query = query
        self.showsSearchField = showsSearchField
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    private var shouldShowResultsPanel: Bool {
        isSearching || !(query ?? searchText).isEmpty
    }

    private var resultsPanelHeight: CGFloat {
        let rowHeight: CGFloat = 67
        let visibleRows = min(max(searchResults.count, 1), 3)
        return CGFloat(visibleRows) * rowHeight
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsSearchField {
                searchField
            } else {
                inlineHeader
            }

            if shouldShowResultsPanel {
                resultsPanel
            }
        }
        .onAppear {
            isSearchFocused = showsSearchField
            if let query {
                searchUsers(query: query)
            }
        }
        .onChange(of: query ?? "") { _, newValue in
            if !showsSearchField {
                searchUsers(query: newValue)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("", text: $searchText)
                .placeholder(when: searchText.isEmpty) {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: searchText) { _, newValue in
                    searchUsers(query: newValue)
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .momentsChromeGlass(in: Capsule(), interactive: true)
    }

    private var inlineHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "at")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)

            Text(query?.isEmpty == false ? "@\(query ?? "")" : placeholder)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .momentsChromeGlass(in: Circle(), interactive: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .momentsChromeGlass(in: Capsule(), interactive: true)
    }

    private var resultsPanel: some View {
        Group {
            if isSearching {
                ProgressView()
                    .tint(.primary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else if searchResults.isEmpty {
                Text(NSLocalizedString("common.noResults", value: "No users found", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults, id: \.id) { user in
                            Button(action: { onSelect(user) }) {
                                CommentMentionSearchRow(user: user)
                            }
                            .buttonStyle(.plain)

                            if user.id != searchResults.last?.id {
                                Divider().opacity(0.25)
                            }
                        }
                    }
                }
                .frame(height: resultsPanelHeight)
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func searchUsers(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        firestoreService.searchUsers(query: trimmedQuery, limit: 10) { result in
            DispatchQueue.main.async {
                isSearching = false
                if case .success(let users) = result {
                    searchResults = users
                }
            }
        }
    }
}

private struct CommentMentionSearchRow: View {
    let user: AppUser

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let profileUrl = user.profileImagePath, let url = URL(string: profileUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            Text(user.username)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .momentsChromeGlass(in: Circle(), interactive: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
